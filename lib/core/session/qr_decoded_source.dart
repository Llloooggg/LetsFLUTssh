import '../import/export_import.dart' show LfsPreview;
import '../../src/rust/api/archive.dart' as rust_archive;

/// Outcome of decoding a `letsflutssh://import` deep-link or paste-link
/// payload. The QR decoder runs Rust-side
/// (`lfs_core::qr_codec_decode::decode_payload`) and stages the
/// resulting `PendingImport` under a handle id in
/// `AppState::imports`; the Dart caller holds only the handle id +
/// the sanitised preview while the user confirms the import in
/// `LinkImportPreviewDialog`.
class QrDecodedSource {
  final rust_archive.DbImportOpenResult rust;

  const QrDecodedSource.rust(this.rust);

  /// Preview shape consumed by `LinkImportPreviewDialog`. Mirrors
  /// the LFS archive preview surface so one dialog renders for both
  /// `.lfs` and QR / paste-link sources.
  LfsPreview get preview => LfsPreview.fromRust(rust.preview);
}

/// Try to decode `uriOrPayload` Rust-side via `qrImportOpen`. Returns
/// the staged handle + preview on success, `null` on any FRB / decode
/// failure. The Rust call accepts both the full
/// `letsflutssh://import?d=...` URI and the raw base64url payload.
Future<rust_archive.DbImportOpenResult?> tryDecodeQrPayloadViaRust(
  String uriOrPayload,
) async {
  try {
    return await rust_archive.qrImportOpen(payload: uriOrPayload);
  } catch (_) {
    return null;
  }
}
