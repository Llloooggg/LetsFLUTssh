//! Per-tier unlock orchestrators that drive the
//! [`crate::security::tier_machine`] state machine through the
//! cascade `Locked → Unlocking → Unlocked`. Every tier is
//! implemented here — Plaintext, Keychain (T1), Keychain+password
//! (T1+pw), Hardware (T2), Paranoid — and the Dart
//! `SecurityInitController` delegates each tier's unlock to the
//! matching FRB entry point rather than computing the cascade
//! Dart-side; it is left coordinating UI and feeding the staged
//! key to drift.
//!
//! The DB-open step itself (drift opens `letsflutssh.db` with
//! the resolved master key) stays Dart-side because drift is a
//! Dart ORM and can't be driven from Rust. The orchestrator's
//! contract is therefore "resolve the master key, stage it in
//! the SecretStore under a canonical id, advance the tier
//! machine, return the SecretStore id". The Dart subscriber
//! reads the staged key from the SecretStore once and feeds it
//! to drift.
//!
//! Plaintext takes no secret; T1/T1+pw compose with the OS
//! keychain / biometric stack via
//! [`lfs_os_security::secure_key_storage`] +
//! [`lfs_os_security::biometric_auth`]; T2 drives the Rust-side
//! prompt registries (`hardware_vault_unlock_prompt`,
//! `hardware_vault_seal_prompt`) — the orchestrator registers a
//! prompt and publishes a bus request, and the Dart side renders
//! the platform-bound surface (Hello PIN sub-dialog, Touch ID
//! prompt) and resolves it back over FRB.

use crate::bus::Event;
use crate::security::hardware_vault_seal_prompt;
use crate::security::hardware_vault_unlock_prompt;
use crate::security::tier_machine::{instance_dispatch, TierEvent, UnlockFailureReason};
use crate::security::SecurityTier;

/// Canonical SecretStore id the per-tier orchestrators stage
/// the resolved DB key under just before emitting
/// `UnlockSucceeded`. Re-exports the global
/// `ACTIVE_DBKEY_SECRET_ID` constant so the orchestrator stages
/// directly into the running session's active slot — the Dart
/// listener routes `db_init_from_secret(ACTIVE)` without an
/// intermediate take + re-stage hop, and downstream consumers
/// (recorder HKDF, biometric vault store) read from the same
/// slot through their own SecretRef-aware FRB shims.
///
/// Plaintext stages an empty buffer; the listener's plaintext
/// branch sees `secrets_get` return empty and routes through the
/// unencrypted `db_init` path.
pub const TIER_UNLOCK_KEY_ID: &str = crate::secrets::ACTIVE_DBKEY_SECRET_ID;

/// Result of a per-tier unlock attempt. The bytes never cross
/// FRB — `Staged` means the key sits in the SecretStore under
/// [`TIER_UNLOCK_KEY_ID`] and the Dart [`TierUnlockedListener`]
/// (subscribed to `BusTopic::Tier`) will take them via
/// `secrets_take` on the same `TierStateChanged.unlocked` event
/// the orchestrator just emitted.
///
/// The dialog tiers (T1+pw/T2/Paranoid) interpret the variants for
/// their UI:
///   - `Staged` → close the dialog, the listener owns the rest.
///   - `WrongSecret` → keep the dialog open, surface the
///     wrong-password label, decrement the rate-limiter.
///   - `Cancelled` → user dismissed an inner prompt (hardware
///     vault PIN sub-dialog); the outer dialog stays open.
///   - `PluginError` → unrecoverable plugin/hardware failure;
///     close + fall back to plaintext.
///   - `Corruption` → on-disk KDF/gate state unreadable; close
///     + route through corruption recovery.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UnlockOutcome {
    Staged,
    WrongSecret,
    Cancelled,
    PluginError(String),
    Corruption(String),
}

/// Stage the resolved key in the SecretStore under the
/// canonical id so the Dart bus listener can take it. Called
/// just before `UnlockSucceeded` dispatches; the listener's
/// `secrets_take` runs on the bus event handler.
fn stage_key(bytes: &[u8]) {
    crate::app::instance()
        .secrets
        .put(TIER_UNLOCK_KEY_ID, bytes);
}

