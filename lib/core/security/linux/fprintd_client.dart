import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../../src/rust/api/fprintd.dart' as rust_fprintd;

/// Function-pointer signatures matching `lfs_core::api::fprintd` so
/// the [FprintdClient] DI seams stay readable in the ctor.
typedef FprintdReachableFn = Future<bool> Function();
typedef FprintdEnrolmentHashFn = Future<Uint8List?> Function();
typedef FprintdHasFingersFn = Future<bool> Function();
typedef FprintdVerifyFn = Future<bool> Function({required int timeoutMs});

/// Thin async wrapper around the `net.reactivated.Fprint` system-bus
/// API exposed by the `fprintd` daemon.
///
/// Lives in `lib/core/security/linux/` to keep the platform gating
/// obvious; the Rust implementation is at
/// `lfs_core::platform::linux::fprintd` (gated on
/// `cfg(target_os = "linux")`). All four verbs route through FRB
/// async calls — Dart owns only the [Platform.isLinux] short-circuit
/// so non-Linux callers don't pay the FFI hop.
///
/// **Path choice** — Rust `zbus` over the pub.dev `dbus` package.
/// fprintd's verify cycle is signal-driven (`VerifyStatus`); zbus
/// gives async signal streams + tokio integration that drops
/// straight into the existing `lfs_core` runtime, so the entire
/// biometric path runs on one async stack instead of bridging
/// Dart's event loop into a Dart-side D-Bus client.
class FprintdClient {
  /// Timeout for a `VerifyStatus` signal to arrive. fprintd itself has
  /// an internal retry loop; this is the outer cap so a user who
  /// wandered off doesn't leave the UI frozen indefinitely.
  final Duration _verifyTimeout;

  /// Production wiring uses [Platform.isLinux] + the FRB-generated
  /// `rust_fprintd.*` calls; tests override the `*Fn` seams to drive
  /// every off-Linux short-circuit and every reachable / unreachable
  /// branch without booting D-Bus or shelling fprintd.
  FprintdClient({
    Duration? verifyTimeout,
    @visibleForTesting bool Function()? isLinuxFn,
    @visibleForTesting FprintdReachableFn? reachableFn,
    @visibleForTesting FprintdEnrolmentHashFn? enrolmentHashFn,
    @visibleForTesting FprintdHasFingersFn? hasFingersFn,
    @visibleForTesting FprintdVerifyFn? verifyFn,
  }) : _verifyTimeout = verifyTimeout ?? const Duration(seconds: 30),
       _isLinux = isLinuxFn ?? _defaultIsLinux,
       _reachable = reachableFn ?? rust_fprintd.fprintdIsServiceReachable,
       _enrolmentHash = enrolmentHashFn ?? rust_fprintd.fprintdGetEnrolmentHash,
       _hasFingers = hasFingersFn ?? rust_fprintd.fprintdHasEnrolledFingers,
       _verify = verifyFn ?? rust_fprintd.fprintdVerify;

  final bool Function() _isLinux;
  final FprintdReachableFn _reachable;
  final FprintdEnrolmentHashFn _enrolmentHash;
  final FprintdHasFingersFn _hasFingers;
  final FprintdVerifyFn _verify;

  static bool _defaultIsLinux() => Platform.isLinux;

  /// True when fprintd is registered on the system bus and its
  /// Manager interface answers a trivial `GetDefaultDevice` call.
  /// Any error — `ServiceUnknown`, `NoSuchDevice`, transport failure,
  /// timeout — is downgraded to `false` so the caller can translate
  /// into a single `systemServiceMissing` reason.
  Future<bool> isServiceReachable() async {
    if (!_isLinux()) return false;
    return _reachable();
  }

  /// SHA-256 of the current user's enrolled-finger list, sorted and
  /// joined by `:`. Returns null on any D-Bus / fprintd failure.
  ///
  /// Used as the TPM2 auth value when sealing the DB wrapping key so
  /// any change to the biometric enrolment (added, removed, or
  /// re-enrolled finger) invalidates the sealed blob — the Apple-side
  /// equivalent of `biometryCurrentSet`.
  Future<Uint8List?> getEnrolmentHash() async {
    if (!_isLinux()) return null;
    final bytes = await _enrolmentHash();
    if (bytes == null) return null;
    return Uint8List.fromList(bytes);
  }

  /// True when the current user has at least one finger enrolled via
  /// `fprintd-enroll`. Uses the empty-string username shortcut that
  /// fprintd interprets as "the calling uid's user".
  Future<bool> hasEnrolledFingers() async {
    if (!_isLinux()) return false;
    return _hasFingers();
  }

  /// Run a fprintd `Claim` → `VerifyStart` → wait for the terminal
  /// `VerifyStatus` signal cycle. Returns `true` only on the
  /// `verify-match` status; every other terminal — `verify-no-match`,
  /// `verify-error-*`, timeout, `Claim` / `VerifyStart` failure — maps
  /// to `false`. The Device is always released in the Rust impl's
  /// cleanup path so a failed verify does not leave the reader
  /// claimed against other apps.
  Future<bool> verify() async {
    if (!_isLinux()) return false;
    return _verify(timeoutMs: _verifyTimeout.inMilliseconds);
  }
}
