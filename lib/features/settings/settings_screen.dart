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
import '../../utils/logger.dart';
import '../../providers/session_provider.dart';
import '../../utils/platform.dart' as plat;
import '../../widgets/toast.dart';
import '../session_manager/qr_display_screen.dart';
import '../session_manager/qr_export_dialog.dart';
import 'export_import.dart';

const _githubUrl = 'https://github.com/Llloooggg/LetsFLUTssh';

/// Section descriptor for navigation and content rendering.
class _Section {
  final String title;
  final IconData icon;
  final Widget Function() builder;

  const _Section({required this.title, required this.icon, required this.builder});
}

/// Ordered list of all settings sections.
List<_Section> _buildSections() => [
  const _Section(title: 'Appearance', icon: Icons.palette, builder: _AppearanceSection.new),
  const _Section(title: 'Terminal', icon: Icons.terminal, builder: _TerminalSection.new),
  const _Section(title: 'Connection', icon: Icons.lan, builder: _ConnectionSection.new),
  const _Section(title: 'Transfers', icon: Icons.swap_horiz, builder: _TransferSection.new),
  const _Section(title: 'Data', icon: Icons.storage, builder: _DataSection.new),
  const _Section(title: 'Logging', icon: Icons.description, builder: _LoggingSection.new),
  const _Section(title: 'Updates', icon: Icons.system_update, builder: _UpdateSection.new),
  const _Section(title: 'About', icon: Icons.info_outline, builder: _AboutSection.new),
];

/// Settings screen with config editing.
///
/// Desktop: two-column layout (nav rail + content pane).
/// Mobile: flat scrollable list (unchanged).
///
/// Each section watches only its own config fields via `select()` to avoid
/// unnecessary rebuilds when unrelated settings change.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (plat.isMobilePlatform) {
      return const _MobileSettingsScreen();
    }
    return const _DesktopSettingsScreen();
  }
}

