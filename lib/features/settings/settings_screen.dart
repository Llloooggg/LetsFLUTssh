import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/import/import_service.dart';
import '../../providers/config_provider.dart';
import '../../utils/logger.dart';
import '../../providers/session_provider.dart';
import '../../widgets/toast.dart';
import 'export_import.dart';

/// App version — kept in sync with pubspec.yaml.
const _appVersion = '1.0.5';
const _githubUrl = 'https://github.com/Llloooggg/LetsFLUTssh';

/// Settings screen with config editing.
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(title: 'Appearance'),
          const _AppearanceSection(),

          const Divider(height: 32),

          const _SectionHeader(title: 'Terminal'),
          const _TerminalSection(),

          const Divider(height: 32),

          const _SectionHeader(title: 'Connection'),
          const _ConnectionSection(),

          const Divider(height: 32),

          const _SectionHeader(title: 'Transfers'),
          const _TransferSection(),

          const Divider(height: 32),

          const _SectionHeader(title: 'Data'),
          _ExportImportTile(),
          const _DataPathTile(),

          const Divider(height: 32),

          const _SectionHeader(title: 'Logging'),
          const _LoggingSection(),

          const Divider(height: 32),

          const _SectionHeader(title: 'About'),
          const _AboutSection(),

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

    try {
      final sessions = ref.read(sessionProvider);
      final config = ref.read(configProvider);
      final dir = await getApplicationSupportDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final outputPath = p.join(dir.path, 'export_$timestamp.lfs');

      await ExportImport.export(
        masterPassword: password,
        sessions: sessions,
        config: config,
        outputPath: outputPath,
      );

      if (context.mounted) {
        Toast.show(context, message: 'Exported to: $outputPath', level: ToastLevel.success);
      }
    } catch (e) {
      AppLogger.instance.log('Export failed: $e', name: 'Settings', error: e);
      if (context.mounted) {
        Toast.show(context, message: 'Export failed: $e', level: ToastLevel.error);
      }
    }
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final pathCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final modeHolder = _ValueHolder(ImportMode.merge);

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
        Toast.show(
          context,
          message: 'Imported ${importResult.sessions.length} session(s)',
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log('Import failed: $e', name: 'Settings', error: e);
      if (context.mounted) {
        Toast.show(context, message: 'Import failed: $e', level: ToastLevel.error);
      }
    }
  }

}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const ListTile(
          leading: Icon(Icons.info_outline, size: 20),
          title: Text('LetsFLUTssh'),
          subtitle: Text('v$_appVersion — SSH/SFTP client'),
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
