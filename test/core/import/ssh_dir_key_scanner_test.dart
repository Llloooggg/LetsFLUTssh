import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/ssh_dir_key_scanner.dart';

void main() {
  group('SshDirKeyScanner', () {
    SshDirKeyScanner scannerWith({
      required List<String> files,
      required Map<String, String?> pemByPath,
    }) {
      return SshDirKeyScanner(
        listDir: (_) => files,
        readPem: (path) => pemByPath[path],
      );
    }

    test('returns empty list when directory has no files', () {
      final result = scannerWith(
        files: const [],
        pemByPath: const {},
      ).scan('/home/u/.ssh');
      expect(result, isEmpty);
    });

    test('includes PEM private-key files', () {
      final result = scannerWith(
        files: ['/home/u/.ssh/id_ed25519', '/home/u/.ssh/work_rsa'],
        pemByPath: {
          '/home/u/.ssh/id_ed25519': 'PRIVATE KEY ed',
          '/home/u/.ssh/work_rsa': 'PRIVATE KEY rsa',
        },
      ).scan('/home/u/.ssh');
      expect(result.map((k) => k.suggestedLabel), ['id_ed25519', 'work_rsa']);
      expect(result.map((k) => k.pem), ['PRIVATE KEY ed', 'PRIVATE KEY rsa']);
    });

    test('skips .pub, known_hosts, authorized_keys, config', () {
      final result = scannerWith(
        files: [
          '/home/u/.ssh/id_ed25519',
          '/home/u/.ssh/id_ed25519.pub',
          '/home/u/.ssh/known_hosts',
          '/home/u/.ssh/known_hosts.old',
          '/home/u/.ssh/authorized_keys',
          '/home/u/.ssh/authorized_keys2',
          '/home/u/.ssh/config',
        ],
        pemByPath: {
          '/home/u/.ssh/id_ed25519': 'PRIVATE KEY',
          // Even if a forbidden path somehow has PRIVATE KEY, skip it.
          '/home/u/.ssh/known_hosts': 'PRIVATE KEY leaked',
        },
      ).scan('/home/u/.ssh');
      expect(result.map((k) => k.suggestedLabel), ['id_ed25519']);
    });

    test('omits files that fail the PEM check', () {
      final result = scannerWith(
        files: [
          '/home/u/.ssh/real_key',
          '/home/u/.ssh/garbage',
          '/home/u/.ssh/too_big',
        ],
        pemByPath: {
          '/home/u/.ssh/real_key': 'PRIVATE KEY',
          '/home/u/.ssh/garbage': null,
          '/home/u/.ssh/too_big': null,
        },
      ).scan('/home/u/.ssh');
      expect(result.map((k) => k.suggestedLabel), ['real_key']);
    });

    test('results are sorted by path', () {
      final result = scannerWith(
        files: [
          '/home/u/.ssh/z_last',
          '/home/u/.ssh/a_first',
          '/home/u/.ssh/m_middle',
        ],
        pemByPath: {
          '/home/u/.ssh/z_last': 'PRIVATE KEY',
          '/home/u/.ssh/a_first': 'PRIVATE KEY',
          '/home/u/.ssh/m_middle': 'PRIVATE KEY',
        },
      ).scan('/home/u/.ssh');
      expect(result.map((k) => k.suggestedLabel), [
        'a_first',
        'm_middle',
        'z_last',
      ]);
    });

    test('Windows-style paths resolve basename correctly', () {
      final result = scannerWith(
        files: [r'C:\Users\u\.ssh\id_rsa'],
        pemByPath: {r'C:\Users\u\.ssh\id_rsa': 'PRIVATE KEY'},
      ).scan(r'C:\Users\u\.ssh');
      expect(result.single.suggestedLabel, 'id_rsa');
    });
  });
}
