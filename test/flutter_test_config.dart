import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:letsflutssh/core/security/kdf_params.dart';
import 'package:letsflutssh/core/security/master_password.dart';

/// Flutter test harness calls this before every test file. KDF cost is
/// lowered to a minimum Argon2id profile (8 KiB / 1 iter / 1 lane) so the
/// suite finishes in seconds instead of minutes. The crypto primitives
/// stay untested-to-cryptographic-strength but are exercised end-to-end.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  MasterPasswordManager.debugSetKdfParams(
    const KdfParams.argon2id(memoryKiB: 8, iterations: 1, parallelism: 1),
  );
  // Drift warns in debug when multiple `GeneratedDatabase` instances
  // exist in the same process. Every `openTestDatabase()` call
  // constructs a fresh in-memory DB — legitimate for tests that
  // need clean isolation per case — but the global tracker can't
  // tell those apart from a real "app accidentally opened two
  // writers on one file" bug. Silence the warning here so the
  // debug console stays focused on actual assertion failures; the
  // production app never goes through this path.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
