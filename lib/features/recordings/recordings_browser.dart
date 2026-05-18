import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/security/active_dbkey.dart';
import '../../core/session/session.dart';
import '../../core/session/session_recorder.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/session_provider.dart';
import '../../src/rust/api/app.dart' as rust_secrets;
import '../../src/rust/api/format.dart' as rust_format;
import '../../src/rust/api/recorder.dart' as rust_recorder;
import '../../theme/app_theme.dart';
import '../../utils/logger.dart';
import '../../widgets/app_data_row.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/confirm_dialog.dart';
import 'recording_playback_dialog.dart';
import 'recording_reader.dart';
import 'recordings_logic.dart';

/// Per-recording metadata aggregated for the list view. The
/// `sessionId` + `fileName` pair is the stable identity the Rust
/// browser surface accepts on delete + open — Dart never holds a
/// `dart:io` `File` for recordings any more (the disk walk lives
/// in `lfs_core::recorder::browser`).
class _RecordingEntry {
  final String sessionId;
  final String fileName;
  final DateTime fileTimestamp;
  final int sizeBytes;
  final bool encrypted;
  final RecordingMeta? meta;

  _RecordingEntry({
    required this.sessionId,
    required this.fileName,
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

  /// Resolve `<appSupport>/recordings` through the canonical Rust
  /// getter. The Rust browser walks from this root; a missing
  /// directory returns an empty list, so the fresh-install case
  /// lands here without a sentinel branch. Sync FRB hop — the path
  /// resolution lives entirely on the singleton pinned by
  /// `configStoreInit` at startup.
  String _recordingsRoot() => rust_recorder.recorderRecordingsRoot();

  Future<void> _scan() async {
    final root = _recordingsRoot();
    // Migrate any `.lfsr`-named plaintext recording written by
    // a build where the Dart side picked the extension off
    // `secretsHas(ACTIVE_DBKEY_SECRET_ID)` (true on the plaintext
    // tier because the slot carries empty bytes there). The Rust
    // helper renames every `.lfsr` whose first bytes are not the
    // encrypted magic to `.cast` so the dispatcher routes them
    // through the plaintext reader on the next list pass.
    // Idempotent — a no-op once the sweep has run on this device.
    try {
      final renamed = await SessionRecorder.migrateMisnamedRecordings();
      if (renamed > 0) {
        AppLogger.instance.log(
          'Migrated $renamed misnamed recordings to .cast',
          name: 'Recording',
        );
      }
    } catch (_) {
      // The migration is best-effort; the list scan still runs.
    }
    final list = <_RecordingEntry>[];
    try {
      final entries = await rust_recorder.recorderListRecordings(
        recordingsRoot: root,
      );
      for (final e in entries) {
        // Header read is best-effort — corrupt or wrong-key files
        // still appear in the list with size + timestamp so the
        // user can delete them. Encrypted recordings derive the
        // playback key Rust-side from the active DB-key slot via
        // the playback stream; the DB key never lands on the Dart
        // heap on this path.
        final filePath = p.join(root, e.sessionId, e.fileName);
        final meta = await RecordingReader.readMeta(
          filePath,
          encrypted: e.encrypted,
        );
        list.add(
          _RecordingEntry(
            sessionId: e.sessionId,
            fileName: e.fileName,
            fileTimestamp: DateTime.fromMillisecondsSinceEpoch(
              e.mtimeUnixSecs * 1000,
            ),
            sizeBytes: e.sizeBytes.toInt(),
            encrypted: e.encrypted,
            meta: meta,
          ),
        );
      }
    } catch (e, st) {
      AppLogger.instance.log(
        'Recordings list failed',
        name: 'Recording',
        error: e,
        stackTrace: st,
        level: LogLevel.warn,
      );
    }
    list.sort((a, b) => b.fileTimestamp.compareTo(a.fileTimestamp));
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  Future<void> _delete(_RecordingEntry entry) async {
    final l10n = S.of(context);
    final label = _resolveSessionLabel(
      entry.sessionId,
      ref.read(sessionProvider),
    );
    final timestamp = entry.fileTimestamp.toLocal().toString().split('.').first;
    final confirmed = await ConfirmDialog.show(
      context,
      title: l10n.deleteRecording,
      content: Text('$label\n$timestamp'),
    );
    if (!confirmed) return;
    final root = _recordingsRoot();
    try {
      await rust_recorder.recorderDeleteRecording(
        recordingsRoot: root,
        sessionId: entry.sessionId,
        fileName: entry.fileName,
      );
    } catch (e) {
      // Best-effort — already gone or permissions changed; refresh
      // anyway so a stale row clears.
      AppLogger.instance.log(
        'Recording delete failed',
        name: 'Recording',
        error: e,
        level: LogLevel.warn,
      );
    }
    await _scan();
  }

  Future<void> _play(_RecordingEntry entry) async {
    if (entry.encrypted && !rust_secrets.secretsHas(id: kActiveDbKeySecretId)) {
      // Encrypted recording but the running tier has no active DB
      // key (plaintext tier or auto-locked) — playback can't decrypt.
      // The user would need to unlock first.
      return;
    }
    final root = _recordingsRoot();
    final filePath = p.join(root, entry.sessionId, entry.fileName);
    if (!mounted) return;
    await RecordingPlaybackDialog.show(
      context,
      filePath: filePath,
      encrypted: entry.encrypted,
      meta: entry.meta,
    );
  }

  String _resolveSessionLabel(String sessionId, List<Session> sessions) =>
      resolveRecordingSessionLabel(sessionId, sessions);

  /// Format byte size with IEC prefixes (B / KiB / MiB / GiB) via
  /// `lfs_core::format::format_size_iec`.
  String _formatSize(int bytes) => rust_format.formatSizeIec(bytes: bytes);

  /// Format the recording duration shape (fractional sub-minute,
  /// padded sub-hour, padded above-hour) via
  /// `lfs_core::format::format_duration_seconds_fractional`.
  String _formatDuration(double seconds) =>
      rust_format.formatDurationSecondsFractional(seconds: seconds);

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
        // Encrypted recordings are unplayable when the running
        // tier has no active DB key (plaintext / auto-locked).
        // Disable the row + show a tooltip so the user sees WHY
        // playback won't fire instead of a silent no-op on tap.
        final canPlay =
            !e.encrypted || rust_secrets.secretsHas(id: kActiveDbKeySecretId);
        final secondary = [
          e.fileTimestamp.toLocal().toString().split('.').first,
          duration,
          _formatSize(e.sizeBytes),
          if (e.encrypted) 'encrypted',
          if (!canPlay) l10n.recordingPlayLocked,
        ].join('  •  ');
        return AppDataRow(
          icon: e.encrypted ? Icons.lock_outline : Icons.play_circle_outline,
          iconColor: e.encrypted ? AppTheme.accent : AppTheme.fgDim,
          title: label,
          secondary: secondary,
          // Whole row is the play target — the dedicated play icon
          // was redundant noise (row-tap + icon-tap both routed to
          // `_play`). Trailing slot stays for actions that aren't
          // the row's primary intent (delete).
          onTap: canPlay ? () => _play(e) : null,
          trailing: [
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
