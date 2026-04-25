import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/argon2.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/macs/hmac.dart';

/// Parsed PuTTY Private Key file.
///
/// The codec parses the textual envelope, validates the MAC, and
/// returns the public + private blobs in their on-the-wire SSH form.
/// `version`, `algorithm`, and `encrypted` are surfaced so the caller
/// can drive the right error message when an unsupported variant is
/// imported (the parser still recognises the file as PPK and points
/// at the specific dimension we don't handle yet).
class PpkKey {
  final int version; // 2 or 3
  final String algorithm; // ssh-ed25519 / ssh-rsa / etc.
  final String encryption; // 'none' / 'aes256-cbc'
  final String comment;
  final Uint8List publicBlob;
  final Uint8List privateBlob;

  PpkKey({
    required this.version,
    required this.algorithm,
    required this.encryption,
    required this.comment,
    required this.publicBlob,
    required this.privateBlob,
  });

  bool get encrypted => encryption != 'none';
}

/// Pure-Dart PuTTY Private Key codec.
///
/// **v1 scope:** parse + verify PPK v2 `ssh-ed25519` **unencrypted**.
/// Other variants are recognised at parse time and surface a typed
/// exception so the importer can show "this file is a PPK but the
/// build does not support `<reason>` yet" instead of swallowing it
/// as a generic "not a key" error.
///
/// Reference: <https://the.earth.li/~sgtatham/putty/0.78/htmldoc/AppendixC.html>.
class PpkCodec {
  PpkCodec._();

  /// MAC key tag for unencrypted PPK v2 — verbatim from PuTTY source.
  /// For encrypted v2 the same tag is concatenated with the
  /// passphrase; we do not support encrypted yet so the constant
  /// stays unused outside the unencrypted path.
  static const _v2MacTag = 'putty-private-key-file-mac-key';

  /// Quick sniff: does [text] look like a PPK file at all? Used by
  /// the import dispatcher to route .ppk before falling through to
  /// PEM detection. Cheap — first-line peek only.
  static bool looksLikePpk(String text) {
    return text.startsWith('PuTTY-User-Key-File-2:') ||
        text.startsWith('PuTTY-User-Key-File-3:');
  }

  /// Algorithms supported in this build.
  static const _supportedAlgorithms = {'ssh-ed25519', 'ssh-rsa'};

  /// Hard ceiling on Argon2 memory cost — 1 GiB. A pathologically
  /// crafted PPK file could otherwise drive Dart out of memory
  /// before the parser even started looking at the body. Real
  /// puttygen v3 defaults to 8 MiB; 1 GiB is generous headroom.
  static const int _argon2MaxMemoryKiB = 1024 * 1024;

  /// Top-level dispatcher — chooses v2 vs v3 by header. Surface
  /// passes through to either [parseV2] or [parseV3] depending on
  /// the file's first line. The importer dialog calls this single
  /// entry point so it does not have to peek the version itself.
  static PpkKey parse(String text, {String? passphrase}) {
    if (text.startsWith('PuTTY-User-Key-File-3:')) {
      return parseV3(text, passphrase: passphrase);
    }
    return parseV2(text, passphrase: passphrase);
  }

  /// Parse + MAC-verify a PPK v3 file with an optional passphrase.
  ///
  /// v3 differs from v2 in three important places:
  ///
  /// 1. **KDF.** Encrypted v3 derives the AES-256 key, IV, and
  ///    HMAC key together via Argon2id (params from the
  ///    `Argon2-Memory` / `Argon2-Passes` / `Argon2-Parallelism`
  ///    / `Argon2-Salt` headers). v3 unencrypted does NOT KDF —
  ///    the MAC key is the empty string.
  /// 2. **MAC.** HMAC-SHA-256 instead of HMAC-SHA-1.
  /// 3. **MAC payload.** Same ssh-string-prefixed concatenation
  ///    of `algorithm`, `encryption`, `comment`, `publicBlob`,
  ///    `privateBlob` (encrypted bytes for encrypted files).
  static PpkKey parseV3(String text, {String? passphrase}) {
    return _parseV3(text, passphrase: passphrase);
  }

