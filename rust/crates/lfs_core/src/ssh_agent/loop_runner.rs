//! Custom accept loop for the in-process ssh-agent endpoint.
//!
//! ## Why we replace `ssh_agent_lib::agent::listen`
//!
//! `ssh-agent-lib`'s built-in `handle_socket` serialises every outgoing
//! reply through `Codec<Request, Response>`, which encodes the response
//! via the `Encode` trait on the strongly typed
//! `ssh_agent_lib::proto::Response` enum. For the IDENTITIES_ANSWER
//! arm that means each identity goes through `Identity::encode`, which
//! writes `pubkey.encode_prefixed(writer)` — and `pubkey` is an
//! `ssh_key::public::KeyData`. `KeyData` has no `Certificate` variant
//! in `ssh-key 0.6`, and the catch-all `KeyData::Other(OpaquePublicKey)`
//! adds an extra `u32` length prefix between the algorithm string and
//! the rest of the encoded bytes, which doesn't match the wire shape
//! of an OpenSSH certificate (algo string then `string nonce` then the
//! inline cert fields, no extra length prefix in between). So we
//! cannot route a cert through the typed Identity at all.
//!
//! Bypassing `listen` keeps the Session trait surface intact (tests +
//! the unlikely future of a non-cert use case still rely on it) while
//! letting `RequestIdentities` emit hand-crafted bytes through
//! [`identities::encode_identities_answer`]. Every other request type
//! still routes through `Session::handle` and the typed `Response`
//! encoder — only the listing path is custom.
//!
//! ## Wire framing
//!
//! Each agent message is framed as `uint32 length || bytes`. The
//! `bytes` slice starts with a single `uint8` message-type byte and is
//! followed by a per-type payload. See
//! [draft-miller-ssh-agent-14 §3](https://www.ietf.org/archive/id/draft-miller-ssh-agent-14.html#section-3).
//! We read framed bytes via `read_exact`, peek the type byte, and
//! either route through our cert-aware listing path (`type == 11`) or
//! pass the request through to `Session::handle` for the typed path.

use ssh_agent_lib::agent::Session;
use ssh_agent_lib::proto::message::{Request, Response};
use ssh_agent_lib::ssh_encoding::{Decode, Encode};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use crate::ssh_agent::endpoint::Endpoint;
use crate::ssh_agent::identities;

/// SSH agent protocol message-type byte for
/// `SSH_AGENTC_REQUEST_IDENTITIES`. See
/// [draft-miller-ssh-agent-14 §6.1](https://www.ietf.org/archive/id/draft-miller-ssh-agent-14.html#section-6.1).
const REQUEST_IDENTITIES_MSG_ID: u8 = 11;

/// Maximum frame size we accept on a single request. The wire protocol
/// is u32-prefixed; absent a cap a hostile peer could ask us to
/// allocate 4 GiB. OpenSSH ssh-agent caps at 256 KiB; we follow the
/// same number.
const MAX_FRAME_LEN: u32 = 256 * 1024;

/// Drive one accepted client stream to completion. Reads framed
/// requests, dispatches each, writes framed responses, exits cleanly
/// on EOF.
///
/// Returns `Err` only on IO errors that abort the connection — message
/// decode failures or protocol-level errors surface as
/// `SSH_AGENT_FAILURE` (msg id 5) on the same stream and the loop keeps
/// running.
pub(super) async fn handle_socket<S>(mut session: Endpoint, mut stream: S) -> std::io::Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    loop {
        // Frame header: u32 big-endian length of the payload that
        // follows.
        let mut len_bytes = [0u8; 4];
        match stream.read_exact(&mut len_bytes).await {
            Ok(_) => {}
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(()),
            Err(e) => return Err(e),
        }
        let frame_len = u32::from_be_bytes(len_bytes);
        if frame_len == 0 || frame_len > MAX_FRAME_LEN {
            // Refuse oversized / empty frames — no recovery path, the
            // connection is in an unknown state.
            return Err(std::io::Error::other(format!(
                "agent: invalid frame length {frame_len}"
            )));
        }
        let mut payload = vec![0u8; frame_len as usize];
        stream.read_exact(&mut payload).await?;

        let reply = dispatch_payload(&mut session, &payload).await;
        write_frame(&mut stream, &reply).await?;
    }
}

