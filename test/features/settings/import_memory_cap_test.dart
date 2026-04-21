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
    test('desktop always returns the static 1 GiB ceiling', () {
      plat.debugMobilePlatformOverride = false;
      ExportImport.debugMemoryProbeOverride = 2 * 1024 * 1024 * 1024; // 2 GiB
      expect(
        ExportImport.resolveMaxImportArgon2idMemoryKiB(),
        ExportImport.maxImportArgon2idMemoryKiB,
      );
    });

    test('mobile with plenty of RAM clamps at the 1 GiB ceiling', () {
      plat.debugMobilePlatformOverride = true;
      // 8 GiB physical → 25 % = 2 GiB → capped to 1 GiB.
      ExportImport.debugMemoryProbeOverride = 8 * 1024 * 1024 * 1024;
      expect(
        ExportImport.resolveMaxImportArgon2idMemoryKiB(),
        ExportImport.maxImportArgon2idMemoryKiB,
      );
    });

    test('mobile on a 2 GiB device caps the Argon2id memory at ~512 MiB', () {
      plat.debugMobilePlatformOverride = true;
      // 2 GiB physical → 25 % = 512 MiB, below the static cap.
      ExportImport.debugMemoryProbeOverride = 2 * 1024 * 1024 * 1024;
      final cap = ExportImport.resolveMaxImportArgon2idMemoryKiB();
      expect(cap, 512 * 1024);
    });

    test('non-positive probe falls back to the static ceiling', () {
      plat.debugMobilePlatformOverride = true;
      ExportImport.debugMemoryProbeOverride = 0;
      expect(
        ExportImport.resolveMaxImportArgon2idMemoryKiB(),
        ExportImport.maxImportArgon2idMemoryKiB,
      );
    });
  });
}
