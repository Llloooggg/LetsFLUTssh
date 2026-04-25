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
      // Override has no label — show host only. user@host is too
      // wide for the sidebar row and the user already knows the
      // user from the parent session's auth.
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
        // Saved-session label wins — typically short and recognisable
        // (e.g. "prod-bastion"), unlike the user@host fallback.
        label = bastion.label;
      } else {
        label = bastion.host;
      }
    }
    return Flexible(
      // Flexible (not Expanded) so the badge shrinks when the row
      // is tight but does not steal extra space when there's room.
      // Keeps the badge from pushing past the sidebar's right edge
      // when the resolved bastion label happens to be long.
      fit: FlexFit.loose,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Container(
          // Hard cap so a maliciously long bastion label cannot
          // squeeze the session name to a single character either.
          constraints: const BoxConstraints(maxWidth: 140),
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
            softWrap: false,
          ),
        ),
      ),
    );
  }
}
