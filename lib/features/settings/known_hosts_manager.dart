import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ssh/known_hosts.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/connection_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_collection_toolbar.dart';
import '../../widgets/app_data_search_bar.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/toast.dart';

/// Embeddable known hosts manager — search + list with CRUD.
///
/// Used standalone inside [KnownHostsManagerDialog] (mobile) and embedded
/// in the desktop Tools dialog.
class KnownHostsManagerPanel extends ConsumerStatefulWidget {
  const KnownHostsManagerPanel({super.key});

  @override
  ConsumerState<KnownHostsManagerPanel> createState() =>
      _KnownHostsManagerPanelState();
}

class _KnownHostsManagerPanelState
    extends ConsumerState<KnownHostsManagerPanel> {
  String _filter = '';
  bool _loading = true;

  KnownHostsManager get _manager => ref.read(knownHostsProvider);

  @override
  void initState() {
    super.initState();
    _loadHosts();
  }

  Future<void> _loadHosts() async {
    await _manager.load();
    if (mounted) setState(() => _loading = false);
  }

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

    return Column(
      children: [
        _buildToolbar(s, totalCount),
        const Divider(height: 1),
        Expanded(child: _buildBody(s, entries, totalCount)),
      ],
    );
  }

  Widget _buildBody(
    S s,
    List<MapEntry<String, String>> entries,
    int totalCount,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (entries.isEmpty) {
      return AppEmptyState(
        message: totalCount == 0 ? s.knownHostsEmpty : s.knownHostsCount(0),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildEntry(s, entries[index]),
    );
  }

  Widget _buildToolbar(S s, int totalCount) {
    return AppCollectionToolbar(
      hasItems: totalCount > 0,
      search: AppDataSearchBar(
        onChanged: (v) => setState(() => _filter = v),
        hintText: s.search,
      ),
      countLabel: s.knownHostsCount(totalCount),
      actions: [
        if (totalCount > 0)
          _ToolbarButton(
            icon: Icons.delete_sweep,
            tooltip: s.clearAllKnownHosts,
            onTap: _clearAll,
          ),
      ],
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
          AppButton.cancel(onTap: () => Navigator.pop(ctx, false)),
          AppButton.destructive(
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
          AppButton.cancel(onTap: () => Navigator.pop(ctx, false)),
          AppButton.destructive(
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
}

/// Dialog wrapper for standalone use (mobile settings).
class KnownHostsManagerDialog extends StatelessWidget {
  const KnownHostsManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return AppDialog.show(
      context,
      builder: (_) => const KnownHostsManagerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).knownHosts,
      maxWidth: 640,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: const SizedBox(height: 400, child: KnownHostsManagerPanel()),
      actions: [AppButton.cancel(onTap: () => Navigator.pop(context))],
    );
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
