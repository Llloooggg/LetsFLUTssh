part of 'file_pane.dart';

/// Context-menu + dialog handlers for the file pane. Lives as an
/// extension on [_FilePaneState] so the methods reach `ctrl` /
/// `widget` and the dialog wrappers route through `FilePaneDialogs`
/// the same way they did inside the State class; `part of` joins
/// the file into the same library so library-private names stay
/// reachable.
extension _Actions on _FilePaneState {
  void _showBackgroundContextMenu(BuildContext context, Offset position) {
    ctrl.clearSelection();
    showAppContextMenu(
      context: context,
      position: position,
      items: [
        StandardMenuAction.newFolder.item(
          context,
          onTap: () => _showNewFolderDialog(context),
        ),
        StandardMenuAction.refresh.item(
          context,
          shortcut: AppShortcut.fileRefresh,
          onTap: () => ctrl.refresh(),
        ),
      ],
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    FileEntry entry,
  ) {
    if (!ctrl.selected.contains(entry.path)) {
      ctrl.selectSingle(entry.path);
    }

    final selectedEntries = ctrl.selectedEntries;
    final hasMultiple = selectedEntries.length > 1;

    showAppContextMenu(
      context: context,
      position: position,
      items: [
        if (!hasMultiple && entry.isDir)
          StandardMenuAction.open.item(
            context,
            onTap: () => ctrl.navigateTo(entry.path),
          ),
        StandardMenuAction.transfer.item(
          context,
          labelOverride: hasMultiple
              ? S.of(context).transferNItems(selectedEntries.length)
              : null,
          onTap: () {
            if (hasMultiple) {
              widget.onTransferMultiple?.call(selectedEntries);
            } else {
              widget.onTransfer?.call(entry);
            }
          },
        ),
        const ContextMenuItem.divider(),
        StandardMenuAction.newFolder.item(
          context,
          onTap: () => _showNewFolderDialog(context),
        ),
        if (!hasMultiple)
          StandardMenuAction.rename.item(
            context,
            shortcut: AppShortcut.fileRename,
            onTap: () => _showRenameDialog(context, entry),
          ),
        StandardMenuAction.delete.item(
          context,
          labelOverride: hasMultiple
              ? S.of(context).deleteNItems(selectedEntries.length)
              : null,
          onTap: () => _confirmDelete(context, selectedEntries),
        ),
      ],
    );
  }

  // ── Dialogs (delegated to FilePaneDialogs) ──

  Future<void> _showNewFolderDialog(BuildContext context) =>
      FilePaneDialogs.showNewFolder(context, ctrl);

  Future<void> _showRenameDialog(BuildContext context, FileEntry entry) =>
      FilePaneDialogs.showRename(context, ctrl, entry);

  Future<void> _confirmDelete(BuildContext context, List<FileEntry> entries) =>
      FilePaneDialogs.confirmDelete(context, ctrl, entries);
}