  /// Parse + MAC-verify a PPK v2 file with an optional passphrase.
  ///
  /// Supports ssh-ed25519 and ssh-rsa today. When the file's
  /// `Encryption: aes256-cbc` header is present, the caller must
  /// supply a non-empty [passphrase]; the codec derives the AES-256
  /// key via PuTTY's SHA-1 chain (no PBKDF2 — the v2 format is what
  /// it is, v3 fixes this with Argon2id) and decrypts the private
  /// blob before the standard MAC + parse path runs.
  ///
  /// [passphrase] is required when the file is encrypted and ignored
  /// when it isn't. Wrong passphrase surfaces as
  /// [PpkMacMismatchException] — the encryption is malleable (PuTTY
  /// uses a zero IV) so the only honest "wrong passphrase" signal
  /// is the MAC failing on the gibberish that decryption produced.
  static PpkKey parseV2(String text, {String? passphrase}) {
    return _parseV2(text, passphrase: passphrase);
  }

  /// Convenience alias targeting ed25519 keys specifically. Throws
  /// [PpkUnsupportedException] for other algorithms even when the
  /// codec otherwise supports them — useful for callers that only
  /// have an ed25519 path wired downstream.
  static PpkKey parseV2Ed25519(String text, {String? passphrase}) {
    final key = _parseV2(text, passphrase: passphrase);
    if (key.algorithm != 'ssh-ed25519') {
      throw PpkUnsupportedException(
        key.algorithm,
        'parseV2Ed25519 only accepts ssh-ed25519',
      );
    }
    return key;
  }

  /// Backwards-compatible entry point — equivalent to
  /// `parseV2Ed25519(text)` and rejects encrypted variants. Kept so
  /// callers that explicitly only want the unencrypted path keep a
  /// short signature.
  static PpkKey parseUnencryptedV2Ed25519(String text) {
    final key = _parseV2(text, passphrase: null, allowEncrypted: false);
    if (key.algorithm != 'ssh-ed25519') {
      throw PpkUnsupportedException(
        key.algorithm,
        'parseUnencryptedV2Ed25519 only accepts ssh-ed25519',
      );
    }
    return key;
  }

  static PpkKey _parseV2(
    String text, {
    String? passphrase,
    bool allowEncrypted = true,
  }) {
    final headers = <String, String>{};
    final lines = const LineSplitter().convert(text);

    var idx = 0;
    String? readHeader(String name) {
      if (idx >= lines.length) return null;
      final line = lines[idx];
      final colon = line.indexOf(':');
      if (colon < 0) return null;
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      if (key != name) return null;
      headers[key] = value;
      idx++;
      return value;
    }

    final algorithm = readHeader('PuTTY-User-Key-File-2');
    if (algorithm == null) {
      // Maybe v3 — produce a targeted error so the UI surfaces
      // "v3 not supported" rather than "not a key".
      if (text.startsWith('PuTTY-User-Key-File-3:')) {
        throw const PpkUnsupportedException(
          'v3',
          'PPK v3 not supported in this build',
        );
      }
      throw const PpkParseException('Not a PPK file');
    }
    if (!_supportedAlgorithms.contains(algorithm)) {
      throw PpkUnsupportedException(
        algorithm,
        'PPK algorithm "$algorithm" not supported in this build',
      );
    }
    final encryption = readHeader('Encryption');
    if (encryption == null) {
      throw const PpkParseException('Missing Encryption header');
    }
    if (encryption != 'none' && encryption != 'aes256-cbc') {
      throw PpkUnsupportedException(
        encryption,
        'PPK encryption "$encryption" not supported in this build',
      );
    }
    if (encryption != 'none' && !allowEncrypted) {
      // The unencrypted-only entry point was used on an encrypted
      // file — surface as Unsupported so the caller can route the
      // user through the passphrase-aware entry point on retry.
      throw PpkUnsupportedException(
        encryption,
        'Encrypted PPK files require the passphrase-aware entry point',
      );
    }
    if (encryption != 'none' && (passphrase == null || passphrase.isEmpty)) {
      throw const PpkPassphraseRequiredException();
    }
    final comment = readHeader('Comment') ?? '';
    final publicLines = readHeader('Public-Lines');
    if (publicLines == null) {
      throw const PpkParseException('Missing Public-Lines header');
    }
    final publicLineCount = int.tryParse(publicLines);
    if (publicLineCount == null || publicLineCount < 1) {
      throw const PpkParseException('Bad Public-Lines value');
    }
    final publicB64 = StringBuffer();
    for (var i = 0; i < publicLineCount; i++) {
      if (idx >= lines.length) {
        throw const PpkParseException('Truncated public block');
      }
      publicB64.write(lines[idx++]);
    }
    final privateLines = readHeader('Private-Lines');
    if (privateLines == null) {
      throw const PpkParseException('Missing Private-Lines header');
    }
    final privateLineCount = int.tryParse(privateLines);
    if (privateLineCount == null || privateLineCount < 1) {
      throw const PpkParseException('Bad Private-Lines value');
    }
    final privateB64 = StringBuffer();
    for (var i = 0; i < privateLineCount; i++) {
      if (idx >= lines.length) {
        throw const PpkParseException('Truncated private block');
      }
      privateB64.write(lines[idx++]);
    }
    final macHeader = readHeader('Private-MAC');
    if (macHeader == null) {
      throw const PpkParseException('Missing Private-MAC header');
    }

    final publicBlob = base64.decode(publicB64.toString());
    final encryptedPrivate = base64.decode(privateB64.toString());

    // MAC is computed over the **encrypted** private blob in v2 —
    // verify before we decrypt so a corrupted file doesn't waste a
    // CBC pass and so the MAC failure is the canonical wrong-
    // passphrase signal (decrypted gibberish hashes uniformly).
    _verifyV2Mac(
      algorithm: algorithm,
      encryption: encryption,
      passphrase: encryption == 'none' ? null : passphrase,
      comment: comment,
      publicBlob: publicBlob,
      privateBlob: encryptedPrivate,
      macHex: macHeader,
    );

    final privateBlob = encryption == 'aes256-cbc'
        ? _decryptAes256Cbc(encryptedPrivate, passphrase!)
        : encryptedPrivate;

    return PpkKey(
      version: 2,
      algorithm: algorithm,
      encryption: encryption,
      comment: comment,
      publicBlob: publicBlob,
      privateBlob: privateBlob,
    );
  }

