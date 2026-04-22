part of 'settings_screen.dart';

class _UpdateSection extends ConsumerWidget {
  const _UpdateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkOnStart = ref.watch(
      configProvider.select((c) => c.checkUpdatesOnStart),
    );
    final updateState = ref.watch(updateProvider);

    return Column(
      children: [
        _Toggle(
          label: S.of(context).checkForUpdatesOnStartup,
          subtitle: S.of(context).checkForUpdatesOnStartupSubtitle,
          icon: Icons.system_update_alt,
          value: checkOnStart,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWith(
                  behavior: c.behavior.copyWith(checkUpdatesOnStart: v),
                ),
              ),
        ),
        _buildCheckButton(context, ref, updateState),
        _buildStatusWidget(context, ref, updateState),
      ],
    );
  }

  Widget _buildCheckButton(
    BuildContext context,
    WidgetRef ref,
    UpdateState updateState,
  ) {
    final isChecking = updateState.status == UpdateStatus.checking;
    final version = ref.watch(appVersionProvider);
    return _SettingsRow(
      icon: Icons.refresh,
      label: S.of(context).checkForUpdates,
      subtitle: S.of(context).currentVersion(version),
      // The row's trailing action used to be a raw `OutlinedButton.icon`
      // with ad-hoc `minimumSize` + `padding` overrides; it clashed
      // visually with the `_Toggle` rows above (different radius, no
      // `bg4` fill, larger font weight). `AppButton.secondary` keeps the
      // row in the same visual language, `dense: true` pins the compact
      // desktop height on every platform, and `loading: isChecking`
      // swaps the leading icon for a matched-size spinner in place of
      // the previous inline `CircularProgressIndicator`.
      child: AppButton.secondary(
        label: isChecking ? S.of(context).checking : S.of(context).checkNow,
        icon: Icons.refresh,
        loading: isChecking,
        dense: true,
        onTap: isChecking ? null : () => _runCheck(context, ref),
      ),
    );
  }

  Future<void> _runCheck(BuildContext context, WidgetRef ref) async {
    await ref.read(updateProvider.notifier).check();
    if (!context.mounted) return;
    final state = ref.read(updateProvider);
    if (state.status == UpdateStatus.upToDate) {
      Toast.show(
        context,
        message: S.of(context).youreRunningLatest,
        level: ToastLevel.success,
      );
    } else if (state.status == UpdateStatus.updateAvailable) {
      Toast.show(
        context,
        message: S.of(context).versionAvailable(state.info!.latestVersion),
        level: ToastLevel.info,
      );
    } else if (state.status == UpdateStatus.error) {
      Toast.show(
        context,
        message: state.error != null
            ? S
                  .of(context)
                  .errDownloadFailed(localizeError(S.of(context), state.error!))
            : S.of(context).updateCheckFailed,
        level: ToastLevel.error,
      );
    }
  }

  Widget _buildStatusWidget(
    BuildContext context,
    WidgetRef ref,
    UpdateState updateState,
  ) {
    final theme = Theme.of(context);

    switch (updateState.status) {
      case UpdateStatus.idle:
      case UpdateStatus.checking:
        return const SizedBox.shrink();

      case UpdateStatus.upToDate:
        return ListTile(
          leading: Icon(
            Icons.check_circle_outline,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          title: Text(S.of(context).youreUpToDate),
          contentPadding: EdgeInsets.zero,
        );

      case UpdateStatus.updateAvailable:
        return _buildUpdateAvailable(context, ref, updateState);

      case UpdateStatus.downloading:
        // Linear progress gives the user a much clearer sense of how
        // far the download has gone than a 20-px spinner — pair it
        // with a percent-annotated caption for screen readers. The
        // widget is shared with the first-launch update dialog so
        // both surfaces move together when the caption copy changes.
        return UpdateProgressIndicator(state: updateState);

      case UpdateStatus.downloaded:
        return _buildDownloaded(context, ref, updateState);

      case UpdateStatus.error:
        // Signature-verification failures get their own presentation: the
        // payload bytes on the network did not match the key pinned in
        // the app, which either means the download was tampered with or
        // the release genuinely is not for this installation. Either
        // way the user must not be nudged to retry the same failing
        // download — surface a security-styled warning with an "open
        // Releases page" action that points them at a manual reinstall
        // instead.
        if (updateState.error is InvalidReleaseSignatureException) {
          return _buildSignatureFailureWidget(context, ref);
        }
        return ListTile(
          leading: Icon(
            Icons.error_outline,
            size: 20,
            color: theme.colorScheme.error,
          ),
          title: Text(S.of(context).updateCheckFailed),
          subtitle: Text(
            updateState.error != null
                ? localizeError(S.of(context), updateState.error!)
                : S.of(context).unknownError,
            style: TextStyle(
              fontSize: AppFonts.md,
              color: theme.colorScheme.error,
            ),
          ),
          contentPadding: EdgeInsets.zero,
        );
    }
  }

  Widget _buildUpdateAvailable(
    BuildContext context,
    WidgetRef ref,
    UpdateState updateState,
  ) {
    final info = updateState.info!;
    final hasAsset = info.assetUrl != null;
    final skipped = ref.watch(configProvider.select((c) => c.skippedVersion));
    final isSkipped = skipped == info.latestVersion;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.system_update, size: 20),
          title: Text(S.of(context).versionAvailable(info.latestVersion)),
          subtitle: Text(S.of(context).currentVersion(info.currentVersion)),
          contentPadding: EdgeInsets.zero,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Wrap(
            spacing: 8,
            children: [
              _ChangelogButton(changelog: info.changelog),
              if (hasAsset && plat.isDesktopPlatform)
                AppButton.primary(
                  label: S.of(context).downloadAndInstall,
                  icon: Icons.download,
                  onTap: () => ref.read(updateProvider.notifier).download(),
                )
              else
                AppButton.secondary(
                  label: S.of(context).openInBrowser,
                  icon: Icons.open_in_new,
                  onTap: () async {
                    final url = Uri.parse(info.releaseUrl);
                    if (!await launchUrl(
                      url,
                      mode: LaunchMode.externalApplication,
                    )) {
                      if (context.mounted) {
                        Clipboard.setData(ClipboardData(text: info.releaseUrl));
                        Toast.show(
                          context,
                          message: S.of(context).couldNotOpenBrowser,
                          level: ToastLevel.warning,
                        );
                      }
                    }
                  },
                ),
              if (!isSkipped)
                AppButton(
                  label: S.of(context).skipThisVersion,
                  onTap: () => ref
                      .read(configProvider.notifier)
                      .update(
                        (c) => c.copyWith(
                          behavior: c.behavior.copyWith(
                            skippedVersion: info.latestVersion,
                          ),
                        ),
                      ),
                )
              else
                AppButton(
                  label: S.of(context).unskip,
                  onTap: () => ref
                      .read(configProvider.notifier)
                      .update(
                        (c) => c.copyWith(
                          behavior: c.behavior.copyWith(skippedVersion: null),
                        ),
                      ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloaded(
    BuildContext context,
    WidgetRef ref,
    UpdateState updateState,
  ) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.check_circle, size: 20),
          title: Text(S.of(context).downloadComplete),
          subtitle: Text(
            updateState.downloadedPath ?? '',
            style: TextStyle(fontSize: AppFonts.md),
            overflow: TextOverflow.ellipsis,
          ),
          contentPadding: EdgeInsets.zero,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Wrap(
            spacing: 8,
            children: [
              _ChangelogButton(changelog: updateState.info?.changelog),
              _InstallOrOpenReleaseButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSignatureFailureWidget(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final onError = theme.colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(Icons.gpp_bad_outlined, size: 20, color: onError),
          title: Text(
            S.of(context).updateSecurityWarningTitle,
            style: TextStyle(color: onError, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            S.of(context).errReleaseSignatureInvalid,
            style: TextStyle(fontSize: AppFonts.md, color: onError),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
              label: S.of(context).updateReinstallAction,
              icon: Icons.open_in_new,
              onTap: () => ref.read(updateProvider.notifier).openReleasePage(),
            ),
          ),
        ),
      ],
    );
  }
}

/// Action button for a ready-to-install update. On platforms that can
/// launch a native installer (desktop), the button says "Install Now"
/// and triggers the installer. On platforms without an in-app installer
/// (mobile / unknown / fallback after runtime failure), it says
/// "Open Release Page" and launches the browser instead — so the label
/// always matches the action the user is about to take.
class _InstallOrOpenReleaseButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(updateProvider.notifier);
    final canInstall = notifier.canLaunchInstaller;

    if (!canInstall) {
      return AppButton.primary(
        label: S.of(context).openReleasePage,
        icon: Icons.open_in_new,
        onTap: () async {
          final ok = await notifier.openReleasePage();
          if (!ok && context.mounted) {
            Toast.show(
              context,
              message: S.of(context).couldNotOpenInstaller,
              level: ToastLevel.error,
            );
          }
        },
      );
    }

    return AppButton.primary(
      label: S.of(context).installNow,
      icon: Icons.install_desktop,
      onTap: () async {
        final ok = await notifier.install();
        if (ok || !context.mounted) return;
        // Installer launch failed at runtime — fall back to opening the
        // release page in the browser so the user has a path forward.
        final fallback = await notifier.openReleasePage();
        if (!context.mounted) return;
        Toast.show(
          context,
          message: fallback
              ? S.of(context).installerFailedOpenedReleasePage
              : S.of(context).couldNotOpenInstaller,
          level: ToastLevel.error,
        );
      },
    );
  }
}

