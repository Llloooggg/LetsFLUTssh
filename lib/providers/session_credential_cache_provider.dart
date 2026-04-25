import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/session_credential_cache.dart';

/// Container-scoped per-session credential cache.
///
/// Scoped to the Riverpod container so test harnesses using
/// `ProviderContainer` + dispose get a clean slate, and so the app's
/// container teardown (app shutdown) zeroes every SecretBuffer via
/// [SessionCredentialCache.evictAll].
///
/// Consumed by:
///   * `ConnectionManager` — populate on successful auth, evict on
///     explicit disconnect.
///   * `Connection._reconnect*` — read as an override before falling
///     back to `Session.auth`.
///   * `WipeAllService` — `evictAll` at the start of `wipeAll()` so a
///     reset never leaves stale credentials for now-gone sessions.
final sessionCredentialCacheProvider = Provider<SessionCredentialCache>((ref) {
  final cache = SessionCredentialCache();
  // evictAll is async; wrap in a void closure so onDispose accepts
  // it. Errors are swallowed — provider teardown can't propagate
  // failures and the FRB call is best-effort anyway.
  ref.onDispose(() {
    cache.evictAll().catchError((Object _) {});
  });
  return cache;
});
