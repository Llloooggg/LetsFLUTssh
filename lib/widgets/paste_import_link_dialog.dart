import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/qr/qr_scanner.dart';
import '../core/session/qr_codec.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';

/// Dialog that accepts a `letsflutssh://import?d=...` URL or the raw
/// base64url payload, decodes it via [decodeImportUri] /
/// [decodeExportPayload], and returns the parsed [ExportPayloadData].
///
/// Intended as a camera-less alternative to QR scanning — the user copies
/// the deep link from the desktop QR export screen and pastes it here.
class PasteImportLinkDialog extends StatefulWidget {
  const PasteImportLinkDialog({super.key});

  /// Show the dialog and await the user's decoded payload, or `null` on
  /// cancel / invalid input.
  static Future<ExportPayloadData?> show(BuildContext context) {
    return AppDialog.show<ExportPayloadData>(
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

  /// Decode the pasted text.  Accepts the full deep-link URI or the raw
  /// payload string (what `decodeExportPayload` produces).  Returns null
  /// when nothing parses — the dialog sets [_error] so the user can try
  /// again instead of silently dismissing.
  ExportPayloadData? _tryDecode(String raw) {
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
    _submit();
  }

  void _submit() {
    final data = _tryDecode(_controller.text);
    if (data == null) {
      setState(() => _error = S.of(context).invalidImportLink);
      return;
    }
    Navigator.of(context).pop(data);
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
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.content_paste, size: 16),
                label: Text(s.pasteFromClipboard),
                onPressed: _pasteFromClipboard,
              ),
              if (Platform.isAndroid || Platform.isIOS)
                TextButton.icon(
                  icon: const Icon(Icons.qr_code_scanner, size: 16),
                  label: Text(s.scanQrCode),
                  onPressed: _scanQr,
                ),
            ],
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.of(context).pop()),
        AppDialogAction.primary(label: s.importAction, onTap: _submit),
      ],
    );
  }
}
