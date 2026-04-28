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

    test('returns PEM content for valid private key file', () async {
      final keyFile = File('${tmpDir.path}/id_rsa');
      const pemContent =
          '-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n-----END RSA PRIVATE KEY-----';
      keyFile.writeAsStringSync(pemContent);

      final result = await KeyFileHelper.tryReadPemKey(keyFile.path);

      expect(result, pemContent);
    });

    test('returns null for non-PEM file', () async {
      final textFile = File('${tmpDir.path}/readme.txt');
      textFile.writeAsStringSync('This is just a text file.');

      final result = await KeyFileHelper.tryReadPemKey(textFile.path);

      expect(result, isNull);
    });

    test('returns null for nonexistent file', () async {
      final result = await KeyFileHelper.tryReadPemKey(
        '${tmpDir.path}/does_not_exist',
      );

      expect(result, isNull);
    });

    test('returns null for file exceeding max size', () async {
      final largeFile = File('${tmpDir.path}/large_key');
      // Write content larger than maxKeyFileSize (32768 bytes)
      final content = 'BEGIN PRIVATE KEY\n${'A' * 40000}\nEND PRIVATE KEY';
      largeFile.writeAsStringSync(content);

      final result = await KeyFileHelper.tryReadPemKey(largeFile.path);

      expect(result, isNull);
    });

    test('returns content for OpenSSH format key', () async {
      final keyFile = File('${tmpDir.path}/id_ed25519');
      const pemContent =
          '-----BEGIN OPENSSH PRIVATE KEY-----\nb3Blb...\n-----END OPENSSH PRIVATE KEY-----';
      keyFile.writeAsStringSync(pemContent);

      final result = await KeyFileHelper.tryReadPemKey(keyFile.path);

      expect(result, pemContent);
    });
  });

  // The Dart `KeyFileHelper.isEncryptedPem` group retired alongside
  // the move of the binary-format scan into `lfs_core::keys::
  // is_encrypted_pem`. Under flutter_test the FRB native lib is not
  // loaded so calling the shim throws synchronously; equivalent
  // coverage (PKCS#1 markers, PKCS#8 armor, OpenSSH KDF-name field,
  // malformed body fallthrough) lives in `lfs_core::keys::tests`.

  group('KeyFileHelper.isSuspiciousPath', () {
    test('flags `..` segments regardless of platform separator', () {
      expect(KeyFileHelper.isSuspiciousPath('~/.ssh/../../etc/shadow'), isTrue);
      expect(KeyFileHelper.isSuspiciousPath('../../../etc'), isTrue);
      expect(KeyFileHelper.isSuspiciousPath(r'C:\Users\..\..\Windows'), isTrue);
    });

    test('passes benign paths with no traversal', () {
      expect(KeyFileHelper.isSuspiciousPath('~/.ssh/id_rsa'), isFalse);
      expect(KeyFileHelper.isSuspiciousPath('/etc/ssh/keys/id'), isFalse);
      expect(KeyFileHelper.isSuspiciousPath('relative/path/id'), isFalse);
    });
  });

  group('KeyFileHelper.basename', () {
    test('extracts filename from POSIX and Windows paths', () {
      expect(KeyFileHelper.basename('/home/user/.ssh/id_rsa'), 'id_rsa');
      expect(KeyFileHelper.basename(r'C:\Users\u\.ssh\id_rsa'), 'id_rsa');
      expect(KeyFileHelper.basename('id_rsa'), 'id_rsa');
      expect(KeyFileHelper.basename(''), '');
    });
  });
}
