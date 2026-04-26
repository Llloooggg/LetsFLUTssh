import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/qr/qr_scanner.dart';
import '../core/session/qr_codec.dart';
import '../core/session/qr_decoded_source.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart' show localizeError;
import 'app_dialog.dart';

/// Dialog that accepts a `letsflutssh://import?d=...` URL or the raw
/// base64url payload, decodes it (Rust path via `qrImportOpen` first,
/// Dart `decodeImportUri` / `decodeExportPayload` as fallback), and
/// returns the unified [QrDecodedSource].
///
/// Intended as a camera-less alternative to QR scanning — the user copies
/// the deep link from the desktop QR export screen and pastes it here.
class PasteImportLinkDialog extends StatefulWidget {
  const PasteImportLinkDialog({super.key});

  /// Show the dialog and await the user's decoded payload, or `null` on
  /// cancel / invalid input.
  static Future<QrDecodedSource?> show(BuildContext context) {
    return AppDialog.show<QrDecodedSource>(
      context,
      builder: (_) => const PasteImportLinkDialog(),
    );
  }

  @override
  State<PasteImportLinkDialog> createState() => _PasteImportLinkDialogState();
}

class _PasteImportLinkDialogState extends State<PasteImportLinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Try the Rust decoder first — `qrImportOpen` accepts both the full
  /// `letsflutssh://import?d=...` URI and the raw base64url payload.
  /// Returns null on any FRB / parse failure; the caller then falls
  /// back to the Dart pipeline so existing tests keep working without
  /// the FRB native lib loaded.
  Future<QrDecodedSource?> _tryDecodeViaRust(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final result = await tryDecodeQrPayloadViaRust(trimmed);
    if (result == null) return null;
    return QrDecodedSource.rust(result);
  }

  /// Dart fallback. Accepts the full deep-link URI or the raw payload
  /// string (what `decodeExportPayload` produces).  Returns null when
  /// nothing parses — the dialog sets [_error] so the user can try
  /// again instead of silently dismissing. A valid-but-too-new payload
  /// bubbles up as [QrPayloadVersionTooNewException] so the caller can
  /// steer the user to update rather than retry.
  ExportPayloadData? _tryDecodeDart(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == 'letsflutssh') {
      final data = decodeImportUri(uri);
      if (data != null) return data;
    }
    return decodeExportPayload(trimmed);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (!mounted) return;
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    setState(() {
      _controller.text = text;
      _error = null;
    });
  }

  /// Launch the native QR scanner and, if it returns a decoded payload,
  /// submit the import straight away — the camera flow implies intent,
  /// and an extra tap would be noise.
  Future<void> _scanQr() async {
    final scanned = await scanQrCode();
    if (!mounted || scanned == null || scanned.isEmpty) return;
    _controller.text = scanned;
    unawaited(_submit());
  }

  Future<void> _submit() async {
    // Rust path first — production sees this when the FRB native lib
    // is loaded. Bytes (sessions, key PEMs) stay Rust-side under a
    // staged handle id; the Dart heap only sees the sanitised preview.
    final rustSource = await _tryDecodeViaRust(_controller.text);
    if (rustSource != null) {
      if (!mounted) return;
      Navigator.of(context).pop(rustSource);
      return;
    }
    // Dart fallback — flutter_test, fresh checkout without
    // `cargo build`, or the Rust decoder rejected the payload as
    // malformed. The Dart pipeline duplicates the parser well
    // enough to keep the test surface working.
    final ExportPayloadData? data;
    try {
      data = _tryDecodeDart(_controller.text);
    } on QrPayloadVersionTooNewException catch (e) {
      // Valid payload, just newer than this build — tell the user to
      // update instead of showing the generic "invalid link" error.
      if (!mounted) return;
      setState(() => _error = localizeError(S.of(context), e));
      return;
    }
    if (!mounted) return;
    if (data == null) {
      setState(() => _error = S.of(context).invalidImportLink);
      return;
    }
    Navigator.of(context).pop(QrDecodedSource.dart(data));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: s.pasteImportLinkTitle,
      maxWidth: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.pasteImportLinkDescription,
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            autofocus: true,
            style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fg),
            decoration: InputDecoration(
              hintText: 'letsflutssh://import?d=…',
              hintStyle: AppFonts.mono(
                fontSize: AppFonts.xs,
                color: AppTheme.fgFaint,
              ),
              filled: true,
              fillColor: AppTheme.bg3,
              isDense: true,
              errorText: _error,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.accent),
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => unawaited(_submit()),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              AppButton(
                label: s.pasteFromClipboard,
                icon: Icons.content_paste,
                onTap: _pasteFromClipboard,
                dense: true,
              ),
              if (Platform.isAndroid || Platform.isIOS)
                AppButton(
                  label: s.scanQrCode,
                  icon: Icons.qr_code_scanner,
                  onTap: _scanQr,
                  dense: true,
                ),
            ],
          ),
        ],
      ),
      actions: [
        AppButton.cancel(onTap: () => Navigator.of(context).pop()),
        AppButton.primary(
          label: s.importAction,
          onTap: () => unawaited(_submit()),
        ),
      ],
    );
  }
}
