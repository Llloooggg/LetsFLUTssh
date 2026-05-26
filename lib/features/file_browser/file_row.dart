import 'package:flutter/material.dart';

import '../../core/sftp/sftp_models.dart';
import '../../src/rust/api/sftp_models.dart' as rust_sftp_models;
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/core/hover_region.dart';
import '../../widgets/core/sortable_header_cell.dart';

/// Classify [entry] into a `DbFileKind`. The decision tree
/// (extension buckets, dir / symlink precedence) lives in
/// `lfs_core::sftp_models::file_kind`; Dart only renders the result.
/// `FileEntry` doesn't carry a symlink flag (the file panes resolve
/// symlinks on list), so `isSymlink` is always `false` here — the
/// dir / extension branches cover every row the table renders.
rust_sftp_models.DbFileKind _kind(FileEntry entry) => rust_sftp_models
    .sftpFileKind(name: entry.name, isDir: entry.isDir, isSymlink: false);

/// Returns a file-type icon for the entry's [rust_sftp_models.DbFileKind].
/// This map (kind → glyph) is a rendering concern and is the only
/// file-type decision that stays Dart-side.
IconData fileIcon(FileEntry entry) {
  switch (_kind(entry)) {
    case rust_sftp_models.DbFileKind.directory:
      return Icons.folder;
    case rust_sftp_models.DbFileKind.symlink:
      return Icons.link;
    case rust_sftp_models.DbFileKind.image:
      return Icons.image;
    case rust_sftp_models.DbFileKind.archive:
      return Icons.archive;
    case rust_sftp_models.DbFileKind.code:
      return Icons.description;
    case rust_sftp_models.DbFileKind.audio:
      return Icons.audiotrack;
    case rust_sftp_models.DbFileKind.video:
      return Icons.movie;
    case rust_sftp_models.DbFileKind.document:
      return Icons.article;
    case rust_sftp_models.DbFileKind.binary:
      return Icons.memory;
    case rust_sftp_models.DbFileKind.plain:
      return Icons.insert_drive_file;
  }
}

/// Returns a file-type icon color for the entry's kind. Dotfiles
/// (name starting with `.`) render faint regardless of kind — a
/// presentation rule that keeps hidden entries visually recessive.
Color fileIconColor(FileEntry entry) {
  final kind = _kind(entry);
  if (kind != rust_sftp_models.DbFileKind.directory &&
      entry.name.startsWith('.')) {
    return AppTheme.fgFaint;
  }
  switch (kind) {
    case rust_sftp_models.DbFileKind.directory:
      return AppTheme.folderIcon;
    case rust_sftp_models.DbFileKind.symlink:
      return AppTheme.fgFaint;
    case rust_sftp_models.DbFileKind.image:
      return AppTheme.purple;
    case rust_sftp_models.DbFileKind.archive:
      return AppTheme.orange;
    case rust_sftp_models.DbFileKind.code:
      return AppTheme.green;
    case rust_sftp_models.DbFileKind.audio:
    case rust_sftp_models.DbFileKind.video:
    case rust_sftp_models.DbFileKind.document:
    case rust_sftp_models.DbFileKind.binary:
    case rust_sftp_models.DbFileKind.plain:
      return AppTheme.blue;
  }
}

/// A single file row in the file browser list.

class FileRow extends StatelessWidget {
  final FileEntry entry;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCtrlTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset position) onContextMenu;
  final double sizeWidth;
  final double modifiedWidth;
  final double modeWidth;
  final double ownerWidth;
  final String? folderSizeText;

  const FileRow({
    super.key,
    required this.entry,
    required this.isSelected,
    this.sizeWidth = 55,
    this.modifiedWidth = 105,
    this.modeWidth = 65,
    this.ownerWidth = 50,
    this.folderSizeText,
    required this.onTap,
    required this.onCtrlTap,
    required this.onDoubleTap,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: entry.name,
      button: true,
      selected: isSelected,
      child: HoverRegion(
        onTap: onTap,
        onCtrlTap: onCtrlTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
        builder: (hovered) => Container(
          height: AppTheme.controlHeightXs,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(color: _rowColor(hovered)),
          child: Row(children: _buildColumns(theme, context)),
        ),
      ),
    );
  }

  Color? _rowColor(bool hovered) {
    if (isSelected) return AppTheme.selection;
    if (hovered) return AppTheme.hover;
    return null;
  }

  List<Widget> _buildColumns(ThemeData theme, BuildContext context) {
    final metaStyle = AppFonts.mono(
      fontSize: AppFonts.xs,
      color: AppTheme.fgFaint,
    );
    return [
      Icon(fileIcon(entry), size: 14, color: fileIconColor(entry)),
      const SizedBox(width: AppSpacing.xxs),
      Expanded(
        child: Tooltip(
          message: entry.name,
          waitDuration: const Duration(milliseconds: 600),
          child: Text(
            entry.name,
            style: AppFonts.mono(
              fontSize: AppFonts.sm,
              color: entry.isDir ? AppTheme.fg : AppTheme.fgDim,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      if (sizeWidth > 0) ...[
        columnDivider(),
        SizedBox(
          width: sizeWidth,
          child: Text(
            entry.isDir ? (folderSizeText ?? '') : formatSize(entry.size),
            style: metaStyle,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
      if (modifiedWidth > 0) ...[
        columnDivider(),
        SizedBox(
          width: modifiedWidth,
          child: Text(
            formatTimestamp(
              entry.modTime,
              locale: Localizations.localeOf(context),
            ),
            style: metaStyle,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
      if (modeWidth > 0) ...[
        columnDivider(),
        SizedBox(
          width: modeWidth,
          child: Text(
            entry.modeString,
            style: metaStyle,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
      if (ownerWidth > 0 && entry.owner.isNotEmpty) ...[
        columnDivider(),
        SizedBox(
          width: ownerWidth,
          child: Text(
            entry.owner,
            style: metaStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ];
  }
}

/// Row layout for popup menu items with icon + text.
class MenuRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const MenuRow({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    // `Flexible + ellipsis` keeps long-locale menu entries (Russian
    // "Переместить в корзину", German "In den Papierkorb
    // verschieben") from overflowing the popup-menu width when the
    // menu anchors near the right edge of a narrow file pane. The
    // menu itself grows its maxWidth from the caller; we add the
    // truncation safety net here instead of at every call site.
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Drag data with source pane identity to prevent same-pane drops.
class PaneDragData {
  final String sourcePaneId;
  final List<FileEntry> entries;
  const PaneDragData({required this.sourcePaneId, required this.entries});
}
