import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/import/import_service.dart';
import '../../core/session/qr_codec.dart';
import '../../providers/config_provider.dart';
import '../../providers/update_provider.dart';
import '../../providers/version_provider.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../providers/session_provider.dart';
import '../../utils/platform.dart' as plat;
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bordered_box.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/hover_region.dart';
import '../../widgets/toast.dart';
import '../session_manager/qr_display_screen.dart';
import '../session_manager/qr_export_dialog.dart';
import 'export_import.dart';

const _githubUrl = 'https://github.com/Llloooggg/LetsFLUTssh';

/// Returns a sensible initial directory for file-picker dialogs.
/// Desktop: Downloads folder; mobile: shared external storage root.
Future<String?> _defaultDirectory() async {
  if (plat.isDesktopPlatform) {
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir.path;
    } catch (_) {
      // fall through
    }
  }
  final home = plat.homeDirectory;
  return home.isNotEmpty ? home : null;
}

/// Section descriptor for navigation and content rendering.
class _Section {
  final String title;
  final IconData icon;
  final Widget Function() builder;

  const _Section({
    required this.title,
    required this.icon,
    required this.builder,
  });
}

/// Ordered list of all settings sections.
List<_Section> _buildSections(BuildContext context) => [
  _Section(
    title: S.of(context).appearance,
    icon: Icons.palette,
    builder: _AppearanceSection.new,
  ),
  _Section(
    title: S.of(context).terminal,
    icon: Icons.terminal,
    builder: _TerminalSection.new,
  ),
  _Section(
    title: S.of(context).connectionSection,
    icon: Icons.lan,
    builder: _ConnectionSection.new,
  ),
  _Section(
    title: S.of(context).transfers,
    icon: Icons.swap_horiz,
    builder: _TransferSection.new,
  ),
  _Section(
    title: S.of(context).data,
    icon: Icons.storage,
    builder: _DataSection.new,
  ),
  _Section(
    title: S.of(context).logging,
    icon: Icons.description,
    builder: _LoggingSection.new,
  ),
  _Section(
    title: S.of(context).updates,
    icon: Icons.system_update,
    builder: _UpdateSection.new,
  ),
  _Section(
    title: S.of(context).about,
    icon: Icons.info_outline,
    builder: _AboutSection.new,
  ),
];

/// Settings screen with config editing.
///
/// Desktop: two-column layout (nav rail + content pane).
/// Mobile: flat scrollable list (unchanged).
///
/// Each section watches only its own config fields via `select()` to avoid
/// unnecessary rebuilds when unrelated settings change.
/// Settings screen — mobile only (pushed as a route).
///
/// On desktop, settings are embedded directly in [AppShell] via
/// [SettingsSidebar] and [SettingsContent] — no route navigation needed.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Push the mobile settings screen.
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const SettingsScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _MobileSettingsScreen();
  }
}

/// Mobile: collapsible sections in a scrollable list.
class _MobileSettingsScreen extends ConsumerWidget {
  const _MobileSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = _buildSections(context);
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).settings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final section in sections)
            _CollapsibleSection(
              title: section.title,
              icon: section.icon,
              child: section.builder(),
            ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => ref
                  .read(configProvider.notifier)
                  .update((_) => AppConfig.defaults),
              icon: const Icon(Icons.restore, size: 18),
              label: Text(S.of(context).resetToDefaults),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// When true (test-only), all [_CollapsibleSection] widgets start expanded.
/// Set this in test setUp / tearDown using the same pattern as
/// [plat.debugMobilePlatformOverride].
@visibleForTesting
bool debugCollapsibleSectionsExpanded = false;

/// Collapsible settings section used on mobile.
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _CollapsibleSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _expanded = debugCollapsibleSectionsExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.radiusLg,
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(widget.icon, size: 20),
        title: Text(
          widget.title,
          style: TextStyle(fontSize: AppFonts.lg, fontWeight: FontWeight.w500),
        ),
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [widget.child],
      ),
    );
  }
}