/// Mobile: flat scrollable list with all sections separated by dividers.
class _MobileSettingsScreen extends ConsumerWidget {
  const _MobileSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = _buildSections();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const Divider(height: 32),
            _SectionHeader(title: sections[i].title),
            sections[i].builder(),
          ],
          const Divider(height: 32),
          Center(
            child: TextButton.icon(
              onPressed: () => ref.read(configProvider.notifier).update((_) => AppConfig.defaults),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Reset to Defaults'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop: navigation rail on the left, content pane on the right.
class _DesktopSettingsScreen extends ConsumerStatefulWidget {
  const _DesktopSettingsScreen();

  @override
  ConsumerState<_DesktopSettingsScreen> createState() => _DesktopSettingsScreenState();
}

class _DesktopSettingsScreenState extends ConsumerState<_DesktopSettingsScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = _buildSections();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Row(
        children: [
          // --- Navigation rail ---
          SizedBox(
            width: 180,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: sections.length,
                    itemBuilder: (context, index) {
                      final section = sections[index];
                      final selected = index == _selectedIndex;
                      return _NavItem(
                        icon: section.icon,
                        label: section.title,
                        selected: selected,
                        onTap: () => setState(() => _selectedIndex = index),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextButton.icon(
                    onPressed: () => ref.read(configProvider.notifier).update((_) => AppConfig.defaults),
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('Reset to Defaults', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: theme.dividerColor),
          // --- Content pane ---
          Expanded(
            child: ListView(
              key: ValueKey(_selectedIndex),
              padding: const EdgeInsets.all(24),
              children: [
                _SectionHeader(title: sections[_selectedIndex].title),
                sections[_selectedIndex].builder(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single item in the desktop navigation rail.
class _NavItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
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
    final theme = ref.watch(configProvider.select((c) => c.theme));
    final fontSize = ref.watch(configProvider.select((c) => c.fontSize));
    return Column(
      children: [
        _ThemeTile(
          value: theme,
          onChanged: (v) => ref.read(configProvider.notifier).update((c) => c.copyWith(terminal: c.terminal.copyWith(theme: v))),
        ),
        _SliderTile(
          title: 'Font Size',
          value: fontSize,
          min: 8,
          max: 24,
          divisions: 16,
          format: (v) => '${v.round()}',
          onChanged: (v) => ref.read(configProvider.notifier).update((c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: v))),
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
      title: 'Scrollback Lines',
      value: scrollback,
      min: 100,
      max: 100000,
      onChanged: (v) => ref.read(configProvider.notifier).update((c) => c.copyWith(terminal: c.terminal.copyWith(scrollback: v))),
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
          title: 'Keep-Alive Interval (sec)',
          value: keepAlive,
          min: 0,
          max: 300,
          onChanged: (v) => ref.read(configProvider.notifier).update((c) => c.copyWith(ssh: c.ssh.copyWith(keepAliveSec: v))),
        ),
        _IntTile(
          title: 'SSH Timeout (sec)',
          value: timeout,
          min: 1,
          max: 60,
          onChanged: (v) => ref.read(configProvider.notifier).update((c) => c.copyWith(ssh: c.ssh.copyWith(sshTimeoutSec: v))),
        ),
        _IntTile(
          title: 'Default Port',
          value: port,
          min: 1,
          max: 65535,
          onChanged: (v) => ref.read(configProvider.notifier).update((c) => c.copyWith(ssh: c.ssh.copyWith(defaultPort: v))),
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
    return Column(
      children: [
        _IntTile(
          title: 'Parallel Workers',
          value: workers,
          min: 1,
          max: 10,
          onChanged: (v) => ref.read(configProvider.notifier).update((c) => c.copyWith(transferWorkers: v)),
        ),
        _IntTile(
          title: 'Max History',
          value: maxHistory,
          min: 10,
          max: 5000,
          onChanged: (v) => ref.read(configProvider.notifier).update((c) => c.copyWith(maxHistory: v)),
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
        ListTile(
          leading: const Icon(Icons.upload_file, size: 20),
          title: const Text('Export Data'),
          subtitle: const Text('Save sessions, config, and keys to encrypted .lfs file'),
          contentPadding: EdgeInsets.zero,
          onTap: () => _showExportDialog(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.download, size: 20),
          title: const Text('Import Data'),
          subtitle: const Text('Load data from .lfs file'),
          contentPadding: EdgeInsets.zero,
          onTap: () => _showImportDialog(context, ref),
        ),
      ],
    );
  }

  Future<void> _showExportDialog(BuildContext context, WidgetRef ref) async {
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    try {
      final password = await showDialog<String>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (ctx) => AlertDialog(
          title: const Text('Export Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Set a master password to encrypt the archive.'),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Master Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (passwordCtrl.text.isEmpty) return;
                if (passwordCtrl.text != confirmCtrl.text) {
                  Toast.show(ctx, message: 'Passwords do not match', level: ToastLevel.warning);
                  return;
                }
                Navigator.pop(ctx, passwordCtrl.text);
              },
              child: const Text('Export'),
            ),
          ],
        ),
      );

      if (password == null || !context.mounted) return;

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final defaultName = 'export_$timestamp.lfs';

      final outputPath = await _pickSavePath(defaultName, 'lfs');
      if (outputPath == null || !context.mounted) return;

      // Show progress indicator while PBKDF2 + encryption runs in isolate
      showDialog(
        context: context,
        barrierDismissible: false,
        animationStyle: AnimationStyle.noAnimation,
        builder: (_) => const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      );

      try {
        final sessions = ref.read(sessionProvider);
        final config = ref.read(configProvider);

        await ExportImport.export(
          masterPassword: password,
          sessions: sessions,
          config: config,
          outputPath: outputPath,
        );

        if (context.mounted) {
          Navigator.of(context).pop(); // close progress
          Toast.show(context, message: 'Exported to: $outputPath', level: ToastLevel.success);
        }
      } catch (e) {
        if (context.mounted) Navigator.of(context).pop(); // close progress
        rethrow;
      }
    } catch (e) {
      AppLogger.instance.log('Export failed: $e', name: 'Settings', error: e);
      if (context.mounted) {
        Toast.show(context, message: 'Export failed: $e', level: ToastLevel.error);
      }
    } finally {
      passwordCtrl.dispose();
      confirmCtrl.dispose();
    }
  }

  /// Opens a save-file picker. Desktop uses native save dialog,
  /// mobile uses directory picker + default filename.
  Future<String?> _pickSavePath(String defaultName, String extension) async {
    if (plat.isDesktopPlatform) {
      return FilePicker.platform.saveFile(
        dialogTitle: 'Save as',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
    }
    // Mobile: pick directory, append default filename
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose save location',
    );
    if (dir == null) return null;
    return p.join(dir, defaultName);
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final pathCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final modeHolder = _ValueHolder(ImportMode.merge);

    try {
      final result = await showDialog<({String path, String password, ImportMode mode})>(
        context: context,
        animationStyle: AnimationStyle.noAnimation,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Import Data'),
            content: _buildImportDialogContent(ctx, pathCtrl, passwordCtrl, modeHolder, setState),
            actions: _buildImportDialogActions(ctx, pathCtrl, passwordCtrl, modeHolder),
          ),
        ),
      );

      if (result == null || !context.mounted) return;
      await _executeImport(context, ref, result);
    } finally {
      pathCtrl.dispose();
      passwordCtrl.dispose();
    }
  }

  Column _buildImportDialogContent(
    BuildContext ctx,
    TextEditingController pathCtrl,
    TextEditingController passwordCtrl,
    _ValueHolder<ImportMode> modeHolder,
    StateSetter setState,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: pathCtrl,
          decoration: const InputDecoration(
            labelText: 'Path to .lfs file',
            border: OutlineInputBorder(),
            hintText: '/path/to/export.lfs',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Master Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _buildImportModeSelector(ctx, modeHolder, setState),
      ],
    );
  }

  Widget _buildImportModeSelector(
    BuildContext ctx,
    _ValueHolder<ImportMode> modeHolder,
    StateSetter setState,
  ) {
    return Column(
      children: [
        SegmentedButton<ImportMode>(
          segments: const [
            ButtonSegment(
              value: ImportMode.merge,
              label: Text('Merge'),
              icon: Icon(Icons.merge, size: 16),
            ),
            ButtonSegment(
              value: ImportMode.replace,
              label: Text('Replace'),
              icon: Icon(Icons.swap_horiz, size: 16),
            ),
          ],
          selected: {modeHolder.value},
          onSelectionChanged: (s) => setState(() => modeHolder.value = s.first),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(height: 4),
        Text(
          modeHolder.value == ImportMode.merge
              ? 'Add new sessions, keep existing'
              : 'Replace all sessions with imported',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildImportDialogActions(
    BuildContext ctx,
    TextEditingController pathCtrl,
    TextEditingController passwordCtrl,
    _ValueHolder<ImportMode> modeHolder,
  ) {
    return [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (pathCtrl.text.isEmpty || passwordCtrl.text.isEmpty) return;
          Navigator.pop(ctx, (
            path: pathCtrl.text,
            password: passwordCtrl.text,
            mode: modeHolder.value,
          ));
        },
        child: const Text('Import'),
      ),
    ];
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
          Toast.show(context, message: 'File not found: ${result.path}', level: ToastLevel.error);
        }
        return;
      }

      // Show progress indicator while PBKDF2 + decryption runs in isolate
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          animationStyle: AnimationStyle.noAnimation,
          builder: (_) => const PopScope(
            canPop: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        );
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
          applyConfig: (config) => ref.read(configProvider.notifier).update((_) => config),
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
        Toast.show(context, message: 'Import failed: $e', level: ToastLevel.error);
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
        SwitchListTile(
          title: const Text('Check for Updates on Startup'),
          value: checkOnStart,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => ref.read(configProvider.notifier).update(
            (c) => c.copyWith(checkUpdatesOnStart: v),
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
    return ListTile(
      leading: isChecking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 20),
      title: Text(isChecking ? 'Checking...' : 'Check for Updates'),
      contentPadding: EdgeInsets.zero,
      onTap: isChecking ? null : () async {
        await ref.read(updateProvider.notifier).check();
        if (!context.mounted) return;
        final state = ref.read(updateProvider);
        if (state.status == UpdateStatus.upToDate) {
          Toast.show(context,
              message: 'You\'re running the latest version',
              level: ToastLevel.success);
        } else if (state.status == UpdateStatus.updateAvailable) {
          Toast.show(context,
              message: 'Version ${state.info!.latestVersion} available',
              level: ToastLevel.info);
        } else if (state.status == UpdateStatus.error) {
          Toast.show(context,
              message: state.error ?? 'Update check failed',
              level: ToastLevel.error);
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
        final version = ref.watch(appVersionProvider);
        return ListTile(
          leading: Icon(Icons.check_circle_outline, size: 20,
              color: theme.colorScheme.primary),
          title: Text('You\'re up to date (v$version)'),
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
            'Downloading... ${(updateState.progress * 100).toInt()}%',
          ),
          contentPadding: EdgeInsets.zero,
        );

      case UpdateStatus.downloaded:
        return _buildDownloaded(context, ref, updateState);

      case UpdateStatus.error:
        return ListTile(
          leading: Icon(Icons.error_outline, size: 20,
              color: theme.colorScheme.error),
          title: const Text('Update check failed'),
          subtitle: Text(
            updateState.error ?? 'Unknown error',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
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

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.system_update, size: 20),
          title: Text('Version ${info.latestVersion} available'),
          subtitle: Text('Current: v${info.currentVersion}'),
          contentPadding: EdgeInsets.zero,
        ),
        if (hasAsset && plat.isDesktopPlatform)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: FilledButton.icon(
              onPressed: () => ref.read(updateProvider.notifier).download(),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download & Install'),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: OutlinedButton.icon(
              onPressed: () async {
                final url = Uri.parse(info.releaseUrl);
                if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                  if (context.mounted) {
                    Clipboard.setData(ClipboardData(text: info.releaseUrl));
                    Toast.show(context,
                        message: 'Could not open browser — URL copied to clipboard',
                        level: ToastLevel.warning);
                  }
                }
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open in Browser'),
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
          title: const Text('Download complete'),
          subtitle: Text(
            updateState.downloadedPath ?? '',
            style: const TextStyle(fontSize: 12),
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
                Toast.show(context,
                    message: 'Could not open installer',
                    level: ToastLevel.error);
              }
            },
            icon: const Icon(Icons.install_desktop, size: 18),
            label: const Text('Install Now'),
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
          title: const Text('LetsFLUTssh'),
          subtitle: Text('v$version — SSH/SFTP client'),
          contentPadding: EdgeInsets.zero,
        ),
        ListTile(
          leading: const Icon(Icons.code, size: 20),
          title: const Text('Source Code'),
          subtitle: Text(
            _githubUrl,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 13,
            ),
          ),
          contentPadding: EdgeInsets.zero,
          onTap: () {
            Clipboard.setData(const ClipboardData(text: _githubUrl));
            Toast.show(context, message: 'URL copied to clipboard', level: ToastLevel.info);
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ThemeTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Theme'),
      contentPadding: EdgeInsets.zero,
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'dark', label: Text('Dark')),
          ButtonSegment(value: 'light', label: Text('Light')),
          ButtonSegment(value: 'system', label: Text('System')),
        ],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.first),
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
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
    return ListTile(
      title: Text(title),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: format(value),
        onChanged: onChanged,
      ),
      trailing: Text(format(value)),
      contentPadding: EdgeInsets.zero,
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
    return ListTile(
      title: Text(title),
      contentPadding: EdgeInsets.zero,
      trailing: SizedBox(
        width: 100,
        child: TextFormField(
          initialValue: value.toString(),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: (v) {
            final n = int.tryParse(v);
            if (n != null && n >= min && n <= max) {
              onChanged(n);
            }
          },
        ),
      ),
    );
  }
}

class _QrExportTile extends ConsumerWidget {
  const _QrExportTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.qr_code, size: 20),
      title: const Text('Share via QR Code'),
      subtitle: const Text('Export sessions to QR for scanning by another device'),
      contentPadding: EdgeInsets.zero,
      onTap: () => _showQrExport(context, ref),
    );
  }

  Future<void> _showQrExport(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(sessionProvider);
    if (sessions.isEmpty) {
      Toast.show(context, message: 'No sessions to export', level: ToastLevel.warning);
      return;
    }
    final store = ref.read(sessionStoreProvider);
    final deepLink = await QrExportDialog.show(
      context,
      sessions: sessions,
      emptyGroups: store.emptyGroups,
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
        return ListTile(
          leading: const Icon(Icons.folder_special, size: 20),
          title: const Text('Data Location'),
          subtitle: Text(path, style: const TextStyle(fontSize: 12)),
          contentPadding: EdgeInsets.zero,
          onTap: () {
            Clipboard.setData(ClipboardData(text: path));
            Toast.show(context, message: 'Path copied to clipboard', level: ToastLevel.info);
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
        SwitchListTile(
          title: const Text('Enable Logging'),
          subtitle: const Text('Write diagnostic logs to file (no sensitive data)'),
          value: enabled,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => ref.read(configProvider.notifier).update(
            (c) => c.copyWith(enableLogging: v),
          ),
        ),
        if (enabled && logPath != null) ...[
          ListTile(
            leading: const Icon(Icons.visibility, size: 20),
            title: const Text('View Log'),
            contentPadding: EdgeInsets.zero,
            onTap: () => _showLogDialog(context),
          ),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  leading: const Icon(Icons.save_alt, size: 20),
                  title: const Text('Export Log'),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _exportLog(context),
                ),
              ),
              Expanded(
                child: ListTile(
                  leading: const Icon(Icons.copy, size: 20),
                  title: const Text('Copy Log'),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _copyLog(context),
                ),
              ),
              Expanded(
                child: ListTile(
                  leading: const Icon(Icons.delete_outline, size: 20),
                  title: const Text('Clear Logs'),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _clearLogs(context),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _showLogDialog(BuildContext context) async {
    final content = await AppLogger.instance.readLog();
    if (!context.mounted) return;
    showDialog(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Log'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(
              content.isEmpty ? '(empty)' : content,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              Toast.show(ctx, message: 'Log copied to clipboard', level: ToastLevel.info);
            },
            child: const Text('Copy All'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportLog(BuildContext context) async {
    try {
      final content = await AppLogger.instance.readLog();
      if (!context.mounted) return;
      if (content.isEmpty) {
        Toast.show(context, message: 'Log is empty', level: ToastLevel.info);
        return;
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final defaultName = 'letsflutssh_log_$timestamp.txt';

      String? outputPath;
      if (plat.isDesktopPlatform) {
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save log as',
          fileName: defaultName,
          type: FileType.custom,
          allowedExtensions: ['txt', 'log'],
        );
      } else {
        final dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose save location',
        );
        if (dir != null) outputPath = p.join(dir, defaultName);
      }

      if (outputPath == null || !context.mounted) return;

      await File(outputPath).writeAsString(content);
      if (context.mounted) {
        Toast.show(context, message: 'Log exported to: $outputPath', level: ToastLevel.success);
      }
    } catch (e) {
      AppLogger.instance.log('Log export failed: $e', name: 'Settings', error: e);
      if (context.mounted) {
        Toast.show(context, message: 'Log export failed: $e', level: ToastLevel.error);
      }
    }
  }

  Future<void> _copyLog(BuildContext context) async {
    final content = await AppLogger.instance.readLog();
    if (!context.mounted) return;
    Clipboard.setData(ClipboardData(text: content));
    Toast.show(context,
      message: content.isEmpty ? 'Log is empty' : 'Log copied to clipboard',
      level: ToastLevel.info,
    );
  }

  Future<void> _clearLogs(BuildContext context) async {
    await AppLogger.instance.clearLogs();
    if (!context.mounted) return;
    Toast.show(context, message: 'Logs cleared', level: ToastLevel.info);
  }
}

/// Mutable holder for passing state by reference into extracted helper methods.
class _ValueHolder<T> {
  T value;
  _ValueHolder(this.value);
}
