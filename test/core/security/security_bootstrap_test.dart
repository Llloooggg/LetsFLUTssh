import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_bootstrap.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/src/rust/api/security_capabilities.dart';

import '../../helpers/frb_bootstrap.dart';

/// Build a [DbSecurityCapabilities] with `defaults()` as the
/// baseline + the named-arg overrides only the test cares about.
/// Keeps each fixture line readable when every field is otherwise
/// `false` / default.
DbSecurityCapabilities _caps({
  bool? keychainAvailable,
  bool? hardwareVaultAvailable,
  bool? biometricAvailable,
  bool? fprintdAvailable,
  bool? isLinuxHost,
  DbKeyringProbeResult? keychainProbe,
  String? hardwareProbeCode,
}) => securityCapabilitiesDefaults().copyWith(
  keychainAvailable: keychainAvailable,
  hardwareVaultAvailable: hardwareVaultAvailable,
  biometricAvailable: biometricAvailable,
  fprintdAvailable: fprintdAvailable,
  isLinuxHost: isLinuxHost,
  keychainProbe: keychainProbe,
  hardwareProbeCode: hardwareProbeCode,
);

void main() {
  // canOfferBiometricModifier, mapWizardChoice, the value-type
  // contract + JSON round-trip groups all route through `lfs_core`
  // — bootstrap FRB so the canonical Rust grammar is exercised.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('DbSecurityCapabilities.canOfferBiometricModifier', () {
    test('non-Linux: only the platform biometric flag matters', () {
      expect(_caps(biometricAvailable: true).canOfferBiometricModifier, isTrue);
    });

    test('non-Linux: false when biometric unavailable', () {
      expect(
        _caps(biometricAvailable: false).canOfferBiometricModifier,
        isFalse,
      );
    });

    test('Linux: either biometric or fprintd suffices', () {
      expect(
        _caps(
          isLinuxHost: true,
          fprintdAvailable: true,
        ).canOfferBiometricModifier,
        isTrue,
      );
      expect(
        _caps(
          isLinuxHost: true,
          biometricAvailable: true,
        ).canOfferBiometricModifier,
        isTrue,
      );
      expect(_caps(isLinuxHost: true).canOfferBiometricModifier, isFalse);
    });
  });

  group('mapWizardChoice', () {
    test('plaintext → plaintext tier, no secret fields populated', () {
      final mapped = mapWizardChoice(
        chosen: WizardTier.plaintext,
        password: false,
        biometric: false,
      );
      expect(mapped.tier, SecurityTier.plaintext);
      expect(mapped.masterPassword, isNull);
      expect(mapped.shortPassword, isNull);
      expect(mapped.pin, isNull);
    });

    test('keychain without password → plain keychain tier', () {
      final mapped = mapWizardChoice(
        chosen: WizardTier.keychain,
        password: false,
        biometric: false,
      );
      expect(mapped.tier, SecurityTier.keychain);
      expect(mapped.shortPassword, isNull);
      expect(mapped.modifiers.password, isFalse);
    });

    test(
      'keychain + password → keychainWithPassword with shortPassword set',
      () {
        final mapped = mapWizardChoice(
          chosen: WizardTier.keychain,
          password: true,
          biometric: false,
          typedSecret: 'hunter2',
        );
        expect(mapped.tier, SecurityTier.keychain);
        expect(mapped.shortPassword, 'hunter2');
        expect(mapped.modifiers.password, isTrue);
      },
    );

    test('keychain + password + biometric → flags stay on modifiers', () {
      final mapped = mapWizardChoice(
        chosen: WizardTier.keychain,
        password: true,
        biometric: true,
        typedSecret: 'hunter2',
      );
      expect(mapped.tier, SecurityTier.keychain);
      expect(mapped.modifiers.password, isTrue);
      expect(mapped.modifiers.biometric, isTrue);
    });

    test(
      'hardware → hardware tier with masterPassword populated from typedSecret',
      () {
        // Hardware is always password-gated; the typed secret is
        // the primary unlock gate and lands in `masterPassword`
        // exclusively. Biometric is the optional shortcut layer
        // on top, never a separate PIN.
        final mapped = mapWizardChoice(
          chosen: WizardTier.hardware,
          password: true,
          biometric: false,
          typedSecret: 'verylong_pass',
        );
        expect(mapped.tier, SecurityTier.hardware);
        expect(mapped.masterPassword, 'verylong_pass');
        expect(mapped.pin, isNull);
        expect(mapped.shortPassword, isNull);
        expect(mapped.modifiers.password, isTrue);
      },
    );

    test('paranoid → paranoid tier with masterPassword populated', () {
      final mapped = mapWizardChoice(
        chosen: WizardTier.paranoid,
        password: true,
        biometric: false,
        typedSecret: 'correct horse battery staple',
      );
      expect(mapped.tier, SecurityTier.paranoid);
      expect(mapped.masterPassword, 'correct horse battery staple');
    });
  });

  group('SecurityTierModifiers bank-style fields', () {
    test('defaults leave password + biometric off', () {
      const m = SecurityTierModifiers.defaults;
      expect(m.password, isFalse);
      expect(m.biometric, isFalse);
    });

    // Wire codec (JSON round-trip, legacy-key stripping) lives
    // Rust-side in `lfs_core::security::SecurityTierModifiers`; the
    // Dart class is now a plain data holder. The `from_json_map` /
    // `to_json_map` contracts (round-trip every field, drop pre-v4
    // `biometric_shortcut` / `pin_length` keys) are covered by the
    // `lfs_core::security::tier` unit tests + the `lfs_frb::api::
    // security_config` FRB shim tests, so the Dart side no longer
    // re-asserts them.
  });

  group('DbSecurityCapabilities value-type contract', () {
    test('defaults factory carries the "nothing detected" snapshot', () {
      final caps = securityCapabilitiesDefaults();
      expect(caps.keychainAvailable, isFalse);
      expect(caps.hardwareVaultAvailable, isFalse);
      expect(caps.biometricAvailable, isFalse);
      expect(caps.fprintdAvailable, isFalse);
      expect(caps.isLinuxHost, isFalse);
      expect(caps.keychainProbe, DbKeyringProbeResult.probeFailed);
      expect(caps.hardwareProbeCode, 'unknown');
    });

    test('copyWith replaces only the named fields', () {
      final base = _caps(
        keychainAvailable: true,
        isLinuxHost: true,
        keychainProbe: DbKeyringProbeResult.available,
        hardwareProbeCode: 'available',
      );
      final copy = base.copyWith(
        hardwareVaultAvailable: true,
        biometricAvailable: true,
      );
      expect(copy.keychainAvailable, isTrue, reason: 'untouched stays true');
      expect(copy.isLinuxHost, isTrue);
      expect(copy.keychainProbe, DbKeyringProbeResult.available);
      expect(copy.hardwareProbeCode, 'available');
      expect(copy.hardwareVaultAvailable, isTrue);
      expect(copy.biometricAvailable, isTrue);
    });

    test('== + hashCode agree on field-by-field equality', () {
      final a = _caps(
        keychainAvailable: true,
        hardwareVaultAvailable: true,
        biometricAvailable: true,
        fprintdAvailable: false,
        isLinuxHost: true,
        keychainProbe: DbKeyringProbeResult.available,
        hardwareProbeCode: 'available',
      );
      final b = _caps(
        keychainAvailable: true,
        hardwareVaultAvailable: true,
        biometricAvailable: true,
        fprintdAvailable: false,
        isLinuxHost: true,
        keychainProbe: DbKeyringProbeResult.available,
        hardwareProbeCode: 'available',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a == b.copyWith(fprintdAvailable: true),
        isFalse,
        reason: 'any field diff must flip equality',
      );
    });

    test(
      'JSON round-trip preserves every field; invalid payloads return null',
      () {
        final caps = _caps(
          keychainAvailable: true,
          hardwareVaultAvailable: false,
          biometricAvailable: true,
          fprintdAvailable: true,
          isLinuxHost: true,
          keychainProbe: DbKeyringProbeResult.linuxNoSecretService,
          hardwareProbeCode: 'available',
        );
        final round = securityCapabilitiesFromJsonString(caps.toJsonString)!;
        expect(round, caps);
        expect(securityCapabilitiesFromJsonString(null), isNull);
        expect(securityCapabilitiesFromJsonString(''), isNull);
        // Missing keychain_probe → treated as corrupt cache (null).
        expect(securityCapabilitiesFromJsonString('{}'), isNull);
        // Non-string keychain_probe → corrupt.
        expect(
          securityCapabilitiesFromJsonString(
            '{"keychain_probe":42,"hardware_probe_code":"available"}',
          ),
          isNull,
        );
        // Unknown enum value for keychain_probe → corrupt.
        expect(
          securityCapabilitiesFromJsonString(
            '{"keychain_probe":"nonsense","hardware_probe_code":"available"}',
          ),
          isNull,
        );
        // Non-string hardware_probe_code → corrupt.
        expect(
          securityCapabilitiesFromJsonString(
            '{"keychain_probe":"available","hardware_probe_code":7}',
          ),
          isNull,
        );
      },
    );
  });

  // probeCapabilities itself is no longer unit-tested here: the
  // function is a thin async wrapper around
  // `lfs_core::security::capabilities_orchestrator::run`. The
  // orchestrator runs platform probes against the real host
  // (Secret Service / TPM2 / fprintd / etc.) under prompt
  // listeners that flutter_test cannot drive without a live FRB
  // runtime + plugin set. End-to-end coverage lives in
  // `lfs_core::security::capabilities_orchestrator::tests` and the
  // integration_test suite that runs against real probes.
}