  /// Decrypt the private blob with PuTTY v2's SHA-1-derived AES-256
  /// key. The IV is all zeros — that's the format, not our choice;
  /// PPK v3 fixes this with a KDF-derived IV. The decryption is
  /// done as raw AES-CBC (no PKCS#7 padding strip — PuTTY pads
  /// the private blob to a 16-byte boundary with arbitrary bytes
  /// that the parser later ignores).
  static Uint8List _decryptAes256Cbc(Uint8List ciphertext, String passphrase) {
    if (ciphertext.length % 16 != 0 || ciphertext.isEmpty) {
      throw const PpkParseException(
        'Encrypted blob length not a multiple of 16',
      );
    }
    final key = _v2DeriveKey(passphrase);
    final iv = Uint8List(16); // all-zero IV — PuTTY v2 contract
    final cbc = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(ciphertext.length);
    var offset = 0;
    while (offset < ciphertext.length) {
      offset += cbc.processBlock(ciphertext, offset, out, offset);
    }
    return out;
  }

  /// PuTTY v2 key schedule: SHA-1(0x00000000 || passphrase) ||
  /// SHA-1(0x00000001 || passphrase), take first 32 bytes for
  /// AES-256. Inadequate by modern standards (no salt, no work
  /// factor) — that's the format. v3 supersedes with Argon2id.
  static Uint8List _v2DeriveKey(String passphrase) {
    final pp = utf8.encode(passphrase);
    final out = BytesBuilder(copy: false);
    for (var counter = 0; counter < 2; counter++) {
      final input = Uint8List(4 + pp.length)
        ..[3] = counter
        ..setRange(4, 4 + pp.length, pp);
      final digest = SHA1Digest();
      digest.update(input, 0, input.length);
      final hash = Uint8List(20);
      digest.doFinal(hash, 0);
      out.add(hash);
    }
    return Uint8List.sublistView(out.toBytes(), 0, 32);
  }

