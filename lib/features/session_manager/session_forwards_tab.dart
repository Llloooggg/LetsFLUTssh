import 'package:flutter/material.dart';

import '../../core/ssh/port_forward_rule.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_data_row.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/app_picker_chip.dart';
import '../../widgets/styled_form_field.dart';
import 'session_forwards_logic.dart';

/// Editor surface for the per-session port-forward rule list.
///
/// Stateless — the dialog above owns the rule list and rebuilds the
/// widget when the list mutates. Add / edit modal is reached via
/// [_showRuleEditor], which returns the edited rule (or null on
/// cancel) so the caller folds it into the in-memory list before any
/// persistence happens. This keeps the data flow uniform with the
/// rest of `session_edit_dialog.dart`: nothing hits the store until
/// the user clicks Save on the parent dialog.
class SessionForwardsTab extends StatelessWidget {
  final List<PortForwardRule> rules;
  final ValueChanged<List<PortForwardRule>> onChanged;

  const SessionForwardsTab({
    super.key,
    required this.rules,
    required this.onChanged,
  });

  void _replace(PortForwardRule updated) {
    final next = [
      for (final r in rules)
        if (r.id == updated.id) updated else r,
    ];
    onChanged(next);
  }

  void _add(PortForwardRule rule) {
    onChanged([...rules, rule]);
  }

  void _delete(PortForwardRule rule) {
    onChanged([
      for (final r in rules)
        if (r.id != rule.id) r,
    ]);
  }

  Future<void> _showRuleEditor(
    BuildContext context, {
    PortForwardRule? existing,
  }) async {
    final result = await showDialog<PortForwardRule>(
      context: context,
      builder: (_) => _ForwardRuleEditor(initial: existing),
    );
    if (result == null) return;
    if (existing == null) {
      _add(result);
    } else {
      _replace(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: AppEmptyState(message: l10n.portForwardingEmpty),
          )
        else
          for (final rule in rules)
            _ForwardRuleRow(
              rule: rule,
              onTap: () => _showRuleEditor(context, existing: rule),
              onToggle: () => _replace(rule.copyWith(enabled: !rule.enabled)),
              onDelete: () => _delete(rule),
            ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.secondary(
            label: l10n.addForwardRule,
            icon: Icons.add,
            onTap: () => _showRuleEditor(context),
          ),
        ),
      ],
    );
  }
}

/// Modal sub-dialog that hosts [SessionForwardsTab] for editing the
/// per-session port-forward rule list.
///
/// The parent session edit dialog (`session_edit_dialog.dart`) owns
/// the rule list as in-memory state until the user saves. The
/// Advanced section opens this dialog with the current list, lets
/// the user add / edit / toggle / delete rules in-place, and
/// returns the edited list back so the parent's `_forwards` field
/// updates without writing to the persistence layer until the
/// parent Save fires. Cancel returns `null` and the parent keeps
/// the pre-edit list.
class SessionForwardsDialog extends StatefulWidget {
  final List<PortForwardRule> initial;

  const SessionForwardsDialog({super.key, required this.initial});

  static Future<List<PortForwardRule>?> show(
    BuildContext context, {
    required List<PortForwardRule> initial,
  }) {
    return AppDialog.show<List<PortForwardRule>>(
      context,
      builder: (_) => SessionForwardsDialog(initial: initial),
    );
  }

  @override
  State<SessionForwardsDialog> createState() => _SessionForwardsDialogState();
}

class _SessionForwardsDialogState extends State<SessionForwardsDialog> {
  late List<PortForwardRule> _rules;

  @override
  void initState() {
    super.initState();
    _rules = List.of(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: l10n.portForwarding,
      content: SessionForwardsTab(
        rules: _rules,
        onChanged: (next) => setState(() => _rules = next),
      ),
      actions: [
        AppButton.cancel(onTap: () => Navigator.of(context).pop()),
        AppButton.primary(
          label: l10n.save,
          onTap: () => Navigator.of(context).pop(_rules),
        ),
      ],
    );
  }
}

