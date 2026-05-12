//! Cert-aware SSH_AGENT_IDENTITIES_ANSWER (msg id `12`) serialiser.
//!
//! Why this module exists at all: `ssh-agent-lib` 0.5 models the
//! `IDENTITIES_ANSWER` payload through `Vec<Identity>`, and each
//! `Identity` carries its public-key bytes as an `ssh_key::public::KeyData`
//! enum. That enum has variants for every bare public-key shape
//! OpenSSH ships (Ed25519, ECDSA, RSA, SK-Ed25519, SK-Ecdsa, DSA, an
//! opaque catch-all) **but no variant for an OpenSSH certificate**.
//! The opaque catch-all wraps its inner bytes in an extra
//! `string` length prefix, which doesn't match the on-wire shape of a
//! certificate (algo-name then nonce-string then inline key fields).
//! So we cannot route a cert through `Identity::encode` and have to
//! emit the bytes ourselves.
//!
//! Matching OpenSSH behaviour: `ssh-add cert.pub` runs
//! `ssh_add_identity_constrained` twice — once for the bare key and
//! again after `sshkey_to_certified` grafts the cert onto the key
//! handle. OpenSSH `ssh-agent`'s `process_add_identity` looks up
//! existing rows through `sshkey_equal`, which compares the full key
//! including the cert blob, so the bare and cert variants don't
//! collide — both end up in `idtab`. The result: `ssh-add -L` against
//! OpenSSH `ssh-agent` shows two entries per cert-paired key, and
//! cert-aware clients (OpenSSH 8+) prefer the cert form during
//! userauth while bare-only clients fall back to the public-key form.
//! This module emits both for the same reason.
//!
//! The serialiser is split out from `endpoint` so it can be tested
//! against fixture rows + cert blobs without spinning up the full
//! listener.

use ssh_agent_lib::ssh_encoding::{self, Encode};
use ssh_key::PublicKey;

use crate::db::ssh_key_certificates::{self, CertRecord};
use crate::db::ssh_keys::{AgentPolicy, SshKeyRow};
use crate::error::Error;
use crate::ssh_agent::backends::BackendKind;

/// Message-type byte the SSH agent draft assigns to
/// `SSH_AGENT_IDENTITIES_ANSWER`. See
/// [draft-miller-ssh-agent-14 §6.1](https://www.ietf.org/archive/id/draft-miller-ssh-agent-14.html#section-6.1).
pub(crate) const IDENTITIES_ANSWER_MSG_ID: u8 = 12;

/// One published identity — the bytes that go into the `key_blob`
/// `string` plus the human-readable comment. `key_blob` is the
/// SSH-wire-format public-key blob for a bare key OR the OpenSSH
/// certificate blob for a cert-paired key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Advertised {
    pub key_blob: Vec<u8>,
    pub comment: String,
}

/// Decide whether the listing path should publish this row at all.
/// Software rows leak plaintext PEM material through the agent socket
/// and are filtered out. `Deny`-policy rows are filtered out too so
/// listing does not disclose their existence to the external client
/// (information-disclosure tightening of the OpenSSH `ssh-add -c`
/// semantics).
fn row_is_publishable(row: &SshKeyRow) -> bool {
    BackendKind::from_row(row) != BackendKind::Software && row.agent_policy != AgentPolicy::Deny
}

/// Build the bare public-key wire blob for a row. The DB stores the
/// OpenSSH text (`ssh-ed25519 AAAA…`); we re-parse through `ssh-key`
/// and call `to_bytes()` to get the binary form ssh-agent puts on
/// the wire.
fn bare_key_blob(row: &SshKeyRow) -> Option<Vec<u8>> {
    let pk = PublicKey::from_openssh(&row.public_key).ok()?;
    pk.key_data().encoded_bytes().ok()
}