  static PpkKey _parseV3(String text, {String? passphrase}) {
    final headers = <String, String>{};
    final lines = const LineSplitter().convert(text);
    var idx = 0;
    String? readHeader(String name) {
      if (idx >= lines.length) return null;
      final line = lines[idx];
      final colon = line.indexOf(':');
      if (colon < 0) return null;
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      if (key != name) return null;
      headers[key] = value;
      idx++;
      return value;
    }

    final algorithm = readHeader('PuTTY-User-Key-File-3');
    if (algorithm == null) {
      throw const PpkParseException('Not a PPK v3 file');
    }
    if (!_supportedAlgorithms.contains(algorithm)) {
      throw PpkUnsupportedException(
        algorithm,
        'PPK algorithm "$algorithm" not supported in this build',
      );
    }
    final encryption = readHeader('Encryption');
    if (encryption == null) {
      throw const PpkParseException('Missing Encryption header');
    }
    if (encryption != 'none' && encryption != 'aes256-cbc') {
      throw PpkUnsupportedException(
        encryption,
        'PPK encryption "$encryption" not supported in this build',
      );
    }
    final comment = readHeader('Comment') ?? '';
    final publicLines = readHeader('Public-Lines');
    if (publicLines == null) {
      throw const PpkParseException('Missing Public-Lines header');
    }
    final publicLineCount = int.tryParse(publicLines);
    if (publicLineCount == null || publicLineCount < 1) {
      throw const PpkParseException('Bad Public-Lines value');
    }
    final publicB64 = StringBuffer();
    for (var i = 0; i < publicLineCount; i++) {
      if (idx >= lines.length) {
        throw const PpkParseException('Truncated public block');
      }
      publicB64.write(lines[idx++]);
    }

    // Argon2 KDF block — only present on encrypted files.
    String? kdfName;
    int argonMemoryKiB = 0;
    int argonPasses = 0;
    int argonParallelism = 0;
    Uint8List? argonSalt;
    if (encryption == 'aes256-cbc') {
      kdfName = readHeader('Key-Derivation');
      if (kdfName == null) {
        throw const PpkParseException('Missing Key-Derivation header');
      }
      if (kdfName != 'Argon2id' &&
          kdfName != 'Argon2i' &&
          kdfName != 'Argon2d') {
        throw PpkUnsupportedException(kdfName, 'Unsupported KDF "$kdfName"');
      }
      argonMemoryKiB = int.tryParse(readHeader('Argon2-Memory') ?? '') ?? 0;
      argonPasses = int.tryParse(readHeader('Argon2-Passes') ?? '') ?? 0;
      argonParallelism =
          int.tryParse(readHeader('Argon2-Parallelism') ?? '') ?? 0;
      final saltHex = readHeader('Argon2-Salt');
      if (saltHex == null) {
        throw const PpkParseException('Missing Argon2-Salt header');
      }
      if (argonMemoryKiB <= 0 || argonPasses <= 0 || argonParallelism <= 0) {
        throw const PpkParseException('Bad Argon2 parameters');
      }
      if (argonMemoryKiB > _argon2MaxMemoryKiB) {
        // Reject crafted files that would force the parser to
        // allocate gigabytes of working memory before any auth
        // check runs. 1 GiB is far above any legitimate puttygen
        // default (~8 MiB) so a real key is never rejected here.
        throw const PpkUnsupportedException(
          'argon2-memory',
          'Argon2 memory cost too high (max 1024 MiB)',
        );
      }
      argonSalt = _hexToBytes(saltHex);
      if (passphrase == null || passphrase.isEmpty) {
        throw const PpkPassphraseRequiredException();
      }
    }
    final privateLines = readHeader('Private-Lines');
    if (privateLines == null) {
      throw const PpkParseException('Missing Private-Lines header');
    }
    final privateLineCount = int.tryParse(privateLines);
    if (privateLineCount == null || privateLineCount < 1) {
      throw const PpkParseException('Bad Private-Lines value');
    }
    final privateB64 = StringBuffer();
    for (var i = 0; i < privateLineCount; i++) {
      if (idx >= lines.length) {
        throw const PpkParseException('Truncated private block');
      }
      privateB64.write(lines[idx++]);
    }
    final macHeader = readHeader('Private-MAC');
    if (macHeader == null) {
      throw const PpkParseException('Missing Private-MAC header');
    }

    final publicBlob = base64.decode(publicB64.toString());
    final encryptedPrivate = base64.decode(privateB64.toString());

    Uint8List macKey;
    Uint8List? aesKey;
    Uint8List? aesIv;
    if (encryption == 'aes256-cbc') {
      // Argon2 outputs 80 bytes: 32 AES key + 16 IV + 32 MAC key.
      final derived = _argon2Derive(
        type: kdfName!,
        passphrase: passphrase!,
        salt: argonSalt!,
        memoryKiB: argonMemoryKiB,
        passes: argonPasses,
        parallelism: argonParallelism,
      );
      aesKey = Uint8List.sublistView(derived, 0, 32);
      aesIv = Uint8List.sublistView(derived, 32, 48);
      macKey = Uint8List.sublistView(derived, 48, 80);
    } else {
      // Unencrypted v3: MAC key is the empty string. v3 still
      // verifies the MAC for tamper detection — the key is just
      // not derived from anything secret.
      macKey = Uint8List(0);
    }

    _verifyV3Mac(
      algorithm: algorithm,
      encryption: encryption,
      comment: comment,
      publicBlob: publicBlob,
      privateBlob: encryptedPrivate,
      macHex: macHeader,
      macKey: macKey,
    );

    final privateBlob = encryption == 'aes256-cbc'
        ? _decryptCbcWithIv(encryptedPrivate, aesKey!, aesIv!)
        : encryptedPrivate;

    return PpkKey(
      version: 3,
      algorithm: algorithm,
      encryption: encryption,
      comment: comment,
      publicBlob: publicBlob,
      privateBlob: privateBlob,
    );
  }

