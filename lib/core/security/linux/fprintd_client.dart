import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dbus/dbus.dart';

import '../../../utils/logger.dart';

/// Thin async wrapper around the `net.reactivated.Fprint` system-bus
/// API exposed by the `fprintd` daemon. Lives in the Linux-only
/// [`lib/core/security/linux/`](..) subdirectory because the package
/// `dbus` only has a useful implementation on Linux; the callers guard
/// every entry point with [Platform.isLinux].
///
/// The class is deliberately narrow: it covers the three verbs the
/// biometric-unlock feature actually needs — *is the service up*, *is
/// there a registered finger*, and *does the live finger match* — and
/// nothing else. Enrolment flows live in `fprintd-enroll` (the CLI the
/// README points users at); there is no reason for the app to ship its
/// own enroller.
///
/// **Path choice** — `dbus` pub.dev package over a native plugin.
/// Per [§ Native Over Dart When Better](../../../docs/AGENT_RULES.md#native-over-dart-when-better-and-zero-install):
/// a fprintd call is once-per-unlock IPC through a system-bus daemon;
/// a native Kotlin/Rust plugin would marshal the same D-Bus traffic
/// through the same socket with an extra method-channel hop. No
/// measurable performance or functionality win; the pub.dev `dbus`
/// package covers every call + signal we need.
class FprintdClient {
  static const _busName = 'net.reactivated.Fprint';
  static const _managerPath = '/net/reactivated/Fprint/Manager';
  static const _managerInterface = 'net.reactivated.Fprint.Manager';
  static const _deviceInterface = 'net.reactivated.Fprint.Device';

  /// Factory that yields a fresh [DBusClient]. Each probe opens its
  /// own connection and closes it in `finally` so a stuck fprintd
  /// call never wedges a long-lived socket. Tests inject a factory
  /// that returns a stub client; production calls [DBusClient.system].
  final DBusClient Function() _clientFactory;

  /// Timeout for a VerifyStatus signal to arrive. fprintd itself has
  /// an internal retry loop; we keep our own upper bound so a user
  /// who wandered off doesn't leave the UI frozen indefinitely.
  final Duration _verifyTimeout;

  FprintdClient({DBusClient Function()? clientFactory, Duration? verifyTimeout})
    : _clientFactory = clientFactory ?? DBusClient.system,
      _verifyTimeout = verifyTimeout ?? const Duration(seconds: 30);

