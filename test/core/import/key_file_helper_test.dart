import 'dart:convert' show base64;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/import/key_file_helper.dart';

/// Build an OpenSSH private key PEM whose binary body announces [kdfName]
/// as the KDF. `kdfName` of `'none'` produces an unencrypted key frame;
/// anything else (typically `bcrypt`) marks it as passphrase-protected.
String _buildOpensshPem(String kdfName) {
  const magic = 'openssh-key-v1';
  final body = <int>[
    ...magic.codeUnits,
    0, // null terminator
    0, 0, 0, kdfName.length, // kdfName length (big-endian u32)
    ...kdfName.codeUnits,
    // Rest of the frame is irrelevant for the encryption-state sniff —
    // add a handful of bytes so the decoder doesn't reject a truncated
    // preamble as malformed.
    0, 0, 0, 0,
    0, 0, 0, 0,
  ];
  return '-----BEGIN OPENSSH PRIVATE KEY-----\n'
      '${base64.encode(body)}\n'
      '-----END OPENSSH PRIVATE KEY-----';
}

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

  group('KeyFileHelper.isEncryptedPem', () {
    test('detects legacy PKCS#1 encrypted header', () {
      // openssl-style encrypted RSA — `Proc-Type: 4,ENCRYPTED` with a
      // `DEK-Info` line. Either marker on its own is enough to flag the
      // key as requiring a passphrase.
      const pem =
          '-----BEGIN RSA PRIVATE KEY-----\n'
          'Proc-Type: 4,ENCRYPTED\n'
          'DEK-Info: AES-128-CBC,ABC\n'
          'Base64body\n'
          '-----END RSA PRIVATE KEY-----';
      expect(KeyFileHelper.isEncryptedPem(pem), isTrue);
    });

    test('detects PKCS#8 encrypted armor', () {
      const pem =
          '-----BEGIN ENCRYPTED PRIVATE KEY-----\nb64\n'
          '-----END ENCRYPTED PRIVATE KEY-----';
      expect(KeyFileHelper.isEncryptedPem(pem), isTrue);
    });

    test('detects OpenSSH bcrypt-wrapped body', () {
      // `ssh-keygen -p` announces `bcrypt` as the KDF in the binary frame —
      // the helper decodes the base64 body to read that field, so the test
      // builds a realistic frame instead of pasting pre-computed base64.
      final pem = _buildOpensshPem('bcrypt');
      expect(KeyFileHelper.isEncryptedPem(pem), isTrue);
    });

    test('plain OpenSSH key (KDF=none) is not flagged', () {
      final pem = _buildOpensshPem('none');
      expect(KeyFileHelper.isEncryptedPem(pem), isFalse);
    });

    test('malformed OpenSSH body is not flagged as encrypted', () {
      // Non-base64 garbage between the armor lines — the decoder must
      // gracefully return false (treat as unknown/unencrypted) rather
      // than throwing. Wrong answer here would false-positive every
      // corrupt key as "needs passphrase".
      const pem =
          '-----BEGIN OPENSSH PRIVATE KEY-----\n'
          'not-valid-base64!!!\n'
          '-----END OPENSSH PRIVATE KEY-----';
      expect(KeyFileHelper.isEncryptedPem(pem), isFalse);
    });

    test('plain PKCS#1 key is not flagged', () {
      const pem =
          '-----BEGIN RSA PRIVATE KEY-----\nbody\n-----END RSA PRIVATE KEY-----';
      expect(KeyFileHelper.isEncryptedPem(pem), isFalse);
    });
  });

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
