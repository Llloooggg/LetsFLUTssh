/// Unit tests extracted from ssh_agent/backends.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::db::ssh_keys::{AgentPolicy, SshKeyRow};

fn row_software() -> SshKeyRow {
    SshKeyRow {
        id: "k-sw".into(),
        label: "Software key".into(),
        private_key: "PEM".into(),
        public_key: "PUB".into(),
        key_type: "ssh-ed25519".into(),
        is_generated: false,
        created_at_ms: 0,
        credential_id: None,
        application_string: None,
        has_user_verification: false,
        agent_policy: AgentPolicy::Ask,
        backend: crate::db::ssh_keys::KeyBackend::Software,
        pkcs11_uri: None,
        pkcs11_module_path: None,
        pkcs11_token_serial: None,
        pkcs11_object_id: None,
        pkcs11_object_label: None,
        enclave_tag: None,
        hello_credential_name: None,
        tpm_blob: None,
        tpm_handle: None,
        tpm_provider: None,
        tpm_pin_required: false,
        cng_key_name: None,
        keystore_alias: None,
        keystore_strongbox: false,
        keystore_user_auth_required: false,
        keystore_platform: None,
        imported_as_stub: false,
    }
}

fn row_fido2_no_creds() -> SshKeyRow {
    SshKeyRow {
        credential_id: Some(vec![1, 2, 3]),
        application_string: Some("ssh:".into()),
        key_type: "sk-ssh-ed25519@openssh.com".into(),
        backend: crate::db::ssh_keys::KeyBackend::Fido2,
        ..row_software()
    }
}

#[test]
fn from_row_resolves_software_when_no_credential() {
    let row = row_software();
    assert_eq!(BackendKind::from_row(&row), BackendKind::Software);
}

#[test]
fn from_row_resolves_fido2_when_credential_present() {
    let row = row_fido2_no_creds();
    assert_eq!(BackendKind::from_row(&row), BackendKind::Fido2);
}

#[test]
fn from_row_resolves_hello_when_backend_is_hello() {
    let row = SshKeyRow {
        backend: crate::db::ssh_keys::KeyBackend::Hello,
        key_type: "ecdsa-sha2-nistp256".into(),
        hello_credential_name: Some("letsflutssh-ssh-abc-1234".into()),
        ..row_software()
    };
    assert_eq!(BackendKind::from_row(&row), BackendKind::Hello);
}

#[test]
fn from_row_resolves_keystore_when_backend_is_keystore() {
    let row = SshKeyRow {
        backend: crate::db::ssh_keys::KeyBackend::Keystore,
        key_type: "ecdsa-sha2-nistp256".into(),
        keystore_alias: Some("lfs-keystore-1234".into()),
        keystore_strongbox: true,
        keystore_user_auth_required: true,
        ..row_software()
    };
    assert_eq!(BackendKind::from_row(&row), BackendKind::Keystore);
}

#[tokio::test]
async fn dispatch_keystore_on_desktop_surfaces_unsupported() {
    let row = SshKeyRow {
        backend: crate::db::ssh_keys::KeyBackend::Keystore,
        key_type: "ecdsa-sha2-nistp256".into(),
        keystore_alias: Some("lfs-keystore-1234".into()),
        keystore_strongbox: true,
        keystore_user_auth_required: true,
        ..row_software()
    };
    let err = dispatch_sign(&row, b"data", 0).await.unwrap_err();
    match err {
        BackendError::Signer(Error::Keystore(s)) => {
            assert!(s.contains("Android"), "expected Android note, got {s}");
        }
        other => panic!("expected BackendError::Signer(Error::Keystore), got {other:?}"),
    }
}

#[tokio::test]
async fn dispatch_refuses_software_key() {
    let row = row_software();
    let err = dispatch_sign(&row, b"data", 0).await.unwrap_err();
    assert!(matches!(err, BackendError::SoftwareKeyRefused));
}

#[test]
fn ssh_algorithm_maps_known_sk_strings() {
    assert!(matches!(
        ssh_algorithm_from_key_type("sk-ssh-ed25519@openssh.com").unwrap(),
        russh::keys::ssh_key::Algorithm::SkEd25519
    ));
    assert!(matches!(
        ssh_algorithm_from_key_type("sk-ecdsa-sha2-nistp256@openssh.com").unwrap(),
        russh::keys::ssh_key::Algorithm::SkEcdsaSha2NistP256
    ));
}

#[test]
fn ssh_algorithm_rejects_unknown_string() {
    let err = ssh_algorithm_from_key_type("rsa-classic").unwrap_err();
    assert!(matches!(err, Error::Fido2(_)));
}

#[test]
fn backend_error_software_refused_renders_message() {
    let err = BackendError::SoftwareKeyRefused;
    let s = err.to_string();
    assert!(s.contains("software keys"));
}

/// FIDO2 row whose `has_user_verification` bit is set must short-
/// circuit the dispatcher with the typed
/// `FidoUvNotSupportedViaAgent` error — CTAP2 would otherwise be
/// asked to sign without a PIN and return a generic CTAP2 error
/// that the agent maps to opaque `SSH_AGENT_FAILURE`.
#[tokio::test]
async fn dispatch_refuses_fido2_uv_required_with_typed_error() {
    let row = SshKeyRow {
        label: "yubikey-uv".into(),
        has_user_verification: true,
        ..row_fido2_no_creds()
    };
    let err = dispatch_sign(&row, b"data", 0).await.unwrap_err();
    match err {
        BackendError::FidoUvNotSupportedViaAgent {
            key_label,
            fingerprint,
        } => {
            assert_eq!(key_label, "yubikey-uv");
            // OpenSSH public-key text is the placeholder "PUB" in
            // `row_software()`; that does not parse as OpenSSH so
            // the fingerprint helper falls back to "unknown".
            assert_eq!(fingerprint, "unknown");
        }
        other => panic!("expected BackendError::FidoUvNotSupportedViaAgent, got {other:?}"),
    }
}

/// FIDO2 row WITHOUT UV stays on the existing path. The CTAP2
/// device is unreachable in CI so we don't get a SignOutput, but
/// the dispatcher must NOT short-circuit with the UV error — the
/// failure must be the generic FIDO2 signer error.
#[tokio::test]
async fn dispatch_fido2_without_uv_does_not_short_circuit_on_uv_error() {
    let row = SshKeyRow {
        has_user_verification: false,
        ..row_fido2_no_creds()
    };
    let err = dispatch_sign(&row, b"data", 0).await.unwrap_err();
    assert!(
        !matches!(err, BackendError::FidoUvNotSupportedViaAgent { .. }),
        "uv-not-required row must not surface the uv refusal: {err:?}"
    );
}

/// Error rendering carries enough detail for the log line / future
/// dialog to identify the key: label, fingerprint, and the hint
/// to use a direct connection.
#[test]
fn backend_error_uv_not_supported_renders_message() {
    let err = BackendError::FidoUvNotSupportedViaAgent {
        key_label: "yubikey-uv".into(),
        fingerprint: "SHA256:abc".into(),
    };
    let s = err.to_string();
    assert!(s.contains("yubikey-uv"));
    assert!(s.contains("SHA256:abc"));
    assert!(s.contains("user-verification"));
    assert!(s.contains("direct connection"));
}
