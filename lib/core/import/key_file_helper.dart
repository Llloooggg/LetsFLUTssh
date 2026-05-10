import '../../src/rust/api/keys.dart' as rust_keys;
import '../../src/rust/api/path.dart' as rust_path;

/// Shared helpers for SSH key files on disk.
///
/// Centralises PEM detection, encryption-state classification, path safety
/// checks and basename extraction so that the OpenSSH-config importer, the
/// `~/.ssh` directory scanner and the settings file-picker all agree on the
/// same rules.
class KeyFileHelper {
  /// Try to read a file as a PEM private key.
  /// Returns the PEM content if the file looks like a private key, null otherwise.
  ///
  /// PPK files (PuTTY's `.ppk` format) are recognised here too — when
  /// the file looks like a PPK, the Rust core decodes it (russh-keys
  /// `from_ppk`) and re-encodes as OpenSSH PEM so the rest of the
  /// import path stays format-agnostic. Encrypted PPKs collapse to
  /// `null` so the silent file-picker path returns "not a key" and
  /// the caller can route to the passphrase-aware key-manager flow.
  ///
  /// Routes through `lfs_core::keys::try_read_pem_from_path`, so the
  /// 32 KiB ceiling, the missing-file fallback, and the PPK / PEM
  /// detection all run Rust-side without the bytes ever reaching
  /// the Dart heap on the silent path.
  static Future<String?> tryReadPemKey(String path) =>
      rust_keys.keysTryReadPemFromPath(path: path);

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
  /// separators via `lfs_core::path::basename`.
  static String basename(String path) => rust_path.pathBasename(path: path);

  /// Reject paths that contain `..` segments — a maliciously crafted
  /// `~/.ssh/config` could point `IdentityFile` at `~/../../etc/shadow` or
  /// similar, coercing an importer into reading sensitive files under the
  /// current user. Absolute paths the user wrote intentionally are still
  /// allowed — only traversal segments inside a path are rejected.
  /// Routes through `lfs_core::path::is_suspicious_path` for one
  /// canonical traversal-detection grammar across the codebase.
  static bool isSuspiciousPath(String path) =>
      rust_path.pathIsSuspicious(path: path);
}
