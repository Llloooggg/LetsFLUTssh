import 'dart:io';

import '../../src/rust/api/keys.dart' as rust_keys;
import '../../src/rust/api/path.dart' as rust_path;

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
  ///
  /// PPK files (PuTTY's `.ppk` format) are recognised here too — when
  /// the file looks like a PPK, the Rust core's `keys_import_ppk`
  /// (russh-keys' `from_ppk`) decodes it and re-encodes as OpenSSH
  /// PEM so the rest of the import path stays format-agnostic.
  /// Encrypted PPKs throw `PassphraseRequired` so the silent
  /// file-picker path returns null and the caller can route to the
  /// passphrase-aware key-manager flow.
  static Future<String?> tryReadPemKey(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      if (file.lengthSync() > maxKeyFileSize) return null;
      final content = file.readAsStringSync();
      if (_looksLikePpk(content)) {
        // Unencrypted only at this entry point — let the FRB call
        // throw and we map "passphrase required" to "not a key" for
        // the silent path.
        try {
          final km = await rust_keys.keysImportPpk(
            ppkText: content,
            passphrase: null,
            comment: '',
          );
          return km.privatePem;
        } catch (_) {
          // Encrypted / malformed / wrong passphrase / unsupported
          // algorithm — surface as "not a key" so the silent file
          // picker just refuses; the key-manager UI offers the full
          // passphrase-aware flow.
          return null;
        }
      }
      if (content.contains('PRIVATE KEY')) return content;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Quick sniff: does [text] look like a PPK file at all? Used by
  /// the import dispatcher to route .ppk before falling through to
  /// PEM detection. Cheap — first-line peek only. Routes through
  /// `lfs_core::keys::looks_like_ppk` so the v2 / v3 header set
  /// lives one place; falls back to the inline header check when
  /// the FRB native lib is not loaded.
  static bool _looksLikePpk(String text) {
    try {
      return rust_keys.keysLooksLikePpk(text: text);
    } catch (_) {
      final t = text.trimLeft();
      return t.startsWith('PuTTY-User-Key-File-2:') ||
          t.startsWith('PuTTY-User-Key-File-3:');
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
  ///
  /// Implementation lives Rust-side in `lfs_core::keys::is_encrypted_pem`
  /// so the OpenSSH-config importer, the `~/.ssh` directory scanner and
  /// the settings file picker all share one binary-format reader.
  static bool isEncryptedPem(String pem) =>
      rust_keys.keysIsEncryptedPem(pem: pem);

  /// Extract the filename portion of [path], normalising Windows
  /// separators. Routes through `lfs_core::path::basename` so the
  /// grammar lives one place; falls back to the inline scan when
  /// the FRB native lib is not loaded.
  static String basename(String path) {
    try {
      return rust_path.pathBasename(path: path);
    } catch (_) {
      final normalized = path.replaceAll('\\', '/');
      final idx = normalized.lastIndexOf('/');
      return idx < 0 ? normalized : normalized.substring(idx + 1);
    }
  }

  /// Reject paths that contain `..` segments — a maliciously crafted
  /// `~/.ssh/config` could point `IdentityFile` at `~/../../etc/shadow` or
  /// similar, coercing an importer into reading sensitive files under the
  /// current user. Absolute paths the user wrote intentionally are still
  /// allowed — only traversal segments inside a path are rejected.
  /// Routes through `lfs_core::path::is_suspicious_path` for one
  /// canonical traversal-detection grammar across the codebase.
  static bool isSuspiciousPath(String path) {
    try {
      return rust_path.pathIsSuspicious(path: path);
    } catch (_) {
      final normalized = path.replaceAll('\\', '/');
      for (final segment in normalized.split('/')) {
        if (segment == '..') return true;
      }
      return false;
    }
  }
}
