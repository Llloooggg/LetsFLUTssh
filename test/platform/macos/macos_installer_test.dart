import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/platform/macos/code_signing/codesigner.dart';
import 'package:letsflutssh/platform/macos/code_signing/process_runner.dart';
import 'package:letsflutssh/platform/macos/code_signing/resign_service.dart';
import 'package:letsflutssh/platform/macos/installer/macos_installer.dart';

class _ScriptedRunner implements IProcessRunner {
  final List<List<String>> calls = [];
  final Map<String, ProcessResult> scripted;
  final ProcessResult fallback;

  _ScriptedRunner({required this.scripted, required this.fallback});

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    List<int>? stdin,
  }) async {
    calls.add([executable, ...arguments]);
    final key = arguments.isEmpty ? '' : arguments.first;
    return scripted[key] ?? fallback;
  }
}

void main() {
  group('MacosInstaller.install — non-applicable paths', () {
    test('returns notApplicable when target parent is not writable', () async {
      // `/` is typically not writable by the test user. The installer
      // probe tries to write in the parent dir of the target bundle.
      // We point target at `/letsflutssh.app` which has parent `/`,
      // and on macOS + Linux test hosts the root dir rejects writes.
      final unwritableTarget = Directory('/letsflutssh.app');
      final installer = MacosInstaller(
        runner: _ScriptedRunner(
          scripted: {},
          fallback: ProcessResult(1, 1, '', ''),
        ),
      );
      expect(
        await installer.install(
          dmgPath: File('/tmp/does-not-matter.dmg'),
          targetBundle: unwritableTarget,
        ),
        InstallOutcome.notApplicable,
      );
    });

    test('returns notApplicable on hdiutil attach failure', () async {
      final targetParent = Directory.systemTemp.createTempSync('lfs-t-');
      addTearDown(() => targetParent.deleteSync(recursive: true));
      final target = Directory('${targetParent.path}/letsflutssh.app')
        ..createSync();
      final installer = MacosInstaller(
        runner: _ScriptedRunner(
          scripted: {'attach': ProcessResult(1, 1, '', 'mount denied')},
          fallback: ProcessResult(1, 0, '', ''),
        ),
      );
      expect(
        await installer.install(
          dmgPath: File('${targetParent.path}/fake.dmg'),
          targetBundle: target,
        ),
        InstallOutcome.notApplicable,
      );
    });
  });

  group('MacosInstaller.install — mounted-volume paths', () {
    Directory setupLiveBundle(String parentPrefix) {
      final parent = Directory.systemTemp.createTempSync(parentPrefix);
      final target = Directory('${parent.path}/letsflutssh.app')..createSync();
      // Seed a sentinel file so the swap + backup paths can be
      // observed after the install completes.
      File('${target.path}/OLD').writeAsStringSync('old');
      addTearDown(() {
        if (parent.existsSync()) parent.deleteSync(recursive: true);
      });
      return target;
    }

    /// Fake `hdiutil attach` by pre-creating a `.app` directory at the
    /// scripted mount point — the installer's `_findAppBundle` just
    /// lists the mount point, so a real file-system stand-in is
    /// enough. Returns the function that populates the mount path
    /// when the runner's `attach` call fires.
    IProcessRunner buildRunner({
      required Directory mountPointRef,
      required String stagedPrefix,
      bool rsyncOk = true,
    }) {
      return _ScriptedRunnerWithSideEffects(
        onCall: (exec, args) {
          if (args.first == 'attach') {
            // Mount point is the -mountpoint arg. Create a dummy .app
            // inside so `_findAppBundle` finds it.
            final mp = args[args.indexOf('-mountpoint') + 1];
            Directory('$mp/letsflutssh.app').createSync(recursive: true);
            File('$mp/letsflutssh.app/NEW').writeAsStringSync('new');
            mountPointRef.path; // keep reference alive
            return ProcessResult(0, 0, '', '');
          }
          if (args.first == 'detach') return ProcessResult(0, 0, '', '');
          if (exec == '/usr/bin/rsync') {
            if (!rsyncOk) return ProcessResult(0, 1, '', 'rsync broke');
            // Mirror the source → staged path so `codesigner.verify`
            // sees the bundle.
            final src = args[args.length - 2].replaceAll(RegExp(r'/$'), '');
            final dst = args.last.replaceAll(RegExp(r'/$'), '');
            final dstDir = Directory(dst);
            if (!dstDir.existsSync()) dstDir.createSync(recursive: true);
            for (final f in Directory(src).listSync()) {
              if (f is File) {
                File(
                  '$dst/${f.uri.pathSegments.last}',
                ).writeAsStringSync(f.readAsStringSync());
              }
            }
            return ProcessResult(0, 0, '', '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );
    }

    test(
      'rsync failure returns notApplicable and leaves target intact',
      () async {
        final target = setupLiveBundle('lfs-rsync-fail-');
        final mountRef = Directory('');
        final installer = MacosInstaller(
          runner: buildRunner(
            mountPointRef: mountRef,
            stagedPrefix: target.path,
            rsyncOk: false,
          ),
          codesigner: _FakeCodesigner(),
          resignService: _FakeResign(hasId: false),
        );
        expect(
          await installer.install(
            dmgPath: File('${target.parent.path}/fake.dmg'),
            targetBundle: target,
          ),
          InstallOutcome.notApplicable,
        );
        // Target is untouched — OLD sentinel still there.
        expect(File('${target.path}/OLD').existsSync(), isTrue);
        expect(
          Directory('${target.path}.new').existsSync(),
          isFalse,
          reason: 'rsync failure must clean up staging',
        );
      },
    );

    test('codesign verify failure rolls back without swapping', () async {
      final target = setupLiveBundle('lfs-verify-fail-');
      final mountRef = Directory('');
      final installer = MacosInstaller(
        runner: buildRunner(mountPointRef: mountRef, stagedPrefix: target.path),
        codesigner: _FakeCodesigner(verifyOk: false),
        resignService: _FakeResign(hasId: false),
      );
      expect(
        await installer.install(
          dmgPath: File('${target.parent.path}/fake.dmg'),
          targetBundle: target,
        ),
        InstallOutcome.rolledBack,
      );
      // Target bundle is still the old version — atomic rename never
      // ran, so the OLD sentinel survives and the NEW file never
      // reached the live path.
      expect(File('${target.path}/OLD').existsSync(), isTrue);
      expect(File('${target.path}/NEW').existsSync(), isFalse);
      expect(Directory('${target.path}.new').existsSync(), isFalse);
    });

    test(
      'post-resign entitlement loss rolls back even when verify passes',
      () async {
        // Simulate the -34018 trap: extractEntitlements returns a
        // non-empty plist on the pre-resign pass, then null on the
        // post-resign pass. Verify succeeds (signature is valid) but
        // the installer must still abort the swap.
        final target = setupLiveBundle('lfs-ent-drop-');
        final mountRef = Directory('');
        final installer = MacosInstaller(
          runner: buildRunner(
            mountPointRef: mountRef,
            stagedPrefix: target.path,
          ),
          codesigner: _DroppingEntitlementsCodesigner(),
          resignService: _FakeResign(hasId: true),
        );
        expect(
          await installer.install(
            dmgPath: File('${target.parent.path}/fake.dmg'),
            targetBundle: target,
          ),
          InstallOutcome.rolledBack,
        );
        expect(File('${target.path}/OLD').existsSync(), isTrue);
      },
    );

    test(
      'happy path: staged bundle atomically replaces target + backup kept',
      () async {
        final target = setupLiveBundle('lfs-happy-');
        final mountRef = Directory('');
        final installer = MacosInstaller(
          runner: buildRunner(
            mountPointRef: mountRef,
            stagedPrefix: target.path,
          ),
          codesigner: _FakeCodesigner(),
          resignService: _FakeResign(hasId: false),
        );
        expect(
          await installer.install(
            dmgPath: File('${target.parent.path}/fake.dmg'),
            targetBundle: target,
          ),
          InstallOutcome.succeeded,
        );
        // Live path now holds the NEW bundle (rsynced from the mount).
        expect(File('${target.path}/NEW').existsSync(), isTrue);
        expect(File('${target.path}/OLD').existsSync(), isFalse);
        // Backup copy of the old bundle sticks around for
        // crash-recovery.
        final backup = Directory('${target.path}.backup');
        expect(backup.existsSync(), isTrue);
        expect(File('${backup.path}/OLD').existsSync(), isTrue);
      },
    );
  });

  group('MacosInstaller.cleanupBackup', () {
    test('removes .backup directory when it exists', () {
      final tmp = Directory.systemTemp.createTempSync('lfs-cb-');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      final target = Directory('${tmp.path}/app.app')..createSync();
      final backup = Directory('${target.path}.backup')
        ..createSync(recursive: true);
      MacosInstaller.cleanupBackup(target);
      expect(backup.existsSync(), isFalse);
    });

    test('is a no-op when .backup is absent', () {
      final tmp = Directory.systemTemp.createTempSync('lfs-cb-');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      final target = Directory('${tmp.path}/app.app')..createSync();
      // Must not throw.
      MacosInstaller.cleanupBackup(target);
    });
  });
}

class _ScriptedRunnerWithSideEffects implements IProcessRunner {
  _ScriptedRunnerWithSideEffects({required this.onCall});

  final ProcessResult Function(String executable, List<String> arguments)
  onCall;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    List<int>? stdin,
  }) async {
    return onCall(executable, arguments);
  }
}

class _FakeCodesigner extends Codesigner {
  _FakeCodesigner({this.verifyOk = true});

  final bool verifyOk;

  @override
  Future<String?> extractEntitlements(Directory appBundle) async => '<plist/>';

  @override
  Future<bool> verify(Directory bundle) async => verifyOk;
}

/// Codesigner that returns a plist on the *first* call to
/// [extractEntitlements] (pre-resign) and `null` on subsequent calls
/// (post-resign) — mirrors the `errSecMissingEntitlement` silent-drop
/// bug the installer's post-resign probe is designed to catch.
class _DroppingEntitlementsCodesigner extends Codesigner {
  int _calls = 0;

  @override
  Future<String?> extractEntitlements(Directory appBundle) async {
    _calls++;
    return _calls == 1 ? '<plist><dict/></plist>' : null;
  }

  @override
  Future<bool> verify(Directory bundle) async => true;
}

class _FakeResign extends ResignService {
  _FakeResign({required this.hasId});

  final bool hasId;

  @override
  Future<bool> hasIdentity({String commonName = 'letsflutssh-self'}) async =>
      hasId;

  @override
  Future<ResignOutcome> resignBundle({
    required Directory appBundle,
    String commonName = 'letsflutssh-self',
  }) async {
    return ResignOutcome.succeeded;
  }
}
