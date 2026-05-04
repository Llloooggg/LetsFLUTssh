// Utilities for sanitizing sensitive data before logging or surfacing in
// user-facing error toasts.
//
// Routes through `lfs_core::log_sanitize` over the synchronous FRB
// endpoints — the canonical PEM/base64 redactor and IP/user@host/path
// scrubber live Rust-side.
//
// **Pre-FRB-init safety.** `AppLogger.logCritical` (the crash-path
// logger wired into the runZonedGuarded / FlutterError / PlatformDispatcher
// error handlers) calls these functions on every error, and errors
// can fire before `RustLib.init()` has completed — the Rust core
// load is deferred past the first frame so the splash paints
// immediately. If the sanitizer itself threw "FRB not initialised",
// the zone handler would catch the throw, log it again, hit the same
// throw, and loop forever (the symptom that prompted this guard:
// every async error pre-init turned into infinite "Bad state: FRB
// not initialised" spam). The wrappers below detect the unbootstrapped
// state via `RustLib.initialized` and fall through to the unredacted
// input. Trade-off: a handful of error lines that fire in the brief
// window between `runApp` and `_initRustCore` may carry unredacted
// PEM / IP / paths. That window contains only bootstrap-internal
// errors (no SSH / SFTP work yet, no user secrets entered), and
// trading silent log corruption for a crash loop is the right call.

import '../src/rust/api/log_sanitize.dart' as rust_san;
import '../src/rust/frb_generated.dart' show RustLib;

/// Strip PEM private keys and long base64 blobs. No-op fallback when
/// the Rust core is not yet initialised — see the file-level comment.
String redactSecrets(String input) {
  if (!RustLib.instance.initialized) return input;
  try {
    return rust_san.redactSecrets(input: input);
  } catch (_) {
    return input;
  }
}

/// Remove sensitive data (IPv4 / IPv6 addresses, user@host, host:port,
/// home-dir paths, …) from error messages. No-op fallback when the
/// Rust core is not yet initialised — see the file-level comment.
String sanitizeErrorMessage(String message) {
  if (!RustLib.instance.initialized) return message;
  try {
    return rust_san.sanitizeErrorMessage(input: message);
  } catch (_) {
    return message;
  }
}
