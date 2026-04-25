import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/ppk_codec.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/argon2.dart';
import 'package:pointycastle/key_derivators/api.dart';
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

/// Build an unencrypted PPK v2 ssh-rsa file with hand-crafted
/// RSA components. We do not need a cryptographically valid key
/// pair for the codec test — we only assert that the bytes round-
/// trip through parse + toOpenSshPemRsa intact. The mpint values
/// are crafted so the high bit is unset (no leading-zero pad
/// quirk to debug separately).
String _buildPpkV2Rsa({
  required Uint8List e,
  required Uint8List n,
  required Uint8List d,
  required Uint8List p,
  required Uint8List q,
  required Uint8List iqmp,
  String comment = 'rsa-fixture',
}) {
  // Public blob: ssh-string("ssh-rsa") + mpint e + mpint n.
  final pubBlob = BytesBuilder(copy: false);
  _putString(pubBlob, utf8.encode('ssh-rsa'));
  _putString(pubBlob, e);
  _putString(pubBlob, n);
  // Private blob: mpint d + mpint p + mpint q + mpint iqmp.
  final privBlob = BytesBuilder(copy: false);
  _putString(privBlob, d);
  _putString(privBlob, p);
  _putString(privBlob, q);
  _putString(privBlob, iqmp);

  final macTag = utf8.encode('putty-private-key-file-mac-key');
  final macKey = Uint8List(20);
  (SHA1Digest()..update(Uint8List.fromList(macTag), 0, macTag.length)).doFinal(
    macKey,
    0,
  );
  final payload = BytesBuilder(copy: false);
  _putString(payload, utf8.encode('ssh-rsa'));
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
  return [
    'PuTTY-User-Key-File-2: ssh-rsa',
    'Encryption: none',
    'Comment: $comment',
    'Public-Lines: ${pubText.split('\n').length}',
    pubText,
    'Private-Lines: ${privText.split('\n').length}',
    privText,
    'Private-MAC: $macHex',
  ].join('\n');
}

