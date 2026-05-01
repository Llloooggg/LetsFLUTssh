part of 'session_panel.dart';

/// Per-session action menu — context menu (desktop) or bottom sheet
/// (mobile), plus the add / edit / move / confirm-delete flows the
/// menu items invoke. Lives as an extension on
/// [SessionPanelState] so the methods reach private controller state
/// (`_ctrl`, `_focusNode`, …) without going through a public surface;
/// `part of` joins the file into the same library so the underscore
/// names stay reachable.
extension _SessionActions on SessionPanelState {
  Future<void> _handleDialogResult(
    WidgetRef ref,
    SessionDialogResult result,
  ) async {
    switch (result) {
      case SaveResult(:final session, :final connect, :final forwards):
        await ref.read(sessionProvider.notifier).add(session);
        await _syncForwards(ref, session.id, forwards);
        if (connect) widget.onConnect(session);
    }
  }

  /// Diff the rule list against what the store holds for [sessionId]
  /// and write the delta. Removed rules drop via `deletePortForward`,
  /// added or edited rules go through `upsertPortForward` (which is
  /// idempotent on the rule id). Runs in its own pass after the
  /// session row commits so the FK constraint sees a real parent.
  Future<void> _syncForwards(
    WidgetRef ref,
    String sessionId,
    List<PortForwardRule> nextRules,
  ) async {
    final existing = await loadPortForwards(sessionId);
    final keep = nextRules.map((r) => r.id).toSet();
    for (final old in existing) {
      if (!keep.contains(old.id)) {
        await deletePortForward(old.id);
      }
    }
    for (final r in nextRules) {
      await upsertPortForward(sessionId, r);
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
        StandardMenuAction.terminal.item(
          context,
          onTap: () => widget.onConnect(session),
        ),
        if (widget.onSftpConnect != null)
          StandardMenuAction.files.item(
            context,
            onTap: () => widget.onSftpConnect?.call(session),
          ),
        const ContextMenuItem.divider(),
        StandardMenuAction.copy.item(
          context,
          shortcut: AppShortcut.sessionCopy,
          onTap: () => _ctrl.copySessionId(session.id),
        ),
        StandardMenuAction.cut.item(
          context,
          shortcut: AppShortcut.sessionCut,
          onTap: () => _ctrl.cutSessionId(session.id),
        ),
        // Paste is always visible — matches Finder / Explorer / Nautilus,
        // where the entry stays present and silently no-ops when the
        // clipboard is empty. Hiding it would make the menu layout jitter
        // between copy-then-paste actions.
        StandardMenuAction.paste.item(
          context,
          shortcut: AppShortcut.sessionPaste,
          onTap: () => pasteCopiedSession(explicitTarget: session.folder),
        ),
        const ContextMenuItem.divider(),
        StandardMenuAction.editConnection.item(
          context,
          onTap: () => _editSession(context, ref, session),
        ),
        StandardMenuAction.duplicate.item(
          context,
          onTap: () => ref.read(sessionProvider.notifier).duplicate(session.id),
        ),
        const ContextMenuItem.divider(),
        StandardMenuAction.delete.item(
          context,
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
    final notifier = ref.read(sessionProvider.notifier);
    final allFolders = <String>{
      '',
      ...notifier.folders(),
      ...notifier.emptyFolders,
    };

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
    // The cached [session] no longer carries plaintext credentials —
    // the edit dialog renders "[Saved]" badges off the per-slot
    // `hasStoredPassword` / `hasStoredKeyData` / `hasStoredPassphrase`
    // flags and only writes the secret columns whose dirty bits the
    // user flipped. No `loadWithCredentials` round-trip; no plaintext
    // on the Dart heap during the edit.
    final result = await SessionEditDialog.show(context, session: session);
    if (result == null) return;
    if (result is SaveResult) {
      await ref
          .read(sessionProvider.notifier)
          .updatePartial(
            result.session,
            passwordDirty: result.passwordDirty,
            keyDataDirty: result.keyDataDirty,
            passphraseDirty: result.passphraseDirty,
          );
      await _syncForwards(ref, result.session.id, result.forwards);
      if (result.connect) widget.onConnect(result.session);
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
