import 'package:flutter/material.dart';

import '../../core/security/threat_vocabulary.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../utils/platform.dart' as plat;
import '../core/app_dialog.dart';
import 'security_threat_list.dart';

/// Full threat × tier-config matrix. Threats as rows, tier columns
/// along the top. Horizontally scrollable on narrow desktop; rendered
/// in transposed "one section per tier" shape on mobile so readers
/// don't fight a 2D scroll inside the drawer.
///
/// Columns are fixed — every (tier × modifier) combination the wizard
/// can actually produce is a column. Paranoid is the rightmost column
/// with a visual gap to the numbered tiers to reinforce that it is
/// not "tier 4" but a different branch.
class SecurityComparisonTable extends StatelessWidget {
  const SecurityComparisonTable({super.key});

  static const List<_Column> _columns = [
    _Column(
      id: 'T0',
      model: ThreatModel(tier: ThreatTier.plaintext),
    ),
    _Column(
      id: 'T1',
      model: ThreatModel(tier: ThreatTier.keychain),
    ),
    _Column(
      id: 'T1+pw',
      model: ThreatModel(tier: ThreatTier.keychain, password: true),
    ),
    _Column(
      id: 'T1+pw+bio',
      model: ThreatModel(
        tier: ThreatTier.keychain,
        password: true,
        biometric: true,
      ),
    ),
    // T2 is always password-gated in the bank-style model (password
    // modifier required). Biometric stays as an orthogonal column
    // because the overlay is the optional shortcut layer on top of
    // the typed password.
    _Column(
      id: 'T2+pw',
      model: ThreatModel(tier: ThreatTier.hardware, password: true),
    ),
    _Column(
      id: 'T2+pw+bio',
      model: ThreatModel(
        tier: ThreatTier.hardware,
        password: true,
        biometric: true,
      ),
    ),
    _Column(
      id: 'Paranoid',
      model: ThreatModel(tier: ThreatTier.paranoid, password: true),
      isAlternativeBranch: true,
    ),
  ];

  static Future<void> show(BuildContext context) {
    return AppDialog.show<void>(
      context,
      builder: (_) => const SecurityComparisonTable(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final useTransposed = plat.isMobilePlatform;
    return AppDialog(
      title: l10n.compareAllTiers,
      // Eight tier columns + threat-label column + padding overflow the
      // stock 460-wide AppDialog — the table's own horizontal scroll
      // kicks in around 820. Bump the dialog so the whole matrix fits
      // on a typical 1440+ desktop without needing the nested scroll.
      // Transposed mobile layout already fits in 460 (one tier section
      // per row) so we only widen on desktop.
      maxWidth: useTransposed ? 460 : 900,
      content: useTransposed
          ? _TransposedMatrix(l10n: l10n)
          : _WideMatrix(l10n: l10n),
      actions: [
        AppButton.primary(
          label: l10n.close,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _WideMatrix extends StatelessWidget {
  const _WideMatrix({required this.l10n});
  final S l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            horizontalMargin: 8,
            headingRowHeight: 36,
            dataRowMinHeight: 30,
            dataRowMaxHeight: 40,
            columns: [
              DataColumn(label: Text(l10n.securityComparisonTableThreatColumn)),
              for (final col in SecurityComparisonTable._columns)
                DataColumn(label: Text(_columnLabel(col, l10n))),
            ],
            rows: [
              for (final threat in SecurityThreat.values)
                DataRow(
                  cells: [
                    DataCell(
                      Tooltip(
                        message: threatDescription(threat, l10n),
                        child: Text(threatTitle(threat, l10n)),
                      ),
                    ),
                    for (final col in SecurityComparisonTable._columns)
                      DataCell(
                        _StatusCell(status: evaluate(col.model)[threat]!),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Legend(l10n: l10n),
      ],
    );
  }
}

class _TransposedMatrix extends StatelessWidget {
  const _TransposedMatrix({required this.l10n});
  final S l10n;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final col in SecurityComparisonTable._columns) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                _columnLabel(col, l10n),
                style: TextStyle(
                  fontSize: AppFonts.md,
                  color: AppTheme.fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SecurityThreatList(model: col.model),
          ],
          const SizedBox(height: 14),
          _Legend(l10n: l10n),
        ],
      ),
    );
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.status});
  final ThreatStatus status;

  @override
  Widget build(BuildContext context) {
    // Cells render as bare icons for sighted users — screen readers
    // saw an unlabelled image and announced nothing meaningful when
    // navigating the table. Wrap each cell in a Semantics node that
    // declares the cell's truth value via the same legend strings
    // the table footer uses, so a SR walk through the comparison
    // grid hears "protects" / "does not protect" per cell.
    final l10n = S.of(context);
    final (icon, color, label) = switch (status) {
      ThreatStatus.protects => (
        Icons.check,
        AppTheme.green,
        l10n.legendProtects,
      ),
      ThreatStatus.doesNotProtect => (
        Icons.close,
        AppTheme.red,
        l10n.legendDoesNotProtect,
      ),
    };
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: Icon(icon, size: 16, color: color)),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.l10n});
  final S l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _legendRow(Icons.check, AppTheme.green, l10n.legendProtects),
        _legendRow(Icons.close, AppTheme.red, l10n.legendDoesNotProtect),
        const SizedBox(height: 10),
        // Honest framing: a flat truth table suggests the user can
        // "pick a better tier" to fix runtime threats. They cannot —
        // those are addressed by the mitigation layer, not the KEK
        // provider. Call this out explicitly so the table does not
        // over-promise what tier choice can do.
        Text(
          l10n.mitigationsNoteRuntimeThreats,
          style: TextStyle(
            fontSize: AppFonts.xs,
            color: AppTheme.fgDim,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _legendRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _Column {
  const _Column({
    required this.id,
    required this.model,
    this.isAlternativeBranch = false,
  });

  final String id;
  final ThreatModel model;
  final bool isAlternativeBranch;
}

String _columnLabel(_Column col, S l10n) {
  switch (col.id) {
    case 'T0':
      return l10n.colT0;
    case 'T1':
      return l10n.colT1;
    case 'T1+pw':
      return l10n.colT1Password;
    case 'T1+pw+bio':
      return l10n.colT1PasswordBiometric;
    case 'T2+pw':
      return l10n.colT2Password;
    case 'T2+pw+bio':
      return l10n.colT2PasswordBiometric;
    case 'Paranoid':
      return l10n.colParanoid;
    default:
      return col.id;
  }
}