/// Run the Rust-side half of the post-unlock cascade after the
/// per-tier orchestrator successfully staged the DB key + fired
/// `UnlockSucceeded`. Three responsibilities, in order:
///
/// 1. Open the rusqlite handle keyed off the staged bytes
///    (empty bytes ⇒ plaintext open). Failure is logged and the
///    cascade continues — recovery routes through the Dart-side
///    `verifyRustDbReadable` probe + `DbCorruptDialog`.
/// 2. Persist the resolved tier into `config.json` via the
///    config_store partial-update. Idempotent on a matching
///    `(tier, modifiers)` pair. Failure is logged + continues —
///    the in-memory state machine still reflects the unlocked
///    tier; the persistence is best-effort.
/// 3. Publish [`Event::UnlockCascadeReady`] on the `Tier` topic
///    so the Dart `TierUnlockedListener` runs its Riverpod half
///    (cache invalidations + `securityStateProvider` flip) off
///    a single payload.
///
/// Posture: log + continue on partial failures. One stuck step
/// must not block the chain; the Dart side's recovery rails
/// still trip on a broken DB / config write.
fn run_post_unlock_cascade(tier: crate::security::SecurityTier) {
    let app = crate::app::instance();
    let tier_wire = tier.wire_name().to_string();

    // Probe presence of the canonical active-DB-key slot. Mirrors
    // the previous Dart `rust_app.secretsHas(kActiveDbKeySecretId)`
    // probe; the orchestrator's `stage_key` always populates the
    // slot (with an empty buffer on plaintext) so this is true on
    // every successful unlock path.
    let has_key = app.secrets.has(TIER_UNLOCK_KEY_ID);

    // 1. Open the rusqlite handle. Empty bytes (plaintext path)
    //    yield an unencrypted open; non-empty bytes feed SQLCipher.
    let path = match app.support_dir() {
        Ok(p) => p.join(crate::db::DB_FILE_NAME),
        Err(e) => {
            crate::app_log_warn!(
                "TierUnlock",
                "post-unlock cascade: support_dir unavailable: {e}"
            );
            // Without a support_dir we can't open the DB; the
            // event still publishes so Dart Riverpod runs and the
            // probe-based recovery rail trips on the missing DB.
            app.bus
                .publish(Event::UnlockCascadeReady { tier_wire, has_key });
            return;
        }
    };
    let key_bytes = app.secrets.get(TIER_UNLOCK_KEY_ID);
    let key_slice: &[u8] = match key_bytes.as_deref() {
        Some(slice) => slice,
        None => &[],
    };
    if let Err(e) = app.db_init(&path, key_slice) {
        crate::app_log_warn!("TierUnlock", "post-unlock cascade: db_init failed: {e}");
    }

    // 2. Persist the tier. `Err` only when config_store hasn't been
    //    initialised yet — production cold-start invariant guards
    //    against that, so a hit here is a real bug worth logging.
    if let Err(e) = crate::config_store::instance().update_security_tier(tier) {
        crate::app_log_warn!(
            "TierUnlock",
            "post-unlock cascade: update_security_tier failed: {e}"
        );
    }

    // 3. Re-publish the Rust-owned store-changed events. The DB
    //    handle just flipped from "closed / wrong-key" to "readable
    //    under the freshly-staged key"; every Dart-side store stream
    //    (sessions, ssh_keys, known_hosts) is subscribed to its
    //    topic via `AppBus.subscribe` and re-fetches on each event.
    //    Without this republish the streams keep the snapshot they
    //    captured pre-unlock (typically empty), and the sidebar /
    //    key manager / Settings panels would render blank until the
    //    user mutates something.
    app.bus.publish(Event::SessionsChanged);
    app.bus.publish(Event::KeysChanged);
    app.bus.publish(Event::KnownHostsChanged);

    // 4. Publish the cascade-ready event AFTER both side-effects
    //    have settled (success or logged failure). Subscribers
    //    react to a single payload carrying `(tier_wire, has_key)`
    //    instead of round-tripping through the tier-machine +
    //    secrets-probe FRB surfaces.
    app.bus
        .publish(Event::UnlockCascadeReady { tier_wire, has_key });
}

/// Storage key for the T1 / T1+pw DB encryption key in the OS
/// keychain. Mirrors the Dart-era
/// `SecureKeyStorage._keyName` const — both implementations
/// must agree on the slot or an existing install would lose
/// access to its encrypted DB after the unlock cascade flips
/// to the orchestrator.
const ENCRYPTION_KEY_SLOT: &str = "letsflutssh_encryption_key";

/// Stable rate-limiter ids for the Rust-side gates wired into
/// [`unlock_keychain_with_password`] and [`unlock_paranoid`]. Stored
/// in the process-singleton `app::instance().rate_limiters`
/// registry; survive the lifetime of the process and reset on
/// `record_success` (correct password lands).
const KEYCHAIN_PW_UNLOCK_LIMITER_ID: &str = "tier_unlock.keychain_with_password";
const PARANOID_UNLOCK_LIMITER_ID: &str = "tier_unlock.paranoid";
const HARDWARE_UNLOCK_LIMITER_ID: &str = "tier_unlock.hardware";

/// Plaintext tier — no secret, no plugin call, no user prompt.
/// Idempotent: re-entry while already `Unlocked` is a no-op
/// because both dispatches are state-guarded.
///
/// 1. Set the active tier to Plaintext + dispatch
///    `UnlockRequested` (state goes to `Unlocking`).
/// 2. Dispatch `UnlockSucceeded` (state goes to `Unlocked`,
///    publishes `BusEvent::TierStateChanged { wire_name:
///    "unlocked" }`).
///
/// The Dart subscriber sees the Unlocked event and runs the
/// drift-open step with an empty key (`AppDatabase` opens the
/// file as plaintext).
pub fn unlock_plaintext() {
    instance_dispatch(SecurityTier::Plaintext, &TierEvent::UnlockRequested);
    // Stage an empty buffer so the Dart `TierUnlockedListener`
    // sees the same "take the staged key, hand it to drift"
    // shape across every tier — drift opens with empty bytes
    // for the plaintext path.
    stage_key(&[]);
    instance_dispatch(SecurityTier::Plaintext, &TierEvent::UnlockSucceeded);
    run_post_unlock_cascade(SecurityTier::Plaintext);
}

