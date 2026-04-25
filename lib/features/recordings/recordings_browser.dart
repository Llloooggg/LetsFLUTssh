import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/session/session.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/security_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_data_row.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_icon_button.dart';
import 'recording_playback_dialog.dart';
import 'recording_reader.dart';

/// Per-recording metadata aggregated for the list view.
class _RecordingEntry {
  final File file;
  final String sessionId;
  final DateTime fileTimestamp;
  final int sizeBytes;
  final bool encrypted;
  final RecordingMeta? meta;

  _RecordingEntry({
    required this.file,
    required this.sessionId,
    required this.fileTimestamp,
    required this.sizeBytes,
    required this.encrypted,
    required this.meta,
  });
}

/// List + delete + play recordings written by [SessionRecorder].
///
/// Mounted inside the Tools dialog (desktop) alongside SSH Keys /
/// Snippets / Tags / Known Hosts. Mirror of `SnippetManagerPanel`
/// in shape — toolbar + body — so the Tools sidebar treats it as
/// just another panel.
///
/// **Why Tools and not Settings → Data.** Settings → Data is for
/// destructive lifecycle operations (export / import / reset).
/// Browsing recordings is a routine "look at my recorded sessions"
/// flow, the same shape as browsing snippets or known hosts; it
/// belongs with the rest of the manager surfaces.
class RecordingsPanel extends ConsumerStatefulWidget {
  const RecordingsPanel({super.key});

  @override
  ConsumerState<RecordingsPanel> createState() => _RecordingsPanelState();
}

class _RecordingsPanelState extends ConsumerState<RecordingsPanel> {
  bool _loading = true;
  List<_RecordingEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final dbKey = ref.read(securityStateProvider).encryptionKey;
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'recordings'));
    final list = <_RecordingEntry>[];
    if (await root.exists()) {
      await for (final sessionDir in root.list()) {
        if (sessionDir is! Directory) continue;
        final sessionId = p.basename(sessionDir.path);
        await for (final f in sessionDir.list()) {
          if (f is! File) continue;
          final ext = p.extension(f.path).toLowerCase();
          if (ext != '.cast' && ext != '.lfsr') continue;
          final encrypted = ext == '.lfsr';
          final stat = await f.stat();
          // Header read is best-effort — corrupt or wrong-key files
          // still appear in the list with size + timestamp so the
          // user can delete them.
          final meta = await RecordingReader.readMeta(
            f,
            encrypted: encrypted,
            dbKey: dbKey,
          );
          list.add(
            _RecordingEntry(
              file: f,
              sessionId: sessionId,
              fileTimestamp: stat.modified,
              sizeBytes: stat.size,
              encrypted: encrypted,
              meta: meta,
            ),
          );
        }
      }
    }
    list.sort((a, b) => b.fileTimestamp.compareTo(a.fileTimestamp));
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  Future<void> _delete(_RecordingEntry entry) async {
    try {
      await entry.file.delete();
    } catch (_) {
      // Best-effort — already gone or permissions changed; refresh
      // anyway so a stale row clears.
    }
    await _scan();
  }

  Future<void> _play(_RecordingEntry entry) async {
    final dbKey = ref.read(securityStateProvider).encryptionKey;
    if (entry.encrypted && dbKey == null) {
      // Encrypted recording but the running tier is plaintext —
      // we don't have the key. The user would need to unlock first.
      return;
    }
    await RecordingPlaybackDialog.show(
      context,
      file: entry.file,
      encrypted: entry.encrypted,
      dbKey: dbKey,
      meta: entry.meta,
    );
  }

  String _resolveSessionLabel(String sessionId, List<Session> sessions) {
    for (final s in sessions) {
      if (s.id == sessionId) {
        return s.label.isNotEmpty ? s.label : s.displayName;
      }
    }
    // Session deleted — show the id (truncated) so the user can
    // still find / delete the orphaned recording.
    return '<deleted> ${sessionId.substring(0, 8)}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }

  String _formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final m = (seconds / 60).floor();
    final s = (seconds - m * 60).floor();
    if (m < 60) return '${m}m ${s.toString().padLeft(2, '0')}s';
    final h = (m / 60).floor();
    return '${h}h ${(m - h * 60).toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final sessions = ref.watch(sessionProvider);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_entries.isEmpty) {
      return AppEmptyState(message: l10n.recordingsEmpty);
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final e = _entries[i];
        final label = _resolveSessionLabel(e.sessionId, sessions);
        final duration = e.meta != null
            ? _formatDuration(e.meta!.durationSeconds)
            : '?';
        final secondary = [
          e.fileTimestamp.toLocal().toString().split('.').first,
          duration,
          _formatSize(e.sizeBytes),
          if (e.encrypted) 'encrypted',
        ].join('  •  ');
        return AppDataRow(
          icon: e.encrypted ? Icons.lock_outline : Icons.play_circle_outline,
          iconColor: e.encrypted ? AppTheme.accent : AppTheme.fgDim,
          title: label,
          secondary: secondary,
          onTap: () => _play(e),
          trailing: [
            AppIconButton(
              icon: Icons.play_arrow,
              tooltip: l10n.playRecording,
              onTap: () => _play(e),
            ),
            AppIconButton(
              icon: Icons.delete_outline,
              tooltip: l10n.deleteRecording,
              color: AppTheme.red,
              onTap: () => _delete(e),
            ),
          ],
        );
      },
    );
  }
}

/// Mobile entry — wraps [RecordingsPanel] in an [AppDialog] so the
/// shape matches the rest of the manager dialogs (SSH Keys / Snippets
/// / Tags). Desktop mounts the panel directly inside the Tools
/// dialog's sidebar layout.
class RecordingsBrowserDialog extends StatelessWidget {
  const RecordingsBrowserDialog({super.key});

  static Future<void> show(BuildContext context) {
    return AppDialog.show<void>(
      context,
      builder: (_) => const RecordingsBrowserDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return AppDialog(
      title: l10n.recordingsBrowserTitle,
      maxWidth: 640,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: const SizedBox(height: 480, child: RecordingsPanel()),
      actions: [AppButton.cancel(onTap: () => Navigator.pop(context))],
    );
  }
}
