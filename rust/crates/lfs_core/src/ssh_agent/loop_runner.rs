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
//! inline cert fields, no extra length prefix in between). The same
//! mismatch hits SIGN_REQUEST: `SignRequest::decode` calls
//! `reader.read_prefixed(KeyData::decode)` and the cert blob fails
//! the inner length check, so the typed sign path can never receive a
//! cert `key_blob` either.
//!
//! Bypassing `listen` keeps the Session trait surface intact (tests +
//! every non-cert verb still rely on it) while letting
//! `RequestIdentities` emit hand-crafted bytes through
//! [`identities::encode_identities_answer`] and letting cert-bearing
//! SIGN_REQUEST frames route through [`Endpoint::run_sign`] after we
//! resolve the row by the bare key blob embedded in the certificate.
//! Bare-key SIGN_REQUEST frames stay on the typed path.
//!
//! ## Wire framing
//!
//! Each agent message is framed as `uint32 length || bytes`. The
//! `bytes` slice starts with a single `uint8` message-type byte and is
//! followed by a per-type payload. See
//! [draft-miller-ssh-agent-14 §3](https://www.ietf.org/archive/id/draft-miller-ssh-agent-14.html#section-3).
//! We read framed bytes via `read_exact`, peek the type byte, and
//! route through one of three arms:
//!
//! - msg id 11 (REQUEST_IDENTITIES) — cert-aware listing path.
//! - msg id 13 (SIGN_REQUEST) — peek the `key_blob` algorithm string;
//!   if it ends in `-cert-v01@openssh.com` the cert path resolves the
//!   row by the bare pubkey embedded in the cert and dispatches
//!   through [`Endpoint::run_sign`]. Otherwise fall through to the
//!   typed path.
//! - any other id — typed path via `Session::handle`.

use ssh_agent_lib::agent::Session;
use ssh_agent_lib::proto::message::{Request, Response};
use ssh_agent_lib::ssh_encoding::{Decode, Encode};
use ssh_key::public::KeyData;
use ssh_key::Certificate;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use crate::ssh_agent::endpoint::Endpoint;
use crate::ssh_agent::identities;

/// SSH agent protocol message-type byte for
/// `SSH_AGENTC_REQUEST_IDENTITIES`. See
/// [draft-miller-ssh-agent-14 §6.1](https://www.ietf.org/archive/id/draft-miller-ssh-agent-14.html#section-6.1).
const REQUEST_IDENTITIES_MSG_ID: u8 = 11;

/// SSH agent protocol message-type byte for `SSH_AGENTC_SIGN_REQUEST`.
/// See [draft-miller-ssh-agent-14 §3.6](https://www.ietf.org/archive/id/draft-miller-ssh-agent-14.html#section-3.6).
const SIGN_REQUEST_MSG_ID: u8 = 13;

/// SSH agent protocol message-type byte for `SSH_AGENT_SIGN_RESPONSE`.
/// Wire body is `string signature` where `signature` follows the
/// OpenSSH userauth shape `string algorithm || string sig_blob`. The
/// algorithm is always the bare key's algorithm — verified against
/// OpenSSH `ssh_ed25519_encode_store_sig` and siblings: every
/// per-type sign callback writes the bare algorithm name regardless of
/// whether the lookup key was a cert. The cert blob discriminator only
/// selects the identity; the response carries the bare-key signature.
const SIGN_RESPONSE_MSG_ID: u8 = 14;

