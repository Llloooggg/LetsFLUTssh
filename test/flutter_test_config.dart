import 'dart:async';

import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/features/settings/export_import.dart';

/// Flutter test harness calls this before every test file. We lower the
/// PBKDF2 iteration count from the production 600k to 1k so the suite
/// finishes in seconds instead of minutes — the crypto primitives stay
/// untested-to-cryptographic-strength but are exercised end-to-end.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ExportImport.debugSetPbkdf2Iterations(1000);
  MasterPasswordManager.debugSetPbkdf2Iterations(1000);
  await testMain();
}
