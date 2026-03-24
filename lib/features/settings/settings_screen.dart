import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../providers/config_provider.dart';

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