/// Desktop settings sidebar — nav items + reset button.
///
/// Designed to be embedded in [AppShell]'s sidebar slot so it shares
/// the same resizable panel and visual frame as the sessions sidebar.
class SettingsSidebar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const SettingsSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = _buildSections(context);
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // Header — matches SessionPanel _PanelHeader style
          Container(
            height: AppTheme.barHeightSm,
            padding: const EdgeInsets.only(left: 12, right: 2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    S.of(context).settings.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppFonts.sm,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: sections.length,
              itemBuilder: (context, index) {
                final section = sections[index];
                return _NavItem(
                  icon: section.icon,
                  label: section.title,
                  selected: index == selectedIndex,
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
          _ResetButton(
            onTap: () => ref
                .read(configProvider.notifier)
                .update((_) => AppConfig.defaults),
          ),
        ],
      ),
    );
  }
}

/// Desktop settings content pane — shows the selected section.
///
/// Designed to be embedded in [AppShell]'s body slot.
class SettingsContent extends StatelessWidget {
  final int selectedIndex;

  const SettingsContent({super.key, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections(context);
    final scheme = Theme.of(context).colorScheme;
    return ListTileTheme(
      data: ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.zero,
        titleTextStyle: AppFonts.inter(
          fontSize: AppFonts.sm,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: AppFonts.inter(
          fontSize: AppFonts.xs,
          color: scheme.onSurfaceVariant,
        ),
        leadingAndTrailingTextStyle: AppFonts.inter(
          fontSize: AppFonts.xs,
          color: scheme.onSurface.withValues(alpha: 0.45),
        ),
      ),
      child: DefaultTextStyle(
        style: AppFonts.inter(fontSize: AppFonts.sm, color: scheme.onSurface),
        child: ListView(
          key: ValueKey(selectedIndex),
          padding: const EdgeInsets.all(24),
          children: [
            _SectionHeader(title: sections[selectedIndex].title),
            sections[selectedIndex].builder(),
          ],
        ),
      ),
    );
  }
}

/// A single item in the desktop navigation rail.
class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HoverRegion(
      onTap: widget.onTap,
      builder: (hovered) {
        final Color bg;
        if (widget.selected) {
          bg = theme.colorScheme.primary.withValues(alpha: 0.15);
        } else if (hovered) {
          bg = AppTheme.hover;
        } else {
          bg = Colors.transparent;
        }
        return Container(
          height: AppTheme.controlHeightMd,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: bg,
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 13,
                color: widget.selected ? AppTheme.fg : AppTheme.fgDim,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.inter(
                    fontSize: AppFonts.sm,
                    color: widget.selected ? AppTheme.fg : AppTheme.fgDim,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Reset to Defaults button at bottom of nav.
class _ResetButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ResetButton({required this.onTap});

  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: HoverRegion(
        onTap: widget.onTap,
        builder: (hovered) => Container(
          height: AppTheme.controlHeightSm,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: hovered ? AppTheme.hover : Colors.transparent,
          child: Row(
            children: [
              Icon(Icons.restore, size: 12, color: AppTheme.red),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  S.of(context).resetToDefaults,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.inter(
                    fontSize: AppFonts.xs,
                    color: AppTheme.red,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data section — groups export, import, QR, and data path tiles.
class _DataSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ExportImportTile(),
        const _QrExportTile(),
        const _DataPathTile(),
      ],
    );
  }
}

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
          onChanged: (v) =>
              ref.read(configProvider.notifier).update((c) => c.withLocale(v)),
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
          value: keepAlive,
          min: 0,
          max: 300,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ssh: c.ssh.copyWith(keepAliveSec: v))),
        ),
        _IntTile(
          title: S.of(context).sshTimeout,
          value: timeout,
          min: 1,
          max: 60,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ssh: c.ssh.copyWith(sshTimeoutSec: v))),
        ),
        _IntTile(
          title: S.of(context).defaultPort,
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
          value: workers,
          min: 1,
          max: 10,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(transferWorkers: v)),
        ),
        _IntTile(
          title: S.of(context).maxHistory,
          value: maxHistory,
          min: 10,
          max: 5000,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(maxHistory: v)),
        ),
        _Toggle(
          label: S.of(context).calculateFolderSizes,
          value: showFolderSizes,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(ui: c.ui.copyWith(showFolderSizes: v))),
        ),
      ],
    );
  }
}

