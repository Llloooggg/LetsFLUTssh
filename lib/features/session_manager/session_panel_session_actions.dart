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
    if (result is! SaveResult) return;
    await applySessionSaveResult(ref, result, onConnect: widget.onConnect);
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
    // Kinds without a PTY (WebDAV / S3 today) cannot open a
    // terminal pane, so the "Open terminal" item is meaningless on
    // those rows — show only Files. The capability lives on
    // `SessionKind` (extension in `session.dart`) so a future kind
    // that gains a PTY needs no edit here.
    final hasTerminal = session.hasTerminal;
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        if (hasTerminal)
          StandardMenuAction.terminal.item(
            context,
            onTap: () => widget.onConnect(session),
          ),
        if (widget.onSftpConnect != null)
          StandardMenuAction.files.item(
            context,
            // For kinds without a PTY, the row-tap action is already
            // the file browser (via `SessionConnect.connectTerminal`'s
            // kind dispatch), so funnel the menu pick through the
            // same path — keeps the `onConnect` and `onSftpConnect`
            // semantics aligned with what the user sees on tap.
            onTap: () => hasTerminal
                ? widget.onSftpConnect?.call(session)
                : widget.onConnect(session),
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
        // Paste appears only with a copy/cut entry in the clipboard —
        // on an action surface an item that can do nothing right now is
        // hidden, not shown disabled (CLAUDE.md disable-vs-hide).
        if (_ctrl.hasClipboardEntry)
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
          onTap: () => ref.read(sessionMutatorProvider).duplicate(session.id),
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
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
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
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
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
              if (session.hasTerminal)
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
                    // For kinds without a PTY, route the Files tap
                    // through `onConnect` — `SessionConnect.connectTerminal`
                    // already dispatches by `hasTerminal`, and
                    // funnelling through it keeps both UI surfaces
                    // (this sheet + the desktop context menu)
                    // consistent.
                    if (session.hasTerminal) {
                      widget.onSftpConnect?.call(session);
                    } else {
                      widget.onConnect(session);
                    }
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
                  ref.read(sessionMutatorProvider).duplicate(session.id);
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
    final mutator = ref.read(sessionMutatorProvider);
    final allFolders = <String>{
      '',
      ...mutator.folders(),
      ...ref.read(emptyFoldersProvider),
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
      ref.read(sessionMutatorProvider).moveSession(session.id, selected);
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
          .read(sessionMutatorProvider)
          .updatePartial(
            result.session,
            passwordDirty: result.passwordDirty,
            keyDataDirty: result.keyDataDirty,
            passphraseDirty: result.passphraseDirty,
          );
      await syncSessionDetailsFromSaveResult(ref, result.session.id, result);
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
      // The `webdav_session_details` / `s3_session_details` join
      // rows drop via the FK `ON DELETE CASCADE` once the parent
      // `sessions` row goes; the SecretStore entry has no FK so
      // it gets dropped here before the row delete so a same-id
      // session created afterwards starts from a clean secret
      // slot.
      if (session.isWebDav) {
        rust_app.secretsDrop(
          id: rust_db.dbWebdavSessionDetailsSecretId(sessionId: session.id),
        );
      }
      if (session.isS3) {
        rust_app.secretsDrop(
          id: rust_db.dbS3SessionDetailsSecretId(sessionId: session.id),
        );
      }
      await ref.read(sessionMutatorProvider).delete(session.id);
    }
  }
}
