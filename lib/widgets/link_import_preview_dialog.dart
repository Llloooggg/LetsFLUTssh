import 'package:flutter/material.dart';

import '../core/session/qr_codec.dart';
import '../core/session/qr_decoded_source.dart';
import '../features/settings/export_import.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'import_preview_dialog.dart';

/// Result from the link/QR import preview dialog.
typedef LinkImportPreviewResult = ({ImportMode mode, ExportOptions options});

/// Preview dialog for `letsflutssh://import?...` deep links and scanned QR
/// payloads.
///
/// Thin wrapper around [ImportPreviewDialog]: renders a link-title header
/// and reads counts off the unified [LfsPreview] shape (built from either
/// the Rust-staged handle's preview or the Dart fallback's
/// [ExportPayloadData]).
class LinkImportPreviewDialog extends StatelessWidget {
  final LfsPreview preview;

  const LinkImportPreviewDialog({super.key, required this.preview});

  /// Show the dialog from a unified [QrDecodedSource]. Either source
  /// projects into the same `LfsPreview` shape so one render path
  /// handles both Rust and Dart decode outcomes.
  static Future<LinkImportPreviewResult?> show(
    BuildContext context, {
    required QrDecodedSource source,
  }) async {
    return showFromPreview(context, preview: source.preview);
  }

  /// Show the dialog from a pre-built [LfsPreview]. Used by tests
  /// that construct a preview directly without going through the
  /// QR decoder.
  static Future<LinkImportPreviewResult?> showFromPreview(
    BuildContext context, {
    required LfsPreview preview,
  }) async {
    final selection = await ImportPreviewDialog.show(
      context,
      header: const _LinkHeader(),
      counts: _countsOf(preview),
    );
    if (selection == null) return null;
    return (mode: selection.mode, options: selection.options);
  }

  @override
  Widget build(BuildContext context) {
    return ImportPreviewDialog(
      header: const _LinkHeader(),
      counts: _countsOf(preview),
    );
  }

  static ImportPreviewCounts _countsOf(LfsPreview p) => (
    sessions: p.sessionCount,
    hasConfig: p.hasConfig,
    managerKeys: p.managerKeyCount,
    tags: p.tagCount,
    snippets: p.snippetCount,
    hasKnownHosts: p.hasKnownHosts,
  );
}

class _LinkHeader extends StatelessWidget {
  const _LinkHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.link, size: 16, color: AppTheme.fgDim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            S.of(context).pasteImportLinkTitle,
            style: AppFonts.inter(
              fontSize: AppFonts.md,
              fontWeight: FontWeight.w600,
              color: AppTheme.fg,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