/// Keychain tier (T1) — read the DB encryption key directly from
/// the OS keychain via [`lfs_os_security::secure_key_storage`],
/// stage it under [`TIER_UNLOCK_KEY_ID`], dispatch the cascade.
///
/// 1. Set tier to Keychain + dispatch `UnlockRequested`.
/// 2. Call `secure_key_storage::read(ENCRYPTION_KEY_SLOT)` —
///    cfg-dispatched per platform (libsecret on Linux, SecItem on
///    Apple, CredRead on Windows, AndroidKeyStore JNI on Android).
/// 3. On a hit, stage the bytes + dispatch `UnlockSucceeded`;
///    on miss / backend error, dispatch
///    `UnlockFailed { PluginUnavailable }`.
///
/// Plaintext discipline: the key bytes never cross FRB on the
/// return value — the Dart [`TierUnlockedListener`] takes them
/// out of the SecretStore on its `unlocked` handler. The
/// caller branches on the [`UnlockOutcome`] discriminant only.
pub async fn unlock_keychain() -> UnlockOutcome {
    instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockRequested);

    let read_outcome = lfs_os_security::secure_key_storage::read(ENCRYPTION_KEY_SLOT).await;

    match read_outcome {
        Ok(Some(bytes)) if !bytes.is_empty() => {
            stage_key(&bytes);
            instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockSucceeded);
            run_post_unlock_cascade(SecurityTier::Keychain);
            UnlockOutcome::Staged
        }
        Ok(_) => {
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: "missing_keychain_entry".into(),
                    },
                },
            );
            UnlockOutcome::PluginError("missing_keychain_entry".into())
        }
        Err(e) => {
            let code = format!("keychain_read_failed: {e}");
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable { code: code.clone() },
                },
            );
            UnlockOutcome::PluginError(code)
        }
    }
}

/// KeychainWithPassword tier (T1+pw) — verify the typed user
/// password through the on-disk gate (HMAC-SHA-256 against the
/// stored salt + the keychain pepper), then on success read
/// the DB encryption key from the OS keychain and return its
/// bytes. Dispatches the cascade events along the way; emits
/// `UnlockFailed { WrongSecret }` on gate-mismatch and
/// `UnlockFailed { PluginUnavailable }` on missing keychain
/// entry.
///
/// The Dart caller owns the unlock dialog UI (rate-limit
/// countdown, biometric option, "forgot password" reset);
/// after the user submits the password the caller invokes this
/// orchestrator to drive the verify + key-read + cascade
/// emission in one FRB hop.
///
/// Reads the support dir from the pinned singleton — caller
/// must have invoked `config_store_init` at app startup
/// (the T1+pw gate shares the same support-dir pin since both
/// store on-disk state under the same root).
pub async fn unlock_keychain_with_password(password: Vec<u8>) -> UnlockOutcome {
    instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockRequested);

    // Rate-limit gate. The Dart unlock dialog's countdown was the
    // only brake on this verify path — a programmatic FRB caller
    // could fire `unlock_keychain_with_password` in a tight loop
    // and brute-force the T1+pw gate password (4-12 chars typical) at
    // wall-clock speed. The InMemoryRateLimiter applies the same
    // exponential schedule (1, 5, 15, 30, 60s cap) the Dart-side
    // limiter used. The persisted variant lives on disk and is
    // owned by the T1+pw gate; the in-memory mirror here is the
    // boundary-level gate that catches direct callers.
    let limiters = &crate::app::instance().rate_limiters;
    let l2_status = limiters.status(KEYCHAIN_PW_UNLOCK_LIMITER_ID);
    if l2_status.is_locked() {
        instance_dispatch(
            SecurityTier::Keychain,
            &TierEvent::UnlockFailed {
                reason: UnlockFailureReason::WrongSecret,
            },
        );
        return UnlockOutcome::WrongSecret;
    }

    let support_dir = crate::security::master_password::pinned_support_dir();
    let verify_result =
        crate::security::keychain_password_gate_actor::verify_password(support_dir, &password)
            .await;

    let verified = match verify_result {
        Ok(b) => b,
        Err(detail) => {
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::Corruption {
                        detail: detail.clone(),
                    },
                },
            );
            return UnlockOutcome::Corruption(detail);
        }
    };

    if !verified {
        limiters.record_failure(KEYCHAIN_PW_UNLOCK_LIMITER_ID);
        instance_dispatch(
            SecurityTier::Keychain,
            &TierEvent::UnlockFailed {
                reason: UnlockFailureReason::WrongSecret,
            },
        );
        return UnlockOutcome::WrongSecret;
    }
    limiters.record_success(KEYCHAIN_PW_UNLOCK_LIMITER_ID);

    // Password verified — read the DB encryption key directly
    // from the OS keychain.
    match lfs_os_security::secure_key_storage::read(ENCRYPTION_KEY_SLOT).await {
        Ok(Some(bytes)) if !bytes.is_empty() => {
            stage_key(&bytes);
            instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockSucceeded);
            run_post_unlock_cascade(SecurityTier::Keychain);
            UnlockOutcome::Staged
        }
        Ok(_) => {
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: "missing_keychain_entry_after_verify".into(),
                    },
                },
            );
            UnlockOutcome::PluginError("missing_keychain_entry_after_verify".into())
        }
        Err(e) => {
            let code = format!("keychain_read_failed: {e}");
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable { code: code.clone() },
                },
            );
            UnlockOutcome::PluginError(code)
        }
    }
}

