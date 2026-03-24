import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../providers/config_provider.dart';
import '../../providers/session_provider.dart';
import '../../widgets/toast.dart';
import 'export_import.dart';

/// Settings screen with config editing.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Appearance
          const _SectionHeader(title: 'Appearance'),
          _ThemeTile(
            value: config.theme,
            onChanged: (v) => _update(ref, (c) => c.copyWith(theme: v)),
          ),
          _SliderTile(
            title: 'Font Size',
            value: config.fontSize,
            min: 8,
            max: 24,
            divisions: 16,
            format: (v) => '${v.round()}',
            onChanged: (v) => _update(ref, (c) => c.copyWith(fontSize: v)),
          ),

          const Divider(height: 32),

          // Terminal
          const _SectionHeader(title: 'Terminal'),
          _IntTile(
            title: 'Scrollback Lines',
            value: config.scrollback,
            min: 100,
            max: 100000,
            onChanged: (v) => _update(ref, (c) => c.copyWith(scrollback: v)),
          ),

          const Divider(height: 32),

          // Connection
          const _SectionHeader(title: 'Connection'),
          _IntTile(
            title: 'Keep-Alive Interval (sec)',
            value: config.keepAliveSec,
            min: 0,
            max: 300,
            onChanged: (v) => _update(ref, (c) => c.copyWith(keepAliveSec: v)),
          ),
          _IntTile(
            title: 'SSH Timeout (sec)',
            value: config.sshTimeoutSec,
            min: 1,
            max: 60,
            onChanged: (v) => _update(ref, (c) => c.copyWith(sshTimeoutSec: v)),
          ),
          _IntTile(
            title: 'Default Port',
            value: config.defaultPort,
            min: 1,
            max: 65535,
            onChanged: (v) => _update(ref, (c) => c.copyWith(defaultPort: v)),
          ),

          const Divider(height: 32),

          // Transfers
          const _SectionHeader(title: 'Transfers'),
          _IntTile(
            title: 'Parallel Workers',
            value: config.transferWorkers,
            min: 1,
            max: 10,
            onChanged: (v) => _update(ref, (c) => c.copyWith(transferWorkers: v)),
          ),
          _IntTile(
            title: 'Max History',
            value: config.maxHistory,
            min: 10,
            max: 5000,
            onChanged: (v) => _update(ref, (c) => c.copyWith(maxHistory: v)),
          ),

          const Divider(height: 32),

          // Data
          const _SectionHeader(title: 'Data'),
          _ExportImportTile(),

          const Divider(height: 32),

          // Reset
          Center(
            child: TextButton.icon(
              onPressed: () => _update(ref, (_) => AppConfig.defaults),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Reset to Defaults'),
            ),
          ),
        ],
      ),
    );
  }

  void _update(WidgetRef ref, AppConfig Function(AppConfig) updater) {
    ref.read(configProvider.notifier).update(updater);
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
      if (context.mounted) {
        Toast.show(context, message: 'Export failed: $e', level: ToastLevel.error);
      }
    }
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final pathCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    final result = await showDialog<({String path, String password, ImportMode mode})>(
      context: context,
      builder: (ctx) {
        var mode = ImportMode.merge;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Import Data'),
            content: Column(
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
                  selected: {mode},
                  onSelectionChanged: (s) => setState(() => mode = s.first),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(height: 4),
                Text(
                  mode == ImportMode.merge
                      ? 'Add new sessions, keep existing'
                      : 'Replace all sessions with imported',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
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
                  if (pathCtrl.text.isEmpty || passwordCtrl.text.isEmpty) return;
                  Navigator.pop(ctx, (
                    path: pathCtrl.text,
                    password: passwordCtrl.text,
                    mode: mode,
                  ));
                },
                child: const Text('Import'),
              ),
            ],
          ),
        );
      },
    );

    if (result == null || !context.mounted) return;

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

      // Apply imported sessions
      final sessionNotifier = ref.read(sessionProvider.notifier);
      if (importResult.mode == ImportMode.replace) {
        // Delete all existing, add imported
        final existing = ref.read(sessionProvider);
        for (final s in existing) {
          await sessionNotifier.delete(s.id);
        }
      }
      for (final s in importResult.sessions) {
        try {
          await sessionNotifier.add(s);
        } catch (e) {
          if (importResult.mode == ImportMode.replace) rethrow;
          debugPrint('Import: skipped session ${s.label}: $e');
        }
      }

      // Apply imported config
      if (importResult.config != null) {
        ref.read(configProvider.notifier).update((_) => importResult.config!);
      }

      if (context.mounted) {
        Toast.show(
          context,
          message: 'Imported ${importResult.sessions.length} session(s)',
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Toast.show(context, message: 'Import failed: $e', level: ToastLevel.error);
      }
    }
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
