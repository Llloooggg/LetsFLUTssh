part of 'unified_export_dialog.dart';

/// Tree rendering + size-indicator builders split off from the main
/// state class to shrink that 1000-line block. These are `extension`
/// methods so they can stay in a sibling `part of` file without
/// changing the public API or losing access to the private state
/// fields they touch.
extension _TreeBuilders on _UnifiedExportDialogState {
  List<Widget> _buildTreeItems(List<SessionTreeNode> nodes, int depth) {
    final items = <Widget>[];
    for (final node in nodes) {
      if (node.isGroup) {
        items.add(_buildGroupItem(node, depth));
        items.addAll(_buildTreeItems(node.children, depth + 1));
      } else if (node.session != null) {
        items.add(_buildSessionItem(node.session!, depth));
      }
    }
    return items;
  }

  Widget _buildGroupItem(SessionTreeNode node, int depth) {
    final tristate = _isFolderPartial(node.fullPath);
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0),
      child: HoverRegion(
        onTap: () => _toggleFolder(node.fullPath),
        builder: (hovered) => Container(
          color: hovered ? AppTheme.hover : null,
          child: Row(
            children: [
              Checkbox(
                value: tristate,
                tristate: true,
                onChanged: (_) => _toggleFolder(node.fullPath),
              ),
              const Icon(Icons.folder, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  node.name,
                  style: AppFonts.inter(
                    fontSize: AppFonts.md,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.fg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionItem(Session session, int depth) {
    final isSelected = _selectedIds.contains(session.id);
    final isIncomplete = !session.isValid;
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0),
      child: HoverRegion(
        onTap: () => _toggleSession(session.id),
        builder: (hovered) => Container(
          color: hovered ? AppTheme.hover : null,
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSession(session.id),
              ),
              Icon(
                isIncomplete ? Icons.warning_amber : Icons.computer,
                size: 16,
                color: isIncomplete ? AppTheme.orange : AppTheme.fg,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  session.label.isNotEmpty
                      ? session.label
                      : session.displayName,
                  style: AppFonts.inter(
                    fontSize: AppFonts.md,
                    color: isIncomplete ? AppTheme.orange : AppTheme.fg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeIndicator(double sizePercent, Color sizeColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isQrMode)
          Text(
            S
                .of(context)
                .qrPayloadSize(
                  (_payloadSize / 1024).toStringAsFixed(1),
                  (qrMaxPayloadBytes / 1024).toStringAsFixed(1),
                ),
            style: AppFonts.inter(fontSize: AppFonts.sm, color: sizeColor),
          )
        else
          Text(
            S.of(context).exportTotalSize(_formatSize(_payloadSize)),
            style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        if (widget.isQrMode) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: AppTheme.radiusSm,
            child: LinearProgressIndicator(
              value: sizePercent,
              backgroundColor: AppTheme.bg3,
              color: sizeColor,
            ),
          ),
          if (!_fitsInQr && _hasSelection) ...[
            const SizedBox(height: 8),
            Text(
              S.of(context).qrTooLarge,
              style: AppFonts.inter(fontSize: AppFonts.sm, color: AppTheme.red),
            ),
          ],
        ],
      ],
    );
  }
}
