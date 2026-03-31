import 'package:flutter/material.dart';

import '../../core/sftp/sftp_models.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
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
      return await showDialog<String>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(nameCtrl.text),
              child: Text(confirmText),
            ),
          ],
        ),
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  /// Show a dialog to create a new folder in [ctrl]'s current directory.
  static Future<void> showNewFolder(BuildContext context, FilePaneController ctrl) async {
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
        AppLogger.instance.log('mkdir failed: $path: $e', name: 'FilePane', error: e);
        if (context.mounted) {
          Toast.show(context, message: 'Failed to create folder: ${sanitizeError(e)}', level: ToastLevel.error);
        }
      }
    }
  }

  /// Show a dialog to rename [entry] in [ctrl]'s current directory.
  static Future<void> showRename(BuildContext context, FilePaneController ctrl, FileEntry entry) async {
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
        AppLogger.instance.log('Rename failed: ${entry.path} → $newPath: $e', name: 'FilePane', error: e);
        if (context.mounted) {
          Toast.show(context, message: 'Failed to rename: ${sanitizeError(e)}', level: ToastLevel.error);
        }
      }
    }
  }

  /// Show a confirmation dialog and delete [entries] from [ctrl].
  static Future<void> confirmDelete(BuildContext context, FilePaneController ctrl, List<FileEntry> entries) async {
    final names = entries.length == 1
        ? '"${entries.first.name}"'
        : '${entries.length} items';
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Delete $names?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.disconnected),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
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
        AppLogger.instance.log('Delete failed: ${entry.path}: $e', name: 'FilePane', error: e);
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

  static Future<void> _deleteSingleEntry(FilePaneController ctrl, FileEntry entry) async {
    if (entry.isDir) {
      await ctrl.fs.removeDir(entry.path);
    } else {
      await ctrl.fs.remove(entry.path);
    }
  }

  static void _showDeletedToast(BuildContext context, List<FileEntry> entries, int deleted) {
    if (deleted > 0 && context.mounted) {
      final msg = deleted == 1 ? 'Deleted ${entries.first.name}' : 'Deleted $deleted items';
      Toast.show(context, message: msg, level: ToastLevel.success);
    }
  }
}
