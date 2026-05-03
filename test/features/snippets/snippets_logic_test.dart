import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/features/snippets/snippets_logic.dart';

Snippet _snip({
  required String id,
  String title = '',
  String command = '',
  String description = '',
}) => Snippet(
  id: id,
  title: title,
  command: command,
  description: description,
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

void main() {
  final fixture = [
    _snip(
      id: '1',
      title: 'List remote home',
      command: 'ls -la ~',
      description: 'Show dotfiles too',
    ),
    _snip(
      id: '2',
      title: 'Disk usage',
      command: 'df -h',
      description: 'Per-mountpoint free space',
    ),
    _snip(
      id: '3',
      title: 'Tail systemd journal',
      command: 'journalctl -fu nginx',
      description: '',
    ),
  ];

  group('filterSnippets', () {
    test('empty filter returns the input verbatim', () {
      expect(filterSnippets(fixture, ''), fixture);
    });

    test('matches title (case-insensitive)', () {
      expect(filterSnippets(fixture, 'DISK').map((s) => s.id).toList(), ['2']);
    });

    test('matches command (case-insensitive)', () {
      expect(filterSnippets(fixture, 'JOURNAL').map((s) => s.id).toList(), [
        '3',
      ]);
    });

    test('matches description (case-insensitive)', () {
      expect(filterSnippets(fixture, 'dotfile').map((s) => s.id).toList(), [
        '1',
      ]);
    });

    test('a substring hitting multiple columns surfaces every match', () {
      // "list" appears in title of #1; nowhere else.
      expect(filterSnippets(fixture, 'list').map((s) => s.id).toSet(), {'1'});
    });

    test('no matches return empty list', () {
      expect(filterSnippets(fixture, 'nonexistent'), isEmpty);
    });

    test('empty input list is a no-op for any filter', () {
      expect(filterSnippets(const [], ''), isEmpty);
      expect(filterSnippets(const [], 'foo'), isEmpty);
    });
  });
}