class _ExportImportTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ActionTile(
          icon: Icons.upload_file,
          title: S.of(context).exportData,
          subtitle: S.of(context).exportDataSubtitle,
          onTap: () => _showExportDialog(context, ref),
        ),
        _ActionTile(
          icon: Icons.download,
          title: S.of(context).importData,
          subtitle: S.of(context).importDataSubtitle,
          onTap: () => _showImportDialog(context, ref),
        ),
      ],
    );
  }

  Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    try {
      final password = await AppDialog.show<String>(
        context,
        builder: (ctx) => _ExportPasswordDialog(
          passwordCtrl: passwordCtrl,
          confirmCtrl: confirmCtrl,
        ),
      );

      if (password == null || !context.mounted) return;

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final outputPath = await _pickSavePath(
        context,
        'export_$timestamp.lfs',
        'lfs',
      );
      if (outputPath == null || !context.mounted) return;

      await _runExport(context, ref, password, outputPath);
    } catch (e) {
      AppLogger.instance.log('Export failed: $e', name: 'Settings', error: e);
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).exportFailed(e.toString()),
          level: ToastLevel.error,
        );
      }
    } finally {
      passwordCtrl.dispose();
      confirmCtrl.dispose();
    }
  }

  Future<void> _runExport(
    BuildContext context,
    WidgetRef ref,
    String password,
    String outputPath,
  ) async {
    // Show progress indicator while PBKDF2 + encryption runs in isolate
    AppProgressDialog.show(context);
    try {
      await ExportImport.export(
        masterPassword: password,
        sessions: ref.read(sessionProvider),
        config: ref.read(configProvider),
        outputPath: outputPath,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        Toast.show(
          context,
          message: S.of(context).exportedTo(outputPath),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      rethrow;
    }
  }

  /// Opens a save-file picker. Desktop uses native save dialog,
  /// mobile uses directory picker + default filename.
  Future<String?> _pickSavePath(
    BuildContext context,
    String defaultName,
    String extension,
  ) async {
    final title = S.of(context).chooseSaveLocation;
    final initDir = await _defaultDirectory();
    if (plat.isDesktopPlatform) {
      return FilePicker.saveFile(
        dialogTitle: title,
        fileName: defaultName,
        initialDirectory: initDir,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
    }
    // Mobile: pick directory, append default filename
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: title,
      initialDirectory: initDir,
    );
    if (dir == null) return null;
    return p.join(dir, defaultName);
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final pathCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final modeHolder = _ValueHolder(ImportMode.merge);

    try {
      final result =
          await AppDialog.show<
            ({String path, String password, ImportMode mode})
          >(
            context,
            builder: (ctx) => _ImportDataDialog(
              pathCtrl: pathCtrl,
              passwordCtrl: passwordCtrl,
              modeHolder: modeHolder,
            ),
          );

      if (result == null || !context.mounted) return;
      await _executeImport(context, ref, result);
    } finally {
      pathCtrl.dispose();
      passwordCtrl.dispose();
    }
  }

  Future<void> _executeImport(
    BuildContext context,
    WidgetRef ref,
    ({String path, String password, ImportMode mode}) result,
  ) async {
    try {
      final file = File(result.path);
      if (!await file.exists()) {
        if (context.mounted) {
          Toast.show(
            context,
            message: 'File not found: ${result.path}',
            level: ToastLevel.error,
          );
        }
        return;
      }

      // Show progress indicator while PBKDF2 + decryption runs in isolate
      if (context.mounted) {
        AppProgressDialog.show(context);
      }

      try {
        final importResult = await ExportImport.import_(
          filePath: result.path,
          masterPassword: result.password,
          mode: result.mode,
          importConfig: true,
          importKnownHosts: true,
        );

        final importService = ImportService(
          addSession: (s) => ref.read(sessionProvider.notifier).add(s),
          deleteSession: (id) => ref.read(sessionProvider.notifier).delete(id),
          getSessions: () => ref.read(sessionProvider),
          applyConfig: (config) =>
              ref.read(configProvider.notifier).update((_) => config),
        );
        await importService.applyResult(importResult);

        if (context.mounted) {
          Navigator.of(context).pop(); // close progress
          Toast.show(
            context,
            message: 'Imported ${importResult.sessions.length} session(s)',
            level: ToastLevel.success,
          );
        }
      } catch (e) {
        if (context.mounted) Navigator.of(context).pop(); // close progress
        rethrow;
      }
    } catch (e) {
      AppLogger.instance.log('Import failed: $e', name: 'Settings', error: e);
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).importFailed(localizeError(S.of(context), e)),
          level: ToastLevel.error,
        );
      }
    }
  }
}

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
          value: checkOnStart,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(checkUpdatesOnStart: v)),
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
    return ListTile(
      leading: isChecking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 20),
      title: Text(
        isChecking ? S.of(context).checking : S.of(context).checkForUpdates,
      ),
      contentPadding: EdgeInsets.zero,
      onTap: isChecking
          ? null
          : () async {
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
                  message: S
                      .of(context)
                      .versionAvailable(state.info!.latestVersion),
                  level: ToastLevel.info,
                );
              } else if (state.status == UpdateStatus.error) {
                Toast.show(
                  context,
                  message: state.error != null
                      ? S
                            .of(context)
                            .errDownloadFailed(
                              localizeError(S.of(context), state.error!),
                            )
                      : S.of(context).updateCheckFailed,
                  level: ToastLevel.error,
                );
              }
            },
    );
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
        return ListTile(
          leading: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              value: updateState.progress > 0 ? updateState.progress : null,
              strokeWidth: 2,
            ),
          ),
          title: Text(
            S
                .of(context)
                .downloadingPercent((updateState.progress * 100).toInt()),
          ),
          contentPadding: EdgeInsets.zero,
        );

      case UpdateStatus.downloaded:
        return _buildDownloaded(context, ref, updateState);

      case UpdateStatus.error:
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
              if (hasAsset && plat.isDesktopPlatform)
                FilledButton.icon(
                  onPressed: () => ref.read(updateProvider.notifier).download(),
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(S.of(context).downloadAndInstall),
                )
              else
                OutlinedButton.icon(
                  onPressed: () async {
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
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(S.of(context).openInBrowser),
                ),
              if (!isSkipped)
                TextButton(
                  onPressed: () => ref
                      .read(configProvider.notifier)
                      .update((c) => c.withSkippedVersion(info.latestVersion)),
                  child: Text(S.of(context).skipThisVersion),
                )
              else
                TextButton(
                  onPressed: () => ref
                      .read(configProvider.notifier)
                      .update((c) => c.withSkippedVersion(null)),
                  child: Text(S.of(context).unskip),
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
          child: FilledButton.icon(
            onPressed: () async {
              final ok = await ref.read(updateProvider.notifier).install();
              if (!ok && context.mounted) {
                Toast.show(
                  context,
                  message: S.of(context).couldNotOpenInstaller,
                  level: ToastLevel.error,
                );
              }
            },
            icon: const Icon(Icons.install_desktop, size: 18),
            label: Text(S.of(context).installNow),
          ),
        ),
      ],
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(border: AppTheme.borderBottom),
      child: Text(
        title,
        style: AppFonts.inter(
          fontSize: AppFonts.md,
          fontWeight: FontWeight.w600,
          color: AppTheme.accent,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Custom settings primitives — match the mockup pixel-perfect
// ═══════════════════════════════════════════════════════════════════

/// Generic settings row: [label Inter 11px fg flex] [control], minHeight 36.
/// Tappable tile for data actions (export, import, QR) — styled to match
/// _SettingsRow but with icon, subtitle, and tap handler.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      onTap: onTap,
      builder: (hovered) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: hovered ? AppTheme.hover : null,
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.fgDim),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppFonts.inter(
                      fontSize: AppFonts.sm,
                      color: AppTheme.fg,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppFonts.inter(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingsRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.barHeightSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fg,
                ),
              ),
            ),
            const SizedBox(width: 24),
            child,
          ],
        ),
      ),
    );
  }
}

