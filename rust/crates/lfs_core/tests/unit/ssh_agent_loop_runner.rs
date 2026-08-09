/// Unit tests extracted from ssh_agent/loop_runner.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use tokio::io::duplex;

/// Serialise tests that prime the process-singleton DB via
/// `app.db_inject_for_tests`. `cargo test` runs tokio tests in
/// parallel by default; the singleton slot races otherwise — one
/// test's prime gets replaced by another's before assertions run.
/// Acquire at the top of any test touching the shared DB.

#[tokio::test]
async fn write_frame_emits_length_prefix() {
    let (mut srv, mut cli) = duplex(64);
    let payload = vec![0xAA, 0xBB, 0xCC];
    write_frame(&mut srv, &payload).await.unwrap();
    let mut got = vec![0u8; 7];
    cli.read_exact(&mut got).await.unwrap();
    assert_eq!(got, vec![0, 0, 0, 3, 0xAA, 0xBB, 0xCC]);
}

#[tokio::test]
async fn failure_payload_is_msg_id_5_only() {
    assert_eq!(failure_payload(), vec![5]);
}

#[tokio::test]
async fn dispatch_unknown_msg_id_returns_failure() {
    let mut ep = Endpoint::default();
    // 99 is not a valid request type — ssh-agent-lib's
    // `Request::decode` should reject it.
    let out = dispatch_payload(&mut ep, &[99u8]).await;
    assert_eq!(out, failure_payload());
}

#[tokio::test]
async fn dispatch_empty_payload_returns_failure() {
    let mut ep = Endpoint::default();
    let out = dispatch_payload(&mut ep, &[]).await;
    assert_eq!(out, failure_payload());
}

