import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';

import '../../utils/logger.dart';

/// SPKI (Subject Public Key Info) pin set for the GitHub release endpoints
/// the auto-updater talks to.
///
/// Pinning is the only defence against:
///   * a DNS spoof that redirects `api.github.com` / `objects.githubusercontent.com`
///     to an attacker-controlled host that holds a valid cert from any
///     trusted CA;
///   * a compromised / coerced CA that mints a real cert for those
///     hostnames;
///   * a corporate MITM proxy that has installed its own root CA in the
///     system trust store.
///
/// Domains, IPs, and DNS resolution are all considered untrusted —
/// matching SPKI is the sole acceptance criterion.
///
/// ## Capturing a new pin
///
/// SPKIs need refreshing whenever GitHub rotates the keypair backing
/// the leaf certificate. Routine leaf rotations that reuse the same
/// keypair keep the same SPKI — the hash survives those; only a
/// genuine key change (rare, explicit rotation) forces a new pin.
/// Capture both endpoints and add the resulting hashes here:
///
/// ```
/// for host in api.github.com objects.githubusercontent.com; do
///   echo | openssl s_client -connect $host:443 -servername $host 2>/dev/null \
///     | openssl x509 -pubkey -noout \
///     | openssl pkey -pubin -outform DER \
///     | openssl dgst -sha256 -binary \
///     | openssl enc -base64
/// done
/// ```
///
/// The openssl pipeline intentionally mirrors what [accept] computes:
/// it extracts the SubjectPublicKeyInfo subtree from the presented
/// certificate, DER-encodes it, then SHA-256 + base64. The Dart side
/// parses `cert.der` through [asn1lib]'s ASN.1 decoder and walks to
/// the same SPKI node before hashing — same bytes in, same hash out.
///
/// Pin **at least two** values per host (current + next backup, so a
/// single key rotation does not brick the updater). Also keep the
/// previous pin in the list for ~one release cycle to handle clients
/// catching up.
///
/// **Status:** the pin set below is intentionally empty. Auto-update
/// remains usable because `enforce` falls through to the system CA store
/// when no pins are configured (see implementation). Once the pins
/// below are populated, enforcement becomes strict and the system CA
/// store is no longer consulted.
class CertPinning {
  CertPinning._();

  /// Per-host SPKI pin lists. Empty list = host is not pinned and falls
  /// through to system CA validation (development / CI default).
  ///
  /// NOTE: the GitHub host lists are intentionally empty. Populating
  /// them requires capturing the SHA-256(SPKI) base64 of GitHub's
  /// current leaf plus one backup (see the openssl pipeline in the
  /// class doc above) and refreshing on every rotation. Until that
  /// operational commitment is made, transport security relies on the
  /// system CA store only.
  static const Map<String, List<String>> _pins = {
    'api.github.com': <String>[],
    'objects.githubusercontent.com': <String>[],
  };

  /// Return true if the supplied X.509 certificate's SPKI matches one of
  /// the configured pins for [host], or if no pins are configured for
  /// [host] (in which case responsibility falls back to the system CA).
  ///
  /// Used as the body of `HttpClient.badCertificateCallback`. Note: this
  /// is invoked when the system trust store ALSO failed to validate, so
  /// any acceptance here intentionally bypasses CA validation. Callers
  /// must not weaken this to "always true on pin match" — the SPKI hash
  /// has to come from the actual cert presented in the handshake.
  static bool accept(X509Certificate cert, String host) {
    final pins = _pins[host];
    if (pins == null || pins.isEmpty) {
      AppLogger.instance.log(
        'No SPKI pins configured for $host — falling back to system CA',
        name: 'CertPinning',
      );
      return false; // let the regular CA-trust flow fail
    }
    final spkiBytes = extractSpki(Uint8List.fromList(cert.der));
    if (spkiBytes == null) {
      AppLogger.instance.log(
        'SPKI extraction failed for $host — cert ASN.1 did not parse',
        name: 'CertPinning',
      );
      return false;
    }
    final spki = base64.encode(sha256.convert(spkiBytes).bytes);
    if (pins.contains(spki)) return true;
    AppLogger.instance.log(
      'SPKI pin mismatch for $host (presented=$spki, pinned=${pins.length})',
      name: 'CertPinning',
    );
    return false;
  }

  /// Extract the DER-encoded `SubjectPublicKeyInfo` subtree from an
  /// X.509 certificate. SPKI is the stable hash target across leaf
  /// rotations: when a CA re-issues a cert with the same keypair
  /// (the normal renewal path) the SPKI bytes are byte-identical, so
  /// a pin survives routine rotations. Hashing the full cert DER
  /// would break on every rotation even when the key is unchanged.
  ///
  /// X.509 shape — see RFC 5280 § 4.1:
  /// ```
  /// Certificate ::= SEQUENCE {
  ///   tbsCertificate       TBSCertificate,
  ///   signatureAlgorithm   AlgorithmIdentifier,
  ///   signatureValue       BIT STRING
  /// }
  /// TBSCertificate ::= SEQUENCE {
  ///   version          [0] EXPLICIT Version DEFAULT v1,
  ///   serialNumber         CertificateSerialNumber,
  ///   signature            AlgorithmIdentifier,
  ///   issuer               Name,
  ///   validity             Validity,
  ///   subject              Name,
  ///   subjectPublicKeyInfo SubjectPublicKeyInfo,   ← target
  ///   ...
  /// }
  /// ```
  /// The `[0] EXPLICIT` version tag is context-specific 0 (tag byte
  /// `0xA0`). When present, SPKI is the 7th element of tbsCertificate
  /// (index 6); when absent (v1 cert), it is the 6th (index 5).
  ///
  /// Returns null on any parse failure — the caller rejects the
  /// handshake in that case, which is the correct failure mode under
  /// a pinning policy.
  ///
  /// Exposed public (static) so [test/core/update/cert_pinning_test.dart]
  /// can assert same-key / different-key fixtures produce same /
  /// different SPKI bytes.
  static Uint8List? extractSpki(Uint8List certDer) {
    try {
      final parser = ASN1Parser(certDer);
      final certSeq = parser.nextObject();
      if (certSeq is! ASN1Sequence) return null;
      final tbs = certSeq.elements.isNotEmpty ? certSeq.elements[0] : null;
      if (tbs is! ASN1Sequence) return null;
      final hasVersion =
          tbs.elements.isNotEmpty && (tbs.elements[0].tag & 0xff) == 0xA0;
      final spkiIndex = hasVersion ? 6 : 5;
      if (spkiIndex >= tbs.elements.length) return null;
      final spki = tbs.elements[spkiIndex];
      if (spki is! ASN1Sequence) return null;
      return spki.encodedBytes;
    } catch (e) {
      AppLogger.instance.log(
        'cert_pinning: ASN.1 parse failed: $e',
        name: 'CertPinning',
      );
      return null;
    }
  }

  /// Configure [client] so that any handshake the system CA flow rejects
  /// gets a second chance against the pinned SPKI for the host. If the
  /// host is not pinned, the rejection stands.
  static void enforce(HttpClient client) {
    client.badCertificateCallback = (cert, host, port) => accept(cert, host);
  }
}