/// Paranoid tier — derive the DB key from the typed master
/// password via Argon2id; dispatch the cascade events along
/// the way; return the key bytes on success or `None` on a
/// wrong password / corrupted KDF record.
///
/// The Dart caller owns the unlock dialog UI (rate-limit
/// countdown, "forgot password" reset path, biometric option
/// where applicable); after the user submits the password the
/// caller invokes this orchestrator to drive the verify +
/// cascade emission in one FRB hop.
///
/// `support_dir` is read from the pinned singleton inside the
/// `master_password` layer (pinned at `config_store_init` time).
/// `password` crosses FRB once on the way in; the key bytes
/// cross once on the way out for the Dart caller to hand to
/// drift.
pub async fn unlock_paranoid(password: Vec<u8>) -> UnlockOutcome {
    instance_dispatch(SecurityTier::Paranoid, &TierEvent::UnlockRequested);

    // In-memory rate-limit gate. Argon2id at production params
    // already costs ~400-1500ms per attempt, so a brute-force on
    // the typed master password is bounded by KDF cost — but the
    // Dart dialog's exponential-cooldown brake made that bound
    // tighter and was the only enforcement. A direct FRB caller
    // could otherwise fire `unlock_paranoid` in a tight loop and
    // pay only the KDF cost. In-memory (not persisted) per the
    // tier docstring — Paranoid sessions are short-lived and the
    // limiter does not need to survive a process restart.
    let limiters = &crate::app::instance().rate_limiters;
    let p_status = limiters.status(PARANOID_UNLOCK_LIMITER_ID);
    if p_status.is_locked() {
        instance_dispatch(
            SecurityTier::Paranoid,
            &TierEvent::UnlockFailed {
                reason: UnlockFailureReason::WrongSecret,
            },
        );
        return UnlockOutcome::WrongSecret;
    }

    // Argon2id is CPU + memory heavy (400-1500ms wall-clock at
    // production profile); spawn_blocking frees the FRB worker
    // for the duration. The pinned support_dir lives inside the
    // `master_password` singleton (set at startup via
    // `master_password::pin_support_dir`).
    let key = tokio::task::spawn_blocking(move || {
        let path = crate::security::master_password::pinned_support_dir();
        crate::security::master_password::verify_and_derive(path, &password)
    })
    .await;

    match key {
        Ok(Ok(Some(bytes))) if !bytes.is_empty() => {
            limiters.record_success(PARANOID_UNLOCK_LIMITER_ID);
            stage_key(&bytes);
            instance_dispatch(SecurityTier::Paranoid, &TierEvent::UnlockSucceeded);
            run_post_unlock_cascade(SecurityTier::Paranoid);
            UnlockOutcome::Staged
        }
        Ok(Ok(_)) => {
            limiters.record_failure(PARANOID_UNLOCK_LIMITER_ID);
            instance_dispatch(
                SecurityTier::Paranoid,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::WrongSecret,
                },
            );
            UnlockOutcome::WrongSecret
        }
        Ok(Err(detail)) => {
            instance_dispatch(
                SecurityTier::Paranoid,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::Corruption {
                        detail: detail.clone(),
                    },
                },
            );
            UnlockOutcome::Corruption(detail)
        }
        Err(_) => {
            let detail = "Argon2id task panicked".to_string();
            instance_dispatch(
                SecurityTier::Paranoid,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::Corruption {
                        detail: detail.clone(),
                    },
                },
            );
            UnlockOutcome::Corruption(detail)
        }
    }
}

