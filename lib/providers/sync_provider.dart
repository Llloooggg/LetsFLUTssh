import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/sync.dart' as rust_sync;
import '../utils/logger.dart';

/// Snapshot of the persisted sync state. Field-for-field mirror of
/// `lfs_core::sync::SyncStatus`. The Riverpod notifier rebuilds this
/// after every push / pull so the Settings → Sync section reflects
/// the actual on-disk state — never a stale Dart-side cache.
class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.enabled,
    required this.lastPushedAtMs,
    required this.lastPulledAtMs,
    this.lastError,
  });

  factory SyncStatusSnapshot.fromRust(rust_sync.DbSyncStatus s) =>
      SyncStatusSnapshot(
        enabled: s.enabled,
        lastPushedAtMs: s.lastPushedAtMs,
        lastPulledAtMs: s.lastPulledAtMs,
        lastError: s.lastError,
      );

  factory SyncStatusSnapshot.disabled() => const SyncStatusSnapshot(
    enabled: false,
    lastPushedAtMs: 0,
    lastPulledAtMs: 0,
  );

  final bool enabled;
  final int lastPushedAtMs;
  final int lastPulledAtMs;
  final String? lastError;

  SyncStatusSnapshot copyWith({String? lastError}) => SyncStatusSnapshot(
    enabled: enabled,
    lastPushedAtMs: lastPushedAtMs,
    lastPulledAtMs: lastPulledAtMs,
    lastError: lastError,
  );
}

/// Riverpod notifier for the Settings → Sync section. Reads the
/// canonical state from the Rust-side sync orchestrator on `build()`
/// and after every push / pull. Mutations always go through the
/// FRB layer; this class holds no persistent state of its own — it
/// is purely a re-fetcher so the widget tree refreshes without a
/// global key.
class SyncStatusNotifier extends Notifier<SyncStatusSnapshot> {
  @override
  SyncStatusSnapshot build() {
    try {
      final raw = rust_sync.syncStatus();
      return SyncStatusSnapshot.fromRust(raw);
    } catch (e) {
      // FRB not yet bootstrapped (cold-start window). Settings panel
      // renders the disabled shape until the listener fires.
      AppLogger.instance.log(
        'sync_status read failed before FRB init',
        name: 'Sync',
        error: e,
        level: LogLevel.warn,
      );
      return SyncStatusSnapshot.disabled();
    }
  }

  /// Force a fresh `sync_status` read off the Rust orchestrator —
  /// used by the Settings panel after a "Push now" / "Pull now"
  /// button completes so the displayed timestamps reflect the new
  /// `last_pushed_at_ms` / `last_pulled_at_ms` values immediately.
  void refresh() {
    try {
      state = SyncStatusSnapshot.fromRust(rust_sync.syncStatus());
    } catch (e) {
      AppLogger.instance.log(
        'sync_status refresh failed',
        name: 'Sync',
        error: e,
        level: LogLevel.warn,
      );
    }
  }

  /// Run the orchestrator's push verb. Returns the typed result on
  /// success; throws the original FRB error envelope on failure so
  /// the caller can route through `localizeError`.
  Future<rust_sync.DbSyncResult> push() async {
    final result = await rust_sync.syncPush();
    refresh();
    return result;
  }

  /// Run the orchestrator's pull verb. Same contract as [push].
  Future<rust_sync.DbSyncResult> pull() async {
    final result = await rust_sync.syncPull();
    refresh();
    return result;
  }
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatusSnapshot>(
      SyncStatusNotifier.new,
    );
