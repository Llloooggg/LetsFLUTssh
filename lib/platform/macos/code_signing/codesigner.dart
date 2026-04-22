import 'dart:io';

import 'process_runner.dart';

/// Wraps `/usr/bin/codesign` for the inside-out re-sign the self-sign
/// flow needs.
///
/// Why not `--deep`: codesign's own docs label `--deep` an "emergency
/// measure" and in practice it visits nested frameworks in arbitrary
/// order. Flutter macOS bundles hit this the moment `--deep` signs
/// `shared_preferences_foundation.framework` after a container that
/// already referenced its old signature — codesign bails with
/// `errSecInternalComponent`. Signing the bundle contents leaf-first
/// (dylibs → frameworks → xpc/appex → outer .app) is the
/// documented-working order, and the loop below is cheap.
///
/// Why `--options runtime` + `--entitlements` on the outer-bundle
/// re-sign: Keychain Services binds stored items to the app's
/// designated requirement *plus* its entitlement blob. Dropping
/// `keychain-access-groups` during re-sign is exactly what produces
/// the `errSecMissingEntitlement` (-34018) that the whole self-sign
/// flow exists to fix. We extract the live entitlements from the
/// current signature via `codesign -d --entitlements :-` and pass
/// them back through `--entitlements`.
class Codesigner {
  static const String _codesignPath = '/usr/bin/codesign';

  final IProcessRunner runner;

  const Codesigner({this.runner = const SystemProcessRunner()});

  /// Extract the live entitlements plist embedded in the bundle's
  /// current signature. Returns `null` when the signature has no
  /// entitlements (CI ad-hoc builds without a Release.entitlements
  /// configured, or a corrupt bundle) — callers fall back to
  /// re-signing without entitlements and log a loud warning because
  /// T1 keychain access will break regardless.
  Future<String?> extractEntitlements(Directory appBundle) async {
    final res = await runner.run(_codesignPath, [
      '-d',
      '--entitlements',
      ':-',
      appBundle.path,
    ]);
    if (res.exitCode != 0) return null;
    final plist = (res.stdout as String).trim();
    return plist.isEmpty ? null : plist;
  }

  /// Verify that [bundle] survives `codesign --verify --deep
  /// --strict --verbose=2`. Returns `true` on clean exit. Callers
  /// use this as the gate between "new bundle staged" and "atomic
  /// swap" — a verify failure means the bundle is corrupt and the
  /// update is aborted.
  Future<bool> verify(Directory bundle) async {
    final res = await runner.run(_codesignPath, [
      '--verify',
      '--deep',
      '--strict',
      '--verbose=2',
      bundle.path,
    ]);
    return res.exitCode == 0;
  }

  /// Re-sign [appBundle] leaf-first with [commonName] as the signing
  /// identity. [entitlementsPlist] is the output of
  /// [extractEntitlements] — passed only on the outer bundle pass so
  /// the runtime entitlements survive.
  ///
  /// Order of operations (each stage a separate codesign call):
  ///   1. every `*.dylib` under `Contents/`
  ///   2. every `*.framework` dir under `Contents/Frameworks/`
  ///   3. every `*.xpc` / `*.appex` helper under `Contents/`
  ///   4. the outer `.app` bundle with `--options runtime` +
  ///      `--entitlements`
  ///
  /// Any single step throws [CodesignException] with the failing
  /// subpath included so the caller's log points at the precise file
  /// codesign rejected.
  Future<void> resignInsideOut({
    required Directory appBundle,
    required String commonName,
    String? entitlementsPlist,
    bool useSudo = false,
  }) async {
    final String cmd = useSudo ? 'sudo' : _codesignPath;
    // When we prepend sudo, codesign becomes the first positional
    // argument instead of the executable.
    List<String> prefix(List<String> args) =>
        useSudo ? [_codesignPath, ...args] : args;

    final baseSign = ['--force', '--options', 'runtime', '--sign', commonName];

    Future<void> signOne(String subpath, {List<String>? extra}) async {
      final args = prefix([...baseSign, if (extra != null) ...extra, subpath]);
      final res = await runner.run(cmd, args);
      if (res.exitCode != 0) {
        throw CodesignException(
          subpath,
          'codesign exited ${res.exitCode}: ${res.stderr}',
        );
      }
    }

    // 1. dylibs
    for (final lib in _walk(appBundle, suffix: '.dylib', isFile: true)) {
      await signOne(lib.path);
    }

    // 2. frameworks
    final frameworksDir = Directory('${appBundle.path}/Contents/Frameworks');
    if (frameworksDir.existsSync()) {
      for (final fw in _walk(
        frameworksDir,
        suffix: '.framework',
        isFile: false,
      )) {
        await signOne(fw.path);
      }
    }

    // 3. XPC / appex helpers
    for (final helper in _walk(appBundle, suffix: '.xpc', isFile: false)) {
      await signOne(helper.path);
    }
    for (final helper in _walk(appBundle, suffix: '.appex', isFile: false)) {
      await signOne(helper.path);
    }

    // 4. outer bundle — with entitlements
    File? entPlistFile;
    final outerExtra = <String>[];
    if (entitlementsPlist != null) {
      final tmp = Directory.systemTemp.createTempSync('lfs-codesign-ent-');
      entPlistFile = File('${tmp.path}/entitlements.plist')
        ..writeAsStringSync(entitlementsPlist);
      outerExtra.addAll(['--entitlements', entPlistFile.path]);
    }
    try {
      await signOne(appBundle.path, extra: outerExtra);
    } finally {
      entPlistFile?.parent.deleteSync(recursive: true);
    }
  }

  Iterable<FileSystemEntity> _walk(
    Directory root, {
    required String suffix,
    required bool isFile,
  }) {
    if (!root.existsSync()) return const [];
    return root
        .listSync(recursive: true, followLinks: false)
        .where(
          (e) =>
              e.path.endsWith(suffix) && (isFile ? e is File : e is Directory),
        );
  }
}

class CodesignException implements Exception {
  final String subpath;
  final String message;
  CodesignException(this.subpath, this.message);
  @override
  String toString() => 'CodesignException($subpath): $message';
}
