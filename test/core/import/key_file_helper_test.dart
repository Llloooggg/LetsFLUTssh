import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/key_file_helper.dart';

void main() {
  group('KeyFileHelper', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('key_file_helper_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('returns PEM content for valid private key file', () {
      final keyFile = File('${tmpDir.path}/id_rsa');
      const pemContent = '-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n-----END RSA PRIVATE KEY-----';
      keyFile.writeAsStringSync(pemContent);

      final result = KeyFileHelper.tryReadPemKey(keyFile.path);

      expect(result, pemContent);
    });

    test('returns null for non-PEM file', () {
      final textFile = File('${tmpDir.path}/readme.txt');
      textFile.writeAsStringSync('This is just a text file.');

      final result = KeyFileHelper.tryReadPemKey(textFile.path);

      expect(result, isNull);
    });

    test('returns null for nonexistent file', () {
      final result = KeyFileHelper.tryReadPemKey('${tmpDir.path}/does_not_exist');

      expect(result, isNull);
    });

    test('returns null for file exceeding max size', () {
      final largeFile = File('${tmpDir.path}/large_key');
      // Write content larger than maxKeyFileSize (32768 bytes)
      final content = 'BEGIN PRIVATE KEY\n${'A' * 40000}\nEND PRIVATE KEY';
      largeFile.writeAsStringSync(content);

      final result = KeyFileHelper.tryReadPemKey(largeFile.path);

      expect(result, isNull);
    });

    test('returns content for OpenSSH format key', () {
      final keyFile = File('${tmpDir.path}/id_ed25519');
      const pemContent = '-----BEGIN OPENSSH PRIVATE KEY-----\nb3Blb...\n-----END OPENSSH PRIVATE KEY-----';
      keyFile.writeAsStringSync(pemContent);

      final result = KeyFileHelper.tryReadPemKey(keyFile.path);

      expect(result, pemContent);
    });
  });
}
