part of 'settings_screen.dart';

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(configProvider.select((c) => c.locale));
    final theme = ref.watch(configProvider.select((c) => c.theme));
    final fontSize = ref.watch(configProvider.select((c) => c.fontSize));
    final uiScale = ref.watch(configProvider.select((c) => c.uiScale));
    return Column(
      children: [
        _LanguageTile(
          value: locale,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(locale: v)),
        ),
        _ThemeTile(
          value: theme,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWith(terminal: c.terminal.copyWith(theme: v)),
              ),
        ),
        _SliderTile(
          title: S.of(context).uiScale,
          subtitle: S.of(context).uiScaleSubtitle,
          icon: Icons.aspect_ratio,
          value: uiScale,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ui: c.ui.copyWith(uiScale: v))),
        ),
        _SliderTile(
          title: S.of(context).terminalFontSize,
          subtitle: S.of(context).terminalFontSizeSubtitle,
          icon: Icons.format_size,
          value: fontSize,
          min: 8,
          max: 24,
          divisions: 16,
          format: (v) => '${v.round()}',
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update(
                (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: v)),
              ),
        ),
      ],
    );
  }
}

class _TerminalSection extends ConsumerWidget {
  const _TerminalSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollback = ref.watch(configProvider.select((c) => c.scrollback));
    return _IntTile(
      title: S.of(context).scrollbackLines,
      subtitle: S.of(context).scrollbackLinesSubtitle,
      icon: Icons.history,
      value: scrollback,
      min: 100,
      max: 100000,
      onChanged: (v) => ref
          .read(configProvider.notifier)
          .update(
            (c) => c.copyWith(terminal: c.terminal.copyWith(scrollback: v)),
          ),
    );
  }
}

class _ConnectionSection extends ConsumerWidget {
  const _ConnectionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepAlive = ref.watch(configProvider.select((c) => c.keepAliveSec));
    final timeout = ref.watch(configProvider.select((c) => c.sshTimeoutSec));
    final port = ref.watch(configProvider.select((c) => c.defaultPort));
    return Column(
      children: [
        _IntTile(
          title: S.of(context).keepAliveInterval,
          subtitle: S.of(context).keepAliveIntervalSubtitle,
          icon: Icons.wifi_tethering,
          value: keepAlive,
          min: 0,
          max: 300,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ssh: c.ssh.copyWith(keepAliveSec: v))),
        ),
        _IntTile(
          title: S.of(context).sshTimeout,
          subtitle: S.of(context).sshTimeoutSubtitle,
          icon: Icons.timer_outlined,
          value: timeout,
          min: 1,
          max: 60,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ssh: c.ssh.copyWith(sshTimeoutSec: v))),
        ),
        _IntTile(
          title: S.of(context).defaultPort,
          subtitle: S.of(context).defaultPortSubtitle,
          icon: Icons.settings_ethernet,
          value: port,
          min: 1,
          max: 65535,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ssh: c.ssh.copyWith(defaultPort: v))),
        ),
      ],
    );
  }
}

class _TransferSection extends ConsumerWidget {
  const _TransferSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(configProvider.select((c) => c.transferWorkers));
    final maxHistory = ref.watch(configProvider.select((c) => c.maxHistory));
    final showFolderSizes = ref.watch(
      configProvider.select((c) => c.showFolderSizes),
    );
    return Column(
      children: [
        _IntTile(
          title: S.of(context).parallelWorkers,
          subtitle: S.of(context).parallelWorkersSubtitle,
          icon: Icons.multiple_stop,
          value: workers,
          min: 1,
          max: 10,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(transferWorkers: v)),
        ),
        _IntTile(
          title: S.of(context).maxHistory,
          subtitle: S.of(context).maxHistorySubtitle,
          icon: Icons.manage_history,
          value: maxHistory,
          min: 10,
          max: 5000,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(maxHistory: v)),
        ),
        _Toggle(
          label: S.of(context).calculateFolderSizes,
          subtitle: S.of(context).calculateFolderSizesSubtitle,
          icon: Icons.folder_open,
          value: showFolderSizes,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ui: c.ui.copyWith(showFolderSizes: v))),
        ),
      ],
    );
  }
}

