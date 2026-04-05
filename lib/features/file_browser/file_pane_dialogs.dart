import 'package:flutter/material.dart';

import '../../core/sftp/sftp_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/toast.dart';
import 'file_browser_controller.dart';

/// Shared dialogs for file pane operations (New Folder, Rename, Delete).
class FilePaneDialogs {
  FilePaneDialogs._();

  /// Show a text input dialog and return the entered value (or null).
  static Future<String?> _showTextInputDialog(
    BuildContext context, {
    required String title,
    required String label,
    required String confirmText,
    String initialValue = '',
  }) async {
    final nameCtrl = TextEditingController(text: initialValue);
    try {
      return await AppDialog.show<String>(
        context,
        builder: (ctx) => AppDialog(
          title: title,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppFonts.xs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppTheme.fgFaint,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.bg3,
                  isDense: true,
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
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
            ],
          ),
          actions: [
            AppDialogAction.cancel(onTap: () => Navigator.of(ctx).pop()),
            AppDialogAction.primary(
              label: confirmText,
              onTap: () => Navigator.of(ctx).pop(nameCtrl.text),
            ),
          ],
        ),
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  /// Show a dialog to create a new folder in [ctrl]'s current directory.
  static Future<void> showNewFolder(
    BuildContext context,
    FilePaneController ctrl,
  ) async {
    final result = await _showTextInputDialog(
      context,
      title: 'New Folder',
      label: 'Folder name',
      confirmText: 'Create',
    );

    if (result != null && result.isNotEmpty) {
      final path = '${ctrl.currentPath}/$result';
      try {
        await ctrl.fs.mkdir(path);
        await ctrl.refresh();
      } catch (e) {
        AppLogger.instance.log(
          'mkdir failed: $path: $e',
          name: 'FilePane',
          error: e,
        );
        if (context.mounted) {
          Toast.show(
            context,
            message: 'Failed to create folder: ${sanitizeError(e)}',
            level: ToastLevel.error,
          );
        }
      }
    }
  }

  /// Show a dialog to rename [entry] in [ctrl]'s current directory.
  static Future<void> showRename(
    BuildContext context,
    FilePaneController ctrl,
    FileEntry entry,
  ) async {
    final result = await _showTextInputDialog(
      context,
      title: 'Rename',
      label: 'New name',
      confirmText: 'Rename',
      initialValue: entry.name,
    );

    if (result != null && result.isNotEmpty && result != entry.name) {
      final newPath = '${ctrl.currentPath}/$result';
      try {
        await ctrl.fs.rename(entry.path, newPath);
        await ctrl.refresh();
      } catch (e) {
        AppLogger.instance.log(
          'Rename failed: ${entry.path} → $newPath: $e',
          name: 'FilePane',
          error: e,
        );
        if (context.mounted) {
          Toast.show(
            context,
            message: 'Failed to rename: ${sanitizeError(e)}',
            level: ToastLevel.error,
          );
        }
      }
    }
  }

  /// Show a confirmation dialog and delete [entries] from [ctrl].
  static Future<void> confirmDelete(
    BuildContext context,
    FilePaneController ctrl,
    List<FileEntry> entries,
  ) async {
    final names = entries.length == 1
        ? '"${entries.first.name}"'
        : '${entries.length} items';
    final confirmed = await AppDialog.show<bool>(
      context,
      builder: (ctx) => AppDialog(
        title: 'Delete',
        content: Text(
          'Delete $names?',
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
        ),
        actions: [
          AppDialogAction.cancel(onTap: () => Navigator.of(ctx).pop(false)),
          AppDialogAction.destructive(
            label: 'Delete',
            onTap: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final deleted = await _deleteEntries(context, ctrl, entries);
      await ctrl.refresh();
      if (context.mounted) {
        _showDeletedToast(context, entries, deleted);
      }
    }
  }

  static Future<int> _deleteEntries(
    BuildContext context,
    FilePaneController ctrl,
    List<FileEntry> entries,
  ) async {
    var deleted = 0;
    final errors = <String>[];
    for (final entry in entries) {
      try {
        await _deleteSingleEntry(ctrl, entry);
        deleted++;
      } catch (e) {
        AppLogger.instance.log(
          'Delete failed: ${entry.path}: $e',
          name: 'FilePane',
          error: e,
        );
        errors.add('Failed to delete ${entry.name}: $e');
      }
    }
    if (errors.isNotEmpty && context.mounted) {
      for (final msg in errors) {
        Toast.show(context, message: msg, level: ToastLevel.error);
      }
    }
    return deleted;
  }

  static Future<void> _deleteSingleEntry(
    FilePaneController ctrl,
    FileEntry entry,
  ) async {
    if (entry.isDir) {
      await ctrl.fs.removeDir(entry.path);
    } else {
      await ctrl.fs.remove(entry.path);
    }
  }

  static void _showDeletedToast(
    BuildContext context,
    List<FileEntry> entries,
    int deleted,
  ) {
    if (deleted > 0 && context.mounted) {
      final msg = deleted == 1
          ? 'Deleted ${entries.first.name}'
          : 'Deleted $deleted items';
      Toast.show(context, message: msg, level: ToastLevel.success);
    }
  }
}