class _ForwardRuleRow extends StatelessWidget {
  final PortForwardRule rule;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ForwardRuleRow({
    required this.rule,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final kindLabel = switch (rule.kind) {
      PortForwardKind.local => l10n.localForward,
      PortForwardKind.remote => l10n.remoteForward,
      PortForwardKind.dynamic_ => l10n.dynamicForward,
    };
    final secondary = rule.kind == PortForwardKind.dynamic_
        ? '${rule.bindHost}:${rule.bindPort}  •  $kindLabel'
        : '${rule.bindHost}:${rule.bindPort} → '
              '${rule.remoteHost}:${rule.remotePort}  •  $kindLabel';
    return AppDataRow(
      icon: rule.enabled ? Icons.swap_horiz : Icons.swap_horiz_outlined,
      iconColor: rule.enabled ? AppTheme.accent : AppTheme.fgFaint,
      title: rule.description.isNotEmpty
          ? rule.description
          : '${rule.bindHost}:${rule.bindPort}',
      secondary: secondary,
      secondaryMono: true,
      onTap: onTap,
      trailing: [
        // Both controls use AppIconButton (full size, not dense) so
        // they line up identically with every other row in the app —
        // tag pin, snippet pin, key actions all use the same icon
        // size. Toggle uses a filled / outlined icon swap to read
        // as "on/off" without a Material Switch (whose 24×40 frame
        // dwarfs the row).
        AppIconButton(
          icon: rule.enabled ? Icons.toggle_on : Icons.toggle_off_outlined,
          tooltip: l10n.forwardEnabled,
          color: rule.enabled ? AppTheme.accent : AppTheme.fgFaint,
          onTap: onToggle,
        ),
        AppIconButton(
          icon: Icons.delete_outline,
          tooltip: l10n.deleteForwardRule,
          color: AppTheme.red,
          onTap: onDelete,
        ),
      ],
    );
  }
}

class _ForwardRuleEditor extends StatefulWidget {
  final PortForwardRule? initial;

  const _ForwardRuleEditor({this.initial});

  @override
  State<_ForwardRuleEditor> createState() => _ForwardRuleEditorState();
}

class _ForwardRuleEditorState extends State<_ForwardRuleEditor> {
  final _formKey = GlobalKey<FormState>();
  late PortForwardKind _kind;
  late final TextEditingController _bindHost;
  late final TextEditingController _bindPort;
  late final TextEditingController _remoteHost;
  late final TextEditingController _remotePort;
  late final TextEditingController _description;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _kind = i?.kind ?? PortForwardKind.local;
    _bindHost = TextEditingController(text: i?.bindHost ?? '127.0.0.1');
    _bindPort = TextEditingController(text: i == null ? '' : '${i.bindPort}');
    _remoteHost = TextEditingController(text: i?.remoteHost ?? '');
    _remotePort = TextEditingController(
      text: i == null ? '' : '${i.remotePort}',
    );
    _description = TextEditingController(text: i?.description ?? '');
    _enabled = i?.enabled ?? true;
    // Re-render on bindHost edit so the wildcard warning reacts as
    // soon as the user types `0.0.0.0` instead of waiting for blur.
    _bindHost.addListener(_onBindHostChanged);
  }

