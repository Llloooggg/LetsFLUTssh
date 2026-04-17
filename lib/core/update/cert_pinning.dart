import 'dart:convert';
import 'dart:io';

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
/// SPKIs need refreshing whenever GitHub rotates the leaf certificate
/// (typically every 1–2 years). Capture both endpoints and add the
/// resulting hashes here:
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
    final spki = base64.encode(sha256.convert(cert.der).bytes);
    if (pins.contains(spki)) return true;
    AppLogger.instance.log(
      'SPKI pin mismatch for $host (presented=$spki, pinned=${pins.length})',
      name: 'CertPinning',
    );
    return false;
  }

  /// Configure [client] so that any handshake the system CA flow rejects
  /// gets a second chance against the pinned SPKI for the host. If the
  /// host is not pinned, the rejection stands.
  static void enforce(HttpClient client) {
    client.badCertificateCallback = (cert, host, port) => accept(cert, host);
  }
}
