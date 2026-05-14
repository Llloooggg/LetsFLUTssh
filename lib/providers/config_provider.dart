import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show protected, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../src/rust/api/config.dart' as rust_config;
import '../utils/logger.dart';

/// Pre-load seam: `main()` snapshots the Rust-side `config_store`
/// actor into this provider as an override before the first frame
/// (so the first paint already carries the user's saved theme /
/// locale / `ui_scale` without a light-theme flash). The notifier's
/// `build()` reads this instead of returning [AppConfig.defaults]
/// when present.
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

/// Thrown by [loadAppConfigFromDisk] when the Rust `config_store`
/// actor could not adopt an on-disk `config.json` (parse failure
/// surfaced by `config_store_init` as an `Err`, or an in-memory
/// snapshot the Dart factory cannot turn into a valid [AppConfig]
/// — Rust + Dart canonical encoders disagreeing is itself a bug).
/// Distinct from the missing-file branch — a missing file means
/// "fresh install, use defaults"; a parse error means "the user
/// has on-disk data we cannot interpret, do NOT silently fall back
/// to defaults and then save those defaults over the unparseable
/// file".
///
/// Silent fallback would overwrite the user's real `config.json`
/// on the next probe-cache write — specifically `security_tier`
/// would drop, sending the next launch into the legacy-state path
/// with a "Reset all" dialog the user couldn't see because it sat
/// under the splash. [main] catches this and routes to
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

/// Snapshot the Rust `config_store` actor into a [LoadedAppConfig].
///
/// Preconditions: [bootstrapRustConfigStore] (which calls
/// `config_store_init`) must have run earlier in `_mainBody` so the
/// actor already adopted the on-disk file (or seeded defaults). This
/// function only reads the in-memory canonical JSON via
/// `config_store_get_json` plus the `was_loaded_from_disk` flag —
/// no Dart-side `dart:io` File / Directory operations touch the
/// config path at all. `lfs_core::config_store::Store` owns parse +
/// symlink-safe read + atomic write.
///
/// Returns defaults with `loadedFromFile: false` when init seeded
/// defaults (absent or unreadable file — fresh-install or
/// hostile-environment path). Throws [AppConfigParseException]
/// when:
/// * the actor returned `None` from `config_store_get_json` (init
///   never ran — precondition violation, caller bug), or
/// * the returned JSON does not decode into a `Map<String, dynamic>`
///   shape the Dart [AppConfig.fromJson] factory accepts (Rust +
///   Dart canonical encoders drifted — schema bug).
///
/// `config_store_init` itself surfaces an on-disk parse failure as
/// `Err`; that path turns into the same fatal-screen route via the
/// throw inside [bootstrapRustConfigStore].
Future<LoadedAppConfig> loadAppConfigFromDisk() async {
  final loadedFromFile = rust_config.configStoreWasLoadedFromDisk();
  final canonicalJson = rust_config.configStoreGetJson();
  if (canonicalJson == null) {
    // Structural precondition violation: `_mainBody` runs
    // `_initRustCoreOrFatal` (which calls `bootstrapRustConfigStore`)
    // before any caller can reach `loadAppConfigFromDisk`. A null
    // return here means a test (or a future refactor) skipped the
    // bootstrap step — refuse to invent defaults that the next
    // `update` would persist over the unread file.
    AppLogger.instance.log(
      'config_store snapshot was null — bootstrapRustConfigStore '
      'must run before loadAppConfigFromDisk',
      name: 'ConfigStore',
    );
    throw AppConfigParseException(
      _configPathHint(),
      StateError('config_store not initialised'),
    );
  }
  try {
    final json = jsonDecode(canonicalJson) as Map<String, dynamic>;
    return LoadedAppConfig(
      config: AppConfig.fromJson(json),
      loadedFromFile: loadedFromFile,
    );
  } catch (e) {
    AppLogger.instance.log(
      'config_store snapshot did not decode into AppConfig — '
      'refusing silent fallback to defaults so the existing file '
      'is not overwritten on next save: $e',
      name: 'ConfigStore',
    );
    throw AppConfigParseException(_configPathHint(), e);
  }
}

/// Best-effort path hint for [AppConfigParseException]. The Rust
/// actor owns the canonical path; this Dart-side composition is for
/// the fatal-screen message only, where the localised template
/// substitutes the path into "The settings file at … could not be
/// parsed…". Failures here yield the bare filename so the screen
/// still renders.
String _configPathHint() => 'config.json';

