import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/session/qr_codec.dart';
import '../features/settings/export_import.dart';
import '../theme/app_theme.dart';
import 'import_preview_dialog.dart';

/// Result from the LFS import preview dialog.
///
/// The master password is NOT part of this result — the caller must have
/// already decrypted the archive to build the [LfsPreview], so it already
/// has the password in hand.
typedef LfsImportPreviewResult = ({
  String filePath,
  ImportMode mode,
  ExportOptions options,
});

/// Preview dialog for a decrypted `.lfs` archive.
///
/// Thin wrapper around [ImportPreviewDialog]: renders the archive filename as
/// the header, maps [LfsPreview] fields to the shared count record, and
/// packages the shared selection into a result that also carries the
/// [filePath] so the caller can hand it back to `ImportService` without
/// bookkeeping.
class LfsImportPreviewDialog extends StatelessWidget {
  final String filePath;
  final LfsPreview preview;

  const LfsImportPreviewDialog({
    super.key,
    required this.filePath,
    required this.preview,
  });

  /// Show the dialog and return the result.
  static Future<LfsImportPreviewResult?> show(
    BuildContext context, {
    required String filePath,
    required LfsPreview preview,
  }) async {
    final selection = await ImportPreviewDialog.show(
      context,
      header: _ArchiveHeader(filePath: filePath),
      counts: (
        sessions: preview.sessions.length,
        hasConfig: preview.hasConfig,
        managerKeys: preview.managerKeyCount,
        tags: preview.tagCount,
        snippets: preview.snippetCount,
        hasKnownHosts: preview.hasKnownHosts,
      ),
    );
    if (selection == null) return null;
    return (
      filePath: filePath,
      mode: selection.mode,
      options: selection.options,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ImportPreviewDialog(
      header: _ArchiveHeader(filePath: filePath),
      counts: (
        sessions: preview.sessions.length,
        hasConfig: preview.hasConfig,
        managerKeys: preview.managerKeyCount,
        tags: preview.tagCount,
        snippets: preview.snippetCount,
        hasKnownHosts: preview.hasKnownHosts,
      ),
    );
  }
}

class _ArchiveHeader extends StatelessWidget {
  final String filePath;

  const _ArchiveHeader({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.archive_outlined, size: 16, color: AppTheme.fgDim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            p.basename(filePath),
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
