/// Coverage for [LinuxKeychainMarker] — the gate that stops libsecret
/// probes from spamming stderr on Linux installs where no keyring
/// daemon is reachable.
///
/// The Dart class is a thin façade over
/// `lfs_core::security::keychain_marker`; the meaningful Dart-side
/// branches are (1) the `skipOnNonLinux` early-return on non-Linux
/// platforms and (2) the swallow-and-log paths on `set` / `clear`
/// failure. Both are testable end-to-end with a per-test temp dir
/// injected via the constructor's `supportDirFactory`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/linux_keychain_marker.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  late Directory tmp;
  late LinuxKeychainMarker marker;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lfs_keychain_marker_');
    marker = LinuxKeychainMarker(supportDirFactory: () async => tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('exists', () {
    test(
      'returns true on non-Linux when skipOnNonLinux defaults to true',
      () async {
        if (Platform.isLinux) return;
        // On macOS / Windows the keyring APIs do not emit stderr
        // warnings, so the gate must short-circuit to true without
        // ever touching the FRB call or the temp dir.
        expect(await marker.exists(), isTrue);
      },
    );

    test('forces the Rust probe when skipOnNonLinux=false', () async {
      // Marker file is absent in a fresh tmp dir → false, regardless
      // of platform. This is the branch the SecureKeyStorage path
      // hits on Linux first-launch.
      expect(await marker.exists(skipOnNonLinux: false), isFalse);
    });

    test('returns false on Linux when the marker file is absent', () async {
      if (!Platform.isLinux) return;
      expect(await marker.exists(), isFalse);
    });

    test('falls back to false when the supportDirFactory throws', () async {
      final broken = LinuxKeychainMarker(
        supportDirFactory: () async => throw StateError('factory boom'),
      );
      expect(await broken.exists(skipOnNonLinux: false), isFalse);
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
      // there's nothing on disk. Anything else would surface as
      // unhandled-future on the deleteKey rail.
      await marker.clear();
      expect(await marker.exists(skipOnNonLinux: false), isFalse);
    });

    test('set swallows when the supportDirFactory throws', () async {
      final broken = LinuxKeychainMarker(
        supportDirFactory: () async => throw StateError('factory boom'),
      );
      await broken.set();
    });

    test('clear swallows when the supportDirFactory throws', () async {
      final broken = LinuxKeychainMarker(
        supportDirFactory: () async => throw StateError('factory boom'),
      );
      await broken.clear();
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
