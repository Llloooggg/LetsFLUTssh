import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/security_tier.dart';
import '../l10n/app_localizations.dart';

/// Return the likeliest-per-platform reason T2 is out of reach on
/// this host. Shared by the first-launch dialog and the Settings
/// "hardware unavailable" notice so both surfaces say the same
/// thing — a future TPM-probe refinement only needs one edit.
HardwareUnavailableReason defaultHardwareUnavailableReason() {
  if (Platform.isWindows) return HardwareUnavailableReason.noTpm;
  if (Platform.isMacOS || Platform.isIOS) {
    return HardwareUnavailableReason.noSecureEnclave;
  }
  if (Platform.isLinux) return HardwareUnavailableReason.noTpm2Tools;
  if (Platform.isAndroid) {
    return HardwareUnavailableReason.noAndroidKeystoreHardware;
  }
  return HardwareUnavailableReason.generic;
}

/// Resolve the user-facing copy for a [HardwareUnavailableReason].
/// Shared so the first-launch dialog and the Settings "hardware
/// unavailable" notice stay in lockstep — one ARB key pair per
/// reason, no drift between surfaces.
String hardwareUnavailableReasonText(S l10n, HardwareUnavailableReason reason) {
  switch (reason) {
    case HardwareUnavailableReason.noSecureEnclave:
      return l10n.firstLaunchSecurityHardwareUnavailableApple;
    case HardwareUnavailableReason.noTpm:
      return l10n.firstLaunchSecurityHardwareUnavailableWindows;
    case HardwareUnavailableReason.noTpm2Tools:
      return l10n.firstLaunchSecurityHardwareUnavailableLinux;
    case HardwareUnavailableReason.noAndroidKeystoreHardware:
      return l10n.firstLaunchSecurityHardwareUnavailableAndroid;
    case HardwareUnavailableReason.generic:
      return l10n.firstLaunchSecurityHardwareUnavailableGeneric;
  }
}

/// Reason the hardware-backed tier is not reachable on this device.
/// Ordered by the order of the checks in the capability probe —
/// first match wins. Drives the copy shown in the first-launch
/// banner's "hardware unavailable" branch.
enum HardwareUnavailableReason {
  /// macOS / iOS Secure Enclave not present (pre-T2 Intel Mac,
  /// older iOS device without SE). Rare on current hardware.
  noSecureEnclave,

  /// Windows without TPM 2.0, or TPM present but disabled in BIOS.
  noTpm,

  /// Linux without `tpm2-tools` installed. The kernel-visible TPM
  /// may be present; without the userland tool the app cannot talk
  /// to it, so the effective answer is "unavailable".
  noTpm2Tools,

  /// Android StrongBox / TEE probe came back false — most likely a
  /// very old device (API 24 era) or a custom ROM that strips
  /// Keystore.
  noAndroidKeystoreHardware,

  /// Fallback when the probe could not classify a specific reason.
  /// Surfaced as a generic "not available on this device" string.
  generic,
}

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

  /// Set when [hardwareUpgradeAvailable] is false — surfaces a
  /// short per-platform "why" line so the user understands the
  /// upgrade is not hidden, it genuinely is not supported here.
  final HardwareUnavailableReason? hardwareUnavailableReason;

  const FirstLaunchBannerData({
    required this.activeTier,
    required this.hardwareUpgradeAvailable,
    this.hardwareUnavailableReason,
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
