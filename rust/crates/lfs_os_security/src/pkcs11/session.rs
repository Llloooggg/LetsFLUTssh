//! Per-(module, slot) PKCS#11 session pool.
//!
//! Most production tokens (Yubico PIV, JaCarta, Рутокен, eToken)
//! handle parallel sign requests against a single session correctly
//! once `CKF_OS_LOCKING_OK` is set. Some older Рутокен firmwares
//! crash inside `C_Sign` on parallel calls anyway; we keep the
//! belt-and-braces per-session `Mutex` so the contract is "one
//! `C_Sign` at a time per slot, regardless of vendor".
//!
//! Sessions are kept warm for up to 5 minutes of idle. After that
//! the implicit-logout drop clears the PIN context; the next sign
//! request re-prompts.

#![cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use cryptoki::session::{Session as CkSession, UserType};
use cryptoki::slot::Slot;
use cryptoki::types::AuthPin;
use zeroize::Zeroizing;

use super::error::Error;
use super::module::Module;

/// 5-minute idle threshold per plan. Matches the documented PIN
/// caching behaviour of `pkcs11-tool` and `ssh-agent -t 300`.
pub const IDLE_TIMEOUT: Duration = Duration::from_secs(300);

/// Cache entry — a logged-in (or anonymous, when the token does not
/// require login) PKCS#11 session held under a `Mutex` so concurrent
/// sign requests serialize per slot. The `Arc<Mutex<Inner>>` shape
/// matches the agent-endpoint pattern — sign requests come in
/// concurrently from the FRB worker pool, and we hand each one
/// exclusive access for the duration of the `C_Sign` call.
pub struct Session {
    pub module: Module,
    pub slot: Slot,
    inner: Arc<Mutex<Inner>>,
}

struct Inner {
    /// Live cryptoki session — `None` when the idle drop wiped it.
    ck_session: Option<CkSession>,
    last_used: Instant,
}

impl Session {
    /// Lock the underlying session for one signing operation.
    /// Re-opens + re-logs-in (with the cached PIN, when provided) if
    /// the session was dropped by the idle sweep. PIN is borrowed
    /// for the duration of the call only — never persisted.
    ///
    /// `pin` may be `None` either because the token uses a protected
    /// authentication path (PIN-pad on device) or because login is
    /// not required at all.
    pub fn with_session<R>(
        &self,
        pin: Option<&str>,
        f: impl FnOnce(&CkSession) -> Result<R, Error>,
    ) -> Result<R, Error> {
        let mut guard = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        if guard.ck_session.is_none() || guard.last_used.elapsed() > IDLE_TIMEOUT {
            guard.ck_session = None;
            let s = self
                .module
                .pkcs11()
                .open_rw_session(self.slot)
                .map_err(Error::from)?;
            if let Some(pin_text) = pin {
                let pin_secret = Zeroizing::new(pin_text.to_string());
                // `AuthPin::new` takes `Box<str>`; the secrecy crate
                // owns the wrap from here on (zeroizes on drop).
                let pin_auth = AuthPin::new(pin_secret.as_str().to_string().into_boxed_str());
                login_and_classify(self, &s, &pin_auth)?;
            } else if needs_login(self) {
                // Protected-auth-path token — request login with no PIN
                // string; Cryptoki will block until the user pushes the
                // physical button.
                let auth = AuthPin::new(String::new().into_boxed_str());
                match s.login(UserType::User, Some(&auth)) {
                    Ok(()) => {}
                    Err(e) => return Err(map_login_error(self, e)),
                }
            }
            guard.ck_session = Some(s);
        }
        let session_ref = guard
            .ck_session
            .as_ref()
            .ok_or_else(|| Error::Other("session lost mid-call".into()))?;
        let r = f(session_ref);
        guard.last_used = Instant::now();
        r
    }

    /// Drop the cryptoki session immediately. Used by the explicit
    /// teardown path (logout after the import dialog closes) and by
    /// the idle sweeper.
    pub fn forget_session(&self) {
        let mut guard = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        guard.ck_session = None;
    }
}

/// Type alias for the global session pool's inner map. Carries
/// `Mutex<HashMap<(module-content-key, slot-id), Arc<Session>>>` —
/// clippy flags the inline shape as overly complex.
type SessionPoolInner = Mutex<HashMap<(super::module::ModuleKey, u64), Arc<Session>>>;

fn pool() -> &'static SessionPoolInner {
    static POOL: OnceLock<SessionPoolInner> = OnceLock::new();
    POOL.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Look up (or create) the cached session for `(module, slot)`.
/// First call opens a R/W session — login is deferred to the first
/// signing call so the listing path can run anonymously when the
/// token allows it.
pub fn for_slot(module: &Module, slot: Slot) -> Arc<Session> {
    let key = (module.key.clone(), slot.id());
    let mut map = pool().lock().unwrap_or_else(|e| e.into_inner());
    map.entry(key)
        .or_insert_with(|| {
            Arc::new(Session {
                module: module.clone(),
                slot,
                inner: Arc::new(Mutex::new(Inner {
                    ck_session: None,
                    last_used: Instant::now(),
                })),
            })
        })
        .clone()
}

fn needs_login(session: &Session) -> bool {
    session
        .module
        .pkcs11()
        .get_token_info(session.slot)
        .map(|t| t.login_required())
        .unwrap_or(false)
}

/// Try login; on `PinIncorrect`, refresh the token-info pin counter
/// so the surfaced error carries the remaining-tries hint.
fn login_and_classify(session: &Session, ck: &CkSession, pin: &AuthPin) -> Result<(), Error> {
    match ck.login(UserType::User, Some(pin)) {
        Ok(()) => Ok(()),
        Err(e) => Err(map_login_error(session, e)),
    }
}

fn map_login_error(session: &Session, e: cryptoki::error::Error) -> Error {
    let token_info = session.module.pkcs11().get_token_info(session.slot).ok();
    match (e, token_info) {
        (cryptoki::error::Error::Pkcs11(cryptoki::error::RvError::PinIncorrect, _), Some(info)) => {
            Error::WrongPin {
                remaining_tries: if info.user_pin_final_try() {
                    Some(1)
                } else if info.user_pin_count_low() {
                    // PKCS#11 spec exposes "count low" as a boolean
                    // hint — the exact remaining-tries integer is not in
                    // the standard surface. Surface 2 as a conservative
                    // floor (final_try is 1, count_low is "more than
                    // one but few", so 2 is the canonical value vendors
                    // mean by "count_low").
                    Some(2)
                } else {
                    None
                },
            }
        }
        (cryptoki::error::Error::Pkcs11(cryptoki::error::RvError::PinLocked, _), _) => {
            Error::PinLocked
        }
        (other, _) => Error::from(other),
    }
}

/// Walk every cached entry and drop sessions whose `last_used` is
/// older than the idle threshold. Idempotent — call from a periodic
/// task or skip entirely (sessions self-recycle on the next
/// `with_session` call).
pub fn sweep_idle() {
    let mut map = pool().lock().unwrap_or_else(|e| e.into_inner());
    for entry in map.values_mut() {
        let mut inner = entry.inner.lock().unwrap_or_else(|e| e.into_inner());
        if inner.last_used.elapsed() > IDLE_TIMEOUT {
            inner.ck_session = None;
        }
    }
}
