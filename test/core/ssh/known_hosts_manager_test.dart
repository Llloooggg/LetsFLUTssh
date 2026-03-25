import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('known_hosts_mgr_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void mockPathProvider() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  }

  group('KnownHostsManager with real file I/O', () {
    test('load creates manager with empty hosts', () async {
      mockPathProvider();
      final manager = KnownHostsManager();
      await manager.load();
      // No file exists, should load without error
    });

    test('load reads existing known_hosts file', () async {
      mockPathProvider();
      final file = File('${tempDir.path}/known_hosts');
      await file.writeAsString('myhost.com:22 ssh-rsa AAAA\n');

      final manager = KnownHostsManager();
      await manager.load();

      // Verify the known host by providing matching key
      final result = await manager.verify(
        'myhost.com', 22, 'ssh-rsa', base64Decode('AAAA'),
      );
      expect(result, isTrue);
    });

    test('verify unknown host without callback rejects', () async {
      mockPathProvider();
      final manager = KnownHostsManager();
      await manager.load();

      final result = await manager.verify('unknown.com', 22, 'ssh-rsa', [1, 2, 3]);
      expect(result, isFalse);
    });

    test('verify unknown host with accepting callback adds to file', () async {
      mockPathProvider();
      final manager = KnownHostsManager();
      manager.onUnknownHost = (host, port, keyType, fingerprint) async => true;
      await manager.load();

      final result = await manager.verify('newhost.com', 22, 'ssh-ed25519', [1, 2, 3]);
      expect(result, isTrue);

      // Verify file was written
      final file = File('${tempDir.path}/known_hosts');
      expect(file.existsSync(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('newhost.com:22'));
      expect(content, contains('ssh-ed25519'));
    });

    test('verify unknown host with rejecting callback rejects', () async {
      mockPathProvider();
      final manager = KnownHostsManager();
      manager.onUnknownHost = (host, port, keyType, fingerprint) async => false;
      await manager.load();

      final result = await manager.verify('newhost.com', 22, 'ssh-rsa', [1, 2, 3]);
      expect(result, isFalse);
    });

    test('verify known host with matching key accepts silently', () async {
      mockPathProvider();
      final keyBytes = [10, 20, 30];
      final file = File('${tempDir.path}/known_hosts');
      await file.writeAsString(
        'server.com:22 ssh-rsa ${base64Encode(keyBytes)}\n',
      );

      final manager = KnownHostsManager();
      await manager.load();

      final result = await manager.verify('server.com', 22, 'ssh-rsa', keyBytes);
      expect(result, isTrue);
    });

    test('verify known host with changed key rejects without callback', () async {
      mockPathProvider();
      final file = File('${tempDir.path}/known_hosts');
      await file.writeAsString(
        'server.com:22 ssh-rsa ${base64Encode([1, 2, 3])}\n',
      );

      final manager = KnownHostsManager();
      await manager.load();

      final result = await manager.verify('server.com', 22, 'ssh-rsa', [4, 5, 6]);
      expect(result, isFalse);
    });

    test('verify known host with changed key and accepting callback updates', () async {
      mockPathProvider();
      final file = File('${tempDir.path}/known_hosts');
      await file.writeAsString(
        'server.com:22 ssh-rsa ${base64Encode([1, 2, 3])}\n',
      );

      final manager = KnownHostsManager();
      String? receivedFingerprint;
      manager.onHostKeyChanged = (host, port, keyType, fingerprint) async {
        receivedFingerprint = fingerprint;
        return true;
      };
      await manager.load();

      final result = await manager.verify('server.com', 22, 'ssh-rsa', [4, 5, 6]);
      expect(result, isTrue);
      expect(receivedFingerprint, startsWith('SHA256:'));

      // Verify new key was saved
      final content = await file.readAsString();
      expect(content, contains(base64Encode([4, 5, 6])));
    });

    test('load is idempotent', () async {
      mockPathProvider();
      final manager = KnownHostsManager();
      await manager.load();
      await manager.load(); // should not re-parse
    });

    test('load skips comment and empty lines', () async {
      mockPathProvider();
      final file = File('${tempDir.path}/known_hosts');
      await file.writeAsString(
        '# This is a comment\n'
        '\n'
        'host.com:22 ssh-rsa S0VZ\n'
        '\n',
      );

      final manager = KnownHostsManager();
      await manager.load();

      // Only the valid line should be parsed
      final result = await manager.verify(
        'host.com', 22, 'ssh-rsa', base64Decode('S0VZ'),
      );
      expect(result, isTrue);
    });

    test('callback receives correct host, port, keyType, fingerprint', () async {
      mockPathProvider();
      final manager = KnownHostsManager();
      String? capturedHost;
      int? capturedPort;
      String? capturedKeyType;
      String? capturedFingerprint;

      manager.onUnknownHost = (host, port, keyType, fingerprint) async {
        capturedHost = host;
        capturedPort = port;
        capturedKeyType = keyType;
        capturedFingerprint = fingerprint;
        return true;
      };
      await manager.load();

      await manager.verify('test.org', 2222, 'ssh-ed25519', [42, 43, 44]);
      expect(capturedHost, 'test.org');
      expect(capturedPort, 2222);
      expect(capturedKeyType, 'ssh-ed25519');
      expect(capturedFingerprint, startsWith('SHA256:'));
    });
  });
}