/// Hardware tier (T2) — unseal the DB key via the platform
/// hardware vault (Linux TPM via `tpm2-tools`, Apple Secure
/// Enclave / Android StrongBox / Windows Hello via method
/// channel). Dispatches the cascade events along the way;
/// returns the unsealed key bytes on success or a typed
/// failure variant on wrong PIN / cancelled dialog / plugin
/// failure.
///
/// `password` is the typed user secret — the primary unlock
/// gate. Biometric is the optional shortcut layer that
/// releases this password from an OS-managed slot, never a
/// replacement; the biometric fast-path bypasses this
/// orchestrator and uses [`commit_biometric_unlock_from_secret`]
/// instead.
///
/// Hardware tier is mandatory-password by contract — the
/// signature carries `String` (not `Option<String>`) so a
/// caller that forgot to collect a secret fails the type
/// check at the call site rather than at runtime. An empty
/// string is treated as a usage error and short-circuits with
/// `PluginError("hardware_password_required")` so older
/// dispatch paths that round-tripped through a `String`
/// container surface a typed signal instead of silently
/// rate-limiting against an unseal payload that will always
/// fail.
///
/// The Dart caller owns the T2 unlock dialog UI (PIN input,
/// rate-limit countdown, biometric option, "forgot PIN" reset)
/// and the platform channel call itself; the orchestrator
/// publishes a `HardwareVaultUnlockPromptRequest` and the
/// `HardwareVaultUnlockPromptListener` Dart subscriber calls
/// `HardwareTierVault.read(password)` which fans out per-platform.
pub async fn unlock_hardware(password: String) -> UnlockOutcome {
    instance_dispatch(SecurityTier::Hardware, &TierEvent::UnlockRequested);

    if password.is_empty() {
        let code = "hardware_password_required".to_string();
        instance_dispatch(
            SecurityTier::Hardware,
            &TierEvent::UnlockFailed {
                reason: UnlockFailureReason::PluginUnavailable { code: code.clone() },
            },
        );
        return UnlockOutcome::PluginError(code);
    }
    let pin = Some(password);

    // Rate-limit gate (parity with `unlock_keychain_with_password` /
    // `unlock_paranoid`). The Dart unlock dialog's countdown was
    // the only brake on a programmatic FRB caller firing
    // `unlock_hardware` in a tight loop — the platform plugin's
    // own per-attempt cool-down kicks in too late on Linux
    // (TPM2 unseal returns non-rate-limited immediately on a wrong
    // PIN). The InMemoryRateLimiter applies the shared exponential
    // schedule the keychain-pw and paranoid limiters use, so a
    // direct caller hits the same boundary-level gate.
    let limiters = &crate::app::instance().rate_limiters;
    let hw_status = limiters.status(HARDWARE_UNLOCK_LIMITER_ID);
    if hw_status.is_locked() {
        instance_dispatch(
            SecurityTier::Hardware,
            &TierEvent::UnlockFailed {
                reason: UnlockFailureReason::PluginUnavailable {
                    code: "hardware_vault_rate_limited".into(),
                },
            },
        );
        return UnlockOutcome::PluginError("hardware_vault_rate_limited".into());
    }

    let prompt_id = generate_prompt_id();
    let receiver = hardware_vault_unlock_prompt::instance().register(prompt_id.clone());
    crate::app::instance()
        .bus
        .publish(Event::HardwareVaultUnlockPromptRequest {
            prompt_id: prompt_id.clone(),
            pin,
        });

    match receiver.await {
        Ok(Ok(Some(bytes))) if !bytes.is_empty() => {
            stage_key(&bytes);
            limiters.record_success(HARDWARE_UNLOCK_LIMITER_ID);
            instance_dispatch(SecurityTier::Hardware, &TierEvent::UnlockSucceeded);
            run_post_unlock_cascade(SecurityTier::Hardware);
            UnlockOutcome::Staged
        }
        Ok(Ok(_)) => {
            limiters.record_failure(HARDWARE_UNLOCK_LIMITER_ID);
            instance_dispatch(
                SecurityTier::Hardware,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::WrongSecret,
                },
            );
            UnlockOutcome::WrongSecret
        }
        Ok(Err(detail)) => {
            limiters.record_failure(HARDWARE_UNLOCK_LIMITER_ID);
            instance_dispatch(
                SecurityTier::Hardware,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: detail.clone(),
                    },
                },
            );
            UnlockOutcome::PluginError(detail)
        }
        Err(_) => {
            // Cancellation isn't a failed attempt — don't burn a
            // limiter slot on a user who closed the prompt.
            hardware_vault_unlock_prompt::instance().cancel(&prompt_id);
            instance_dispatch(
                SecurityTier::Hardware,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: "hardware_vault_prompt_cancelled".into(),
                    },
                },
            );
            UnlockOutcome::PluginError("hardware_vault_prompt_cancelled".into())
        }
    }
}

// ── First-launch orchestrators ─────────────────────────────────
//
// Symmetric with the unlock orchestrators above — instead of
// recovering the DB key from on-disk state, they generate a fresh
// key + persist it through the per-tier mechanism (Argon2id KDF,
// OS keychain, hardware vault) + stage in the SecretStore + emit
// the cascade. The Dart `TierUnlockedListener` runs the same
// post-unlock cascade (caches, drift open, securityStateProvider,
// config persist) for both paths so the Dart-side first-launch
// helpers shrink to "dispatch + await listener".

/// First-launch T0 (Plaintext). No secret, no plugin call. Stages
/// the empty buffer + emits the cascade so the listener opens the
/// DB unencrypted via `ensureRustDbOpen(key: empty)`.
pub fn first_launch_plaintext() {
    instance_dispatch(SecurityTier::Plaintext, &TierEvent::UnlockRequested);
    stage_key(&[]);
    instance_dispatch(SecurityTier::Plaintext, &TierEvent::UnlockSucceeded);
    run_post_unlock_cascade(SecurityTier::Plaintext);
}

/// First-launch Paranoid. Runs `master_password::enable` (Argon2id +
/// writes `credentials.kdf` + `credentials.verify` atomically) then
/// stages the derived key + emits the cascade.
pub async fn first_launch_paranoid(password: Vec<u8>) -> UnlockOutcome {
    instance_dispatch(SecurityTier::Paranoid, &TierEvent::UnlockRequested);
    let result = tokio::task::spawn_blocking(move || {
        let path = crate::security::master_password::pinned_support_dir();
        crate::security::master_password::enable(
            path,
            &password,
            &crate::security::master_password::KdfParams::defaults(),
        )
    })
    .await;
    let detail = match result {
        Ok(Ok(bytes)) if !bytes.is_empty() => {
            stage_key(&bytes);
            instance_dispatch(SecurityTier::Paranoid, &TierEvent::UnlockSucceeded);
            run_post_unlock_cascade(SecurityTier::Paranoid);
            return UnlockOutcome::Staged;
        }
        Ok(Ok(_)) => "master_password::enable returned empty key".into(),
        Ok(Err(e)) => e,
        Err(_) => "Argon2id task panicked".into(),
    };
    instance_dispatch(
        SecurityTier::Paranoid,
        &TierEvent::UnlockFailed {
            reason: UnlockFailureReason::Corruption {
                detail: detail.clone(),
            },
        },
    );
    UnlockOutcome::Corruption(detail)
}

