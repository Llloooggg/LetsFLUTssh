import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/core/snippets/snippet_template.dart';

Snippet _s(String command) => Snippet(id: 'i', title: 't', command: command);

void main() {
  group('renderSnippet', () {
    test('substitutes a single known token', () {
      final r = renderSnippet(_s('ssh {{host}}'), {'host': 'example.com'});
      expect(r.rendered, 'ssh example.com');
      expect(r.unresolved, isEmpty);
    });

    test('substitutes multiple distinct tokens', () {
      final r = renderSnippet(_s('ssh -p {{port}} {{user}}@{{host}}'), {
        'host': 'h',
        'user': 'u',
        'port': '2222',
      });
      expect(r.rendered, 'ssh -p 2222 u@h');
      expect(r.unresolved, isEmpty);
    });

    test('leaves unknown tokens intact and lists them once each', () {
      final r = renderSnippet(_s('echo {{name}} {{name}} {{age}}'), const {});
      expect(r.rendered, 'echo {{name}} {{name}} {{age}}');
      expect(r.unresolved, ['name', 'age']);
    });

    test('mixes known and unknown', () {
      final r = renderSnippet(_s('curl http://{{host}}/{{path}}'), {
        'host': 'api.local',
      });
      expect(r.rendered, 'curl http://api.local/{{path}}');
      expect(r.unresolved, ['path']);
    });

    test('whitespace inside the token is trimmed', () {
      final r = renderSnippet(_s('{{  host  }}'), {'host': 'x'});
      expect(r.rendered, 'x');
      expect(r.unresolved, isEmpty);
    });

    test('empty token `{{}}` is left literal, not silently dropped', () {
      final r = renderSnippet(_s('a{{}}b'), const {});
      expect(r.rendered, 'a{{}}b');
      expect(r.unresolved, isEmpty);
    });

    test('unterminated `{{` is copied verbatim', () {
      final r = renderSnippet(_s('echo {{host'), {'host': 'x'});
      expect(r.rendered, 'echo {{host');
      expect(r.unresolved, isEmpty);
    });

    test('escape `{{{{` produces a literal `{{`', () {
      final r = renderSnippet(_s('{{{{not-a-token}}'), const {});
      expect(r.rendered, '{{not-a-token}}');
      expect(r.unresolved, isEmpty);
    });

    test('substituted values are not re-scanned (no recursion)', () {
      // value contains a placeholder-looking string — must NOT expand.
      final r = renderSnippet(_s('a {{x}} b'), {'x': '{{y}}', 'y': 'NOPE'});
      expect(r.rendered, 'a {{y}} b');
      expect(r.unresolved, isEmpty);
    });

    test('empty context passes the source through and reports every token', () {
      final r = renderSnippet(_s('{{a}} {{b}}'), const {});
      expect(r.rendered, '{{a}} {{b}}');
      expect(r.unresolved, ['a', 'b']);
    });

    test('command with no tokens is unchanged', () {
      final r = renderSnippet(_s('uptime'), const {'host': 'x'});
      expect(r.rendered, 'uptime');
      expect(r.unresolved, isEmpty);
    });
  });

  group('fillSnippetUnresolved', () {
    test('substitutes the values left behind by renderSnippet', () {
      final first = renderSnippet(_s('curl http://{{host}}/{{path}}'), {
        'host': 'api.local',
      });
      expect(first.unresolved, ['path']);
      final filled = fillSnippetUnresolved(first.rendered, {'path': 'v1/x'});
      expect(filled, 'curl http://api.local/v1/x');
    });

    test('leaves still-missing tokens intact', () {
      final filled = fillSnippetUnresolved('{{a}} {{b}}', {'a': '1'});
      expect(filled, '1 {{b}}');
    });
  });
}
