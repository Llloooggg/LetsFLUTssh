import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/config/config_store.dart';
import '../utils/logger.dart';

/// Global config store instance.
final configStoreProvider = Provider<ConfigStore>((ref) {
  return ConfigStore();
});

/// App config state — loaded async, then updated in-place.
final configProvider = NotifierProvider<ConfigNotifier, AppConfig>(
  ConfigNotifier.new,
);

class ConfigNotifier extends Notifier<AppConfig> {
  /// Sequential save lock — prevents concurrent file writes.
  Future<void> _pendingSave = Future.value();

  /// Coalesce rapid `update` calls (slider drags, fast typing) into a
  /// single trailing disk write. Memory state mutates synchronously;
  /// only the persistence is debounced. Tested values: 200 ms felt
  /// laggy when toggling switches; 300 ms is imperceptible and still
  /// collapses long slider drags into 1–2 writes.
  static const Duration _saveDebounce = Duration(milliseconds: 300);
  Timer? _debounceTimer;
  AppConfig? _pendingConfig;

  /// Shared completer for the next debounced save. Every `update` call
  /// inside the same debounce window receives this same future, so all
  /// callers are notified together when the save completes (or fails).
  Completer<void>? _pendingSaveCompleter;

  /// Cached store reference. Captured during `build` (when `ref` is
  /// definitely live) so the dispose-time flush does not have to call
  /// `ref.read` after the provider has been torn down — that would raise
  /// UnmountedRefException in tests and during hot-reload.
  ConfigStore? _cachedStore;

  @override
  AppConfig build() {
    final store = ref.watch(configStoreProvider);
    _cachedStore = store;
    ref.onDispose(() {
      _debounceTimer?.cancel();
      // Flush any pending write so a transient teardown (e.g. hot-reload,
      // test container.dispose) does not lose the user's last change.
      // Uses the cached store so we never touch a disposed ref.
      if (_pendingConfig != null) {
        _flushPending();
      }
    });
    return store.config;
  }

  ConfigStore get _store => _cachedStore ?? ref.read(configStoreProvider);

  Future<void> load() async {
    try {
      state = await _store.load();
      await AppLogger.instance.setThreshold(state.logLevel);
    } catch (e) {
      AppLogger.instance.log(
        'Failed to load config, using defaults',
        name: 'ConfigProvider',
        error: e,
      );
    }
  }

  /// Apply [updater], publish the new state, and schedule a debounced save.
  ///
  /// Returns a future that completes when the *eventual* disk write
  /// finishes — multiple updates inside the debounce window share one
  /// future and are notified together. Errors from the save propagate
  /// to every awaiter.
  Future<void> update(AppConfig Function(AppConfig) updater) {
    final updated = updater(state);
    state = updated;
    // Fire-and-forget — threshold change only flips an enum + maybe
    // opens/closes the sink; the awaited load() path handles cold-
    // start init synchronously. Callers of update() should not pay
    // for the I/O of opening a sink file.
    // ignore: unawaited_futures
    AppLogger.instance.setThreshold(updated.logLevel);
    _pendingConfig = updated;
    _pendingSaveCompleter ??= Completer<void>();
    final completer = _pendingSaveCompleter!;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_saveDebounce, _flushPending);
    return completer.future;
  }

  void _flushPending() {
    final pending = _pendingConfig;
    final completer = _pendingSaveCompleter;
    _pendingConfig = null;
    _pendingSaveCompleter = null;
    _debounceTimer = null;
    if (pending == null) {
      completer?.complete();
      return;
    }
    unawaited(_save(pending, completer));
  }

  Future<void> _save(AppConfig updated, Completer<void>? completer) async {
    try {
      _pendingSave = _pendingSave
          .catchError((_) {})
          .then((_) => _store.save(updated));
      await _pendingSave;
      completer?.complete();
    } catch (e) {
      AppLogger.instance.log(
        'Failed to save config',
        name: 'ConfigProvider',
        error: e,
      );
      completer?.completeError(e);
      rethrow;
    }
  }
}
