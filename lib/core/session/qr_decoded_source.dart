import '../../features/settings/export_import.dart'
    show ExportImport, LfsPreview;
import '../../src/rust/api/archive.dart' as rust_archive;
import 'qr_codec.dart' show ExportPayloadData;

/// Outcome of decoding a `letsflutssh://import` deep-link or paste-
/// link payload. Either the Rust path succeeded (handle id +
/// sanitised preview registered in `AppState::imports`) or the Dart
/// fallback returned the legacy `ExportPayloadData` tree.
///
/// The unified shape lets `LinkImportPreviewDialog` render counts
/// from either source without caring which path the decoder took,
/// and lets `handleQrImport` dispatch the apply call to either
/// `applyOpenedHandle` (Rust) or `applyResultViaRust` (Dart).
sealed class QrDecodedSource {
  const QrDecodedSource();

  /// Rust-decoded payload — bytes stayed Rust-side; the Dart caller
  /// holds only the handle id + the sanitised preview.
  factory QrDecodedSource.rust(rust_archive.DbImportOpenResult result) =
      _QrRustSource;

  /// Dart-decoded fallback — the legacy `_decodePayload` pipeline
  /// returned a fully-walked `ExportPayloadData` tree. Production
  /// only reaches this path when the FRB native lib is unavailable
  /// (flutter_test, fresh checkout without `cargo build`).
  factory QrDecodedSource.dart(ExportPayloadData payload) = _QrDartSource;

  /// Preview shape consumed by `LinkImportPreviewDialog`. Mirrors
  /// the LFS archive preview surface so one dialog renders for
  /// both paths.
  LfsPreview get preview;
}

class _QrRustSource extends QrDecodedSource {
  final rust_archive.DbImportOpenResult result;
  const _QrRustSource(this.result);

  @override
  LfsPreview get preview => LfsPreview.fromRust(result.preview);
}

class _QrDartSource extends QrDecodedSource {
  final ExportPayloadData payload;
  const _QrDartSource(this.payload);

  @override
  LfsPreview get preview => LfsPreview(
    schemaVersion: ExportImport.currentSchemaVersion,
    sessionCount: payload.sessions.length,
    sessionLabels: [for (final s in payload.sessions) s.label],
    managerKeyCount: payload.managerKeys.length,
    tagCount: payload.tags.length,
    snippetCount: payload.snippets.length,
    emptyFoldersCount: payload.emptyFolders.length,
    hasConfig: payload.hasConfig,
    hasKnownHosts: payload.hasKnownHosts,
  );
}

/// Try to decode `uriOrPayload` Rust-side via `qrImportOpen`. Returns
/// the staged handle + preview on success, `null` on any FRB / decode
/// failure so the caller can fall back to the Dart pipeline.
Future<rust_archive.DbImportOpenResult?> tryDecodeQrPayloadViaRust(
  String uriOrPayload,
) async {
  try {
    return await rust_archive.qrImportOpen(payload: uriOrPayload);
  } catch (_) {
    return null;
  }
}

/// Internal helpers — exposed only so `handleQrImport` can pattern-
/// match on the concrete source type without adding a public visitor.
extension QrDecodedSourceMatch on QrDecodedSource {
  rust_archive.DbImportOpenResult? get asRust =>
      this is _QrRustSource ? (this as _QrRustSource).result : null;

  ExportPayloadData? get asDart =>
      this is _QrDartSource ? (this as _QrDartSource).payload : null;
}
