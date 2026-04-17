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
/// Verification is local: the public key is compiled into the app, and
/// the signature is fetched from the GitHub release alongside the
/// binary. No external service is consulted at verify time, so the
/// updater works even if Sigstore / a CA / DNS is compromised.
///
/// ## Single-pin layout
///
/// We embed **one** release-signing public key. CI signs with the
/// matching private key, held in the `RELEASE_SIGNING_KEY` GitHub
/// secret plus an offline copy in the maintainer's password manager.
///
/// If the private key ever leaks, the auto-update channel is effectively
/// dead for existing installs — any new release would have to be signed
/// by a key the app already trusts, and the only pinned key is now the
/// compromised one. The recovery path is to publish a new release
/// branch with a fresh pubkey pair and ask users to reinstall manually
/// from the website. There is no key-rotation ceremony.
///
/// This is a deliberate simplification: a backup pin buys one rotation
/// at the cost of permanent ceremony (generate a second key, keep it
/// offline, embed it, document the rotation flow). For a solo-dev repo
/// where "dump the install and grab the fresh one" is a reasonable
/// incident playbook, the single-pin design removes the whole
/// two-key maintenance burden.
class ReleaseSigning {
  ReleaseSigning._();

  /// Trusted Ed25519 release-signing public key. Raw 32 bytes of the
  /// Edwards-curve public point, captured with:
  ///   `openssl pkey -in release-key-current.pem -pubout -outform DER | tail -c 32`
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
