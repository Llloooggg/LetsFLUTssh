import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/transfer/unique_name.dart';

void main() {
  group('uniqueSiblingName — POSIX', () {
    test('appends (1) before the extension on first collision', () async {
      final existing = {'/dir/report.txt'};
      final result = await uniqueSiblingName(
        '/dir/report.txt',
        (p) async => existing.contains(p),
        isPosix: true,
      );
      expect(result, '/dir/report (1).txt');
    });

    test('increments suffix until an unused name is found', () async {
      final existing = {
        '/dir/report.txt',
        '/dir/report (1).txt',
        '/dir/report (2).txt',
      };
      final result = await uniqueSiblingName(
        '/dir/report.txt',
        (p) async => existing.contains(p),
        isPosix: true,
      );
      expect(result, '/dir/report (3).txt');
    });

    test('treats only the final extension as an extension', () async {
      final existing = {'/dir/archive.tar.gz'};
      final result = await uniqueSiblingName(
        '/dir/archive.tar.gz',
        (p) async => existing.contains(p),
        isPosix: true,
      );
      // .tar is part of the stem; only .gz is preserved as the suffix.
      expect(result, '/dir/archive.tar (1).gz');
    });

    test('works for extensionless files', () async {
      final existing = {'/dir/README'};
      final result = await uniqueSiblingName(
        '/dir/README',
        (p) async => existing.contains(p),
        isPosix: true,
      );
      expect(result, '/dir/README (1)');
    });

    test('returns the original path when nothing collides', () async {
      final result = await uniqueSiblingName(
        '/dir/fresh.txt',
        (_) async => false,
        isPosix: true,
      );
      expect(result, '/dir/fresh (1).txt');
    });

    test('throws StateError after exhausting maxAttempts', () async {
      expect(
        () => uniqueSiblingName(
          '/dir/x.txt',
          (_) async => true,
          isPosix: true,
          maxAttempts: 3,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
