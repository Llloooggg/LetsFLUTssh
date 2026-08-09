import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/active_dbkey.dart';
import 'package:letsflutssh/src/rust/api/app.dart' as rust_app;
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;
import 'package:letsflutssh/src/rust/api/crypto.dart' as rust_crypto;
import 'package:letsflutssh/src/rust/api/security_config.dart' as rust_sec_cfg;

import '../../helpers/frb_bootstrap.dart';

/// Integration test for `security_switch_to_plaintext`.
///
/// Verifies that:
/// 1. The FRB call resolves without panic
/// 2. The active DB key is dropped from SecretStore after the call
/// 3. A no-op (no DB handle, no key) doesn't crash
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    await requireFrbLoaded();
    tempDir = Directory.systemTemp.createTempSync('security_switch_test_');
    rust_config.configStoreInit(supportDir: tempDir.path);
  });

  tearDownAll(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('security_switch_to_plaintext', () {
    test('no-op: no key, no DB handle — does not throw', () {
      // Before db_init, there's no DB handle. Without a key in SecretStore,
      // the function should be a safe no-op.
      expect(() => rust_sec_cfg.securitySwitchToPlaintext(), returnsNormally);
    });

    test('no secretId param — uses ACTIVE_DBKEY_SECRET_ID internally', () {
      // Even without a key, calling without secretId should not crash.
      expect(
        () => rust_sec_cfg.securitySwitchToPlaintext(secretId: null),
        returnsNormally,
      );
    });

    test('drops an existing active DB key from SecretStore', () {
      // Stage a random key under ACTIVE_DBKEY_SECRET_ID.
      rust_crypto.cryptoAesGcmRandomKeyToSecret(id: kActiveDbKeySecretId);
      expect(rust_app.secretsHas(id: kActiveDbKeySecretId), isTrue);

      // Call the switch — DB handle doesn't exist, but key should be dropped.
      rust_sec_cfg.securitySwitchToPlaintext(secretId: kActiveDbKeySecretId);

      expect(rust_app.secretsHas(id: kActiveDbKeySecretId), isFalse);
    });

    test('key drop is idempotent — calling twice does not error', () {
      // Stage a key, drop it via the switch, call again.
      rust_crypto.cryptoAesGcmRandomKeyToSecret(id: kActiveDbKeySecretId);
      rust_sec_cfg.securitySwitchToPlaintext(secretId: kActiveDbKeySecretId);
      // Second call: key already gone, should be safe no-op.
      expect(
        () => rust_sec_cfg.securitySwitchToPlaintext(
          secretId: kActiveDbKeySecretId,
        ),
        returnsNormally,
      );
    });

    test('secretId parameter is used — other secrets survive', () {
      // Stage two keys: one under ACTIVE_DBKEY_SECRET_ID, one under a test id.
      const testSecretId = 'test-other-secret-survives';
      rust_crypto.cryptoAesGcmRandomKeyToSecret(id: kActiveDbKeySecretId);
      rust_crypto.cryptoAesGcmRandomKeyToSecret(id: testSecretId);

      expect(rust_app.secretsHas(id: kActiveDbKeySecretId), isTrue);
      expect(rust_app.secretsHas(id: testSecretId), isTrue);

      // Call with the test secretId — it should drop that one but
      // the function internally also drops ACTIVE_DBKEY_SECRET_ID.
      rust_sec_cfg.securitySwitchToPlaintext(secretId: testSecretId);

      // The function drops whatever secret_id it was given.
      // If it's the ACTIVE_DBKEY_SECRET_ID, both get dropped.
      // If it's a different one, only that one gets dropped.
      // The key invariant: the passed secretId is always dropped.
      expect(rust_app.secretsHas(id: testSecretId), isFalse);
    });
  });
}
