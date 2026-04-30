// Utilities for sanitizing sensitive data before logging or surfacing in
// user-facing error toasts.
//
// Routes through `lfs_core::log_sanitize` over the synchronous FRB
// endpoints — the canonical PEM/base64 redactor and IP/user@host/path
// scrubber live Rust-side. AppLogger gates `sanitize` behind its
// threshold check, so unbootstrapped tests that never enable file
// logging never reach this code path; tests that call `sanitizeError`
// or `redactSecrets` directly bootstrap FRB via `requireFrbLoaded`.

import '../src/rust/api/log_sanitize.dart' as rust_san;

/// Strip PEM private keys and long base64 blobs.
String redactSecrets(String input) => rust_san.redactSecrets(input: input);

/// Remove sensitive data (IPv4 / IPv6 addresses, user@host, host:port,
/// home-dir paths, …) from error messages.
String sanitizeErrorMessage(String message) =>
    rust_san.sanitizeErrorMessage(input: message);
