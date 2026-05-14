import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/known_hosts_provider.dart'
    show
        KnownHostsMutator,
        knownHostFingerprint,
        knownHostsMutatorProvider,
        knownHostsStreamProvider;
import '../../theme/app_theme.dart';
import '../../widgets/app_collection_toolbar.dart';
import '../../widgets/app_data_search_bar.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/toast.dart';
import 'known_hosts_manager_logic.dart';

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

  KnownHostsMutator get _mutator => ref.read(knownHostsMutatorProvider);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // Stream-driven: the first frame paints the spinner while the
    // initial FRB fetch is in flight; every subsequent
    // `KnownHostsChanged` bus event (TOFU accept, settings clear,
    // .lfs import) re-emits a fresh snapshot here without an
    // explicit `setState` round-trip.
    final async = ref.watch(knownHostsStreamProvider);
    final all = async.hasValue
        ? async.value as Map<String, String>
        : const <String, String>{};

    return Column(
      children: [
        _buildToolbar(s, all.length),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            data: (entries) => _buildBody(s, entries),
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (_, _) => _buildBody(s, all),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(S s, Map<String, String> all) {
    final filtered = filterKnownHostEntries(all, _filter);
    if (filtered.isEmpty) {
      return AppEmptyState(
        message: all.isEmpty ? s.knownHostsEmpty : s.knownHostsCount(0),
      );
    }
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildEntry(s, filtered[index]),
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
    final split = splitKnownHostValue(entry.value);
    final keyType = split.keyType;
    final keyData = split.keyData;

    // Compute fingerprint from base64 key data
    String fp;
    try {
      final keyBytes = base64Decode(keyData);
      fp = knownHostFingerprint(keyBytes);
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
    await _mutator.removeHost(hostPort);
    if (mounted) {
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
    await _mutator.clearAll();
    if (mounted) {
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