/// First-launch T1 (Keychain). Generates a random AES-GCM key,
/// writes it directly to the OS keychain via
/// [`lfs_os_security::secure_key_storage::write`], then stages
/// the bytes + emits the cascade. On a write failure dispatches
/// `UnlockFailed { PluginUnavailable }` so the caller falls back
/// to plaintext.
pub async fn first_launch_keychain() -> UnlockOutcome {
    instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockRequested);
    let key = crate::crypto::aes_gcm_random_key();
    match write_to_keychain(&key).await {
        Ok(()) => {
            stage_key(&key);
            instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockSucceeded);
            run_post_unlock_cascade(SecurityTier::Keychain);
            UnlockOutcome::Staged
        }
        Err(detail) => {
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: detail.clone(),
                    },
                },
            );
            UnlockOutcome::PluginError(detail)
        }
    }
}

/// First-launch T1+pw (KeychainWithPassword). Sets the gate password
/// (Rust-side actor writes the salt + verifier files), generates a
/// random key, writes it to the OS keychain via the Dart
/// subscriber, stages the bytes + emits the cascade.
pub async fn first_launch_keychain_with_password(password: Vec<u8>) -> UnlockOutcome {
    instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockRequested);
    let support_dir = crate::security::master_password::pinned_support_dir();
    if let Err(detail) =
        crate::security::keychain_password_gate_actor::set_password(support_dir, &password).await
    {
        instance_dispatch(
            SecurityTier::Keychain,
            &TierEvent::UnlockFailed {
                reason: UnlockFailureReason::Corruption {
                    detail: detail.clone(),
                },
            },
        );
        return UnlockOutcome::Corruption(detail);
    }
    let key = crate::crypto::aes_gcm_random_key();
    match write_to_keychain(&key).await {
        Ok(()) => {
            stage_key(&key);
            instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockSucceeded);
            run_post_unlock_cascade(SecurityTier::Keychain);
            UnlockOutcome::Staged
        }
        Err(detail) => {
            // Roll back the gate so a follow-up retry sees a
            // fresh "not configured" state instead of stale
            // verifier files keyed off a password that the user
            // can't reproduce after the failed first-launch.
            let _ = crate::security::keychain_password_gate_actor::clear(support_dir).await;
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: detail.clone(),
                    },
                },
            );
            UnlockOutcome::PluginError(detail)
        }
    }
}

/// First-launch T2 (Hardware). Generates a fresh AES-GCM key,
/// publishes a `HardwareVaultSealPromptRequest` so the Dart
/// subscriber wraps it via `HardwareTierVault.store(dbKey: bytes,
/// pin: pin)`, stages the same bytes + emits the cascade. `pin`
/// is `None` for the passwordless variant.
pub async fn first_launch_hardware(pin: Option<String>) -> UnlockOutcome {
    instance_dispatch(SecurityTier::Hardware, &TierEvent::UnlockRequested);
    let key = crate::crypto::aes_gcm_random_key();
    let prompt_id = generate_prompt_id();
    let receiver = hardware_vault_seal_prompt::instance().register(prompt_id.clone());
    // Stage the DB key + optional PIN in the SecretStore under
    // transient ids so the broadcast bus carries only the ids,
    // not the plaintext bytes. The Dart subscriber takes (atomic
    // read-and-remove) the bytes inside its handler and never
    // sees them on the channel buffer.
    let secrets = &crate::app::instance().secrets;
    let db_key_secret_id = format!("seal_prompt.db_key.{prompt_id}");
    secrets.put(&db_key_secret_id, &key);
    let pin_secret_id = pin.as_ref().map(|p| {
        let id = format!("seal_prompt.pin.{prompt_id}");
        secrets.put(&id, p.as_bytes());
        id
    });
    crate::app::instance()
        .bus
        .publish(Event::HardwareVaultSealPromptRequest {
            prompt_id: prompt_id.clone(),
            db_key_secret_id: db_key_secret_id.clone(),
            pin_secret_id: pin_secret_id.clone(),
        });
    let outcome = match receiver.await {
        Ok(Ok(())) => {
            stage_key(&key);
            instance_dispatch(SecurityTier::Hardware, &TierEvent::UnlockSucceeded);
            run_post_unlock_cascade(SecurityTier::Hardware);
            UnlockOutcome::Staged
        }
        Ok(Err(detail)) => {
            instance_dispatch(
                SecurityTier::Hardware,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: detail.clone(),
                    },
                },
            );
            UnlockOutcome::PluginError(detail)
        }
        Err(_) => {
            hardware_vault_seal_prompt::instance().cancel(&prompt_id);
            let detail = "hardware_vault_seal_prompt_cancelled".to_string();
            instance_dispatch(
                SecurityTier::Hardware,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: detail.clone(),
                    },
                },
            );
            UnlockOutcome::PluginError(detail)
        }
    };
    // Drop any staged seal-prompt secrets the Dart subscriber did
    // not take — `take` is atomic-read-and-remove, so the
    // success path has already drained them; the error / cancel
    // paths could otherwise leave the bytes pinned in the
    // SecretStore until process exit.
    let _ = secrets.take(&db_key_secret_id);
    if let Some(id) = &pin_secret_id {
        let _ = secrets.take(id);
    }
    outcome
}

/// Direct keychain write via [`lfs_os_security::secure_key_storage`].
/// Returns `Ok(())` on success or `Err(plugin_code)` on failure.
async fn write_to_keychain(bytes: &[u8]) -> Result<(), String> {
    lfs_os_security::secure_key_storage::write(ENCRYPTION_KEY_SLOT, bytes)
        .await
        .map_err(|e| format!("keychain_write_failed: {e}"))
}