class _ChangelogButton extends StatelessWidget {
  const _ChangelogButton({required this.changelog});

  final String? changelog;

  @override
  Widget build(BuildContext context) {
    if (changelog == null || changelog!.isEmpty) return const SizedBox.shrink();

    return AppButton(
      label: S.of(context).releaseNotes,
      icon: Icons.article_outlined,
      onTap: () => AppDialog.show(
        context,
        builder: (ctx) => AppDialog(
          title: S.of(ctx).releaseNotes,
          content: SingleChildScrollView(
            child: Text(
              changelog!,
              style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fgDim),
            ),
          ),
          actions: [AppButton.cancel(onTap: () => Navigator.pop(ctx))],
        ),
      ),
    );
  }
}

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline, size: 20),
          title: Text(S.of(context).appTitle),
          subtitle: Text(S.of(context).aboutSubtitle(version)),
          contentPadding: EdgeInsets.zero,
        ),
        ListTile(
          leading: const Icon(Icons.code, size: 20),
          title: Text(S.of(context).sourceCode),
          subtitle: Text(
            _githubUrl,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: AppFonts.xs,
            ),
          ),
          contentPadding: EdgeInsets.zero,
          onTap: () {
            Clipboard.setData(const ClipboardData(text: _githubUrl));
            Toast.show(
              context,
              message: S.of(context).urlCopied,
              level: ToastLevel.info,
            );
          },
        ),
      ],
    );
  }
}