  /// True when fprintd is registered on the system bus and its
  /// Manager interface answers a trivial `GetDefaultDevice` call.
  /// Any exception — `ServiceUnknown`, `NoSuchDevice`, timeout — is
  /// downgraded to `false` so the caller can translate into a single
  /// `systemServiceMissing` reason without re-parsing D-Bus errors.
  Future<bool> isServiceReachable() async {
    if (!Platform.isLinux) return false;
    final client = _clientFactory();
    try {
      final manager = DBusRemoteObject(
        client,
        name: _busName,
        path: DBusObjectPath(_managerPath),
      );
      await manager.callMethod(_managerInterface, 'GetDefaultDevice', const []);
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'fprintd not reachable: $e',
        name: 'FprintdClient',
      );
      return false;
    } finally {
      await client.close();
    }
  }

  /// SHA-256 of the current user's enrolled-finger list, sorted and
  /// joined by `:`. Returns null on any D-Bus / fprintd failure.
  ///
  /// Used as the TPM2 auth value when sealing the DB wrapping key so
  /// any change to the biometric enrolment (added, removed, or
  /// re-enrolled finger) invalidates the sealed blob — the Apple-side
  /// equivalent of `biometryCurrentSet`.
  Future<Uint8List?> getEnrolmentHash() async {
    if (!Platform.isLinux) return null;
    final client = _clientFactory();
    try {
      final devicePath = await _defaultDevicePath(client);
      if (devicePath == null) return null;
      final device = DBusRemoteObject(client, name: _busName, path: devicePath);
      final response = await device.callMethod(
        _deviceInterface,
        'ListEnrolledFingers',
        const [DBusString('')],
      );
      if (response.values.isEmpty) return null;
      final fingers = response.values.first.asStringArray().toList()..sort();
      if (fingers.isEmpty) return null;
      final joined = fingers.join(':');
      final digest = sha256.convert(utf8.encode(joined));
      return Uint8List.fromList(digest.bytes);
    } catch (e) {
      AppLogger.instance.log(
        'fprintd getEnrolmentHash failed: $e',
        name: 'FprintdClient',
      );
      return null;
    } finally {
      await client.close();
    }
  }

  /// True when the current user has at least one finger enrolled via
  /// `fprintd-enroll`. Uses the empty-string username shortcut that
  /// fprintd interprets as "the calling uid's user".
  Future<bool> hasEnrolledFingers() async {
    if (!Platform.isLinux) return false;
    final client = _clientFactory();
    try {
      final devicePath = await _defaultDevicePath(client);
      if (devicePath == null) return false;
      final device = DBusRemoteObject(client, name: _busName, path: devicePath);
      final response = await device.callMethod(
        _deviceInterface,
        'ListEnrolledFingers',
        const [DBusString('')],
      );
      if (response.values.isEmpty) return false;
      final fingers = response.values.first.asStringArray().toList();
      return fingers.isNotEmpty;
    } catch (e) {
      AppLogger.instance.log(
        'fprintd ListEnrolledFingers failed: $e',
        name: 'FprintdClient',
      );
      return false;
    } finally {
      await client.close();
    }
  }

  /// Run a fprintd `VerifyStart` / `VerifyStop` pair and wait for the
  /// terminal `VerifyStatus` signal. Returns `true` only on the
  /// `verify-match` status; every other terminal — `verify-no-match`,
  /// `verify-error-*`, timeout, Claim/VerifyStart failure — maps to
  /// `false`. The Device is always released in `finally` so a failed
  /// verify does not leave the reader claimed against other apps.
  Future<bool> verify() async {
    if (!Platform.isLinux) return false;
    final client = _clientFactory();
    StreamSubscription<DBusSignal>? sub;
    DBusRemoteObject? device;
    var claimed = false;
    var started = false;
    try {
      final devicePath = await _defaultDevicePath(client);
      if (devicePath == null) return false;
      device = DBusRemoteObject(client, name: _busName, path: devicePath);
      await device.callMethod(_deviceInterface, 'Claim', const [
        DBusString(''),
      ]);
      claimed = true;
      final completer = Completer<bool>();
      final statusStream = DBusRemoteObjectSignalStream(
        object: device,
        interface: _deviceInterface,
        name: 'VerifyStatus',
      );
      sub = statusStream.listen((signal) {
        if (completer.isCompleted || signal.values.length < 2) return;
        final result = signal.values[0].asString();
        final done = signal.values[1].asBoolean();
        if (done) {
          completer.complete(result == 'verify-match');
        }
      });
      await device.callMethod(_deviceInterface, 'VerifyStart', const [
        DBusString('any'),
      ]);
      started = true;
      return await completer.future.timeout(
        _verifyTimeout,
        onTimeout: () {
          AppLogger.instance.log(
            'fprintd VerifyStatus timeout after ${_verifyTimeout.inSeconds}s',
            name: 'FprintdClient',
          );
          return false;
        },
      );
    } catch (e) {
      AppLogger.instance.log(
        'fprintd Verify flow failed: $e',
        name: 'FprintdClient',
      );
      return false;
    } finally {
      await sub?.cancel();
      await _releaseDevice(device: device, started: started, claimed: claimed);
      await client.close();
    }
  }

  /// Best-effort cleanup of a verify session's Device. Each call is
  /// swallowed because the surrounding `verify()` has already decided
  /// the outcome — an exception here only means the reader was lost
  /// mid-verify, and there is nothing useful to do with that.
  /// Extracted so `verify()` stays under the S3776 cognitive-
  /// complexity threshold.
  Future<void> _releaseDevice({
    required DBusRemoteObject? device,
    required bool started,
    required bool claimed,
  }) async {
    if (device == null) return;
    if (started) {
      try {
        await device.callMethod(_deviceInterface, 'VerifyStop', const []);
      } catch (_) {}
    }
    if (claimed) {
      try {
        await device.callMethod(_deviceInterface, 'Release', const []);
      } catch (_) {}
    }
  }

  Future<DBusObjectPath?> _defaultDevicePath(DBusClient client) async {
    final manager = DBusRemoteObject(
      client,
      name: _busName,
      path: DBusObjectPath(_managerPath),
    );
    final response = await manager.callMethod(
      _managerInterface,
      'GetDefaultDevice',
      const [],
    );
    if (response.values.isEmpty) return null;
    final path = response.values.first.asObjectPath();
    // fprintd returns `/` when no device is present; treat as "no reader".
    if (path.value.isEmpty || path.value == '/') return null;
    return path;
  }
}
