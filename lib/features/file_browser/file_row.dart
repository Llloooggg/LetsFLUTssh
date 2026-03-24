import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../core/sftp/sftp_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

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
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
          child: Row(
            children: [
              Icon(
                entry.isDir ? Icons.folder : Icons.insert_drive_file,
                size: 16,
                color: entry.isDir
                    ? AppTheme.folderColor(theme.brightness)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.name,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                entry.isDir ? '' : formatSize(entry.size),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                entry.modeString,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
