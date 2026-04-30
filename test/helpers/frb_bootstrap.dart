/// Loads the compiled `liblfs_frb.so` (Linux) / `liblfs_frb.dylib` (macOS) /
/// `lfs_frb.dll` (Windows) into the unit-test process so flutter_test code
/// can make real FRB calls instead of routing through Dart fallback paths.
///
/// flutter_test does not preload the native library the way `flutter run`
/// does — `RustLib.init` defaults to the `lfs_frb` stem at
/// `rust/crates/lfs_frb/target/release/`, but the Cargo workspace builds
/// at `rust/target/release/` (one level higher). This helper points the
/// loader at the workspace target.
///
/// Usage:
///
/// ```dart
/// void main() {
///   TestWidgetsFlutterBinding.ensureInitialized();
///   setUpAll(() async {
///     await ensureFrbLoaded();
///   });
///   test('reads from Rust', () async {
///     // Real FRB call — no fallback.
///   });
/// }
/// ```
///
/// Idempotent — repeated calls within a single process return immediately
/// once the library is loaded. Safe to call from `setUpAll` of every test
/// file that needs FRB; the underlying `RustLib.init` short-circuits on
/// the second call.
library;

import 'dart:io';

import 'package:flutter_rust_bridge/src/platform_types/_io.dart';

import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/frb_generated.dart';

bool _loaded = false;

/// Attempt to load `liblfs_frb` from one of the known build outputs.
/// Returns true on success, false when the library is genuinely
/// unreachable (CI without a Rust build, missing .so/.dylib).
///
/// Tests that gracefully degrade when FRB is unavailable can branch
/// on the return value; tests that require FRB should call
/// [requireFrbLoaded] which throws on miss.
Future<bool> ensureFrbLoaded() async {
  if (_loaded) return true;
  final libPath = _resolveLibraryPath();
  if (libPath == null) return false;
  try {
    await RustLib.init(externalLibrary: ExternalLibrary.open(libPath));
    // Mirror production startup — `lfs_core::app::AppState` is a
    // process singleton that downstream FRB calls (secrets / db /
    // connection registry / transfer queue / etc.) panic against
    // when missing. Production code calls this from `main.dart`
    // immediately after `RustLib.init`.
    rust_app.appInit();
    _loaded = true;
    return true;
  } catch (e) {
    // Surface the underlying error so a content-hash mismatch (forgot
    // to rebuild Rust after a codegen change) doesn't show up as a
    // mute "FRB unreachable" downstream. Failure mode is the same as
    // not finding the .so — the caller falls back or skips.
    // ignore: avoid_print
    print('ensureFrbLoaded: $libPath load failed — $e');
    return false;
  }
}

/// Strict variant — throws when the library cannot be loaded so the
/// test author sees a clear "FRB not available" error instead of the
/// downstream "RustLib instance is null" stack trace.
Future<void> requireFrbLoaded() async {
  if (await ensureFrbLoaded()) return;
  throw StateError(
    'liblfs_frb could not be loaded. Run `make rust-build` (or `cargo '
    'build --release -p lfs_frb` from rust/) before invoking the test '
    'suite that calls real FRB endpoints.',
  );
}

/// Walk the candidate paths the Cargo workspace lays the dylib down at.
/// Returns the first that exists, or `null` when none do (caller falls
/// back to Dart-side or skips).
String? _resolveLibraryPath() {
  // Cargo workspace target dir (the one `make rust-test` populates).
  for (final candidate in _candidatePaths) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

List<String> get _candidatePaths {
  // Project-root-relative — `flutter test` always runs from the project
  // root, so a relative path resolves identically across machines.
  final stem = Platform.isMacOS
      ? 'lib/liblfs_frb.dylib'
      : Platform.isWindows
      ? 'lfs_frb.dll'
      : 'liblfs_frb.so';
  if (Platform.isMacOS) {
    return ['rust/target/release/$stem', 'rust/target/debug/$stem'];
  }
  if (Platform.isWindows) {
    return ['rust/target/release/$stem', 'rust/target/debug/$stem'];
  }
  return ['rust/target/release/$stem', 'rust/target/debug/$stem'];
}