  /// Argon2 derivation with the type fixed at the value parsed out
  /// of the `Key-Derivation` header. Output length is 80 bytes
  /// (32 AES + 16 IV + 32 MAC) — what PPK v3's encrypted layout
  /// requires.
  static Uint8List _argon2Derive({
    required String type,
    required String passphrase,
    required Uint8List salt,
    required int memoryKiB,
    required int passes,
    required int parallelism,
  }) {
    final argonType = switch (type) {
      'Argon2i' => Argon2Parameters.ARGON2_i,
      'Argon2d' => Argon2Parameters.ARGON2_d,
      _ => Argon2Parameters.ARGON2_id,
    };
    final params = Argon2Parameters(
      argonType,
      Uint8List.fromList(salt),
      desiredKeyLength: 80,
      iterations: passes,
      memory: memoryKiB,
      lanes: parallelism,
    );
    final gen = Argon2BytesGenerator()..init(params);
    final pp = Uint8List.fromList(utf8.encode(passphrase));
    final out = Uint8List(80);
    gen.deriveKey(pp, 0, out, 0);
    return out;
  }

  /// AES-256-CBC decrypt with an explicit IV — used by PPK v3
  /// where the IV comes from the KDF rather than being all-zero.
  static Uint8List _decryptCbcWithIv(
    Uint8List ciphertext,
    Uint8List key,
    Uint8List iv,
  ) {
    if (ciphertext.length % 16 != 0 || ciphertext.isEmpty) {
      throw const PpkParseException(
        'Encrypted blob length not a multiple of 16',
      );
    }
    final cbc = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(ciphertext.length);
    var offset = 0;
    while (offset < ciphertext.length) {
      offset += cbc.processBlock(ciphertext, offset, out, offset);
    }
    return out;
  }

  static void _verifyV3Mac({
    required String algorithm,
    required String encryption,
    required String comment,
    required Uint8List publicBlob,
    required Uint8List privateBlob,
    required String macHex,
    required Uint8List macKey,
  }) {
    final payload = BytesBuilder(copy: false);
    _writeSshString(payload, utf8.encode(algorithm));
    _writeSshString(payload, utf8.encode(encryption));
    _writeSshString(payload, utf8.encode(comment));
    _writeSshString(payload, publicBlob);
    _writeSshString(payload, privateBlob);

    final hmac = HMac(SHA256Digest(), 64)
      ..init(KeyParameter(macKey))
      ..update(payload.toBytes(), 0, payload.length);
    final actual = Uint8List(32);
    hmac.doFinal(actual, 0);

    final expected = _hexToBytes(macHex);
    if (!_constantTimeEquals(actual, expected)) {
      throw const PpkMacMismatchException();
    }
  }