/// Custom toggle pill: 32×18, borderRadius 9, accent/bg4 bg, white 14×14 thumb.
class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: label,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          width: 32,
          height: 18,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? AppTheme.accent : AppTheme.bg4,
            borderRadius: BorderRadius.circular(9),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 120),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppTheme.onAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom segment control: height 26, accent+white / bg3+fgDim.
class _SegmentControl extends StatelessWidget {
  final List<String> values;
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onChanged;

  const _SegmentControl({
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < values.length; i++) {
      if (i > 0) {
        children.add(Container(width: 1, color: AppTheme.borderLight));
      }
      final isSelected = values[i] == selected;
      children.add(
        GestureDetector(
          onTap: () => onChanged(values[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: isSelected ? AppTheme.accent : AppTheme.bg3,
            alignment: Alignment.center,
            child: Text(
              labels[i],
              style: AppFonts.inter(
                fontSize: AppFonts.sm,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                color: isSelected ? AppTheme.onAccent : AppTheme.fgDim,
              ),
            ),
          ),
        ),
      );
    }

    return AppBorderedBox(
      height: AppTheme.controlHeightXs,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Custom slider: 3px track, circle thumb bg2 + 2px accent border, width 280.
class _SliderField extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _SliderField({
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 200,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: AppTheme.bg4,
              thumbColor: AppTheme.bg2,
              thumbShape: const _CircleThumbShape(),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          format(value),
          style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fgDim),
        ),
      ],
    );
  }
}

