import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ssh/known_hosts.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/connection_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/platform.dart' as plat;
import '../../widgets/app_dialog.dart';
import '../../widgets/toast.dart';

/// Full-screen dialog for managing known SSH host entries.
///
/// Shows a searchable list of known hosts with delete, import, export,
/// and clear-all actions.
class KnownHostsManagerDialog extends ConsumerStatefulWidget {
  const KnownHostsManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return AppDialog.show(
      context,
      builder: (_) => const KnownHostsManagerDialog(),
    );
  }

  @override
  ConsumerState<KnownHostsManagerDialog> createState() =>
      _KnownHostsManagerDialogState();
}

class _KnownHostsManagerDialogState
    extends ConsumerState<KnownHostsManagerDialog> {
  String _filter = '';

  KnownHostsManager get _manager => ref.read(knownHostsProvider);

  List<MapEntry<String, String>> get _filteredEntries {
    final entries = _manager.entries.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (_filter.isEmpty) return entries;
    final lower = _filter.toLowerCase();
    return entries.where((e) {
      return e.key.toLowerCase().contains(lower) ||
          e.value.toLowerCase().contains(lower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final entries = _filteredEntries;
    final totalCount = _manager.count;

    return AppDialog(
      title: s.knownHosts,
      maxWidth: 640,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        height: 400,
        child: Column(
          children: [
            _buildToolbar(s, totalCount),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        totalCount == 0
                            ? s.knownHostsEmpty
                            : s.knownHostsCount(0),
                        style: TextStyle(
                          color: AppTheme.fgDim,
                          fontSize: AppFonts.sm,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _buildEntry(s, entries[index]),
                    ),
            ),
          ],
        ),
      ),
      actions: [AppDialogAction.cancel(onTap: () => Navigator.pop(context))],
    );
  }

  Widget _buildToolbar(S s, int totalCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: AppTheme.controlHeightSm,
              child: TextField(
                onChanged: (v) => setState(() => _filter = v),
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fg,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: s.search,
                  hintStyle: TextStyle(
                    color: AppTheme.fgDim,
                    fontSize: AppFonts.sm,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 0,
                  ),
                  filled: true,
                  fillColor: AppTheme.bg3,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
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
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            s.knownHostsCount(totalCount),
            style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgDim),
          ),
          const SizedBox(width: 8),
          _ToolbarButton(
            icon: Icons.file_download_outlined,
            tooltip: s.importKnownHosts,
            onTap: _importHosts,
          ),
          _ToolbarButton(
            icon: Icons.file_upload_outlined,
            tooltip: s.exportKnownHosts,
            onTap: _exportHosts,
          ),
          _ToolbarButton(
            icon: Icons.delete_sweep,
            tooltip: s.clearAllKnownHosts,
            onTap: totalCount > 0 ? _clearAll : null,
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(S s, MapEntry<String, String> entry) {
    final hostPort = entry.key;
    final parts = entry.value.split(' ');
    final keyType = parts.isNotEmpty ? parts[0] : '';
    final keyData = parts.length > 1 ? parts[1] : '';

    // Compute fingerprint from base64 key data
    String fp;
    try {
      final keyBytes = base64Decode(keyData);
      fp = KnownHostsManager.fingerprint(keyBytes);
    } catch (_) {
      fp = '?';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hostPort,
                  style: AppFonts.mono(
                    fontSize: AppFonts.sm,
                    color: AppTheme.fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$keyType  $fp',
                  style: AppFonts.mono(
                    fontSize: AppFonts.xs,
                    color: AppTheme.fgDim,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.content_copy, size: 14),
            tooltip: s.copy,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fp));
              Toast.show(
                context,
                message: '${s.fingerprint}: $fp',
                level: ToastLevel.info,
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 14, color: AppTheme.red),
            tooltip: s.removeHost,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _removeHost(hostPort),
          ),
        ],
      ),
    );
  }

  Future<void> _removeHost(String hostPort) async {
    final s = S.of(context);
    final confirmed = await AppDialog.show<bool>(
      context,
      builder: (ctx) => AppDialog(
        title: s.removeHost,
        content: Text(s.removeHostConfirm(hostPort)),
        actions: [
          AppDialogAction.cancel(onTap: () => Navigator.pop(ctx, false)),
          AppDialogAction.destructive(
            label: s.delete,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _manager.removeHost(hostPort);
    if (mounted) {
      setState(() {});
      Toast.show(context, message: s.removedHost(hostPort));
    }
  }

  Future<void> _clearAll() async {
    final s = S.of(context);
    final confirmed = await AppDialog.show<bool>(
      context,
      builder: (ctx) => AppDialog(
        title: s.clearAllKnownHosts,
        content: Text(s.clearAllKnownHostsConfirm),
        actions: [
          AppDialogAction.cancel(onTap: () => Navigator.pop(ctx, false)),
          AppDialogAction.destructive(
            label: s.clearAllKnownHosts,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _manager.clearAll();
    if (mounted) {
      setState(() {});
      Toast.show(context, message: s.clearedAllHosts);
    }
  }

  Future<void> _importHosts() async {
    final s = S.of(context);
    final result = await FilePicker.pickFiles(
      dialogTitle: s.importKnownHosts,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final path = result.files.single.path;
    if (path == null) return;

    final count = await _manager.importFromFile(path);
    if (mounted) {
      setState(() {});
      Toast.show(
        context,
        message: s.importedHosts(count),
        level: ToastLevel.success,
      );
    }
  }

  Future<void> _exportHosts() async {
    final s = S.of(context);
    if (_manager.count == 0) {
      Toast.show(
        context,
        message: s.noHostsToExport,
        level: ToastLevel.warning,
      );
      return;
    }

    final content = _manager.exportToString();

    if (plat.isDesktopPlatform) {
      final outputPath = await FilePicker.saveFile(
        dialogTitle: s.exportKnownHosts,
        fileName: 'known_hosts',
      );
      if (outputPath == null || !mounted) return;
      await _writeExport(outputPath, content);
    } else {
      // Mobile: copy to clipboard
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        Toast.show(
          context,
          message: s.exportKnownHosts,
          level: ToastLevel.success,
        );
      }
    }
  }

  Future<void> _writeExport(String path, String content) async {
    try {
      await _writeFile(path, content);
      if (mounted) {
        Toast.show(
          context,
          message: S.of(context).exportedTo(path),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      if (mounted) {
        Toast.show(context, message: e.toString(), level: ToastLevel.error);
      }
    }
  }

  Future<void> _writeFile(String path, String content) async {
    final file = File(path);
    await file.writeAsString(content);
  }
}

/// Small toolbar button for known hosts actions.
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _ToolbarButton({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onTap,
    );
  }
}