  /// Dispatch a parsed PPK key to the right algorithm-specific
  /// OpenSSH converter. The result is a PEM string that
  /// `dartssh2.SSHKeyPair.fromPem` accepts.
  static String toOpenSshPem(PpkKey ppk) {
    switch (ppk.algorithm) {
      case 'ssh-ed25519':
        return toOpenSshPemEd25519(ppk);
      case 'ssh-rsa':
        return toOpenSshPemRsa(ppk);
      default:
        throw PpkUnsupportedException(
          ppk.algorithm,
          'No OpenSSH conversion for ${ppk.algorithm}',
        );
    }
  }

  /// Convert a parsed PPK ssh-ed25519 key into an OpenSSH-format PEM
  /// string that dartssh2's `SSHKeyPair.fromPem` accepts.
  ///
  /// Wraps the public + private material in the openssh-key-v1
  /// envelope (cipher / kdf set to "none") and base64-armors with
  /// the standard `-----BEGIN OPENSSH PRIVATE KEY-----` header.
  static String toOpenSshPemEd25519(PpkKey ppk) {
    if (ppk.algorithm != 'ssh-ed25519') {
      throw PpkUnsupportedException(
        ppk.algorithm,
        'OpenSSH conversion only implemented for ssh-ed25519',
      );
    }
    // Public blob layout: ssh-string("ssh-ed25519") + ssh-string(pub32)
    final algoStr = _readSshString(ppk.publicBlob, 0);
    final pub = _readSshString(ppk.publicBlob, algoStr.nextOffset);
    final pubBytes = pub.value;
    if (pubBytes.length != 32) {
      throw const PpkParseException('Bad ed25519 public key length');
    }
    // Private blob: mpint(scalar) — either 32 bytes or 33 (with
    // leading zero pad when MSB set). Strip the optional pad.
    final privMp = _readMpint(ppk.privateBlob, 0);
    var priv = privMp.value;
    if (priv.length == 33 && priv[0] == 0) {
      priv = priv.sublist(1);
    }
    if (priv.length != 32) {
      throw const PpkParseException('Bad ed25519 private scalar length');
    }

    // Build openssh-key-v1 frame.
    final out = BytesBuilder(copy: false);
    const magic = 'openssh-key-v1 ';
    out.add(utf8.encode(magic));
    _writeSshString(out, utf8.encode('none')); // ciphername
    _writeSshString(out, utf8.encode('none')); // kdfname
    _writeSshString(out, <int>[]); // kdf-options
    _writeUint32(out, 1); // num keys
    final pubBlobOut = BytesBuilder(copy: false);
    _writeSshString(pubBlobOut, utf8.encode('ssh-ed25519'));
    _writeSshString(pubBlobOut, pubBytes);
    _writeSshString(out, pubBlobOut.toBytes());

    // Private block — random check (matched twice), keys, comment, padding.
    final rand = Random.secure();
    final check = rand.nextInt(0x7fffffff);
    final privBlock = BytesBuilder(copy: false);
    _writeUint32(privBlock, check);
    _writeUint32(privBlock, check);
    _writeSshString(privBlock, utf8.encode('ssh-ed25519'));
    _writeSshString(privBlock, pubBytes);
    final concat = Uint8List.fromList([...priv, ...pubBytes]);
    _writeSshString(privBlock, concat);
    _writeSshString(privBlock, utf8.encode(ppk.comment));
    // Pad to 8-byte boundary with 1, 2, 3, ...
    var pad = 1;
    while (privBlock.length % 8 != 0) {
      privBlock.addByte(pad++);
    }
    _writeSshString(out, privBlock.toBytes());

    final body = base64.encode(out.toBytes());
    final wrapped = StringBuffer();
    wrapped.writeln('-----BEGIN OPENSSH PRIVATE KEY-----');
    for (var i = 0; i < body.length; i += 70) {
      wrapped.writeln(
        body.substring(i, body.length - i < 70 ? body.length : i + 70),
      );
    }
    wrapped.writeln('-----END OPENSSH PRIVATE KEY-----');
    return wrapped.toString();
  }

