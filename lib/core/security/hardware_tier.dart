import 'dart:io' show Platform;

import 'package:meta/meta.dart' show visibleForTesting;

/// Hardware-backed SSH-key backends the key manager can mint or
/// import from. One variant per native driver exposed by
/// `lfs_os_security`, not per security tier — these are the
/// concrete backends the user picks in the key-manager toolbar, not
/// the bank-style `SecurityTier` applied to the app DB.
///
/// The variant set deliberately mirrors the `backend` discriminator
/// column on `ssh_keys` (`enclave`, `hello`, `tpm`, `keystore`).
/// FIDO2 (`sk-*`) and PKCS#11 are intentionally **not** here — both
/// route through runtime FRB availability probes
/// (`fido2_is_available`, `pkcs11_is_available`) rather than an
/// OS-static capability table, since dev-build / driver-present
/// state matters as much as the target triple. This enum encodes
/// only the OS-static decision (`target_os = "macos"` etc.).
enum HardwareTier {
  /// Apple Secure Enclave — `lfs_os_security::apple_se_ssh`. macOS +
  /// iOS only (the underlying `SecKeyCreateRandomKey` chip exists on
  /// every modern Apple device, but the driver compiles only against
  /// the Apple target triples).
  appleEnclave,

  /// Windows Hello / NCrypt PCP — `lfs_os_security::windows::ncrypt_ssh`.
  /// Windows only.
  windowsHello,

  /// TPM 2.0 — `lfs_os_security::tpm_ssh`. Linux (tss-esapi driver) +
  /// Windows (PCP silent variant). Apple targets route to the Secure
  /// Enclave instead.
  tpm,

  /// Android Hardware Keystore / StrongBox —
  /// `lfs_os_security::android::keystore_ssh`. Android only.
  androidKeystore,
}

/// Override for testing — when non-null,
/// [supportedHardwareTiersForPlatform] returns this list verbatim so
/// the wizard tests can simulate "this is macOS" without booting a
/// real macOS host.
@visibleForTesting
List<HardwareTier>? debugHardwareTiersOverride;

/// Hardware tiers the current OS can mint or import. Single source
/// of truth for "which key-manager toolbar entries should appear" —
/// every wizard caller routes through this list instead of branching
/// on `Platform.isXyz` inline. Order is the order the toolbar renders
/// the entries; downstream callers must not re-sort.
///
/// The list intentionally encodes the **OS-static** capability —
/// whether the underlying driver is compiled in. Runtime probes
/// (Secure Enclave entitlement on macOS dev builds, Windows Hello
/// configuration, TPM presence) still gate the actual generate path
/// inside the wizard; this list only decides whether the toolbar
/// entry is rendered at all.
List<HardwareTier> supportedHardwareTiersForPlatform() {
  final override = debugHardwareTiersOverride;
  if (override != null) return override;
  if (Platform.isMacOS) {
    return const [HardwareTier.appleEnclave];
  }
  if (Platform.isIOS) {
    return const [HardwareTier.appleEnclave];
  }
  if (Platform.isWindows) {
    return const [HardwareTier.windowsHello, HardwareTier.tpm];
  }
  if (Platform.isLinux) {
    return const [HardwareTier.tpm];
  }
  if (Platform.isAndroid) {
    return const [HardwareTier.androidKeystore];
  }
  return const [];
}

/// True when [tier] is one of the entries returned by
/// [supportedHardwareTiersForPlatform]. Wizards branch on this when
/// rendering a multi-tier picker — Linux TPM has an extra "Import
/// `.tpm` blob" affordance, Windows TPM does not.
bool isHardwareTierSupported(HardwareTier tier) =>
    supportedHardwareTiersForPlatform().contains(tier);
