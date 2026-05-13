import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../src/rust/api/host_info.dart' as rust_host;

/// Returns the user's home directory path.
///
/// Resolution lives in `lfs_core::host_info::home_directory`. The
/// Rust side reads `EXTERNAL_STORAGE` (Android), then `HOME`,
/// then `USERPROFILE` (Windows). The Rust call is a sync FRB
/// getter against an `OnceLock`-pinned value, so repeat calls are
/// nanoseconds — no Dart-side cache needed.
///
/// Falls back to the env vars directly on `StateError` (FRB not
/// yet initialised in widget-test contexts).
String get homeDirectory {
  try {
    return rust_host.hostInfoHomeDirectory();
  } on StateError {
    if (Platform.isAndroid) {
      final ext = Platform.environment['EXTERNAL_STORAGE'];
      if (ext != null && ext.isNotEmpty) return ext;
    }
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
  }
}

/// Override for testing — when non-null, [isMobilePlatform] returns this value.
@visibleForTesting
bool? debugMobilePlatformOverride;

/// Override for testing — when non-null, [isDesktopPlatform] returns this value.
@visibleForTesting
bool? debugDesktopPlatformOverride;

/// Override for testing — when non-null, [isMacosPlatform] returns this value.
/// Used by macOS-only UI paths (first-launch self-sign pre-prompt, Settings
/// Enable/Remove identity block) that would otherwise skip the branch on a
/// Linux / CI host and leave the code uncovered.
@visibleForTesting
bool? debugIsMacosOverride;

/// Override for testing — when non-null, [isApplePlatform] returns this
/// value. Drives the Apple Secure Enclave key-manager toolbar action
/// (macOS + iOS) that would otherwise skip the branch on a Linux CI host.
@visibleForTesting
bool? debugIsAppleOverride;

/// Override for testing — when non-null, [isWindowsPlatform] returns this
/// value. Drives the Windows Hello (NCrypt) key-manager toolbar action
/// that would otherwise skip the branch on a Linux CI host.
@visibleForTesting
bool? debugIsWindowsOverride;

/// True on Android or iOS.
///
/// Routes through `lfs_core::host_info::is_mobile` (sync FRB
/// getter against a compile-time constant). Falls back to
/// `dart:io` `Platform.isXyz` when FRB is not initialised — both
/// forms compile down to the same constant for a given binary
/// target, so the fallback never disagrees with Rust; it just
/// lets widget tests that haven't bootstrapped FRB still execute.
bool get isMobilePlatform =>
    debugMobilePlatformOverride ??
    _readBool(
      rust_host.hostInfoIsMobile,
      () => Platform.isAndroid || Platform.isIOS,
    );

/// True on Linux, macOS, or Windows. See [isMobilePlatform] for
/// fallback rationale.
bool get isDesktopPlatform =>
    debugDesktopPlatformOverride ??
    _readBool(
      rust_host.hostInfoIsDesktop,
      () => Platform.isLinux || Platform.isMacOS || Platform.isWindows,
    );

/// True on macOS. See [isMobilePlatform] for fallback rationale.
bool get isMacosPlatform =>
    debugIsMacosOverride ??
    _readBool(rust_host.hostInfoIsMacos, () => Platform.isMacOS);

/// True on macOS or iOS — the Apple-target umbrella. Drives the
/// Apple Secure Enclave SSH-key toolbar action's visibility (the
/// underlying `lfs_os_security::apple_se_ssh` driver compiles only
/// on `target_os = "macos"` or `target_os = "ios"`; the toolbar
/// action stays hidden on Linux / Windows / Android per the
/// capability ladder's rung-4 "honestly hide" rule).
bool get isApplePlatform =>
    debugIsAppleOverride ?? (Platform.isMacOS || Platform.isIOS);

/// True on Windows. Drives the Windows Hello (NCrypt) key-manager
/// toolbar action's visibility (the underlying
/// `lfs_os_security::windows::ncrypt_ssh` driver compiles only on
/// `target_os = "windows"`; the toolbar action stays hidden on every
/// other platform per the capability ladder's rung-4 "honestly hide"
/// rule).
bool get isWindowsPlatform => debugIsWindowsOverride ?? Platform.isWindows;

/// Try the FRB call; on `StateError` (RustLib not initialised in
/// flutter_test contexts) fall back to the Dart `Platform.isXyz`
/// path. The two answers are mathematically identical for any
/// given binary target — both are compile-time constants — so
/// the fallback never produces a different result, it just
/// removes the FRB-bootstrap requirement for widget tests.
bool _readBool(bool Function() rust, bool Function() dartFallback) {
  try {
    return rust();
  } on StateError {
    return dartFallback();
  }
}
