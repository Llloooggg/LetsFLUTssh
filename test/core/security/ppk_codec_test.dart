import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/ppk_codec.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/macs/hmac.dart';

/// Build a hand-crafted PPK v2 ssh-ed25519 unencrypted file with a
/// matching MAC. Exposing this as a helper keeps the parser tests
/// self-contained — no external puttygen fixture needed in the repo.
String _buildPpkV2Ed25519({
  required Uint8List pub32,
  required Uint8List priv32,
  String comment = 'fixture',
}) {
  // Public blob: ssh-string("ssh-ed25519") + ssh-string(pub32)
  final pubBlob = BytesBuilder(copy: false);
  _putString(pubBlob, utf8.encode('ssh-ed25519'));
  _putString(pubBlob, pub32);
  // Private blob: mpint(priv) — keep 32 bytes (no leading zero pad)
  // when the high bit is unset. For deterministic tests we generate
  // priv with bit 7 of byte 0 cleared so the canonical encoding is
  // 32 bytes — keeps the fixture's offsets predictable across runs.
  final priv = Uint8List.fromList(priv32);
  priv[0] &= 0x7f;
  final privBlob = BytesBuilder(copy: false);
  _putString(privBlob, priv);

  // MAC = HMAC-SHA-1 keyed with SHA-1("putty-private-key-file-mac-key")
  // over ssh-string(algorithm) + ssh-string(encryption) +
  // ssh-string(comment) + ssh-string(publicBlob) + ssh-string(privateBlob).
  final macTag = utf8.encode('putty-private-key-file-mac-key');
  final macKey = Uint8List(20);
  (SHA1Digest()..update(Uint8List.fromList(macTag), 0, macTag.length)).doFinal(
    macKey,
    0,
  );
  final payload = BytesBuilder(copy: false);
  _putString(payload, utf8.encode('ssh-ed25519'));
  _putString(payload, utf8.encode('none'));
  _putString(payload, utf8.encode(comment));
  _putString(payload, pubBlob.toBytes());
  _putString(payload, privBlob.toBytes());
  final hmac = HMac(SHA1Digest(), 64)
    ..init(KeyParameter(macKey))
    ..update(payload.toBytes(), 0, payload.length);
  final mac = Uint8List(20);
  hmac.doFinal(mac, 0);
  final macHex = mac.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String wrap(Uint8List bytes) {
    final b64 = base64.encode(bytes);
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 64) {
      lines.add(b64.substring(i, b64.length - i < 64 ? b64.length : i + 64));
    }
    return lines.join('\n');
  }

  final pubText = wrap(pubBlob.toBytes());
  final privText = wrap(privBlob.toBytes());
  final pubLineCount = pubText.split('\n').length;
  final privLineCount = privText.split('\n').length;

  return [
    'PuTTY-User-Key-File-2: ssh-ed25519',
    'Encryption: none',
    'Comment: $comment',
    'Public-Lines: $pubLineCount',
    pubText,
    'Private-Lines: $privLineCount',
    privText,
    'Private-MAC: $macHex',
  ].join('\n');
}

