import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/threat_vocabulary.dart';

/// Golden JSON of the canonical truth table. Each top-level key is a
/// short column identifier matching the plan's comparison table
/// (T0 / T1 / T1+pw / T1+pw+bio / T2 / T2+pw / T2+pw+bio / Paranoid).
/// Each inner map is threat name → ThreatStatus name.
const _goldenJson = r'''
{
  "T0": {
    "coldDiskTheft": "doesNotProtect",
    "bystanderUnlockedMachine": "doesNotProtect",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect",
    "offlineBruteForce": "notApplicable"
  },
  "T1": {
    "coldDiskTheft": "protects",
    "bystanderUnlockedMachine": "doesNotProtect",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect",
    "offlineBruteForce": "notApplicable"
  },
  "T1+pw": {
    "coldDiskTheft": "protects",
    "bystanderUnlockedMachine": "protects",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect",
    "offlineBruteForce": "noteWeakPasswordAcceptable"
  },
  "T1+pw+bio": {
    "coldDiskTheft": "protects",
    "bystanderUnlockedMachine": "protects",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect",
    "offlineBruteForce": "noteWeakPasswordAcceptable"
  },
  "T2": {
    "coldDiskTheft": "protects",
    "bystanderUnlockedMachine": "doesNotProtect",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect",
    "offlineBruteForce": "notApplicable"
  },
  "T2+pw": {
    "coldDiskTheft": "protects",
    "bystanderUnlockedMachine": "protects",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect",
    "offlineBruteForce": "noteWeakPasswordAcceptable"
  },
  "T2+pw+bio": {
    "coldDiskTheft": "protects",
    "bystanderUnlockedMachine": "protects",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "doesNotProtect",
    "osKernelOrKeychainBreach": "doesNotProtect",
    "offlineBruteForce": "noteWeakPasswordAcceptable"
  },
  "Paranoid": {
    "coldDiskTheft": "protects",
    "bystanderUnlockedMachine": "protects",
    "sameUserMalware": "doesNotProtect",
    "liveProcessMemoryDump": "doesNotProtect",
    "liveRamForensicsLocked": "protects",
    "osKernelOrKeychainBreach": "protects",
    "offlineBruteForce": "noteStrongPasswordRecommended"
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
        if (threat == SecurityThreat.offlineBruteForce) {
          expect(m[threat], ThreatStatus.notApplicable);
        } else {
          expect(
            m[threat],
            ThreatStatus.doesNotProtect,
            reason: 'T0 should not protect against $threat',
          );
        }
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

    test(
      'offline brute force annotation differentiates T2+pw from Paranoid',
      () {
        final t2 = evaluate(
          const ThreatModel(tier: ThreatTier.hardware, password: true),
        );
        final paranoid = evaluate(
          const ThreatModel(tier: ThreatTier.paranoid, password: true),
        );
        expect(
          t2[SecurityThreat.offlineBruteForce],
          ThreatStatus.noteWeakPasswordAcceptable,
        );
        expect(
          paranoid[SecurityThreat.offlineBruteForce],
          ThreatStatus.noteStrongPasswordRecommended,
        );
      },
    );

    test('offline brute force is notApplicable when no user secret exists', () {
      for (final tier in [
        ThreatTier.plaintext,
        ThreatTier.keychain,
        ThreatTier.hardware,
      ]) {
        final m = evaluate(ThreatModel(tier: tier));
        expect(m[SecurityThreat.offlineBruteForce], ThreatStatus.notApplicable);
      }
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