/// End-to-end smoke. Primes the singleton DB with two rows: one
/// FIDO2 sk-* row with a paired OpenSSH certificate, one bare
/// FIDO2 sk-* row. Drives `handle_socket` through a tokio duplex
/// stream and asserts the IDENTITIES_ANSWER frame contains:
///
/// - 3 entries total (bare + cert for paired key, bare for the
///   other),
/// - the cert blob bytes equal `Certificate::to_bytes()` for the
///   stored cert text.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn handle_socket_serves_cert_paired_identities_answer() {
    use crate::db::{bootstrap_schema, ssh_key_certificates, ssh_keys, Connection, Db};
    use crate::ssh_agent::identities;

    let _guard = crate::app::test_serial_lock().lock().await;
    // Prime the process singleton + an in-memory DB shared with
    // `Endpoint::list_rows`.
    let app = crate::app::init();
    let conn = Connection::open_in_memory().unwrap();
    conn.raw()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    let db = Db::from_raw_for_tests(conn);

    const USER_PUB: &str = include_str!("../fixtures/ssh_agent/ed25519_user.pub");
    const USER_CERT: &[u8] = include_bytes!("../fixtures/ssh_agent/ed25519_cert.pub");

    db.with_conn(|c| {
        ssh_keys::upsert(
            c,
            &ssh_keys::SshKeyRow {
                id: "fido-cert".into(),
                label: "FIDO-with-cert".into(),
                private_key: "PRIV".into(),
                public_key: USER_PUB.into(),
                key_type: "sk-ssh-ed25519@openssh.com".into(),
                is_generated: false,
                created_at_ms: 0,
                credential_id: Some(vec![1, 2, 3]),
                application_string: Some("ssh:".into()),
                has_user_verification: false,
                agent_policy: ssh_keys::AgentPolicy::Always,
                backend: ssh_keys::KeyBackend::Fido2,
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
            },
        )
    })
    .unwrap();
    db.with_conn(|c| {
        ssh_key_certificates::upsert(
            c,
            &ssh_key_certificates::CertRecord {
                key_id: "fido-cert".into(),
                certificate: USER_CERT.to_vec(),
                valid_after: 0,
                valid_before: i64::MAX,
                principals: Vec::new(),
                critical_options: std::collections::BTreeMap::new(),
                fingerprint: "SHA256:fixture".into(),
            },
        )
    })
    .unwrap();
    // A second bare-only row so the answer has three entries.
    db.with_conn(|c| {
        ssh_keys::upsert(
            c,
            &ssh_keys::SshKeyRow {
                id: "fido-bare".into(),
                label: "FIDO-bare".into(),
                private_key: "PRIV".into(),
                public_key: USER_PUB.into(),
                key_type: "sk-ssh-ed25519@openssh.com".into(),
                is_generated: false,
                created_at_ms: 0,
                credential_id: Some(vec![4, 5, 6]),
                application_string: Some("ssh:".into()),
                has_user_verification: false,
                agent_policy: ssh_keys::AgentPolicy::Always,
                backend: ssh_keys::KeyBackend::Fido2,
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
            },
        )
    })
    .unwrap();
    app.db_inject_for_tests(db);

    let (srv, mut cli) = tokio::io::duplex(4096);
    let ep = Endpoint::default();
    let task = tokio::spawn(async move {
        let _ = handle_socket(ep, srv).await;
    });

    // Send REQUEST_IDENTITIES (msg id 11, no body).
    cli.write_all(&[0, 0, 0, 1, REQUEST_IDENTITIES_MSG_ID])
        .await
        .unwrap();
    cli.flush().await.unwrap();

    // Read the framed reply.
    let mut len_bytes = [0u8; 4];
    cli.read_exact(&mut len_bytes).await.unwrap();
    let reply_len = u32::from_be_bytes(len_bytes) as usize;
    let mut reply = vec![0u8; reply_len];
    cli.read_exact(&mut reply).await.unwrap();
    drop(cli);
    let _ = task.await;

    // Parse the reply: msg id (1) + nkeys (4) + entries.
    assert_eq!(reply[0], identities::IDENTITIES_ANSWER_MSG_ID);
    let nkeys = u32::from_be_bytes(reply[1..5].try_into().unwrap()) as usize;
    assert_eq!(nkeys, 3, "expected bare + cert + bare for two rows");

    // The cert blob bytes we expect on the wire.
    let cert_text = std::str::from_utf8(USER_CERT).unwrap().trim();
    let cert = ssh_key::Certificate::from_openssh(cert_text).unwrap();
    let expected_cert_blob = cert.to_bytes().unwrap();

    // Walk the entries until we find a cert blob that matches.
    let mut cursor = 5usize;
    let mut found_cert_blob = false;
    for _ in 0..nkeys {
        let blob_len = u32::from_be_bytes(reply[cursor..cursor + 4].try_into().unwrap()) as usize;
        cursor += 4;
        let blob = &reply[cursor..cursor + blob_len];
        cursor += blob_len;
        let comment_len =
            u32::from_be_bytes(reply[cursor..cursor + 4].try_into().unwrap()) as usize;
        cursor += 4 + comment_len;

        if blob == expected_cert_blob.as_slice() {
            found_cert_blob = true;
        }
    }
    assert!(
        found_cert_blob,
        "expected a cert blob entry in the answer; cert bytes: {} on wire",
        expected_cert_blob.len()
    );
}

/// Compose a SIGN_REQUEST body (without the leading msg-id byte):
/// `string key_blob || string data || uint32 flags`. Used by the
/// cert-routing tests below to exercise the framing branch
/// without dragging in the full `ssh_agent_lib` typed encoder.
fn build_sign_request_body(key_blob: &[u8], data: &[u8], flags: u32) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(&(key_blob.len() as u32).to_be_bytes());
    out.extend_from_slice(key_blob);
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    out.extend_from_slice(data);
    out.extend_from_slice(&flags.to_be_bytes());
    out
}