/// Suffix every OpenSSH cert-form algorithm string ends with. The
/// SIGN_REQUEST cert-detection peek matches against this so we don't
/// pay the cost of a full cert decode on every bare-key sign.
const CERT_ALGORITHM_SUFFIX: &str = "-cert-v01@openssh.com";

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
    if msg_id == SIGN_REQUEST_MSG_ID {
        if let Some(reply) = try_sign_with_cert(session, &payload[1..]).await {
            return reply;
        }
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

/// Cert-aware SIGN_REQUEST arm. `body` is the SIGN_REQUEST payload
/// after the msg-id byte: `string key_blob || string data || uint32 flags`.
///
/// Returns:
/// - `Some(bytes)` with a fully-framed SIGN_RESPONSE or FAILURE
///   payload when the request is a cert-form sign — caller writes
///   the bytes back verbatim.
/// - `None` when the `key_blob` is NOT a cert; caller falls through
///   to the typed `Session::handle` path.
async fn try_sign_with_cert(session: &mut Endpoint, body: &[u8]) -> Option<Vec<u8>> {
    let mut reader: &[u8] = body;
    let key_blob = Vec::<u8>::decode(&mut reader).ok()?;
    if !is_cert_algorithm(&key_blob) {
        return None;
    }
    let data = match Vec::<u8>::decode(&mut reader) {
        Ok(v) => v,
        Err(e) => {
            crate::app_log_warn!("SshAgent", "sign-cert: data decode: {e}");
            return Some(failure_payload());
        }
    };
    let flags = match u32::decode(&mut reader) {
        Ok(v) => v,
        Err(e) => {
            crate::app_log_warn!("SshAgent", "sign-cert: flags decode: {e}");
            return Some(failure_payload());
        }
    };
    Some(sign_cert_request(session, &key_blob, &data, flags).await)
}

/// Peek the leading `string` of a `key_blob` and report whether the
/// algorithm name ends in `-cert-v01@openssh.com`. Cheap — reads at
/// most the first `u32 len + 32` bytes and never allocates.
fn is_cert_algorithm(key_blob: &[u8]) -> bool {
    if key_blob.len() < 4 {
        return false;
    }
    let algo_len = u32::from_be_bytes(key_blob[0..4].try_into().expect("4 bytes")) as usize;
    if 4 + algo_len > key_blob.len() {
        return false;
    }
    let algo_bytes = &key_blob[4..4 + algo_len];
    match std::str::from_utf8(algo_bytes) {
        Ok(s) => s.ends_with(CERT_ALGORITHM_SUFFIX),
        Err(_) => false,
    }
}

/// Sign a cert-form SIGN_REQUEST. Returns the SIGN_RESPONSE wire
/// payload (msg id 14 + `string signature`) on success or a
/// SSH_AGENT_FAILURE payload on any failure mode.
///
/// Steps:
/// 1. Parse `key_blob` as an OpenSSH certificate via
///    [`ssh_key::Certificate::from_bytes`].
/// 2. Extract the underlying bare [`KeyData`] from the cert.
/// 3. Find the matching `ssh_keys` row via
///    [`Endpoint::find_row_by_keydata`] — same equality check the
///    typed bare-key path uses.
/// 4. Dispatch through [`Endpoint::run_sign`] which runs the
///    per-key policy gate and the backend signer, then encode the
///    resulting [`ssh_key::Signature`] as SSH_AGENT_SIGN_RESPONSE.
async fn sign_cert_request(
    session: &mut Endpoint,
    key_blob: &[u8],
    data: &[u8],
    flags: u32,
) -> Vec<u8> {
    let cert = match Certificate::from_bytes(key_blob) {
        Ok(c) => c,
        Err(e) => {
            crate::app_log_warn!("SshAgent", "sign-cert: cert decode: {e}");
            return failure_payload();
        }
    };
    let bare: &KeyData = cert.public_key();
    let row = match Endpoint::find_row_by_keydata(bare) {
        Ok(Some(r)) => r,
        Ok(None) => {
            crate::app_log_warn!("SshAgent", "sign-cert: no row matches cert pubkey");
            return failure_payload();
        }
        Err(e) => {
            crate::app_log_warn!("SshAgent", "sign-cert: row lookup: {e}");
            return failure_payload();
        }
    };
    let sig = match session.run_sign(row, data, flags).await {
        Ok(s) => s,
        Err(e) => {
            crate::app_log_warn!("SshAgent", "sign-cert: backend dispatch: {e}");
            return failure_payload();
        }
    };
    encode_sign_response(&sig).unwrap_or_else(|e| {
        crate::app_log_warn!("SshAgent", "sign-cert: response encode: {e}");
        failure_payload()
    })
}

/// Compose the SIGN_RESPONSE wire payload: msg id 14 followed by a
/// length-prefixed `Signature` (which itself is `string algorithm ||
/// string sig_blob`). Mirrors the typed `Response::SignResponse`
/// shape — see ssh-agent-lib `proto/message/response.rs` —
/// constructed by hand because the cert path doesn't synthesise a
/// `Response` enum value.
fn encode_sign_response(
    sig: &ssh_key::Signature,
) -> Result<Vec<u8>, ssh_agent_lib::ssh_encoding::Error> {
    let inner_len = sig.encoded_len()?;
    let mut out = Vec::with_capacity(1 + 4 + inner_len);
    out.push(SIGN_RESPONSE_MSG_ID);
    sig.encode_prefixed(&mut out)?;
    Ok(out)
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
#[path = "../../tests/unit/ssh_agent_loop_runner.rs"]
mod tests;
