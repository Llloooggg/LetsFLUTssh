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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redact_secrets_strips_pem_block() {
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\nbody\n-----END OPENSSH PRIVATE KEY-----";
        let out = redact_secrets(pem.into());
        assert!(!out.contains("-----BEGIN"));
        assert!(out.contains("REDACTED"));
    }

    #[test]
    fn redact_secrets_passes_plain_text() {
        let plain = "no secrets here";
        assert_eq!(redact_secrets(plain.into()), plain);
    }

    #[test]
    fn sanitize_error_message_redacts_user_at_host() {
        let msg = "auth failed for alice@edge.example.com";
        let out = sanitize_error_message(msg.into());
        assert!(!out.contains("alice@edge.example.com"));
    }

    #[test]
    fn looks_sensitive_recognises_pem_header() {
        assert!(looks_sensitive(
            "-----BEGIN RSA PRIVATE KEY-----\nbody".into()
        ));
    }

    #[test]
    fn looks_sensitive_recognises_long_base64_run() {
        let long = "x".repeat(199);
        assert!(!looks_sensitive(long.clone()), "199 < cap should pass");
        let longer = "A".repeat(220);
        assert!(looks_sensitive(longer));
    }

    #[test]
    fn looks_sensitive_passes_plain_text() {
        assert!(!looks_sensitive("ls -la /tmp".into()));
        assert!(!looks_sensitive("".into()));
    }
}
