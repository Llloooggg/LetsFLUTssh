import 'package:flutter/material.dart';

import '../core/security/threat_vocabulary.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'security_threat_list.dart';

/// Single-tier presentation block used by both Settings → Security
/// (read-only info) and the first-launch wizard (tap-to-select).
///
/// Header carries the tier badge + title + subtitle + a trailing
/// [trailing] slot (e.g. a "✓ Current" pill, an "Upgrade" button, or
/// a radio). Body splits the seven canonical threats into two halves
/// — the top lists threats this tier defeats (✓), the bottom lists
/// those it does not (✗). The split shape makes the migration across
/// tiers obvious visually: T0 has everything in the bottom half,
/// Paranoid has most items in the top half.
///
/// The widget is intentionally presentational — the caller builds the
/// [ThreatModel] and the [trailing] widget, and decides whether the
/// block is selected / dimmed / tappable via [selected], [dimmed],
/// and [onTap].
class TierThreatBlock extends StatelessWidget {
  const TierThreatBlock({
    super.key,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.model,
    this.accent,
    this.trailing,
    this.selected = false,
    this.dimmed = false,
    this.onTap,
  });

  /// Short identifier rendered in the left-hand pill. "T0", "T1",
  /// "T2", "P" are the canonical values.
  final String badge;

  /// Tier name — "Plaintext", "Keychain", "Hardware", "Paranoid".
  final String title;

  /// Short tier description — one line, usually the "OS keychain" /
  /// "TPM-backed" / "derived from master password" framing.
  final String subtitle;

  /// Threat model for the row — caller decides whether to show the
  /// bare tier (no modifiers) or with a password / biometric modifier
  /// applied. The evaluator returns the binary ✓ / ✗ map regardless.
  final ThreatModel model;

  /// Accent colour used on the selected border + badge chip. Defaults
  /// to the theme accent when omitted.
  final Color? accent;

  /// Optional trailing slot — a "✓ Current" pill in Settings, an
  /// "Upgrade" text button when the hardware probe is positive and
  /// the tier is above the current one, or nothing when the block is
  /// just informational.
  final Widget? trailing;

  /// Render the block with a highlighted border — used for the
  /// currently-active tier in Settings and the selected tier in the
  /// wizard. Orthogonal to [dimmed]; a block can be neither, dimmed,
  /// or selected but not both.
  final bool selected;

  /// Render the block at reduced opacity — used when the tier is
  /// unavailable on this host (e.g. T2 without a TPM). Keeps the
  /// block visible so the user sees what they are missing, but
  /// conveys that the row is not actionable.
  final bool dimmed;

  /// Tap handler. `null` makes the block inert — Settings uses this
  /// for every row because tier changes live behind the "Change tier"
  /// button. The wizard supplies a handler so the block itself acts
  /// as the selection.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final effectiveAccent = accent ?? AppTheme.accent;

    final statusMap = evaluate(model);
    final protects = <SecurityThreat>[];
    final doesNot = <SecurityThreat>[];
    for (final threat in SecurityThreat.values) {
      final status = statusMap[threat]!;
      switch (status) {
        case ThreatStatus.protects:
          protects.add(threat);
        case ThreatStatus.doesNotProtect:
          doesNot.add(threat);
      }
    }

    final borderColor = selected ? effectiveAccent : AppTheme.border;
    final borderWidth = selected ? 1.5 : 1.0;

    Widget body = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            badge: badge,
            title: title,
            subtitle: subtitle,
            accent: effectiveAccent,
            trailing: trailing,
          ),
          const SizedBox(height: 10),
          _SplitThreatList(
            protects: protects,
            doesNotProtect: doesNot,
            l10n: l10n,
          ),
        ],
      ),
    );

    if (dimmed) {
      body = Opacity(opacity: 0.55, child: body);
    }
    if (onTap != null) {
      body = InkWell(
        borderRadius: AppTheme.radiusSm,
        onTap: onTap,
        child: body,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: body,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.trailing,
  });

  final String badge;
  final String title;
  final String subtitle;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: accent, width: 1),
          ),
          child: Text(
            badge,
            style: TextStyle(
              color: accent,
              fontSize: AppFonts.xs,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.fg,
                  fontSize: AppFonts.md,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTheme.fgDim,
                    fontSize: AppFonts.xs,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class _SplitThreatList extends StatelessWidget {
  const _SplitThreatList({
    required this.protects,
    required this.doesNotProtect,
    required this.l10n,
  });

  final List<SecurityThreat> protects;
  final List<SecurityThreat> doesNotProtect;
  final S l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          label: l10n.tierBlockProtectsHeader,
          icon: Icons.check_circle,
          color: AppTheme.green,
        ),
        if (protects.isEmpty)
          _EmptyHint(text: l10n.tierBlockProtectsEmpty)
        else
          for (final t in protects)
            _ThreatLine(threat: t, status: ThreatStatus.protects, l10n: l10n),
        const SizedBox(height: 8),
        _SectionHeader(
          label: l10n.tierBlockDoesNotProtectHeader,
          icon: Icons.cancel,
          color: AppTheme.red,
        ),
        if (doesNotProtect.isEmpty)
          _EmptyHint(text: l10n.tierBlockDoesNotProtectEmpty)
        else
          for (final t in doesNotProtect)
            _ThreatLine(
              threat: t,
              status: ThreatStatus.doesNotProtect,
              l10n: l10n,
            ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: AppFonts.xs,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreatLine extends StatelessWidget {
  const _ThreatLine({
    required this.threat,
    required this.status,
    required this.l10n,
  });

  final SecurityThreat threat;
  final ThreatStatus status;
  final S l10n;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      ThreatStatus.protects => (Icons.check, AppTheme.green),
      ThreatStatus.doesNotProtect => (Icons.close, AppTheme.red),
    };
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              threatTitle(threat, l10n),
              style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.xs),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 22, top: 2, bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.fgDim,
          fontSize: AppFonts.xs,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
