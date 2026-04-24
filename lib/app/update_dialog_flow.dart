import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update/update_service.dart';
import '../l10n/app_localizations.dart';
import '../providers/config_provider.dart';
import '../providers/update_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/platform.dart' as plat;
import '../widgets/app_dialog.dart';
import '../widgets/toast.dart';
import '../widgets/update_progress_indicator.dart';

/// Opens the "Update available" modal for [info].
///
/// The dialog's body + actions sit inside a `Consumer` so the widget
/// tree reacts to `updateProvider` transitions while the download is
/// in flight — the button swap to a progress indicator used to be
/// the visible regression when the dialog popped synchronously and
/// the download happened invisibly in the background.
///
/// Moved out of `MainScreen` so main.dart no longer carries ~180 LOC
/// of update-flow wiring inline. The caller ([MainScreen]) keeps the
/// `_updateDialogShown` latch + the `ref.listenManual(updateProvider)`
/// entry point; this module owns only the dialog composition.
void showUpdateDialog({
  required BuildContext context,
  required WidgetRef ref,
  required UpdateInfo info,
}) {
  final hasAsset = info.assetUrl != null && plat.isDesktopPlatform;
  AppDialog.show(
    context,
    // `AppDialog` is a StatelessWidget, so its `content` + `actions`
    // are captured at construction. Wrapping them in a `Consumer`
    // lets the dialog react to `updateProvider` state changes while
    // the download runs — previously the "Download and Install"
    // button popped the dialog immediately and the user was left
    // with zero visibility into the in-flight transfer. Now the
    // dialog stays open, swaps its body for a
    // `UpdateProgressIndicator`, and collapses its footer to just
    // Cancel while the state machine walks through
    // `downloading → downloaded → (autoInstall) installing`.
    builder: (ctx) => Consumer(
      builder: (ctx, innerRef, _) {
        final state = innerRef.watch(updateProvider);
        final inFlight =
            state.status == UpdateStatus.downloading ||
            state.status == UpdateStatus.downloaded;
        final hasError = state.status == UpdateStatus.error;
        return AppDialog(
          title: S.of(ctx).updateAvailable,
          dismissible: !inFlight,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S
                    .of(ctx)
                    .updateVersionAvailable(
                      info.latestVersion,
                      info.currentVersion,
                    ),
                style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
              ),
              if (inFlight) ...[
                const SizedBox(height: 12),
                UpdateProgressIndicator(state: state),
              ] else if (hasError) ...[
                const SizedBox(height: 12),
                Text(
                  state.error != null
                      ? localizeError(S.of(ctx), state.error!)
                      : S.of(ctx).updateCheckFailed,
                  style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.red),
                ),
              ] else if (info.changelog != null &&
                  info.changelog!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  S.of(ctx).releaseNotes,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppFonts.md,
                    color: AppTheme.fg,
                  ),
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Text(
                      info.changelog!,
                      style: TextStyle(
                        fontSize: AppFonts.md,
                        color: AppTheme.fgDim,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: _buildUpdateDialogActions(
            ctx: ctx,
            outerContext: context,
            ref: innerRef,
            info: info,
            hasAsset: hasAsset,
            state: state,
          ),
        );
      },
    ),
  );
}

List<Widget> _buildUpdateDialogActions({
  required BuildContext ctx,
  required BuildContext outerContext,
  required WidgetRef ref,
  required UpdateInfo info,
  required bool hasAsset,
  required UpdateState state,
}) {
  // No actionable buttons while bytes are in flight — the installer
  // launcher owns the next step after `downloaded`, and Cancel
  // would orphan the partial download without the updater picking
  // up the signal. Show progress, hide everything else.
  if (state.status == UpdateStatus.downloading) {
    return const [];
  }
  if (state.status == UpdateStatus.error) {
    return [
      AppButton.cancel(onTap: () => Navigator.pop(ctx)),
      AppButton.primary(
        label: S.of(ctx).retry,
        onTap: () {
          ref.read(updateProvider.notifier).download(autoInstall: hasAsset);
        },
      ),
    ];
  }
  // Default: idle / update-available / up-to-date / downloaded
  // (auto-install path closes itself once the installer spawns).
  return [
    AppButton.cancel(onTap: () => Navigator.pop(ctx)),
    AppButton.secondary(
      label: S.of(ctx).skipThisVersion,
      onTap: () {
        Navigator.pop(ctx);
        ref
            .read(configProvider.notifier)
            .update(
              (c) => c.copyWith(
                behavior: c.behavior.copyWith(
                  skippedVersion: info.latestVersion,
                ),
              ),
            );
      },
    ),
    _buildPrimaryUpdateAction(
      ctx: ctx,
      outerContext: outerContext,
      ref: ref,
      info: info,
      hasAsset: hasAsset,
    ),
  ];
}

Widget _buildPrimaryUpdateAction({
  required BuildContext ctx,
  required BuildContext outerContext,
  required WidgetRef ref,
  required UpdateInfo info,
  required bool hasAsset,
}) {
  if (hasAsset) {
    return AppButton.primary(
      label: S.of(ctx).downloadAndInstall,
      onTap: () {
        // Do not pop — the dialog stays open and swaps its body
        // for the in-flight progress indicator. Earlier the
        // dialog popped synchronously and the download happened
        // silently in the background with no user feedback.
        ref.read(updateProvider.notifier).download(autoInstall: true);
      },
    );
  }
  return AppButton.primary(
    label: S.of(ctx).openInBrowser,
    onTap: () async {
      Navigator.pop(ctx);
      final url = Uri.parse(info.releaseUrl);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (outerContext.mounted) {
          Clipboard.setData(ClipboardData(text: info.releaseUrl));
          Toast.show(
            outerContext,
            message: S.of(outerContext).couldNotOpenBrowser,
            level: ToastLevel.warning,
          );
        }
      }
    },
  );
}