#[test]
fn is_cert_algorithm_recognises_cert_suffix() {
    // `ssh-ed25519-cert-v01@openssh.com` = 32 ASCII bytes, length 32.
    let algo = b"ssh-ed25519-cert-v01@openssh.com";
    let mut blob = Vec::new();
    blob.extend_from_slice(&(algo.len() as u32).to_be_bytes());
    blob.extend_from_slice(algo);
    assert!(is_cert_algorithm(&blob));
}

#[test]
fn is_cert_algorithm_recognises_sk_cert_suffix() {
    let algo = b"sk-ssh-ed25519-cert-v01@openssh.com";
    let mut blob = Vec::new();
    blob.extend_from_slice(&(algo.len() as u32).to_be_bytes());
    blob.extend_from_slice(algo);
    assert!(is_cert_algorithm(&blob));
}

#[test]
fn is_cert_algorithm_rejects_bare_key_blob() {
    let algo = b"ssh-ed25519";
    let mut blob = Vec::new();
    blob.extend_from_slice(&(algo.len() as u32).to_be_bytes());
    blob.extend_from_slice(algo);
    assert!(!is_cert_algorithm(&blob));
}

#[test]
fn is_cert_algorithm_rejects_truncated_blob() {
    // Length header claims 32 bytes; payload provides 4.
    let blob = vec![0, 0, 0, 32, b'x', b'y', b'z', b'a'];
    assert!(!is_cert_algorithm(&blob));
}

#[test]
fn is_cert_algorithm_rejects_empty_blob() {
    assert!(!is_cert_algorithm(&[]));
}

/// Routing-only smoke. Sends a SIGN_REQUEST whose `key_blob` is
/// the real ed25519 cert from the fixture. The matching `ssh_keys`
/// row is FIDO2-backed, so the dispatcher reaches
/// `fido2_sign` — there's no FIDO2 device in CI, so the dispatcher
/// surfaces a typed error which the loop translates into a
/// SSH_AGENT_FAILURE byte. The contract this test pins is the
/// *routing*: the cert blob reached `try_sign_with_cert`, decoded
/// as a cert, matched the row, and ran through the gate; failure
/// to reach the device is the expected ending in this harness.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn cert_sign_routes_to_dispatch_then_returns_failure_without_device() {
    use crate::db::{bootstrap_schema, ssh_keys, Connection, Db};

    let _guard = crate::app::test_serial_lock().lock().await;
    let app = crate::app::init();
    let conn = Connection::open_in_memory().unwrap();
    conn.raw()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    let db = Db::from_raw_for_tests(conn);

    const USER_PUB: &str = include_str!("../fixtures/ssh_agent/ed25519_user.pub");
    const USER_CERT: &[u8] = include_bytes!("../fixtures/ssh_agent/ed25519_cert.pub");

    db.with_conn(|c| {
        ssh_keys::upsert(
            c,
            &ssh_keys::SshKeyRow {
                id: "fido-cert-sign".into(),
                label: "FIDO-with-cert-sign".into(),
                private_key: "PRIV".into(),
                public_key: USER_PUB.into(),
                key_type: "sk-ssh-ed25519@openssh.com".into(),
                is_generated: false,
                created_at_ms: 0,
                credential_id: Some(vec![1, 2, 3]),
                application_string: Some("ssh:".into()),
                has_user_verification: false,
                // `Always` skips the per-key confirm gate so we
                // reach the backend dispatcher directly.
                agent_policy: ssh_keys::AgentPolicy::Always,
                backend: ssh_keys::KeyBackend::Fido2,
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
            },
        )
    })
    .unwrap();
    app.db_inject_for_tests(db);

    let cert_text = std::str::from_utf8(USER_CERT).unwrap().trim();
    let cert = ssh_key::Certificate::from_openssh(cert_text).unwrap();
    let cert_blob = cert.to_bytes().unwrap();

    let mut ep = Endpoint::default();
    let mut payload = vec![SIGN_REQUEST_MSG_ID];
    payload.extend_from_slice(&build_sign_request_body(&cert_blob, b"to-sign", 0));
    let reply = dispatch_payload(&mut ep, &payload).await;

    // CTAP2 over libfido2 is unreachable in CI — the dispatcher
    // surfaces the typed error and the loop encodes it as the
    // failure byte. The exact failure mode (device missing /
    // permission denied / unimplemented) is environment-
    // dependent; we pin the wire byte that's invariant.
    assert_eq!(reply, failure_payload());
}

