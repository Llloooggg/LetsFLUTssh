import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../core/ssh/ssh_config.dart';
import '../../providers/connection_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bordered_box.dart';
import '../../widgets/app_divider.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/context_menu.dart';
import '../../utils/platform.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/cross_marquee_controller.dart';
import '../../widgets/status_indicator.dart';
import '../tabs/tab_controller.dart';
import 'session_edit_dialog.dart';
import 'session_tree_view.dart';

const _kNewFolder = 'New Folder';
const _kNewConnection = 'New Connection';
const _kRenameFolder = 'Rename Folder';
const _kDeleteFolder = 'Delete Folder';

/// Session sidebar — tree view + search + actions.
class SessionPanel extends ConsumerStatefulWidget {
  final void Function(Session session) onConnect;
  final void Function(SSHConfig config) onQuickConnect;
  final void Function(Session session)? onSftpConnect;
  final CrossMarqueeController? crossMarquee;

  const SessionPanel({
    super.key,
    required this.onConnect,
    required this.onQuickConnect,
    this.onSftpConnect,
    this.crossMarquee,
  });

  @override
  ConsumerState<SessionPanel> createState() => SessionPanelState();
}

class SessionPanelState extends ConsumerState<SessionPanel> {
  final _focusNode = FocusNode();
  bool _selectMode = false;
  final _selectedIds = <String>{};
  final _selectedFolderPaths = <String>{};
  // Marquee state tracked for test visibility only.
  @visibleForTesting
  bool marqueeInProgress = false;

  // Focused session for keyboard shortcuts (single-click selection).
  String? _focusedSessionId;
  // Session clipboard — Ctrl+C stores the session ID, Ctrl+V duplicates it.
  String? _copiedSessionId;

  @visibleForTesting
  FocusNode get focusNode => _focusNode;
  @visibleForTesting
  String? get focusedSessionId => _focusedSessionId;
  @visibleForTesting
  bool get selectMode => _selectMode;
  @visibleForTesting
  Set<String> get selectedIds => _selectedIds;
  @visibleForTesting
  Set<String> get selectedFolderPaths => _selectedFolderPaths;

