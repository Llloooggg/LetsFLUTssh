import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/update_provider.dart';
import '../theme/app_theme.dart';

/// Linear progress bar + percent-annotated caption for an in-flight
/// [UpdateState].
///
/// Shared between the Settings → Updates section and the first-launch
/// update dialog in `main.dart`. Both surfaces used to inline their
/// own copy of the layout, which made it easy for the two surfaces to
/// drift out of lockstep on spacing / wording. Centralising here
/// keeps the download / verify / install captions identical in both
/// places — the startup dialog switches from "Download and Install"
/// to this widget in-place while the updater walks the state
/// machine, and the Settings section swaps this widget in as the row
/// trailing content for the same state.
class UpdateProgressIndicator extends StatelessWidget {
  final UpdateState state;

  const UpdateProgressIndicator({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final caption = _caption(l10n, state);
    // Indeterminate (`value: null`) while progress is still zero so
    // the bar doesn't pretend to be at 0% when nothing has streamed
    // back yet — matches the Material guidance for "awaiting first
    // byte".
    final value = state.progress > 0 ? state.progress : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(caption),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: AppTheme.radiusSm,
            child: LinearProgressIndicator(value: value, minHeight: 6),
          ),
        ],
      ),
    );
  }

  static String _caption(S l10n, UpdateState state) {
    switch (state.status) {
      case UpdateStatus.downloading:
        return l10n.downloadingPercent((state.progress * 100).toInt());
      // The updater's public state machine does not surface a
      // dedicated "verifying" or "installing" slot yet — the
      // Settings section rerenders through `downloaded` / `idle`
      // transitions. Keep the switch exhaustive so a future
      // verifying / installing state surfaces with its own copy
      // instead of silently falling through.
      case UpdateStatus.checking:
        return l10n.checking;
      case UpdateStatus.idle:
      case UpdateStatus.upToDate:
      case UpdateStatus.updateAvailable:
      case UpdateStatus.downloaded:
      case UpdateStatus.error:
        return l10n.downloadingPercent((state.progress * 100).toInt());
    }
  }
}
