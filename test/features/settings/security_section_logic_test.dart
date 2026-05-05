import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/features/settings/security_section_logic.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/platform/macos/code_signing/resign_service.dart';

/// Drive the section's pure decision helpers
/// (`biometricPlatformReason`, `autoLockDisabledReason`,
/// `biometricSpecFor`, `securityTierLogName`) against every
/// reachable input shape — every reason variant, every priority
/// rung, every tier × modifier combo. Tests instantiate the
/// localisations once and reuse it; no widget tree, no Riverpod
/// container, no async setup.
void main() {
  late S l10n;

  setUpAll(() async {
    // Locale-independent fixture: SLocalizations.delegate works
    // synchronously for the canonical en bundle in flutter_test.
    l10n = await S.delegate.load(const Locale('en'));
  });

  group('biometricPlatformReason', () {
    test('returns null until the first probe completes', () {
      expect(
        biometricPlatformReason(l10n: l10n, availability: null, probed: false),
        isNull,
      );
      expect(
        biometricPlatformReason(
          l10n: l10n,
          availability: BiometricUnavailableReason.noSensor,
          probed: false,
        ),
        isNull,
        reason:
            'Pre-probe state must not surface "no sensor" — probe may yet '
            'come back available.',
      );
    });

    test('null availability after probe means "biometric available"', () {
      expect(
        biometricPlatformReason(l10n: l10n, availability: null, probed: true),
        isNull,
      );
    });

    test('platformUnsupported and noSensor share the same tooltip', () {
      final r1 = biometricPlatformReason(
        l10n: l10n,
        availability: BiometricUnavailableReason.platformUnsupported,
        probed: true,
      );
      final r2 = biometricPlatformReason(
        l10n: l10n,
        availability: BiometricUnavailableReason.noSensor,
        probed: true,
      );
      expect(r1, isNotNull);
      expect(r1, equals(r2));
      expect(r1, l10n.biometricSensorNotAvailable);
    });

    test('notEnrolled → biometricNotEnrolled', () {
      expect(
        biometricPlatformReason(
          l10n: l10n,
          availability: BiometricUnavailableReason.notEnrolled,
          probed: true,
        ),
        l10n.biometricNotEnrolled,
      );
    });

    test('systemServiceMissing → biometricSystemServiceMissing', () {
      expect(
        biometricPlatformReason(
          l10n: l10n,
          availability: BiometricUnavailableReason.systemServiceMissing,
          probed: true,
        ),
        l10n.biometricSystemServiceMissing,
      );
    });
  });

  group('autoLockDisabledReason', () {
    test('paranoid tier always allows auto-lock (inherent password)', () {
      expect(
        autoLockDisabledReason(
          l10n: l10n,
          level: SecurityTier.paranoid,
          modifiers: const SecurityTierModifiers(),
        ),
        isNull,
      );
    });

    test('keychainWithPassword always allows auto-lock', () {
      expect(
        autoLockDisabledReason(
          l10n: l10n,
          level: SecurityTier.keychainWithPassword,
          modifiers: const SecurityTierModifiers(),
        ),
        isNull,
      );
    });

    test('keychain + password modifier allows auto-lock', () {
      expect(
        autoLockDisabledReason(
          l10n: l10n,
          level: SecurityTier.keychain,
          modifiers: const SecurityTierModifiers(password: true),
        ),
        isNull,
      );
    });

    test('keychain without password modifier disables auto-lock', () {
      expect(
        autoLockDisabledReason(
          l10n: l10n,
          level: SecurityTier.keychain,
          modifiers: const SecurityTierModifiers(),
        ),
        l10n.autoLockRequiresPassword,
      );
    });

    test('plaintext tier always disables auto-lock', () {
      expect(
        autoLockDisabledReason(
          l10n: l10n,
          level: SecurityTier.plaintext,
          modifiers: const SecurityTierModifiers(),
        ),
        l10n.autoLockRequiresPassword,
      );
      expect(
        autoLockDisabledReason(
          l10n: l10n,
          level: SecurityTier.plaintext,
          modifiers: const SecurityTierModifiers(password: true),
        ),
        isNull,
        reason:
            'A password modifier on plaintext tier still satisfies the '
            'has-password gate the auto-lock helper checks.',
      );
    });
  });

  group('biometricSpecFor', () {
    const baseModifiers = SecurityTierModifiers();

    test('plaintext + paranoid expose no biometric row', () {
      expect(
        biometricSpecFor(
          l10n: l10n,
          tier: SecurityTier.plaintext,
          currentLevel: SecurityTier.plaintext,
          currentModifiers: baseModifiers,
          tierAvailable: true,
          tierUnavailableReason: null,
          availability: null,
          probed: true,
          biometricEnabled: false,
        ),
        isNull,
      );
      expect(
        biometricSpecFor(
          l10n: l10n,
          tier: SecurityTier.paranoid,
          currentLevel: SecurityTier.paranoid,
          currentModifiers: baseModifiers,
          tierAvailable: true,
          tierUnavailableReason: null,
          availability: null,
          probed: true,
          biometricEnabled: false,
        ),
        isNull,
      );
    });

    test('priority 1: platform unavailable wins over every other rung', () {
      // Even with tier ready + password modifier on, the platform
      // tooltip must surface — anything else hides the real blocker.
      final spec = biometricSpecFor(
        l10n: l10n,
        tier: SecurityTier.keychain,
        currentLevel: SecurityTier.keychainWithPassword,
        currentModifiers: const SecurityTierModifiers(password: true),
        tierAvailable: true,
        tierUnavailableReason: null,
        availability: BiometricUnavailableReason.noSensor,
        probed: true,
        biometricEnabled: true,
      )!;
      expect(spec.enabled, isFalse);
      expect(spec.disabledReason, l10n.biometricSensorNotAvailable);
      expect(spec.value, isTrue, reason: 'Mirror current biometricEnabled');
    });

    test(
      'priority 2: tier available but not currently selected → "select tier"',
      () {
        final spec = biometricSpecFor(
          l10n: l10n,
          tier: SecurityTier.hardware,
          currentLevel: SecurityTier.keychain,
          currentModifiers: const SecurityTierModifiers(password: true),
          tierAvailable: true,
          tierUnavailableReason: null,
          availability: null,
          probed: true,
          biometricEnabled: false,
        )!;
        expect(spec.enabled, isFalse);
        expect(spec.disabledReason, l10n.biometricRequiresActiveTier);
      },
    );

    test('keychainWithPassword counts as the keychain tier being current', () {
      // keychain card while keychainWithPassword is applied — must
      // fall through to "ready" rung instead of "select tier".
      final spec = biometricSpecFor(
        l10n: l10n,
        tier: SecurityTier.keychain,
        currentLevel: SecurityTier.keychainWithPassword,
        currentModifiers: const SecurityTierModifiers(password: true),
        tierAvailable: true,
        tierUnavailableReason: null,
        availability: null,
        probed: true,
        biometricEnabled: true,
      )!;
      expect(spec.enabled, isTrue);
      expect(spec.disabledReason, isNull);
      expect(spec.value, isTrue);
    });

    test(
      'priority 3: tier unavailable surfaces the tier-card reason verbatim',
      () {
        const reason = 'TPM not present';
        final spec = biometricSpecFor(
          l10n: l10n,
          tier: SecurityTier.hardware,
          currentLevel: SecurityTier.plaintext,
          currentModifiers: baseModifiers,
          tierAvailable: false,
          tierUnavailableReason: reason,
          availability: null,
          probed: true,
          biometricEnabled: false,
        )!;
        expect(spec.enabled, isFalse);
        expect(spec.disabledReason, reason);
      },
    );

    test(
      'priority 4: current tier without password modifier → "needs pwd"',
      () {
        // keychain is the current tier but the password modifier is off
        // and currentLevel is plain `keychain` (not the with-password
        // variant) — biometric is meaningless without something to
        // shortcut.
        final spec = biometricSpecFor(
          l10n: l10n,
          tier: SecurityTier.keychain,
          currentLevel: SecurityTier.keychain,
          currentModifiers: const SecurityTierModifiers(),
          tierAvailable: true,
          tierUnavailableReason: null,
          availability: null,
          probed: true,
          biometricEnabled: false,
        )!;
        expect(spec.enabled, isFalse);
        expect(spec.disabledReason, l10n.biometricRequiresPassword);
      },
    );

    test('all preconditions satisfied → toggle enabled with current value', () {
      final spec = biometricSpecFor(
        l10n: l10n,
        tier: SecurityTier.hardware,
        currentLevel: SecurityTier.hardware,
        currentModifiers: const SecurityTierModifiers(password: true),
        tierAvailable: true,
        tierUnavailableReason: null,
        availability: null,
        probed: true,
        biometricEnabled: true,
      )!;
      expect(spec.enabled, isTrue);
      expect(spec.value, isTrue);
      expect(spec.disabledReason, isNull);
    });

    test('enabled=false until the first probe completes', () {
      // Same successful preconditions but probed=false → toggle is
      // disabled (the toggle logic uses `enabled = probed`).
      final spec = biometricSpecFor(
        l10n: l10n,
        tier: SecurityTier.hardware,
        currentLevel: SecurityTier.hardware,
        currentModifiers: const SecurityTierModifiers(password: true),
        tierAvailable: true,
        tierUnavailableReason: null,
        availability: null,
        probed: false,
        biometricEnabled: false,
      )!;
      expect(spec.enabled, isFalse);
      expect(spec.disabledReason, isNull);
    });
  });

  group('isVerifiablePasswordDrop', () {
    test('keychainWithPassword → anything other than keychainWithPassword '
        'requires verification', () {
      for (final next in SecurityTier.values) {
        if (next == SecurityTier.keychainWithPassword) continue;
        expect(
          isVerifiablePasswordDrop(SecurityTier.keychainWithPassword, next),
          isTrue,
          reason: 'Drop from keychainWithPassword to $next must verify',
        );
      }
    });

    test('paranoid → anything other than paranoid requires verification', () {
      for (final next in SecurityTier.values) {
        if (next == SecurityTier.paranoid) continue;
        expect(
          isVerifiablePasswordDrop(SecurityTier.paranoid, next),
          isTrue,
          reason: 'Drop from paranoid to $next must verify',
        );
      }
    });

    test(
      'same-tier transitions never trigger the prompt (modifier-only edit)',
      () {
        for (final t in SecurityTier.values) {
          expect(
            isVerifiablePasswordDrop(t, t),
            isFalse,
            reason: '$t → $t is a modifier-only edit, no verify prompt',
          );
        }
      },
    );

    test('non-verifiable source tiers never demand a verification prompt', () {
      const sources = [
        SecurityTier.plaintext,
        SecurityTier.keychain,
        SecurityTier.hardware,
      ];
      for (final src in sources) {
        for (final next in SecurityTier.values) {
          if (src == next) continue;
          expect(
            isVerifiablePasswordDrop(src, next),
            isFalse,
            reason: 'Source $src has no verifiable password — $src → $next',
          );
        }
      }
    });
  });

  group('securityTierLogName', () {
    test('every tier has a stable snake_case marker', () {
      expect(securityTierLogName(SecurityTier.plaintext), 'plaintext');
      expect(securityTierLogName(SecurityTier.keychain), 'keychain');
      expect(
        securityTierLogName(SecurityTier.keychainWithPassword),
        'keychain_with_password',
      );
      expect(securityTierLogName(SecurityTier.hardware), 'hardware');
      expect(securityTierLogName(SecurityTier.paranoid), 'paranoid');
    });
  });

  group('classifyTierTransition', () {
    const noPwd = SecurityTierModifiers(password: false);
    const withPwd = SecurityTierModifiers(password: true);

    test('same tier + same password + biometric flip → biometricOnly', () {
      // Target = current, password modifier unchanged, biometric is
      // the only thing flipping. Fast path skips the full rekey.
      expect(
        classifyTierTransition(
          currentLevel: SecurityTier.keychainWithPassword,
          currentModifiers: withPwd,
          targetTier: SecurityTier.keychainWithPassword,
          targetModifiers: withPwd,
          pendingBiometric: true,
        ),
        TierTransitionKind.biometricOnly,
      );
      // Same with biometric=false (disabling).
      expect(
        classifyTierTransition(
          currentLevel: SecurityTier.hardware,
          currentModifiers: withPwd,
          targetTier: SecurityTier.hardware,
          targetModifiers: withPwd,
          pendingBiometric: false,
        ),
        TierTransitionKind.biometricOnly,
      );
    });

    test('same tier + same password + no pending biometric → fullRekey', () {
      // pendingBiometric=null means the card did not request a
      // biometric flip; even when tier + password haven't moved,
      // there's nothing for the biometricOnly branch to do, so the
      // dispatcher routes to fullRekey (a metadata-only reconfirm).
      expect(
        classifyTierTransition(
          currentLevel: SecurityTier.keychain,
          currentModifiers: noPwd,
          targetTier: SecurityTier.keychain,
          targetModifiers: noPwd,
          pendingBiometric: null,
        ),
        TierTransitionKind.fullRekey,
      );
    });

    test('different tier always routes to fullRekey', () {
      // Even with biometric pending — a tier change always rekeys
      // the DB wrapping key end-to-end.
      expect(
        classifyTierTransition(
          currentLevel: SecurityTier.plaintext,
          currentModifiers: noPwd,
          targetTier: SecurityTier.keychain,
          targetModifiers: noPwd,
          pendingBiometric: true,
        ),
        TierTransitionKind.fullRekey,
      );
      expect(
        classifyTierTransition(
          currentLevel: SecurityTier.keychain,
          currentModifiers: noPwd,
          targetTier: SecurityTier.paranoid,
          targetModifiers: noPwd,
          pendingBiometric: null,
        ),
        TierTransitionKind.fullRekey,
      );
    });

    test('password modifier flip routes to fullRekey', () {
      // Same tier but the password modifier changes ⇒ HMAC gate
      // shape changes ⇒ the always-rekey invariant kicks in.
      expect(
        classifyTierTransition(
          currentLevel: SecurityTier.keychain,
          currentModifiers: noPwd,
          targetTier: SecurityTier.keychain,
          targetModifiers: withPwd,
          pendingBiometric: null,
        ),
        TierTransitionKind.fullRekey,
      );
      // Reverse direction — password drop. Even with biometric
      // pending (rare in real UI but defended here), full rekey
      // still wins.
      expect(
        classifyTierTransition(
          currentLevel: SecurityTier.keychain,
          currentModifiers: withPwd,
          targetTier: SecurityTier.keychain,
          targetModifiers: noPwd,
          pendingBiometric: false,
        ),
        TierTransitionKind.fullRekey,
      );
    });

    test(
      'biometric flip with tier move is fullRekey (tier move dominates)',
      () {
        expect(
          classifyTierTransition(
            currentLevel: SecurityTier.keychain,
            currentModifiers: noPwd,
            targetTier: SecurityTier.hardware,
            targetModifiers: noPwd,
            pendingBiometric: true,
          ),
          TierTransitionKind.fullRekey,
        );
      },
    );
  });

  group('buildTierMarkerPayload', () {
    test('payload is JSON {tier, mods} with snake_case tier name', () {
      final payload = buildTierMarkerPayload(
        SecurityTier.keychainWithPassword,
        const SecurityTierModifiers(password: true),
      );
      // Round-trip through jsonDecode for shape assertions — never
      // assert on raw string layout (would lock to formatting).
      final decoded = json.decode(payload);
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded['tier'], 'keychain_with_password');
      expect(decoded['mods'], isA<Map<String, dynamic>>());
      expect(decoded['mods']['password'], isTrue);
    });

    test('every tier round-trips its snake_case marker into the payload', () {
      for (final tier in SecurityTier.values) {
        final payload = buildTierMarkerPayload(
          tier,
          const SecurityTierModifiers(),
        );
        final decoded = json.decode(payload) as Map<String, dynamic>;
        expect(decoded['tier'], securityTierLogName(tier));
      }
    });

    test('modifiers map mirrors SecurityTierModifiers.toJson verbatim', () {
      const mods = SecurityTierModifiers(password: false);
      final payload = buildTierMarkerPayload(SecurityTier.plaintext, mods);
      final decoded = json.decode(payload) as Map<String, dynamic>;
      expect(decoded['mods'], mods.toJson());
    });
  });

  group('isResignAcceptable', () {
    test('succeeded counts as acceptable', () {
      expect(isResignAcceptable(ResignOutcome.succeeded), isTrue);
    });
    test('reusedExisting counts as acceptable', () {
      expect(isResignAcceptable(ResignOutcome.reusedExisting), isTrue);
    });
    test('cancelledOrFailed routes through the failure toast', () {
      expect(isResignAcceptable(ResignOutcome.cancelledOrFailed), isFalse);
    });
    test('bundleNotWritable routes through the failure toast', () {
      expect(isResignAcceptable(ResignOutcome.bundleNotWritable), isFalse);
    });
    test('every ResignOutcome value classifies into exactly one bucket', () {
      // Belt-and-braces: a future enum addition (e.g. a "user
      // declined keychain prompt") must consciously decide which
      // bucket it falls into. The test exhausts the enum so a new
      // variant trips a missing-classification analyzer error.
      for (final o in ResignOutcome.values) {
        // The function returns a bool — the call itself is the
        // classification. We just assert it doesn't throw.
        isResignAcceptable(o);
      }
    });
  });

  group('isPostIdentityRemovalTierAccepted', () {
    test('plaintext + paranoid are the two accepted targets', () {
      expect(isPostIdentityRemovalTierAccepted(SecurityTier.plaintext), isTrue);
      expect(isPostIdentityRemovalTierAccepted(SecurityTier.paranoid), isTrue);
    });

    test('every keychain / hardware tier rejects after identity removal', () {
      // The cert backs T1 / T2 — once it's gone, those tiers can no
      // longer wrap their secrets. The wizard's `forcedCaps` shape
      // must align with this accept-set.
      for (final tier in [
        SecurityTier.keychain,
        SecurityTier.keychainWithPassword,
        SecurityTier.hardware,
      ]) {
        expect(
          isPostIdentityRemovalTierAccepted(tier),
          isFalse,
          reason: 'tier $tier must not be accepted post-identity-removal',
        );
      }
    });
  });

  group('appBundlePathFromExecutable', () {
    test('walks three parents up to reach the .app bundle root', () {
      // macOS layout: <bundle>.app/Contents/MacOS/<exe>
      final dir = appBundlePathFromExecutable(
        '/Applications/LetsFLUTssh.app/Contents/MacOS/letsflutssh',
      );
      expect(dir.path, '/Applications/LetsFLUTssh.app');
    });

    test('handles a path with extra trailing segments correctly', () {
      // Should still yield three parents up — caller's responsibility
      // to hand a valid macOS executable path.
      final dir = appBundlePathFromExecutable(
        '/tmp/Foo.app/Contents/MacOS/foo',
      );
      expect(dir.path, '/tmp/Foo.app');
    });
  });

  group('passwordVerifierKindFor', () {
    test('paranoid → masterPassword', () {
      expect(
        passwordVerifierKindFor(SecurityTier.paranoid),
        PasswordVerifierKind.masterPassword,
      );
    });

    test('keychainWithPassword → keychainGate', () {
      expect(
        passwordVerifierKindFor(SecurityTier.keychainWithPassword),
        PasswordVerifierKind.keychainGate,
      );
    });

    test('non-verifiable tiers fall back to keychainGate', () {
      // The caller (`_confirmCurrentPasswordIfDropping`) is gated by
      // `isVerifiablePasswordDrop`, so these tiers never reach the
      // dispatcher in production — but the helper still has to
      // return *some* kind to keep the switch exhaustive. Pick the
      // safe-default branch (keychainGate); the surrounding gate
      // would have already short-circuited on the false return.
      for (final tier in [
        SecurityTier.plaintext,
        SecurityTier.keychain,
        SecurityTier.hardware,
      ]) {
        expect(
          passwordVerifierKindFor(tier),
          PasswordVerifierKind.keychainGate,
          reason: 'tier $tier defaults to keychainGate',
        );
      }
    });
  });

  group('biometricKeySourceFor', () {
    test('cross-tier transition always pulls from the applied tier', () {
      // Every {current, next | current != next} pair must surface
      // the key from `securityStateProvider` after the rekey, never
      // re-prompt — the user already typed the new tier's secret
      // into the card and the rekey derived from it.
      for (final current in SecurityTier.values) {
        for (final next in SecurityTier.values) {
          if (current == next) continue;
          expect(
            biometricKeySourceFor(currentTier: current, nextTier: next),
            BiometricKeySource.pullFromAppliedTier,
            reason: '$current → $next must NOT prompt for password',
          );
        }
      }
    });

    test('same-tier T1+pw → promptAndVerifyKeychainGate', () {
      expect(
        biometricKeySourceFor(
          currentTier: SecurityTier.keychainWithPassword,
          nextTier: SecurityTier.keychainWithPassword,
        ),
        BiometricKeySource.promptAndVerifyKeychainGate,
      );
    });

    test('same-tier Paranoid → promptAndVerifyMasterPassword', () {
      expect(
        biometricKeySourceFor(
          currentTier: SecurityTier.paranoid,
          nextTier: SecurityTier.paranoid,
        ),
        BiometricKeySource.promptAndVerifyMasterPassword,
      );
    });

    test(
      'same-tier T0 / T1 / T2 → pullFromAppliedTier (no verifiable secret)',
      () {
        // No verifiable password to re-prompt against — the post-apply
        // DB key is the only thing we can stash. Empty sentinel falls
        // out as a no-op when the tier holds no key (plaintext / T1
        // without password).
        for (final tier in [
          SecurityTier.plaintext,
          SecurityTier.keychain,
          SecurityTier.hardware,
        ]) {
          expect(
            biometricKeySourceFor(currentTier: tier, nextTier: tier),
            BiometricKeySource.pullFromAppliedTier,
            reason: 'same-tier $tier has no verifiable secret to prompt for',
          );
        }
      },
    );
  });

  group('tierVaultClearPlanFor', () {
    test('plaintext clears every vault — no key survives at T0', () {
      final plan = tierVaultClearPlanFor(SecurityTier.plaintext);
      expect(plan.clearKeychainKey, isTrue);
      expect(plan.clearKeychainGate, isTrue);
      expect(plan.clearHardwareVault, isTrue);
      expect(plan.clearMasterPassword, isTrue);
      expect(plan.clearBiometricVault, isTrue);
    });

    test('keychain spares the keychain entry it just wrote', () {
      final plan = tierVaultClearPlanFor(SecurityTier.keychain);
      expect(plan.clearKeychainKey, isFalse);
      expect(plan.clearKeychainGate, isTrue);
      expect(plan.clearHardwareVault, isTrue);
      expect(plan.clearMasterPassword, isTrue);
      expect(plan.clearBiometricVault, isTrue);
    });

    test('keychainWithPassword spares both keychain key + gate', () {
      final plan = tierVaultClearPlanFor(SecurityTier.keychainWithPassword);
      expect(plan.clearKeychainKey, isFalse);
      expect(plan.clearKeychainGate, isFalse);
      expect(plan.clearHardwareVault, isTrue);
      expect(plan.clearMasterPassword, isTrue);
      expect(plan.clearBiometricVault, isTrue);
    });

    test('hardware spares the hw vault it just sealed', () {
      final plan = tierVaultClearPlanFor(SecurityTier.hardware);
      expect(plan.clearKeychainKey, isTrue);
      expect(plan.clearKeychainGate, isTrue);
      expect(plan.clearHardwareVault, isFalse);
      expect(plan.clearMasterPassword, isTrue);
      expect(plan.clearBiometricVault, isTrue);
    });

    test('paranoid spares the master password it just enabled', () {
      final plan = tierVaultClearPlanFor(SecurityTier.paranoid);
      expect(plan.clearKeychainKey, isTrue);
      expect(plan.clearKeychainGate, isTrue);
      expect(plan.clearHardwareVault, isTrue);
      expect(plan.clearMasterPassword, isFalse);
      expect(plan.clearBiometricVault, isTrue);
    });

    test('every plan keeps the biometric vault wiped — vault is per-tier', () {
      // The biometric vault stores a tier-specific HMAC; a tier
      // switch always invalidates it, so no plan should ever
      // skip the bio clear.
      for (final tier in SecurityTier.values) {
        expect(
          tierVaultClearPlanFor(tier).clearBiometricVault,
          isTrue,
          reason: 'tier $tier must clear biometric vault on switch',
        );
      }
    });

    test('exactly one slot is `false` per tier — the slot the apply method '
        'just wrote into (plaintext is the all-clear exception)', () {
      for (final tier in SecurityTier.values) {
        final plan = tierVaultClearPlanFor(tier);
        final falseCount = [
          plan.clearKeychainKey,
          plan.clearKeychainGate,
          plan.clearHardwareVault,
          plan.clearMasterPassword,
          plan.clearBiometricVault,
        ].where((b) => !b).length;
        if (tier == SecurityTier.plaintext) {
          expect(falseCount, 0, reason: 'plaintext clears every vault');
        } else if (tier == SecurityTier.keychainWithPassword) {
          // keychainWithPassword is the only tier that writes to
          // two slots — the keychain key and the password gate —
          // so two `false`s.
          expect(
            falseCount,
            2,
            reason: 'keychainWithPassword writes both keychain key and gate',
          );
        } else {
          expect(
            falseCount,
            1,
            reason: 'tier $tier writes one vault slot only',
          );
        }
      }
    });
  });
}