class _CircleThumbShape extends SliderComponentShape {
  const _CircleThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(12, 12);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    // Accent border
    canvas.drawCircle(center, 6, Paint()..color = AppTheme.accent);
    // Inner circle
    canvas.drawCircle(center, 4, Paint()..color = AppTheme.bg2);
  }
}

/// Custom input field: bg bg3, height 26, borderLight, JetBrains Mono 11px.
class _InputField extends StatelessWidget {
  final String initialValue;
  final TextInputType? keyboardType;
  final double width = 100;
  final ValueChanged<String> onSubmitted;

  const _InputField({
    required this.initialValue,
    this.keyboardType,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: AppTheme.controlHeightXs,
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        textAlign: TextAlign.center,
        style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTheme.bg3,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusSm,
            borderSide: BorderSide(color: AppTheme.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusSm,
            borderSide: BorderSide(color: AppTheme.accent),
          ),
        ),
        onFieldSubmitted: onSubmitted,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Composed setting tiles using the primitives above
// ═══════════════════════════════════════════════════════════════════

class _ThemeTile extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ThemeTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return _SettingsRow(
      label: s.theme,
      child: _SegmentControl(
        values: const ['dark', 'light', 'system'],
        labels: [s.themeDark, s.themeLight, s.themeSystem],
        selected: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _LanguageTile({required this.value, required this.onChanged});

  /// Sentinel used in PopupMenuItem instead of null (which Flutter treats as
  /// "menu dismissed"). Converted back to null in onSelected.
  static const _systemDefault = '\x00';

  static const _localeLabels = <String, (String, String)>{
    _systemDefault: ('', ''),
    'en': ('English', ''),
    'ar': ('العربية', 'Arabic'),
    'zh': ('中文', 'Chinese'),
    'fr': ('Français', 'French'),
    'de': ('Deutsch', 'German'),
    'hi': ('हिन्दी', 'Hindi'),
    'id': ('Bahasa Indonesia', 'Indonesian'),
    'ja': ('日本語', 'Japanese'),
    'ko': ('한국어', 'Korean'),
    'fa': ('فارسی', 'Persian'),
    'pt': ('Português', 'Portuguese'),
    'ru': ('Русский', 'Russian'),
    'es': ('Español', 'Spanish'),
    'tr': ('Türkçe', 'Turkish'),
    'vi': ('Tiếng Việt', 'Vietnamese'),
  };

  @override
  Widget build(BuildContext context) {
    final effectiveValue = value ?? _systemDefault;
    final s = S.of(context);
    final current = _localeLabels[effectiveValue];
    final label = effectiveValue == _systemDefault
        ? s.languageSystemDefault
        : current?.$1 ?? effectiveValue;

    return _SettingsRow(
      label: s.language,
      child: PopupMenuButton<String>(
        onSelected: (v) => onChanged(v == _systemDefault ? null : v),
        tooltip: '',
        offset: const Offset(0, AppTheme.controlHeightSm),
        constraints: const BoxConstraints(
          minWidth: 200,
          maxHeight: AppTheme.popupMaxHeight,
        ),
        color: AppTheme.bg2,
        shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
        itemBuilder: (_) => _localeLabels.entries.map((e) {
          final code = e.key;
          final (native, secondary) = e.value;
          final displayNative = code == _systemDefault
              ? s.languageSystemDefault
              : native;
          return PopupMenuItem<String>(
            value: code,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayNative,
                    style: TextStyle(
                      fontSize: AppFonts.sm,
                      color: code == effectiveValue
                          ? AppTheme.accent
                          : AppTheme.fg,
                    ),
                  ),
                ),
                if (secondary.isNotEmpty)
                  Text(
                    secondary,
                    style: AppFonts.inter(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgDim,
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
        child: Container(
          height: AppTheme.controlHeightSm,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppTheme.bg3,
            borderRadius: AppTheme.radiusSm,
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.language, size: 16, color: AppTheme.fgDim),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fg,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.fgDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: title,
      child: _SliderField(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        format: format,
        onChanged: onChanged,
      ),
    );
  }
}

class _IntTile extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _IntTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      label: title,
      child: _InputField(
        initialValue: value.toString(),
        keyboardType: TextInputType.number,
        onSubmitted: (v) {
          final n = int.tryParse(v);
          if (n != null && n >= min && n <= max) {
            onChanged(n);
          }
        },
      ),
    );
  }
}

class _QrExportTile extends ConsumerWidget {
  const _QrExportTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ActionTile(
      icon: Icons.qr_code,
      title: S.of(context).shareViaQrCode,
      subtitle: S.of(context).shareViaQrSubtitle,
      onTap: () => _showQrExport(context, ref),
    );
  }

  Future<void> _showQrExport(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(sessionProvider);
    if (sessions.isEmpty) {
      Toast.show(
        context,
        message: S.of(context).noSessionsToExport,
        level: ToastLevel.warning,
      );
      return;
    }
    final store = ref.read(sessionStoreProvider);
    final deepLink = await QrExportDialog.show(
      context,
      sessions: sessions,
      emptyFolders: store.emptyFolders,
    );
    if (deepLink == null || !context.mounted) return;

    final data = decodeImportUri(Uri.parse(deepLink));
    final count = data?.sessions.length ?? 0;
    await QrDisplayScreen.show(context, data: deepLink, sessionCount: count);
  }
}

class _DataPathTile extends StatelessWidget {
  const _DataPathTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Directory>(
      future: getApplicationSupportDirectory(),
      builder: (context, snapshot) {
        final path = snapshot.data?.path ?? '...';
        return _ActionTile(
          icon: Icons.folder_special,
          title: S.of(context).dataLocation,
          subtitle: path,
          onTap: () {
            Clipboard.setData(ClipboardData(text: path));
            Toast.show(
              context,
              message: S.of(context).pathCopied,
              level: ToastLevel.info,
            );
          },
        );
      },
    );
  }
}

class _LoggingSection extends ConsumerWidget {
  const _LoggingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(configProvider.select((c) => c.enableLogging));
    final logPath = AppLogger.instance.logPath;

    return Column(
      children: [
        _Toggle(
          label: S.of(context).enableLogging,
          value: enabled,
          onChanged: (v) => ref
              .read(configProvider.notifier)
              .update((c) => c.copyWith(enableLogging: v)),
        ),
        if (enabled && logPath != null) ...[
          const SizedBox(height: 8),
          _LiveLogViewer(
            onExport: () => _exportLog(context),
            onClear: () => _clearLogs(context),
          ),
        ],
      ],
    );
  }

  Future<void> _exportLog(BuildContext context) async {
    try {
      final content = await AppLogger.instance.readLog();
      if (!context.mounted) return;
      if (content.isEmpty) {
        Toast.show(
          context,
          message: S.of(context).logIsEmpty,
          level: ToastLevel.info,
        );
        return;
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final defaultName = 'letsflutssh_log_$timestamp.txt';

      final saveTitle = S.of(context).saveLogAs;
      final chooseTitle = S.of(context).chooseSaveLocation;
      final initDir = await _defaultDirectory();

      String? outputPath;
      if (plat.isDesktopPlatform) {
        outputPath = await FilePicker.saveFile(
          dialogTitle: saveTitle,
          fileName: defaultName,
          initialDirectory: initDir,
          type: FileType.custom,
          allowedExtensions: ['txt', 'log'],
        );
      } else {
        final dir = await FilePicker.getDirectoryPath(
          dialogTitle: chooseTitle,
          initialDirectory: initDir,
        );
        if (dir != null) outputPath = p.join(dir, defaultName);
      }

      if (outputPath == null || !context.mounted) return;

      await File(outputPath).writeAsString(content);
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).logExportedTo(outputPath),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log(
        'Log export failed: $e',
        name: 'Settings',
        error: e,
      );
      if (context.mounted) {
        Toast.show(
          context,
          message: S.of(context).logExportFailed('$e'),
          level: ToastLevel.error,
        );
      }
    }
  }

  Future<void> _clearLogs(BuildContext context) async {
    await AppLogger.instance.clearLogs();
    if (!context.mounted) return;
    Toast.show(
      context,
      message: S.of(context).logsCleared,
      level: ToastLevel.info,
    );
  }
}

/// Inline live log viewer — polls the log file every second and displays the
/// content in a dark terminal-style panel with Copy and Clear action buttons.
class _LiveLogViewer extends StatefulWidget {
  final VoidCallback onExport;
  final VoidCallback onClear;

