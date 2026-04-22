import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../core/session/session_tree.dart';
import '../../core/shortcut_registry.dart';
import '../../providers/connection_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bordered_box.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_divider.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/context_menu.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/platform.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/mobile_selection_bar.dart';
import '../../widgets/status_indicator.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_node.dart';
import '../tags/tag_assign_dialog.dart';
import 'session_edit_dialog.dart';
import 'session_panel_controller.dart';
import 'session_tree_view.dart';

part 'session_panel_widgets.dart';

/// Session sidebar — tree view + search + actions.
class SessionPanel extends ConsumerStatefulWidget {
  final void Function(Session session) onConnect;
  final void Function(Session session)? onSftpConnect;

  /// Called when the user interacts with the sidebar (pointer down).
  /// Used to clear selection in other panels (e.g. file browser).
  final VoidCallback? onActivated;

  const SessionPanel({
    super.key,
    required this.onConnect,
    this.onSftpConnect,
    this.onActivated,
  });

  @override
  ConsumerState<SessionPanel> createState() => SessionPanelState();
}

class SessionPanelState extends ConsumerState<SessionPanel> {
  final _focusNode = FocusNode();
  late final SessionPanelController _ctrl;

  // ---- @visibleForTesting surface ----------------------------------
  // Tests reach into state via these getters / methods. The state
  // itself now lives on [_ctrl]; keep the shims so existing widget
  // tests continue to drive the panel without touching the controller
  // class directly.

  @visibleForTesting
  FocusNode get focusNode => _focusNode;
  @visibleForTesting
  SessionPanelController get controller => _ctrl;
  @visibleForTesting
  String? get focusedSessionId => _ctrl.focusedSessionId;
  @visibleForTesting
  bool get selectMode => _ctrl.selectMode;
  @visibleForTesting
  Set<String> get selectedIds => _ctrl.selectedIds;
  @visibleForTesting
  Set<String> get selectedFolderPaths => _ctrl.selectedFolderPaths;
  @visibleForTesting
  bool get marqueeInProgress => _ctrl.marqueeInProgress;

  @visibleForTesting
  void setMarqueeSelection(
    Set<String> ids, [
    Set<String> folderPaths = const {},
  ]) => _ctrl.setMarqueeSelection(ids, folderPaths);

  @visibleForTesting
  void simulateMarqueeStart() => _ctrl.setMarqueeInProgress(true);

  @visibleForTesting
  void simulateMarqueeEnd() => _ctrl.setMarqueeInProgress(false);

  @visibleForTesting
  void enterSelectModeWithSession(String sessionId) =>
      _ctrl.enterSelectModeWithSession(sessionId);

  @visibleForTesting
  void enterSelectModeWithFolder(String folderPath) =>
      _ctrl.enterSelectModeWithFolder(folderPath);

  @override
  void initState() {
    super.initState();
    _ctrl = SessionPanelController();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  /// Clears multi-selection (marquee / Ctrl+click). Keeps the
  /// focused session/folder so the details panel stays visible.
  void clearDesktopSelection() => _ctrl.clearDesktopSelection();

  void _selectAll() {
    final sessions = ref.read(filteredSessionsProvider);
    _ctrl.selectAllIds(sessions.map((s) => s.id));
  }

  Future<void> _deleteSelected(BuildContext context) async {
    if (!_ctrl.hasSelection) return;
    final sessionCount = _ctrl.selectedIds.length;
    final folderCount = _ctrl.selectedFolderPaths.length;
    final parts = <String>[
      if (sessionCount > 0) S.of(context).nSessions(sessionCount),
      if (folderCount > 0) S.of(context).nFolders(folderCount),
    ];
    final confirmed = await ConfirmDialog.show(
      context,
      title: S.of(context).deleteSelected,
      content: Text(
        S.of(context).deleteNSessionsAndFolders(parts.join(' and ')),
      ),
    );
    if (confirmed) {
      final notifier = ref.read(sessionProvider.notifier);
      if (_ctrl.selectedIds.isNotEmpty) {
        await notifier.deleteMultiple(Set.of(_ctrl.selectedIds));
      }
      for (final folderPath in _ctrl.selectedFolderPaths) {
        await notifier.deleteFolder(folderPath);
      }
      if (_ctrl.selectMode) {
        _ctrl.exitSelectMode();
      } else {
        _ctrl.clearDesktopSelection();
      }
    }
  }

  Future<void> _moveSelected(BuildContext context) async {
    if (!_ctrl.hasSelection) return;
    final store = ref.read(sessionStoreProvider);
    final allFolders = <String>{'', ...store.folders(), ...store.emptyFolders};

    final selected = await AppDialog.show<String>(
      context,
      builder: (ctx) => AppDialog(
        title: S.of(context).moveToFolder,
        scrollable: false,
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allFolders.length,
            itemBuilder: (ctx, index) {
              final folder = allFolders.elementAt(index);
              return ListTile(
                leading: Icon(folder.isEmpty ? Icons.home : Icons.folder),
                title: Text(folder.isEmpty ? S.of(context).rootFolder : folder),
                onTap: () => Navigator.of(ctx).pop(folder),
              );
            },
          ),
        ),
        actions: [AppButton.cancel(onTap: () => Navigator.of(ctx).pop())],
      ),
    );

