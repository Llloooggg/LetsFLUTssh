import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';

/// Compact "via X" badge surfaced in the session tree row when a
/// session has a [Session.hasProxyJump] bastion configured.
///
/// For saved-session bastions we resolve the id against the live
/// session list and show the bastion's label (or `displayName`
/// fallback). For one-off overrides we show the override host. A
/// dangling `viaSessionId` (the bastion was deleted, leaving the
/// FK as NULL) renders an `?` so the user notices the broken
/// reference instead of the badge silently disappearing.
class SessionViaBadge extends ConsumerWidget {
  final Session session;

  const SessionViaBadge({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!session.hasProxyJump) return const SizedBox.shrink();
    final l10n = S.of(context);
    String label;
    if (session.viaOverride != null) {
      label = session.viaOverride!.host;
    } else {
      final all = ref.watch(sessionProvider);
      Session? bastion;
      for (final s in all) {
        if (s.id == session.viaSessionId) {
          bastion = s;
          break;
        }
      }
      if (bastion == null) {
        label = '?';
      } else if (bastion.label.isNotEmpty) {
        label = bastion.label;
      } else {
        label = '${bastion.user}@${bastion.host}';
      }
    }
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppTheme.bg3,
          borderRadius: AppTheme.radiusSm,
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Text(
          l10n.viaSessionLabel(label),
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: AppFonts.xs,
            color: AppTheme.fgFaint,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }
}