  /// Convert a parsed PPK ssh-rsa key into an OpenSSH-format PEM
  /// string. Reconstructs the full RSA tuple from PPK's split:
  ///
  /// - public blob carries `(e, n)` after the algorithm string
  /// - private blob carries `(d, p, q, iqmp)` as four mpints
  ///
  /// OpenSSH ssh-rsa packs `(n, e, d, iqmp, p, q)` in that exact
  /// order — note the `iqmp` ordering quirk which differs from the
  /// PPK private-blob layout.
  static String toOpenSshPemRsa(PpkKey ppk) {
    if (ppk.algorithm != 'ssh-rsa') {
      throw PpkUnsupportedException(
        ppk.algorithm,
        'OpenSSH RSA conversion called on a non-RSA key',
      );
    }
    // Public blob: ssh-string("ssh-rsa") + mpint e + mpint n.
    final algo = _readSshString(ppk.publicBlob, 0);
    final eRead = _readMpint(ppk.publicBlob, algo.nextOffset);
    final nRead = _readMpint(ppk.publicBlob, eRead.nextOffset);
    // Private blob: mpint d + mpint p + mpint q + mpint iqmp.
    final dRead = _readMpint(ppk.privateBlob, 0);
    final pRead = _readMpint(ppk.privateBlob, dRead.nextOffset);
    final qRead = _readMpint(ppk.privateBlob, pRead.nextOffset);
    final iqmpRead = _readMpint(ppk.privateBlob, qRead.nextOffset);

    final eBytes = eRead.value;
    final nBytes = nRead.value;
    final dBytes = dRead.value;
    final pBytes = pRead.value;
    final qBytes = qRead.value;
    final iqmpBytes = iqmpRead.value;

    final out = BytesBuilder(copy: false);
    out.add(utf8.encode('openssh-key-v1'));
    out.addByte(0);
    _writeSshString(out, utf8.encode('none')); // ciphername
    _writeSshString(out, utf8.encode('none')); // kdfname
    _writeSshString(out, <int>[]); // kdf-options
    _writeUint32(out, 1); // num keys

    // Pubkey blob: ssh-rsa + e + n.
    final pubBlob = BytesBuilder(copy: false);
    _writeSshString(pubBlob, utf8.encode('ssh-rsa'));
    _writeMpint(pubBlob, eBytes);
    _writeMpint(pubBlob, nBytes);
    _writeSshString(out, pubBlob.toBytes());

    // Private block: matched checks + n + e + d + iqmp + p + q +
    // comment, padded to 8-byte align.
    final rand = Random.secure();
    final check = rand.nextInt(0x7fffffff);
    final priv = BytesBuilder(copy: false);
    _writeUint32(priv, check);
    _writeUint32(priv, check);
    _writeSshString(priv, utf8.encode('ssh-rsa'));
    _writeMpint(priv, nBytes);
    _writeMpint(priv, eBytes);
    _writeMpint(priv, dBytes);
    _writeMpint(priv, iqmpBytes);
    _writeMpint(priv, pBytes);
    _writeMpint(priv, qBytes);
    _writeSshString(priv, utf8.encode(ppk.comment));
    var pad = 1;
    while (priv.length % 8 != 0) {
      priv.addByte(pad++);
    }
    _writeSshString(out, priv.toBytes());

    final body = base64.encode(out.toBytes());
    final wrapped = StringBuffer();
    wrapped.writeln('-----BEGIN OPENSSH PRIVATE KEY-----');
    for (var i = 0; i < body.length; i += 70) {
      wrapped.writeln(
        body.substring(i, body.length - i < 70 ? body.length : i + 70),
      );
    }
    wrapped.writeln('-----END OPENSSH PRIVATE KEY-----');
    return wrapped.toString();
  }

  /// Write an mpint per RFC 4251: ssh-string of the two's-complement
  /// big-endian integer with a leading zero byte when the high bit
  /// is set. The PPK reader returns mpints already in canonical
  /// shape, so passing the read bytes through unchanged is correct
  /// — but we keep the helper for symmetry with future encoders
  /// that build the bytes from a `BigInt`.
  static void _writeMpint(BytesBuilder out, Uint8List bytes) {
    _writeSshString(out, bytes);
  }

