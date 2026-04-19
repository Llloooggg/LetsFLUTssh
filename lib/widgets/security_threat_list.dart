import 'package:flutter/material.dart';

import '../core/security/threat_vocabulary.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Single-tier threat-status list used by the per-tier info popup.
///
/// Renders the full [SecurityThreat] vocabulary — every threat row
/// visible inline with a ✓ / ✗ / — / ! glyph derived from the
/// [ThreatStatus] returned by [evaluate]. Order is the canonical
/// vocabulary order so the user can flip between popups (e.g. T1+pw
/// vs T2+pw) and compare positionally.
///
/// The widget is purely presentational — caller builds the
/// [ThreatModel] from the current (or hypothetical) security
/// config and passes it in. All strings come from `S.of(context)`
/// so the component works in every locale without extra wiring.
class SecurityThreatList extends StatelessWidget {
  const SecurityThreatList({super.key, required this.model});

  final ThreatModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final statusMap = evaluate(model);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final threat in SecurityThreat.values)
          _ThreatRow(threat: threat, status: statusMap[threat]!, l10n: l10n),
      ],
    );
  }
}

class _ThreatRow extends StatelessWidget {
  const _ThreatRow({
    required this.threat,
    required this.status,
    required this.l10n,
  });

  final SecurityThreat threat;
  final ThreatStatus status;
  final S l10n;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _glyphFor(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  threatTitle(threat, l10n),
                  style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fg),
                ),
                if (status == ThreatStatus.noteWeakPasswordAcceptable)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l10n.legendWeakPasswordWarning,
                      style: TextStyle(
                        fontSize: AppFonts.xs,
                        color: AppTheme.fgDim,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (status == ThreatStatus.noteStrongPasswordRecommended)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l10n.legendStrongPasswordRecommended,
                      style: TextStyle(
                        fontSize: AppFonts.xs,
                        color: AppTheme.fgDim,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _glyphFor(ThreatStatus status) {
    switch (status) {
      case ThreatStatus.protects:
        return (Icons.check, AppTheme.green);
      case ThreatStatus.doesNotProtect:
        return (Icons.close, AppTheme.red);
      case ThreatStatus.notApplicable:
        return (Icons.remove, AppTheme.fgDim);
      case ThreatStatus.noteWeakPasswordAcceptable:
      case ThreatStatus.noteStrongPasswordRecommended:
        return (Icons.error_outline, AppTheme.yellow);
    }
  }
}

/// Resolve the localized title for [threat]. Public so the
/// comparison-table rendering can share the same strings without
/// having to duplicate the switch.
String threatTitle(SecurityThreat threat, S l10n) {
  switch (threat) {
    case SecurityThreat.coldDiskTheft:
      return l10n.threatColdDiskTheft;
    case SecurityThreat.bystanderUnlockedMachine:
      return l10n.threatBystanderUnlockedMachine;
    case SecurityThreat.sameUserMalware:
      return l10n.threatSameUserMalware;
    case SecurityThreat.liveProcessMemoryDump:
      return l10n.threatLiveProcessMemoryDump;
    case SecurityThreat.liveRamForensicsLocked:
      return l10n.threatLiveRamForensicsLocked;
    case SecurityThreat.osKernelOrKeychainBreach:
      return l10n.threatOsKernelOrKeychainBreach;
    case SecurityThreat.offlineBruteForce:
      return l10n.threatOfflineBruteForce;
  }
}

/// Resolve the localized description for [threat]. Used in the
/// comparison-table hover tooltip.
String threatDescription(SecurityThreat threat, S l10n) {
  switch (threat) {
    case SecurityThreat.coldDiskTheft:
      return l10n.threatColdDiskTheftDescription;
    case SecurityThreat.bystanderUnlockedMachine:
      return l10n.threatBystanderUnlockedMachineDescription;
    case SecurityThreat.sameUserMalware:
      return l10n.threatSameUserMalwareDescription;
    case SecurityThreat.liveProcessMemoryDump:
      return l10n.threatLiveProcessMemoryDumpDescription;
    case SecurityThreat.liveRamForensicsLocked:
      return l10n.threatLiveRamForensicsLockedDescription;
    case SecurityThreat.osKernelOrKeychainBreach:
      return l10n.threatOsKernelOrKeychainBreachDescription;
    case SecurityThreat.offlineBruteForce:
      return l10n.threatOfflineBruteForceDescription;
  }
}
