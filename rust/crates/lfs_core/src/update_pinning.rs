//! SPKI (SubjectPublicKeyInfo) pinning for the auto-update HTTP client.
//!
//! Defence-in-depth on top of system-CA validation: the auto-update
//! channel pulls signed manifests + artefacts from
//! `api.github.com` / `objects.githubusercontent.com`, and a
//! compromise of a CA in the system trust store would otherwise
//! let an attacker substitute a forged certificate that the
//! Ed25519 signature verification (the load-bearing integrity
//! check) would still fail-closed against. Pinning the
//! SubjectPublicKeyInfo hash is the second wall.
//!
//! ## Why SPKI (not the full cert DER)
//!
//! Routine leaf rotations re-sign the same keypair — the SPKI
//! subtree (algorithm + public-key bits) stays byte-stable across
//! the rotation, so the pin survives a normal renewal without a
//! release. A genuine key rotation (rare, explicit) is the only
//! event that breaks the pin, and that's the case the
//! [`PINNED_HOSTS`] list is designed to handle (add the new pin,
//! ship a release that trusts both for one cycle, drop the old
//! pin).
//!
//! ## Pin map status
//!
//! Today [`PINNED_HOSTS`] is empty — the pinning verifier is
//! wired through to the TLS stack, so a populated entry takes
//! immediate effect, but no host is pinned by default. The
//! maintainer captures the live SPKI hash via:
//!
//! ```text
//! openssl s_client -connect <host>:443 -servername <host> < /dev/null 2>/dev/null \
//!   | openssl x509 -pubkey -noout \
//!   | openssl pkey -pubin -outform DER \
//!   | openssl dgst -sha256 -binary \
//!   | xxd -p -c 64
//! ```
//!
//! and pastes the 32-byte digest into [`PINNED_HOSTS`]. Empty
//! map = system-CA-only validation, same as today; populated map
//! = additional SPKI gate per host.
//!
//! ## Hand-rolled extractor
//!
//! [`extract_spki_der`] walks the X.509 DER structure
//! field-by-field rather than pulling in a full ASN.1 crate. The
//! cert structure is fixed and the walker only descends into
//! `tbsCertificate` to step over the seven leading fields and
//! return the bytes of `subjectPublicKeyInfo` as a slice. Walks
//! against malformed input fail-closed (`None`) so a
//! deliberately-broken cert can't crash the verifier.

use std::sync::Arc;

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature, CryptoProvider};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, Error as TlsError, RootCertStore, SignatureScheme};
use sha2::{Digest, Sha256};

/// One entry per pinned host. The verifier matches on exact
/// hostname (case-insensitive ASCII compare); wildcards aren't
/// supported because every relevant target (`api.github.com`,
/// `objects.githubusercontent.com`) is a fixed FQDN.
pub struct PinnedHost {
    pub host: &'static str,
    /// SHA-256 of the DER-encoded SubjectPublicKeyInfo subtree.
    pub spki_sha256: [u8; 32],
}

/// Active pin set. Empty today — the wiring is in place so a
/// future release can populate this without touching call sites.
pub static PINNED_HOSTS: &[PinnedHost] = &[];

/// Look up a hostname in [`PINNED_HOSTS`]. ASCII case-insensitive.
/// Returns the pin entry or `None` when the host isn't pinned.
pub fn pin_for(host: &str) -> Option<&'static PinnedHost> {
    PINNED_HOSTS
        .iter()
        .find(|p| p.host.eq_ignore_ascii_case(host))
}

/// SHA-256 of `spki_der`. Helper so call sites don't repeat the
/// digest boilerplate; the verifier compares this against the
/// pinned digest byte-for-byte.
pub fn sha256_of(spki_der: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(spki_der);
    hasher.finalize().into()
}

