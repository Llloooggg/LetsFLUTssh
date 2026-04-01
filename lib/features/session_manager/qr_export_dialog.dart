import 'package:flutter/material.dart';

import '../../core/session/qr_codec.dart';
import '../../core/session/session.dart';
import '../../core/session/session_tree.dart';
import '../../theme/app_theme.dart';

/// Dialog for selecting sessions to export via QR code.
///
/// Shows a tree of sessions with checkboxes, a live payload size indicator,
/// a disclaimer about credentials, and Export All / Show QR buttons.
class QrExportDialog extends StatefulWidget {
  final List<Session> sessions;
  final Set<String> emptyGroups;

  const QrExportDialog({
    super.key,
    required this.sessions,
    required this.emptyGroups,
  });

  /// Show the export dialog. Returns the QR payload string, or null if cancelled.
  static Future<String?> show(
    BuildContext context, {
    required List<Session> sessions,
    required Set<String> emptyGroups,
  }) {
    return showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => QrExportDialog(
        sessions: sessions,
        emptyGroups: emptyGroups,
      ),
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

  Set<String> get _relevantEmptyGroups {
    final selectedGroups = _selectedSessions.map((s) => s.group).toSet();
    return widget.emptyGroups.where((g) {
      // Include empty group if it or its parent is relevant
      return selectedGroups.any((sg) => sg.startsWith(g) || g.startsWith(sg)) ||
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
          emptyGroups: _relevantEmptyGroups,
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

  void _toggleGroup(String groupPath) {
    final groupSessionIds = widget.sessions
        .where((s) => s.group == groupPath || s.group.startsWith('$groupPath/'))
        .map((s) => s.id)
        .toSet();
    final allSelected = groupSessionIds.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(groupSessionIds);
      } else {
        _selectedIds.addAll(groupSessionIds);
      }
    });
  }

  bool? _isGroupPartial(String groupPath) {
    final groupSessionIds = widget.sessions
        .where((s) => s.group == groupPath || s.group.startsWith('$groupPath/'))
        .map((s) => s.id)
        .toSet();
    if (groupSessionIds.isEmpty) return false;
    final selectedCount = groupSessionIds.where(_selectedIds.contains).length;
    if (selectedCount == 0) return false;
    if (selectedCount == groupSessionIds.length) return true;
    return null; // partial
  }

  void _exportAll() {
    _toggleAll(true);
    if (!_fitsInQr) {
      _showTooLargeSnackbar();
      return;
    }
    _popWithDeepLink(_allSelected ? widget.emptyGroups : _relevantEmptyGroups);
  }

  void _showQr() {
    _popWithDeepLink(_relevantEmptyGroups);
  }

  void _popWithDeepLink(Set<String> groups) {
    final payload = encodeSessionsForQr(_selectedSessions, emptyGroups: groups);
    Navigator.of(context).pop(wrapInDeepLink(payload));
  }

  void _showTooLargeSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Too many sessions for a single QR code. Deselect some or use .lfs export.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tree = SessionTree.build(widget.sessions, emptyGroups: widget.emptyGroups);
    final sizePercent = qrMaxPayloadBytes > 0
        ? (_payloadSize / qrMaxPayloadBytes).clamp(0.0, 1.0)
        : 0.0;
    final sizeColor = _fitsInQr ? theme.colorScheme.primary : AppTheme.disconnected;

    return AlertDialog(
      title: const Text('Export Sessions via QR'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Disclaimer
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Passwords and SSH keys are NOT included.\n'
                      'Imported sessions will need credentials filled in.',
                      style: TextStyle(fontSize: AppFonts.md),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Select All
            InkWell(
              onTap: () => _toggleAll(!_allSelected),
              child: Row(
                children: [
                  Checkbox(
                    value: _tristateValue,
                    tristate: true,
                    onChanged: (v) => _toggleAll(v == true),
                  ),
                  Text(
                    'Select All (${_selectedIds.length}/${widget.sessions.length})',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppFonts.lg),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

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
              style: TextStyle(fontSize: AppFonts.md, color: sizeColor),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: sizePercent,
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              color: sizeColor,
            ),

            if (!_fitsInQr && _hasSelection) ...[
              const SizedBox(height: 8),
              Text(
                'Too large — deselect some sessions or use .lfs file export.',
                style: TextStyle(fontSize: AppFonts.md, color: AppTheme.disconnectedColor(theme.brightness)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: _exportAll,
          child: const Text('Export All'),
        ),
        FilledButton(
          onPressed: _hasSelection && _fitsInQr ? _showQr : null,
          child: const Text('Show QR'),
        ),
      ],
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
    final tristate = _isGroupPartial(node.fullPath);
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0),
      child: InkWell(
        onTap: () => _toggleGroup(node.fullPath),
        child: Row(
          children: [
            Checkbox(
              value: tristate,
              tristate: true,
              onChanged: (_) => _toggleGroup(node.fullPath),
            ),
            const Icon(Icons.folder, size: 16),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                node.name,
                style: TextStyle(fontSize: AppFonts.lg, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionItem(Session session, int depth) {
    final isSelected = _selectedIds.contains(session.id);
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0),
      child: InkWell(
        onTap: () => _toggleSession(session.id),
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
                session.label.isNotEmpty ? session.label : session.displayName,
                style: TextStyle(fontSize: AppFonts.lg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${session.user}@${session.host}',
              style: TextStyle(
                fontSize: AppFonts.sm,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
