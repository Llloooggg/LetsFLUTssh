import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../src/rust/api/local_fs.dart' as rust_local_fs;
import '../../theme/app_theme.dart';
import '../../utils/format.dart' show localizeError;
import '../core/app_dialog.dart';
import '../core/app_icon_button.dart';

/// In-app directory picker that walks the filesystem through
/// `lfs_core::fs::local::list_directories`, bypassing SAF. Used on
/// Android when the app already holds `MANAGE_EXTERNAL_STORAGE` — SAF's
/// `ACTION_OPEN_DOCUMENT_TREE` always prompts for a fresh per-folder
/// consent dialog even when all-files access is granted, which is the
/// bug users hit on the export flow.
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
  List<String> _children = const [];
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
      // Rust-side: missing path returns `"no_such_file_or_directory"`,
      // unreadable returns `"permission_denied"`; both keys route
      // through `localizeError` to the same toast strings the rest of
      // the local-fs surface uses. Sorted by lowercase basename in
      // Rust so the UI does not need a second pass.
      final entries = await rust_local_fs.localFsListDirectories(path: path);
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
        _error = localizeError(S.of(context), e);
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
          const SizedBox(width: AppSpacing.sm),
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
          padding: const EdgeInsets.all(AppSpacing.lg),
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
        final child = _children[i];
        final name = p.basename(child);
        if (name.startsWith('.')) return const SizedBox.shrink();
        return ListTile(
          dense: true,
          leading: Icon(Icons.folder, size: 18, color: AppTheme.yellow),
          title: Text(name, style: TextStyle(fontSize: AppFonts.sm)),
          onTap: () => _load(child),
        );
      },
    );
  }
}
