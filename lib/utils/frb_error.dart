/// Typed envelope for FRB error strings.
///
/// Every FRB API surfaces failures as `Result<T, String>`; new
/// callsites encode the error as JSON `{kind, detail}` so the Dart
/// side can switch on `kind` instead of substring-matching the
/// English `detail` text. Older callsites still emit plain strings;
/// [`FrbError.fromWire`] falls back to `kind = generic` for those
/// so adoption is incremental — no flag day required.
///
/// Closes the substring-matching loop the audit found in
/// `lib/utils/format.dart` (auth-error / connect-error / sftp-error
/// classification by `msg.startsWith(...) / contains(...)`).
library;

import 'dart:convert';

class FrbError {
  /// Stable wire-name discriminator. Switch on this for UI
  /// routing — never on [detail].
  final String kind;

  /// Free-form detail; sanitized upstream by the log pipeline.
  /// Render via a localised template keyed by [kind] when surfacing
  /// to the user, never directly.
  final String detail;

  const FrbError({required this.kind, required this.detail});

  /// Parse an FRB error string. JSON-shaped envelopes land as
  /// `FrbError(kind, detail)`; plain strings (the legacy shape)
  /// fall through to `kind = "generic"` with the original text
  /// as detail. Invalid JSON also lands in the generic bucket.
  factory FrbError.fromWire(String wire) {
    if (wire.isEmpty) {
      return const FrbError(kind: 'generic', detail: '');
    }
    if (!wire.startsWith('{')) {
      return FrbError(kind: 'generic', detail: wire);
    }
    try {
      final decoded = jsonDecode(wire);
      if (decoded is Map &&
          decoded['kind'] is String &&
          decoded['detail'] is String) {
        return FrbError(
          kind: decoded['kind'] as String,
          detail: decoded['detail'] as String,
        );
      }
      return FrbError(kind: 'generic', detail: wire);
    } on FormatException {
      return FrbError(kind: 'generic', detail: wire);
    }
  }

  /// Lift any caught error into [FrbError]. FRB throws strings
  /// (the `Result<T, String>` shape); other thrown objects fall
  /// through to `kind = "generic"` with `toString()` as detail.
  factory FrbError.from(Object error) {
    if (error is FrbError) return error;
    if (error is String) return FrbError.fromWire(error);
    return FrbError(kind: 'generic', detail: error.toString());
  }

  bool get isCancelled => kind == 'cancelled';
  bool get isAuthFailed => kind == 'auth_failed';
  bool get isPassphraseRequired => kind == 'passphrase_required';
  bool get isPassphraseIncorrect => kind == 'passphrase_incorrect';
  bool get isHostKeyRejected => kind == 'host_key_rejected';
  bool get isTimeout => kind == 'timeout';

  @override
  String toString() => detail.isEmpty ? '[$kind]' : '[$kind] $detail';
}