/// Wire the Rust `lfs_core::config_store::Store` actor against the
/// app-support directory. The actor loads `<support_dir>/config.json`
/// if present (or seeds defaults), spawns the singleton background
/// debounce ticker, and exposes the canonical JSON through the
/// `config_store_get_json` snapshot.
///
/// Called once from `_initRustCoreOrFatal()` in `main.dart`
/// immediately after `RustLib.init()` + `appInit()` succeed and
/// before [loadAppConfigFromDisk] reads the snapshot. Idempotent
/// per the Rust-side docstring — re-running under the same
/// `support_dir` reloads from disk without writing.
///
/// Surfaces an on-disk parse failure as [AppConfigParseException]
/// so the caller (`_mainBody`) routes the user to the fatal-error
/// screen instead of silently falling back to defaults.
Future<void> bootstrapRustConfigStore() async {
  final dir = await getApplicationSupportDirectory();
  try {
    rust_config.configStoreInit(supportDir: dir.path);
  } catch (e) {
    AppLogger.instance.log(
      'config_store_init refused on-disk file: $e',
      name: 'ConfigStore',
    );
    throw AppConfigParseException('${dir.path}/config.json', e);
  }
}

Future<void> _saveAppConfigToDisk(AppConfig config) async {
  // `config.toJson()` already routes through the Rust canonicaliser
  // (`config_app_config_to_json`), which stamps `config_schema_version`
  // from `SchemaVersions::CONFIG` on the way out. Persisting goes
  // through `lfs_core::config_store::Store` — the actor owns the
  // in-memory snapshot, 300 ms debounce, atomic write through
  // `write_bytes_atomic`, and the bus event publication. The
  // `flush()` after `set_json` forces the pending state to disk on
  // an explicit save semantic ("save now") rather than letting the
  // actor's own debounce window absorb it.
  //
  // `configStoreInit` is idempotent — the Rust singleton's
  // `OnceLock<PathBuf>` adopts the first path and ignores the rest.
  // Production runs `bootstrapRustConfigStore` once at startup so
  // this call is a no-op there; widget tests + unit tests construct
  // a fresh `ConfigNotifier` per case and rely on this defensive
  // init to pin the singleton against the test's temp support dir.
  final dir = await getApplicationSupportDirectory();
  rust_config.configStoreInit(supportDir: dir.path);
  rust_config.configStoreSetJson(newJson: jsonEncode(config.toJson()));
  rust_config.configStoreFlush();
}

/// App config state — initial value comes from
/// [preloadedAppConfigProvider] when set (production cold-start path)
/// or [AppConfig.defaults] (tests). Mutations debounce a trailing disk
/// write through the Notifier's `update` API.
final configProvider = NotifierProvider<ConfigNotifier, AppConfig>(
  ConfigNotifier.new,
);

/// Read-only accessor for the recordings storage cap. Selected off
/// [configProvider] so a widget that only needs the cap (Settings
/// tile, recordings browser footer summary) re-renders solely when
/// the cap changes — not on every unrelated config mutation. The
/// Rust recorder hooks are the source of truth for eviction; this
/// provider is the Dart read path for surfacing the configured
/// value.
final recordingsStorageCapBytesProvider = Provider<int>(
  (ref) => ref.watch(configProvider.select((c) => c.recordingsStorageCapBytes)),
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

  /// Force a re-read from the Rust config-store actor + push into
  /// state. Used after `main()` already pre-loaded (no-op except
  /// for late-binding tests) and by the SecurityInitController
  /// reset cascade after wipe (where the config file is gone and
  /// `loadAppConfigFromDisk` returns the missing-file branch with
  /// `AppConfig.defaults`).
  ///
  /// On [AppConfigParseException] (corrupt-file path turned into a
  /// throw by `config_store_init`) the catch keeps the prior state
  /// — the throw is structurally only reachable here on a
  /// mid-session corruption (the cold-start path catches the same
  /// exception in `main` and routes to the fatal screen). Logging
  /// + leaving state untouched is the safest fallback for the
  /// runtime case: a follow-up `update` will save the prior
  /// in-memory state, not silently overwrite the on-disk file with
  /// defaults.
  Future<void> load() async {
    try {
      // Re-run the bootstrap so a wipe + re-init cycle picks up
      // the now-absent file (`was_loaded_from_disk` flips back to
      // false). `config_store_init` is idempotent under the same
      // dir per its docstring.
      await bootstrapRustConfigStore();
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