/// Stage [`bytes`] in the SecretStore + drive the tier machine
/// `Locked → Unlocking → Unlocked` cascade for [`tier`] without
/// going through a per-tier verify (gate / Argon2id /
/// keychain-read / hardware unseal). Used by the biometric
/// fast-path on T1+pw/T2 — the bytes come from the OS-managed
/// `BiometricKeyVault` (Dart-side flutter plugin), so the
/// per-tier orchestrator's verify step is bypassed; the
/// cascade still has to fire so the [`TierUnlockedListener`]
/// runs the same post-unlock cascade (caches, drift open,
/// config persist) as the typed-secret path.
///
/// Idempotent against the tier-machine state guards. Caller is
/// responsible for ensuring the bytes really do unlock the DB
/// (the biometric vault is keyed off the same DB key that the
/// keychain / hardware vault stores).
pub fn commit_biometric_unlock(tier: SecurityTier, bytes: &[u8]) {
    instance_dispatch(tier, &TierEvent::UnlockRequested);
    stage_key(bytes);
    instance_dispatch(tier, &TierEvent::UnlockSucceeded);
    run_post_unlock_cascade(tier);
}

/// SecretRef variant of [`commit_biometric_unlock`]. The DB key is
/// already staged in the [`crate::secrets::SecretStore`] under
/// `secret_id`; if that id differs from the canonical
/// [`TIER_UNLOCK_KEY_ID`] slot, the entry is atomically renamed
/// into it before the unlock cascade fires. Bytes never cross the
/// FRB boundary on this path.
///
/// Returns `false` when `secret_id` is empty in the store (or the
/// rename target collision is unrecoverable) so the Dart caller
/// can route to the master-password fallback.
pub fn commit_biometric_unlock_from_secret(tier: SecurityTier, secret_id: &str) -> bool {
    let store = &crate::app::instance().secrets;
    if !store.has(secret_id) {
        return false;
    }
    if secret_id != TIER_UNLOCK_KEY_ID && !store.rename(secret_id, TIER_UNLOCK_KEY_ID) {
        return false;
    }
    instance_dispatch(tier, &TierEvent::UnlockRequested);
    instance_dispatch(tier, &TierEvent::UnlockSucceeded);
    run_post_unlock_cascade(tier);
    true
}

/// Cancel an in-flight unlock attempt for [`tier`]. Dispatches
/// `UnlockFailed { UserCancelled }` so the tier machine flips
/// from `Unlocking` back to `Locked` instead of staying wedged
/// in the half-state when the user dismisses the dialog
/// without submitting.
///
/// Idempotent — the dispatch is state-guarded; calling against
/// a tier that's already `Locked` is a no-op. The Dart unlock
/// dialog calls this on its dismiss handler so every
/// `request_unlock` lands a paired terminal-state event.
pub fn cancel_unlock(tier: SecurityTier) {
    instance_dispatch(
        tier,
        &TierEvent::UnlockFailed {
            reason: UnlockFailureReason::UserCancelled,
        },
    );
}