  const _LiveLogViewer({required this.onExport, required this.onClear});

  @override
  State<_LiveLogViewer> createState() => _LiveLogViewerState();
}

class _LiveLogViewerState extends State<_LiveLogViewer> {
  final _scrollController = ScrollController();
  String _content = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final text = await AppLogger.instance.readLog();
    if (!mounted) return;
    final changed = text != _content;
    setState(() => _content = text);
    if (changed && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = AppTheme.bg0;
    final fg = AppTheme.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar
        Row(
          children: [
            Icon(Icons.circle, size: 8, color: fg),
            const SizedBox(width: 6),
            Text(
              S.of(context).liveLog,
              style: TextStyle(
                fontSize: AppFonts.md,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const Spacer(),
            AppIconButton(
              icon: Icons.copy,
              onTap: () {
                Clipboard.setData(ClipboardData(text: _content));
                Toast.show(
                  context,
                  message: _content.isEmpty
                      ? S.of(context).logIsEmpty
                      : S.of(context).copiedToClipboard,
                  level: ToastLevel.info,
                );
              },
              tooltip: S.of(context).copyLog,
              size: 16,
            ),
            AppIconButton(
              icon: Icons.save_alt,
              onTap: widget.onExport,
              tooltip: S.of(context).exportLog,
              size: 16,
            ),
            AppIconButton(
              icon: Icons.delete_outline,
              onTap: () async {
                widget.onClear();
                await Future<void>.delayed(const Duration(milliseconds: 100));
                await _refresh();
              },
              tooltip: S.of(context).clearLogs,
              size: 16,
            ),
          ],
        ),
        // Log content — fill remaining vertical space
        LayoutBuilder(
          builder: (context, constraints) {
            // Use available height minus toolbar (~40px), clamped to reasonable min
            final availableHeight = MediaQuery.of(context).size.height - 200;
            return Container(
              width: double.infinity,
              height: availableHeight.clamp(200.0, double.infinity),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppTheme.radiusLg,
              ),
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SelectableText(
                  _content.isEmpty ? '(no log entries yet)' : _content,
                  style: TextStyle(
                    fontSize: AppFonts.sm,
                    fontFamily: 'monospace',
                    color: fg,
                    height: 1.4,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Mutable holder for passing state by reference into extracted helper methods.
class _ValueHolder<T> {
  T value;
  _ValueHolder(this.value);
}

// ── Export password dialog ──

class _ExportPasswordDialog extends StatelessWidget {
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;

  const _ExportPasswordDialog({
    required this.passwordCtrl,
    required this.confirmCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).exportData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            S.of(context).setMasterPasswordHint,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          ),
          const SizedBox(height: 16),
          _styledPasswordField(passwordCtrl, S.of(context).masterPassword),
          const SizedBox(height: 8),
          _styledPasswordField(confirmCtrl, S.of(context).confirmPassword),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: S.of(context).export_,
          onTap: () {
            if (passwordCtrl.text.isEmpty) return;
            if (passwordCtrl.text != confirmCtrl.text) {
              Toast.show(
                context,
                message: S.of(context).passwordsDoNotMatch,
                level: ToastLevel.warning,
              );
              return;
            }
            Navigator.pop(context, passwordCtrl.text);
          },
        ),
      ],
    );
  }

  static Widget _styledPasswordField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppTheme.fgFaint),
        filled: true,
        fillColor: AppTheme.bg3,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.accent),
        ),
      ),
    );
  }
}

