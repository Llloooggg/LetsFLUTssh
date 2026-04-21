import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/threat_vocabulary.dart';

/// Golden JSON of the canonical truth table. Binary protects /
/// doesNotProtect — no weak/strong-password notes, no "not applicable"
/// marker; the evaluator returns a straight yes-or-no per threat per
/// tier+modifier combo.
const _goldenJson = r'''
{
  "T0": {
    "coldDiskTheft": "doesNotProtect",
    "keyringFileTheft": "doesNotProtect",
    "offlineBruteForce": "doesNotProtect",
    "bystanderUnlockedMachine": "doesNotProtect",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T1": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "doesNotProtect",
    "offlineBruteForce": "doesNotProtect",
    "bystanderUnlockedMachine": "doesNotProtect",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T1+pw": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "protects",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T1+pw+bio": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "protects",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T2": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "doesNotProtect",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T2+pw": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "protects",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T2+pw+bio": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "protects",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "Paranoid": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "protects",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "protects",
    "osKernelOrKeychainBreach": "protects"
  }
}
''';

const Map<String, ThreatModel> _models = {
  'T0': ThreatModel(tier: ThreatTier.plaintext),
  'T1': ThreatModel(tier: ThreatTier.keychain),
  'T1+pw': ThreatModel(tier: ThreatTier.keychain, password: true),
  'T1+pw+bio': ThreatModel(
    tier: ThreatTier.keychain,
    password: true,
    biometric: true,
  ),
  'T2': ThreatModel(tier: ThreatTier.hardware),
  'T2+pw': ThreatModel(tier: ThreatTier.hardware, password: true),
  'T2+pw+bio': ThreatModel(
    tier: ThreatTier.hardware,
    password: true,
    biometric: true,
  ),
  'Paranoid': ThreatModel(tier: ThreatTier.paranoid, password: true),
};

void main() {
  group('evaluate()', () {
    test('T0 plaintext defeats no threats', () {
      final m = evaluate(const ThreatModel(tier: ThreatTier.plaintext));
      for (final threat in SecurityThreat.values) {
        expect(
          m[threat],
          ThreatStatus.doesNotProtect,
          reason: 'T0 should not protect against $threat',
        );
      }
    });

    test('Paranoid is the only tier that defeats kernel/keychain breach', () {
      for (final tier in ThreatTier.values) {
        final m = evaluate(
          ThreatModel(tier: tier, password: tier == ThreatTier.paranoid),
        );
        final expected = tier == ThreatTier.paranoid
            ? ThreatStatus.protects
            : ThreatStatus.doesNotProtect;
        expect(m[SecurityThreat.osKernelOrKeychainBreach], expected);
        expect(m[SecurityThreat.liveRamForensicsLocked], expected);
      }
    });

    test('password flag enables bystander defence on T1 and T2', () {
      for (final tier in [ThreatTier.keychain, ThreatTier.hardware]) {
        final without = evaluate(ThreatModel(tier: tier));
        expect(
          without[SecurityThreat.bystanderUnlockedMachine],
          ThreatStatus.doesNotProtect,
        );
        final withPw = evaluate(ThreatModel(tier: tier, password: true));
        expect(
          withPw[SecurityThreat.bystanderUnlockedMachine],
          ThreatStatus.protects,
        );
      }
    });

    test('offline brute force depends on whether the attacker has a usable '
        'on-disk asset to grind', () {
      // T1 without password: the wrapped key is inside the keyring
      // file — an offline attacker with the disk reads the file
      // directly (no brute-force step needed), so the honest answer
      // is ✗ on the offline-brute-force row.
      expect(
        evaluate(
          const ThreatModel(tier: ThreatTier.keychain),
        )[SecurityThreat.offlineBruteForce],
        ThreatStatus.doesNotProtect,
        reason: 'T1 no password: keyring file exfil wins without brute force',
      );
      // T2 without password: the wrapped blob lives on disk but the
      // unwrap key is inside the hardware module, which refuses
      // export regardless of password. There is nothing for the
      // attacker to brute-force offline — ✓.
      expect(
        evaluate(
          const ThreatModel(tier: ThreatTier.hardware),
        )[SecurityThreat.offlineBruteForce],
        ThreatStatus.protects,
        reason: 'T2 no password: nothing on disk is brute-forceable',
      );
      // T1 + password and T2 + password: an offline brute-force
      // attempt is possible against the wrapped blob, and Argon2id
      // wall-clock cost is what the ✓ is selling.
      for (final tier in [ThreatTier.keychain, ThreatTier.hardware]) {
        expect(
          evaluate(
            ThreatModel(tier: tier, password: true),
          )[SecurityThreat.offlineBruteForce],
          ThreatStatus.protects,
          reason: '$tier + password: Argon2id slows brute force',
        );
      }
      expect(
        evaluate(
          const ThreatModel(tier: ThreatTier.plaintext),
        )[SecurityThreat.offlineBruteForce],
        ThreatStatus.doesNotProtect,
        reason: 'T0: data is plaintext — no defence at all',
      );
      expect(
        evaluate(
          const ThreatModel(tier: ThreatTier.paranoid, password: true),
        )[SecurityThreat.offlineBruteForce],
        ThreatStatus.protects,
        reason: 'Paranoid: password IS the secret, Argon2id slows brute',
      );
    });

    test('keyringFileTheft separates T1 from T2 independent of password', () {
      // The whole point of the new row: T1 relies on the keyring
      // file being safe; T2 relies on the hw chip refusing key
      // export. That distinction holds with or without a user
      // password.
      expect(
        evaluate(
          const ThreatModel(tier: ThreatTier.keychain),
        )[SecurityThreat.keyringFileTheft],
        ThreatStatus.doesNotProtect,
      );
      expect(
        evaluate(
          const ThreatModel(tier: ThreatTier.hardware),
        )[SecurityThreat.keyringFileTheft],
        ThreatStatus.protects,
      );
      // Adding a password on T1 does close this threat: the keyring
      // file still ends up in the attacker's hands but now the
      // wrapped key requires the user password too (not just the
      // OS login password), and Argon2id turns it into the same
      // brute-force shape as T1+pw's offline brute force row.
      expect(
        evaluate(
          const ThreatModel(tier: ThreatTier.keychain, password: true),
        )[SecurityThreat.keyringFileTheft],
        ThreatStatus.protects,
      );
    });

    test('biometric flag alone does not change truth-table outputs', () {
      // Biometric is structurally a shortcut for entering the password —
      // it never changes what the tier protects against, only UI wording.
      for (final tier in ThreatTier.values) {
        final withBio = evaluate(
          ThreatModel(tier: tier, password: true, biometric: true),
        );
        final withoutBio = evaluate(ThreatModel(tier: tier, password: true));
        expect(withBio, withoutBio);
      }
    });
  });

  group('golden truth table', () {
    final golden = (jsonDecode(_goldenJson) as Map<String, dynamic>)
        .cast<String, Map<String, dynamic>>();

    for (final entry in _models.entries) {
      test('golden column ${entry.key} matches evaluate() output', () {
        final actual = evaluate(entry.value);
        final expected = golden[entry.key]!;
        for (final threat in SecurityThreat.values) {
          expect(
            actual[threat]!.name,
            expected[threat.name],
            reason: '${entry.key} / ${threat.name}',
          );
        }
      });
    }
  });
}
