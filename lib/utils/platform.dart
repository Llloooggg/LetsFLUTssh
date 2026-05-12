import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../src/rust/api/host_info.dart' as rust_host;

/// Returns the user's home directory path.
///
/// Resolution lives in `lfs_core::host_info::home_directory`. The
/// Rust side reads `EXTERNAL_STORAGE` (Android), then `HOME`,
/// then `USERPROFILE` (Windows). Same rules the Dart code used
/// to inline; centralising in Rust keeps the answer consistent
/// for any future `lfs_cli` / `lfs_tauri` consumer.
///
/// Cached after first read since the env never changes for the
/// life of the process.
String get homeDirectory => _homeCached ??= rust_host.hostInfoHomeDirectory();
String? _homeCached;

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

/// Drop the FRB-cached results so the next read re-queries the
/// native lib. Used by the test harness when toggling FRB load
/// state mid-suite; callers in production never need this.
@visibleForTesting
void debugResetPlatformCache() {
  _homeCached = null;
  _isMobileCached = null;
  _isDesktopCached = null;
  _isMacosCached = null;
  _isAppleCached = null;
}

/// True on Android or iOS.
///
/// Routes through `lfs_core::host_info::is_mobile`. Cached after
/// first read. Falls back to `dart:io` `Platform.isXyz` when FRB
/// is not initialised — both forms compile down to the same
/// constant for a given binary target, so the fallback never
/// disagrees with Rust; it just lets widget tests that haven't
/// bootstrapped FRB still execute.
bool get isMobilePlatform =>
    debugMobilePlatformOverride ??
    (_isMobileCached ??= _readBool(
      rust_host.hostInfoIsMobile,
      () => Platform.isAndroid || Platform.isIOS,
    ));
bool? _isMobileCached;

/// True on Linux, macOS, or Windows. See [isMobilePlatform] for
/// caching + fallback rationale.
bool get isDesktopPlatform =>
    debugDesktopPlatformOverride ??
    (_isDesktopCached ??= _readBool(
      rust_host.hostInfoIsDesktop,
      () => Platform.isLinux || Platform.isMacOS || Platform.isWindows,
    ));
bool? _isDesktopCached;

/// True on macOS. See [isMobilePlatform] for caching + fallback rationale.
bool get isMacosPlatform =>
    debugIsMacosOverride ??
    (_isMacosCached ??= _readBool(
      rust_host.hostInfoIsMacos,
      () => Platform.isMacOS,
    ));
bool? _isMacosCached;

/// True on macOS or iOS — the Apple-target umbrella. Drives the
/// Apple Secure Enclave SSH-key toolbar action's visibility (the
/// underlying `lfs_os_security::apple_se_ssh` driver compiles only
/// on `target_os = "macos"` or `target_os = "ios"`; the toolbar
/// action stays hidden on Linux / Windows / Android per the
/// capability ladder's rung-4 "honestly hide" rule).
///
/// Cached after the first read; falls back to `dart:io` when FRB
/// hasn't bootstrapped yet, same shape as the sibling helpers.
bool get isApplePlatform =>
    debugIsAppleOverride ??
    (_isAppleCached ??= Platform.isMacOS || Platform.isIOS);
bool? _isAppleCached;

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
