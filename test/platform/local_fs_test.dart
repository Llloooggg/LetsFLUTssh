import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/file_system.dart';
import 'package:letsflutssh/platform/local_fs.dart';

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
}
