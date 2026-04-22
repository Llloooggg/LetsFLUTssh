import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/biometric_auth.dart';
import 'package:letsflutssh/core/security/hardware_tier_vault.dart';
import 'package:letsflutssh/core/security/linux/fprintd_client.dart';
import 'package:letsflutssh/core/security/secure_key_storage.dart';
import 'package:letsflutssh/core/security/security_bootstrap.dart';
import 'package:letsflutssh/core/security/security_tier.dart';

void main() {
  group('SecurityCapabilities.canOfferBiometricModifier', () {
    test('non-Linux: only the platform biometric flag matters', () {
      const caps = SecurityCapabilities(biometricAvailable: true);
      expect(caps.canOfferBiometricModifier, isTrue);
    });

    test('non-Linux: false when biometric unavailable', () {
      const caps = SecurityCapabilities(biometricAvailable: false);
      expect(caps.canOfferBiometricModifier, isFalse);
    });

    test('Linux: either biometric or fprintd suffices', () {
      expect(
        const SecurityCapabilities(
          isLinuxHost: true,
          fprintdAvailable: true,
        ).canOfferBiometricModifier,
        isTrue,
      );
      expect(
        const SecurityCapabilities(
          isLinuxHost: true,
          biometricAvailable: true,
        ).canOfferBiometricModifier,
        isTrue,
      );
      expect(
        const SecurityCapabilities(isLinuxHost: true).canOfferBiometricModifier,
        isFalse,
      );
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
        expect(mapped.tier, SecurityTier.keychainWithPassword);
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
      expect(mapped.tier, SecurityTier.keychainWithPassword);
      expect(mapped.modifiers.password, isTrue);
      expect(mapped.modifiers.biometric, isTrue);
      // Legacy alias must stay in sync.
      expect(mapped.modifiers.biometricShortcut, isTrue);
    });

    test('hardware → hardware tier with pin populated from typedSecret', () {
      final mapped = mapWizardChoice(
        chosen: WizardTier.hardware,
        password: true,
        biometric: false,
        typedSecret: 'verylong_pass',
      );
      expect(mapped.tier, SecurityTier.hardware);
      expect(mapped.pin, 'verylong_pass');
      expect(mapped.modifiers.password, isTrue);
    });

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

  group('SecurityTierModifiers additive fields', () {
    test('defaults leave password + biometric off', () {
      const m = SecurityTierModifiers.defaults;
      expect(m.password, isFalse);
      expect(m.biometric, isFalse);
      expect(m.biometricShortcut, isFalse);
    });

    test('JSON round-trip preserves the new fields', () {
      const m = SecurityTierModifiers(
        password: true,
        biometric: true,
        biometricShortcut: true,
        pinLength: 4,
      );
      final round = SecurityTierModifiers.fromJson(m.toJson());
      expect(round, m);
    });

    test('legacy JSON (biometric_shortcut only) backfills biometric', () {
      final m = SecurityTierModifiers.fromJson(const {
        'biometric_shortcut': true,
        'pin_length': 6,
      });
      expect(
        m.biometric,
        isTrue,
        reason:
            'biometric must default to biometric_shortcut on legacy configs',
      );
      expect(m.biometricShortcut, isTrue);
      expect(m.password, isFalse);
    });

    test('out-of-range pin_length clamps to the default', () {
      final m = SecurityTierModifiers.fromJson(const {'pin_length': 99});
      expect(m.pinLength, SecurityTierModifiers.defaults.pinLength);
    });
  });

  group('SecurityCapabilities value-type contract', () {
    test('default constructor uses the "nothing detected" defaults', () {
      const caps = SecurityCapabilities();
      expect(caps.keychainAvailable, isFalse);
      expect(caps.hardwareVaultAvailable, isFalse);
      expect(caps.biometricAvailable, isFalse);
      expect(caps.fprintdAvailable, isFalse);
      expect(caps.isLinuxHost, isFalse);
      expect(caps.keychainProbe, KeyringProbeResult.probeFailed);
      expect(caps.hardwareProbeCode, 'unknown');
    });

    test('copyWith replaces only the named fields', () {
      const base = SecurityCapabilities(
        keychainAvailable: true,
        isLinuxHost: true,
        keychainProbe: KeyringProbeResult.available,
        hardwareProbeCode: 'available',
      );
      final copy = base.copyWith(
        hardwareVaultAvailable: true,
        biometricAvailable: true,
      );
      expect(copy.keychainAvailable, isTrue, reason: 'untouched stays true');
      expect(copy.isLinuxHost, isTrue);
      expect(copy.keychainProbe, KeyringProbeResult.available);
      expect(copy.hardwareProbeCode, 'available');
      expect(copy.hardwareVaultAvailable, isTrue);
      expect(copy.biometricAvailable, isTrue);
    });

    test('== + hashCode agree on field-by-field equality', () {
      const a = SecurityCapabilities(
        keychainAvailable: true,
        hardwareVaultAvailable: true,
        biometricAvailable: true,
        fprintdAvailable: false,
        isLinuxHost: true,
        keychainProbe: KeyringProbeResult.available,
        hardwareProbeCode: 'available',
      );
      const b = SecurityCapabilities(
        keychainAvailable: true,
        hardwareVaultAvailable: true,
        biometricAvailable: true,
        fprintdAvailable: false,
        isLinuxHost: true,
        keychainProbe: KeyringProbeResult.available,
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
        const caps = SecurityCapabilities(
          keychainAvailable: true,
          hardwareVaultAvailable: false,
          biometricAvailable: true,
          fprintdAvailable: true,
          isLinuxHost: true,
          keychainProbe: KeyringProbeResult.linuxNoSecretService,
          hardwareProbeCode: 'available',
        );
        final round = SecurityCapabilities.fromJson(caps.toJson())!;
        expect(round, caps);
        expect(SecurityCapabilities.fromJson(null), isNull);
        // Missing keychain_probe → treated as corrupt cache (null).
        expect(SecurityCapabilities.fromJson(<String, dynamic>{}), isNull);
        // Non-string keychain_probe → corrupt.
        expect(
          SecurityCapabilities.fromJson(const {
            'keychain_probe': 42,
            'hardware_probe_code': 'available',
          }),
          isNull,
        );
        // Unknown enum value for keychain_probe → corrupt.
        expect(
          SecurityCapabilities.fromJson(const {
            'keychain_probe': 'nonsense',
            'hardware_probe_code': 'available',
          }),
          isNull,
        );
        // Non-string hardware_probe_code → corrupt.
        expect(
          SecurityCapabilities.fromJson(const {
            'keychain_probe': 'available',
            'hardware_probe_code': 7,
          }),
          isNull,
        );
      },
    );
  });

  group('probeCapabilities', () {
    test(
      'derives booleans from the classified probe results (happy path)',
      () async {
        final caps = await probeCapabilities(
          keyStorage: _FakeKeyStorage(KeyringProbeResult.available),
          hardwareVault: _FakeHwVault('available'),
          biometricAuth: _FakeBio(available: true),
          fprintdClient: _FakeFprintdProbe(hash: Uint8List.fromList([1, 2, 3])),
          isLinuxHostOverride: true,
        );
        expect(caps.keychainAvailable, isTrue);
        expect(caps.hardwareVaultAvailable, isTrue);
        expect(caps.biometricAvailable, isTrue);
        expect(caps.fprintdAvailable, isTrue);
        expect(caps.isLinuxHost, isTrue);
        expect(caps.keychainProbe, KeyringProbeResult.available);
        expect(caps.hardwareProbeCode, 'available');
      },
    );

    test(
      'non-Linux host skips the fprintd probe and carries false through',
      () async {
        final caps = await probeCapabilities(
          keyStorage: _FakeKeyStorage(KeyringProbeResult.available),
          hardwareVault: _FakeHwVault('available'),
          biometricAuth: _FakeBio(available: true),
          fprintdClient: _FakeFprintdProbe(throwOnHash: true),
          isLinuxHostOverride: false,
        );
        expect(caps.isLinuxHost, isFalse);
        expect(caps.fprintdAvailable, isFalse);
      },
    );

    test(
      'keychain probe classified as missing → keychainAvailable stays false',
      () async {
        final caps = await probeCapabilities(
          keyStorage: _FakeKeyStorage(KeyringProbeResult.linuxNoSecretService),
          hardwareVault: _FakeHwVault('available'),
          biometricAuth: _FakeBio(available: true),
          fprintdClient: _FakeFprintdProbe(hash: Uint8List.fromList([1])),
          isLinuxHostOverride: true,
        );
        expect(caps.keychainAvailable, isFalse);
        expect(caps.keychainProbe, KeyringProbeResult.linuxNoSecretService);
      },
    );

    test(
      'hardware probe code other than "available" → hardwareVaultAvailable false',
      () async {
        final caps = await probeCapabilities(
          keyStorage: _FakeKeyStorage(KeyringProbeResult.available),
          hardwareVault: _FakeHwVault('windowsSoftwareOnly'),
          biometricAuth: _FakeBio(available: true),
          fprintdClient: _FakeFprintdProbe(hash: null),
          isLinuxHostOverride: false,
        );
        expect(caps.hardwareVaultAvailable, isFalse);
        expect(caps.hardwareProbeCode, 'windowsSoftwareOnly');
      },
    );

    test(
      'any probe throwing collapses into its safe fallback — no leak',
      () async {
        final caps = await probeCapabilities(
          keyStorage: _FakeKeyStorage(null, throwIt: true),
          hardwareVault: _FakeHwVault(null, throwIt: true),
          biometricAuth: _FakeBio(throwIt: true),
          fprintdClient: _FakeFprintdProbe(throwOnHash: true),
          isLinuxHostOverride: true,
        );
        expect(caps.keychainProbe, KeyringProbeResult.probeFailed);
        expect(caps.keychainAvailable, isFalse);
        expect(caps.hardwareProbeCode, 'unknown');
        expect(caps.hardwareVaultAvailable, isFalse);
        expect(caps.biometricAvailable, isFalse);
        expect(caps.fprintdAvailable, isFalse);
      },
    );

    test(
      'fprintd returns empty hash on Linux → fprintdAvailable stays false',
      () async {
        final caps = await probeCapabilities(
          keyStorage: _FakeKeyStorage(KeyringProbeResult.available),
          hardwareVault: _FakeHwVault('available'),
          biometricAuth: _FakeBio(available: true),
          fprintdClient: _FakeFprintdProbe(hash: Uint8List(0)),
          isLinuxHostOverride: true,
        );
        expect(caps.fprintdAvailable, isFalse);
      },
    );
  });
}

class _FakeKeyStorage implements SecureKeyStorage {
  _FakeKeyStorage(this._result, {this.throwIt = false});

  final KeyringProbeResult? _result;
  final bool throwIt;

  @override
  Future<KeyringProbeResult> probe() async {
    if (throwIt) throw StateError('simulated');
    return _result!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHwVault implements HardwareTierVault {
  _FakeHwVault(this._code, {this.throwIt = false});

  final String? _code;
  final bool throwIt;

  @override
  Future<String> probeDetail() async {
    if (throwIt) throw StateError('simulated');
    return _code!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBio implements BiometricAuth {
  _FakeBio({this.available = false, this.throwIt = false});

  final bool available;
  final bool throwIt;

  @override
  Future<BiometricAvailability> availability() async {
    if (throwIt) throw StateError('simulated');
    return available ? null : BiometricUnavailableReason.noSensor;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFprintdProbe implements FprintdClient {
  _FakeFprintdProbe({this.hash, this.throwOnHash = false});

  final Uint8List? hash;
  final bool throwOnHash;

  @override
  Future<Uint8List?> getEnrolmentHash() async {
    if (throwOnHash) throw StateError('simulated');
    return hash;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