  void _onBindHostChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bindHost.removeListener(_onBindHostChanged);
    _bindHost.dispose();
    _bindPort.dispose();
    _remoteHost.dispose();
    _remotePort.dispose();
    _description.dispose();
    super.dispose();
  }

  String? _portValidator(String? raw) => validatePortForwardPort(raw);

  String? _hostValidator(String? raw) => validatePortForwardHost(raw, _kind);

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final rule =
        (widget.initial ??
                PortForwardRule(
                  kind: _kind,
                  bindHost: _bindHost.text.trim(),
                  bindPort: int.parse(_bindPort.text.trim()),
                  remoteHost: _remoteHost.text.trim(),
                  remotePort: _remotePort.text.trim().isEmpty
                      ? 0
                      : int.parse(_remotePort.text.trim()),
                  description: _description.text.trim(),
                  enabled: _enabled,
                ))
            .copyWith(
              kind: _kind,
              bindHost: _bindHost.text.trim(),
              bindPort: int.parse(_bindPort.text.trim()),
              remoteHost: _remoteHost.text.trim(),
              remotePort: _remotePort.text.trim().isEmpty
                  ? 0
                  : int.parse(_remotePort.text.trim()),
              description: _description.text.trim(),
              enabled: _enabled,
            );
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final isDynamic = _kind == PortForwardKind.dynamic_;
    final showWildcardWarning = _bindHost.text.trim() == '0.0.0.0';
    return AppDialog(
      title: widget.initial == null
          ? l10n.addForwardRule
          : l10n.editForwardRule,
      maxWidth: 460,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FieldLabel(l10n.forwardKind),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                _kindChip(PortForwardKind.local, l10n.localForward),
                const SizedBox(width: AppSpacing.xxs),
                _kindChip(PortForwardKind.remote, l10n.remoteForward),
                const SizedBox(width: AppSpacing.xxs),
                _kindChip(PortForwardKind.dynamic_, l10n.dynamicForward),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            // Per-kind explanation: each forward semantics is distinct
            // enough that a one-liner under the chips beats a help
            // button hidden somewhere.
            Text(
              switch (_kind) {
                PortForwardKind.local => l10n.forwardKindLocalHelp,
                PortForwardKind.remote => l10n.forwardKindRemoteHelp,
                PortForwardKind.dynamic_ => l10n.forwardKindDynamicHelp,
              },
              style: TextStyle(
                color: AppTheme.fgFaint,
                fontFamily: AppFonts.interFamily,
                fontSize: AppFonts.xs,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            StyledFormField(
              label: l10n.bindAddress,
              controller: _bindHost,
              hint: '127.0.0.1',
            ),
            if (showWildcardWarning) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                l10n.forwardBindWildcardWarning,
                style: TextStyle(
                  color: AppTheme.yellow,
                  fontSize: AppFonts.xs,
                  fontFamily: AppFonts.interFamily,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            StyledFormField(
              label: l10n.bindPort,
              controller: _bindPort,
              hint: '8080',
              keyboardType: TextInputType.number,
              validator: _portValidator,
            ),
            if (!isDynamic) ...[
              const SizedBox(height: AppSpacing.sm),
              StyledFormField(
                label: l10n.targetHost,
                controller: _remoteHost,
                hint: 'svc.internal',
                validator: _hostValidator,
              ),
              const SizedBox(height: AppSpacing.sm),
              StyledFormField(
                label: l10n.targetPort,
                controller: _remotePort,
                hint: '80',
                keyboardType: TextInputType.number,
                validator: _portValidator,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            StyledFormField(
              label: l10n.forwardDescription,
              controller: _description,
              hint: '',
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Switch(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  l10n.forwardEnabled,
                  style: TextStyle(
                    color: AppTheme.fg,
                    fontSize: AppFonts.sm,
                    fontFamily: AppFonts.interFamily,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        AppButton.cancel(onTap: () => Navigator.pop(context)),
        // OK (not Save) — this only commits the rule into the
        // parent dialog's in-memory list. Persistence happens when
        // the user hits Save on the surrounding session-edit dialog.
        AppButton.primary(label: S.of(context).ok, onTap: _save),
      ],
    );
  }

  Widget _kindChip(PortForwardKind kind, String label) {
    return AppPickerChip(
      active: _kind == kind,
      label: label,
      onTap: () => setState(() => _kind = kind),
    );
  }
}
