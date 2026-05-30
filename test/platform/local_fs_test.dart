import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/platform/local_fs.dart';
import 'package:path/path.dart' as p;

import '../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalFS.capabilities', () {
    // Spec: every local entry carries a real `st_mode` (Unix) or a
    // synthesised mode (Windows / Android) plus an owner string, so
    // the file-browser pane must surface the POSIX columns. A drift
    // back to `objectStore` would silently hide perm + owner columns
    // from local panes.
    test('reports POSIX mode + owner', () {
      final fs = LocalFS();
      final caps = fs.capabilities;
      expect(caps.posixMode, isTrue);
      expect(caps.owner, isTrue);
      // Identity guard — the production constant is the single
      // source of truth, not a fresh instance.
      expect(identical(caps, FileSystemCapabilities.posix), isTrue);
    });
  });

  group('LocalFS.describeError', () {
    // Spec: the FRB wrapper class' toString reads
    // `"AnyhowException: <rust msg>"`. The toast shows the bare
    // rust message — leaking the wrapper name forces every locale
    // to translate the Dart-side noise.
    test('strips the AnyhowException prefix from FRB error envelopes', () {
      const raw = 'AnyhowException: directory not found';
      expect(LocalFS.describeError(raw), 'directory not found');
    });

    test('passes a non-FRB error through unchanged', () {
      // Spec: a `String`-bearing FRB variant (or a plain `Error`)
      // already reads cleanly; the prefix-trim must not chop into
      // valid messages.
      const raw = 'permission denied';
      expect(LocalFS.describeError(raw), raw);
    });

    test('handles a thrown Exception by routing through toString', () {
      // Spec: the helper accepts an arbitrary `Object`; a
      // `FormatException` (or any other thrown type) is described
      // by its `toString` envelope — the prefix only matches the
      // FRB shape, so the rest must round-trip.
      const e = FormatException('bad utf-8');
      final s = LocalFS.describeError(e);
      // Don't pin on the exact toString shape across Dart releases;
      // assert the structural contract — the error message survives.
      expect(s, contains('bad utf-8'));
      expect(s, isNot(startsWith('AnyhowException:')));
    });

    test('a doubled prefix is only trimmed once — the inner one is data', () {
      // Spec: only one leading `AnyhowException: ` is treated as
      // envelope noise; a second occurrence is part of the Rust
      // message (e.g. a wrapped chained error). Stripping both
      // would lose information from the rendered toast.
      const raw = 'AnyhowException: AnyhowException: nested';
      expect(LocalFS.describeError(raw), 'AnyhowException: nested');
    });
  });

  group('LocalFS — desktop initialDir + list/exists round-trip', () {
    // Non-mobile branch of `initialDir` resolves the OS home dir from the
    // Rust `host_info::home_directory` getter and falls back to
    // `Directory.current.path` when empty. The mobile branches
    // (`Platform.isIOS` / `Platform.isAndroid`) need `path_provider`
    // plugin channels and Android scoped-storage probes which the
    // unit harness cannot drive — covered by integration.
    setUpAll(requireFrbLoaded);

    test(
      'initialDir on the desktop CI host returns a non-empty absolute path — '
      'the Rust home_dir getter or the cwd fallback always wins, never the '
      'empty string',
      () async {
        if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
          return; // Mobile branches require plugin channels — skipped.
        }
        // Spec: `initialDir` on desktop returns the user's home dir, or
        // falls back to `Directory.current.path` when the Rust-side
        // probe surfaces empty. The two-arm contract guarantees the
        // file browser always opens at a real directory; an empty
        // string would let the pane try to list `""` and surface a
        // raw FRB error instead of useful content.
        final dir = await LocalFS().initialDir();
        expect(dir, isNotEmpty);
        // Both arms produce absolute paths — homes (`/home/<user>` /
        // `/Users/<user>` / `C:\\Users\\<user>`) and the cwd fallback
        // (`Directory.current.path`) are absolute on every supported
        // desktop host.
        expect(p.isAbsolute(dir), isTrue);
      },
    );

    test(
      'list against a missing path surfaces FileSystemException with the path '
      'attached — the FRB error envelope is unwrapped Rust-side and rewrapped '
      'so callers catch one stable type, not the FRB anyhow shape',
      () async {
        // Spec: `LocalFS.list` catches the FRB error variant and
        // rethrows as `FileSystemException(describeError(e), path)`.
        // A regression that let the bare FRB exception escape would
        // force every caller to import the FRB error class to handle
        // a missing path — instead they get the stable
        // `FileSystemException` shape and an attached path field for
        // the toast.
        final fs = LocalFS();
        try {
          await fs.list(
            '/nonexistent-/-letsflutssh-fixture-${DateTime.now().microsecondsSinceEpoch}',
          );
          fail('expected FileSystemException on a missing path');
        } on FileSystemException catch (e) {
          expect(e.path, isNotNull);
          expect(e.path, contains('letsflutssh-fixture-'));
        }
      },
    );

    test(
      'exists on a freshly-created empty temp dir returns true; on a synthetic '
      'never-created child it returns false — the LSTAT probe is the cheap '
      'path the trait default does not take',
      () async {
        // Spec: `LocalFS.exists` overrides the default parent-list walk
        // with `localFsSymlinkStat`, which is one syscall. The
        // contract is "true iff the path exists on disk", surfaced
        // without following symlinks. We exercise both arms against
        // a real tempdir so the FRB round-trip is what's pinned, not
        // a mock.
        final tmp = await Directory.systemTemp.createTemp('lfs_exists_');
        try {
          final fs = LocalFS();
          expect(await fs.exists(tmp.path), isTrue);
          final missing = p.join(tmp.path, 'never-created');
          expect(await fs.exists(missing), isFalse);
        } finally {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        }
      },
    );

    test(
      'list of a fresh empty tempdir yields an empty entry list — no synthetic '
      '"." / ".." rows leak through from the Rust walker',
      () async {
        // Spec: `localFsListVisible` filters Windows Hidden / System
        // bits Rust-side and never emits `.` / `..`. The Dart wrapper
        // then sorts the result. An empty tempdir must produce a zero-
        // length list — a regression that surfaced `.` / `..` would
        // double-count entries in the pane and break the "empty
        // directory" empty-state copy.
        final tmp = await Directory.systemTemp.createTemp('lfs_list_');
        try {
          final entries = await LocalFS().list(tmp.path);
          expect(entries, isEmpty);
        } finally {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        }
      },
    );
  });

  // iOS / Android `initialDir` branches — covered by integration:
  // both routes need plugin channels (`path_provider`,
  // `getApplicationDocumentsDirectory`, `getExternalStorageDirectory`)
  // that the unit harness does not wire. The desktop branch above
  // exercises the home-dir / cwd-fallback arm of the same method;
  // the mobile branches are pinned by the per-platform integration
  // suite (`test/integration/file_browser_transfer_test.dart` and
  // mobile-specific build-time smoke runs).
}
