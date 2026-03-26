import 'dart:io';

/// Helper for detecting SSH key files.
/// Extracted from SessionEditDialog for testability.
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
}