/// Convenience extension over `ssh_key::KeyData` so the call site
/// reads cleanly. `encode` returns the algorithm-prefixed bytes that
/// `Identity::encode` would have written via `encode_prefixed` — i.e.
/// the bytes that go inside the agent's `string key_blob`.
trait KeyDataEncodeBytes {
    fn encoded_bytes(&self) -> Result<Vec<u8>, ssh_encoding::Error>;
}

impl KeyDataEncodeBytes for ssh_key::public::KeyData {
    fn encoded_bytes(&self) -> Result<Vec<u8>, ssh_encoding::Error> {
        let mut out = Vec::with_capacity(self.encoded_len()?);
        self.encode(&mut out)?;
        Ok(out)
    }
}

/// Build the cert blob for a paired cert row. The DB stores the
/// OpenSSH text body (the `*-cert.pub` file contents). We re-parse
/// through `ssh_key::Certificate::from_openssh` and call `to_bytes()`
/// — the binary SSH-wire-format equivalent of the base64 body, which
/// is exactly the byte string `ssh-add -L` would print after the
/// cert algorithm name on a paired key.
///
/// Returns `None` when the stored cert text fails to parse — the
/// listing path skips it then so a corrupt cert row does not pull
/// the bare pubkey down with it. Logged at the call site.
fn cert_blob(rec: &CertRecord) -> Option<Vec<u8>> {
    let text = std::str::from_utf8(&rec.certificate).ok()?;
    let cert = ssh_key::Certificate::from_openssh(text.trim()).ok()?;
    cert.to_bytes().ok()
}

/// Compose the cert identity comment. OpenSSH `ssh-add -L` against a
/// cert-paired key shows the same comment the bare entry uses; we
/// match that so the Settings UI / external `ssh-add -l` view stays
/// readable.
fn cert_comment(row: &SshKeyRow) -> String {
    row.label.clone()
}

/// Build the published-identity list. Mirrors OpenSSH `ssh-agent`'s
/// listing shape: one entry per stored identity, certs and bares
/// counted separately when both exist on a cert-paired key.
///
/// Order: by `row.id` (caller's responsibility to pass a stable
/// listing) — within a row the bare key comes first, then the cert.
/// Cert-aware clients walk the list and pick the cert form on userauth;
/// bare-only clients pick the first match.
pub(crate) fn build_advertised<F>(
    rows: &[SshKeyRow],
    cert_lookup: F,
) -> Result<Vec<Advertised>, Error>
where
    F: Fn(&str) -> Result<Option<CertRecord>, Error>,
{
    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        if !row_is_publishable(row) {
            continue;
        }
        let Some(bare) = bare_key_blob(row) else {
            // Unparseable stored OpenSSH text — skip silently. The
            // key manager rejects malformed bodies at import.
            continue;
        };
        out.push(Advertised {
            key_blob: bare,
            comment: row.label.clone(),
        });
        if let Some(rec) = cert_lookup(&row.id)? {
            if let Some(blob) = cert_blob(&rec) {
                out.push(Advertised {
                    key_blob: blob,
                    comment: cert_comment(row),
                });
            }
            // Cert text that fails to parse falls through silently —
            // we already published the bare entry, the cert is a
            // nice-to-have on top.
        }
    }
    Ok(out)
}

/// DB-backed cert lookup used by the live endpoint. Split out so the
/// pure serialisation path stays test-friendly with closure stubs.
pub(crate) fn lookup_cert_from_db(key_id: &str) -> Result<Option<CertRecord>, Error> {
    let app = crate::app::instance();
    let db = app
        .db()
        .ok_or_else(|| Error::Db("ssh-agent: DB not initialised".into()))?;
    db.with_conn(|c| ssh_key_certificates::get(c, key_id))
}

