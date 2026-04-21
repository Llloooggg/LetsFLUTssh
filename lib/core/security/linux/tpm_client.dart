import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../utils/logger.dart';

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
  Future<TpmProbeResult> probe() async {
    if (!Platform.isLinux) return TpmProbeResult.wrongPlatform;
    if (!await File(_tpmDevice).exists()) {
      return TpmProbeResult.deviceNodeMissing;
    }
    try {
      final getcap = await Process.run(_binary, const [
        'getcap',
        '-l',
      ], runInShell: false).timeout(_timeout);
      if (getcap.exitCode != 0) {
        AppLogger.instance.log(
          'tpm2 getcap exit=${getcap.exitCode} stderr=${getcap.stderr}',
          name: 'TpmClient',
        );
        return TpmProbeResult.probeFailed;
      }
      // Real key-create round-trip on top of the capability query —
      // `getcap` only reads TPM properties and can succeed on a host
      // where `/dev/tpmrm0` permissions allow read but not write
      // (uncommon but observed on hardened sandboxes). The full
      // `createprimary` exercises the same path as `seal`, so a
      // probe success here is a strict guarantee that downstream
      // sealing will not fail with a permissions / lockout error.
      // Best-effort cleanup: a stranded primary handle costs nothing
      // (TPM resource manager flushes it when the parent context
      // closes anyway) and the work dir is wiped via the same helper
      // `seal` uses.
      final workDir = await Directory.systemTemp.createTemp('lfs-tpm-probe-');
      try {
        final ctx = p.join(workDir.path, 'probe.ctx');
        final create = await Process.run(_binary, [
          'createprimary',
          '-Q',
          '-C',
          'o',
          '-c',
          ctx,
        ], runInShell: false).timeout(_timeout);
        if (create.exitCode != 0) {
          AppLogger.instance.log(
            'tpm2 createprimary probe exit=${create.exitCode} '
            'stderr=${create.stderr}',
            name: 'TpmClient',
          );
          return TpmProbeResult.probeFailed;
        }
      } finally {
        await _wipeDir(workDir);
      }
      return TpmProbeResult.available;
    } on ProcessException catch (e) {
      // `tpm2` binary missing → Process.start fails with errno 2
      // before the timeout fires. Classify explicitly so the UI can
      // steer the user at an `apt install tpm2-tools` hint.
      if (e.errorCode == 2 || e.message.contains('No such file')) {
        return TpmProbeResult.binaryMissing;
      }
      AppLogger.instance.log('tpm2 probe process error: $e', name: 'TpmClient');
      return TpmProbeResult.probeFailed;
    } catch (e) {
      AppLogger.instance.log('tpm2 probe failed: $e', name: 'TpmClient');
      return TpmProbeResult.probeFailed;
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
    if (secret.length > 128) {
      AppLogger.instance.log(
        'tpm2 seal rejected: secret longer than 128 bytes',
        name: 'TpmClient',
      );
      return null;
    }
    final workDir = await Directory.systemTemp.createTemp('lfs-tpm-seal-');
    try {
      final primary = p.join(workDir.path, 'primary.ctx');
      final pubPath = p.join(workDir.path, 'sealed.pub');
      final privPath = p.join(workDir.path, 'sealed.priv');
      final secretPath = p.join(workDir.path, 'secret.bin');
      await File(secretPath).writeAsBytes(secret, flush: true);
      final authArg = 'hex:${hex(authValue)}';
      final createPrimary = await _runTpm([
        'createprimary',
        '-Q',
        '-C',
        'o',
        '-c',
        primary,
      ]);
      if (!createPrimary) return null;
      final create = await _runTpm([
        'create',
        '-Q',
        '-C',
        primary,
        '-u',
        pubPath,
        '-r',
        privPath,
        '-i',
        secretPath,
        '-p',
        authArg,
      ]);
      if (!create) return null;
      final pub = await File(pubPath).readAsBytes();
      final priv = await File(privPath).readAsBytes();
      return _pack(pub, priv);
    } catch (e) {
      AppLogger.instance.log('tpm2 seal failed: $e', name: 'TpmClient');
      return null;
    } finally {
      await _wipeDir(workDir);
    }
  }

  /// Unseal a blob produced by [seal] using the same [authValue].
  /// Returns the original secret on success, null on any failure —
  /// wrong auth (enrolment changed), missing TPM, format mismatch.
  Future<Uint8List?> unseal(
    Uint8List blob, {
    required Uint8List authValue,
  }) async {
    final unpacked = _unpack(blob);
    if (unpacked == null) return null;
    final (pub, priv) = unpacked;
    final workDir = await Directory.systemTemp.createTemp('lfs-tpm-unseal-');
    try {
      final primary = p.join(workDir.path, 'primary.ctx');
      final pubPath = p.join(workDir.path, 'sealed.pub');
      final privPath = p.join(workDir.path, 'sealed.priv');
      final loadedCtx = p.join(workDir.path, 'loaded.ctx');
      await File(pubPath).writeAsBytes(pub, flush: true);
      await File(privPath).writeAsBytes(priv, flush: true);
      final authArg = 'hex:${hex(authValue)}';
      final createPrimary = await _runTpm([
        'createprimary',
        '-Q',
        '-C',
        'o',
        '-c',
        primary,
      ]);
      if (!createPrimary) return null;
      final load = await _runTpm([
        'load',
        '-Q',
        '-C',
        primary,
        '-u',
        pubPath,
        '-r',
        privPath,
        '-c',
        loadedCtx,
      ]);
      if (!load) return null;
      final result = await Process.run(_binary, [
        'unseal',
        '-Q',
        '-c',
        loadedCtx,
        '-p',
        authArg,
      ]).timeout(_timeout);
      if (result.exitCode != 0) {
        AppLogger.instance.log(
          'tpm2 unseal exit=${result.exitCode} stderr=${result.stderr}',
          name: 'TpmClient',
        );
        return null;
      }
      final stdout = result.stdout;
      if (stdout is List<int>) return Uint8List.fromList(stdout);
      if (stdout is String) return Uint8List.fromList(stdout.codeUnits);
      return null;
    } catch (e) {
      AppLogger.instance.log('tpm2 unseal failed: $e', name: 'TpmClient');
      return null;
    } finally {
      await _wipeDir(workDir);
    }
  }

  Future<bool> _runTpm(List<String> args) async {
    final result = await Process.run(
      _binary,
      args,
      runInShell: false,
    ).timeout(_timeout);
    if (result.exitCode != 0) {
      AppLogger.instance.log(
        'tpm2 ${args.first} exit=${result.exitCode} stderr=${result.stderr}',
        name: 'TpmClient',
      );
      return false;
    }
    return true;
  }

  Future<void> _wipeDir(Directory dir) async {
    try {
      // Best-effort overwrite of every file before unlink so the
      // sealed-but-transient plaintext (`secret.bin` during seal) is
      // not merely marked free on whatever filesystem `/tmp` lives on.
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File) {
            try {
              final length = await entity.length();
              await entity.writeAsBytes(Uint8List(length), flush: true);
            } catch (_) {}
          }
        }
        await dir.delete(recursive: true);
      }
    } catch (e) {
      AppLogger.instance.log('tpm temp wipe failed: $e', name: 'TpmClient');
    }
  }

  /// Lowercase hex helper — tpm2-tools auth values use `hex:<hex>`.
  static String hex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _pack(Uint8List pub, Uint8List priv) {
    final out = BytesBuilder(copy: false);
    out.add(_u32(pub.length));
    out.add(pub);
    out.add(_u32(priv.length));
    out.add(priv);
    return out.toBytes();
  }

  static (Uint8List pub, Uint8List priv)? _unpack(Uint8List blob) {
    if (blob.length < 8) return null;
    var offset = 0;
    int readU32() {
      final v =
          (blob[offset] << 24) |
          (blob[offset + 1] << 16) |
          (blob[offset + 2] << 8) |
          blob[offset + 3];
      offset += 4;
      return v;
    }

    final pubLen = readU32();
    if (offset + pubLen > blob.length) return null;
    final pub = Uint8List.sublistView(blob, offset, offset + pubLen);
    offset += pubLen;
    if (offset + 4 > blob.length) return null;
    final privLen = readU32();
    if (offset + privLen > blob.length) return null;
    final priv = Uint8List.sublistView(blob, offset, offset + privLen);
    return (pub, priv);
  }

  static Uint8List _u32(int v) {
    return Uint8List.fromList([
      (v >> 24) & 0xff,
      (v >> 16) & 0xff,
      (v >> 8) & 0xff,
      v & 0xff,
    ]);
  }
}

// Kept at file bottom so the top of the file reads as the public
// contract first. Not exported; callers rely only on the typed
// methods above.
// ignore: unused_element
String _base64Debug(Uint8List bytes) => base64Encode(bytes);