  static void _verifyV2Mac({
    required String algorithm,
    required String encryption,
    String? passphrase,
    required String comment,
    required Uint8List publicBlob,
    required Uint8List privateBlob,
    required String macHex,
  }) {
    // PPK v2 MAC key: SHA-1(_v2MacTag) for unencrypted files;
    // SHA-1(_v2MacTag || passphrase) for encrypted ones. Same
    // ssh-string-prefixed payload either way.
    final macKeyDigest = SHA1Digest();
    final tagBytes = utf8.encode(_v2MacTag);
    macKeyDigest.update(Uint8List.fromList(tagBytes), 0, tagBytes.length);
    if (passphrase != null && passphrase.isNotEmpty) {
      final pp = utf8.encode(passphrase);
      macKeyDigest.update(Uint8List.fromList(pp), 0, pp.length);
    }
    final macKey = Uint8List(20);
    macKeyDigest.doFinal(macKey, 0);

    final payload = BytesBuilder(copy: false);
    _writeSshString(payload, utf8.encode(algorithm));
    _writeSshString(payload, utf8.encode(encryption));
    _writeSshString(payload, utf8.encode(comment));
    _writeSshString(payload, publicBlob);
    _writeSshString(payload, privateBlob);

    final hmac = HMac(SHA1Digest(), 64)
      ..init(KeyParameter(macKey))
      ..update(payload.toBytes(), 0, payload.length);
    final actual = Uint8List(20);
    hmac.doFinal(actual, 0);

    final expected = _hexToBytes(macHex);
    if (!_constantTimeEquals(actual, expected)) {
      throw const PpkMacMismatchException();
    }
  }

  // -----------------------------------------------------------------
  // SSH wire helpers
  // -----------------------------------------------------------------

  static void _writeUint32(BytesBuilder out, int value) {
    out.addByte((value >> 24) & 0xff);
    out.addByte((value >> 16) & 0xff);
    out.addByte((value >> 8) & 0xff);
    out.addByte(value & 0xff);
  }

  static void _writeSshString(BytesBuilder out, List<int> bytes) {
    _writeUint32(out, bytes.length);
    out.add(bytes);
  }

  static _ReadResult<Uint8List> _readSshString(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) {
      throw const PpkParseException('Truncated ssh-string length');
    }
    final len =
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    if (offset + 4 + len > bytes.length) {
      throw const PpkParseException('Truncated ssh-string body');
    }
    return _ReadResult(
      Uint8List.fromList(bytes.sublist(offset + 4, offset + 4 + len)),
      offset + 4 + len,
    );
  }

  static _ReadResult<Uint8List> _readMpint(Uint8List bytes, int offset) =>
      _readSshString(bytes, offset);

  static Uint8List _hexToBytes(String hex) {
    if (hex.length % 2 != 0) {
      throw const PpkParseException('Bad hex length in MAC');
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      out[i] = byte;
    }
    return out;
  }

  /// Constant-time compare so an attacker who can submit forged MACs
  /// cannot time-extract the expected value byte-by-byte. Length
  /// short-circuit is safe because length itself is not secret here.
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class _ReadResult<T> {
  final T value;
  final int nextOffset;
  const _ReadResult(this.value, this.nextOffset);
}

/// Thrown when the file is not a valid PPK or its envelope is
/// malformed. Surfaced to the user as "this is not a PuTTY key file".
class PpkParseException implements Exception {
  final String message;
  const PpkParseException(this.message);
  @override
  String toString() => 'PpkParseException: $message';
}

/// Thrown when the file IS a PPK but uses a variant the current
/// build does not support yet (v3, encrypted, ssh-rsa). The
/// importer dialog uses [reason] verbatim so the user gets a
/// concrete "PPK v3 not supported" message rather than a generic
/// "not a key" error.
class PpkUnsupportedException implements Exception {
  final String dimension;
  final String reason;
  const PpkUnsupportedException(this.dimension, this.reason);
  @override
  String toString() => 'PpkUnsupportedException($dimension): $reason';
}

/// Thrown when the MAC at the end of the PPK does not match the
/// computed value. For encrypted files this is also the wrong-
/// passphrase signal: PuTTY's v2 encryption is malleable (zero IV)
/// so we cannot tell decryption from corruption from a stale MAC
/// without the MAC failing against the gibberish that decryption
/// produced.
class PpkMacMismatchException implements Exception {
  const PpkMacMismatchException();
  @override
  String toString() =>
      'PpkMacMismatchException: PPK MAC mismatch — wrong passphrase or corrupt file';
}

/// Thrown when an encrypted PPK file is parsed without a passphrase.
/// Caller catches this to surface a passphrase prompt and retry.
class PpkPassphraseRequiredException implements Exception {
  const PpkPassphraseRequiredException();
  @override
  String toString() =>
      'PpkPassphraseRequiredException: PPK file is encrypted; passphrase required';
}
