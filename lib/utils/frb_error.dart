/// Typed envelope for FRB error strings.
///
/// Every FRB API surfaces failures as `Result<T, String>`; new
/// callsites encode the error as JSON `{kind, detail}` so the Dart
/// side can switch on `kind` instead of substring-matching the
/// English `detail` text. Older callsites still emit plain strings;
/// the Rust-side parser [`rust_frb_err.frbErrorFromWire`] folds those
/// onto `kind = generic` so adoption is incremental — no flag day
/// required.
///
/// The grammar (envelope shape, fallback rules, control-character
/// handling) lives Rust-side in `lfs_frb::api::frb_err`. This Dart
/// class is a thin handle around the FRB-typed [`DbFrbError`] struct
/// so legacy call sites keep their `wire.kind` / `wire.isAuthFailed`
/// shape without a flag-day rename.
library;

import '../src/rust/api/frb_err.dart' as rust_frb_err;

class FrbError {
  /// Stable wire-name discriminator. Switch on this for UI
  /// routing — never on [detail].
  final String kind;

  /// Free-form detail; sanitized upstream by the log pipeline.
  /// Render via a localised template keyed by [kind] when surfacing
  /// to the user, never directly.
  final String detail;

  const FrbError({required this.kind, required this.detail});

  /// Parse an FRB error string. Delegates the grammar to the
  /// Rust-side [`frb_error_from_wire`] FRB sync helper — JSON
  /// envelopes land as `FrbError(kind, detail)`; non-JSON or
  /// malformed strings fall through to `kind = "generic"` with the
  /// original text as detail. Never throws on untrusted input.
  factory FrbError.fromWire(String wire) {
    final db = rust_frb_err.frbErrorFromWire(wire: wire);
    return FrbError(kind: db.kind, detail: db.detail);
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

  /// Hardware-vault on-disk envelope failed length-prefix sanity
  /// (truncated header, length out of range, JSON malformed). The
  /// caller MUST trigger the documented vault-reset cascade —
  /// recoverable backend errors (wrong PIN, missing file, TPM
  /// revoked) surface as the generic `kind == 'vault'` instead.
  bool get isVaultCorrupt => kind == 'vault_corrupt';

  /// Hardware vault unavailable on this host (Linux without TPM2,
  /// probe-rejected backend). Caller falls back to the
  /// master-password unlock; UI shows "hardware tier unavailable"
  /// rather than a security warning.
  bool get isVaultPlatformUnsupported => kind == 'vault_platform_unsupported';

  @override
  String toString() => detail.isEmpty ? '[$kind]' : '[$kind] $detail';
}
