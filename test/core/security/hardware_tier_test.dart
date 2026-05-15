import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/hardware_tier.dart';

void main() {
  // The override knob is `visibleForTesting` — clear after each
  // case so the next test sees the real-host result. The runner
  // shares the static across cases otherwise.
  tearDown(() => debugHardwareTiersOverride = null);

  group('supportedHardwareTiersForPlatform', () {
    test('mac override surfaces appleEnclave (and nothing else)', () {
      debugHardwareTiersOverride = const [HardwareTier.appleEnclave];
      expect(supportedHardwareTiersForPlatform(), [HardwareTier.appleEnclave]);
    });

    test('Windows override surfaces hello + TPM in toolbar order', () {
      // The list order is load-bearing — the key-manager toolbar
      // renders entries in this order; pin the contract.
      debugHardwareTiersOverride = const [
        HardwareTier.windowsHello,
        HardwareTier.tpm,
      ];
      expect(supportedHardwareTiersForPlatform(), [
        HardwareTier.windowsHello,
        HardwareTier.tpm,
      ]);
    });

    test('Linux override surfaces TPM only — no Hello, no Keystore', () {
      debugHardwareTiersOverride = const [HardwareTier.tpm];
      expect(supportedHardwareTiersForPlatform(), [HardwareTier.tpm]);
      // Linux must not silently expose any Apple/Windows/Android tier.
      expect(
        supportedHardwareTiersForPlatform(),
        isNot(contains(HardwareTier.appleEnclave)),
      );
      expect(
        supportedHardwareTiersForPlatform(),
        isNot(contains(HardwareTier.windowsHello)),
      );
      expect(
        supportedHardwareTiersForPlatform(),
        isNot(contains(HardwareTier.androidKeystore)),
      );
    });

    test('Android override surfaces androidKeystore only', () {
      debugHardwareTiersOverride = const [HardwareTier.androidKeystore];
      expect(supportedHardwareTiersForPlatform(), [
        HardwareTier.androidKeystore,
      ]);
    });

    test(
      'empty override surfaces the empty list (capability ladder rung 4)',
      () {
        debugHardwareTiersOverride = const [];
        expect(supportedHardwareTiersForPlatform(), isEmpty);
      },
    );

    test('null override falls through to the real-host result', () {
      // Without the override, the function reads `Platform.isXyz` at
      // call time. The host running the test is one of the supported
      // OSes; the result is some (possibly empty) list, and asking
      // twice produces an identical answer — the function is pure.
      debugHardwareTiersOverride = null;
      final first = supportedHardwareTiersForPlatform();
      final second = supportedHardwareTiersForPlatform();
      expect(first, second);
    });
  });

  group('isHardwareTierSupported', () {
    test('returns true when the tier is in the override list', () {
      debugHardwareTiersOverride = const [
        HardwareTier.windowsHello,
        HardwareTier.tpm,
      ];
      expect(isHardwareTierSupported(HardwareTier.tpm), isTrue);
      expect(isHardwareTierSupported(HardwareTier.windowsHello), isTrue);
    });

    test('returns false when the tier is absent from the override list', () {
      debugHardwareTiersOverride = const [HardwareTier.tpm];
      expect(isHardwareTierSupported(HardwareTier.appleEnclave), isFalse);
      expect(isHardwareTierSupported(HardwareTier.androidKeystore), isFalse);
    });

    test('every tier returns false when the override list is empty', () {
      debugHardwareTiersOverride = const [];
      for (final tier in HardwareTier.values) {
        expect(
          isHardwareTierSupported(tier),
          isFalse,
          reason: 'tier=$tier should not be supported on an empty platform',
        );
      }
    });
  });
}