/// Extract the SubjectPublicKeyInfo DER subtree from an X.509
/// certificate's outer DER bytes. Returns `None` for any malformed
/// input — fail-closed; the verifier then rejects the connection.
///
/// Walks the structure:
///
/// ```text
/// Certificate ::= SEQUENCE {
///   tbsCertificate  TBSCertificate,
///   signatureAlg    AlgorithmIdentifier,
///   signatureValue  BIT STRING
/// }
///
/// TBSCertificate ::= SEQUENCE {
///   [0] EXPLICIT version DEFAULT v1,    -- present on v3 certs
///   serialNumber  INTEGER,
///   signature     AlgorithmIdentifier,
///   issuer        Name,
///   validity      Validity,
///   subject       Name,
///   subjectPublicKeyInfo SubjectPublicKeyInfo,  -- this
///   ...
/// }
/// ```
pub fn extract_spki_der(cert_der: &[u8]) -> Option<&[u8]> {
    // Outer Certificate SEQUENCE → step into.
    let (outer_inside, _) = take_sequence(cert_der, 0)?;
    // First child is tbsCertificate (SEQUENCE).
    let (tbs_inside, _) = take_sequence(cert_der, outer_inside)?;
    let mut cursor = tbs_inside;
    // Optional [0] EXPLICIT version — context-specific tag 0xa0.
    if cert_der.get(cursor)? == &0xa0 {
        cursor = skip_tlv(cert_der, cursor)?;
    }
    // serialNumber INTEGER
    cursor = skip_tlv(cert_der, cursor)?;
    // signature AlgorithmIdentifier (SEQUENCE)
    cursor = skip_tlv(cert_der, cursor)?;
    // issuer Name (SEQUENCE)
    cursor = skip_tlv(cert_der, cursor)?;
    // validity Validity (SEQUENCE)
    cursor = skip_tlv(cert_der, cursor)?;
    // subject Name (SEQUENCE)
    cursor = skip_tlv(cert_der, cursor)?;
    // subjectPublicKeyInfo SubjectPublicKeyInfo (SEQUENCE) — return
    // its full TLV bytes (not just the value), since the SHA-256
    // pin is taken over the *whole* SPKI subtree.
    let (_inside, end) = take_sequence(cert_der, cursor)?;
    Some(&cert_der[cursor..end])
}

/// Read a DER length at `offset`, return `(length, new_offset)`.
/// Supports short form (single byte 0..=0x7f) and long form
/// (0x80 | n_octets, then n_octets BE bytes). Caps at 4 length
/// octets — anything bigger is malformed for our cert sizes.
fn read_len(data: &[u8], offset: usize) -> Option<(usize, usize)> {
    let first = *data.get(offset)? as usize;
    if first < 0x80 {
        return Some((first, offset + 1));
    }
    let n_octets = first & 0x7f;
    if n_octets == 0 || n_octets > 4 {
        return None;
    }
    let mut len = 0usize;
    let mut o = offset + 1;
    for _ in 0..n_octets {
        len = (len << 8) | (*data.get(o)? as usize);
        o += 1;
    }
    Some((len, o))
}

/// At `offset`, expect a SEQUENCE tag (0x30); return
/// `(inside_offset, end_offset)` where `inside` points at the
/// first child byte and `end` is the byte just past the
/// sequence's value (i.e. where the next sibling starts).
fn take_sequence(data: &[u8], offset: usize) -> Option<(usize, usize)> {
    if *data.get(offset)? != 0x30 {
        return None;
    }
    let (len, after_len) = read_len(data, offset + 1)?;
    let end = after_len.checked_add(len)?;
    if end > data.len() {
        return None;
    }
    Some((after_len, end))
}

/// Skip a TLV at `offset` regardless of tag — return the offset
/// of the next sibling or `None` on malformed input.
fn skip_tlv(data: &[u8], offset: usize) -> Option<usize> {
    let _tag = *data.get(offset)?;
    let (len, after_len) = read_len(data, offset + 1)?;
    after_len.checked_add(len).filter(|end| *end <= data.len())
}

/// Custom `ServerCertVerifier` that wraps an inner system-CA
/// chain validator and additionally enforces the SPKI pin (when
/// the connecting hostname appears in [`PINNED_HOSTS`]).
///
/// Empty pin map → verifier is a transparent pass-through to the
/// inner WebPki verifier; security parity with the
/// pre-pinning configuration.
///
/// Populated pin map → end-entity SPKI is hashed and compared
/// against the pinned digest. Mismatch fails-closed with a
/// `TlsError::General`.
#[derive(Debug)]
pub struct LfsPinningVerifier {
    inner: Arc<dyn ServerCertVerifier>,
}

