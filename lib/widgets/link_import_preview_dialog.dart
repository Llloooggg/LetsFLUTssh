import 'package:flutter/material.dart';

import '../core/session/qr_codec.dart';
import '../features/settings/export_import.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'import_preview_dialog.dart';

/// Result from the link/QR import preview dialog.
typedef LinkImportPreviewResult = ({ImportMode mode, ExportOptions options});

/// Preview dialog for `letsflutssh://import?...` deep links and scanned QR
/// payloads.
///
/// Thin wrapper around [ImportPreviewDialog]: renders a link-title header,
/// maps [ExportPayloadData] to the shared count record, and passes the
/// selection through unchanged (no extra result fields to carry).
class LinkImportPreviewDialog extends StatelessWidget {
  final ExportPayloadData payload;

  const LinkImportPreviewDialog({super.key, required this.payload});

  static Future<LinkImportPreviewResult?> show(
    BuildContext context, {
    required ExportPayloadData payload,
  }) async {
    final selection = await ImportPreviewDialog.show(
      context,
      header: const _LinkHeader(),
      counts: _countsOf(payload),
    );
    if (selection == null) return null;
    return (mode: selection.mode, options: selection.options);
  }

  @override
  Widget build(BuildContext context) {
    return ImportPreviewDialog(
      header: const _LinkHeader(),
      counts: _countsOf(payload),
    );
  }

  static ImportPreviewCounts _countsOf(ExportPayloadData p) => (
    sessions: p.sessions.length,
    hasConfig: p.hasConfig,
    managerKeys: p.managerKeys.length,
    tags: p.tags.length,
    snippets: p.snippets.length,
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
