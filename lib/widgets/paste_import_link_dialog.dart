import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/qr/qr_scanner.dart';
import '../core/session/qr_decoded_source.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';

/// Dialog that accepts a `letsflutssh://import?d=...` URL or the raw
/// base64url payload, decodes it Rust-side via `qrImportOpen` (which
/// transparently handles both the full URI and the raw base64url
/// payload — the leading `letsflutssh://import?d=` is stripped
/// internally), and returns the staged [QrDecodedSource].
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

  /// Decode via Rust — `qrImportOpen` accepts both the full
  /// `letsflutssh://import?d=...` URI and the raw base64url payload
  /// (the leading wrapper is stripped internally). Returns null on
  /// any decode failure; the dialog surfaces a generic "invalid link"
  /// error so the user can try again.
  Future<QrDecodedSource?> _tryDecodeViaRust(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final result = await tryDecodeQrPayloadViaRust(trimmed);
    if (result == null) return null;
    return QrDecodedSource.rust(result);
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
    // Bytes (sessions, key PEMs) stay Rust-side under a staged handle
    // id; the Dart heap only sees the sanitised preview. The
    // version-too-new branch falls through to the generic error toast
    // — `qrImportOpen` already swallows that variant via the typed
    // dispatcher path; the standalone paste flow does not yet
    // re-raise the typed exception.
    final rustSource = await _tryDecodeViaRust(_controller.text);
    if (!mounted) return;
    if (rustSource == null) {
      setState(() => _error = S.of(context).invalidImportLink);
      return;
    }
    Navigator.of(context).pop(rustSource);
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
          const SizedBox(height: AppSpacing.md),
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
          const SizedBox(height: AppSpacing.sm),
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
