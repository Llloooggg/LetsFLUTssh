import 'dart:io';

import 'package:flutter/material.dart';

import '../features/settings/export_import.dart';

/// Result from the LFS import password dialog.
typedef LfsImportDialogResult = ({String password, ImportMode mode});

/// Dialog for entering master password and import mode for .lfs file import.
///
/// Returns [LfsImportDialogResult] on submit, null on cancel.
/// Extracted from MainScreen for testability.
class LfsImportDialog extends StatefulWidget {
  final String filePath;

  const LfsImportDialog({super.key, required this.filePath});

  /// Show the dialog and return the result.
  static Future<LfsImportDialogResult?> show(BuildContext context, {required String filePath}) {
    return showDialog<LfsImportDialogResult>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => LfsImportDialog(filePath: filePath),
    );
  }

  @override
  State<LfsImportDialog> createState() => _LfsImportDialogState();
}

class _LfsImportDialogState extends State<LfsImportDialog> {
  final _passwordCtrl = TextEditingController();
  var _mode = ImportMode.merge;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_passwordCtrl.text.isEmpty) return;
    Navigator.pop(context, (password: _passwordCtrl.text, mode: _mode));
  }

  @override
  Widget build(BuildContext context) {
    final subtleStyle = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    );

    return AlertDialog(
      title: const Text('Import Data'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(File(widget.filePath).uri.pathSegments.last, style: subtleStyle),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Master Password',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              if (v.isNotEmpty) {
                Navigator.pop(context, (password: v, mode: _mode));
              }
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<ImportMode>(
            segments: const [
              ButtonSegment(
                value: ImportMode.merge,
                label: Text('Merge'),
                icon: Icon(Icons.merge, size: 16),
              ),
              ButtonSegment(
                value: ImportMode.replace,
                label: Text('Replace'),
                icon: Icon(Icons.swap_horiz, size: 16),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(height: 4),
          Text(
            _mode == ImportMode.merge
                ? 'Add new sessions, keep existing'
                : 'Replace all sessions with imported',
            style: subtleStyle,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Import'),
        ),
      ],
    );
  }
}
