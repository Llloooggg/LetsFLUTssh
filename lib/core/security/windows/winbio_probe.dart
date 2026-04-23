import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' as pffi;

import '../../../utils/logger.dart';

/// Windows-only probe for physical biometric hardware via `winbio.dll`.
///
/// ### Why this exists
///
/// On Windows `local_auth` sits on top of the `UserConsentVerifier` WinRT
/// API. That API reports "biometric available" whenever Windows Hello is
/// *configured in any form* — including a plain PIN with no fingerprint
/// reader / IR camera attached. Users who only set up a Hello PIN could
/// therefore see the biometric-unlock toggle enabled in Settings, tap it,
/// and be greeted by a silent failure (Hello refused to enrol the
/// app-level biometric-only flow because no biometric factor exists) or,
/// depending on the Hello configuration, a PIN prompt disguised as a
/// biometric unlock — exactly the "Hello PIN impersonating biometric"
/// footgun the tier UI is meant to prevent.
///
/// `WinBioEnumBiometricUnits` is the lower-level `Windows Biometric
/// Framework` call that enumerates the *physical* biometric sensors the
/// OS has attached. An empty enumeration is the ground truth: no
/// fingerprint reader, no IR camera for Windows Hello Face, no iris
/// scanner — Hello may still be reachable via PIN, but the biometric
/// unlock UI must refuse to light up.
///
/// ### Behaviour
///
/// * Non-Windows host → returns -1 sentinel. Caller treats that as
///   "don't gate on this probe" so the Linux / macOS / Android /
///   iOS paths keep their existing logic unchanged.
/// * Windows host → `WinBioEnumBiometricUnits(factor = FINGERPRINT |
///   FACIAL_FEATURES | IRIS)` + `WinBioFree` on the returned buffer.
///   Returns the number of physical units the framework reports.
/// * Any native error → logged + returns 0. The "no biometric" fallback
///   is the safer classification: refusing a feature because we can't
///   prove the hardware is there is preferable to enabling it against a
///   ghost sensor.
///
/// Calling code depends on the low-level result, not on a boolean, so
/// future refinements (e.g. "has IR camera but not fingerprint") can
/// surface without breaking the Dart API.
class WinBioProbe {
  const WinBioProbe();

  /// Bitmask passed to `WinBioEnumBiometricUnits` — the three factors
  /// that Windows Hello exposes for app authentication. Voice (0x04)
  /// is deliberately omitted: it is not surfaced through Hello on any
  /// Windows SKU we ship to, so including it would only inflate the
  /// unit count with non-actionable hardware.
  static const int _winbioTypeFingerprint = 0x00000001;
  static const int _winbioTypeFacialFeatures = 0x00000002;
  static const int _winbioTypeIris = 0x00000008;
  static const int _biometricFactors =
      _winbioTypeFingerprint | _winbioTypeFacialFeatures | _winbioTypeIris;

  /// Count the physical biometric units the OS exposes. Returns -1 on
  /// non-Windows hosts, 0 when the native call fails.
  Future<int> countBiometricUnits() async {
    if (!Platform.isWindows) return -1;
    try {
      final lib = DynamicLibrary.open('winbio.dll');
      final enumUnits = lib
          .lookup<NativeFunction<_EnumC>>('WinBioEnumBiometricUnits')
          .asFunction<_EnumDart>();
      final free = lib
          .lookup<NativeFunction<_FreeC>>('WinBioFree')
          .asFunction<_FreeDart>();

      final schemasOut = pffi.calloc<Pointer<Void>>();
      final countOut = pffi.calloc<IntPtr>();
      try {
        final hr = enumUnits(_biometricFactors, schemasOut, countOut);
        if (hr != 0) {
          AppLogger.instance.log(
            'WinBioEnumBiometricUnits returned HRESULT=0x${hr.toRadixString(16)}',
            name: 'WinBioProbe',
          );
          return 0;
        }
        final count = countOut.value;
        final schemas = schemasOut.value;
        if (schemas.address != 0) {
          free(schemas);
        }
        return count;
      } finally {
        pffi.calloc.free(schemasOut);
        pffi.calloc.free(countOut);
      }
    } catch (e) {
      // A missing / stripped `winbio.dll` is the only realistic
      // failure mode; Windows ships it in system32 on every SKU we
      // support, but a heavily-stripped enterprise image could
      // remove it. Treat as "no biometric hardware" — the
      // conservative classification matches the rest of the
      // availability probe chain.
      AppLogger.instance.log(
        'WinBioProbe.countBiometricUnits failed: $e',
        name: 'WinBioProbe',
      );
      return 0;
    }
  }
}

/// `HRESULT WinBioEnumBiometricUnits(ULONG Factor,
///     PWINBIO_UNIT_SCHEMA *UnitSchemaArray, PSIZE_T UnitCount)`
typedef _EnumC =
    Int32 Function(Uint32, Pointer<Pointer<Void>>, Pointer<IntPtr>);
typedef _EnumDart = int Function(int, Pointer<Pointer<Void>>, Pointer<IntPtr>);

/// `HRESULT WinBioFree(PVOID Address)` — frees the WinBio-owned buffer.
typedef _FreeC = Int32 Function(Pointer<Void>);
typedef _FreeDart = int Function(Pointer<Void>);
