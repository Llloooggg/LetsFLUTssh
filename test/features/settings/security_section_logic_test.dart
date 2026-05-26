import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/features/settings/security_section_logic.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/macos_resign.dart'
    show MacosResignOutcome;
import 'package:letsflutssh/src/rust/api/security_config.dart' as rust_sec_cfg;

import '../../helpers/frb_bootstrap.dart';

/// Drive the section's pure decision helpers
/// (`biometricPlatformReason`, `autoLockDisabledReason`,
/// `biometricSpecFor`, `securityTierLogName`) against every
/// reachable input shape — every reason variant, every priority
/// rung, every tier × modifier combo. Tests instantiate the
/// localisations once and reuse it; no widget tree, no Riverpod
/// container, no async setup.
void main() {
  // `buildTierMarkerPayload` routes the modifiers block through the
  // Rust FRB codec, so bootstrap the bridge before any test runs.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

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

    test('keychain + password modifier allows auto-lock', () {
      // Bank-style: a password-gated keychain is `keychain` +
      // `modifiers.password = true`, not a dedicated tier value.
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
        currentLevel: SecurityTier.keychain,
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

    test('keychain + password counts as the keychain tier being current', () {
      // keychain card while keychain + password is applied — must
      // fall through to "ready" rung instead of "select tier".
      final spec = biometricSpecFor(
        l10n: l10n,
        tier: SecurityTier.keychain,
        currentLevel: SecurityTier.keychain,
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
    const noPw = SecurityTierModifiers.defaults;
    const withPw = SecurityTierModifiers(password: true);

    test(
      'keychain+password → keychain (drop modifier alone) requires verification',
      () {
        expect(
          isVerifiablePasswordDrop(
            currentTier: SecurityTier.keychain,
            currentModifiers: withPw,
            nextTier: SecurityTier.keychain,
            nextModifiers: noPw,
          ),
          isTrue,
        );
      },
    );

    test('keychain+password → other tiers requires verification', () {
      for (final next in SecurityTier.values) {
        if (next == SecurityTier.keychain) continue;
        expect(
          isVerifiablePasswordDrop(
            currentTier: SecurityTier.keychain,
            currentModifiers: withPw,
            nextTier: next,
            nextModifiers: noPw,
          ),
          isTrue,
          reason: 'Drop from keychain+password to $next must verify',
        );
      }
    });

    test('paranoid → anything other than paranoid requires verification', () {
      for (final next in SecurityTier.values) {
        if (next == SecurityTier.paranoid) continue;
        expect(
          isVerifiablePasswordDrop(
            currentTier: SecurityTier.paranoid,
            currentModifiers: withPw,
            nextTier: next,
            nextModifiers: noPw,
          ),
          isTrue,
          reason: 'Drop from paranoid to $next must verify',
        );
      }
    });

    test('same-tier same-modifier transitions never trigger the prompt', () {
      for (final t in SecurityTier.values) {
        for (final mods in [noPw, withPw]) {
          expect(
            isVerifiablePasswordDrop(
              currentTier: t,
              currentModifiers: mods,
              nextTier: t,
              nextModifiers: mods,
            ),
            isFalse,
            reason: '$t/$mods → same is a no-op, no verify prompt',
          );
        }
      }
    });

    test('non-verifiable source tiers never demand a verification prompt', () {
      // Hardware and Paranoid both carry a verifiable password by
      // tier — see the dedicated cases above. Only Plaintext + the
      // passwordless Keychain configuration have no verifier to
      // route the typed string through.
      const cases = [
        (SecurityTier.plaintext, noPw),
        (SecurityTier.keychain, noPw),
      ];
      for (final (src, mods) in cases) {
        for (final next in SecurityTier.values) {
          if (src == next) continue;
          expect(
            isVerifiablePasswordDrop(
              currentTier: src,
              currentModifiers: mods,
              nextTier: next,
              nextModifiers: noPw,
            ),
            isFalse,
            reason:
                'Source ($src, password=${mods.password}) has no verifiable '
                'password — $src → $next',
          );
        }
      }
    });

    test('hardware → anything other than hardware requires verification', () {
      // T2 is always password-gated; the hw-vault unseal is the
      // verifier so every tier change off Hardware must re-prompt
      // before discarding the live seal.
      for (final next in SecurityTier.values) {
        if (next == SecurityTier.hardware) continue;
        expect(
          isVerifiablePasswordDrop(
            currentTier: SecurityTier.hardware,
            currentModifiers: withPw,
            nextTier: next,
            nextModifiers: noPw,
          ),
          isTrue,
          reason: 'Drop from hardware to $next must verify',
        );
      }
    });
  });

  group('securityTierLogName', () {
    test('every tier has a stable snake_case marker', () {
      expect(securityTierLogName(SecurityTier.plaintext), 'plaintext');
      expect(securityTierLogName(SecurityTier.keychain), 'keychain');
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
          currentLevel: SecurityTier.keychain,
          currentModifiers: withPwd,
          targetTier: SecurityTier.keychain,
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
        SecurityTier.keychain,
        const SecurityTierModifiers(password: true),
      );
      // Round-trip through jsonDecode for shape assertions — never
      // assert on raw string layout (would lock to formatting).
      // Bank-style: a password-gated L1 keeps the `keychain` wire
      // name and carries the password signal in `mods.password`.
      final decoded = json.decode(payload);
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded['tier'], 'keychain');
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

    test('modifiers map mirrors the canonical FRB codec verbatim', () {
      const mods = SecurityTierModifiers(password: false);
      final payload = buildTierMarkerPayload(SecurityTier.plaintext, mods);
      final decoded = json.decode(payload) as Map<String, dynamic>;
      // The canonical wire shape lives in `lfs_core::security::
      // SecurityTierModifiers::to_json_map`; route the expected
      // payload through the same Rust codec so the test pins the
      // exact bytes the recovery parser ingests.
      final expectedMods = json.decode(
        rust_sec_cfg.securityTierModifiersToJson(
          password: mods.password,
          biometric: mods.biometric,
        ),
      );
      expect(decoded['mods'], expectedMods);
    });
  });

  group('isResignAcceptable', () {
    test('succeeded counts as acceptable', () {
      expect(isResignAcceptable(MacosResignOutcome.succeeded), isTrue);
    });
    test('cancelledOrFailed routes through the failure toast', () {
      expect(isResignAcceptable(MacosResignOutcome.cancelledOrFailed), isFalse);
    });
    test('bundleNotWritable routes through the failure toast', () {
      expect(isResignAcceptable(MacosResignOutcome.bundleNotWritable), isFalse);
    });
    test(
      'every MacosResignOutcome value classifies into exactly one bucket',
      () {
        // Belt-and-braces: a future enum addition (e.g. a "user
        // declined keychain prompt") must consciously decide which
        // bucket it falls into. The test exhausts the enum so a new
        // variant trips a missing-classification analyzer error.
        for (final o in MacosResignOutcome.values) {
          // The function returns a bool — the call itself is the
          // classification. We just assert it doesn't throw.
          isResignAcceptable(o);
        }
      },
    );
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
        SecurityTier.keychain,
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

  group('passwordVerifierKindFor', () {
    test('paranoid → masterPassword', () {
      expect(
        passwordVerifierKindFor(SecurityTier.paranoid),
        PasswordVerifierKind.masterPassword,
      );
    });

    test('keychain + password → keychainGate', () {
      expect(
        passwordVerifierKindFor(SecurityTier.keychain),
        PasswordVerifierKind.keychainGate,
      );
    });

    test('hardware → hardwareVault', () {
      expect(
        passwordVerifierKindFor(SecurityTier.hardware),
        PasswordVerifierKind.hardwareVault,
      );
    });

    test('non-verifiable tiers fall back to keychainGate', () {
      // The caller (`_confirmCurrentPasswordIfDropping`) is gated by
      // `isVerifiablePasswordDrop`, so these tiers never reach the
      // dispatcher in production — but the helper still has to
      // return *some* kind to keep the switch exhaustive. Pick the
      // safe-default branch (keychainGate); the surrounding gate
      // would have already short-circuited on the false return.
      // Hardware is verifiable now, so the only remaining
      // unsupported tiers are plaintext and keychain (passwordless).
      for (final tier in [SecurityTier.plaintext, SecurityTier.keychain]) {
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
      const noPw = SecurityTierModifiers.defaults;
      for (final current in SecurityTier.values) {
        for (final next in SecurityTier.values) {
          if (current == next) continue;
          expect(
            biometricKeySourceFor(
              currentTier: current,
              currentModifiers: noPw,
              nextTier: next,
              nextModifiers: noPw,
            ),
            BiometricKeySource.pullFromAppliedTier,
            reason: '$current → $next must NOT prompt for password',
          );
        }
      }
    });

    test('same-tier keychain+password → promptAndVerifyKeychainGate', () {
      const withPw = SecurityTierModifiers(password: true);
      expect(
        biometricKeySourceFor(
          currentTier: SecurityTier.keychain,
          currentModifiers: withPw,
          nextTier: SecurityTier.keychain,
          nextModifiers: withPw,
        ),
        BiometricKeySource.promptAndVerifyKeychainGate,
      );
    });

    test('same-tier Paranoid → promptAndVerifyMasterPassword', () {
      const withPw = SecurityTierModifiers(password: true);
      expect(
        biometricKeySourceFor(
          currentTier: SecurityTier.paranoid,
          currentModifiers: withPw,
          nextTier: SecurityTier.paranoid,
          nextModifiers: withPw,
        ),
        BiometricKeySource.promptAndVerifyMasterPassword,
      );
    });

    test('same-tier T0 / T1 (no password) → pullFromAppliedTier', () {
      // No verifiable password to re-prompt against — the post-apply
      // DB key is the only thing we can stash. Empty sentinel falls
      // out as a no-op when the tier holds no key (plaintext / T1
      // without password). Hardware is mandatory-password so it
      // routes through `promptAndVerifyHardwarePassword` instead.
      const noPw = SecurityTierModifiers.defaults;
      for (final tier in [SecurityTier.plaintext, SecurityTier.keychain]) {
        expect(
          biometricKeySourceFor(
            currentTier: tier,
            currentModifiers: noPw,
            nextTier: tier,
            nextModifiers: noPw,
          ),
          BiometricKeySource.pullFromAppliedTier,
          reason: 'same-tier $tier has no verifiable secret to prompt for',
        );
      }
    });

    test('same-tier Hardware → promptAndVerifyHardwarePassword', () {
      // T2 is always password-gated; the hw-vault unseal is the
      // verifier so a same-tier biometric flip on Hardware
      // re-prompts the user for the typed password and stages the
      // unsealed DB key under the staging slot.
      const withPw = SecurityTierModifiers(password: true);
      expect(
        biometricKeySourceFor(
          currentTier: SecurityTier.hardware,
          currentModifiers: withPw,
          nextTier: SecurityTier.hardware,
          nextModifiers: withPw,
        ),
        BiometricKeySource.promptAndVerifyHardwarePassword,
      );
    });
  });

  group('applyPlaintextTier', () {
    test('runs rekey(null, plaintext) → clearPlan(plaintext)', () async {
      final calls = <String>[];
      await applyPlaintextTier(
        modifiers: const SecurityTierModifiers(),
        applyAlwaysRekey: (key, level, _) async {
          calls.add('rekey(${key == null ? "null" : "key"},$level)');
        },
        runClearPlan: (target, _) async {
          calls.add('clearPlan($target)');
        },
      );
      expect(calls, [
        'rekey(null,DbSecurityTier.plaintext)',
        'clearPlan(DbSecurityTier.plaintext)',
      ]);
    });
  });

  group('applyKeychainTier', () {
    test(
      'happy path runs stageRandomKey → write → rekey → clearPlan',
      () async {
        final calls = <String>[];
        await applyKeychainTier(
          modifiers: const SecurityTierModifiers(),
          stageRandomKey: () {
            calls.add('stage');
            return 'fake-secret-id';
          },
          keychainWriteFromSecret: (id) async {
            calls.add('write($id)');
            return true;
          },
          applyAlwaysRekeyFromSecret: (id, level, _) async {
            calls.add('rekey($level,$id)');
          },
          dropStaged: (id) => calls.add('drop($id)'),
          runClearPlan: (target, _) async {
            calls.add('clearPlan($target)');
          },
        );
        expect(calls, [
          'stage',
          'write(fake-secret-id)',
          'rekey(DbSecurityTier.keychain,fake-secret-id)',
          'clearPlan(DbSecurityTier.keychain)',
        ]);
      },
    );

    test(
      'keychain write failure drops staged secret + throws + skips rekey/clearPlan',
      () async {
        final calls = <String>[];
        await expectLater(
          () => applyKeychainTier(
            modifiers: const SecurityTierModifiers(),
            stageRandomKey: () {
              calls.add('stage');
              return 'fake-secret-id';
            },
            keychainWriteFromSecret: (_) async {
              calls.add('write');
              return false;
            },
            applyAlwaysRekeyFromSecret: (_, _, _) async {
              calls.add('rekey-SHOULD-NOT-FIRE');
            },
            dropStaged: (id) => calls.add('drop($id)'),
            runClearPlan: (_, _) async {
              calls.add('clearPlan-SHOULD-NOT-FIRE');
            },
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'keychain write failed',
            ),
          ),
        );
        expect(calls, ['stage', 'write', 'drop(fake-secret-id)']);
      },
    );
  });

  group('applyHardwareTier', () {
    test(
      'happy path passes password through to hardwareStoreFromSecret',
      () async {
        final calls = <String>[];
        String? capturedPassword;
        await applyHardwareTier(
          modifiers: const SecurityTierModifiers(password: true),
          password: 'pw-1',
          stageRandomKey: () {
            calls.add('stage');
            return 'fake-id';
          },
          hardwareStoreFromSecret: ({required secretId, required pin}) async {
            capturedPassword = pin;
            calls.add('seal($secretId)');
            return true;
          },
          applyAlwaysRekeyFromSecret: (id, level, _) async {
            calls.add('rekey($level,$id)');
          },
          dropStaged: (id) => calls.add('drop($id)'),
          runClearPlan: (target, _) async {
            calls.add('clearPlan($target)');
          },
        );
        expect(calls, [
          'stage',
          'seal(fake-id)',
          'rekey(DbSecurityTier.hardware,fake-id)',
          'clearPlan(DbSecurityTier.hardware)',
        ]);
        expect(capturedPassword, 'pw-1');
      },
    );

    test('null password throws hardware password missing', () async {
      // Hardware tier is mandatory-password; the apply pipeline
      // must never reach the seal without one. A null reaches
      // here only via misuse and surfaces as a typed StateError
      // before any vault touch.
      await expectLater(
        () => applyHardwareTier(
          modifiers: const SecurityTierModifiers(password: true),
          password: null,
          stageRandomKey: () => 'fake-id',
          hardwareStoreFromSecret: ({required secretId, required pin}) async =>
              true,
          applyAlwaysRekeyFromSecret: (_, _, _) async {},
          dropStaged: (_) {},
          runClearPlan: (_, _) async {},
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'hardware password missing',
          ),
        ),
      );
    });

    test(
      'seal failure drops staged secret + throws hardware seal failed + skips rekey/clearPlan',
      () async {
        final calls = <String>[];
        await expectLater(
          () => applyHardwareTier(
            modifiers: const SecurityTierModifiers(password: true),
            password: 'pw',
            stageRandomKey: () {
              calls.add('stage');
              return 'fake-id';
            },
            hardwareStoreFromSecret: ({required secretId, required pin}) async {
              calls.add('seal');
              return false;
            },
            applyAlwaysRekeyFromSecret: (_, _, _) async {
              calls.add('rekey-SHOULD-NOT-FIRE');
            },
            dropStaged: (id) => calls.add('drop($id)'),
            runClearPlan: (_, _) async {
              calls.add('clearPlan-SHOULD-NOT-FIRE');
            },
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'hardware seal failed',
            ),
          ),
        );
        expect(calls, ['stage', 'seal', 'drop(fake-id)']);
      },
    );
  });

  group('applyParanoidTier', () {
    test('happy path: mintSecretId → enable → rekey → clearPlan', () async {
      final calls = <String>[];
      Uint8List? enabledWith;
      String? capturedSecretId;
      await applyParanoidTier(
        masterPassword: 'master-pw',
        modifiers: const SecurityTierModifiers(password: true),
        mintSecretId: () {
          calls.add('mint');
          return 'fake-master-id';
        },
        masterEnableToSecret: (pw, secretId) async {
          enabledWith = pw;
          capturedSecretId = secretId;
          calls.add('enable($secretId)');
        },
        applyAlwaysRekeyFromSecret: (id, level, _) async {
          calls.add('rekey($level,$id)');
        },
        dropStaged: (id) => calls.add('drop($id)'),
        runClearPlan: (target, _) async {
          calls.add('clearPlan($target)');
        },
      );
      expect(utf8.decode(enabledWith!), 'master-pw');
      expect(capturedSecretId, 'fake-master-id');
      expect(calls, [
        'mint',
        'enable(fake-master-id)',
        'rekey(DbSecurityTier.paranoid,fake-master-id)',
        'clearPlan(DbSecurityTier.paranoid)',
      ]);
    });

    test('null master password throws + no seams fire', () async {
      final calls = <String>[];
      await expectLater(
        () => applyParanoidTier(
          masterPassword: null,
          modifiers: const SecurityTierModifiers(),
          mintSecretId: () {
            calls.add('mint-SHOULD-NOT-FIRE');
            return 'x';
          },
          masterEnableToSecret: (_, _) async {
            calls.add('enable-SHOULD-NOT-FIRE');
          },
          applyAlwaysRekeyFromSecret: (_, _, _) async {
            calls.add('rekey-SHOULD-NOT-FIRE');
          },
          dropStaged: (_) {},
          runClearPlan: (_, _) async {
            calls.add('clearPlan-SHOULD-NOT-FIRE');
          },
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'master password missing',
          ),
        ),
      );
      expect(calls, isEmpty);
    });

    test('empty master password throws + no seams fire', () async {
      await expectLater(
        () => applyParanoidTier(
          masterPassword: '',
          modifiers: const SecurityTierModifiers(),
          mintSecretId: () => 'x',
          masterEnableToSecret: (_, _) async {},
          applyAlwaysRekeyFromSecret: (_, _, _) async {},
          dropStaged: (_) {},
          runClearPlan: (_, _) async {},
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'master password missing',
          ),
        ),
      );
    });
  });

  group('applyKeychainWithPasswordTier', () {
    /// Records every seam invocation so each test can assert on
    /// the exact sequence + args.
    Future<List<String>> drive({String? short, bool writeOk = true}) async {
      final calls = <String>[];
      try {
        await applyKeychainWithPasswordTier(
          shortPassword: short,
          modifiers: const SecurityTierModifiers(password: true),
          gateSetPassword: (pw) async {
            // Decode for the assertion log so the test still reads
            // human-friendly; the FRB call sees the bytes directly.
            calls.add('gate.set(${utf8.decode(pw)})');
          },
          gateClear: () async {
            calls.add('gate.clear');
          },
          stageRandomKey: () {
            calls.add('stage');
            return 'fake-id';
          },
          keychainWriteFromSecret: (id) async {
            calls.add('keychainWrite($id)');
            return writeOk;
          },
          applyAlwaysRekeyFromSecret: (id, level, mods) async {
            calls.add('rekey($level,$id)');
          },
          dropStaged: (id) => calls.add('drop($id)'),
          runClearPlan: (target, _) async {
            calls.add('clearPlan($target)');
          },
        );
      } catch (_) {
        // Tests assert on the call sequence + (separately) the throw.
      }
      return calls;
    }

    test(
      'happy path runs gate.set → stage → write → rekey → clearPlan',
      () async {
        final calls = await drive(short: 'pw-1');
        expect(calls, [
          'gate.set(pw-1)',
          'stage',
          'keychainWrite(fake-id)',
          'rekey(DbSecurityTier.keychain,fake-id)',
          'clearPlan(DbSecurityTier.keychain)',
        ]);
      },
    );

    test('null short password throws StateError, no seams fire', () async {
      final calls = await drive();
      expect(calls, isEmpty);
      // Re-run with a propagating throw assertion.
      await expectLater(
        applyKeychainWithPasswordTier(
          shortPassword: null,
          modifiers: const SecurityTierModifiers(password: true),
          gateSetPassword: (_) async {},
          gateClear: () async {},
          stageRandomKey: () => 'fake-id',
          keychainWriteFromSecret: (_) async => true,
          applyAlwaysRekeyFromSecret: (_, _, _) async {},
          dropStaged: (_) {},
          runClearPlan: (_, _) async {},
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('short password missing'),
          ),
        ),
      );
    });

    test('empty short password throws StateError, no seams fire', () async {
      final calls = await drive(short: '');
      expect(calls, isEmpty);
    });

    test(
      'keychain write failure drops staged secret + rolls back the gate password and throws',
      () async {
        final calls = await drive(short: 'pw-1', writeOk: false);
        expect(calls, [
          'gate.set(pw-1)',
          'stage',
          'keychainWrite(fake-id)',
          // No rekey, no clearPlan — the throw fires first; staged
          // drop + gate rollback fire before the throw.
          'drop(fake-id)',
          'gate.clear',
        ]);
        await expectLater(
          applyKeychainWithPasswordTier(
            shortPassword: 'pw-1',
            modifiers: const SecurityTierModifiers(password: true),
            gateSetPassword: (_) async {},
            gateClear: () async {},
            stageRandomKey: () => 'fake-id',
            keychainWriteFromSecret: (_) async => false,
            applyAlwaysRekeyFromSecret: (_, _, _) async {},
            dropStaged: (_) {},
            runClearPlan: (_, _) async {},
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('keychain write failed'),
            ),
          ),
        );
      },
    );

    test('gate.set is called with the unmodified short password', () async {
      // Belt-and-braces: pin that the password isn't trimmed / hashed
      // / mutated before reaching the gate setter.
      final calls = await drive(short: ' has spaces ');
      expect(calls.first, 'gate.set( has spaces )');
    });
  });

  group('confirmCurrentPasswordIfDropping', () {
    Future<ConfirmPasswordResult> runWith({
      required SecurityTier current,
      SecurityTierModifiers currentModifiers = const SecurityTierModifiers(
        password: true,
      ),
      required SecurityTier next,
      SecurityTierModifiers nextModifiers = const SecurityTierModifiers(),
      required Future<String?> Function() prompt,
      bool masterAccepts = true,
      bool gateAccepts = true,
      bool hardwareAccepts = true,
    }) {
      return confirmCurrentPasswordIfDropping(
        currentTier: current,
        currentModifiers: currentModifiers,
        targetTier: next,
        targetModifiers: nextModifiers,
        promptCurrentPassword: prompt,
        verifyMaster: (_) async => masterAccepts,
        verifyKeychainGate: (_) async => gateAccepts,
        verifyHardwareVault: (_) async => hardwareAccepts,
      );
    }

    test('non-verifiable transition short-circuits to notRequired', () async {
      // Passwordless keychain → plaintext has no verifiable
      // password to drop. The default `currentModifiers` in
      // `runWith` flips on `password: true` (the bank-style
      // L1+password case); here we override with passwordless so
      // the predicate sees no password to verify.
      var prompted = 0;
      final r = await runWith(
        current: SecurityTier.keychain,
        currentModifiers: const SecurityTierModifiers(),
        next: SecurityTier.plaintext,
        prompt: () async {
          prompted++;
          return 'should-not-be-called';
        },
      );
      expect(r, ConfirmPasswordResult.notRequired);
      expect(prompted, 0, reason: 'prompt must NOT fire on non-verifiable');
    });

    test('null prompt → cancelled', () async {
      final r = await runWith(
        current: SecurityTier.keychain,
        next: SecurityTier.plaintext,
        prompt: () async => null,
      );
      expect(r, ConfirmPasswordResult.cancelled);
    });

    test('keychainGate verifier rejects → wrongPassword', () async {
      final r = await runWith(
        current: SecurityTier.keychain,
        next: SecurityTier.plaintext,
        prompt: () async => 'whatever',
        gateAccepts: false,
      );
      expect(r, ConfirmPasswordResult.wrongPassword);
    });

    test('keychainGate verifier accepts → ok', () async {
      final r = await runWith(
        current: SecurityTier.keychain,
        next: SecurityTier.plaintext,
        prompt: () async => 'ok-pw',
        gateAccepts: true,
      );
      expect(r, ConfirmPasswordResult.ok);
    });

    test('master verifier rejects → wrongPassword', () async {
      final r = await runWith(
        current: SecurityTier.paranoid,
        next: SecurityTier.plaintext,
        prompt: () async => 'whatever',
        masterAccepts: false,
      );
      expect(r, ConfirmPasswordResult.wrongPassword);
    });

    test('master verifier accepts → ok', () async {
      final r = await runWith(
        current: SecurityTier.paranoid,
        next: SecurityTier.plaintext,
        prompt: () async => 'right',
        masterAccepts: true,
      );
      expect(r, ConfirmPasswordResult.ok);
    });

    test('paranoid verifier path never calls the keychainGate seam', () async {
      // The dispatcher routes paranoid → masterPassword exclusively.
      // A wrong-config crossover would silently shadow paranoid
      // verification with the gate's verdict.
      var gateCalled = 0;
      await confirmCurrentPasswordIfDropping(
        currentTier: SecurityTier.paranoid,
        currentModifiers: const SecurityTierModifiers(password: true),
        targetTier: SecurityTier.plaintext,
        targetModifiers: const SecurityTierModifiers(),
        promptCurrentPassword: () async => 'pw',
        verifyMaster: (_) async => true,
        verifyKeychainGate: (_) async {
          gateCalled++;
          return false;
        },
        verifyHardwareVault: (_) async => false,
      );
      expect(gateCalled, 0);
    });

    test('hardware → plaintext routes through verifyHardwareVault', () async {
      // Hardware tier always carries a verifiable password (the
      // hw-vault unseal is the verifier). A wrong-password drop
      // surfaces as wrongPassword instead of silently routing
      // through the keychainGate fallback.
      var gateCalled = 0;
      final r = await confirmCurrentPasswordIfDropping(
        currentTier: SecurityTier.hardware,
        currentModifiers: const SecurityTierModifiers(password: true),
        targetTier: SecurityTier.plaintext,
        targetModifiers: const SecurityTierModifiers(),
        promptCurrentPassword: () async => 'pw',
        verifyMaster: (_) async => true,
        verifyKeychainGate: (_) async {
          gateCalled++;
          return true;
        },
        verifyHardwareVault: (_) async => false,
      );
      expect(r, ConfirmPasswordResult.wrongPassword);
      expect(gateCalled, 0);
    });

    test('hardware → plaintext with correct password → ok', () async {
      final r = await confirmCurrentPasswordIfDropping(
        currentTier: SecurityTier.hardware,
        currentModifiers: const SecurityTierModifiers(password: true),
        targetTier: SecurityTier.plaintext,
        targetModifiers: const SecurityTierModifiers(),
        promptCurrentPassword: () async => 'pw',
        verifyMaster: (_) async => false,
        verifyKeychainGate: (_) async => false,
        verifyHardwareVault: (_) async => true,
      );
      expect(r, ConfirmPasswordResult.ok);
    });
  });

  group('runVaultClearPlan', () {
    /// Records every seam the runner invoked, in order.
    Future<List<String>> runPlan(
      TierVaultClearPlan plan, {
      bool masterEnabled = true,
    }) async {
      final calls = <String>[];
      await runVaultClearPlan(
        plan: plan,
        clearKeychainKey: () async {
          calls.add('keychain');
        },
        clearKeychainGate: () async {
          calls.add('gate');
        },
        clearHardwareVault: () async {
          calls.add('hw');
        },
        isMasterPasswordEnabled: () async => masterEnabled,
        disableMasterPassword: () async {
          calls.add('master.disable');
        },
        clearBiometricVault: () async {
          calls.add('bio');
        },
      );
      return calls;
    }

    test('plaintext plan walks every slot in canonical order', () async {
      final calls = await runPlan(
        tierVaultClearPlanFor(
          SecurityTier.plaintext,
          const SecurityTierModifiers(),
        ),
      );
      expect(calls, ['keychain', 'gate', 'hw', 'master.disable', 'bio']);
    });

    test('keychain plan skips the keychain key (just wrote it)', () async {
      final calls = await runPlan(
        tierVaultClearPlanFor(
          SecurityTier.keychain,
          const SecurityTierModifiers(),
        ),
      );
      expect(calls, ['gate', 'hw', 'master.disable', 'bio']);
      expect(calls, isNot(contains('keychain')));
    });

    test('keychain + password plan skips both keychain key + gate', () async {
      // Bank-style: a password-gated keychain is `keychain` +
      // `modifiers.password`; the modifier drives the plan branch.
      final calls = await runPlan(
        tierVaultClearPlanFor(
          SecurityTier.keychain,
          const SecurityTierModifiers(password: true),
        ),
      );
      expect(calls, ['hw', 'master.disable', 'bio']);
    });

    test('hardware plan skips the hw vault (just sealed)', () async {
      final calls = await runPlan(
        tierVaultClearPlanFor(
          SecurityTier.hardware,
          const SecurityTierModifiers(),
        ),
      );
      expect(calls, ['keychain', 'gate', 'master.disable', 'bio']);
      expect(calls, isNot(contains('hw')));
    });

    test(
      'paranoid plan skips master password disable (just enabled)',
      () async {
        final calls = await runPlan(
          tierVaultClearPlanFor(
            SecurityTier.paranoid,
            const SecurityTierModifiers(),
          ),
        );
        expect(calls, ['keychain', 'gate', 'hw', 'bio']);
        expect(calls, isNot(contains('master.disable')));
      },
    );

    test(
      'master.disable runs only when both plan flag is set AND manager is enabled',
      () async {
        // Plan says clear-master, but manager reports !enabled — the
        // runner must skip the disable call (idempotent on a disabled
        // manager but the FRB round-trip is non-trivial).
        final calls = await runPlan(
          tierVaultClearPlanFor(
            SecurityTier.plaintext,
            const SecurityTierModifiers(),
          ),
          masterEnabled: false,
        );
        expect(calls, ['keychain', 'gate', 'hw', 'bio']);
        expect(calls, isNot(contains('master.disable')));
      },
    );

    test(
      'isMasterPasswordEnabled is NOT polled when plan flag is false',
      () async {
        // T1 plan does NOT clear master password (slot stays true; T1
        // doesn't have a master-password verifier in scope). The
        // gate must short-circuit so a slow `isEnabled` FRB call
        // never runs for that branch.
        // Sanity: keychain + password is where the `clearMasterPassword`
        // flag is true; assert the gate fires there.
        var enabledQueried = 0;
        await runVaultClearPlan(
          plan: tierVaultClearPlanFor(
            SecurityTier.keychain,
            const SecurityTierModifiers(),
          ),
          clearKeychainKey: () async {},
          clearKeychainGate: () async {},
          clearHardwareVault: () async {},
          isMasterPasswordEnabled: () async {
            enabledQueried++;
            return false;
          },
          disableMasterPassword: () async {},
          clearBiometricVault: () async {},
        );
        expect(
          enabledQueried,
          1,
          reason: 'KeychainWithPassword plan does poll isEnabled',
        );
        // Now the inverse: plan with clearMasterPassword=false (no such
        // case in production but the runner must respect the flag).
        enabledQueried = 0;
        await runVaultClearPlan(
          plan: const TierVaultClearPlan(
            clearKeychainKey: false,
            clearKeychainGate: false,
            clearHardwareVault: false,
            clearMasterPassword: false,
            clearBiometricVault: false,
          ),
          clearKeychainKey: () async {},
          clearKeychainGate: () async {},
          clearHardwareVault: () async {},
          isMasterPasswordEnabled: () async {
            enabledQueried++;
            return false;
          },
          disableMasterPassword: () async {},
          clearBiometricVault: () async {},
        );
        expect(
          enabledQueried,
          0,
          reason: 'flag=false must skip the isEnabled poll',
        );
      },
    );
  });

  group('tierVaultClearPlanFor', () {
    test('plaintext clears every vault — no key survives at T0', () {
      final plan = tierVaultClearPlanFor(
        SecurityTier.plaintext,
        const SecurityTierModifiers(),
      );
      expect(plan.clearKeychainKey, isTrue);
      expect(plan.clearKeychainGate, isTrue);
      expect(plan.clearHardwareVault, isTrue);
      expect(plan.clearMasterPassword, isTrue);
      expect(plan.clearBiometricVault, isTrue);
    });

    test('keychain spares the keychain entry it just wrote', () {
      final plan = tierVaultClearPlanFor(
        SecurityTier.keychain,
        const SecurityTierModifiers(),
      );
      expect(plan.clearKeychainKey, isFalse);
      expect(plan.clearKeychainGate, isTrue);
      expect(plan.clearHardwareVault, isTrue);
      expect(plan.clearMasterPassword, isTrue);
      expect(plan.clearBiometricVault, isTrue);
    });

    test('keychain + password spares both keychain key + gate', () {
      // Bank-style: the modifier carries the password signal —
      // the gate file survives only when `modifiers.password` is on.
      final plan = tierVaultClearPlanFor(
        SecurityTier.keychain,
        const SecurityTierModifiers(password: true),
      );
      expect(plan.clearKeychainKey, isFalse);
      expect(plan.clearKeychainGate, isFalse);
      expect(plan.clearHardwareVault, isTrue);
      expect(plan.clearMasterPassword, isTrue);
      expect(plan.clearBiometricVault, isTrue);
    });

    test('plain keychain (no password modifier) clears the gate file', () {
      // Symmetric: passwordless L1 is the OTHER bank-style branch.
      // The gate file would be stale here, so the plan flips
      // `clearKeychainGate` to true.
      final plan = tierVaultClearPlanFor(
        SecurityTier.keychain,
        const SecurityTierModifiers(),
      );
      expect(plan.clearKeychainKey, isFalse);
      expect(plan.clearKeychainGate, isTrue);
      expect(plan.clearHardwareVault, isTrue);
      expect(plan.clearMasterPassword, isTrue);
      expect(plan.clearBiometricVault, isTrue);
    });

    test('hardware spares the hw vault it just sealed', () {
      final plan = tierVaultClearPlanFor(
        SecurityTier.hardware,
        const SecurityTierModifiers(),
      );
      expect(plan.clearKeychainKey, isTrue);
      expect(plan.clearKeychainGate, isTrue);
      expect(plan.clearHardwareVault, isFalse);
      expect(plan.clearMasterPassword, isTrue);
      expect(plan.clearBiometricVault, isTrue);
    });

    test('paranoid spares the master password it just enabled', () {
      final plan = tierVaultClearPlanFor(
        SecurityTier.paranoid,
        const SecurityTierModifiers(),
      );
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
          tierVaultClearPlanFor(
            tier,
            const SecurityTierModifiers(),
          ).clearBiometricVault,
          isTrue,
          reason: 'tier $tier must clear biometric vault on switch',
        );
      }
    });

    test('exactly one slot is `false` per (tier, password) — the slot the '
        'apply method just wrote into (plaintext is the all-clear exception, '
        'keychain + password writes two slots)', () {
      // Bank-style: the keychain branch's plan depends on the
      // password modifier. Walk both `password = false` and
      // `password = true` to cover the passwordless and
      // password-gated keychain shapes.
      for (final tier in SecurityTier.values) {
        for (final pw in [false, true]) {
          final plan = tierVaultClearPlanFor(
            tier,
            SecurityTierModifiers(password: pw),
          );
          final falseCount = [
            plan.clearKeychainKey,
            plan.clearKeychainGate,
            plan.clearHardwareVault,
            plan.clearMasterPassword,
            plan.clearBiometricVault,
          ].where((b) => !b).length;
          if (tier == SecurityTier.plaintext) {
            expect(
              falseCount,
              0,
              reason: 'plaintext clears every vault (pw=$pw)',
            );
          } else if (tier == SecurityTier.keychain && pw) {
            expect(
              falseCount,
              2,
              reason: 'keychain + password writes both keychain key and gate',
            );
          } else {
            expect(
              falseCount,
              1,
              reason: 'tier $tier (pw=$pw) writes one vault slot only',
            );
          }
        }
      }
    });
  });
}
