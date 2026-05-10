import 'package:path_provider/path_provider.dart';

/// Best-effort, FRB-free wipe of every artefact the app holds under
/// `<app_support>`. Used by [FatalErrorApp] when the bootstrap chain
/// stops before `_initRustCoreOrFatal` has loaded the Rust core, so
/// `WipeAllService.wipeAll()` (the canonical Rust-backed sweep that
/// also flushes keychain / hardware-vault state) is not yet reachable.
///
/// The app-support directory is entirely owned by us — `path_provider`
/// resolves it to a per-bundle subdir on every supported platform
/// (`~/.local/share/<bundle>`, `~/Library/Application Support/<bundle>`,
/// `%APPDATA%/<bundle>`, per-app sandbox on mobile). Iterating the
/// immediate children and deleting each one wipes every file the app
/// could have written without needing a Dart-side catalogue mirroring
/// `lfs_core::security::wipe::MANAGED_FILES`; new artefacts land in
/// the same directory and inherit the sweep automatically. The parent
/// directory itself is kept so `path_provider` caches and any post-
/// wipe restart logic see a familiar empty home.
///
/// Keychain / hardware-vault / Apple SE artefacts are NOT covered
/// here — those live in OS-managed secret stores that need FRB to
/// reach. Any leftover OS-secure-storage entries surface on the next
/// launch as orphan state, which `_handleLegacyStateIfPresent`
/// catches and offers a tier-reset dialog for. Net effect: a user who
/// hits this path lands in a clean fresh-install state on the second
/// cold start.
Future<void> earlyWipeAppSupportFiles() async {
  try {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {
        // Best-effort — partial wipe is better than no wipe.
      }
    }
  } catch (_) {
    // path_provider unreachable — nothing to do.
  }
}