// ── Import data dialog ──

class _ImportDataDialog extends StatefulWidget {
  final TextEditingController pathCtrl;
  final TextEditingController passwordCtrl;
  final _ValueHolder<ImportMode> modeHolder;

  const _ImportDataDialog({
    required this.pathCtrl,
    required this.passwordCtrl,
    required this.modeHolder,
  });

  @override
  State<_ImportDataDialog> createState() => _ImportDataDialogState();
}

class _ImportDataDialogState extends State<_ImportDataDialog> {
  Future<void> _pickFile() async {
    final title = S.of(context).pathToLfsFile;
    final initDir = await _defaultDirectory();
    final result = await FilePicker.pickFiles(
      dialogTitle: title,
      initialDirectory: initDir,
      type: FileType.custom,
      allowedExtensions: ['lfs'],
    );
    final path = result?.files.single.path;
    if (path != null) {
      widget.pathCtrl.text = path;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).importData,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _styledTextField(
                  widget.pathCtrl,
                  S.of(context).pathToLfsFile,
                  hint: S.of(context).hintLfsPath,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: AppTheme.controlHeightLg,
                child: TextButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(S.of(context).browse),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    textStyle: AppFonts.inter(fontSize: AppFonts.sm),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.passwordCtrl,
            obscureText: true,
            style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
            decoration: InputDecoration(
              labelText: S.of(context).masterPassword,
              labelStyle: TextStyle(color: AppTheme.fgFaint),
              filled: true,
              fillColor: AppTheme.bg3,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppTheme.radiusSm,
                borderSide: BorderSide(color: AppTheme.accent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildModeSelector(),
          const SizedBox(height: 4),
          Text(
            widget.modeHolder.value == ImportMode.merge
                ? S.of(context).importModeMergeDescription
                : S.of(context).importModeReplaceDescription,
            style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
          ),
        ],
      ),
      actions: [
        AppDialogAction.cancel(onTap: () => Navigator.pop(context)),
        AppDialogAction.primary(
          label: S.of(context).import_,
          onTap: () {
            if (widget.pathCtrl.text.isEmpty ||
                widget.passwordCtrl.text.isEmpty) {
              return;
            }
            Navigator.pop(context, (
              path: widget.pathCtrl.text,
              password: widget.passwordCtrl.text,
              mode: widget.modeHolder.value,
            ));
          },
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        _modeButton(S.of(context).merge, Icons.merge, ImportMode.merge),
        const SizedBox(width: 8),
        _modeButton(
          S.of(context).replace,
          Icons.swap_horiz,
          ImportMode.replace,
        ),
      ],
    );
  }

  Widget _modeButton(String label, IconData icon, ImportMode mode) {
    final selected = widget.modeHolder.value == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => widget.modeHolder.value = mode),
        child: Container(
          height: AppTheme.controlHeightLg,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.bg3,
            borderRadius: AppTheme.radiusSm,
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.borderLight,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppTheme.onAccent : AppTheme.fgDim,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.sm,
                  fontWeight: selected ? FontWeight.w600 : null,
                  color: selected ? AppTheme.onAccent : AppTheme.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _styledTextField(
    TextEditingController ctrl,
    String label, {
    String? hint,
  }) {
    return TextField(
      controller: ctrl,
      style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AppTheme.fgFaint),
        hintStyle: TextStyle(color: AppTheme.fgFaint),
        filled: true,
        fillColor: AppTheme.bg3,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppTheme.radiusSm,
          borderSide: BorderSide(color: AppTheme.accent),
        ),
      ),
    );
  }
}