impl LfsPinningVerifier {
    /// Build the verifier with the workspace's bundled webpki-roots
    /// trust anchors as the inner chain validator. Returns `None`
    /// when the rustls crypto provider hasn't been installed yet
    /// (the default-provider install happens once at process
    /// startup; calling sites that build the client cold should
    /// `CryptoProvider::install_default(...)` first).
    pub fn build() -> Result<Arc<Self>, TlsError> {
        let provider = CryptoProvider::get_default()
            .cloned()
            .or_else(|| Some(Arc::new(rustls::crypto::ring::default_provider())))
            .ok_or_else(|| TlsError::General("no rustls crypto provider".to_string()))?;
        let mut roots = RootCertStore::empty();
        roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        let inner =
            rustls::client::WebPkiServerVerifier::builder_with_provider(Arc::new(roots), provider)
                .build()
                .map_err(|e| TlsError::General(format!("webpki verifier build: {e}")))?;
        Ok(Arc::new(Self { inner }))
    }
}

impl ServerCertVerifier for LfsPinningVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        server_name: &ServerName<'_>,
        ocsp_response: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, TlsError> {
        // 1. Inner chain validation — webpki + system trust roots.
        //    Non-negotiable; runs even when no pin is configured.
        self.inner.verify_server_cert(
            end_entity,
            intermediates,
            server_name,
            ocsp_response,
            now,
        )?;

        // 2. SPKI pin check — only fires for hostnames in
        //    PINNED_HOSTS. Wildcard / IP names are never pinned.
        let host_str = match server_name {
            ServerName::DnsName(d) => d.as_ref(),
            _ => return Ok(ServerCertVerified::assertion()),
        };
        let Some(pin) = pin_for(host_str) else {
            return Ok(ServerCertVerified::assertion());
        };
        let spki = extract_spki_der(end_entity.as_ref())
            .ok_or_else(|| TlsError::General(format!("SPKI extract failed for {host_str}")))?;
        let actual = sha256_of(spki);
        if actual != pin.spki_sha256 {
            return Err(TlsError::General(format!(
                "SPKI pin mismatch for {host_str}",
            )));
        }
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, TlsError> {
        verify_tls12_signature(
            message,
            cert,
            dss,
            &CryptoProvider::get_default()
                .cloned()
                .ok_or_else(|| TlsError::General("no rustls crypto provider".to_string()))?
                .signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, TlsError> {
        verify_tls13_signature(
            message,
            cert,
            dss,
            &CryptoProvider::get_default()
                .cloned()
                .ok_or_else(|| TlsError::General("no rustls crypto provider".to_string()))?
                .signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.inner.supported_verify_schemes()
    }
}

/// Build a `rustls::ClientConfig` wired to use
/// [`LfsPinningVerifier`] for cert validation. Used by
/// `update_http::build_client` to plug the pin gate into reqwest.
pub fn build_pinning_tls_config() -> Result<rustls::ClientConfig, TlsError> {
    // Ensure a default crypto provider is installed (idempotent —
    // `install_default` is a no-op once installed, and the call
    // returns Err if a different provider is already installed
    // which we ignore so a parent crate's selection wins).
    let _ = rustls::crypto::ring::default_provider().install_default();

    let verifier = LfsPinningVerifier::build()?;
    let config = rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_no_client_auth();
    Ok(config)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Self-signed X.509 v3 cert generated for testing only —
    /// 256-bit ECDSA over P-256, SAN `localhost`, no validity-period
    /// pin. Generated with:
    ///
    /// ```text
    /// openssl req -x509 -newkey ec:<(openssl ecparam -name prime256v1) \
    ///   -keyout /tmp/k.pem -out /tmp/c.pem -days 36500 -nodes \
    ///   -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost"
    /// openssl x509 -in /tmp/c.pem -outform DER | base64 -w 0
    /// ```
    const TEST_CERT_DER_B64: &str = "MIIBlTCCATugAwIBAgIUbAVdJo+Kv5nAFxtWxhlboPSBLiIwCgYIKoZIzj0EAwIwFDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MDUwMjIwMTM1MloYDzIxMjYwNDA4MjAxMzUyWjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARB/cbqJf+v71mtzD0vlSuOBYf3Lr09i6yOMOJoqhL2Hvdlvbfor6P35pJ7ykTw0ouChf34ehy8czPE+z19Aspxo2kwZzAdBgNVHQ4EFgQUAX1v2ZKA8hGWFZOc1ykqHx8EdGMwHwYDVR0jBBgwFoAUAX1v2ZKA8hGWFZOc1ykqHx8EdGMwDwYDVR0TAQH/BAUwAwEB/zAUBgNVHREEDTALgglsb2NhbGhvc3QwCgYIKoZIzj0EAwIDSAAwRQIgL9QhP32dDvMvc8U3ZYmMxAysJ27QBQiNrSgymTUHomYCIQCKjzjhaoETxbWxbxhjql/QHAZuDEA0n8k3/c3AokF3Sw==";

    fn decode_b64(s: &str) -> Vec<u8> {
        // Tiny base64 decoder — pulling in `base64` crate just for
        // this test would be wrong scope.
        const TBL: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut out = Vec::with_capacity(s.len() * 3 / 4);
        let bytes: Vec<u8> = s.bytes().filter(|b| *b != b'=').collect();
        let mut buf = 0u32;
        let mut bits = 0;
        for c in bytes {
            let i = TBL.iter().position(|&t| t == c).expect("valid b64") as u32;
            buf = (buf << 6) | i;
            bits += 6;
            if bits >= 8 {
                bits -= 8;
                out.push(((buf >> bits) & 0xff) as u8);
            }
        }
        out
    }

    #[test]
    fn extracts_spki_from_real_cert() {
        let cert = decode_b64(TEST_CERT_DER_B64);
        let spki = extract_spki_der(&cert).expect("SPKI extraction succeeds");
        // SubjectPublicKeyInfo is itself a SEQUENCE — must start
        // with the SEQUENCE tag.
        assert_eq!(spki[0], 0x30, "SPKI must start with SEQUENCE tag");
        // ECDSA P-256 SPKI is exactly 89 bytes (TLV-wrapped
        // AlgorithmIdentifier + 65-byte BIT STRING) — pinning a
        // known value here so an accidental drift in the walker
        // surfaces immediately.
        assert_eq!(spki.len(), 91, "SPKI length for ECDSA P-256");
    }

    #[test]
    fn spki_hash_is_stable() {
        let cert = decode_b64(TEST_CERT_DER_B64);
        let spki = extract_spki_der(&cert).unwrap();
        let h1 = sha256_of(spki);
        let h2 = sha256_of(spki);
        assert_eq!(h1, h2, "hash must be deterministic");
        // Hash is non-zero (sanity — hashing 91 random-ish bytes
        // can't yield 32 zero bytes).
        assert_ne!(h1, [0u8; 32]);
    }

    #[test]
    fn rejects_truncated_input() {
        let cert = decode_b64(TEST_CERT_DER_B64);
        for cut in [0, 1, 5, cert.len() / 2, cert.len() - 1] {
            assert!(
                extract_spki_der(&cert[..cut]).is_none(),
                "truncated cert (cut={cut}) must fail-closed"
            );
        }
    }

    #[test]
    fn rejects_garbage_tag() {
        // Replace the outer 0x30 with an invalid tag — walker
        // must refuse rather than misinterpret.
        let mut cert = decode_b64(TEST_CERT_DER_B64);
        cert[0] = 0xff;
        assert!(extract_spki_der(&cert).is_none());
    }

    #[test]
    fn rejects_oversize_length_octet_count() {
        // Long-form length with 5 size octets (we cap at 4).
        let bogus = [0x30, 0x85, 0x00, 0x00, 0x00, 0x00, 0x01];
        assert!(extract_spki_der(&bogus).is_none());
    }

    #[test]
    fn pin_for_returns_none_when_map_empty() {
        // Default config — no hosts pinned.
        assert!(pin_for("github.com").is_none());
        assert!(pin_for("objects.githubusercontent.com").is_none());
    }
}
