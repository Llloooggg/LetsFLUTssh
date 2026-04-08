import 'package:flutter/material.dart';

import '../../core/sftp/sftp_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/hover_region.dart';
import '../../widgets/sortable_header_cell.dart';

/// File extensions grouped by type for icon/color mapping.
const _imageExts = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'bmp',
  'svg',
  'webp',
  'ico',
  'tiff',
};
const _archiveExts = {
  'zip',
  'tar',
  'gz',
  'bz2',
  'xz',
  'rar',
  '7z',
  'tgz',
  'zst',
};
const _codeExts = {
  'dart',
  'js',
  'ts',
  'py',
  'go',
  'rs',
  'c',
  'cpp',
  'h',
  'java',
  'kt',
  'rb',
  'sh',
  'bash',
  'zsh',
  'yaml',
  'yml',
  'toml',
  'json',
  'xml',
  'html',
  'css',
  'scss',
  'md',
  'txt',
  'log',
  'conf',
  'cfg',
  'ini',
  'env',
  'sql',
  'swift',
  'tsx',
  'jsx',
};

String _ext(String name) =>
    name.contains('.') ? name.split('.').last.toLowerCase() : '';

/// Returns a file-type icon matching the mockup color scheme.
IconData fileIcon(FileEntry entry) {
  if (entry.isDir) {
    return Icons.folder;
  }
  final ext = _ext(entry.name);
  if (_imageExts.contains(ext)) {
    return Icons.image;
  }
  if (_archiveExts.contains(ext)) {
    return Icons.archive;
  }
  if (_codeExts.contains(ext)) {
    return Icons.description;
  }
  return Icons.insert_drive_file;
}

/// Returns a file-type icon color matching the mockup.
Color fileIconColor(FileEntry entry) {
  if (entry.isDir) {
    return AppTheme.folderIcon;
  }
  if (entry.name.startsWith('.')) {
    return AppTheme.fgFaint;
  }
  final ext = _ext(entry.name);
  if (_imageExts.contains(ext)) {
    return AppTheme.purple;
  }
  if (_archiveExts.contains(ext)) {
    return AppTheme.orange;
  }
  if (_codeExts.contains(ext)) {
    return AppTheme.green;
  }
  return AppTheme.blue;
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

    return HoverRegion(
      onTap: onTap,
      onCtrlTap: onCtrlTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
      builder: (hovered) => Container(
        height: AppTheme.controlHeightXs,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(color: _rowColor(hovered)),
        child: Row(children: _buildColumns(theme)),
      ),
    );
  }

  Color? _rowColor(bool hovered) {
    if (isSelected) return AppTheme.selection;
    if (hovered) return AppTheme.hover;
    return null;
  }

  List<Widget> _buildColumns(ThemeData theme) {
    final metaStyle = AppFonts.mono(
      fontSize: AppFonts.xs,
      color: AppTheme.fgFaint,
    );
    return [
      Icon(fileIcon(entry), size: 14, color: fileIconColor(entry)),
      const SizedBox(width: 6),
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
            formatTimestamp(entry.modTime),
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
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(text)],
    );
  }
}

/// Drag data with source pane identity to prevent same-pane drops.
class PaneDragData {
  final String sourcePaneId;
  final List<FileEntry> entries;
  const PaneDragData({required this.sourcePaneId, required this.entries});
}
