//! FRB adapter for `lfs_core::log_sanitize`. Synchronous one-shot
//! wrappers — both functions run on the caller's thread (the
//! regex match cost is negligible compared to FRB worker
//! scheduling, and the Dart-side log path runs sanitisation on
//! every line so a sync hop avoids per-line worker churn).

#[flutter_rust_bridge::frb(sync)]
pub fn redact_secrets(input: String) -> String {
    lfs_core::log_sanitize::redact_secrets(&input)
}

#[flutter_rust_bridge::frb(sync)]
pub fn sanitize_error_message(input: String) -> String {
    lfs_core::log_sanitize::sanitize_error_message(&input)
}

/// True when [`text`] looks like it carries secret material — a
/// PEM private-key block or a long base64 run (≥ 200 chars).
/// Backed by the same regex pool the redactor uses, so the
/// clipboard auto-wipe + the log scrubber agree on what counts as
/// "do not let this leak".
#[flutter_rust_bridge::frb(sync)]
pub fn looks_sensitive(text: String) -> bool {
    lfs_core::log_sanitize::looks_sensitive(&text)
}
