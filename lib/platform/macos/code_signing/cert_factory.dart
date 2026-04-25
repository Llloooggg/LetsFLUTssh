import 'dart:io';

import 'process_runner.dart';

/// Thrown when the cert-creation pipeline bails partway through — the
/// caller is expected to surface the error copy verbatim to the user.
class CertFactoryException implements Exception {
  final String stage;
  final String message;
  CertFactoryException(this.stage, this.message);
  @override
  String toString() => 'CertFactoryException($stage): $message';
}

/// A freshly-minted self-signed code-signing identity, ready to hand
/// off to `security import`. `p12Path` lives in [tmpDir] — the caller
/// must `tmpDir.deleteSync(recursive: true)` once import completes.
class GeneratedCertMaterial {
  final Directory tmpDir;
  final File crtPath;
  final File p12Path;
  final String p12Passphrase;
  GeneratedCertMaterial({
    required this.tmpDir,
    required this.crtPath,
    required this.p12Path,
    required this.p12Passphrase,
  });
}

/// Generates a user-owned self-signed code-signing certificate with
/// enough cert + key material for `security import` on macOS to
/// accept as a signing identity.
///
/// Why subprocess-based (not pure Dart / Rust): generating an X.509
/// v3 cert + PKCS#12 envelope is ~300 LOC of hand-rolled ASN.1 for
/// a code path used once per install. `/usr/bin/openssl` ships by
/// default on every macOS release we support and is already the
/// tool the prior bash `macos-resign.sh` used. When Apple eventually
/// drops `/usr/bin/openssl` (LibreSSL is deprecated in system) we
/// can swap to a Rust-based generator (`rcgen` covers v3 + PKCS#12).
/// The entry point below is the single seam.
///
/// Subject CN identifies the cert as a user-level signing identity;
/// the designated requirement derived from this cert is what the
/// macOS Keychain ACL will match against on every subsequent
/// `codesign` pass, so changing the CN invalidates every stored T1
/// secret — treat this string as a stable invariant across releases.
class CertFactory {
  static const String defaultCommonName = 'LetsFLUTssh Self-Sign';
  static const String defaultOrganisation = 'LetsFLUTssh';
  static const String _opensslPath = '/usr/bin/openssl';

  /// The passphrase protecting the PKCS#12 bundle. Kept in-memory
  /// and passed through `-passout pass:...` / `-P ...` on the
  /// subsequent `security import` call; macOS does not persist this
  /// value anywhere after import, so rotating it does not invalidate
  /// the imported identity.
  static const String _p12Passphrase = 'lfs-transient';

  final IProcessRunner runner;

  const CertFactory({this.runner = const SystemProcessRunner()});

  /// Produce `cert.crt` + `cert.p12` in a fresh tmp dir and return
  /// the paths. Caller must clean up [GeneratedCertMaterial.tmpDir]
  /// once `security import` has consumed the p12.
  ///
  /// Pipeline (matches the prior bash script's algorithm exactly):
  ///   1. Emit an OpenSSL config with `keyUsage = digitalSignature`
  ///      + `extendedKeyUsage = codeSigning` + `CA:FALSE`.
  ///   2. `openssl req -x509 -nodes -new -newkey rsa:2048 -days
  ///      3650` — self-signed cert + key, ten-year validity.
  ///   3. `openssl pkcs12 -export -legacy` — PKCS#12 bundle. The
  ///      `-legacy` flag is required because OpenSSL 3 defaults to
  ///      AES-256 + PBKDF2 for the MAC, which macOS
  ///      `SecKeychainItemImport` cannot parse ("MAC verification
  ///      failed during PKCS12 import"). The legacy provider emits
  ///      3DES / SHA1 MAC, which Keychain Services reads.
  Future<GeneratedCertMaterial> generate({
    String commonName = defaultCommonName,
    String organisation = defaultOrganisation,
    int validityDays = 3650,
  }) async {
    final tmp = Directory.systemTemp.createTempSync('lfs-macos-sign-');
    final cnfPath = File('${tmp.path}/cert.cnf');
    final keyPath = File('${tmp.path}/cert.key');
    final crtPath = File('${tmp.path}/cert.crt');
    final p12Path = File('${tmp.path}/cert.p12');

    cnfPath.writeAsStringSync(_opensslConfig(commonName, organisation));

    final reqRes = await runner.run(_opensslPath, [
      'req',
      '-x509',
      '-nodes',
      '-new',
      '-newkey',
      'rsa:2048',
      '-days',
      '$validityDays',
      '-config',
      cnfPath.path,
      '-extensions',
      'v3_req',
      '-keyout',
      keyPath.path,
      '-out',
      crtPath.path,
    ]);
    if (reqRes.exitCode != 0) {
      tmp.deleteSync(recursive: true);
      throw CertFactoryException(
        'openssl_req',
        'openssl x509 generation exited ${reqRes.exitCode}: '
            '${reqRes.stderr}',
      );
    }

    final p12Res = await runner.run(_opensslPath, [
      'pkcs12',
      '-export',
      '-legacy',
      '-in',
      crtPath.path,
      '-inkey',
      keyPath.path,
      '-out',
      p12Path.path,
      '-name',
      commonName,
      '-passout',
      'pass:$_p12Passphrase',
    ]);
    if (p12Res.exitCode != 0) {
      tmp.deleteSync(recursive: true);
      throw CertFactoryException(
        'openssl_pkcs12',
        'openssl pkcs12 -export -legacy exited ${p12Res.exitCode}: '
            '${p12Res.stderr}',
      );
    }

    return GeneratedCertMaterial(
      tmpDir: tmp,
      crtPath: crtPath,
      p12Path: p12Path,
      p12Passphrase: _p12Passphrase,
    );
  }

  static String _opensslConfig(String cn, String org) =>
      '''
[req]
distinguished_name = dn
prompt = no
req_extensions = v3_req
[dn]
CN = $cn
O  = $org
[v3_req]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:FALSE
''';
}
