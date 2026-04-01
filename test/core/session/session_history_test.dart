import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/session/session_history.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  late SessionHistory history;

  Session makeSession(String id, {String folder = ''}) => Session(
    id: id,
    label: 'test-$id',
    folder: folder,
    server: const ServerAddress(host: '10.0.0.1', user: 'root'),
  );

  SessionSnapshot makeSnap(List<Session> sessions, {Set<String> folders = const {}, String desc = 'op'}) =>
      SessionSnapshot(sessions: sessions, emptyFolders: folders, description: desc);

  setUp(() {
    history = SessionHistory();
  });

  group('SessionHistory', () {
    test('initially empty', () {
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
      expect(history.undoDescription, isNull);
      expect(history.redoDescription, isNull);
    });

    test('pushUndo enables undo', () {
      history.pushUndo(makeSnap([makeSession('1')], desc: 'delete'));
      expect(history.canUndo, isTrue);
      expect(history.undoDescription, 'delete');
      expect(history.canRedo, isFalse);
    });

    test('undo returns snapshot and enables redo', () {
      final before = makeSnap([makeSession('1'), makeSession('2')], desc: 'before delete');
      history.pushUndo(before);

      // Current state: session 1 was deleted
      final current = makeSnap([makeSession('2')], desc: 'current');
      final restored = history.undo(current);

      expect(restored, isNotNull);
      expect(restored!.sessions.length, 2);
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isTrue);
      expect(history.redoDescription, 'current');
    });

    test('redo returns snapshot', () {
      final before = makeSnap([makeSession('1'), makeSession('2')], desc: 'before');
      history.pushUndo(before);
      final afterDelete = makeSnap([makeSession('2')], desc: 'after delete');
      history.undo(afterDelete);

      // Now redo
      final restored = history.redo(makeSnap([makeSession('1'), makeSession('2')], desc: 'current'));
      expect(restored, isNotNull);
      expect(restored!.sessions.length, 1); // back to deleted state
      expect(history.canRedo, isFalse);
      expect(history.canUndo, isTrue);
    });

    test('pushUndo clears redo stack', () {
      history.pushUndo(makeSnap([makeSession('1')], desc: 'op1'));
      history.undo(makeSnap([], desc: 'current'));
      expect(history.canRedo, isTrue);

      // New operation clears redo
      history.pushUndo(makeSnap([makeSession('1')], desc: 'op2'));
      expect(history.canRedo, isFalse);
    });

    test('undo on empty returns null', () {
      expect(history.undo(makeSnap([], desc: 'x')), isNull);
    });

    test('redo on empty returns null', () {
      expect(history.redo(makeSnap([], desc: 'x')), isNull);
    });

    test('multiple undo/redo roundtrip', () {
      final s1 = makeSnap([makeSession('1')], desc: 'step1');
      final s2 = makeSnap([makeSession('1'), makeSession('2')], desc: 'step2');
      final s3 = makeSnap([makeSession('1'), makeSession('2'), makeSession('3')], desc: 'step3');

      history.pushUndo(s1);
      history.pushUndo(s2);

      // Current state is s3, undo to s2
      final r1 = history.undo(s3);
      expect(r1!.sessions.length, 2);

      // Undo to s1
      final r2 = history.undo(makeSnap(r1.sessions, desc: 'x'));
      expect(r2!.sessions.length, 1);

      // Redo back to s2
      final r3 = history.redo(makeSnap(r2.sessions, desc: 'x'));
      expect(r3!.sessions.length, 2);

      // Redo back to s3
      final r4 = history.redo(makeSnap(r3.sessions, desc: 'x'));
      expect(r4!.sessions.length, 3);
    });

    test('clear empties both stacks', () {
      history.pushUndo(makeSnap([makeSession('1')], desc: 'op'));
      history.undo(makeSnap([], desc: 'x'));
      expect(history.canRedo, isTrue);

      history.clear();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    });

    test('max history limits undo stack', () {
      for (var i = 0; i < 60; i++) {
        history.pushUndo(makeSnap([makeSession('$i')], desc: 'op$i'));
      }
      // Should have at most 50
      var count = 0;
      while (history.canUndo) {
        history.undo(makeSnap([], desc: 'x'));
        count++;
      }
      expect(count, 50);
    });

    test('preserves empty folders in snapshot', () {
      final snap = makeSnap([makeSession('1')], folders: {'Production', 'Dev'}, desc: 'with folders');
      history.pushUndo(snap);
      final restored = history.undo(makeSnap([], desc: 'current'));
      expect(restored!.emptyFolders, {'Production', 'Dev'});
    });
  });

  group('SessionSnapshot', () {
    test('holds sessions and folders', () {
      final snap = SessionSnapshot(
        sessions: [makeSession('1')],
        emptyFolders: {'A/B'},
        description: 'test',
      );
      expect(snap.sessions.length, 1);
      expect(snap.emptyFolders, {'A/B'});
      expect(snap.description, 'test');
    });
  });
}
