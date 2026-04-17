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

  @override
  AppConfig build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
      // If we are torn down with a pending write still queued, fire it
      // synchronously so a transient teardown does not lose the user's
      // last change. Errors propagate to the awaiter via the completer.
      if (_pendingConfig != null) {
        _flushPending();
      }
    });
    return ref.watch(configStoreProvider).config;
  }

  ConfigStore get _store => ref.read(configStoreProvider);

  Future<void> load() async {
    try {
      state = await _store.load();
      AppLogger.instance.setEnabled(state.enableLogging);
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
    AppLogger.instance.setEnabled(updated.enableLogging);
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
