import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/session_credential_cache.dart';

/// Per-session credential cache over the process-global
/// `lfs_core::secrets::SecretStore`.
///
/// Secret RAM is zeroed at explicit security boundaries, never as a
/// side effect of container teardown: per-session [evict] on
/// disconnect (`ConnectionsNotifier`), and [evictAll] on lock
/// (auto-lock action), background (lifecycle → lock), wipe-all, and
/// forgot-password / reset (`security_init_controller`). Disposal
/// does NOT call [evictAll]: the `SecretStore` is process-global, so a
/// container-scoped dispose firing a global clear is the wrong layer —
/// it is unreliable in production (skipped when the process is killed,
/// and the lifecycle-background lock already cleared) and, with the
/// parallel test runner sharing one Rust process, it wiped secrets out
/// from under concurrently-running tests.
///
/// Consumed by:
///   * `ConnectionsNotifier` — populate on successful auth, evict on
///     explicit disconnect.
///   * `Connection._reconnect*` — read as an override before falling
///     back to `Session.auth`.
///   * `WipeAllService` — `evictAll` at the start of `wipeAll()` so a
///     reset never leaves stale credentials for now-gone sessions.
final sessionCredentialCacheProvider = Provider<SessionCredentialCache>((ref) {
  return SessionCredentialCache();
});
