//! Apple `URLResourceKey.isExcludedFromBackup` writer.
//!
//! Replaces the Swift `BackupExclusionPlugin` (`macos/Runner/`,
//! `ios/Runner/`) one-call `URL.setResourceValues` invocation.
//! On macOS this writes the
//! `com.apple.metadata:com_apple_backup_excludeItem` extended
//! attribute, which Time Machine honours; on iOS it sets the
//! private flag iCloud Backup / iTunes / Finder backup all
//! consult.
//!
//! Compile-time no-op on every non-Apple target (Linux, Windows,
//! Android) — those platforms either don't have a cloud-backup
//! default to opt out of, or the exclusion lives in a separate
//! manifest channel (Android `data_extraction_rules.xml`).
//!
//! Idempotent — re-running on a directory that already carries
//! the flag is a cheap no-op the OS handles internally. Failures
//! return a structured `Err(String)` so the Dart caller can log
//! without crashing the startup path.

#[cfg(any(target_os = "macos", target_os = "ios"))]
use objc2::msg_send;
#[cfg(any(target_os = "macos", target_os = "ios"))]
use objc2_foundation::{NSError, NSNumber, NSString, NSURL};

/// Set `NSURLIsExcludedFromBackupKey = true` on the directory at
/// `path`. Idempotent. Returns `Err` only when the OS surface
/// reports a real failure (path missing, permission denied,
/// filesystem doesn't support resource keys). Non-Apple targets
/// short-circuit to `Ok(())` so the caller doesn't have to gate
/// on `cfg!`.
#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn exclude_from_backup(path: &str) -> Result<(), String> {
    // SAFETY: every objc2 call here either returns an autoreleased
    // Retained<T> (memory-managed by the bindings) or sends a
    // documented Cocoa selector; no raw pointer arithmetic. The
    // unsafe blocks scope the `msg_send!` macros, which call
    // through to dynamic-dispatched selectors.
    unsafe {
        let path_ns = NSString::from_str(path);
        let url = NSURL::fileURLWithPath(&path_ns);
        let true_value = NSNumber::numberWithBool(true);
        let key = NSString::from_str("NSURLIsExcludedFromBackupKey");
        let mut error: *mut NSError = std::ptr::null_mut();
        let success: bool = msg_send![
            &*url,
            setResourceValue: &*true_value,
            forKey: &*key,
            error: &mut error,
        ];
        if success {
            return Ok(());
        }
        if !error.is_null() {
            let err_ref = &*error;
            let desc: *const NSString = msg_send![err_ref, localizedDescription];
            if !desc.is_null() {
                let s = (*desc).to_string();
                return Err(format!("setResourceValue failed: {s}"));
            }
        }
        Err("setResourceValue failed (unknown error)".to_string())
    }
}

/// Non-Apple targets: documented no-op so the Dart caller can
/// invoke the function unconditionally on startup without a
/// platform branch.
#[cfg(not(any(target_os = "macos", target_os = "ios")))]
pub fn exclude_from_backup(_path: &str) -> Result<(), String> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_op_on_non_apple_targets_does_not_error() {
        // The function compiles on every host — on Linux / Windows
        // it short-circuits to Ok. On macOS the call would attempt
        // a real setResourceValue against the path; we hand it a
        // path that almost certainly doesn't exist so the assertion
        // is "doesn't panic" rather than "succeeds".
        let result = exclude_from_backup("/tmp/lfs_backup_exclusion_no_such_path");
        if cfg!(not(any(target_os = "macos", target_os = "ios"))) {
            assert!(result.is_ok());
        }
        // Apple side: either Ok (file existed somehow) or a
        // structured error; both are acceptable here.
    }
}
