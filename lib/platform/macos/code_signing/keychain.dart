import 'dart:io';

import 'process_runner.dart';

/// Typed wrapper around the macOS `security` CLI.
///
/// Exposes only the calls the code-signing flow actually needs:
/// import an identity, look up an existing cert by common name, mark
/// a cert as trusted for codeSigning in the user trust domain, and
/// the mirror-image delete / untrust flow for a clean uninstall.
///
/// The wrapper is intentionally thin — macOS's trust model only
/// makes sense in terms of the underlying `security` primitives, so
/// abstracting them further would hide the moving parts the user
/// actually cares about (their login keychain gets modified, they
/// see a macOS password prompt once for trust-DB writes). Tests
/// inject a fake [IProcessRunner] and assert on argv composition.
class Keychain {
  static const String _securityPath = '/usr/bin/security';

  final IProcessRunner runner;

  /// Absolute path to the target keychain — defaults to the user's
  /// login keychain (`~/Library/Keychains/login.keychain-db`). Kept
  /// injectable so tests can aim at a scratch keychain without
  /// touching the caller's real one.
  final String keychainPath;

  Keychain({this.runner = const SystemProcessRunner(), String? keychainPath})
    : keychainPath =
          keychainPath ??
          '${Platform.environment['HOME']}/Library/Keychains/login.keychain-db';

  /// Returns `true` when a cert with [commonName] already exists in
  /// the target keychain. Used to make the cert-creation step
  /// idempotent — re-running the re-sign flow does not generate a
  /// second cert when one is already in place.
  Future<bool> hasCertificate(String commonName) async {
    final res = await runner.run(_securityPath, [
      'find-certificate',
      '-c',
      commonName,
      keychainPath,
    ]);
    return res.exitCode == 0;
  }

  /// Import a PKCS#12 bundle produced by [CertFactory] into the
  /// keychain. `-T /usr/bin/codesign` grants codesign silent access
  /// to the private key (no password prompt on every subsequent
  /// re-sign); `-T /usr/bin/security` grants silent access to the
  /// security CLI itself so the trust + delete flows don't prompt.
  Future<void> importPkcs12({
    required File p12Path,
    required String passphrase,
  }) async {
    final res = await runner.run(_securityPath, [
      'import',
      p12Path.path,
      '-k',
      keychainPath,
      '-P',
      passphrase,
      '-T',
      '/usr/bin/codesign',
      '-T',
      '/usr/bin/security',
    ]);
    if (res.exitCode != 0) {
      throw KeychainException(
        'import',
        'security import exited ${res.exitCode}: ${res.stderr}',
      );
    }
  }

  /// Add the cert to the user-domain trust database, scoped to
  /// `codeSign`. This is the *only* step in the whole pipeline that
  /// triggers a macOS password prompt — writing to the trust DB
  /// requires user authorization even within the user's own keychain.
  /// Errors surface verbatim so callers can detect "user hit Cancel"
  /// versus real failures.
  Future<void> addTrustedCert(File crtPath) async {
    final res = await runner.run(_securityPath, [
      'add-trusted-cert',
      '-r',
      'trustRoot',
      '-p',
      'codeSign',
      '-k',
      keychainPath,
      crtPath.path,
    ]);
    if (res.exitCode != 0) {
      throw KeychainException(
        'add-trusted-cert',
        'security add-trusted-cert exited ${res.exitCode}: ${res.stderr}',
      );
    }
  }

  /// Delete the cert-with-private-key identity pair. `delete-identity`
  /// sweeps both the cert and its matching private key in one call.
  Future<void> deleteIdentity(String commonName) async {
    await runner.run(_securityPath, [
      'delete-identity',
      '-c',
      commonName,
      keychainPath,
    ]);
  }

  /// Delete any straggling cert whose common name matches. Called
  /// after [deleteIdentity] — some historical bash `-legacy`
  /// imports left a lone cert without the private key attached, and
  /// `delete-identity` wouldn't sweep those.
  Future<void> deleteCertificate(String commonName) async {
    await runner.run(_securityPath, [
      'delete-certificate',
      '-c',
      commonName,
      keychainPath,
    ]);
  }
}

class KeychainException implements Exception {
  final String stage;
  final String message;
  KeychainException(this.stage, this.message);
  @override
  String toString() => 'KeychainException($stage): $message';
}
