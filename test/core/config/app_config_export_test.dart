import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The portable-export pipeline routes through the typed FRB shim
  // `configAppConfigStripForExportTyped`; tests bootstrap the FRB
  // native lib so the Rust canonicaliser can run.
  setUpAll(requireFrbLoaded);

  Map<String, dynamic> stripJsonFor(AppConfig cfg) {
    final raw = rust_config.configAppConfigStripForExportTyped(
      value: cfg.toTyped(),
    );
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  group('configAppConfigStripForExportTyped', () {
    test('strips per-machine security metadata', () {
      final cfg = AppConfig.defaults.copyWithSecurity(
        security: const SecurityConfig(
          tier: SecurityTier.hardware,
          modifiers: SecurityTierModifiers(password: true, biometric: true),
        ),
      );
      // The full snapshot carries the per-host fields — pin that
      // before the strip pass to keep the test self-documenting.
      final full =
          jsonDecode(
                rust_config.configAppConfigToJsonTyped(value: cfg.toTyped()),
              )
              as Map<String, dynamic>;
      expect(full['security_tier'], 'hardware');
      expect(full['security_modifiers'], isA<Map>());

      final portable = stripJsonFor(cfg);
      expect(portable.containsKey('security_tier'), isFalse);
      expect(portable.containsKey('security_modifiers'), isFalse);
      expect(portable.containsKey('config_schema_version'), isFalse);
    });

    test('preserves every portable field', () {
      final cfg = AppConfig.defaults
          .copyWith(transferWorkers: 7, maxHistory: 1234, locale: 'ru')
          .copyWithSecurity(
            security: const SecurityConfig(
              tier: SecurityTier.paranoid,
              modifiers: SecurityTierModifiers(password: true),
            ),
          );
      final portable = stripJsonFor(cfg);
      expect(portable['transfer_workers'], 7);
      expect(portable['max_history'], 1234);
      expect(portable['locale'], 'ru');
    });

    test('rehydration of the stripped JSON leaves security null', () {
      final cfg = AppConfig.defaults.copyWithSecurity(
        security: const SecurityConfig(
          tier: SecurityTier.hardware,
          modifiers: SecurityTierModifiers(password: true),
        ),
      );
      final portable = rust_config.configAppConfigStripForExportTyped(
        value: cfg.toTyped(),
      );
      final rehydratedTyped = rust_config.configAppConfigFromJsonTyped(
        inputJson: portable,
      );
      expect(rehydratedTyped, isNotNull);
      final rehydrated = AppConfig.fromTyped(rehydratedTyped!);
      expect(
        rehydrated.security,
        isNull,
        reason:
            'portable export must not carry security; importer keeps the '
            'local value instead',
      );
    });
  });
}