/// Build an encrypted PPK v2 ssh-ed25519 file. The encryption uses
/// the same SHA-1-derived AES-256 / zero-IV / HMAC-SHA-1-with-
/// passphrase scheme PuTTY ships with v2.
String _buildEncryptedPpkV2Ed25519({
  required Uint8List pub32,
  required Uint8List priv32,
  required String passphrase,
  String comment = 'enc',
}) {
  final pubBlob = BytesBuilder(copy: false);
  _putString(pubBlob, utf8.encode('ssh-ed25519'));
  _putString(pubBlob, pub32);

  final priv = Uint8List.fromList(priv32);
  priv[0] &= 0x7f;
  final privPlain = BytesBuilder(copy: false);
  _putString(privPlain, priv);
  // Pad to 16 bytes for AES-CBC.
  final padded = privPlain.toBytes();
  final blockCount = ((padded.length + 15) ~/ 16);
  final padTo = blockCount * 16;
  final padding = Uint8List(padTo - padded.length); // zero pad — fine for v2
  final plaintext = Uint8List.fromList([...padded, ...padding]);

  final pp = utf8.encode(passphrase);
  final keyBuilder = BytesBuilder(copy: false);
  for (var c = 0; c < 2; c++) {
    final input = Uint8List(4 + pp.length)
      ..[3] = c
      ..setRange(4, 4 + pp.length, pp);
    final hash = Uint8List(20);
    (SHA1Digest()..update(input, 0, input.length)).doFinal(hash, 0);
    keyBuilder.add(hash);
  }
  final aesKey = Uint8List.sublistView(keyBuilder.toBytes(), 0, 32);
  final cbc = CBCBlockCipher(AESEngine())
    ..init(true, ParametersWithIV(KeyParameter(aesKey), Uint8List(16)));
  final ciphertext = Uint8List(plaintext.length);
  var off = 0;
  while (off < plaintext.length) {
    off += cbc.processBlock(plaintext, off, ciphertext, off);
  }

  final macTag = utf8.encode('putty-private-key-file-mac-key');
  final macKey = Uint8List(20);
  final macKeyDigest = SHA1Digest()
    ..update(Uint8List.fromList(macTag), 0, macTag.length)
    ..update(Uint8List.fromList(pp), 0, pp.length);
  macKeyDigest.doFinal(macKey, 0);
  final payload = BytesBuilder(copy: false);
  _putString(payload, utf8.encode('ssh-ed25519'));
  _putString(payload, utf8.encode('aes256-cbc'));
  _putString(payload, utf8.encode(comment));
  _putString(payload, pubBlob.toBytes());
  _putString(payload, ciphertext);
  final hmac = HMac(SHA1Digest(), 64)
    ..init(KeyParameter(macKey))
    ..update(payload.toBytes(), 0, payload.length);
  final mac = Uint8List(20);
  hmac.doFinal(mac, 0);
  final macHex = mac.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String wrap(Uint8List bytes) {
    final b64 = base64.encode(bytes);
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 64) {
      lines.add(b64.substring(i, b64.length - i < 64 ? b64.length : i + 64));
    }
    return lines.join('\n');
  }

  final pubText = wrap(pubBlob.toBytes());
  final privText = wrap(ciphertext);
  return [
    'PuTTY-User-Key-File-2: ssh-ed25519',
    'Encryption: aes256-cbc',
    'Comment: $comment',
    'Public-Lines: ${pubText.split('\n').length}',
    pubText,
    'Private-Lines: ${privText.split('\n').length}',
    privText,
    'Private-MAC: $macHex',
  ].join('\n');
}

void _putString(BytesBuilder out, List<int> bytes) {
  out.addByte((bytes.length >> 24) & 0xff);
  out.addByte((bytes.length >> 16) & 0xff);
  out.addByte((bytes.length >> 8) & 0xff);
  out.addByte(bytes.length & 0xff);
  out.add(bytes);
}

Uint8List _bytes(int length, int seed) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = (i + seed) & 0xff;
  }
  return out;
}

