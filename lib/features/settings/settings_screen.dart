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
import '../../utils/logger.dart';
import '../../providers/session_provider.dart';
import '../../utils/platform.dart' as plat;
import '../../theme/app_theme.dart';
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

/// Mobile: collapsible sections in a scrollable list.
class _MobileSettingsScreen extends ConsumerWidget {
  const _MobileSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = _buildSections();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
              onPressed: () => ref.read(configProvider.notifier).update((_) => AppConfig.defaults),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Reset to Defaults'),
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
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ExpansionTile(
        leading: Icon(widget.icon, size: 20),
        title: Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [widget.child],
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
    final sections = _buildSections();

    return Scaffold(
      body: Column(
        children: [
          // ── Header ──
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: AppTheme.bg1,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.arrow_back, size: 16, color: AppTheme.fgDim),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Settings',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.fgBright,
                  ),
                ),
              ],
            ),
          ),
          // ── Body ──
          Expanded(
            child: Row(
              children: [
                // ── Left nav ──
                Container(
                  width: 160,
                  color: AppTheme.bg1,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
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
                      _ResetButton(
                        onTap: () => ref.read(configProvider.notifier).update((_) => AppConfig.defaults),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1, color: AppTheme.border),
                // ── Content pane ──
                Expanded(
                  child: DefaultTextStyle(
                    style: AppFonts.inter(fontSize: 11, color: AppTheme.fg),
                    child: ListView(
                      key: ValueKey(_selectedIndex),
                      padding: const EdgeInsets.all(24),
                      children: [
                        _SectionHeader(title: sections[_selectedIndex].title),
                        sections[_selectedIndex].builder(),
                      ],
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
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: widget.selected
              ? AppTheme.selection
              : _hovered
                  ? AppTheme.hover
                  : Colors.transparent,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (widget.selected)
                Positioned(
                  left: 0,
                  top: 4,
                  bottom: 4,
                  child: Container(width: 2, color: AppTheme.accent),
                ),
              Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 13,
                    color: widget.selected ? AppTheme.accent : AppTheme.fgDim,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: widget.selected ? FontWeight.w500 : FontWeight.normal,
                        color: widget.selected ? AppTheme.accent : AppTheme.fgDim,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: _hovered ? AppTheme.hover : Colors.transparent,
          child: const Row(
            children: [
              Icon(Icons.restore, size: 12, color: AppTheme.red),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Reset to Defaults',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
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
    final theme = ref.watch(configProvider.select((c) => c.theme));
    final fontSize = ref.watch(configProvider.select((c) => c.fontSize));
    final uiScale = ref.watch(configProvider.select((c) => c.uiScale));
    return Column(
      children: [
        _ThemeTile(
          value: theme,
          onChanged: (v) => ref.read(configProvider.notifier).update((c) => c.copyWith(terminal: c.terminal.copyWith(theme: v))),
        ),
        _SliderTile(
          title: 'UI Scale',
          value: uiScale,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => ref.read(configProvider.notifier).update((c) => c.copyWith(ui: c.ui.copyWith(uiScale: v))),
        ),
        _SliderTile(
          title: 'Terminal Font Size',
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
      final outputPath = await _pickSavePath('export_$timestamp.lfs', 'lfs');
      if (outputPath == null || !context.mounted) return;

      await _runExport(context, ref, password, outputPath);
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

  Future<void> _runExport(
    BuildContext context,
    WidgetRef ref,
    String password,
    String outputPath,
  ) async {
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
      await ExportImport.export(
        masterPassword: password,
        sessions: ref.read(sessionProvider),
        config: ref.read(configProvider),
        outputPath: outputPath,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        Toast.show(context, message: 'Exported to: $outputPath', level: ToastLevel.success);
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      rethrow;
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
        _Toggle(
          label: 'Check for Updates on Startup',
          value: checkOnStart,
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
        return ListTile(
          leading: Icon(Icons.check_circle_outline, size: 20,
              color: theme.colorScheme.primary),
          title: const Text('You\'re up to date'),
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
    final skipped = ref.watch(configProvider.select((c) => c.skippedVersion));
    final isSkipped = skipped == info.latestVersion;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.system_update, size: 20),
          title: Text('Version ${info.latestVersion} available'),
          subtitle: Text(
            isSkipped
                ? 'Current: v${info.currentVersion} (skipped)'
                : 'Current: v${info.currentVersion}',
          ),
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
                  label: const Text('Download & Install'),
                )
              else
                OutlinedButton.icon(
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
              if (!isSkipped)
                TextButton(
                  onPressed: () => ref.read(configProvider.notifier).update(
                    (c) => c.withSkippedVersion(info.latestVersion),
                  ),
                  child: const Text('Skip This Version'),
                )
              else
                TextButton(
                  onPressed: () => ref.read(configProvider.notifier).update(
                    (c) => c.withSkippedVersion(null),
                  ),
                  child: const Text('Unskip'),
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
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
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
class _SettingsRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingsRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppFonts.inter(fontSize: 11, color: AppTheme.fg),
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
              decoration: const BoxDecoration(
                color: Colors.white,
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
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                color: isSelected ? Colors.white : AppTheme.fgDim,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 26,
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.borderLight),
      ),
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
          style: AppFonts.mono(fontSize: 11, color: AppTheme.fgDim),
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
    canvas.drawCircle(
      center,
      6,
      Paint()..color = AppTheme.accent,
    );
    // Inner circle
    canvas.drawCircle(
      center,
      4,
      Paint()..color = AppTheme.bg2,
    );
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
      height: 26,
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        textAlign: TextAlign.center,
        style: AppFonts.mono(fontSize: 11, color: AppTheme.fg),
        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTheme.bg3,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppTheme.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
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
    return _SettingsRow(
      label: 'Theme',
      child: _SegmentControl(
        values: const ['dark', 'light', 'system'],
        labels: const ['Dark', 'Light', 'System'],
        selected: value,
        onChanged: onChanged,
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
        _Toggle(
          label: 'Enable Logging',
          value: enabled,
          onChanged: (v) => ref.read(configProvider.notifier).update(
            (c) => c.copyWith(enableLogging: v),
          ),
        ),
        if (enabled && logPath != null) ...[
          const SizedBox(height: 8),
          _LiveLogViewer(onExport: () => _exportLog(context), onClear: () => _clearLogs(context)),
        ],
      ],
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

  Future<void> _clearLogs(BuildContext context) async {
    await AppLogger.instance.clearLogs();
    if (!context.mounted) return;
    Toast.show(context, message: 'Logs cleared', level: ToastLevel.info);
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
    const bg = Colors.black87;
    final fg = Colors.green.shade300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar
        Row(
          children: [
            Icon(Icons.circle, size: 8, color: fg),
            const SizedBox(width: 6),
            Text('Live Log', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const Spacer(),
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _content));
                Toast.show(context,
                  message: _content.isEmpty ? 'Log is empty' : 'Copied to clipboard',
                  level: ToastLevel.info,
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Copy log',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            IconButton(
              onPressed: widget.onExport,
              icon: const Icon(Icons.save_alt, size: 16),
              tooltip: 'Export log',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            IconButton(
              onPressed: () async {
                widget.onClear();
                await Future<void>.delayed(const Duration(milliseconds: 100));
                await _refresh();
              },
              icon: const Icon(Icons.delete_outline, size: 16),
              tooltip: 'Clear logs',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        // Log content
        Container(
          width: double.infinity,
          height: 400,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: SelectableText(
              _content.isEmpty ? '(no log entries yet)' : _content,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg, height: 1.4),
            ),
          ),
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
