import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/security_tier.dart';

void main() {
  group('AppConfig.toJsonForExport', () {
    test('strips per-machine security metadata', () {
      final cfg = AppConfig.defaults.copyWithSecurity(
        security: const SecurityConfig(
          tier: SecurityTier.hardware,
          modifiers: SecurityTierModifiers(
            password: true,
            biometric: true,
            biometricShortcut: true,
          ),
        ),
      );
      final full = cfg.toJson();
      expect(full['security_tier'], 'hardware');
      expect(full['security_modifiers'], isA<Map>());

      final portable = cfg.toJsonForExport();
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
      final portable = cfg.toJsonForExport();
      expect(portable['transfer_workers'], 7);
      expect(portable['max_history'], 1234);
      expect(portable['locale'], 'ru');
    });

    test('round-trip via toJsonForExport + fromJson leaves security null', () {
      final cfg = AppConfig.defaults.copyWithSecurity(
        security: const SecurityConfig(
          tier: SecurityTier.hardware,
          modifiers: SecurityTierModifiers(password: true),
        ),
      );
      final portable = cfg.toJsonForExport();
      final rehydrated = AppConfig.fromJson(portable);
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