  /// Simulate marquee selection in tests.
  @visibleForTesting
  void setMarqueeSelection(Set<String> ids, [Set<String> folderPaths = const {}]) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(ids);
      _selectedFolderPaths
        ..clear()
        ..addAll(folderPaths);
    });
  }

  @visibleForTesting
  void simulateMarqueeStart() => setState(() => marqueeInProgress = true);

  @visibleForTesting
  void simulateMarqueeEnd() => setState(() => marqueeInProgress = false);

  @visibleForTesting
  void enterSelectModeWithSession(String sessionId) {
    setState(() {
      _selectMode = true;
      _selectedIds
        ..clear()
        ..add(sessionId);
      _selectedFolderPaths.clear();
    });
  }

  @visibleForTesting
  void enterSelectModeWithFolder(String folderPath) {
    setState(() {
      _selectMode = true;
      _selectedIds.clear();
      _selectedFolderPaths
        ..clear()
        ..add(folderPath);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
      _selectedFolderPaths.clear();
    });
  }

  void _clearDesktopSelection() {
    setState(() {
      _selectedIds.clear();
      _selectedFolderPaths.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleFolderSelected(String folderPath) {
    setState(() {
      if (_selectedFolderPaths.contains(folderPath)) {
        _selectedFolderPaths.remove(folderPath);
      } else {
        _selectedFolderPaths.add(folderPath);
      }
    });
  }

  void _selectAll() {
    final sessions = ref.read(filteredSessionsProvider);
    setState(() {
      _selectedIds.addAll(sessions.map((s) => s.id));
    });
  }

  Future<void> _deleteSelected(BuildContext context) async {
    if (_selectedIds.isEmpty && _selectedFolderPaths.isEmpty) return;
    final sessionCount = _selectedIds.length;
    final folderCount = _selectedFolderPaths.length;
    final parts = <String>[
      if (sessionCount > 0) '$sessionCount session(s)',
      if (folderCount > 0) '$folderCount folder(s)',
    ];
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Selected',
      content: Text('Delete ${parts.join(' and ')}?\n\nThis cannot be undone.'),
    );
    if (confirmed) {
      final notifier = ref.read(sessionProvider.notifier);
      if (_selectedIds.isNotEmpty) {
        await notifier.deleteMultiple(Set.of(_selectedIds));
      }
      for (final folderPath in _selectedFolderPaths) {
        await notifier.deleteFolder(folderPath);
      }
      if (_selectMode) {
        _exitSelectMode();
      } else {
        _clearDesktopSelection();
      }
    }
  }

  Future<void> _moveSelected(BuildContext context) async {
    if (_selectedIds.isEmpty && _selectedFolderPaths.isEmpty) return;
    final store = ref.read(sessionStoreProvider);
    final allFolders = <String>{'', ...store.folders(), ...store.emptyFolders};

    final selected = await showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allFolders.length,
            itemBuilder: (ctx, index) {
              final folder = allFolders.elementAt(index);
              return ListTile(
                leading: Icon(folder.isEmpty ? Icons.home : Icons.folder),
                title: Text(folder.isEmpty ? '/ (root)' : folder),
                onTap: () => Navigator.of(ctx).pop(folder),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null) {
      await _applyMove(selected);
    }
  }

  Future<void> _applyMove(String target) async {
    final notifier = ref.read(sessionProvider.notifier);
    if (_selectedIds.isNotEmpty) {
      await notifier.moveMultiple(Set.of(_selectedIds), target);
    }
    for (final folderPath in _selectedFolderPaths) {
      await notifier.moveFolder(folderPath, target);
    }
    if (_selectMode) {
      _exitSelectMode();
    } else {
      _clearDesktopSelection();
    }
  }

  /// Build set of session IDs that have an active connection.
  Set<String> _connectedSessionIds(WidgetRef ref) {
    final connections = ref.watch(connectionsProvider).value ?? [];
    return connections
        .where((c) => c.isConnected && c.sessionId != null)
        .map((c) => c.sessionId!)
        .toSet();
  }

  Set<String> _connectingSessionIds(WidgetRef ref) {
    final connections = ref.watch(connectionsProvider).value ?? [];
    return connections
        .where((c) => c.isConnecting && c.sessionId != null)
        .map((c) => c.sessionId!)
        .toSet();
  }

  /// Copy the focused session to the clipboard.
  @visibleForTesting
  void copyFocusedSession() {
    if (_focusedSessionId != null) {
      _copiedSessionId = _focusedSessionId;
    }
  }

  /// Paste (duplicate) the copied session.
  @visibleForTesting
  void pasteCopiedSession() {
    if (_copiedSessionId != null) {
      ref.read(sessionProvider.notifier).duplicate(_copiedSessionId!);
    }
  }

  /// Delete the focused session (shows confirmation dialog).
  @visibleForTesting
  void deleteFocusedSession() {
    final id = _focusedSessionId;
    if (id == null) return;
    final sessions = ref.read(sessionProvider);
    final session = sessions.where((s) => s.id == id).firstOrNull;
    if (session == null) return;
    _confirmDelete(context, ref, session);
  }

  /// Edit the focused session (shows edit dialog).
  @visibleForTesting
  void editFocusedSession() {
    final id = _focusedSessionId;
    if (id == null) return;
    final sessions = ref.read(sessionProvider);
    final session = sessions.where((s) => s.id == id).firstOrNull;
    if (session == null) return;
    _editSession(context, ref, session);
  }

  KeyEventResult _handleCtrlKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.keyZ) {
      ref.read(sessionProvider.notifier).undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyY) {
      ref.read(sessionProvider.notifier).redo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      copyFocusedSession();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyV) {
      pasteCopiedSession();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handlePlainKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.delete) {
      if (_focusedSessionId == null) return KeyEventResult.ignored;
      deleteFocusedSession();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2) {
      if (_focusedSessionId == null) return KeyEventResult.ignored;
      editFocusedSession();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isCtrl = HardwareKeyboard.instance.logicalKeysPressed
        .intersection({LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight})
        .isNotEmpty;

    if (isCtrl) return _handleCtrlKey(event.logicalKey);
    return _handlePlainKey(event.logicalKey);
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(filteredSessionTreeProvider);
    final searchQuery = ref.watch(sessionSearchProvider);
    final isEmpty = tree.isEmpty;

    final mobile = isMobilePlatform;

    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _focusNode,
      autofocus: false,
      onKeyEvent: _onKeyEvent,
      child: Container(
      color: scheme.surfaceContainerLow,
      child: Column(
      children: [
        if (_selectMode && mobile)
          _SelectActionBar(
            selectedCount: _selectedIds.length,
            onSelectAll: _selectAll,
            onDelete: () => _deleteSelected(context),
            onMove: () => _moveSelected(context),
            onCancel: _exitSelectMode,
          )
        else ...[
          // Header with title + add/select buttons
          _PanelHeader(
            onAddSession: () => _addSession(context, ref),
            onAddFolder: () => _createFolder(context, ref, ''),
          ),
          // Search bar
          _SearchBar(
            value: searchQuery,
            onChanged: (v) => ref.read(sessionSearchProvider.notifier).set(v),
          ),
          // Desktop marquee selection is shown inline via row highlights.
          // Bulk actions available via right-click context menu.
        ],
        // Tree view
        Expanded(
          child: isEmpty
              ? _EmptyState(onAdd: () => _addSession(context, ref))
              : SessionTreeView(
                  tree: tree,
                  connectedSessionIds: _connectedSessionIds(ref),
                  connectingSessionIds: _connectingSessionIds(ref),
                  selectMode: mobile && _selectMode,
                  selectedIds: _selectedIds,
                  onToggleSelected: _toggleSelected,
                  selectedFolderPaths: _selectedFolderPaths,
                  onToggleFolderSelected: _toggleFolderSelected,
                  crossMarquee: widget.crossMarquee,
                  onSessionDoubleTap: widget.onConnect,
                  onSessionSelected: (id) {
                    _focusedSessionId = id;
                    _focusNode.requestFocus();
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
                    _clearDesktopSelection();
                  },
                  onMarqueeStart: () => setState(() => marqueeInProgress = true),
                  onMarqueeEnd: () => setState(() => marqueeInProgress = false),
                  onMarqueeSelect: (ids, folderPaths) {
                    setState(() {
                      _selectedIds
                        ..clear()
                        ..addAll(ids);
                      _selectedFolderPaths
                        ..clear()
                        ..addAll(folderPaths);
                    });
                  },
                ),
        ),
        // Footer — only on desktop (mobile shows counts in MobileShell header)
        if (!mobile) const _SidebarFooter(),
      ],
    ),
    ),
    );
  }

  Future<void> _handleDialogResult(WidgetRef ref, SessionDialogResult result) async {
    switch (result) {
      case ConnectOnlyResult(:final config):
        widget.onQuickConnect(config);
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
          label: 'Terminal',
          icon: Icons.terminal,
          color: AppTheme.blue,
          onTap: () => widget.onConnect(session),
        ),
        if (widget.onSftpConnect != null)
          ContextMenuItem(
            label: 'Files',
            icon: Icons.folder,
            color: AppTheme.yellow,
            onTap: () => widget.onSftpConnect?.call(session),
          ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          label: 'Edit Connection',
          icon: Icons.settings,
          onTap: () => _editSession(context, ref, session),
        ),
        ContextMenuItem(
          label: 'Duplicate',
          icon: Icons.copy,
          onTap: () => ref.read(sessionProvider.notifier).duplicate(session.id),
        ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          label: 'Delete',
          icon: Icons.delete,
          color: AppTheme.red,
          onTap: () => _confirmDelete(context, ref, session),
        ),
      ],
    );
  }

  void _showMobileSessionSheet(BuildContext context, WidgetRef ref, Session session) {
    final label = session.label.isNotEmpty ? session.label : session.displayName;
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
                  style: TextStyle(fontSize: AppFonts.xl, fontWeight: FontWeight.w600),
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
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              const AppDivider(),
              ListTile(
                leading: Icon(Icons.terminal, color: AppTheme.blue),
                title: const Text('Terminal'),
                onTap: () { Navigator.pop(ctx); widget.onConnect(session); },
              ),
              if (widget.onSftpConnect != null)
                ListTile(
                  leading: Icon(Icons.folder, color: AppTheme.yellow),
                  title: const Text('Files'),
                  onTap: () { Navigator.pop(ctx); widget.onSftpConnect?.call(session); },
                ),
              const AppDivider(),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Edit Connection'),
                onTap: () { Navigator.pop(ctx); _editSession(context, ref, session); },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Duplicate'),
                onTap: () { Navigator.pop(ctx); ref.read(sessionProvider.notifier).duplicate(session.id); },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move),
                title: const Text('Move to...'),
                onTap: () { Navigator.pop(ctx); _moveSession(context, ref, session); },
              ),
              const AppDivider(),
              ListTile(
                leading: const Icon(Icons.delete, color: AppTheme.disconnected),
                title: const Text('Delete', style: TextStyle(color: AppTheme.disconnected)),
                onTap: () { Navigator.pop(ctx); _confirmDelete(context, ref, session); },
              ),
              const AppDivider(),
              ListTile(
                leading: const Icon(Icons.checklist),
                title: const Text('Select'),
                onTap: () { Navigator.pop(ctx); enterSelectModeWithSession(session.id); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _moveSession(BuildContext context, WidgetRef ref, Session session) async {
    final store = ref.read(sessionStoreProvider);
    final allFolders = <String>{'', ...store.folders(), ...store.emptyFolders};

    final selected = await showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Folder'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allFolders.length,
            itemBuilder: (ctx, index) => _buildMoveFolderTile(
              ctx, allFolders.elementAt(index), session.folder,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null) {
      ref.read(sessionProvider.notifier).moveSession(session.id, selected);
    }
  }

  Widget _buildMoveFolderTile(BuildContext context, String folder, String currentFolder) {
    final isCurrent = folder == currentFolder;
    return ListTile(
      leading: Icon(
        folder.isEmpty ? Icons.home : Icons.folder,
        color: isCurrent ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        folder.isEmpty ? '/ (root)' : folder,
        style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : null),
      ),
      trailing: isCurrent ? const Icon(Icons.check, size: 18) : null,
      onTap: isCurrent ? null : () => Navigator.of(context).pop(folder),
    );
  }

  Future<void> _editSession(BuildContext context, WidgetRef ref, Session session) async {
    final result = await SessionEditDialog.show(
      context,
      session: session,
    );
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
          label: _kNewConnection,
          icon: Icons.add,
          onTap: () => _addSessionInFolder(context, ref, folderPath),
        ),
        ContextMenuItem(
          label: _kNewFolder,
          icon: Icons.create_new_folder,
          onTap: () => _createFolder(context, ref, folderPath),
        ),
        if (folderPath.isNotEmpty) ...[
          const ContextMenuItem.divider(),
          ContextMenuItem(
            label: _kRenameFolder,
            icon: Icons.drive_file_rename_outline,
            onTap: () => _renameFolder(context, ref, folderPath),
          ),
          ContextMenuItem(
            label: _kDeleteFolder,
            icon: Icons.delete,
            color: AppTheme.red,
            onTap: () => _confirmDeleteFolder(context, ref, folderPath),
          ),
        ],
      ],
    );
  }

  void _showMobileFolderSheet(BuildContext context, WidgetRef ref, String folderPath) {
    final folderName = folderPath.isEmpty ? 'Root' : folderPath.split('/').last;
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
                  style: TextStyle(fontSize: AppFonts.xl, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const AppDivider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text(_kNewConnection),
                onTap: () { Navigator.pop(ctx); _addSessionInFolder(context, ref, folderPath); },
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder),
                title: const Text('New Folder'),
                onTap: () { Navigator.pop(ctx); _createFolder(context, ref, folderPath); },
              ),
              if (folderPath.isNotEmpty) ...[
                const AppDivider(),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text(_kRenameFolder),
                  onTap: () { Navigator.pop(ctx); _renameFolder(context, ref, folderPath); },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: AppTheme.disconnected),
                  title: const Text(_kDeleteFolder, style: TextStyle(color: AppTheme.disconnected)),
                  onTap: () { Navigator.pop(ctx); _confirmDeleteFolder(context, ref, folderPath); },
                ),
                const AppDivider(),
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: const Text('Select'),
                  onTap: () { Navigator.pop(ctx); enterSelectModeWithFolder(folderPath); },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addSessionInFolder(BuildContext context, WidgetRef ref, String folderPath) async {
    final result = await SessionEditDialog.show(
      context,
      defaultFolder: folderPath,
    );
    if (result == null) return;
    await _handleDialogResult(ref, result);
  }

  Future<void> _createFolder(BuildContext context, WidgetRef ref, String parentFolder) async {
    final existingFolders = _collectAllFolderPaths(ref);

    final result = await _showFolderNameDialog(
      context,
      title: _kNewFolder,
      confirmLabel: 'Create',
      existingFolders: existingFolders,
      parentPath: parentFolder,
    );

    if (result == null || result.trim().isEmpty) return;

    final newFolder = parentFolder.isEmpty ? result.trim() : '$parentFolder/${result.trim()}';
    await ref.read(sessionProvider.notifier).addEmptyFolder(newFolder);
  }

  Future<void> _renameFolder(BuildContext context, WidgetRef ref, String folderPath) async {
    // Extract the folder's own name (last segment)
    final parts = folderPath.split('/');
    final currentName = parts.last;
    final parentPath = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '';

    final existingFolders = _collectAllFolderPaths(ref);

    final result = await _showFolderNameDialog(
      context,
      title: _kRenameFolder,
      confirmLabel: 'Rename',
      initialValue: currentName,
      existingFolders: existingFolders,
      parentPath: parentPath,
      currentName: currentName,
    );

    if (result == null || result.trim().isEmpty || result.trim() == currentName) return;

    final newPath = parentPath.isEmpty ? result.trim() : '$parentPath/${result.trim()}';
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
                final fullPath = parentPath.isEmpty ? name : '$parentPath/$name';
                final isDuplicate = name.isNotEmpty
                    && name != currentName
                    && existingFolders.contains(fullPath);
                setDialogState(() {
                  errorText = isDuplicate ? 'Folder "$name" already exists' : null;
                });
              },
              hintText: 'e.g. Production',
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
    return Dialog(
      backgroundColor: AppTheme.bg1,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: AppTheme.borderBottom,
              ),
              child: Row(
                children: [
                  Text(
                    title,
                    style: AppFonts.inter(
                      fontSize: AppFonts.md,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.fg,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close, size: 13, color: AppTheme.fgDim),
                  ),
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FOLDER NAME',
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
                      hintStyle: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fgFaint),
                      filled: true,
                      fillColor: AppTheme.bg3,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            ),
            // Footer
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: AppTheme.borderTop,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      child: Text(
                        'Cancel',
                        style: AppFonts.inter(
                          fontSize: AppFonts.sm,
                          color: AppTheme.fgDim,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: errorText == null
                        ? () => Navigator.of(context).pop(nameCtrl.text)
                        : null,
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: errorText == null ? AppTheme.accent : AppTheme.bg4,
                      ),
                      child: Text(
                        confirmLabel,
                        style: AppFonts.inter(
                          fontSize: AppFonts.sm,
                          fontWeight: FontWeight.w500,
                          color: errorText == null ? AppTheme.onAccent : AppTheme.fgFaint,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteFolder(BuildContext context, WidgetRef ref, String folderPath) async {
    final store = ref.read(sessionStoreProvider);
    final sessionCount = store.countSessionsInFolder(folderPath);
    final folderName = folderPath.split('/').last;

    final confirmed = await ConfirmDialog.show(
      context,
      title: _kDeleteFolder,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delete folder "$folderName"?'),
          if (sessionCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              'This will also delete $sessionCount session(s) inside.',
              style: TextStyle(color: AppTheme.disconnected, fontSize: AppFonts.lg),
            ),
          ],
        ],
      ),
    );
    if (confirmed) {
      await ref.read(sessionProvider.notifier).deleteFolder(folderPath);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Session session) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Session',
      content: Text('Delete "${session.label.isNotEmpty ? session.label : session.displayName}"?'),
    );
    if (confirmed) {
      await ref.read(sessionProvider.notifier).delete(session.id);
    }
  }

}

