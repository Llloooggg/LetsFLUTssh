//! FRB adapter for `lfs_os_security`. Process hardening +
//! page-lock helpers. The unsafe FFI lives in
//! `lfs_os_security::*`; this shim only marshals.

/// Per-step result reported by [`os_security_apply_startup_hardening`].
/// `code` carries the underlying syscall return code (0 = POSIX
/// success). `error` is `None` on success.
#[derive(Debug, Clone)]
pub struct DbHardeningStep {
    pub label: String,
    pub code: i64,
    pub error: Option<String>,
}

/// Apply whatever startup hardening the current platform supports.
/// Idempotent — re-running a process where hardening already
/// landed is a no-op. Returns the per-step outcomes for the
/// caller to log.
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_apply_startup_hardening() -> Vec<DbHardeningStep> {
    lfs_os_security::apply_startup_hardening()
        .into_iter()
        .map(|s| {
            let (code, error) = match s.outcome {
                Ok(c) => (c, None),
                Err(e) => (0, Some(e)),
            };
            DbHardeningStep {
                label: s.label,
                code,
                error,
            }
        })
        .collect()
}

/// Page-lock `len` bytes at `addr`. Returns `true` on success.
/// `addr` is the integer address of a Dart-side native buffer
/// (e.g. `Pointer.address`); the kernel reads the address-range
/// descriptor and never derefs into Dart heap.
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_lock_memory(addr: usize, len: usize) -> bool {
    lfs_os_security::lock_memory(addr, len)
}

/// Reverse of [`os_security_lock_memory`]. Errors swallowed —
/// best-effort cleanup.
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_unlock_memory(addr: usize, len: usize) {
    lfs_os_security::unlock_memory(addr, len);
}

/// Set `NSURLIsExcludedFromBackupKey = true` on the directory at
/// `path` so iCloud Backup / iTunes / Time Machine skip it.
/// No-op on Linux / Windows / Android. Returns the underlying
/// Foundation error string when the call fails on Apple.
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_exclude_from_backup(path: String) -> Result<(), String> {
    lfs_os_security::backup_exclusion::exclude_from_backup(&path)
}

/// Write `text` to the system clipboard with the per-platform
/// "do not sync / do not history" flags applied in the same write
/// session — Win cloud-clipboard opt-out, macOS NSPasteboard
/// transient/concealed types, iOS UIPasteboard.localOnly. Linux
/// uses arboard for the basic write. Android isn't covered here
/// (the Dart wrapper short-circuits to its existing
/// MethodChannel for `EXTRA_IS_SENSITIVE` before invoking).
#[flutter_rust_bridge::frb(sync)]
pub fn os_security_set_secure_clipboard(text: String) -> Result<(), String> {
    lfs_os_security::secure_clipboard::set_secure_text(&text)
}

#[derive(Debug, Clone)]
pub enum DbBiometricAvailability {
    /// `Ok` mapped to this variant — biometrics ready.
    Available,
    PlatformUnsupported,
    NoSensor,
    NotEnrolled,
    SystemServiceMissing,
    Probe(String),
}

/// Probe the platform's biometric backend. Apple uses
/// `LAContext.canEvaluatePolicy` via objc2; Windows uses
/// `UserConsentVerifier.CheckAvailabilityAsync` via the
/// `windows` crate; Android calls `BiometricManager.canAuthenticate`
/// via JNI. Linux short-circuits — the Dart wrapper routes Linux
/// through fprintd directly so the daemon-missing /
/// reader-absent / no-finger-enrolled distinction stays visible
/// to the Settings UI.
#[flutter_rust_bridge::frb]
pub async fn os_security_biometric_availability() -> DbBiometricAvailability {
    match lfs_os_security::biometric_auth::check_availability().await {
        Ok(()) => DbBiometricAvailability::Available,
        Err(reason) => match reason {
            lfs_os_security::biometric_auth::BiometricUnavailableReason::PlatformUnsupported => {
                DbBiometricAvailability::PlatformUnsupported
            }
            lfs_os_security::biometric_auth::BiometricUnavailableReason::NoSensor => {
                DbBiometricAvailability::NoSensor
            }
            lfs_os_security::biometric_auth::BiometricUnavailableReason::NotEnrolled => {
                DbBiometricAvailability::NotEnrolled
            }
            lfs_os_security::biometric_auth::BiometricUnavailableReason::SystemServiceMissing => {
                DbBiometricAvailability::SystemServiceMissing
            }
            lfs_os_security::biometric_auth::BiometricUnavailableReason::Probe(msg) => {
                DbBiometricAvailability::Probe(msg)
            }
        },
    }
}

/// Show the OS biometric prompt with the localised reason text.
/// Resolves to `true` only on a successful authenticate; every
/// failure mode (cancel / no-match / hardware error / timeout /
/// platform-unsupported) maps to `false` so the Dart caller has
/// one branch to handle.
#[flutter_rust_bridge::frb]
pub async fn os_security_biometric_authenticate(reason: String) -> bool {
    lfs_os_security::biometric_auth::authenticate(&reason).await
}

/// Subscribe to OS session-lock events. Yields one `()` per OS
/// lock transition. Currently fires on Linux only (logind via
/// zbus); macOS + Windows keep their existing native plugins
/// because both are window/run-loop bound. The Dart caller
/// short-circuits before invoking on platforms where the Rust
/// listener is a no-op.
pub async fn os_security_session_lock_subscribe(
    sink: crate::frb_generated::StreamSink<()>,
) -> Result<(), String> {
    let mut rx = lfs_os_security::session_lock_listener::subscribe();
    loop {
        match rx.recv().await {
            Ok(()) => {
                if sink.add(()).is_err() {
                    break;
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
            Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
        }
    }
    Ok(())
}
