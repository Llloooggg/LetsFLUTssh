import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_dialog.dart';
import 'app_icon_button.dart';

/// In-app directory picker that walks the filesystem directly via
/// `dart:io`, bypassing SAF. Used on Android when the app already holds
/// `MANAGE_EXTERNAL_STORAGE` — SAF's `ACTION_OPEN_DOCUMENT_TREE` always
/// prompts for a fresh per-folder consent dialog even when all-files
/// access is granted, which is the bug users hit on the export flow.
///
/// Returns the absolute directory path the user chose, or `null` on
/// cancel. Does not create new files; the caller appends the filename.
class LocalDirectoryPicker extends StatefulWidget {
  final String initialPath;
  final String title;

  const LocalDirectoryPicker({
    super.key,
    required this.initialPath,
    required this.title,
  });

  static Future<String?> show(
    BuildContext context, {
    required String initialPath,
    required String title,
  }) {
    return AppDialog.show<String>(
      context,
      builder: (_) =>
          LocalDirectoryPicker(initialPath: initialPath, title: title),
    );
  }

  @override
  State<LocalDirectoryPicker> createState() => _LocalDirectoryPickerState();
}

class _LocalDirectoryPickerState extends State<LocalDirectoryPicker> {
  late String _current;
  List<Directory> _children = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _current = widget.initialPath;
    _load(_current);
  }

  Future<void> _load(String path) async {
    setState(() {
      _current = path;
      _loading = true;
      _error = null;
    });
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        setState(() {
          _loading = false;
          _error = S.of(context).errNoSuchFileOrDirectory;
          _children = const [];
        });
        return;
      }
      final entries = <Directory>[];
      // list() can fail mid-stream on permission-denied subtrees; we
      // collect what we can and surface the error only if the whole
      // directory is unreadable (handled in the outer catch).
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) entries.add(entity);
      }
      entries.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _children = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _children = const [];
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _goUp() {
    final parent = p.dirname(_current);
    if (parent == _current) return;
    _load(parent);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: widget.title,
      maxWidth: 520,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPathBar(),
            Expanded(child: _buildList(s)),
          ],
        ),
      ),
      actions: [
        AppButton.cancel(onTap: () => Navigator.of(context).pop()),
        AppButton.primary(
          label: s.save,
          onTap: () => Navigator.of(context).pop(_current),
        ),
      ],
    );
  }

  Widget _buildPathBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.bg2,
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_upward,
            onTap: _goUp,
            tooltip: S.of(context).back,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _current,
              style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fg),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(S s) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.red),
          ),
        ),
      );
    }
    if (_children.isEmpty) {
      return Center(
        child: Text(
          s.emptyFolder,
          style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgFaint),
        ),
      );
    }
    return ListView.builder(
      itemCount: _children.length,
      itemBuilder: (_, i) {
        final dir = _children[i];
        final name = p.basename(dir.path);
        if (name.startsWith('.')) return const SizedBox.shrink();
        return ListTile(
          dense: true,
          leading: Icon(Icons.folder, size: 18, color: AppTheme.yellow),
          title: Text(name, style: TextStyle(fontSize: AppFonts.sm)),
          onTap: () => _load(dir.path),
        );
      },
    );
  }
}
