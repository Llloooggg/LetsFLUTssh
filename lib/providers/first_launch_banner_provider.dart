import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/security_tier.dart';

/// Data packet that the first-launch auto-setup path hands to the
/// UI so the banner can render accurate per-host copy. `null` means
/// there is no banner to show — the startup either wasn't a first
/// launch or the banner has already been dismissed this session.
class FirstLaunchBannerData {
  /// Tier the auto-setup landed on. Always [SecurityTier.keychain]
  /// today; the shape lets the banner grow a "we fell back to
  /// plaintext because the keychain was unreachable" branch later
  /// without a provider rewrite.
  final SecurityTier activeTier;

  /// T2 is reachable on this device but the auto-setup stayed on
  /// T1. The banner uses this to show the upgrade prompt.
  final bool hardwareUpgradeAvailable;

  const FirstLaunchBannerData({
    required this.activeTier,
    required this.hardwareUpgradeAvailable,
  });
}

/// In-memory-only notification that the first-launch auto-setup
/// just finished and the post-setup banner should render. Set by
/// `main._firstLaunchSetup`, consumed by `_MainScreenState` which
/// pops a one-shot dialog and clears the state on dismiss.
///
/// No persistence — the banner belongs to the launch where the
/// auto-setup ran. Every subsequent launch finds an existing DB and
/// never touches this provider.
class FirstLaunchBannerNotifier extends Notifier<FirstLaunchBannerData?> {
  @override
  FirstLaunchBannerData? build() => null;

  /// Replace the current banner state. Passing `null` dismisses the
  /// banner — the dialog calls this from its `whenComplete`.
  void set(FirstLaunchBannerData? value) => state = value;
}

final firstLaunchBannerProvider =
    NotifierProvider<FirstLaunchBannerNotifier, FirstLaunchBannerData?>(
      FirstLaunchBannerNotifier.new,
    );