/// UUIDv4-shaped prompt id. Mirrors the same id-shape every
/// other prompt registry caller uses.
fn generate_prompt_id() -> String {
    use rand::Rng;
    let mut bytes = [0u8; 16];
    rand::rng().fill_bytes(&mut bytes);
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::tier_machine::{instance, TierState};

    /// All three tests in this module mutate the process-singleton
    /// tier-machine + rate-limiter registry. cargo's default
    /// multi-threaded test runner would interleave dispatches and
    /// race assertions; serialise here so each scenario sees a
    /// quiescent global state. Parallelism stays on for the rest
    /// of the suite.
    ///
    /// Uses `tokio::sync::Mutex` (not `std::sync::Mutex`) so the
    /// async tests can hold the guard across `.await` without
    /// tripping the `await_holding_lock` clippy lint.
    fn serial_mutex() -> &'static tokio::sync::Mutex<()> {
        crate::app::test_serial_lock()
    }

    #[test]
    fn unlock_plaintext_self_advances_to_unlocked() {
        // Sync test — `blocking_lock` against the tokio Mutex
        // since we don't have an async runtime here.
        let _guard = serial_mutex().blocking_lock();
        // Drive the singleton through the cascade. Other tests
        // in this binary touch the same singleton so we don't
        // assert from any starting state — only that the final
        // state is Unlocked under the Plaintext tier.
        let _ = crate::app::init();
        unlock_plaintext();
        let m = instance();
        let g = m.lock().unwrap_or_else(|e| e.into_inner());
        assert_eq!(g.state(), TierState::Unlocked);
        assert_eq!(g.tier(), SecurityTier::Plaintext);
    }

    /// Bypass-prevention regression: when the in-memory limiter
    /// for `tier_unlock.keychain_with_password` is locked, the
    /// orchestrator must short-circuit to `WrongSecret` before
    /// it ever calls into `pinned_support_dir()` (which would
    /// panic in tests because no support dir is pinned). If the
    /// rate-limit gate ever regresses out of the orchestrator,
    /// this test panics on the missing pin instead of returning
    /// `WrongSecret`.
    #[tokio::test]
    async fn unlock_keychain_with_password_short_circuits_when_limiter_locked() {
        let _guard = serial_mutex().lock().await;
        let _ = crate::app::init();
        let limiters = &crate::app::instance().rate_limiters;

        // Drive enough record_failure calls to exhaust the
        // backoff schedule (10 entries; index >=1 arms a non-
        // zero cooldown, so a single failure is enough). Use
        // a fresh id-suffix to avoid bleed between tests in
        // this binary.
        for _ in 0..crate::rate_limit::BACKOFF_SCHEDULE.len() {
            limiters.record_failure(KEYCHAIN_PW_UNLOCK_LIMITER_ID);
        }
        assert!(
            limiters.status(KEYCHAIN_PW_UNLOCK_LIMITER_ID).is_locked(),
            "limiter must be locked before invoking the orchestrator"
        );

        let outcome = unlock_keychain_with_password("any-wrong-password".into()).await;
        assert_eq!(outcome, UnlockOutcome::WrongSecret);

        // Cleanup so subsequent tests in this binary that touch
        // the T1+pw limiter start fresh.
        limiters.record_success(KEYCHAIN_PW_UNLOCK_LIMITER_ID);
    }

    /// Mirror of the above for the Paranoid tier. Argon2id is
    /// the only attacker brake without the limiter; if the
    /// `is_locked` short-circuit regresses, this test would
    /// pay the KDF cost (or panic on missing pinned support_dir),
    /// neither of which is `WrongSecret` returning fast.
    #[tokio::test]
    async fn unlock_paranoid_short_circuits_when_limiter_locked() {
        let _guard = serial_mutex().lock().await;
        let _ = crate::app::init();
        let limiters = &crate::app::instance().rate_limiters;

        for _ in 0..crate::rate_limit::BACKOFF_SCHEDULE.len() {
            limiters.record_failure(PARANOID_UNLOCK_LIMITER_ID);
        }
        assert!(
            limiters.status(PARANOID_UNLOCK_LIMITER_ID).is_locked(),
            "Paranoid limiter must be locked before invoking the orchestrator"
        );

        let started = std::time::Instant::now();
        let outcome = unlock_paranoid("any-wrong-password".into()).await;
        let elapsed = started.elapsed();
        assert_eq!(outcome, UnlockOutcome::WrongSecret);
        // Belt-and-braces — Argon2id at production params costs
        // 400-1500 ms; a short-circuit returns in <10 ms. If we
        // somehow took the verify path despite the lock, the
        // wall-clock would expose it even before the missing-pin
        // panic surfaces.
        assert!(
            elapsed < std::time::Duration::from_millis(100),
            "short-circuit took too long: {elapsed:?}"
        );

        limiters.record_success(PARANOID_UNLOCK_LIMITER_ID);
    }

    /// `unlock_hardware(empty)` must surface a typed error before
    /// the prompt registry fires — the Hardware tier is always
    /// password-gated and an empty string means the caller never
    /// collected a secret. The signature requires `String`, so
    /// "no secret at all" can't even be expressed at the type
    /// level; the empty-string check guards the legacy
    /// FRB-shim wire shape that round-trips through a `String`
    /// container.
    #[tokio::test]
    async fn unlock_hardware_empty_password_returns_typed_error() {
        let _guard = serial_mutex().lock().await;
        let _ = crate::app::init();
        let limiters = &crate::app::instance().rate_limiters;
        // Reset the limiter so prior tests in this binary do not
        // mask the short-circuit assertion.
        limiters.record_success(HARDWARE_UNLOCK_LIMITER_ID);

        let outcome = unlock_hardware(String::new()).await;
        match outcome {
            UnlockOutcome::PluginError(code) => {
                assert_eq!(code, "hardware_password_required");
            }
            other => panic!("expected PluginError(hardware_password_required), got {other:?}"),
        }
    }

    /// Bus contract: the orchestrator publishes
    /// `BusEvent::UnlockCascadeReady { tier_wire, has_key }` AFTER
    /// the existing `TierStateChanged.unlocked` event so the Dart
    /// listener subscribes to a single payload instead of probing
    /// the tier machine + secret store directly. Plaintext is the
    /// simplest path to exercise without a real keychain / hardware
    /// vault — every cascade-bearing tier shares the same helper.
    #[tokio::test]
    async fn unlock_plaintext_publishes_cascade_ready_event() {
        let _guard = serial_mutex().lock().await;
        let app = crate::app::init();
        let mut rx = app.bus.subscribe(crate::bus::EventTopic::Tier);
        unlock_plaintext();

        // Walk the topic stream until we see the cascade-ready
        // event. The orchestrator also publishes the
        // intermediate `TierStateChanged.{unlocking,unlocked}`
        // transitions on the same channel; we ignore them and
        // assert only on the new variant.
        let deadline = std::time::Duration::from_secs(2);
        let event = tokio::time::timeout(deadline, async {
            loop {
                match rx.recv().await {
                    Ok(Event::UnlockCascadeReady { tier_wire, has_key }) => {
                        return (tier_wire, has_key);
                    }
                    Ok(_) => continue,
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(e) => panic!("recv error: {e:?}"),
                }
            }
        })
        .await
        .expect("cascade event must fire within 2s");

        assert_eq!(
            event.0, "plaintext",
            "tier_wire must mirror the unlocked tier"
        );
        // Plaintext stages an empty buffer; the slot is still
        // present so the probe-shape `has_key` follows
        // `secrets_has(ACTIVE_DBKEY_SECRET_ID)` semantics — true
        // when the entry exists at all, empty or not.
        assert!(event.1, "has_key must reflect the staged slot probe");
    }
}
