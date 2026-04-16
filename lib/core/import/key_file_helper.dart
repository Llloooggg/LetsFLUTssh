import 'dart:convert' show base64;
import 'dart:io';

import '../../utils/logger.dart';

/// Shared helpers for SSH key files on disk.
///
/// Centralises PEM detection, encryption-state classification, path safety
/// checks and basename extraction so that the OpenSSH-config importer, the
/// `~/.ssh` directory scanner and the settings file-picker all agree on the
/// same rules.
class KeyFileHelper {
  static const maxKeyFileSize = 32768;

  /// Try to read a file as a PEM private key.
  /// Returns the PEM content if the file looks like a private key, null otherwise.
  static String? tryReadPemKey(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      if (file.lengthSync() > maxKeyFileSize) return null;
      final content = file.readAsStringSync();
      if (content.contains('PRIVATE KEY')) return content;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Whether [pem] is a password-protected private key.
  ///
  /// Covers the three encoding families we care about:
  /// * Legacy PKCS#1/OpenSSL: carries `Proc-Type: 4,ENCRYPTED` + `DEK-Info`
  ///   headers inside the ASCII-armor envelope.
  /// * PKCS#8 encrypted: announced via its own armor header.
  /// * New OpenSSH format: the outer armor is the same
  ///   `-----BEGIN OPENSSH PRIVATE KEY-----` regardless of encryption, so we
  ///   decode the base64 body and read the KDF-name field out of the
  ///   `openssh-key-v1\0` binary prefix. `none` means unencrypted; anything
  ///   else (typically `bcrypt`) means a passphrase is required.
  static bool isEncryptedPem(String pem) {
    if (pem.contains('Proc-Type: 4,ENCRYPTED')) return true;
    if (pem.contains('DEK-Info:')) return true;
    if (pem.contains('-----BEGIN ENCRYPTED PRIVATE KEY-----')) return true;
    if (pem.contains('-----BEGIN OPENSSH PRIVATE KEY-----')) {
      return _isEncryptedOpensshKey(pem) ?? false;
    }
    return false;
  }

  /// Parse the base64 body of an OpenSSH private key and inspect its KDF
  /// name field. Returns `null` when the body does not decode as a valid
  /// openssh-key-v1 frame — treated by the caller as "can't tell, assume
  /// unencrypted" rather than false-positive-warning the user.
  ///
  /// Frame layout (big-endian):
  ///   `openssh-key-v1\0` | u32 kdfNameLen | kdfName | ... (rest)
  static bool? _isEncryptedOpensshKey(String pem) {
    try {
      final body = pem
          .split('\n')
          .where((l) => l.isNotEmpty && !l.startsWith('-----'))
          .join()
          .replaceAll(RegExp(r'\s'), '');
      if (body.isEmpty) return null;
      final decoded = base64.decode(body);
      const magic = 'openssh-key-v1';
      if (decoded.length < magic.length + 1 + 4) return null;
      for (var i = 0; i < magic.length; i++) {
        if (decoded[i] != magic.codeUnitAt(i)) return null;
      }
      if (decoded[magic.length] != 0) return null;
      const offset = 15; // magic (14) + null terminator
      final kdfLen =
          (decoded[offset] << 24) |
          (decoded[offset + 1] << 16) |
          (decoded[offset + 2] << 8) |
          decoded[offset + 3];
      // Sanity-check the length so a malformed frame can't make us read
      // gigabytes of garbage; a real KDF name is ≤ a dozen characters.
      if (kdfLen <= 0 || kdfLen > 32) return null;
      const start = offset + 4;
      if (decoded.length < start + kdfLen) return null;
      final name = String.fromCharCodes(decoded.sublist(start, start + kdfLen));
      return name != 'none';
    } catch (e) {
      AppLogger.instance.log(
        'OpenSSH body decode failed — treating as unencrypted',
        name: 'KeyFileHelper',
        error: e,
      );
      return null;
    }
  }

  /// Extract the filename portion of [path], normalising Windows separators.
  static String basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx < 0 ? normalized : normalized.substring(idx + 1);
  }

  /// Reject paths that contain `..` segments — a maliciously crafted
  /// `~/.ssh/config` could point `IdentityFile` at `~/../../etc/shadow` or
  /// similar, coercing an importer into reading sensitive files under the
  /// current user. Absolute paths the user wrote intentionally are still
  /// allowed — only traversal segments inside a path are rejected.
  static bool isSuspiciousPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    for (final segment in normalized.split('/')) {
      if (segment == '..') return true;
    }
    return false;
  }
}
