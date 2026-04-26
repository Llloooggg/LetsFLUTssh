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
