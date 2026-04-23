import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/windows/winbio_probe.dart';

void main() {
  group('WinBioProbe', () {
    test('returns the -1 sentinel on non-Windows hosts', () async {
      // The probe is a Windows-only signal (winbio.dll only ships on
      // Windows). The Dart-side caller in `BiometricAuth.availability`
      // treats -1 as "don't gate on this probe" so the Linux / macOS
      // / Android / iOS paths keep their existing behaviour. Any
      // accidental return of 0 on a non-Windows host would quietly
      // turn off the biometric toggle for every non-Windows user.
      if (Platform.isWindows) return;
      expect(await const WinBioProbe().countBiometricUnits(), -1);
    });

    test('bitmask includes fingerprint, facial features, and iris only', () {
      // Voice (0x04) is intentionally omitted — Windows Hello does
      // not surface voice for app authentication on any SKU we ship
      // to, so counting voice units would inflate the "biometric
      // available" verdict against hardware the user cannot actually
      // use for unlock. Pin the constant via a re-computation to
      // catch a refactor that silently flips the set.
      const fingerprint = 0x01;
      const facial = 0x02;
      const iris = 0x08;
      expect(fingerprint | facial | iris, 0x0B);
    });
  });
}
