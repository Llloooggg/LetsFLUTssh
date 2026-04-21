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
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T1": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "doesNotProtect",
    "offlineBruteForce": "doesNotProtect",
    "bystanderUnlockedMachine": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T1+pw": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "protects",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T1+pw+bio": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "protects",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T2": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "doesNotProtect",
    "bystanderUnlockedMachine": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect"
  },
  "T2+pw": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "protects",
    "liveRamForensicsLocked": "protects",
    "osKernelOrKeychainBreach": "protects"
  },
  "T2+pw+bio": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "protects",
    "liveRamForensicsLocked": "protects",
    "osKernelOrKeychainBreach": "protects"
  },
  "Paranoid": {
    "coldDiskTheft": "protects",
    "keyringFileTheft": "protects",
    "offlineBruteForce": "protects",
    "bystanderUnlockedMachine": "protects",
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

    test('Paranoid defeats kernel/keychain breach regardless of modifiers', () {
      for (final tier in ThreatTier.values) {
        final m = evaluate(
          ThreatModel(tier: tier, password: tier == ThreatTier.paranoid),
        );
        if (tier == ThreatTier.paranoid) {
          expect(
            m[SecurityThreat.osKernelOrKeychainBreach],
            ThreatStatus.protects,
          );
          expect(
            m[SecurityThreat.liveRamForensicsLocked],
            ThreatStatus.protects,
          );
        } else if (tier == ThreatTier.hardware) {
          // Without password, hardware tier has no user-typed secret
          // on the unlock path — a kernel breach can drive the chip
          // freely. ✓ only comes when password is on, exercised in
          // the separate T2+password test below.
          expect(
            m[SecurityThreat.osKernelOrKeychainBreach],
            ThreatStatus.doesNotProtect,
          );
          expect(
            m[SecurityThreat.liveRamForensicsLocked],
            ThreatStatus.doesNotProtect,
          );
        } else {
          expect(
            m[SecurityThreat.osKernelOrKeychainBreach],
            ThreatStatus.doesNotProtect,
          );
          expect(
            m[SecurityThreat.liveRamForensicsLocked],
            ThreatStatus.doesNotProtect,
          );
        }
      }
    });

    test('T2 + password defeats RAM forensics + kernel compromise', () {
      // Always-wipe-on-lock policy + chip opacity: the DB key
      // never lives in app RAM while locked, and what remains on
      // disk (sealed blob) is meaningless without the physical
      // chip answering an auth prompt that is rate-limited by
      // hardware lockout. Matches T1+password failing both rows
      // (keychain daemon retains key outside our wipe) and
      // Paranoid protecting both (no at-rest key at all).
      final t2pw = evaluate(
        const ThreatModel(tier: ThreatTier.hardware, password: true),
      );
      expect(
        t2pw[SecurityThreat.liveRamForensicsLocked],
        ThreatStatus.protects,
      );
      expect(
        t2pw[SecurityThreat.osKernelOrKeychainBreach],
        ThreatStatus.protects,
      );
      final t1pw = evaluate(
        const ThreatModel(tier: ThreatTier.keychain, password: true),
      );
      expect(
        t1pw[SecurityThreat.liveRamForensicsLocked],
        ThreatStatus.doesNotProtect,
      );
      expect(
        t1pw[SecurityThreat.osKernelOrKeychainBreach],
        ThreatStatus.doesNotProtect,
      );
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

    test(
      'offline brute force is symmetric across T1 and T2 — password gates it',
      () {
        // Symmetric on both T1 and T2: without a user password the
        // threat as formulated ("attacker tries passwords offline")
        // does not apply, rendered ✗. Adding a password turns it
        // into an Argon2id wall-clock problem, rendered ✓. The T1 vs
        // T2 split on no-password paths lives on the keyring-file-
        // theft row, not here — keeping this row symmetric matches
        // the mental model that the password modifier is what
        // unlocks brute-force defence.
        for (final tier in [ThreatTier.keychain, ThreatTier.hardware]) {
          expect(
            evaluate(ThreatModel(tier: tier))[SecurityThreat.offlineBruteForce],
            ThreatStatus.doesNotProtect,
            reason: '$tier no password: threat is N/A but rendered ✗',
          );
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
      },
    );

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
