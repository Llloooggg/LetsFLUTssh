import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../core/sftp/sftp_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// File extensions grouped by type for icon/color mapping.
const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'svg', 'webp', 'ico', 'tiff'};
const _archiveExts = {'zip', 'tar', 'gz', 'bz2', 'xz', 'rar', '7z', 'tgz', 'zst'};
const _codeExts = {
  'dart', 'js', 'ts', 'py', 'go', 'rs', 'c', 'cpp', 'h', 'java',
  'kt', 'rb', 'sh', 'bash', 'zsh', 'yaml', 'yml', 'toml', 'json',
  'xml', 'html', 'css', 'scss', 'md', 'txt', 'log', 'conf', 'cfg',
  'ini', 'env', 'sql', 'swift', 'tsx', 'jsx',
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
Color fileIconColor(FileEntry entry, Brightness brightness) {
  if (entry.isDir) {
    return AppTheme.folderColor(brightness);
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

  const FileRow({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onCtrlTap,
    required this.onDoubleTap,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
      child: InkWell(
        onTap: () {
          if (HardwareKeyboard.instance.logicalKeysPressed
                  .contains(LogicalKeyboardKey.controlLeft) ||
              HardwareKeyboard.instance.logicalKeysPressed
                  .contains(LogicalKeyboardKey.controlRight)) {
            onCtrlTap();
          } else {
            onTap();
          }
        },
        onDoubleTap: onDoubleTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: isSelected ? AppTheme.selection : null,
          child: Row(
            children: [
              Icon(
                fileIcon(entry),
                size: 14,
                color: fileIconColor(entry, theme.brightness),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: Text(
                  entry.name,
                  style: AppFonts.mono(
                    fontSize: 11,
                    color: entry.isDir ? AppTheme.fg : AppTheme.fgDim,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  entry.isDir ? '' : formatSize(entry.size),
                  style: AppFonts.mono(fontSize: 10, color: AppTheme.fgFaint),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  formatTimestamp(entry.modTime),
                  style: AppFonts.mono(fontSize: 10, color: AppTheme.fgFaint),
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  entry.modeString,
                  style: AppFonts.mono(fontSize: 10, color: AppTheme.fgFaint),
                ),
              ),
              if (entry.owner.isNotEmpty)
                SizedBox(
                  width: 60,
                  child: Text(
                    entry.owner,
                    style: AppFonts.mono(fontSize: 10, color: AppTheme.fgFaint),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(text),
      ],
    );
  }
}

/// Paints a semi-transparent marquee selection rectangle.
class MarqueePainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  MarqueePainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);

    // Fill
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );

    // Border
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(MarqueePainter oldDelegate) {
    return start != oldDelegate.start || end != oldDelegate.end;
  }
}

/// Drag data with source pane identity to prevent same-pane drops.
class PaneDragData {
  final String sourcePaneId;
  final List<FileEntry> entries;
  const PaneDragData({required this.sourcePaneId, required this.entries});
}
