import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/security_init_controller.dart';
import 'package:letsflutssh/providers/security_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';

import '../helpers/fake_path_provider.dart';
import '../helpers/fake_secure_storage.dart';
import '../helpers/fake_security.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = installFakePathProvider();
    installFakeSecureStorage();
  });

  tearDown(() {
    uninstallFakeSecureStorage();
    uninstallFakePathProvider(tmp);
  });

  testWidgets('SecurityInitController can be constructed + disposed on a fresh '
      'install without touching real providers', (tester) async {
    // Full `bootstrap()` walks the migration runner + security init
    // pipeline, both of which touch native plugins
    // (flutter_secure_storage, hardware_vault, session_lock,
    // backup_exclusion, secret-tool subprocess on Linux) through
    // paths that are not DI-overridable at the provider layer.
    // Covering those needs a per-plugin method-channel harness
    // plus a subprocess mock — deferred to a future session.
    //
    // What we can pin today: the controller wires up with the
    // shared fixture's security fakes + path_provider + secure-
    // storage mocks without constructor-time throw.
    SecurityInitController? ctrl;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureKeyStorageProvider.overrideWithValue(FakeSecureKeyStorage()),
          hardwareTierVaultProvider.overrideWithValue(FakeHardwareTierVault()),
          keychainPasswordGateProvider.overrideWithValue(
            FakeKeychainPasswordGate(),
          ),
          biometricAuthProvider.overrideWithValue(FakeBiometricAuth()),
          biometricKeyVaultProvider.overrideWithValue(FakeBiometricKeyVault()),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (ctx, ref, _) {
              ctrl = SecurityInitController(ref: ref, isMounted: () => true);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(ctrl, isNotNull);
    expect(ctrl!.isReady, isFalse);
    expect(ctrl!.takeAndClearCredentialsResetFlag(), isFalse);

    // Pulling the overridden providers back through the same ref
    // also exercises the Riverpod wiring so a future container-
    // shape change breaks here instead of silently in production.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Consumer)),
    );
    expect(
      container.read(secureKeyStorageProvider),
      isA<FakeSecureKeyStorage>(),
    );
    expect(container.read(sessionProvider), isEmpty);

    ctrl!.dispose();
  });
}
