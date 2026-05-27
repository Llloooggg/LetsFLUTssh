import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/logs/log_store.dart';
import 'package:letsflutssh/utils/logger.dart';

/// `LogStore` is a process singleton that subscribes to the global
/// `AppLogger.liveEntries` stream and exposes the filtered subset the
/// Settings → Logs viewer renders. The pure-Dart behaviour exercised
/// here — append, filter, clear, listener firing — is load-bearing
/// for the viewer; a regression turns the viewer into either a silent
/// black box or a memory leak. Entries are injected through the
/// `debugInject` test seam so the test does not need a fully-bootstrapped
/// AppLogger (which depends on `path_provider`, hence `flutter_test`'s
/// MethodChannel pump).
void main() {
  setUp(() async {
    // ignore: deprecated_member_use_from_same_package
    await LogStore.resetForTesting();
  });

  LogEntry routine(
    String message, {
    LogLevel level = LogLevel.info,
    String tag = 'T',
    List<String> continuations = const [],
  }) => LogEntry(
    level: level,
    timestamp: '12:34:56',
    tag: tag,
    message: message,
    continuations: continuations,
  );

  group('LogStore', () {
    test('starts empty', () {
      final s = LogStore.instance;
      expect(s.allEntries, isEmpty);
      expect(s.filteredEntries, isEmpty);
      expect(s.query, '');
      expect(s.visibleLevels, equals(Set.of(LogLevel.values)));
    });

    test(
      'appended entries land in both lists when filter is wide-open',
      () async {
        final s = LogStore.instance;
        var notified = 0;
        final sub = s.changes.listen((_) => notified++);

        s.debugInject(routine('a'));
        s.debugInject(routine('b'));

        expect(s.allEntries.map((e) => e.message), ['a', 'b']);
        expect(s.filteredEntries.map((e) => e.message), ['a', 'b']);
        // Broadcast delivery is async — drain the microtask queue.
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(notified, 2);
      },
    );

    test('level filter excludes non-matching entries from filteredEntries', () {
      final s = LogStore.instance;
      s.debugInject(routine('warn-a', level: LogLevel.warn));
      s.debugInject(routine('info-a', level: LogLevel.info));
      s.debugInject(routine('err-a', level: LogLevel.error));

      s.applyFilter(visibleLevels: {LogLevel.warn}, query: '');

      expect(s.allEntries.map((e) => e.message).toList(), [
        'warn-a',
        'info-a',
        'err-a',
      ]);
      expect(s.filteredEntries.map((e) => e.message).toList(), ['warn-a']);
    });

    test('substring query matches across message + tag + continuations', () {
      final s = LogStore.instance;
      s.debugInject(routine('Keychain probe ok', tag: 'Sec'));
      s.debugInject(routine('routine', tag: 'KeyStore'));
      s.debugInject(routine('unrelated', tag: 'X'));
      s.debugInject(
        routine(
          'plain',
          tag: 'X',
          continuations: ['  Error: keychain unavailable'],
        ),
      );

      s.applyFilter(visibleLevels: Set.of(LogLevel.values), query: 'KEY');

      expect(s.filteredEntries.map((e) => e.message).toList(), [
        'Keychain probe ok', // tag/message contains 'key'
        'routine', // tag 'KeyStore' contains 'key'
        'plain', // continuation contains 'keychain'
      ]);
    });

    test(
      'header entries drop out of the filtered view when any filter is active',
      () {
        final s = LogStore.instance;
        s.debugInject(
          const LogEntry(message: '--- Log started ---', isHeader: true),
        );
        s.debugInject(routine('row-a'));

        // Wide-open filter keeps headers.
        expect(s.filteredEntries, hasLength(2));

        // Any narrowing — query OR a missing level — drops headers.
        s.applyFilter(visibleLevels: Set.of(LogLevel.values), query: 'row');
        expect(s.filteredEntries.every((e) => !e.isHeader), isTrue);

        s.applyFilter(visibleLevels: {LogLevel.info}, query: '');
        expect(s.filteredEntries.every((e) => !e.isHeader), isTrue);
      },
    );

    test('applyFilter recomputes from the full buffer', () {
      final s = LogStore.instance;
      s.debugInject(routine('a', level: LogLevel.info));
      s.debugInject(routine('b', level: LogLevel.warn));
      s.applyFilter(visibleLevels: {LogLevel.info}, query: '');
      expect(s.filteredEntries.map((e) => e.message), ['a']);

      // Re-widen — the full buffer is still there to recompute against.
      s.applyFilter(visibleLevels: Set.of(LogLevel.values), query: '');
      expect(s.filteredEntries.map((e) => e.message), ['a', 'b']);
    });

    test('clearAll empties both lists and notifies', () async {
      final s = LogStore.instance;
      s.debugInject(routine('a'));
      s.debugInject(routine('b'));

      var notified = false;
      final sub = s.changes.listen((_) => notified = true);

      s.clearAll();
      expect(s.allEntries, isEmpty);
      expect(s.filteredEntries, isEmpty);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(notified, isTrue);
    });

    test('applyFilter exposes the active query + visible levels', () {
      final s = LogStore.instance;
      s.applyFilter(
        visibleLevels: {LogLevel.warn, LogLevel.error},
        query: 'db',
      );
      expect(s.query, 'db');
      expect(s.visibleLevels, {LogLevel.warn, LogLevel.error});
    });

    test('visibleLevels is an unmodifiable snapshot', () {
      // The getter must not hand callers a mutable handle into the
      // store's internal filter set.
      final s = LogStore.instance;
      expect(() => s.visibleLevels.add(LogLevel.info), throwsUnsupportedError);
    });

    test('allEntries is an unmodifiable snapshot', () {
      final s = LogStore.instance;
      s.debugInject(routine('a'));
      expect(() => s.allEntries.add(routine('b')), throwsUnsupportedError);
    });

    test('buffer trims the oldest entries past the 50k soft cap', () {
      // The buffer is bounded; once it exceeds the cap the oldest rows
      // fall out FIFO so a long-lived session does not grow without
      // limit. Cap is 50_000; push one past and assert the head moved.
      final s = LogStore.instance;
      const cap = 50000;
      for (var i = 0; i <= cap; i++) {
        s.debugInject(routine('m$i'));
      }
      expect(s.allEntries, hasLength(cap));
      // The very first entry ('m0') must have been evicted; the new
      // head is 'm1'.
      expect(s.allEntries.first.message, 'm1');
      expect(s.allEntries.last.message, 'm$cap');
    });

    test('a live banner after a non-banner entry appends (no collapse)', () {
      // Collapse only fires banner-on-banner. A banner that lands
      // after ordinary content marks a real new session and must be
      // kept as its own row.
      final s = LogStore.instance;
      s.debugInject(routine('work'));
      s.debugInject(
        const LogEntry(
          message: '--- Log started 2026-05-07 ---',
          isHeader: true,
        ),
      );
      expect(s.allEntries.map((e) => e.message), [
        'work',
        '--- Log started 2026-05-07 ---',
      ]);
    });

    test('dispose closes the change stream so listeners complete', () async {
      final s = LogStore.instance;
      var done = false;
      final sub = s.changes.listen((_) {}, onDone: () => done = true);

      await s.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(done, isTrue, reason: 'stream should close on dispose');
      await sub.cancel();
    });

    test('mutations after dispose do not throw on the closed stream', () async {
      // `_emitChange` guards on `_changes.isClosed`; a stray mutation
      // after dispose must be a silent no-op, not a "Cannot add to a
      // closed stream" crash.
      final s = LogStore.instance;
      await s.dispose();
      expect(() => s.clearAll(), returnsNormally);
      expect(() => s.debugInject(routine('a')), returnsNormally);
    });

    test(
      'listener fires on every append + on filter change + on clear',
      () async {
        final s = LogStore.instance;
        var n = 0;
        final sub = s.changes.listen((_) => n++);

        s.debugInject(routine('a'));
        s.debugInject(routine('b'));
        s.applyFilter(visibleLevels: {LogLevel.info}, query: '');
        s.clearAll();

        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(n, 4);
      },
    );
  });

  group('LogStore.ensureSeeded merge', () {
    // Reproduces the chronology bug fixed by the seed-replace path:
    // the live `liveEntries` subscription fires while the disk seed
    // read is still in flight; without dedup the boot logs end up
    // doubled and out of order (live appended at the start,
    // seed-from-disk dumped at the end with the `--- Log started ---`
    // banner trailing the boot lines).

    test('seed entries land at the top, leftover live entries follow', () {
      final s = LogStore.instance;
      // Live entry that arrived before the seed was applied. The seed
      // does not contain it, so it stays.
      s.debugInject(routine('post-seed live', tag: 'Late'));

      final seed = [
        '--- Log started 2026-05-07 19:26:48 | linux foo ---',
        '12:34:56 I [Boot] phase=rust_core elapsed=61ms',
        '12:34:57 I [DbOpen] db open phase=connection elapsed=0ms',
      ].join('\n');
      s.debugApplySeed(seed);

      final messages = s.allEntries.map((e) => e.message).toList();
      expect(messages, [
        '--- Log started 2026-05-07 19:26:48 | linux foo ---',
        'phase=rust_core elapsed=61ms',
        'db open phase=connection elapsed=0ms',
        'post-seed live',
      ]);
    });

    test(
      'live entries that the seed already contains are dropped (no duplicates)',
      () {
        final s = LogStore.instance;
        // This entry mirrors what the live subscription saw before
        // `_applySeed` ran. The seed read picks the same bytes off
        // disk; without dedup the buffer would carry it twice.
        s.debugInject(
          const LogEntry(
            level: LogLevel.info,
            timestamp: '12:34:57',
            tag: 'Boot',
            message: 'phase=rust_core elapsed=61ms',
          ),
        );
        // A truly-late live entry that the seed has not captured.
        s.debugInject(routine('truly late', tag: 'Late'));

        final seed = [
          '--- Log started 2026-05-07 19:26:48 | linux foo ---',
          '12:34:57 I [Boot] phase=rust_core elapsed=61ms',
        ].join('\n');
        s.debugApplySeed(seed);

        final messages = s.allEntries.map((e) => e.message).toList();
        expect(messages, [
          '--- Log started 2026-05-07 19:26:48 | linux foo ---',
          'phase=rust_core elapsed=61ms',
          'truly late',
        ], reason: 'duplicate live entry should have been dropped');
      },
    );

    test('empty seed leaves any existing live entries untouched', () {
      final s = LogStore.instance;
      s.debugInject(routine('a'));
      s.debugInject(routine('b'));

      s.debugApplySeed('');

      expect(s.allEntries.map((e) => e.message), ['a', 'b']);
    });
  });

  group('LogStore adjacent-banner collapse', () {
    // User-reported "опять два раза лейбл о начале логов" — file
    // accumulates back-to-back `--- Log started ---` markers when
    // multiple processes boot in quick succession without writing
    // any entries between them. The viewer collapses adjacent
    // banners on the read side: only the LATER banner survives.
    // Other header rows (`Platform: ...`, `Dart: ...` from rotated
    // legacy files) do NOT collapse — they carry distinct content.

    test('two adjacent banners in the seed collapse to the later one', () {
      final s = LogStore.instance;
      final seed = [
        '--- Log started 2026-05-07 19:26:48 | linux | LetsFLUTssh 1.0 ---',
        '--- Log started 2026-05-07 19:26:56 | linux | LetsFLUTssh 1.0 ---',
        '12:34:57 I [Boot] phase=rust_core elapsed=61ms',
      ].join('\n');

      s.debugApplySeed(seed);

      expect(s.allEntries.map((e) => e.message), [
        '--- Log started 2026-05-07 19:26:56 | linux | LetsFLUTssh 1.0 ---',
        'phase=rust_core elapsed=61ms',
      ]);
    });

    test(
      'a banner with content between is preserved (each session keeps its boundary)',
      () {
        final s = LogStore.instance;
        final seed = [
          '--- Log started 2026-05-07 19:26:48 | linux | LetsFLUTssh 1.0 ---',
          '12:34:50 I [App] something',
          '--- Log started 2026-05-07 19:26:56 | linux | LetsFLUTssh 1.0 ---',
          '12:34:57 I [Boot] phase=rust_core elapsed=61ms',
        ].join('\n');

        s.debugApplySeed(seed);

        expect(s.allEntries.map((e) => e.message), [
          '--- Log started 2026-05-07 19:26:48 | linux | LetsFLUTssh 1.0 ---',
          'something',
          '--- Log started 2026-05-07 19:26:56 | linux | LetsFLUTssh 1.0 ---',
          'phase=rust_core elapsed=61ms',
        ]);
      },
    );

    test('a live banner arriving on top of an existing banner replaces it', () {
      final s = LogStore.instance;
      s.debugInject(
        const LogEntry(
          message: '--- Log started 2026-05-07 19:26:48 | a ---',
          isHeader: true,
        ),
      );
      s.debugInject(
        const LogEntry(
          message: '--- Log started 2026-05-07 19:26:56 | b ---',
          isHeader: true,
        ),
      );

      expect(s.allEntries.map((e) => e.message), [
        '--- Log started 2026-05-07 19:26:56 | b ---',
      ]);
    });

    test(
      'non-banner header rows (`Platform: ...` from legacy files) are NOT collapsed against banners',
      () {
        final s = LogStore.instance;
        // Legacy three-row block: banner + Platform + Dart. Each is
        // `isHeader: true`, but only the `--- ... ---` row is a banner.
        // The other two carry content and must stay.
        final seed = [
          '--- Log started 2026-05-07 19:26:48 | new | LetsFLUTssh 1.0 ---',
          'Platform: linux Linux 6.6',
          'Dart: 3.4.0',
        ].join('\n');

        s.debugApplySeed(seed);

        expect(s.allEntries.map((e) => e.message), [
          '--- Log started 2026-05-07 19:26:48 | new | LetsFLUTssh 1.0 ---',
          'Platform: linux Linux 6.6',
          'Dart: 3.4.0',
        ]);
      },
    );
  });
}
