import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show protected, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../src/rust/api/config.dart' as rust_config;
import '../utils/logger.dart';

const _configFileName = 'config.json';

/// Pre-load seam: `main()` reads the config from disk before `runApp`
/// (so the very first frame avoids the light-theme flash) and stuffs
/// the result here as an override. The notifier's `build()` reads this
/// instead of returning [AppConfig.defaults] when present.
///
/// Tests leave it null so each fresh container starts at defaults.
final preloadedAppConfigProvider = Provider<AppConfig?>((_) => null);

/// Result of [loadAppConfigFromDisk] — carries the parsed config plus
/// a flag the SecurityInitController inspects to decide whether to
/// run first-launch wizards.
class LoadedAppConfig {
  const LoadedAppConfig({required this.config, required this.loadedFromFile});

  final AppConfig config;
  final bool loadedFromFile;
}

/// Thrown by [loadAppConfigFromDisk] when `config.json` exists but
/// cannot be parsed (truncated JSON, FRB sanitiser threw, schema
/// drift the runner couldn't repair, …). Distinct from the
/// missing-file branch — a missing file means "fresh install, use
/// defaults"; a parse error means "the user has on-disk data we
/// cannot interpret, do NOT silently fall back to defaults and
/// then save those defaults over the unparseable file".
///
/// The previous behaviour caught every parse failure, returned
/// `AppConfig.defaults`, then let `ConfigNotifier` save those
/// defaults on the first probe-cache write — which OVERWROTE the
/// user's real `config.json` (specifically `security_tier` would
/// drop, sending the next launch into the legacy-state path with
/// a "Reset all" dialog the user couldn't see because it sat
/// under the splash). [main] now catches this and routes to
/// [FatalErrorApp] so the user can decide whether to delete the
/// file (lose preferences, keep data) or quit and recover the
/// file out-of-band.
class AppConfigParseException implements Exception {
  AppConfigParseException(this.path, this.cause);

  final String path;
  final Object cause;

  @override
  String toString() => 'AppConfigParseException($path): $cause';
}

/// Load `config.json` from the app support directory. Returns
/// defaults when the file is absent (fresh install). Throws
/// [AppConfigParseException] when the file exists but cannot be
/// parsed — see the exception's docstring for the rationale.
Future<LoadedAppConfig> loadAppConfigFromDisk() async {
  final dir = await getApplicationSupportDirectory();
  final filePath = p.join(dir.path, _configFileName);
  final file = File(filePath);
  if (!await file.exists()) {
    return const LoadedAppConfig(
      config: AppConfig.defaults,
      loadedFromFile: false,
    );
  }
  try {
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return LoadedAppConfig(
      config: AppConfig.fromJson(json),
      loadedFromFile: true,
    );
  } catch (e) {
    AppLogger.instance.log(
      'Failed to parse config.json — refusing silent fallback to '
      'defaults so the existing file is not overwritten on next save: $e',
      name: 'ConfigStore',
    );
    throw AppConfigParseException(filePath, e);
  }
}

/// Wire the Rust `lfs_core::config_store::Store` actor against
/// the app-support directory so subsequent save() calls land on
/// disk through the Rust atomic-write + bus-event path.
///
/// Called once from `_initRustCoreOrFatal()` in `main.dart` right
/// after `RustLib.init()` + `appInit()` succeed and before
/// `loadAppConfigFromDisk` parses the on-disk file (which routes
/// through `rust_config.configAppConfigSanitizeJson`).
/// `_saveAppConfigToDisk` re-invokes `configStoreInit` defensively
/// — the Rust-side actor is idempotent under repeated init with
/// the same directory.
Future<void> bootstrapRustConfigStore() async {
  final dir = await getApplicationSupportDirectory();
  rust_config.configStoreInit(supportDir: dir.path);
}

Future<void> _saveAppConfigToDisk(AppConfig config) async {
  final dir = await getApplicationSupportDirectory();
  rust_config.configStoreInit(supportDir: dir.path);
  // `config.toJson()` already routes through the Rust canonicaliser
  // (`config_app_config_to_json`), which stamps `config_schema_version`
  // from `SchemaVersions::CONFIG` on the way out. Persisting goes
  // through `lfs_core::config_store::Store` — the actor owns the
  // in-memory snapshot, 300 ms debounce, atomic write through
  // `write_bytes_atomic`, and the bus event publication. The
  // `flush()` after `set_json` forces the pending state to disk on
  // an explicit save semantic ("save now") rather than letting the
  // actor's own debounce window absorb it.
  rust_config.configStoreSetJson(newJson: jsonEncode(config.toJson()));
  rust_config.configStoreFlush();
}

/// App config state — initial value comes from
/// [preloadedAppConfigProvider] when set (production cold-start path)
/// or [AppConfig.defaults] (tests). Mutations debounce a trailing disk
/// write through the Notifier's `update` API.
///
/// Replaces the prior two-tier `Provider<ConfigStore>` +
/// `NotifierProvider<ConfigNotifier>` split; persistence lives one
/// place.
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
    final seed = ref.watch(preloadedAppConfigProvider);
    ref.onDispose(() {
      _debounceTimer?.cancel();
      // Flush any pending write so a transient teardown (e.g.
      // hot-reload, test container.dispose) does not lose the user's
      // last change.
      if (_pendingConfig != null) {
        _flushPending();
      }
    });
    return seed ?? AppConfig.defaults;
  }

  /// Force a re-read from disk + push into state. Used after `main()`
  /// already pre-loaded (no-op except for late-binding tests) and by
  /// the SecurityInitController reset cascade after wipe (where the
  /// config file is gone and `loadAppConfigFromDisk` returns the
  /// missing-file branch with `AppConfig.defaults`).
  ///
  /// On [AppConfigParseException] (existing-but-corrupt file) the
  /// catch keeps the prior state — the throw is structurally only
  /// reachable here on a mid-session corruption (the cold-start
  /// path catches the same exception in `main` and routes to the
  /// fatal screen). Logging + leaving state untouched is the
  /// safest fallback for the runtime case: a follow-up `update`
  /// will save the prior in-memory state, not silently overwrite
  /// the on-disk file with defaults.
  Future<void> load() async {
    try {
      final loaded = await loadAppConfigFromDisk();
      state = loaded.config;
      await AppLogger.instance.setThreshold(state.logLevel);
    } catch (e) {
      AppLogger.instance.log(
        'config reload failed mid-session, keeping previous state: $e',
        name: 'ConfigProvider',
        error: e,
      );
    }
  }

  /// Apply [updater], publish the new state, and schedule a debounced
  /// save.
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
    // start init synchronously. Callers of update() should not pay for
    // the I/O of opening a sink file.
    unawaited(AppLogger.instance.setThreshold(updated.logLevel));
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
          .then((_) => persist(updated));
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

  /// Disk-write seam: subclasses (test spies that count `save` calls)
  /// override this to wrap or replace the persistence step. Production
  /// delegates to the top-level [_saveAppConfigToDisk] which goes
  /// through the Rust `config_store::Store` actor (atomic write +
  /// 300 ms debounce + bus event) — no Dart-side write fallback,
  /// the actor is the only writer.
  @visibleForTesting
  @protected
  Future<void> persist(AppConfig config) => _saveAppConfigToDisk(config);
}