    if (selected != null) {
      await _applyMove(selected);
    }
  }

  Future<void> _applyMove(String target) async {
    final notifier = ref.read(sessionProvider.notifier);
    if (_ctrl.selectedIds.isNotEmpty) {
      await notifier.moveMultiple(Set.of(_ctrl.selectedIds), target);
    }
    for (final folderPath in _ctrl.selectedFolderPaths) {
      await notifier.moveFolder(folderPath, target);
    }
    if (_ctrl.selectMode) {
      _ctrl.exitSelectMode();
    } else {
      _ctrl.clearDesktopSelection();
    }
  }

  /// Build connected and connecting session ID sets from a single provider watch.
  ({Set<String> connected, Set<String> connecting}) _connectionSessionIds(
    WidgetRef ref,
  ) {
    // Watch the derived summary, not the raw stream — a cachedPassphrase
    // write or a progress-step append on an unrelated connection does
    // not change which session ids belong to which bucket, so value
    // equality on ConnectionSummary suppresses the rebuild.
    final summary = ref.watch(connectionSummaryProvider);
    return (
      connected: summary.connectedSessionIds,
      connecting: summary.connectingSessionIds,
    );
  }

  /// Copy the focused session to the clipboard.
  @visibleForTesting
  void copyFocusedSession() => _ctrl.copyFocused();

  /// Paste (duplicate) the copied session.
  @visibleForTesting
  void pasteCopiedSession() {
    final id = _ctrl.copiedSessionId;
    if (id == null) return;
    ref.read(sessionProvider.notifier).duplicate(id);
  }

  /// Delete the focused session (shows confirmation dialog).
  @visibleForTesting
  void deleteFocusedSession() {
    final id = _ctrl.focusedSessionId;
    if (id == null) return;
    final sessions = ref.read(sessionProvider);
    final session = sessions.where((s) => s.id == id).firstOrNull;
    if (session == null) return;
    _confirmDelete(context, ref, session);
  }

  /// Edit the focused session (shows edit dialog).
  @visibleForTesting
  void editFocusedSession() {
    final id = _ctrl.focusedSessionId;
    if (id == null) return;
    final sessions = ref.read(sessionProvider);
    final session = sessions.where((s) => s.id == id).firstOrNull;
    if (session == null) return;
    _editSession(context, ref, session);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final reg = AppShortcutRegistry.instance;

    if (reg.matches(AppShortcut.sessionUndo, event)) {
      ref.read(sessionProvider.notifier).undo();
      return KeyEventResult.handled;
    }
    if (reg.matches(AppShortcut.sessionRedo, event)) {
      ref.read(sessionProvider.notifier).redo();
      return KeyEventResult.handled;
    }
    if (reg.matches(AppShortcut.sessionCopy, event)) {
      copyFocusedSession();
      return KeyEventResult.handled;
    }
    if (reg.matches(AppShortcut.sessionPaste, event)) {
      pasteCopiedSession();
      return KeyEventResult.handled;
    }
    if (reg.matches(AppShortcut.sessionDelete, event)) {
      if (_ctrl.hasSelection) {
        _deleteSelected(context);
        return KeyEventResult.handled;
      }
      if (_ctrl.focusedSessionId == null) return KeyEventResult.ignored;
      deleteFocusedSession();
      return KeyEventResult.handled;
    }
    if (reg.matches(AppShortcut.sessionEdit, event)) {
      if (_ctrl.focusedSessionId == null) return KeyEventResult.ignored;
      editFocusedSession();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(filteredSessionTreeProvider);
    final searchQuery = ref.watch(sessionSearchProvider);
    final mobile = isMobilePlatform;

    final scheme = Theme.of(context).colorScheme;
    // Opt the whole sidebar out of the ambient `SelectionArea`. The
    // app-level SelectionArea otherwise claims `Ctrl+C` as "copy the
    // selected Text to the clipboard" and swallows the event before
    // our Focus's `_onKeyEvent` sees it — so `AppShortcut.sessionCopy`
    // / `sessionPaste` never fires. The sidebar is a tool surface
    // (rows, folders, buttons), not informational body text; nothing
    // inside should be drag-selectable. Disabling selection at the
    // panel root keeps drag gestures (tab reorder, session tree DnD)
    // intact because the wrap sits *above* the Listener +
    // ThresholdDraggable tree, so pointer events still reach
    // Draggable unchanged — only the Selectable registration is
    // suppressed.
    return SelectionContainer.disabled(
      child: Listener(
        // Claim focus on any pointer-down inside the sidebar so a marquee
        // drag (which never calls onSessionSelected) still flips the panel
        // into its "focused" colour scheme. Without this, rows switched
        // between the dimmed onSurface highlight and the accent-coloured
        // one depending on whether the user had previously tapped a row —
        // the "selection sometimes grey, sometimes blue" flicker.
        onPointerDown: (_) {
          if (!isMobilePlatform) _focusNode.requestFocus();
          widget.onActivated?.call();
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: false,
          onKeyEvent: _onKeyEvent,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => Container(
              color: scheme.surfaceContainerLow,
              child: Column(
                children: [
                  ..._buildHeader(context, ref, searchQuery, mobile),
                  Expanded(
                    child: tree.isEmpty
                        ? _EmptyState(onAdd: () => _addSession(context, ref))
                        : _buildTreeView(context, ref, tree, mobile),
                  ),
                  if (!mobile)
                    _SessionDetailsPanel(
                      session: _focusedSession(ref),
                      folderPath: _ctrl.focusedFolderPath,
                      folderItemCount: _ctrl.focusedFolderItemCount,
                    ),
                  if (!mobile) const _SidebarFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Session? _focusedSession(WidgetRef ref) {
    final id = _ctrl.focusedSessionId;
    if (id == null) return null;
    return ref.read(sessionProvider).where((s) => s.id == id).firstOrNull;
  }

  List<Widget> _buildHeader(
    BuildContext context,
    WidgetRef ref,
    String searchQuery,
    bool mobile,
  ) {
    if (_ctrl.selectMode && mobile) {
      return [_buildMobileSelectionBar(context, ref)];
    }
    return [
      _PanelHeader(
        onAddSession: () => _addSession(context, ref),
        onAddFolder: () => _createFolder(context, ref, ''),
      ),
      _SearchBar(
        value: searchQuery,
        onChanged: (v) => ref.read(sessionSearchProvider.notifier).set(v),
      ),
    ];
  }

  Widget _buildMobileSelectionBar(BuildContext context, WidgetRef ref) {
    final hasSelection = _ctrl.hasSelection;
    return MobileSelectionBar(
      selectedCount: _ctrl.selectedIds.length,
      totalCount: ref.read(filteredSessionsProvider).length,
      onCancel: _ctrl.exitSelectMode,
      onSelectAll: _selectAll,
      onDeselectAll: _ctrl.deselectAll,
      onDelete: hasSelection ? () => _deleteSelected(context) : null,
      actions: [
        AppIconButton(
          icon: Icons.drive_file_move,
          size: 20,
          boxSize: 36,
          onTap: hasSelection ? () => _moveSelected(context) : null,
          tooltip: S.of(context).moveTo,
        ),
      ],
    );
  }

  Widget _buildTreeView(
    BuildContext context,
    WidgetRef ref,
    List<SessionTreeNode> tree,
    bool mobile,
  ) {
    final connState = _connectionSessionIds(ref);
    return SessionTreeView(
      tree: tree,
      connectedSessionIds: connState.connected,
      connectingSessionIds: connState.connecting,
      collapsedFolders: ref.watch(sessionStoreProvider).collapsedFolders,
      onToggleFolderCollapsed: (path) =>
          ref.read(sessionStoreProvider).toggleFolderCollapsed(path),
      selectMode: mobile && _ctrl.selectMode,
      selectedIds: _ctrl.selectedIds,
      onToggleSelected: _ctrl.toggleSelected,
      selectedFolderPaths: _ctrl.selectedFolderPaths,
      onToggleFolderSelected: _ctrl.toggleFolderSelected,
      focusedSessionId: _ctrl.focusedSessionId,
      focusedFolderPath: _ctrl.focusedFolderPath,
      panelHasFocus: _focusNode.hasFocus,
      onSessionDoubleTap: widget.onConnect,
      onSessionSelected: (id) {
        _ctrl.setFocusedSession(id);
        if (!mobile) _focusNode.requestFocus();
      },
      onFolderSelected: _ctrl.setFocusedFolder,
      onEmptySpaceTap: () {
        // Drop the panel focus so highlighted rows dim to grey — the
        // details panel still shows the previously-focused session or
        // folder, so the user can tell which row it belongs to without
        // the row stealing the accent colour from active work elsewhere.
        if (!mobile) _focusNode.unfocus();
      },
      onSessionContextMenu: (session, position) {
        _showContextMenu(context, ref, session, position);
      },
      onFolderContextMenu: (folderPath, position) {
        _showFolderContextMenu(context, ref, folderPath, position);
      },
      onBackgroundContextMenu: (position) {
        _showFolderContextMenu(context, ref, '', position);
      },
      onSessionMoved: (sessionId, targetFolder) {
        ref.read(sessionProvider.notifier).moveSession(sessionId, targetFolder);
      },
      onFolderMoved: (folderPath, targetParent) {
        ref.read(sessionProvider.notifier).moveFolder(folderPath, targetParent);
      },
      onBulkMoved: (sessionIds, folderPaths, targetFolder) async {
        final notifier = ref.read(sessionProvider.notifier);
        if (sessionIds.isNotEmpty) {
          await notifier.moveMultiple(sessionIds, targetFolder);
        }
        for (final gp in folderPaths) {
          await notifier.moveFolder(gp, targetFolder);
        }
        _ctrl.clearDesktopSelection();
      },
      onMarqueeStart: () => _ctrl.setMarqueeInProgress(true),
      onMarqueeEnd: () => _ctrl.setMarqueeInProgress(false),
      onMarqueeSelect: _ctrl.setMarqueeSelection,
    );
  }

  Future<void> _handleDialogResult(
    WidgetRef ref,
    SessionDialogResult result,
  ) async {
    switch (result) {
      case SaveResult(:final session, :final connect):
        await ref.read(sessionProvider.notifier).add(session);
        if (connect) widget.onConnect(session);
    }
  }

  Future<void> _addSession(BuildContext context, WidgetRef ref) async {
    final result = await SessionEditDialog.show(context);
    if (result == null) return;
    await _handleDialogResult(ref, result);
  }

  void _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Session session,
    Offset position,
  ) {
    if (isMobilePlatform) {
      _showMobileSessionSheet(context, ref, session);
      return;
    }
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: S.of(context).terminal,
          icon: Icons.terminal,
          color: AppTheme.blue,
          onTap: () => widget.onConnect(session),
        ),
        if (widget.onSftpConnect != null)
          ContextMenuItem(
            label: S.of(context).files,
            icon: Icons.folder,
            color: AppTheme.yellow,
            onTap: () => widget.onSftpConnect?.call(session),
          ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          label: S.of(context).editConnection,
          icon: Icons.settings,
          onTap: () => _editSession(context, ref, session),
        ),
        ContextMenuItem(
          label: S.of(context).duplicate,
          icon: Icons.copy,
          onTap: () => ref.read(sessionProvider.notifier).duplicate(session.id),
        ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          label: S.of(context).delete,
          icon: Icons.delete,
          color: AppTheme.red,
          onTap: () => _confirmDelete(context, ref, session),
        ),
      ],
    );
  }

  void _showMobileSessionSheet(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) {
    final label = session.label.isNotEmpty
        ? session.label
        : session.displayName;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: AppFonts.xl,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (session.host.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    session.host,
                    style: TextStyle(
                      fontSize: AppFonts.lg,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              const AppDivider(),
              ListTile(
                leading: Icon(Icons.terminal, color: AppTheme.blue),
                title: Text(S.of(ctx).terminal),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onConnect(session);
                },
              ),
              if (widget.onSftpConnect != null)
                ListTile(
                  leading: Icon(Icons.folder, color: AppTheme.yellow),
                  title: Text(S.of(ctx).files),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onSftpConnect?.call(session);
                  },
                ),
              const AppDivider(),
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(S.of(ctx).editConnection),
                onTap: () {
                  Navigator.pop(ctx);
                  _editSession(context, ref, session);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(S.of(ctx).duplicate),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(sessionProvider.notifier).duplicate(session.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move),
                title: Text(S.of(ctx).moveTo),
                onTap: () {
                  Navigator.pop(ctx);
                  _moveSession(context, ref, session);
                },
              ),
              const AppDivider(),
              ListTile(
                leading: Icon(Icons.delete, color: AppTheme.disconnected),
                title: Text(
                  S.of(ctx).delete,
                  style: TextStyle(color: AppTheme.disconnected),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, ref, session);
                },
              ),
              const AppDivider(),
              ListTile(
                leading: const Icon(Icons.checklist),
                title: Text(S.of(ctx).select),
                onTap: () {
                  Navigator.pop(ctx);
                  enterSelectModeWithSession(session.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _moveSession(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final store = ref.read(sessionStoreProvider);
    final allFolders = <String>{'', ...store.folders(), ...store.emptyFolders};

    final selected = await AppDialog.show<String>(
      context,
      builder: (ctx) => AppDialog(
        title: S.of(context).moveToFolder,
        scrollable: false,
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allFolders.length,
            itemBuilder: (ctx, index) => _buildMoveFolderTile(
              ctx,
              allFolders.elementAt(index),
              session.folder,
            ),
          ),
        ),
        actions: [AppButton.cancel(onTap: () => Navigator.of(ctx).pop())],
      ),
    );

    if (selected != null) {
      ref.read(sessionProvider.notifier).moveSession(session.id, selected);
    }
  }

  Widget _buildMoveFolderTile(
    BuildContext context,
    String folder,
    String currentFolder,
  ) {
    final isCurrent = folder == currentFolder;
    return ListTile(
      leading: Icon(
        folder.isEmpty ? Icons.home : Icons.folder,
        color: isCurrent ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        folder.isEmpty ? S.of(context).rootFolder : folder,
        style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : null),
      ),
      trailing: isCurrent ? const Icon(Icons.check, size: 18) : null,
      onTap: isCurrent ? null : () => Navigator.of(context).pop(folder),
    );
  }

  Future<void> _editSession(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    // In-memory cached [session] has no credentials (lazy-load). Reload
    // from DB so the edit form pre-fills password/keyData/passphrase
    // correctly; fall back to the bare cache entry if the row vanished.
    final store = ref.read(sessionStoreProvider);
    final full = await store.loadWithCredentials(session.id) ?? session;
    if (!context.mounted) return;
    final result = await SessionEditDialog.show(context, session: full);
    if (result == null) return;
    if (result is SaveResult) {
      await ref.read(sessionProvider.notifier).update(result.session);
      if (result.connect) widget.onConnect(result.session);
    }
  }

  void _showFolderContextMenu(
    BuildContext context,
    WidgetRef ref,
    String folderPath,
    Offset position,
  ) {
    if (isMobilePlatform) {
      _showMobileFolderSheet(context, ref, folderPath);
      return;
    }
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: S.of(context).newConnection,
          icon: Icons.add,
          onTap: () => _addSessionInFolder(context, ref, folderPath),
        ),
        ContextMenuItem(
          label: S.of(context).newFolder,
          icon: Icons.create_new_folder,
          onTap: () => _createFolder(context, ref, folderPath),
        ),
        if (folderPath.isNotEmpty) ...[
          const ContextMenuItem.divider(),
          ContextMenuItem(
            label: S.of(context).renameFolder,
            icon: Icons.drive_file_rename_outline,
            onTap: () => _renameFolder(context, ref, folderPath),
          ),
          ContextMenuItem(
            label: S.of(context).editTags,
            icon: Icons.label_outline,
            onTap: () {
              final folderId = ref
                  .read(sessionStoreProvider)
                  .folderIdByPath(folderPath);
              if (folderId != null) {
                TagAssignDialog.showForFolder(context, folderId: folderId);
              }
            },
          ),
          ContextMenuItem(
            label: S.of(context).deleteFolder,
            icon: Icons.delete,
            color: AppTheme.red,
            onTap: () => _confirmDeleteFolder(context, ref, folderPath),
          ),
        ],
      ],
    );
  }

  void _showMobileFolderSheet(
    BuildContext context,
    WidgetRef ref,
    String folderPath,
  ) {
    final folderName = folderPath.isEmpty
        ? S.of(context).root
        : folderPath.split('/').last;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  folderName,
                  style: TextStyle(
                    fontSize: AppFonts.xl,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const AppDivider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(S.of(ctx).newConnection),
                onTap: () {
                  Navigator.pop(ctx);
                  _addSessionInFolder(context, ref, folderPath);
                },
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder),
                title: Text(S.of(ctx).newFolder),
                onTap: () {
                  Navigator.pop(ctx);
                  _createFolder(context, ref, folderPath);
                },
              ),
              if (folderPath.isNotEmpty) ...[
                const AppDivider(),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: Text(S.of(ctx).renameFolder),
                  onTap: () {
                    Navigator.pop(ctx);
                    _renameFolder(context, ref, folderPath);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete, color: AppTheme.disconnected),
                  title: Text(
                    S.of(ctx).deleteFolder,
                    style: TextStyle(color: AppTheme.disconnected),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDeleteFolder(context, ref, folderPath);
                  },
                ),
                const AppDivider(),
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: Text(S.of(ctx).select),
                  onTap: () {
                    Navigator.pop(ctx);
                    enterSelectModeWithFolder(folderPath);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addSessionInFolder(
    BuildContext context,
    WidgetRef ref,
    String folderPath,
  ) async {
    final result = await SessionEditDialog.show(
      context,
      defaultFolder: folderPath,
    );
    if (result == null) return;
    await _handleDialogResult(ref, result);
  }

  Future<void> _createFolder(
    BuildContext context,
    WidgetRef ref,
    String parentFolder,
  ) async {
    final existingFolders = _collectAllFolderPaths(ref);

    final result = await _showFolderNameDialog(
      context,
      title: S.of(context).newFolder,
      confirmLabel: S.of(context).create,
      existingFolders: existingFolders,
      parentPath: parentFolder,
    );

    if (result == null || result.trim().isEmpty) return;

    final newFolder = parentFolder.isEmpty
        ? result.trim()
        : '$parentFolder/${result.trim()}';
    await ref.read(sessionProvider.notifier).addEmptyFolder(newFolder);
  }

  Future<void> _renameFolder(
    BuildContext context,
    WidgetRef ref,
    String folderPath,
  ) async {
    // Extract the folder's own name (last segment)
    final parts = folderPath.split('/');
    final currentName = parts.last;
    final parentPath = parts.length > 1
        ? parts.sublist(0, parts.length - 1).join('/')
        : '';

    final existingFolders = _collectAllFolderPaths(ref);

    final result = await _showFolderNameDialog(
      context,
      title: S.of(context).renameFolder,
      confirmLabel: S.of(context).rename,
      initialValue: currentName,
      existingFolders: existingFolders,
      parentPath: parentPath,
      currentName: currentName,
    );

    if (result == null ||
        result.trim().isEmpty ||
        result.trim() == currentName) {
      return;
    }

    final newPath = parentPath.isEmpty
        ? result.trim()
        : '$parentPath/${result.trim()}';
    await ref.read(sessionProvider.notifier).renameFolder(folderPath, newPath);
  }

  /// Collects all existing folder paths including implicit parent segments.
  /// E.g. "A/B/C" implies "A" and "A/B" also exist.
  Set<String> _collectAllFolderPaths(WidgetRef ref) {
    final store = ref.read(sessionStoreProvider);
    final result = <String>{};
    for (final g in [...store.folders(), ...store.emptyFolders]) {
      final parts = g.split('/');
      for (var i = 1; i <= parts.length; i++) {
        result.add(parts.sublist(0, i).join('/'));
      }
    }
    return result;
  }

  /// Shows a folder name input dialog with duplicate validation.
  /// Returns the entered name, or null if cancelled.
  Future<String?> _showFolderNameDialog(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required Set<String> existingFolders,
    required String parentPath,
    String? initialValue,
    String? currentName,
  }) async {
    final nameCtrl = TextEditingController(text: initialValue ?? '');
    String? errorText;

    try {
      return await showDialog<String>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            return _buildFolderNameAlert(
              ctx,
              title: title,
              confirmLabel: confirmLabel,
              nameCtrl: nameCtrl,
              errorText: errorText,
              onChanged: (_) {
                final name = nameCtrl.text.trim();
                final fullPath = parentPath.isEmpty
                    ? name
                    : '$parentPath/$name';
                final isDuplicate =
                    name.isNotEmpty &&
                    name != currentName &&
                    existingFolders.contains(fullPath);
                setDialogState(() {
                  errorText = isDuplicate
                      ? S.of(context).folderAlreadyExists(name)
                      : null;
                });
              },
              hintText: S.of(context).hintFolderExample,
            );
          },
        ),
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  Widget _buildFolderNameAlert(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required TextEditingController nameCtrl,
    required String? errorText,
    required ValueChanged<String> onChanged,
    String? hintText,
  }) {
    return AppDialog(
      title: title,
      maxWidth: 360,
      scrollable: false,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.of(context).folderNameLabel,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppFonts.xs,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: AppTheme.fgFaint,
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: nameCtrl,
            autofocus: true,
            style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: AppFonts.mono(
                fontSize: AppFonts.sm,
                color: AppTheme.fgFaint,
              ),
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
              errorBorder: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.red),
              ),
              errorText: errorText,
              errorStyle: AppFonts.inter(
                fontSize: AppFonts.xs,
                color: AppTheme.red,
              ),
            ),
            onChanged: onChanged,
            onFieldSubmitted: (v) {
              if (errorText == null && v.trim().isNotEmpty) {
                Navigator.of(context).pop(v);
              }
            },
          ),
        ],
      ),
      actions: [
        AppButton.cancel(onTap: () => Navigator.of(context).pop()),
        AppButton.primary(
          label: confirmLabel,
          enabled: errorText == null,
          onTap: () => Navigator.of(context).pop(nameCtrl.text),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteFolder(
    BuildContext context,
    WidgetRef ref,
    String folderPath,
  ) async {
    final store = ref.read(sessionStoreProvider);
    final sessionCount = store.countSessionsInFolder(folderPath);
    final folderName = folderPath.split('/').last;

    final confirmed = await ConfirmDialog.show(
      context,
      title: S.of(context).deleteFolder,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(S.of(context).deleteFolderConfirm(folderName)),
          if (sessionCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              S.of(context).willDeleteSessionsInside(sessionCount),
              style: TextStyle(
                color: AppTheme.disconnected,
                fontSize: AppFonts.lg,
              ),
            ),
          ],
        ],
      ),
    );
    if (confirmed) {
      await ref.read(sessionProvider.notifier).deleteFolder(folderPath);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: S.of(context).deleteSession,
      content: Text(
        S
            .of(context)
            .deleteSessionConfirm(
              session.label.isNotEmpty ? session.label : session.displayName,
            ),
      ),
    );
    if (confirmed) {
      await ref.read(sessionProvider.notifier).delete(session.id);
    }
  }
}
