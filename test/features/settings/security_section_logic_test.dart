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

  group('applyPlaintextTier', () {
    test('runs rekey(null, plaintext) → clearPlan(plaintext)', () async {
      final calls = <String>[];
      await applyPlaintextTier(
        modifiers: const SecurityTierModifiers(),
        applyAlwaysRekey: (key, level, _) async {
          calls.add('rekey(${key == null ? "null" : "key"},$level)');
        },
        runClearPlan: (target) async {
          calls.add('clearPlan($target)');
        },
      );
      expect(calls, [
        'rekey(null,SecurityTier.plaintext)',
        'clearPlan(SecurityTier.plaintext)',
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
          runClearPlan: (target) async {
            calls.add('clearPlan($target)');
          },
        );
        expect(calls, [
          'stage',
          'write(fake-secret-id)',
          'rekey(SecurityTier.keychain,fake-secret-id)',
          'clearPlan(SecurityTier.keychain)',
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
            runClearPlan: (_) async {
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
    test('happy path passes pin through to hardwareStoreFromSecret', () async {
      final calls = <String>[];
      String? capturedPin;
      await applyHardwareTier(
        modifiers: const SecurityTierModifiers(password: true),
        pin: 'pin-1',
        stageRandomKey: () {
          calls.add('stage');
          return 'fake-id';
        },
        hardwareStoreFromSecret: ({required secretId, required pin}) async {
          capturedPin = pin;
          calls.add('seal($secretId)');
          return true;
        },
        applyAlwaysRekeyFromSecret: (id, level, _) async {
          calls.add('rekey($level,$id)');
        },
        dropStaged: (id) => calls.add('drop($id)'),
        runClearPlan: (target) async {
          calls.add('clearPlan($target)');
        },
      );
      expect(calls, [
        'stage',
        'seal(fake-id)',
        'rekey(SecurityTier.hardware,fake-id)',
        'clearPlan(SecurityTier.hardware)',
      ]);
      expect(capturedPin, 'pin-1');
    });

    test('null pin (passwordless T2) is forwarded as-is', () async {
      String? capturedPin = 'sentinel';
      await applyHardwareTier(
        modifiers: const SecurityTierModifiers(),
        pin: null,
        stageRandomKey: () => 'fake-id',
        hardwareStoreFromSecret: ({required secretId, required pin}) async {
          capturedPin = pin;
          return true;
        },
        applyAlwaysRekeyFromSecret: (_, _, _) async {},
        dropStaged: (_) {},
        runClearPlan: (_) async {},
      );
      expect(capturedPin, isNull);
    });

    test(
      'seal failure drops staged secret + throws hardware seal failed + skips rekey/clearPlan',
      () async {
        final calls = <String>[];
        await expectLater(
          () => applyHardwareTier(
            modifiers: const SecurityTierModifiers(),
            pin: null,
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
            runClearPlan: (_) async {
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
      String? enabledWith;
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
        runClearPlan: (target) async {
          calls.add('clearPlan($target)');
        },
      );
      expect(enabledWith, 'master-pw');
      expect(capturedSecretId, 'fake-master-id');
      expect(calls, [
        'mint',
        'enable(fake-master-id)',
        'rekey(SecurityTier.paranoid,fake-master-id)',
        'clearPlan(SecurityTier.paranoid)',
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
          runClearPlan: (_) async {
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
          runClearPlan: (_) async {},
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
            calls.add('gate.set($pw)');
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
          runClearPlan: (target) async {
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
          'rekey(SecurityTier.keychainWithPassword,fake-id)',
          'clearPlan(SecurityTier.keychainWithPassword)',
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
          runClearPlan: (_) async {},
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
            runClearPlan: (_) async {},
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
      required SecurityTier next,
      required Future<String?> Function() prompt,
      bool masterAccepts = true,
      bool gateAccepts = true,
    }) {
      return confirmCurrentPasswordIfDropping(
        currentTier: current,
        targetTier: next,
        promptCurrentPassword: prompt,
        verifyMaster: (_) async => masterAccepts,
        verifyKeychainGate: (_) async => gateAccepts,
      );
    }

    test('non-verifiable transition short-circuits to notRequired', () async {
      // T1 → T0 doesn't have a verifiable password to drop.
      var prompted = 0;
      final r = await runWith(
        current: SecurityTier.keychain,
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
        current: SecurityTier.keychainWithPassword,
        next: SecurityTier.plaintext,
        prompt: () async => null,
      );
      expect(r, ConfirmPasswordResult.cancelled);
    });

    test('keychainGate verifier rejects → wrongPassword', () async {
      final r = await runWith(
        current: SecurityTier.keychainWithPassword,
        next: SecurityTier.plaintext,
        prompt: () async => 'whatever',
        gateAccepts: false,
      );
      expect(r, ConfirmPasswordResult.wrongPassword);
    });

    test('keychainGate verifier accepts → ok', () async {
      final r = await runWith(
        current: SecurityTier.keychainWithPassword,
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
        targetTier: SecurityTier.plaintext,
        promptCurrentPassword: () async => 'pw',
        verifyMaster: (_) async => true,
        verifyKeychainGate: (_) async {
          gateCalled++;
          return false;
        },
      );
      expect(gateCalled, 0);
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
        tierVaultClearPlanFor(SecurityTier.plaintext),
      );
      expect(calls, ['keychain', 'gate', 'hw', 'master.disable', 'bio']);
    });

    test('keychain plan skips the keychain key (just wrote it)', () async {
      final calls = await runPlan(tierVaultClearPlanFor(SecurityTier.keychain));
      expect(calls, ['gate', 'hw', 'master.disable', 'bio']);
      expect(calls, isNot(contains('keychain')));
    });

    test('keychainWithPassword plan skips both keychain key + gate', () async {
      final calls = await runPlan(
        tierVaultClearPlanFor(SecurityTier.keychainWithPassword),
      );
      expect(calls, ['hw', 'master.disable', 'bio']);
    });

    test('hardware plan skips the hw vault (just sealed)', () async {
      final calls = await runPlan(tierVaultClearPlanFor(SecurityTier.hardware));
      expect(calls, ['keychain', 'gate', 'master.disable', 'bio']);
      expect(calls, isNot(contains('hw')));
    });

    test(
      'paranoid plan skips master password disable (just enabled)',
      () async {
        final calls = await runPlan(
          tierVaultClearPlanFor(SecurityTier.paranoid),
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
          tierVaultClearPlanFor(SecurityTier.plaintext),
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
        // Sanity: keychainWithPassword is the tier where the `clearMasterPassword`
        // flag is true; assert the gate fires there.
        var enabledQueried = 0;
        await runVaultClearPlan(
          plan: tierVaultClearPlanFor(SecurityTier.keychainWithPassword),
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
