import 'dart:io';

import 'package:pinenacl/ed25519.dart';

import '../../utils/logger.dart';

/// Ed25519 verification of release artefact signatures.
///
/// Goal: defend the auto-updater against the threat that an attacker can
/// rewrite both the binary AND its declared SHA-256 (the SHA comes from
/// the same GitHub Release JSON the binary does, so on its own it is
/// not authentication).
///
/// Verification is local: the public keys are compiled into the app, and
/// the signature is fetched from the GitHub release alongside the
/// binary. No external service is consulted at verify time, so the
/// updater works even if Sigstore / a CA / DNS is compromised.
///
/// ## Multi-pin layout
///
/// We embed **both** the current and a backup pubkey from the start.
/// CI signs with the current private key. If that key ever leaks:
///   1. switch the GH Actions secret to the backup private key
///   2. generate a fresh backup pair offline
///   3. ship the next release with `[backup, fresh-backup]` in this list
///   4. the previous current public key is dropped — old signatures
///      stop being accepted
///
/// Old installs continue to verify because they still recognise the
/// (now-active) backup. Document the rotation playbook in
/// `.github/SECURITY.md`.
class ReleaseSigning {
  ReleaseSigning._();

  /// Trusted Ed25519 release-signing public keys. Each is the raw 32
  /// bytes of the Edwards-curve public point, captured with:
  ///   `openssl pkey -in <private>.pem -pubout -outform DER | tail -c 32`
  ///
  /// **Order matters only for documentation** — verification accepts
  /// any matching pin. New entries go at the end.
  static final List<Uint8List> _pinnedPublicKeys = [
    // Current — `release-key-current.pem` (generated 2026-04-17)
    Uint8List.fromList([
      0x15,
      0x6a,
      0x7d,
      0x78,
      0xe6,
      0x28,
      0x52,
      0xbd,
      0x3e,
      0xf8,
      0x60,
      0x71,
      0x7f,
      0xcb,
      0x8d,
      0xde,
      0xad,
      0x1b,
      0x2d,
      0x75,
      0xe3,
      0x86,
      0x95,
      0x8f,
      0xec,
      0x3c,
      0xa8,
      0x12,
      0x30,
      0x57,
      0x32,
      0x03,
    ]),
    // Backup — `release-key-backup.pem` (generated 2026-04-17)
    Uint8List.fromList([
      0xb2,
      0x99,
      0x08,
      0x3d,
      0x37,
      0x93,
      0x1e,
      0xa7,
      0x0d,
      0x4a,
      0x9b,
      0xf2,
      0x32,
      0x2a,
      0xd5,
      0xe6,
      0xe1,
      0xd2,
      0xa5,
      0x38,
      0x5e,
      0x1b,
      0xd1,
      0xdd,
      0x7b,
      0xf2,
      0x6e,
      0x77,
      0xd4,
      0x3a,
      0xd2,
      0x14,
    ]),
  ];

  /// True when [signature] (raw 64-byte Ed25519 signature) is a valid
  /// signature over the entire byte content of [artifactPath] for any
  /// pinned public key.
  ///
  /// File is streamed into memory once (release artefacts are
  /// double-digit MB, comfortable for a desktop process). Returns false
  /// on any I/O / format error so the updater fails closed: no signature
  /// match → don't install.
  static Future<bool> verifyFile({
    required String artifactPath,
    required Uint8List signature,
  }) async {
    if (signature.length != 64) {
      AppLogger.instance.log(
        'Release signature has wrong length (${signature.length}, expected 64)',
        name: 'ReleaseSigning',
      );
      return false;
    }
    final Uint8List bytes;
    try {
      bytes = await File(artifactPath).readAsBytes();
    } catch (e) {
      AppLogger.instance.log(
        'Failed to read artefact for signature verify',
        name: 'ReleaseSigning',
        error: e,
      );
      return false;
    }
    return verifyBytes(message: bytes, signature: signature);
  }

  /// True when [signature] is a valid Ed25519 signature over [message]
  /// for any pinned public key.
  ///
  /// Pure-bytes counterpart of [verifyFile] — used by tests and by any
  /// future call site that already has the artefact in memory.
  static bool verifyBytes({
    required Uint8List message,
    required Uint8List signature,
  }) {
    if (signature.length != 64) return false;
    final sig = Signature(signature);
    for (final pubBytes in _pinnedPublicKeys) {
      try {
        final key = VerifyKey(pubBytes);
        if (key.verify(signature: sig, message: message)) return true;
      } catch (_) {
        // Try next pin — a malformed pubkey constant is a coding error,
        // not a verify-time failure, but we don't want it to crash the
        // entire verification path either.
      }
    }
    return false;
  }
}
