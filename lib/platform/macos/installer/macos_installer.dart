import 'dart:io';

import '../code_signing/codesigner.dart';
import '../code_signing/process_runner.dart';
import '../code_signing/resign_service.dart';

/// Outcome of an atomic DMG install. Surfaces back to `UpdateService`
/// so the UI can pick the right copy — success kicks a relaunch,
/// failure lands on the current "open DMG in Finder" fallback.
enum InstallOutcome {
  /// Bundle swapped, re-signed under the existing personal cert
  /// (if any), ready to relaunch.
  succeeded,

  /// Atomic-swap path bailed mid-flight; target bundle is still the
  /// pre-install version.
  rolledBack,

  /// Writability or privilege barrier prevented the swap. Caller
  /// falls back to the Finder-reveal path.
  notApplicable,
}

/// Installs a macOS `.dmg` artefact into the live `.app` location
/// without user interaction.
///
/// Flow:
///   1. `hdiutil attach -nobrowse -noautoopen` mounts the DMG.
///   2. `rsync -a --delete` copies the `.app` inside the mounted
///      volume to `<target>.new`.
///   3. `hdiutil detach` releases the DMG.
///   4. Optional re-sign via [ResignService] when a personal cert is
///      in the keychain. If the user never enabled T1, re-sign is
///      skipped and the new bundle keeps its CI ad-hoc signature.
///   5. `codesign --verify --strict` on `<target>.new` — if the
///      re-sign corrupted the bundle, the verify fails and we roll
///      back to the untouched original.
///   6. Atomic rename: `<target>` → `<target>.backup`, `<target>.new`
///      → `<target>`. The `.backup` directory sticks around as a
///      crash-recovery trail — startup checks for it and restores
///      if the new bundle never launched cleanly.
///
/// Any failure before the atomic rename leaves `<target>` untouched
/// — the worst outcome is a dangling `<target>.new` or `.backup` in
/// the install root, which the next successful install cleans up.
class MacosInstaller {
  final IProcessRunner runner;
  final Codesigner codesigner;
  final ResignService resignService;

  const MacosInstaller({
    this.runner = const SystemProcessRunner(),
    this.codesigner = const Codesigner(),
    this.resignService = const ResignService(),
  });