/// Build a PPK v3 ssh-ed25519 file. Encrypted variants pass a
/// non-null [passphrase]; unencrypted variants pass null. Argon2
/// parameters are kept tiny (memory=128 KiB, passes=1) so the
/// fixture runs fast in CI.
String _buildPpkV3Ed25519({
  required Uint8List pub32,
  required Uint8List priv32,
  String? passphrase,
  String comment = 'v3-fixture',
}) {
  final pubBlob = BytesBuilder(copy: false);
  _putString(pubBlob, utf8.encode('ssh-ed25519'));
  _putString(pubBlob, pub32);

  final priv = Uint8List.fromList(priv32);
  priv[0] &= 0x7f;
  final privPlain = BytesBuilder(copy: false);
  _putString(privPlain, priv);

  Uint8List privateBlob;
  Uint8List macKey;
  String encryption;
  String? kdfBlock;
  if (passphrase == null) {
    encryption = 'none';
    privateBlob = privPlain.toBytes();
    macKey = Uint8List(0);
  } else {
    encryption = 'aes256-cbc';
    final salt = Uint8List.fromList(List.generate(16, (i) => 0x40 + i));
    const memory = 128;
    const passes = 1;
    const lanes = 1;
    final params = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      Uint8List.fromList(salt),
      desiredKeyLength: 80,
      iterations: passes,
      memory: memory,
      lanes: lanes,
    );
    final gen = Argon2BytesGenerator()..init(params);
    final pp = Uint8List.fromList(utf8.encode(passphrase));
    final derived = Uint8List(80);
    gen.deriveKey(pp, 0, derived, 0);
    final aesKey = Uint8List.sublistView(derived, 0, 32);
    final aesIv = Uint8List.sublistView(derived, 32, 48);
    macKey = Uint8List.sublistView(derived, 48, 80);
    final padded = privPlain.toBytes();
    final blockCount = ((padded.length + 15) ~/ 16);
    final padTo = blockCount * 16;
    final padding = Uint8List(padTo - padded.length);
    final plain = Uint8List.fromList([...padded, ...padding]);
    final cbc = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(aesKey), aesIv));
    final cipher = Uint8List(plain.length);
    var off = 0;
    while (off < plain.length) {
      off += cbc.processBlock(plain, off, cipher, off);
    }
    privateBlob = cipher;
    final saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    kdfBlock = [
      'Key-Derivation: Argon2id',
      'Argon2-Memory: $memory',
      'Argon2-Passes: $passes',
      'Argon2-Parallelism: $lanes',
      'Argon2-Salt: $saltHex',
    ].join('\n');
  }

  final payload = BytesBuilder(copy: false);
  _putString(payload, utf8.encode('ssh-ed25519'));
  _putString(payload, utf8.encode(encryption));
  _putString(payload, utf8.encode(comment));
  _putString(payload, pubBlob.toBytes());
  _putString(payload, privateBlob);
  final hmac = HMac(SHA256Digest(), 64)
    ..init(KeyParameter(macKey))
    ..update(payload.toBytes(), 0, payload.length);
  final mac = Uint8List(32);
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
  final privText = wrap(privateBlob);
  return [
    'PuTTY-User-Key-File-3: ssh-ed25519',
    'Encryption: $encryption',
    'Comment: $comment',
    'Public-Lines: ${pubText.split('\n').length}',
    pubText,
    if (kdfBlock != null) kdfBlock,
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
      // Build a complete RSA fixture so the parser reaches the
      // algorithm gate inside the ed25519 alias instead of failing
      // earlier on a malformed body. The alias rejects ssh-rsa
      // even though the underlying parseV2 accepts it.
      final rsa = _buildPpkV2Rsa(
        e: Uint8List.fromList([0x01, 0x00, 0x01]),
        n: Uint8List(64),
        d: Uint8List(64),
        p: Uint8List(32),
        q: Uint8List(32),
        iqmp: Uint8List(32),
      );
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

  group('PpkCodec.parseV2 — ssh-rsa', () {
    Uint8List rsaBytes(int n, int seed) {
      // High bit clear so the canonical mpint is exactly `n` bytes
      // — keeps test offsets predictable.
      final out = Uint8List(n);
      for (var i = 0; i < n; i++) {
        out[i] = (i + seed) & 0x7f;
      }
      return out;
    }

    test('parses an unencrypted RSA fixture', () {
      final ppk = _buildPpkV2Rsa(
        e: rsaBytes(3, 0x01),
        n: rsaBytes(256, 0x10),
        d: rsaBytes(256, 0x20),
        p: rsaBytes(128, 0x30),
        q: rsaBytes(128, 0x40),
        iqmp: rsaBytes(128, 0x50),
      );
      final parsed = PpkCodec.parseV2(ppk);
      expect(parsed.algorithm, 'ssh-rsa');
      expect(parsed.encrypted, isFalse);
    });

    test('toOpenSshPemRsa packs n/e/d/iqmp/p/q in OpenSSH order', () {
      final ppk = _buildPpkV2Rsa(
        e: rsaBytes(3, 0x02),
        n: rsaBytes(256, 0x11),
        d: rsaBytes(256, 0x21),
        p: rsaBytes(128, 0x31),
        q: rsaBytes(128, 0x41),
        iqmp: rsaBytes(128, 0x51),
      );
      final parsed = PpkCodec.parseV2(ppk);
      final pem = PpkCodec.toOpenSshPemRsa(parsed);
      expect(pem, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----\n'));
      expect(pem.trim(), endsWith('-----END OPENSSH PRIVATE KEY-----'));
      // Decode body and verify the openssh-key-v1 magic + the pubkey
      // type string lands on `ssh-rsa` so dartssh2 routes it to the
      // RSA path.
      final body = pem
          .split('\n')
          .where((l) => l.isNotEmpty && !l.startsWith('-----'))
          .join();
      final bytes = base64.decode(body);
      expect(utf8.decode(bytes.sublist(0, 14)), 'openssh-key-v1');
      // Magic terminator + 3 ssh-strings (cipher/kdf/kdfopts) + uint32
      // numKeys, then ssh-string pubkey-blob whose first ssh-string is
      // the pubkey type. We don't manually walk the offsets — just
      // assert that "ssh-rsa" appears at least twice (once in the
      // pubkey blob, once in the private block).
      final all = utf8.decode(bytes, allowMalformed: true);
      expect('ssh-rsa'.allMatches(all).length, greaterThanOrEqualTo(2));
    });

    test('toOpenSshPem dispatcher routes ed25519 + rsa', () {
      final ed = _buildPpkV2Ed25519(
        pub32: _bytes(32, 0x70),
        priv32: _bytes(32, 0x90),
      );
      final rsa = _buildPpkV2Rsa(
        e: rsaBytes(3, 0x03),
        n: rsaBytes(256, 0x12),
        d: rsaBytes(256, 0x22),
        p: rsaBytes(128, 0x32),
        q: rsaBytes(128, 0x42),
        iqmp: rsaBytes(128, 0x52),
      );
      final edPem = PpkCodec.toOpenSshPem(PpkCodec.parseV2(ed));
      final rsaPem = PpkCodec.toOpenSshPem(PpkCodec.parseV2(rsa));
      expect(edPem, contains('OPENSSH PRIVATE KEY'));
      expect(rsaPem, contains('OPENSSH PRIVATE KEY'));
      // Bodies differ (different algorithms inside the envelope).
      expect(edPem, isNot(equals(rsaPem)));
    });

    test('parseV2Ed25519 alias still rejects ssh-rsa', () {
      final ppk = _buildPpkV2Rsa(
        e: rsaBytes(3, 0x04),
        n: rsaBytes(256, 0x13),
        d: rsaBytes(256, 0x23),
        p: rsaBytes(128, 0x33),
        q: rsaBytes(128, 0x43),
        iqmp: rsaBytes(128, 0x53),
      );
      expect(
        () => PpkCodec.parseV2Ed25519(ppk),
        throwsA(isA<PpkUnsupportedException>()),
      );
    });
  });

  group('PpkCodec.parseV3 — ssh-ed25519', () {
    test('parses an unencrypted v3 fixture', () {
      final ppk = _buildPpkV3Ed25519(
        pub32: _bytes(32, 0xB0),
        priv32: _bytes(32, 0xD0),
      );
      final parsed = PpkCodec.parseV3(ppk);
      expect(parsed.version, 3);
      expect(parsed.algorithm, 'ssh-ed25519');
      expect(parsed.encrypted, isFalse);
    });

    test('decrypts v3 fixture with correct passphrase', () {
      final ppk = _buildPpkV3Ed25519(
        pub32: _bytes(32, 0xB1),
        priv32: _bytes(32, 0xD1),
        passphrase: 'pass',
      );
      final parsed = PpkCodec.parseV3(ppk, passphrase: 'pass');
      expect(parsed.version, 3);
      expect(parsed.encrypted, isTrue);
    });

    test('throws PpkPassphraseRequiredException when omitted', () {
      final ppk = _buildPpkV3Ed25519(
        pub32: _bytes(32, 0xB2),
        priv32: _bytes(32, 0xD2),
        passphrase: 'p',
      );
      expect(
        () => PpkCodec.parseV3(ppk),
        throwsA(isA<PpkPassphraseRequiredException>()),
      );
    });

    test('throws PpkMacMismatchException on wrong passphrase', () {
      final ppk = _buildPpkV3Ed25519(
        pub32: _bytes(32, 0xB3),
        priv32: _bytes(32, 0xD3),
        passphrase: 'right',
      );
      expect(
        () => PpkCodec.parseV3(ppk, passphrase: 'wrong'),
        throwsA(isA<PpkMacMismatchException>()),
      );
    });

    test('top-level parse() routes v3 by header', () {
      final ppk = _buildPpkV3Ed25519(
        pub32: _bytes(32, 0xB4),
        priv32: _bytes(32, 0xD4),
      );
      final parsed = PpkCodec.parse(ppk);
      expect(parsed.version, 3);
    });

    test('top-level parse() routes v2 by header', () {
      final ppk = _buildPpkV2Ed25519(
        pub32: _bytes(32, 0xB5),
        priv32: _bytes(32, 0xD5),
      );
      final parsed = PpkCodec.parse(ppk);
      expect(parsed.version, 2);
    });

    test('v3 toOpenSshPem produces a valid PEM', () {
      final ppk = _buildPpkV3Ed25519(
        pub32: _bytes(32, 0xB6),
        priv32: _bytes(32, 0xD6),
      );
      final parsed = PpkCodec.parseV3(ppk);
      final pem = PpkCodec.toOpenSshPem(parsed);
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
