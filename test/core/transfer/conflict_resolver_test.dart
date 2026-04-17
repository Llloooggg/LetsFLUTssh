import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/transfer/conflict_resolver.dart';

void main() {
  group('BatchConflictResolver', () {
    test('forwards each call to the prompt when applyToAll is false', () async {
      final calls = <String>[];
      final resolver = BatchConflictResolver((
        path, {
        bool isRemote = false,
      }) async {
        calls.add(path);
        return const ConflictDecision(ConflictAction.replace);
      });

      expect(await resolver.resolve('/a'), ConflictAction.replace);
      expect(await resolver.resolve('/b'), ConflictAction.replace);
      expect(calls, ['/a', '/b']);
    });

    test('caches decision after applyToAll is checked', () async {
      final calls = <String>[];
      final resolver = BatchConflictResolver((
        path, {
        bool isRemote = false,
      }) async {
        calls.add(path);
        return const ConflictDecision(
          ConflictAction.keepBoth,
          applyToAll: true,
        );
      });

      expect(await resolver.resolve('/a'), ConflictAction.keepBoth);
      expect(await resolver.resolve('/b'), ConflictAction.keepBoth);
      expect(await resolver.resolve('/c'), ConflictAction.keepBoth);
      expect(calls, ['/a']);
    });

    test('short-circuits after a cancel decision', () async {
      var calls = 0;
      final resolver = BatchConflictResolver((
        path, {
        bool isRemote = false,
      }) async {
        calls++;
        return const ConflictDecision(ConflictAction.cancel);
      });

      expect(await resolver.resolve('/a'), ConflictAction.cancel);
      expect(resolver.isCancelled, isTrue);
      expect(await resolver.resolve('/b'), ConflictAction.cancel);
      expect(await resolver.resolve('/c'), ConflictAction.cancel);
      // Prompt should only have been invoked once — subsequent resolves
      // return the cancel sentinel without asking again.
      expect(calls, 1);
    });

    test('passes isRemote flag through to the prompt', () async {
      final seen = <bool>[];
      final resolver = BatchConflictResolver((
        path, {
        bool isRemote = false,
      }) async {
        seen.add(isRemote);
        return const ConflictDecision(ConflictAction.skip);
      });

      await resolver.resolve('/remote', isRemote: true);
      await resolver.resolve('/local', isRemote: false);
      expect(seen, [true, false]);
    });
  });
}