  /// Install [dmgPath] on top of [targetBundle]. [targetBundle] is the
  /// live `.app` the running process was launched from — caller
  /// resolves it via `Platform.resolvedExecutable` / walk up the
  /// bundle tree.
  Future<InstallOutcome> install({
    required File dmgPath,
    required Directory targetBundle,
  }) async {
    if (!_isWritable(targetBundle.parent)) {
      return InstallOutcome.notApplicable;
    }

    final mountPoint = Directory.systemTemp.createTempSync('lfs-dmg-mount-');
    final stagedPath = Directory('${targetBundle.path}.new');
    final backupPath = Directory('${targetBundle.path}.backup');

    try {
      // 1. mount
      final attachRes = await runner.run('/usr/bin/hdiutil', [
        'attach',
        '-nobrowse',
        '-noautoopen',
        '-mountpoint',
        mountPoint.path,
        dmgPath.path,
      ]);
      if (attachRes.exitCode != 0) return InstallOutcome.notApplicable;

      // 2. find the .app inside the mounted volume
      final mountedApp = _findAppBundle(mountPoint);
      if (mountedApp == null) {
        await _detach(mountPoint.path);
        return InstallOutcome.notApplicable;
      }

      // 3. rsync into staging
      if (stagedPath.existsSync()) {
        stagedPath.deleteSync(recursive: true);
      }
      final rsyncRes = await runner.run('/usr/bin/rsync', [
        '-a',
        '--delete',
        '${mountedApp.path}/',
        '${stagedPath.path}/',
      ]);
      await _detach(mountPoint.path);
      if (rsyncRes.exitCode != 0) {
        if (stagedPath.existsSync()) stagedPath.deleteSync(recursive: true);
        return InstallOutcome.notApplicable;
      }

      // 4. snapshot the pre-resign entitlements so the post-resign
      //    probe can catch "entitlements survived the re-sign pass".
      //    A CI ad-hoc bundle with `keychain-access-groups` that
      //    silently drops that key during re-sign is exactly the
      //    -34018 trap we're trying to dodge — the staged bundle
      //    would pass `codesign --verify` (signature is valid) but
      //    hit `errSecMissingEntitlement` on the first T1 read.
      final preResignEnt = await codesigner.extractEntitlements(stagedPath);

      // 5. re-sign under the user's personal cert, but only if one
      //    is actually installed. `hasIdentity` short-circuits the
      //    no-cert case so a user who declined the first-launch
      //    self-sign offer still gets silent updates — the bundle
      //    just keeps the CI ad-hoc signature it came with. Calling
      //    `resignBundle` unconditionally would fail `codesign`
      //    subprocess with "no identity found" and rolling back the
      //    install on every update for users who never opted in.
      if (await resignService.hasIdentity()) {
        await resignService.resignBundle(appBundle: stagedPath);
      }

      // 6. verify the staged bundle — if it fails, discard staging
      //    and leave target untouched.
      if (!await codesigner.verify(stagedPath)) {
        stagedPath.deleteSync(recursive: true);
        return InstallOutcome.rolledBack;
      }

      // 7. post-resign entitlement probe: if the pre-resign bundle
      //    had entitlements but the re-signed one comes back empty
      //    the re-sign silently stripped them. Signature is still
      //    valid (codesign --verify passes) but T1 keychain is
      //    dead — every stored item returns -34018. Roll back
      //    before the atomic swap so the user stays on the working
      //    prior version.
      if (preResignEnt != null) {
        final postResignEnt = await codesigner.extractEntitlements(stagedPath);
        if (postResignEnt == null) {
          stagedPath.deleteSync(recursive: true);
          return InstallOutcome.rolledBack;
        }
      }

      // 8. atomic swap. Sequence matters: move old → backup first,
      //    then new → target. If the second rename fails the user
      //    is left with `.backup` at the install root and no live
      //    `.app`, which the caller surfaces as "update broken,
      //    restore from backup".
      if (backupPath.existsSync()) {
        backupPath.deleteSync(recursive: true);
      }
      targetBundle.renameSync(backupPath.path);
      try {
        stagedPath.renameSync(targetBundle.path);
      } on FileSystemException {
        // Rollback: restore old bundle, leave staging for diag.
        backupPath.renameSync(targetBundle.path);
        return InstallOutcome.rolledBack;
      }
      return InstallOutcome.succeeded;
    } finally {
      if (mountPoint.existsSync()) {
        mountPoint.deleteSync(recursive: true);
      }
    }
  }

  Future<void> _detach(String mountPoint) async {
    await runner.run('/usr/bin/hdiutil', ['detach', mountPoint, '-force']);
  }

  Directory? _findAppBundle(Directory mountPoint) {
    if (!mountPoint.existsSync()) return null;
    for (final entry in mountPoint.listSync(followLinks: false)) {
      if (entry is Directory && entry.path.endsWith('.app')) return entry;
    }
    return null;
  }

  bool _isWritable(Directory dir) {
    try {
      final probe = File('${dir.path}/.lfs-install-probe');
      probe.writeAsStringSync('x');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Housekeeping: drop the rollback backup after the new bundle has
  /// run cleanly. Called from `main._bootstrap` a few seconds after
  /// startup so a crash during early init still finds the backup.
  static void cleanupBackup(Directory targetBundle) {
    final backup = Directory('${targetBundle.path}.backup');
    if (backup.existsSync()) {
      try {
        backup.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort — if the backup can't be removed the next
        // successful install's swap will sweep it.
      }
    }
  }
}
