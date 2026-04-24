import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app is currently auto-locked.
///
/// `true` → the root widget tree swaps to [LockScreen] and blocks all
/// interaction; the DB key is zeroed in memory. `false` → normal UI.
final lockStateProvider = NotifierProvider<LockStateNotifier, bool>(
  LockStateNotifier.new,
);

/// Riverpod notifier backing [lockStateProvider].
///
/// Two transitions, both idempotent:
/// - [lock] — idle-timer fires, auto-lock trigger, or manual Settings
///   toggle. Flips the flag on; the root widget tree reacts by
///   swapping to [LockScreen].
/// - [unlock] — user re-authenticated. Caller has already re-pushed
///   the DB key into `securityStateProvider` before flipping this.
class LockStateNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Enter locked state. Caller is responsible for wiping in-memory
  /// secrets (securityStateProvider.clearEncryption()) before or after.
  void lock() {
    if (!state) state = true;
  }

  /// Leave locked state. Caller has already re-derived the DB key and
  /// pushed it back into securityStateProvider.
  void unlock() {
    if (state) state = false;
  }
}
