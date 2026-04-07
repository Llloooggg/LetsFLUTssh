import 'package:flutter/material.dart';

import '../../core/shortcut_registry.dart';
import '../../l10n/app_localizations.dart';
import '../../core/session/qr_codec.dart';
import '../../core/session/session.dart';
import '../../core/session/session_tree.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_divider.dart';
import '../../widgets/hover_region.dart';

/// Dialog for selecting sessions to export via QR code.
///
/// Shows a tree of sessions with checkboxes, a live payload size indicator,
/// a disclaimer about credentials, and Export All / Show QR buttons.
class QrExportDialog extends StatefulWidget {
  final List<Session> sessions;
  final Set<String> emptyFolders;

  const QrExportDialog({
    super.key,
    required this.sessions,
    required this.emptyFolders,
  });

  /// Show the export dialog. Returns the QR payload string, or null if cancelled.
  static Future<String?> show(
    BuildContext context, {
    required List<Session> sessions,
    required Set<String> emptyFolders,
  }) {
    return AppDialog.show<String>(
      context,
      builder: (_) =>
          QrExportDialog(sessions: sessions, emptyFolders: emptyFolders),
    );
  }

  @override
  State<QrExportDialog> createState() => _QrExportDialogState();
}

class _QrExportDialogState extends State<QrExportDialog> {
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.sessions.map((s) => s.id).toSet();
  }

  List<Session> get _selectedSessions =>
      widget.sessions.where((s) => _selectedIds.contains(s.id)).toList();

  Set<String> get _relevantEmptyFolders {
    final selectedFolders = _selectedSessions.map((s) => s.folder).toSet();
    return widget.emptyFolders.where((g) {
      // Include empty folder if it or its parent is relevant
      return selectedFolders.any(
            (sf) => sf.startsWith(g) || g.startsWith(sf),
          ) ||
          _selectedIds.length == widget.sessions.length;
    }).toSet();
  }

  bool? get _tristateValue {
    if (_allSelected) return true;
    if (_selectedIds.isEmpty) return false;
    return null;
  }

  int get _payloadSize => _selectedSessions.isEmpty
      ? 0
      : calculateQrPayloadSize(
          _selectedSessions,
          emptyFolders: _relevantEmptyFolders,
        );

  bool get _fitsInQr => _payloadSize <= qrMaxPayloadBytes;
  bool get _hasSelection => _selectedIds.isNotEmpty;
  bool get _allSelected => _selectedIds.length == widget.sessions.length;

  void _toggleAll(bool select) {
    setState(() {
      if (select) {
        _selectedIds.addAll(widget.sessions.map((s) => s.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSession(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleFolder(String folderPath) {
    final folderSessionIds = widget.sessions
        .where(
          (s) => s.folder == folderPath || s.folder.startsWith('$folderPath/'),
        )
        .map((s) => s.id)
        .toSet();
    final allSelected = folderSessionIds.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(folderSessionIds);
      } else {
        _selectedIds.addAll(folderSessionIds);
      }
    });
  }

  bool? _isFolderPartial(String folderPath) {
    final folderSessionIds = widget.sessions
        .where(
          (s) => s.folder == folderPath || s.folder.startsWith('$folderPath/'),
        )
        .map((s) => s.id)
        .toSet();
    if (folderSessionIds.isEmpty) return false;
    final selectedCount = folderSessionIds.where(_selectedIds.contains).length;
    if (selectedCount == 0) return false;
    if (selectedCount == folderSessionIds.length) return true;
    return null; // partial
  }

  void _exportAll() {
    _toggleAll(true);
    if (!_fitsInQr) {
      _showTooLargeSnackbar();
      return;
    }
    _popWithDeepLink(
      _allSelected ? widget.emptyFolders : _relevantEmptyFolders,
    );
  }

  void _showQr() {
    _popWithDeepLink(_relevantEmptyFolders);
  }

  void _popWithDeepLink(Set<String> folders) {
    final payload = encodeSessionsForQr(
      _selectedSessions,
      emptyFolders: folders,
    );
    Navigator.of(context).pop(wrapInDeepLink(payload));
  }

  void _showTooLargeSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).qrTooManyForSingleCode),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tree = SessionTree.build(
      widget.sessions,
      emptyFolders: widget.emptyFolders,
    );
    final sizePercent = qrMaxPayloadBytes > 0
        ? (_payloadSize / qrMaxPayloadBytes).clamp(0.0, 1.0)
        : 0.0;
    final sizeColor = _fitsInQr ? AppTheme.green : AppTheme.red;

    return Dialog(
      backgroundColor: AppTheme.bg1,
      insetPadding: const EdgeInsets.all(24),
      child: CallbackShortcuts(
        bindings: AppShortcutRegistry.instance.buildCallbackMap({
          AppShortcut.dismissDialog: () => Navigator.of(context).pop(),
        }),
        child: Focus(
          autofocus: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppDialogHeader(
                  title: S.of(context).exportSessionsViaQr,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Disclaimer
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.1),
                            borderRadius: AppTheme.radiusLg,
                            border: Border.all(
                              color: AppTheme.accent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: AppTheme.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  S.of(context).qrNoCredentialsWarning,
                                  style: TextStyle(
                                    fontSize: AppFonts.md,
                                    color: AppTheme.fg,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Select All
                        HoverRegion(
                          onTap: () => _toggleAll(!_allSelected),
                          builder: (hovered) => Container(
                            color: hovered ? AppTheme.hover : null,
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _tristateValue,
                                  tristate: true,
                                  onChanged: (v) => _toggleAll(v == true),
                                ),
                                Text(
                                  'Select All (${_selectedIds.length}/${widget.sessions.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: AppFonts.md,
                                    color: AppTheme.fg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const AppDivider(),

                        // Session tree with checkboxes
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            children: _buildTreeItems(tree, 0),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Size indicator
                        Text(
                          'Payload: ${(_payloadSize / 1024).toStringAsFixed(1)} KB / '
                          '${(qrMaxPayloadBytes / 1024).toStringAsFixed(1)} KB max',
                          style: TextStyle(
                            fontSize: AppFonts.sm,
                            color: sizeColor,
                          ),
                        ),
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
                            style: TextStyle(
                              fontSize: AppFonts.sm,
                              color: AppTheme.red,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                AppDialogFooter(
                  actions: [
                    AppDialogAction.cancel(
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    AppDialogAction.secondary(
                      label: S.of(context).exportAll,
                      onTap: _exportAll,
                    ),
                    AppDialogAction.primary(
                      label: S.of(context).showQr,
                      enabled: _hasSelection && _fitsInQr,
                      onTap: _showQr,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
                  style: TextStyle(
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
              const Icon(Icons.computer, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  session.label.isNotEmpty
                      ? session.label
                      : session.displayName,
                  style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${session.user}@${session.host}',
                style: TextStyle(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