class _PanelHeader extends StatelessWidget {
  final VoidCallback onAddSession;
  final VoidCallback onAddFolder;
  const _PanelHeader({
    required this.onAddSession,
    required this.onAddFolder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'SESSIONS',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppFonts.sm,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.create_new_folder,
            onTap: onAddFolder,
            tooltip: _kNewFolder,
            size: 14,
            boxSize: 24,
          ),
          AppIconButton(
            icon: Icons.add,
            onTap: onAddSession,
            tooltip: _kNewConnection,
            size: 16,
            boxSize: 24,
          ),
        ],
      ),
    );
  }
}

class _SelectActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onCancel;

  const _SelectActionBar({
    required this.selectedCount,
    required this.onSelectAll,
    required this.onDelete,
    required this.onMove,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            '$selectedCount selected',
            style: TextStyle(fontSize: AppFonts.md, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
          ),
          const Spacer(),
          AppIconButton(
            icon: Icons.select_all,
            onTap: onSelectAll,
            tooltip: 'Select All',
            size: 18,
          ),
          AppIconButton(
            icon: Icons.drive_file_move,
            onTap: selectedCount > 0 ? onMove : null,
            tooltip: 'Move to...',
            size: 18,
          ),
          AppIconButton(
            icon: Icons.delete,
            onTap: selectedCount > 0 ? onDelete : null,
            tooltip: 'Delete',
            size: 18,
            color: selectedCount > 0 ? AppTheme.disconnected : null,
          ),
          AppIconButton(
            icon: Icons.close,
            onTap: onCancel,
            tooltip: 'Cancel',
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: AppBorderedBox(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: AppTheme.bg3,
        child: Row(
          children: [
            Icon(Icons.search, size: 12, color: AppTheme.fgFaint),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Filter...',
                  hintStyle: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fgFaint),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
                onChanged: onChanged,
              ),
            ),
            if (value.isNotEmpty)
              GestureDetector(
                onTap: () => onChanged(''),
                child: Icon(Icons.close, size: 12, color: AppTheme.fgFaint),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            'No saved sessions',
            style: TextStyle(
              fontSize: AppFonts.md,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: Text('Add Session', style: TextStyle(fontSize: AppFonts.md)),
          ),
        ],
      ),
    );
  }
}

class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedCount = ref.watch(sessionProvider).length;
    final connections = ref.watch(connectionsProvider).value ?? [];
    final connectedCount = connections.where((c) => c.isConnected).length;
    final connectingCount = connections.where((c) => c.isConnecting).length;
    final activeCount = connectedCount + connectingCount;
    final tabState = ref.watch(tabProvider);
    final tabCount = tabState.tabs.length;

    final theme = Theme.of(context);
    final Color? connectionIconColor = connectedCount > 0
        ? AppTheme.connectedColor(theme.brightness)
        : connectingCount > 0
            ? AppTheme.connectingColor(theme.brightness)
            : null;

    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          StatusIndicator(
            icon: Icons.dns_outlined,
            count: savedCount,
            tooltip: 'Saved sessions',
          ),
          const Spacer(),
          StatusIndicator(
            icon: Icons.wifi,
            count: activeCount,
            tooltip: 'Active connections',
            iconColor: connectionIconColor,
          ),
          const SizedBox(width: 10),
          StatusIndicator(
            icon: Icons.tab_outlined,
            count: tabCount,
            tooltip: 'Open tabs',
          ),
        ],
      ),
    );
  }
}