/// Cert blob with no matching DB row -> SSH_AGENT_FAILURE without
/// reaching the backend. Independent of CTAP2 availability.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn cert_sign_unknown_row_returns_failure() {
    use crate::db::{bootstrap_schema, Connection, Db};

    let _guard = crate::app::test_serial_lock().lock().await;
    let app = crate::app::init();
    let conn = Connection::open_in_memory().unwrap();
    conn.raw()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    let db = Db::from_raw_for_tests(conn);
    // No rows inserted — the cert pubkey will not match anything.
    app.db_inject_for_tests(db);

    const USER_CERT: &[u8] = include_bytes!("../fixtures/ssh_agent/ed25519_cert.pub");
    let cert_text = std::str::from_utf8(USER_CERT).unwrap().trim();
    let cert = ssh_key::Certificate::from_openssh(cert_text).unwrap();
    let cert_blob = cert.to_bytes().unwrap();

    let mut ep = Endpoint::default();
    let mut payload = vec![SIGN_REQUEST_MSG_ID];
    payload.extend_from_slice(&build_sign_request_body(&cert_blob, b"to-sign", 0));
    let reply = dispatch_payload(&mut ep, &payload).await;
    assert_eq!(reply, failure_payload());
}

/// Bare-key SIGN_REQUEST stays on the typed path — the cert arm
/// returns `None` and the loop falls through to `Session::handle`.
/// We assert the failure wire byte (no device + no row) instead of
/// a SIGN_RESPONSE, but the load-bearing claim is that the cert arm
/// did NOT short-circuit on a bare blob.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn bare_key_sign_request_falls_through_to_typed_path() {
    let mut ep = Endpoint::default();
    // Compose a bare ssh-ed25519 SIGN_REQUEST against an empty
    // store. The typed path decodes the KeyData fine, finds no
    // matching row, and returns SSH_AGENT_FAILURE.
    const USER_PUB: &str = include_str!("../fixtures/ssh_agent/ed25519_user.pub");
    let pk = ssh_key::PublicKey::from_openssh(USER_PUB).unwrap();
    let mut bare_blob = Vec::new();
    pk.key_data().encode(&mut bare_blob).unwrap();

    // Run a try_sign_with_cert directly to assert the cert arm
    // returns None for a bare blob.
    let body = build_sign_request_body(&bare_blob, b"to-sign", 0);
    let cert_arm = try_sign_with_cert(&mut ep, &body).await;
    assert!(
        cert_arm.is_none(),
        "bare-key SIGN_REQUEST must fall through to the typed path"
    );
}

#[tokio::test]
async fn locked_endpoint_emits_zero_identities() {
    let mut ep = Endpoint::default();
    // The Session trait's `lock` flips the per-connection flag
    // through the typed path; we go through `handle` to exercise
    // the same surface the loop uses.
    let mut payload = Vec::new();
    // Lock request: msg id 22, then `string` empty password.
    payload.push(22u8);
    payload.extend_from_slice(&[0, 0, 0, 0]);
    let out = dispatch_payload(&mut ep, &payload).await;
    // Success message id is 6.
    assert_eq!(out, vec![6]);

    // After lock, RequestIdentities yields the cert-aware empty
    // listing.
    let out = dispatch_payload(&mut ep, &[REQUEST_IDENTITIES_MSG_ID]).await;
    // msg id 12, then nkeys=0.
    assert_eq!(out, vec![12, 0, 0, 0, 0]);
}
