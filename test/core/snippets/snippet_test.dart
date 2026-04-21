import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';

void main() {
  group('Snippet', () {
    test('constructor generates id and timestamps', () {
      final snippet = Snippet(title: 'Test', command: 'echo test');
      expect(snippet.id, isNotEmpty);
      expect(snippet.title, 'Test');
      expect(snippet.command, 'echo test');
      expect(snippet.description, '');
      expect(snippet.createdAt, isNotNull);
      expect(snippet.updatedAt, isNotNull);
    });

    test('constructor uses provided id', () {
      final snippet = Snippet(
        id: 'custom-id',
        title: 'Test',
        command: 'echo test',
      );
      expect(snippet.id, 'custom-id');
    });

    test('copyWith updates fields', () {
      final original = Snippet(
        title: 'Old',
        command: 'old',
        description: 'old desc',
      );
      final updated = original.copyWith(
        title: 'New',
        command: 'new',
        description: 'new desc',
      );

      expect(updated.id, original.id);
      expect(updated.title, 'New');
      expect(updated.command, 'new');
      expect(updated.description, 'new desc');
      expect(updated.createdAt, original.createdAt);
    });

    test('copyWith preserves unchanged fields', () {
      final original = Snippet(
        title: 'Title',
        command: 'cmd',
        description: 'desc',
      );
      final updated = original.copyWith(title: 'New Title');

      expect(updated.command, 'cmd');
      expect(updated.description, 'desc');
    });

    test('equality by id, title, command', () {
      final a = Snippet(id: '1', title: 'T', command: 'C');
      final b = Snippet(id: '1', title: 'T', command: 'C');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality when fields differ', () {
      final a = Snippet(id: '1', title: 'T', command: 'C');
      final b = Snippet(id: '1', title: 'T', command: 'D');
      expect(a, isNot(equals(b)));
    });

    test('two snippets get different ids', () {
      final a = Snippet(title: 'A', command: 'a');
      final b = Snippet(title: 'B', command: 'b');
      expect(a.id, isNot(b.id));
    });
  });
}
