import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';

/// Event signal for "re-run the first-launch security setup flow".
///
/// Consumers (currently only `_LetsFLUTsshAppState` in `main.dart`)
/// subscribe via `ref.listenManual` and trigger a re-init whenever
/// the counter advances. Producers (the Settings → Reset All Data
/// flow) call `ref.read(securityReinitProvider.notifier).bump()`
/// after `WipeAllService.wipeAll()` completes so the app re-enters
/// the same tier-provisioning path that fires on a genuine first
/// launch (auto-T1 if keychain reachable, reduced wizard otherwise).
///
/// Why a counter instead of a boolean: Riverpod emits state changes
/// only on value change; a boolean toggled `true → true` by two
/// sequential resets would be coalesced. An integer strictly
/// increments per event, so listeners fire every time. The numeric
/// value has no meaning — only the delta matters.
///
/// Why an event provider rather than lifting `_firstLaunchSetup`
/// into a shared service: the setup helpers in `main.dart` lean on
/// `_LetsFLUTsshAppState` internals (`mounted`, `_activeDatabase`,
/// `navigatorKey.currentContext`). Moving them behind an event
/// preserves the single owner of that state while still giving the
/// Settings reset path a clean hook to request the same re-init.
class SecurityReinitNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Advances the counter by one. Any listener installed via
  /// `ref.listenManual(securityReinitProvider, …)` observes a delta
  /// and re-runs its reinit handler.
  void bump() {
    state = state + 1;
    AppLogger.instance.log(
      'Security reinit requested (tick=$state)',
      name: 'SecurityReinit',
    );
  }
}

final securityReinitProvider = NotifierProvider<SecurityReinitNotifier, int>(
  SecurityReinitNotifier.new,
);

/// Helper used by reset flows: increments the signal, which wakes
/// the `_LetsFLUTsshAppState` listener into a fresh
/// `_firstLaunchSetup` call. Accepts the widget-scoped `WidgetRef`
/// callers have on hand; both `Ref` and `WidgetRef` expose `read`
/// with the same signature, so the helper takes the lowest common
/// denominator.
void requestSecurityReinit(WidgetRef ref) {
  ref.read(securityReinitProvider.notifier).bump();
}
