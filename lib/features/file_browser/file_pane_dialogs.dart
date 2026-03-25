import 'package:flutter/material.dart';

import '../../core/sftp/sftp_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';
import 'file_browser_controller.dart';

/// Shared dialogs for file pane operations (New Folder, Rename, Delete).
class FilePaneDialogs {
  FilePaneDialogs._();

  /// Show a dialog to create a new folder in [ctrl]'s current directory.
  static Future<void> showNewFolder(BuildContext context, FilePaneController ctrl) async {
    final nameCtrl = TextEditingController();
    try {
      final result = await showDialog<String>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (ctx) => AlertDialog(
          title: const Text('New Folder'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Folder name'),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(nameCtrl.text),
              child: const Text('Create'),
            ),
          ],
        ),
      );

      if (result != null && result.isNotEmpty) {
        final path = '${ctrl.currentPath}/$result';
        try {
          await ctrl.fs.mkdir(path);
          await ctrl.refresh();
        } catch (e) {
          if (context.mounted) {
            Toast.show(context, message: 'Failed to create folder: $e', level: ToastLevel.error);
          }
        }
      }
    } finally {
      nameCtrl.dispose();
    }
  }

  /// Show a dialog to rename [entry] in [ctrl]'s current directory.
  static Future<void> showRename(BuildContext context, FilePaneController ctrl, FileEntry entry) async {
    final nameCtrl = TextEditingController(text: entry.name);
    try {
      final result = await showDialog<String>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New name'),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(nameCtrl.text),
              child: const Text('Rename'),
            ),
          ],
        ),
      );

      if (result != null && result.isNotEmpty && result != entry.name) {
        final newPath = '${ctrl.currentPath}/$result';
        try {
          await ctrl.fs.rename(entry.path, newPath);
          await ctrl.refresh();
        } catch (e) {
          if (context.mounted) {
            Toast.show(context, message: 'Failed to rename: $e', level: ToastLevel.error);
          }
        }
      }
    } finally {
      nameCtrl.dispose();
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
