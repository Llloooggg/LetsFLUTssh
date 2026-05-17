import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/providers/session_provider.dart';

import '../helpers/fake_session_notifier.dart';

/// Pumps the workspace stream so the derived `sessionProvider` sees
/// the latest snapshot. Attaches a permanent listener so Riverpod
/// retains the stream subscription for the rest of the test — the
/// `.future` getter alone doesn't pin the subscription, which lets
/// the tear-down see a stale "loading" state when the container
/// disposes.
void _attachStreamListener(ProviderContainer container) {
  container.listen<AsyncValue<SessionWorkspaceSnapshot>>(
    sessionsWorkspaceStreamProvider,
    (_, _) {},
    fireImmediately: true,
  );
}

Future<void> _pumpStream(ProviderContainer container) async {
  _attachStreamListener(container);
  await container.read(sessionsWorkspaceStreamProvider.future);
}

void main() {
  Session makeSession({
    String id = 's1',
    String label = 'Test',
    String folder = '',
    String host = '10.0.0.1',
    String user = 'root',
  }) {
    return Session(
      id: id,
      label: label,
      folder: folder,
      server: ServerAddress(host: host, user: user),
    );
  }

  group('SessionMutator (FakeSessionNotifier seam)', () {
    late ProviderContainer container;
    late FakeSessionNotifier fake;

    setUp(() {
      fake = FakeSessionNotifier();
      container = ProviderContainer(overrides: fake.overrides());
    });

    tearDown(() async {
      container.dispose();
      await fake.dispose();
    });

    test('initial state is empty list', () async {
      await _pumpStream(container);
      expect(container.read(sessionProvider), isEmpty);
    });

    test('add inserts session and stream re-emits', () async {
      await _pumpStream(container);
      await container.read(sessionMutatorProvider).add(makeSession());
      // Wait for the controller broadcast to arrive.
      await Future<void>.delayed(Duration.zero);
      final sessions = container.read(sessionProvider);
      expect(sessions.length, 1);
      expect(sessions.first.id, 's1');
    });

    test('update modifies session', () async {
      await _pumpStream(container);
      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', label: 'Original'));
      await Future<void>.delayed(Duration.zero);
      await mutator.update(makeSession(id: 's1', label: 'Updated'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionProvider).first.label, 'Updated');
    });

    test('delete removes session', () async {
      await _pumpStream(container);
      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1'));
      await mutator.add(makeSession(id: 's2', label: 'Other'));
      await Future<void>.delayed(Duration.zero);
      await mutator.delete('s1');
      await Future<void>.delayed(Duration.zero);
      final sessions = container.read(sessionProvider);
      expect(sessions.length, 1);
      expect(sessions.first.id, 's2');
    });

    test('duplicate creates copy', () async {
      await _pumpStream(container);
      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', label: 'Original'));
      await Future<void>.delayed(Duration.zero);
      final copy = await mutator.duplicate('s1');
      await Future<void>.delayed(Duration.zero);
      expect(copy.id, 's1-copy');
      expect(copy.label, 'Original (copy)');
      expect(container.read(sessionProvider).length, 2);
    });

    test('addEmptyFolder adds folder', () async {
      await _pumpStream(container);
      await container
          .read(sessionMutatorProvider)
          .addEmptyFolder('Production/Web');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(emptyFoldersProvider), contains('Production/Web'));
    });

    test('renameFolder renames sessions in folder', () async {
      await _pumpStream(container);
      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'Old'));
      await Future<void>.delayed(Duration.zero);
      await mutator.renameFolder('Old', 'New');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionProvider).first.folder, 'New');
    });

    test('deleteFolder removes folder and sessions', () async {
      await _pumpStream(container);
      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'ToDelete'));
      await mutator.add(makeSession(id: 's2', folder: 'Keep'));
      await Future<void>.delayed(Duration.zero);
      await mutator.deleteFolder('ToDelete');
      await Future<void>.delayed(Duration.zero);
      final sessions = container.read(sessionProvider);
      expect(sessions.length, 1);
      expect(sessions.first.folder, 'Keep');
    });

    test('deleteAll clears everything', () async {
      await _pumpStream(container);
      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1'));
      await mutator.add(makeSession(id: 's2'));
      await mutator.addEmptyFolder('Group');
      await Future<void>.delayed(Duration.zero);
      await mutator.deleteAll();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionProvider), isEmpty);
      expect(container.read(emptyFoldersProvider), isEmpty);
    });

    test('moveSession changes folder', () async {
      await _pumpStream(container);
      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'Old'));
      await Future<void>.delayed(Duration.zero);
      await mutator.moveSession('s1', 'New');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionProvider).first.folder, 'New');
    });

    test('moveFolder changes folder path', () async {
      await _pumpStream(container);
      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'A'));
      await Future<void>.delayed(Duration.zero);
      await mutator.moveFolder('A', 'Parent');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionProvider).first.folder, 'Parent/A');
    });

    test(
      'duplicateFolder deep-copies the entire source tree into the target',
      () async {
        await _pumpStream(container);
        final mutator = container.read(sessionMutatorProvider);
        await mutator.add(makeSession(id: 's1', folder: 'A'));
        await mutator.add(makeSession(id: 's2', folder: 'A/Sub'));
        await mutator.add(makeSession(id: 's3', folder: 'B'));
        await Future<void>.delayed(Duration.zero);
        await mutator.duplicateFolder('A', 'B');
        await Future<void>.delayed(Duration.zero);
        final sessions = container.read(sessionProvider);
        // 3 originals + 2 duplicates (A → B/A, A/Sub → B/A/Sub).
        expect(sessions.length, 5);
        expect(sessions.where((s) => s.folder == 'B/A').length, 1);
        expect(sessions.where((s) => s.folder == 'B/A/Sub').length, 1);
        // Originals untouched.
        expect(sessions.any((s) => s.id == 's1' && s.folder == 'A'), isTrue);
        expect(
          sessions.any((s) => s.id == 's2' && s.folder == 'A/Sub'),
          isTrue,
        );
      },
    );

    test(
      'duplicateFolder refuses target inside source (cycle guard)',
      () async {
        await _pumpStream(container);
        final mutator = container.read(sessionMutatorProvider);
        await mutator.add(makeSession(id: 's1', folder: 'A'));
        await Future<void>.delayed(Duration.zero);
        await mutator.duplicateFolder('A', 'A/Sub');
        await Future<void>.delayed(Duration.zero);
        final sessions = container.read(sessionProvider);
        expect(sessions.length, 1);
        expect(sessions.first.folder, 'A');
      },
    );

    test('duplicateFolder is a no-op for an empty source path', () async {
      await _pumpStream(container);
      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', folder: 'A'));
      await Future<void>.delayed(Duration.zero);
      await mutator.duplicateFolder('', 'B');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionProvider).length, 1);
    });
  });

  group('SessionMutator error paths (ThrowingSessionNotifier)', () {
    late ProviderContainer container;
    late ThrowingSessionNotifier fake;

    setUp(() {
      fake = ThrowingSessionNotifier();
      container = ProviderContainer(overrides: fake.overrides());
    });

    tearDown(() async {
      container.dispose();
      await fake.dispose();
    });

    test('add rethrows on failure', () async {
      await _pumpStream(container);
      fake.shouldThrowOnAdd = true;
      // The fake's add is invoked directly through the mutator's
      // override; the throw escapes the FRB pass-through path.
      expect(
        () => container.read(sessionMutatorProvider).add(makeSession(id: 's1')),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('session providers with ProviderContainer', () {
    test('sessionProvider starts empty without overrides', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // The workspace stream's first emission hasn't landed yet —
      // derived `sessionProvider` yields the empty snapshot.
      final sessions = container.read(sessionProvider);
      expect(sessions, isEmpty);
    });

    test('sessionSearchProvider starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final query = container.read(sessionSearchProvider);
      expect(query, isEmpty);
    });

    test('filteredSessionsProvider returns all when no search', () async {
      final fake = FakeSessionNotifier();
      final container = ProviderContainer(overrides: fake.overrides());
      addTearDown(() async {
        container.dispose();
        await fake.dispose();
      });
      await _pumpStream(container);
      final filtered = container.read(filteredSessionsProvider);
      expect(filtered, isEmpty);
    });

    test('filteredSessionsProvider filters by label', () async {
      final fake = FakeSessionNotifier();
      final container = ProviderContainer(overrides: fake.overrides());
      addTearDown(() async {
        container.dispose();
        await fake.dispose();
      });
      await _pumpStream(container);

      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', label: 'Production'));
      await mutator.add(makeSession(id: 's2', label: 'Staging'));
      await Future<void>.delayed(Duration.zero);

      container.read(sessionSearchProvider.notifier).set('prod');
      final filtered = container.read(filteredSessionsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.label, 'Production');
    });

    test('filteredSessionsProvider filters by host', () async {
      final fake = FakeSessionNotifier();
      final container = ProviderContainer(overrides: fake.overrides());
      addTearDown(() async {
        container.dispose();
        await fake.dispose();
      });
      await _pumpStream(container);

      final mutator = container.read(sessionMutatorProvider);
      await mutator.add(makeSession(id: 's1', host: '10.0.0.1'));
      await mutator.add(makeSession(id: 's2', host: '192.168.1.1'));
      await Future<void>.delayed(Duration.zero);

      container.read(sessionSearchProvider.notifier).set('192');
      final filtered = container.read(filteredSessionsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.host, '192.168.1.1');
    });
  });

  group('sessionsLoadingProvider', () {
    test('defaults to loading=true so the cold-start first frame is blank', () {
      // The sidebar reads this flag to tell "still loading" apart from
      // "no sessions yet". Defaulting to `true` is what closes the
      // cold-start "No sessions" flash — flipping the default to
      // `false` would regress the flash.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(sessionsLoadingProvider), isTrue);
    });

    test('flips to false once the workspace stream emits', () async {
      final fake = FakeSessionNotifier();
      final container = ProviderContainer(overrides: fake.overrides());
      addTearDown(() async {
        container.dispose();
        await fake.dispose();
      });
      // First emit lands as soon as we drain the future.
      await _pumpStream(container);
      expect(container.read(sessionsLoadingProvider), isFalse);
    });
  });
}