/// Serialise the IDENTITIES_ANSWER message payload — the bytes that
/// follow the `u32 frame_len` prefix on the wire.
///
/// Wire shape per draft-miller-ssh-agent-14 §3.5:
/// ```text
/// byte    SSH_AGENT_IDENTITIES_ANSWER (12)
/// uint32  nkeys
/// repeat nkeys times:
///     string  key_blob
///     string  comment
/// ```
///
/// `string` is `u32 len || bytes`. Length prefixes are big-endian
/// (OpenSSH convention); `ssh_encoding`'s `Encode` for `Vec<u8>` /
/// `String` already emit that exact shape.
pub(crate) fn encode_identities_answer(
    advertised: &[Advertised],
) -> Result<Vec<u8>, ssh_encoding::Error> {
    // Pre-size the buffer when we can — every identity contributes
    // 8 bytes of length prefixes plus the blob + comment payloads.
    let mut payload_len: usize = 1 /* msg id */ + 4 /* nkeys */;
    for a in advertised {
        payload_len += 4 + a.key_blob.len();
        payload_len += 4 + a.comment.len();
    }
    let mut out = Vec::with_capacity(payload_len);

    IDENTITIES_ANSWER_MSG_ID.encode(&mut out)?;
    (advertised.len() as u32).encode(&mut out)?;
    for a in advertised {
        // `Vec<u8>::encode` writes the SSH `string` shape (u32 len
        // big-endian + bytes); same for `String::encode`. Reuse the
        // ssh_encoding impls so length-prefix discipline lives in
        // one place.
        a.key_blob.encode(&mut out)?;
        a.comment.encode(&mut out)?;
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::ssh_keys::KeyBackend;

    fn row(
        id: &str,
        backend: KeyBackend,
        public_key: &str,
        agent_policy: AgentPolicy,
    ) -> SshKeyRow {
        SshKeyRow {
            id: id.into(),
            label: format!("label-{id}"),
            private_key: "PEM".into(),
            public_key: public_key.into(),
            key_type: "sk-ssh-ed25519@openssh.com".into(),
            is_generated: false,
            created_at_ms: 0,
            credential_id: Some(vec![1, 2, 3]),
            application_string: Some("ssh:".into()),
            has_user_verification: false,
            agent_policy,
            backend,
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
        }
    }

    /// Ed25519 OpenSSH public-key text — the bare key the cert
    /// fixture below was signed against (`ssh-keygen -t ed25519`).
    /// Round-tripped through `PublicKey::from_openssh` in
    /// `bare_key_blob`.
    const ED25519_PUB: &str = include_str!("test_fixtures/ed25519_user.pub");

    /// OpenSSH cert text — `ssh-keygen -s ca -I user-id -n alice,bob
    /// -V always:forever user.pub` against the matching CA. Generated
    /// once and committed so the test does not re-run the signing
    /// flow each run; the bytes are the load-bearing shape, not the
    /// signing key.
    const ED25519_CERT: &[u8] = include_bytes!("test_fixtures/ed25519_cert.pub");

    #[test]
    fn build_skips_software_rows() {
        let r = row("a", KeyBackend::Software, ED25519_PUB, AgentPolicy::Ask);
        let out = build_advertised(&[r], |_| Ok(None)).unwrap();
        assert!(out.is_empty());
    }

    #[test]
    fn build_skips_deny_policy_rows() {
        let r = row("a", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Deny);
        let out = build_advertised(&[r], |_| Ok(None)).unwrap();
        assert!(out.is_empty());
    }

    #[test]
    fn build_emits_bare_when_no_cert_paired() {
        let r = row("a", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Ask);
        let out = build_advertised(&[r], |_| Ok(None)).unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].comment, "label-a");
        // The bare blob starts with the SSH wire-format algo string
        // — bytes 0..4 hold the algo-string length (big-endian).
        assert_eq!(&out[0].key_blob[0..4], &[0, 0, 0, 11]);
        assert_eq!(&out[0].key_blob[4..15], b"ssh-ed25519");
    }

    #[test]
    fn build_emits_bare_then_cert_when_paired() {
        let r = row("a", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Always);
        let lookup = |_key_id: &str| -> Result<Option<CertRecord>, Error> {
            Ok(Some(CertRecord {
                key_id: "a".into(),
                certificate: ED25519_CERT.to_vec(),
                valid_after: 0,
                valid_before: i64::MAX,
                principals: "[]".into(),
                critical_options: "{}".into(),
                fingerprint: "SHA256:fixture".into(),
            }))
        };
        let out = build_advertised(&[r], lookup).unwrap();
        assert_eq!(out.len(), 2);
        // First entry is the bare pubkey blob, second is the cert
        // blob. Cert blob starts with the cert algorithm string
        // (`ssh-ed25519-cert-v01@openssh.com`, 32 ascii bytes).
        let cert_algo = b"ssh-ed25519-cert-v01@openssh.com";
        assert_eq!(
            &out[1].key_blob[0..4],
            &(cert_algo.len() as u32).to_be_bytes()[..]
        );
        assert_eq!(&out[1].key_blob[4..4 + cert_algo.len()], cert_algo);
    }

    #[test]
    fn build_falls_back_to_bare_when_cert_text_unparseable() {
        // Corrupt cert text — the bare entry must survive even though
        // the cert blob slot drops.
        let r = row("a", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Always);
        let lookup = |_: &str| -> Result<Option<CertRecord>, Error> {
            Ok(Some(CertRecord {
                key_id: "a".into(),
                certificate: b"not a cert".to_vec(),
                valid_after: 0,
                valid_before: i64::MAX,
                principals: "[]".into(),
                critical_options: "{}".into(),
                fingerprint: "SHA256:nope".into(),
            }))
        };
        let out = build_advertised(&[r], lookup).unwrap();
        assert_eq!(out.len(), 1);
    }

    #[test]
    fn build_skips_row_with_unparseable_public_key() {
        let mut r = row("a", KeyBackend::Fido2, ED25519_PUB, AgentPolicy::Ask);
        r.public_key = "not openssh".into();
        let out = build_advertised(&[r], |_| Ok(None)).unwrap();
        assert!(out.is_empty());
    }

    #[test]
    fn encode_msg_id_and_count_match_wire_shape() {
        let bytes = encode_identities_answer(&[]).unwrap();
        assert_eq!(bytes[0], IDENTITIES_ANSWER_MSG_ID);
        // 4 bytes of big-endian zero for nkeys=0.
        assert_eq!(&bytes[1..5], &[0, 0, 0, 0]);
    }

    #[test]
    fn encode_writes_two_entries_with_correct_length_prefixes() {
        let entries = vec![
            Advertised {
                key_blob: vec![0xAA, 0xBB, 0xCC],
                comment: "first".into(),
            },
            Advertised {
                key_blob: vec![0x11, 0x22],
                comment: "snd".into(),
            },
        ];
        let bytes = encode_identities_answer(&entries).unwrap();
        // Header: msg_id + nkeys(=2).
        assert_eq!(bytes[0], IDENTITIES_ANSWER_MSG_ID);
        assert_eq!(&bytes[1..5], &[0, 0, 0, 2]);
        // First key_blob: u32(3) || 0xAA 0xBB 0xCC; then comment u32(5) || "first".
        assert_eq!(&bytes[5..9], &[0, 0, 0, 3]);
        assert_eq!(&bytes[9..12], &[0xAA, 0xBB, 0xCC]);
        assert_eq!(&bytes[12..16], &[0, 0, 0, 5]);
        assert_eq!(&bytes[16..21], b"first");
        // Second key_blob: u32(2) || 0x11 0x22; comment u32(3) || "snd".
        assert_eq!(&bytes[21..25], &[0, 0, 0, 2]);
        assert_eq!(&bytes[25..27], &[0x11, 0x22]);
        assert_eq!(&bytes[27..31], &[0, 0, 0, 3]);
        assert_eq!(&bytes[31..34], b"snd");
        assert_eq!(bytes.len(), 34);
    }
}
