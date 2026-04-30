import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../src/rust/api/tpm.dart' as rust_tpm;

/// Classified TPM probe outcome — surfaces the reason the probe
/// failed so the Settings UI can render an actionable hint instead
/// of a generic "unavailable" line.
enum TpmProbeResult {
  /// The device node exists, `tpm2 getcap` returned success. TPM
  /// sealing is ready to go.
  available,

  /// Not Linux — probe returns this on any other host. Lets the
  /// Settings UI keep a single [probe] call instead of branching
  /// on [Platform.isLinux] separately.
  wrongPlatform,

  /// `/dev/tpmrm0` is missing. Either the host has no TPM at all,
  /// or the kernel module (`tpm_crb`, `tpm_tis`) failed to probe,
  /// or TPM is disabled in BIOS. User fix: enable fTPM / PTT in
  /// firmware settings, or accept that the host cannot do T2.
  deviceNodeMissing,

  /// The `tpm2` binary is missing from `$PATH`. User fix:
  /// `sudo apt install tpm2-tools` (or the distro equivalent).
  binaryMissing,

  /// `tpm2 getcap` returned non-zero or threw. Usually a permission
  /// issue on `/dev/tpmrm0` (wrong udev rule) or a TPM command
  /// failure. Harder for the user to diagnose — we show a generic
  /// "probe failed" line with the stderr in the logs.
  probeFailed,
}

/// Shell-out wrapper around the `tpm2-tools` CLI for sealing a 32-byte
/// DB wrapping key under a TPM2 primary key with a password-gated
/// sealed object. The auth value is an opaque byte string the caller
/// supplies — the TPM treats it as raw bytes and does not care how it
/// was derived. Callers choose the derivation to match the security
/// tier + modifier combo they want:
///
/// * T2 without any user-typed secret → empty `Uint8List(0)`
///   (isolation without authentication — same hw-vs-disk separation
///   as T2-no-modifiers on iOS / Android).
/// * T2 + password → `HMAC(typed_password, salt)`. Wrong password
///   fails TPM unseal; the TPM's dictionary-attack lockout rate-limits
///   guessing.
/// * T2 + biometric → `HMAC(fprintd_enrolment_hash, salt)` where the
///   hash is the SHA-256 of the sorted enrolled-fingers list. Any
///   change to enrolment changes the hash → the seal becomes
///   unreadable → user falls back to typing the password. Symmetric
///   with `biometryCurrentSet` on Apple and
///   `setInvalidatedByBiometricEnrollment(true)` on Android.
///
/// **Path choice** — shell-out to `tpm2-tools` over FFI to `libtss2-esys`.
/// Per [§ Native Over Dart When Better](../../../docs/AGENT_RULES.md#native-over-dart-when-better-and-zero-install):
/// the seal/unseal flow runs once per unlock; CLI process spawn costs a
/// few hundred ms against a native FFI's low ones, but `tpm2-tools` is
/// a tiny optional OS dep the user already needs to install via README
/// (rung 3), and it buys a battle-tested ESAPI wrapper for free. FFI
/// to libtss2 would be multi-week work for no measurable user-facing
/// benefit on a rare-path flow. Documented here so the decision is
/// explicit, not silent.
///
/// All inputs that touch the filesystem land in [Directory.systemTemp]
/// and are wiped in `finally` — a crashed process should never leave
/// the DB wrapping key readable on disk.
class TpmClient {
  /// Path to the `tpm2` binary. Override in tests. Production uses
  /// `$PATH` lookup via `Process.run('tpm2', ...)`.
  final String _binary;

  /// TPM resource-manager device node. Present on any modern TPM2
  /// host; absent on VMs without virtual-TPM and on older hardware.
  final String _tpmDevice;

  /// Maximum wall-clock for a seal / unseal shell-out. TPM ops are
  /// normally well under a second; anything beyond this is a stuck
  /// `tpm2-tools` invocation the app should abort rather than block
  /// the unlock dialog on indefinitely.
  final Duration _timeout;

  TpmClient({
    String binary = 'tpm2',
    String tpmDevice = '/dev/tpmrm0',
    Duration? timeout,
  }) : _binary = binary,
       _tpmDevice = tpmDevice,
       _timeout = timeout ?? const Duration(seconds: 15);

  /// True when the TPM device node is accessible and the `tpm2`
  /// binary answers a trivial `getcap` probe. Returns false on any
  /// error — missing binary, missing `/dev/tpmrm0`, permission
  /// denied, or the CLI rejecting the device — so the caller can
  /// surface a single `hardware not available` branch rather than
  /// re-parsing tpm2-tools diagnostics.
  Future<bool> isAvailable() async {
    return (await probe()) == TpmProbeResult.available;
  }

  /// Classified probe result — distinguishes *why* the TPM path is
  /// unavailable so the UI can show a specific fix instead of a
  /// generic "hardware not available on this device". Settings →
  /// Security consumes this on Linux to render the hardware-tier
  /// card's unavailable reason.
  ///
  /// Routes through `lfs_core::platform::linux::tpm::probe` (FRB
  /// async, runs the spawn on the blocking pool). The Rust path is
  /// authoritative — it shells out to the same `tpm2-tools`
  /// binaries and reads the same `/dev/tpmrm0` device node a Dart
  /// implementation would.
  Future<TpmProbeResult> probe() async {
    if (!Platform.isLinux) return TpmProbeResult.wrongPlatform;
    final r = await rust_tpm.tpmProbe(
      binary: _binary,
      device: _tpmDevice,
      timeoutMs: BigInt.from(_timeout.inMilliseconds),
    );
    switch (r) {
      case rust_tpm.DbTpmProbeResult.available:
        return TpmProbeResult.available;
      case rust_tpm.DbTpmProbeResult.deviceNodeMissing:
        return TpmProbeResult.deviceNodeMissing;
      case rust_tpm.DbTpmProbeResult.binaryMissing:
        return TpmProbeResult.binaryMissing;
      case rust_tpm.DbTpmProbeResult.probeFailed:
        return TpmProbeResult.probeFailed;
      case rust_tpm.DbTpmProbeResult.notLinux:
        return TpmProbeResult.wrongPlatform;
    }
  }

  /// Seal [secret] (≤ 128 bytes per TPM2 spec for direct seal) under
  /// a freshly-created primary with [authValue] as the unseal
  /// password. Returns the concatenated public + private blob on
  /// success, null on any failure.
  ///
  /// Encoding of the returned blob:
  /// `[4-byte BE pub length] [pub bytes] [4-byte BE priv length] [priv bytes]`
  Future<Uint8List?> seal(
    Uint8List secret, {
    required Uint8List authValue,
  }) async {
    if (secret.length > 128) return null;
    try {
      return await rust_tpm.tpmSeal(
        secret: secret,
        authValue: authValue,
        binary: _binary,
        device: _tpmDevice,
        timeoutMs: BigInt.from(_timeout.inMilliseconds),
      );
    } catch (_) {
      return null;
    }
  }

  /// Unseal a blob produced by [seal] using the same [authValue].
  /// Returns the original secret on success, null on any failure —
  /// wrong auth (enrolment changed), missing TPM, format mismatch.
  Future<Uint8List?> unseal(
    Uint8List blob, {
    required Uint8List authValue,
  }) async {
    try {
      return await rust_tpm.tpmUnseal(
        blob: blob,
        authValue: authValue,
        binary: _binary,
        device: _tpmDevice,
        timeoutMs: BigInt.from(_timeout.inMilliseconds),
      );
    } catch (_) {
      return null;
    }
  }
}
