part of 'session_panel.dart';

/// Per-folder action menu — context menu (desktop) or bottom sheet
/// (mobile), plus the create / rename / delete dialogs the menu items
/// invoke. Lives as an extension on [SessionPanelState] so the
/// methods reach private controller state without going through a
/// public surface; `part of` joins the file into the same library so
/// the underscore names stay reachable.
extension _FolderActions on SessionPanelState {
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
        StandardMenuAction.newConnection.item(
          context,
          onTap: () => _addSessionInFolder(context, ref, folderPath),
        ),
        StandardMenuAction.newFolder.item(
          context,
          onTap: () => _createFolder(context, ref, folderPath),
        ),
        // Paste lands directly inside the right-clicked folder — the
        // explicit target overrides the focus-derived default, so the
        // user does not have to pre-focus the folder.
        StandardMenuAction.paste.item(
          context,
          shortcut: AppShortcut.sessionPaste,
          onTap: () => pasteCopiedSession(explicitTarget: folderPath),
        ),
        if (folderPath.isNotEmpty) ...[
          const ContextMenuItem.divider(),
          StandardMenuAction.copy.item(
            context,
            shortcut: AppShortcut.sessionCopy,
            onTap: () => _ctrl.copyFolderPath(folderPath),
          ),
          StandardMenuAction.cut.item(
            context,
            shortcut: AppShortcut.sessionCut,
            onTap: () => _ctrl.cutFolderPath(folderPath),
          ),
          const ContextMenuItem.divider(),
          StandardMenuAction.renameFolder.item(
            context,
            onTap: () => _renameFolder(context, ref, folderPath),
          ),
          StandardMenuAction.editTags.item(
            context,
            onTap: () {
              final folderId = ref
                  .read(sessionProvider.notifier)
                  .folderIdByPath(folderPath);
              if (folderId != null) {
                TagAssignDialog.showForFolder(context, folderId: folderId);
              }
            },
          ),
          StandardMenuAction.deleteFolder.item(
            context,
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
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
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
                  leading: const Icon(Icons.copy),
                  title: Text(S.of(ctx).copy),
                  onTap: () {
                    Navigator.pop(ctx);
                    _ctrl.copyFolderPath(folderPath);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.content_cut),
                  title: Text(S.of(ctx).cut),
                  onTap: () {
                    Navigator.pop(ctx);
                    _ctrl.cutFolderPath(folderPath);
                  },
                ),
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
    final notifier = ref.read(sessionProvider.notifier);
    final result = <String>{};
    for (final g in [...notifier.folders(), ...notifier.emptyFolders]) {
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
              fontFamily: AppFonts.interFamily,
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
    final sessionCount = ref
        .read(sessionProvider.notifier)
        .countSessionsInFolder(folderPath);
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
}