void main() {
  group('PpkCodec.looksLikePpk', () {
    test('matches v2 header', () {
      expect(
        PpkCodec.looksLikePpk('PuTTY-User-Key-File-2: ssh-ed25519\nfoo'),
        isTrue,
      );
    });

    test('matches v3 header', () {
      expect(
        PpkCodec.looksLikePpk('PuTTY-User-Key-File-3: ssh-ed25519\nfoo'),
        isTrue,
      );
    });

    test('rejects PEM key', () {
      expect(
        PpkCodec.looksLikePpk('-----BEGIN OPENSSH PRIVATE KEY-----\n...'),
        isFalse,
      );
    });
  });

  group('PpkCodec.parseUnencryptedV2Ed25519', () {
    test('round-trips a hand-crafted fixture', () {
      final pub = _bytes(32, 0x10);
      final priv = _bytes(32, 0x40);
      final ppk = _buildPpkV2Ed25519(pub32: pub, priv32: priv);
      final parsed = PpkCodec.parseUnencryptedV2Ed25519(ppk);
      expect(parsed.algorithm, 'ssh-ed25519');
      expect(parsed.encryption, 'none');
      expect(parsed.comment, 'fixture');
      expect(parsed.version, 2);
    });

    test('rejects v3 with a targeted exception', () {
      const v3 = 'PuTTY-User-Key-File-3: ssh-ed25519\nEncryption: none\n';
      expect(
        () => PpkCodec.parseUnencryptedV2Ed25519(v3),
        throwsA(isA<PpkUnsupportedException>()),
      );
    });

    test('rejects ssh-rsa with a targeted exception', () {
      const rsa =
          'PuTTY-User-Key-File-2: ssh-rsa\n'
          'Encryption: none\n'
          'Comment: x\n';
      expect(
        () => PpkCodec.parseUnencryptedV2Ed25519(rsa),
        throwsA(isA<PpkUnsupportedException>()),
      );
    });

    test('rejects encrypted variants with a targeted exception', () {
      const enc =
          'PuTTY-User-Key-File-2: ssh-ed25519\n'
          'Encryption: aes256-cbc\n'
          'Comment: x\n';
      expect(
        () => PpkCodec.parseUnencryptedV2Ed25519(enc),
        throwsA(isA<PpkUnsupportedException>()),
      );
    });

    test('throws PpkParseException on a non-PPK file', () {
      expect(
        () => PpkCodec.parseUnencryptedV2Ed25519(
          '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
        throwsA(isA<PpkParseException>()),
      );
    });

    test('throws PpkMacMismatchException when MAC tampered', () {
      final pub = _bytes(32, 0x20);
      final priv = _bytes(32, 0x60);
      final raw = _buildPpkV2Ed25519(pub32: pub, priv32: priv);
      // Flip a byte in the trailing MAC line.
      final lines = raw.split('\n');
      final last = lines.last;
      final fudged =
          last.substring(0, last.length - 1) + (last.endsWith('0') ? '1' : '0');
      lines[lines.length - 1] = fudged;
      expect(
        () => PpkCodec.parseUnencryptedV2Ed25519(lines.join('\n')),
        throwsA(isA<PpkMacMismatchException>()),
      );
    });
  });

  group('PpkCodec.parseV2Ed25519 — encrypted', () {
    test('decrypts with the correct passphrase', () {
      final pub = _bytes(32, 0xA0);
      final priv = _bytes(32, 0xC0);
      final ppk = _buildEncryptedPpkV2Ed25519(
        pub32: pub,
        priv32: priv,
        passphrase: 's3cret',
      );
      final parsed = PpkCodec.parseV2Ed25519(ppk, passphrase: 's3cret');
      expect(parsed.encryption, 'aes256-cbc');
      expect(parsed.encrypted, isTrue);
      expect(parsed.algorithm, 'ssh-ed25519');
    });

    test('throws PpkPassphraseRequiredException when passphrase omitted', () {
      final pub = _bytes(32, 0xA1);
      final priv = _bytes(32, 0xC1);
      final ppk = _buildEncryptedPpkV2Ed25519(
        pub32: pub,
        priv32: priv,
        passphrase: 'pass',
      );
      expect(
        () => PpkCodec.parseV2Ed25519(ppk),
        throwsA(isA<PpkPassphraseRequiredException>()),
      );
    });

    test('throws PpkMacMismatchException on wrong passphrase', () {
      final pub = _bytes(32, 0xA2);
      final priv = _bytes(32, 0xC2);
      final ppk = _buildEncryptedPpkV2Ed25519(
        pub32: pub,
        priv32: priv,
        passphrase: 'right',
      );
      expect(
        () => PpkCodec.parseV2Ed25519(ppk, passphrase: 'wrong'),
        throwsA(isA<PpkMacMismatchException>()),
      );
    });

    test('parseUnencryptedV2Ed25519 still rejects encrypted files', () {
      final pub = _bytes(32, 0xA3);
      final priv = _bytes(32, 0xC3);
      final ppk = _buildEncryptedPpkV2Ed25519(
        pub32: pub,
        priv32: priv,
        passphrase: 'p',
      );
      expect(
        () => PpkCodec.parseUnencryptedV2Ed25519(ppk),
        throwsA(isA<PpkUnsupportedException>()),
      );
    });

    test('decrypted blob converts to a valid OpenSSH PEM', () {
      final pub = _bytes(32, 0xA4);
      final priv = _bytes(32, 0xC4);
      final ppk = _buildEncryptedPpkV2Ed25519(
        pub32: pub,
        priv32: priv,
        passphrase: 'pp',
      );
      final parsed = PpkCodec.parseV2Ed25519(ppk, passphrase: 'pp');
      final pem = PpkCodec.toOpenSshPemEd25519(parsed);
      expect(pem, contains('OPENSSH PRIVATE KEY'));
    });
  });

  group('PpkCodec.toOpenSshPemEd25519', () {
    test('produces a PEM with the correct armor', () {
      final pub = _bytes(32, 0x70);
      final priv = _bytes(32, 0x90);
      final ppk = _buildPpkV2Ed25519(pub32: pub, priv32: priv);
      final parsed = PpkCodec.parseUnencryptedV2Ed25519(ppk);
      final pem = PpkCodec.toOpenSshPemEd25519(parsed);
      expect(pem, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----\n'));
      expect(pem.trim(), endsWith('-----END OPENSSH PRIVATE KEY-----'));
      // Sanity-check the body decodes as base64 and starts with the
      // openssh-key-v1 magic so dartssh2's parser will accept it.
      final body = pem
          .split('\n')
          .where((l) => l.isNotEmpty && !l.startsWith('-----'))
          .join();
      final bytes = base64.decode(body);
      // Magic is "openssh-key-v1" + NUL terminator (not space).
      expect(utf8.decode(bytes.sublist(0, 14)), 'openssh-key-v1');
      expect(bytes[14], 0);
    });
  });
}
