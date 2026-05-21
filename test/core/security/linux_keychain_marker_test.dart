/// Coverage for [LinuxKeychainMarker] — the gate that stops libsecret
/// probes from spamming stderr on Linux installs where no keyring
/// daemon is reachable.
///
/// The Dart class is a thin façade over
/// `lfs_core::security::keychain_marker` (path-specific behaviour is
/// covered there against the explicit `&Path` API). The meaningful
/// Dart-side branches are (1) the `skipOnNonLinux` early-return on
/// non-Linux platforms and (2) the swallow-and-log paths on `set` /
/// `clear`. The marker ops resolve the support dir pinned Rust-side at
/// `configStoreInit`, so the test pins a temp dir up front.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/linux_keychain_marker.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final marker = LinuxKeychainMarker();

  setUpAll(() async {
    await requireFrbLoaded();
    tmp = Directory.systemTemp.createTempSync('lfs_keychain_marker_');
    // `configStoreInit` is the canonical pin point — it forwards into
    // `master_password::pin_support_dir`, which every marker op reads.
    // Process-global + idempotent; if another test file pinned first
    // the lifecycle assertions below still hold against that dir.
    rust_config.configStoreInit(supportDir: tmp.path);
  });

  tearDown(() async {
    // The pinned dir is fixed for the whole file, so drop any marker a
    // test left behind to keep the "absent" assertions independent.
    await marker.clear();
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('exists', () {
    test(
      'returns true on non-Linux when skipOnNonLinux defaults to true',
      () async {
        if (Platform.isLinux) return;
        // On macOS / Windows the keyring APIs do not emit stderr
        // warnings, so the gate must short-circuit to true without
        // ever touching the FRB call.
        expect(await marker.exists(), isTrue);
      },
    );

    test('forces the Rust probe when skipOnNonLinux=false', () async {
      // Marker file absent in a fresh pinned dir → false, regardless
      // of platform. This is the branch the SecureKeyStorage path
      // hits on Linux first-launch.
      expect(await marker.exists(skipOnNonLinux: false), isFalse);
    });

    test('returns false on Linux when the marker file is absent', () async {
      if (!Platform.isLinux) return;
      expect(await marker.exists(), isFalse);
    });
  });

  group('set + clear lifecycle', () {
    test('set then exists(skipOnNonLinux: false) reports true', () async {
      await marker.set();
      expect(await marker.exists(skipOnNonLinux: false), isTrue);
    });

    test('set is idempotent — second call leaves marker present', () async {
      await marker.set();
      await marker.set();
      expect(await marker.exists(skipOnNonLinux: false), isTrue);
    });

    test('clear after set drops the marker', () async {
      await marker.set();
      expect(await marker.exists(skipOnNonLinux: false), isTrue);
      await marker.clear();
      expect(await marker.exists(skipOnNonLinux: false), isFalse);
    });

    test('clear on a missing marker does not throw', () async {
      // Caller contract: clear is a "drop if present" no-op when
      // there's nothing on disk.
      await marker.clear();
      expect(await marker.exists(skipOnNonLinux: false), isFalse);
    });
  });

  group('default instance', () {
    test('LinuxKeychainMarker.defaultInstance is non-null + reusable', () {
      expect(LinuxKeychainMarker.defaultInstance, isNotNull);
      // Same singleton across reads — production callers pin the
      // instance once at construction time.
      expect(
        identical(
          LinuxKeychainMarker.defaultInstance,
          LinuxKeychainMarker.defaultInstance,
        ),
        isTrue,
      );
    });
  });
}