/// Map the request payload to the bytes we should emit as the
/// response payload (without the leading u32 length prefix — that is
/// added by [`write_frame`]).
async fn dispatch_payload(session: &mut Endpoint, payload: &[u8]) -> Vec<u8> {
    if payload.is_empty() {
        return failure_payload();
    }
    let msg_id = payload[0];
    if msg_id == REQUEST_IDENTITIES_MSG_ID {
        // Cert-aware path. The typed Session::request_identities cannot
        // carry cert blobs through Identity::encode, so we build the
        // response bytes ourselves.
        return match identities_payload(session) {
            Ok(bytes) => bytes,
            Err(e) => {
                crate::app_log_warn!("SshAgent", "identities serialisation failed: {e}");
                failure_payload()
            }
        };
    }

    // Every other verb keeps the typed path: decode the wire bytes
    // into a `Request`, run them through `Session::handle`, encode
    // the resulting `Response` via `ssh_encoding::Encode`. The
    // payload is the framed `string` body — `Request::decode` reads
    // the message-type byte first, then the typed body.
    let mut reader: &[u8] = payload;
    let req = match Request::decode(&mut reader) {
        Ok(r) => r,
        Err(e) => {
            crate::app_log_warn!("SshAgent", "request decode failed: {e}");
            return failure_payload();
        }
    };
    let resp = match session.handle(req).await {
        Ok(r) => r,
        Err(ssh_agent_lib::error::AgentError::ExtensionFailure) => Response::ExtensionFailure,
        Err(e) => {
            crate::app_log_warn!("SshAgent", "handle returned failure: {e}");
            Response::Failure
        }
    };
    encode_typed_response(&resp).unwrap_or_else(|_| failure_payload())
}

/// Build the SSH_AGENT_IDENTITIES_ANSWER payload bytes from live DB
/// state. Reads `ssh_keys` rows and the paired `ssh_key_certificates`
/// rows. Locked-session connections short-circuit to an empty list
/// (the protocol says lock should hide identities entirely).
fn identities_payload(session: &Endpoint) -> Result<Vec<u8>, String> {
    if session.is_locked() {
        return identities::encode_identities_answer(&[])
            .map_err(|e| format!("encode empty identities: {e}"));
    }
    let rows = Endpoint::list_rows().map_err(|e| format!("list rows: {e}"))?;
    let advertised = identities::build_advertised(&rows, identities::lookup_cert_from_db)
        .map_err(|e| format!("build advertised: {e}"))?;
    identities::encode_identities_answer(&advertised).map_err(|e| format!("encode: {e}"))
}

/// Encode a typed `Response` into wire bytes (without the leading
/// u32 length prefix). `ssh-agent-lib` has the `Encode` impl on
/// `Response`; we just call it into a `Vec<u8>`.
fn encode_typed_response(resp: &Response) -> Result<Vec<u8>, ssh_agent_lib::ssh_encoding::Error> {
    let mut out = Vec::with_capacity(resp.encoded_len()?);
    resp.encode(&mut out)?;
    Ok(out)
}

/// SSH_AGENT_FAILURE wire payload — message id `5`, no body. Returned
/// when any handler decision can't be expressed through the typed
/// path (decode failure, panic in handler, unsupported variant).
fn failure_payload() -> Vec<u8> {
    vec![5]
}

/// Write `payload` as a single agent frame: u32 big-endian length +
/// payload bytes. Flushes so the peer doesn't wait on TCP coalescing.
async fn write_frame<W>(writer: &mut W, payload: &[u8]) -> std::io::Result<()>
where
    W: AsyncWrite + Unpin,
{
    let len = u32::try_from(payload.len()).map_err(|_| {
        std::io::Error::other(format!("agent: reply too large ({} bytes)", payload.len()))
    })?;
    writer.write_all(&len.to_be_bytes()).await?;
    writer.write_all(payload).await?;
    writer.flush().await
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::duplex;

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

        // Prime the process singleton + an in-memory DB shared with
        // `Endpoint::list_rows`.
        let app = crate::app::init();
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        let db = Db::from_raw_for_tests(conn);

        const USER_PUB: &str = include_str!("test_fixtures/ed25519_user.pub");
        const USER_CERT: &[u8] = include_bytes!("test_fixtures/ed25519_cert.pub");

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
                    principals: "[]".into(),
                    critical_options: "{}".into(),
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
            let blob_len =
                u32::from_be_bytes(reply[cursor..cursor + 4].try_into().unwrap()) as usize;
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
}
