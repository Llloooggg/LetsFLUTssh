import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/settings/export_import.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ExportImport.debugMemoryProbeOverride = null;
    plat.debugMobilePlatformOverride = null;
  });

  group('resolveMaxImportArgon2idMemoryKiB', () {
    test('desktop returns the static 1 GiB ceiling', () {
      plat.debugMobilePlatformOverride = false;
      expect(
        ExportImport.resolveMaxImportArgon2idMemoryKiB(),
        ExportImport.maxImportArgon2idMemoryKiB,
      );
    });

    test('mobile returns the 512 MiB mobile ceiling', () {
      // The mobile floor is a flat 512 MiB (see
      // [mobileImportArgon2idMemoryKiB] docstring): high enough to
      // accept every legitimate `.lfs` export, low enough to stay
      // under the Android low-memory killer on the 2 GiB baseline.
      // Previous builds used `ProcessInfo.maxRss * 4 / 4` which
      // under-capped on cold-start (tiny process peak → spurious
      // "malformed header" rejections of valid archives) and
      // over-capped on warm sessions — neither branch tracked real
      // physical RAM. Flat floor matches the actual DoS threat.
      plat.debugMobilePlatformOverride = true;
      expect(
        ExportImport.resolveMaxImportArgon2idMemoryKiB(),
        ExportImport.mobileImportArgon2idMemoryKiB,
      );
      expect(ExportImport.mobileImportArgon2idMemoryKiB, 512 * 1024);
    });

    test('debugMemoryProbeOverride bypasses the platform branch entirely', () {
      // The override is a direct KiB value so tests can pin a
      // deterministic cap regardless of which branch the runner
      // would normally take.
      plat.debugMobilePlatformOverride = true;
      ExportImport.debugMemoryProbeOverride = 42;
      expect(ExportImport.resolveMaxImportArgon2idMemoryKiB(), 42);
    });
  });
}
