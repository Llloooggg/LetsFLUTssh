import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/platform/macos/code_signing/process_runner.dart';
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
