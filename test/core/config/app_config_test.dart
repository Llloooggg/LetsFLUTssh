import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;
import 'package:letsflutssh/src/rust/api/security_capabilities.dart';
import 'package:letsflutssh/utils/logger.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // AppConfig conversions route through `lfs_core::config::AppConfig`
  // via `DbAppConfigSnapshot` — the Dart facade carries no codec.
  // Tests must bootstrap the FRB native lib so the typed get/set
  // pair can serialise through the Rust canonical path.
  setUpAll(requireFrbLoaded);

  // ===== TerminalConfig =====
  group('TerminalConfig', () {
    group('defaults', () {
      test('has expected default values', () {
        const config = TerminalConfig();
        expect(config.fontSize, 14.0);
        expect(config.theme, 'system');
        expect(config.scrollback, 5000);
      });

      test('static defaults matches default constructor', () {
        expect(TerminalConfig.defaults, const TerminalConfig());
      });
    });

    group('copyWith()', () {
      test('replaces specified fields', () {
        const config = TerminalConfig();
        final copy = config.copyWith(fontSize: 18);
        expect(copy.fontSize, 18);
        expect(copy.theme, config.theme);
        expect(copy.scrollback, config.scrollback);
      });

      test('replaces all fields', () {
        const config = TerminalConfig();
        final copy = config.copyWith(
          fontSize: 20,
          theme: 'light',
          scrollback: 300,
        );
        expect(copy.fontSize, 20);
        expect(copy.theme, 'light');
        expect(copy.scrollback, 300);
      });

      test('returns equal object when no arguments given', () {
        const config = TerminalConfig(
          fontSize: 16,
          theme: 'light',
          scrollback: 1000,
        );
        expect(config.copyWith(), config);
      });
    });

    group('equality and hashCode', () {
      test('equal TerminalConfigs are equal', () {
        const a = TerminalConfig(
          fontSize: 16,
          theme: 'light',
          scrollback: 1000,
        );
        const b = TerminalConfig(
          fontSize: 16,
          theme: 'light',
          scrollback: 1000,
        );
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different fields make unequal', () {
        expect(
          const TerminalConfig(fontSize: 14),
          isNot(equals(const TerminalConfig(fontSize: 16))),
        );
        expect(
          const TerminalConfig(theme: 'dark'),
          isNot(equals(const TerminalConfig(theme: 'light'))),
        );
        expect(
          const TerminalConfig(scrollback: 5000),
          isNot(equals(const TerminalConfig(scrollback: 10000))),
        );
      });

      test('not equal to different type', () {
        expect(const TerminalConfig() == Object(), isFalse);
      });
    });

    group('typed round-trip', () {
      test('preserves valid values through DbTerminalConfig', () {
        const config = TerminalConfig(
          fontSize: 18,
          theme: 'dark',
          scrollback: 2000,
        );
        final restored = TerminalConfig.fromTyped(config.toTyped());
        expect(restored, config);
      });
    });
  });

  // ===== SshDefaults =====
  group('SshDefaults', () {
    group('defaults', () {
      test('has expected default values', () {
        const config = SshDefaults();
        expect(config.keepAliveSec, 30);
        expect(config.defaultPort, 22);
        expect(config.sshTimeoutSec, 10);
      });

      test('static defaults matches default constructor', () {
        expect(SshDefaults.defaults, const SshDefaults());
      });
    });

    group('copyWith()', () {
      test('replaces specified fields', () {
        const config = SshDefaults();
        final copy = config.copyWith(defaultPort: 2222);
        expect(copy.defaultPort, 2222);
        expect(copy.keepAliveSec, config.keepAliveSec);
        expect(copy.sshTimeoutSec, config.sshTimeoutSec);
      });

      test('returns equal object when no arguments given', () {
        const config = SshDefaults(
          keepAliveSec: 60,
          defaultPort: 2222,
          sshTimeoutSec: 30,
        );
        expect(config.copyWith(), config);
      });
    });

    group('typed round-trip', () {
      test('preserves valid values through DbSshDefaults', () {
        const config = SshDefaults(
          keepAliveSec: 60,
          defaultPort: 2222,
          sshTimeoutSec: 15,
          verboseConnectionLog: true,
        );
        final restored = SshDefaults.fromTyped(config.toTyped());
        expect(restored, config);
        expect(restored.verboseConnectionLog, isTrue);
      });
    });
  });

  // ===== UiConfig =====
  group('UiConfig', () {
    group('defaults', () {
      test('has expected default values', () {
        const config = UiConfig();
        expect(config.toastDurationMs, 4000);
        expect(config.windowWidth, 1100);
        expect(config.windowHeight, 650);
        expect(config.uiScale, 1.0);
        expect(config.showFolderSizes, isFalse);
      });

      test('static defaults matches default constructor', () {
        expect(UiConfig.defaults, const UiConfig());
      });
    });

    group('copyWith()', () {
      test('replaces specified fields', () {
        const config = UiConfig();
        final copy = config.copyWith(windowWidth: 1920);
        expect(copy.windowWidth, 1920);
        expect(copy.toastDurationMs, config.toastDurationMs);
        expect(copy.windowHeight, config.windowHeight);
      });
    });

    group('typed round-trip', () {
      test('preserves valid values through DbUiConfig', () {
        const config = UiConfig(
          toastDurationMs: 3000,
          windowWidth: 1920,
          windowHeight: 1080,
          uiScale: 1.25,
          showFolderSizes: true,
        );
        final restored = UiConfig.fromTyped(config.toTyped());
        expect(restored, config);
      });
    });
  });

  // ===== BehaviorConfig =====
  group('BehaviorConfig', () {
    test('defaults match constructor', () {
      const config = BehaviorConfig();
      expect(config.logLevel, isNull);
      expect(config.checkUpdatesOnStart, isTrue);
      expect(config.skippedVersion, isNull);
      expect(config.fido2PreferDirectHid, isFalse);
    });

    test('copyWith preserves and replaces fields', () {
      const config = BehaviorConfig(logLevel: LogLevel.info);
      final copy = config.copyWith(checkUpdatesOnStart: false);
      expect(copy.logLevel, LogLevel.info);
      expect(copy.checkUpdatesOnStart, isFalse);
    });

    test('copyWith clears nullable logLevel with explicit null', () {
      const config = BehaviorConfig(logLevel: LogLevel.warn);
      final copy = config.copyWith(logLevel: null);
      expect(copy.logLevel, isNull);
    });

    test('copyWith clears nullable skippedVersion with explicit null', () {
      const config = BehaviorConfig(skippedVersion: '1.0.0');
      final copy = config.copyWith(skippedVersion: null);
      expect(copy.skippedVersion, isNull);
    });

    group('typed round-trip', () {
      test('preserves logLevel + flags through DbBehaviorConfig', () {
        const config = BehaviorConfig(
          logLevel: LogLevel.warn,
          checkUpdatesOnStart: false,
          skippedVersion: '2.0.0',
          fido2PreferDirectHid: true,
        );
        final restored = BehaviorConfig.fromTyped(config.toTyped());
        expect(restored, config);
      });

      test('null logLevel survives the round-trip', () {
        const config = BehaviorConfig();
        expect(BehaviorConfig.fromTyped(config.toTyped()).logLevel, isNull);
      });
    });
  });

  // ===== AppConfig =====
  group('AppConfig', () {
    group('defaults', () {
      test('has expected default values', () {
        const config = AppConfig();
        expect(config.terminal, const TerminalConfig());
        expect(config.ssh, const SshDefaults());
        expect(config.ui, const UiConfig());
        expect(config.transferWorkers, 2);
        expect(config.maxHistory, 500);
        expect(config.logLevel, isNull);
        expect(config.checkUpdatesOnStart, isTrue);
        expect(config.skippedVersion, isNull);
        expect(config.locale, isNull);
        expect(config.security, isNull);
        expect(config.securityProbeCache, isNull);
        expect(
          config.recordingsStorageCapBytes,
          AppConfig.defaultRecordingsStorageCapBytes,
        );
      });

      test('static defaults matches default constructor', () {
        expect(AppConfig.defaults, const AppConfig());
      });
    });

    group('convenience accessors', () {
      test('fontSize / theme / scrollback delegate to terminal', () {
        const config = AppConfig(
          terminal: TerminalConfig(
            fontSize: 20,
            theme: 'light',
            scrollback: 3000,
          ),
        );
        expect(config.fontSize, 20);
        expect(config.theme, 'light');
        expect(config.scrollback, 3000);
      });

      test('keepAliveSec / defaultPort / sshTimeoutSec delegate to ssh', () {
        const config = AppConfig(
          ssh: SshDefaults(
            keepAliveSec: 60,
            defaultPort: 2222,
            sshTimeoutSec: 20,
          ),
        );
        expect(config.keepAliveSec, 60);
        expect(config.defaultPort, 2222);
        expect(config.sshTimeoutSec, 20);
      });

      test('toastDurationMs / windowWidth / windowHeight delegate to ui', () {
        const config = AppConfig(
          ui: UiConfig(
            toastDurationMs: 2000,
            windowWidth: 1920,
            windowHeight: 1080,
          ),
        );
        expect(config.toastDurationMs, 2000);
        expect(config.windowWidth, 1920);
        expect(config.windowHeight, 1080);
      });
    });

    group('copyWith()', () {
      test('replaces sub-configs and scalars', () {
        const config = AppConfig();
        final copy = config.copyWith(
          terminal: const TerminalConfig(fontSize: 20),
          ssh: const SshDefaults(defaultPort: 2222),
          ui: const UiConfig(windowWidth: 1920),
          transferWorkers: 8,
          maxHistory: 100,
        );
        expect(copy.terminal.fontSize, 20);
        expect(copy.ssh.defaultPort, 2222);
        expect(copy.ui.windowWidth, 1920);
        expect(copy.transferWorkers, 8);
        expect(copy.maxHistory, 100);
      });

      test('replaces logLevel via behavior.copyWith', () {
        const config = AppConfig();
        final copy = config.copyWith(
          behavior: config.behavior.copyWith(logLevel: LogLevel.info),
        );
        expect(copy.logLevel, LogLevel.info);
      });

      test('replaces locale with value', () {
        final copy = const AppConfig().copyWith(locale: 'ru');
        expect(copy.locale, 'ru');
      });

      test('clears locale with explicit null', () {
        const config = AppConfig(locale: 'de');
        final copy = config.copyWith(locale: null);
        expect(copy.locale, isNull);
      });

      test('preserves locale when not specified', () {
        const config = AppConfig(locale: 'ja');
        final copy = config.copyWith(transferWorkers: 4);
        expect(copy.locale, 'ja');
      });
    });

    group('copyWithSecurity()', () {
      test('replaces security only', () {
        const config = AppConfig();
        final copy = config.copyWithSecurity(
          security: const SecurityConfig(
            tier: SecurityTier.hardware,
            modifiers: SecurityTierModifiers(password: true),
          ),
        );
        expect(copy.security?.tier, SecurityTier.hardware);
        expect(copy.security?.modifiers.password, isTrue);
        expect(copy.terminal, config.terminal);
        expect(copy.ssh, config.ssh);
      });

      test('clears security with explicit null', () {
        const config = AppConfig(
          security: SecurityConfig(
            tier: SecurityTier.keychain,
            modifiers: SecurityTierModifiers.defaults,
          ),
        );
        final copy = config.copyWithSecurity(security: null);
        expect(copy.security, isNull);
      });

      test('preserves security when omitted', () {
        const config = AppConfig(
          security: SecurityConfig(
            tier: SecurityTier.paranoid,
            modifiers: SecurityTierModifiers.defaults,
          ),
        );
        final copy = config.copyWithSecurity();
        expect(copy.security?.tier, SecurityTier.paranoid);
      });
    });

    group('equality and hashCode', () {
      test('equal AppConfigs are equal', () {
        const a = AppConfig(
          transferWorkers: 4,
          maxHistory: 100,
          behavior: BehaviorConfig(logLevel: LogLevel.info),
        );
        const b = AppConfig(
          transferWorkers: 4,
          maxHistory: 100,
          behavior: BehaviorConfig(logLevel: LogLevel.info),
        );
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different scalar fields make unequal', () {
        expect(
          const AppConfig(transferWorkers: 2),
          isNot(equals(const AppConfig(transferWorkers: 4))),
        );
        expect(
          const AppConfig(maxHistory: 500),
          isNot(equals(const AppConfig(maxHistory: 1000))),
        );
        expect(
          const AppConfig(locale: 'en'),
          isNot(equals(const AppConfig(locale: 'ru'))),
        );
      });

      test('different sub-configs make unequal', () {
        expect(
          const AppConfig(terminal: TerminalConfig(fontSize: 14)),
          isNot(
            equals(const AppConfig(terminal: TerminalConfig(fontSize: 20))),
          ),
        );
        expect(
          const AppConfig(ssh: SshDefaults(defaultPort: 22)),
          isNot(equals(const AppConfig(ssh: SshDefaults(defaultPort: 2222)))),
        );
      });

      test('identical returns true for same instance', () {
        const config = AppConfig();
        expect(config == config, isTrue);
      });

      test('not equal to different type', () {
        expect(const AppConfig() == Object(), isFalse);
      });
    });

    group('typed round-trip', () {
      test('preserves the full envelope through DbAppConfigSnapshot', () {
        const config = AppConfig(
          terminal: TerminalConfig(
            fontSize: 18,
            theme: 'dark',
            scrollback: 2000,
          ),
          ssh: SshDefaults(
            keepAliveSec: 60,
            defaultPort: 2222,
            sshTimeoutSec: 15,
          ),
          ui: UiConfig(
            toastDurationMs: 2000,
            windowWidth: 1920,
            windowHeight: 1080,
            uiScale: 1.25,
            showFolderSizes: true,
          ),
          transferWorkers: 4,
          maxHistory: 1000,
          behavior: BehaviorConfig(
            logLevel: LogLevel.info,
            checkUpdatesOnStart: false,
            skippedVersion: '2.0.0',
            fido2PreferDirectHid: true,
          ),
          locale: 'ru',
        );
        final restored = AppConfig.fromTyped(config.toTyped());
        expect(restored, config);
      });

      test('preserves recordingsStorageCapBytes', () {
        const config = AppConfig(recordingsStorageCapBytes: 750 * 1024 * 1024);
        final restored = AppConfig.fromTyped(config.toTyped());
        expect(restored.recordingsStorageCapBytes, 750 * 1024 * 1024);
      });

      test('preserves security tier + modifiers', () {
        const config = AppConfig(
          security: SecurityConfig(
            tier: SecurityTier.hardware,
            modifiers: SecurityTierModifiers(password: true, biometric: true),
          ),
        );
        final restored = AppConfig.fromTyped(config.toTyped());
        expect(restored.security, config.security);
      });

      test('preserves null security', () {
        const config = AppConfig();
        final restored = AppConfig.fromTyped(config.toTyped());
        expect(restored.security, isNull);
      });

      const probe = DbSecurityCapabilities(
        keychainAvailable: true,
        hardwareVaultAvailable: true,
        biometricAvailable: false,
        fprintdAvailable: false,
        isLinuxHost: true,
        keychainProbe: DbKeyringProbeResult.available,
        hardwareProbeCode: 'ok',
      );

      test('toTyped prefers the passed probe cache over the local field', () {
        // The probe cache is Rust-owned; the persist path passes the
        // live value so an unrelated settings write cannot clobber it
        // with the typically-stale Dart field (a null).
        const config = AppConfig(); // securityProbeCache: null
        expect(config.toTyped(probeCache: probe).securityProbeCache, probe);
      });

      test('toTyped falls back to the local probe cache when none passed', () {
        const config = AppConfig(securityProbeCache: probe);
        expect(config.toTyped().securityProbeCache, probe);
      });
    });

    group('canonical JSON via Rust', () {
      test('sanitises out-of-range fontSize through the JSON parser', () {
        // The Rust canonicaliser clamps every field on the way out.
        // `cfg.toTyped()` builds the DTO verbatim from in-memory
        // values — the sanitiser runs only when the typed value
        // crosses into the store actor (or through the explicit
        // JSON round-trip used here for export / archive).
        const config = AppConfig(terminal: TerminalConfig(fontSize: 1));
        final json = rust_config.configAppConfigToJsonTyped(
          value: config.toTyped(),
        );
        final back = rust_config.configAppConfigFromJsonTyped(inputJson: json);
        expect(back, isNotNull);
        expect(AppConfig.fromTyped(back!).terminal.fontSize, 6);
      });

      test('sanitises invalid locale to null through the JSON parser', () {
        const config = AppConfig(locale: 'xx-not-a-locale');
        final json = rust_config.configAppConfigToJsonTyped(
          value: config.toTyped(),
        );
        final back = rust_config.configAppConfigFromJsonTyped(inputJson: json);
        expect(back, isNotNull);
        expect(AppConfig.fromTyped(back!).locale, isNull);
      });

      test(
        'sanitises negative maxHistory back to default through the JSON parser',
        () {
          const config = AppConfig(maxHistory: -1);
          final json = rust_config.configAppConfigToJsonTyped(
            value: config.toTyped(),
          );
          final back = rust_config.configAppConfigFromJsonTyped(
            inputJson: json,
          );
          expect(back, isNotNull);
          expect(
            AppConfig.fromTyped(back!).maxHistory,
            AppConfig.defaults.maxHistory,
          );
        },
      );

      test(
        'sanitises zero transferWorkers back to default through the JSON parser',
        () {
          const config = AppConfig(transferWorkers: 0);
          final json = rust_config.configAppConfigToJsonTyped(
            value: config.toTyped(),
          );
          final back = rust_config.configAppConfigFromJsonTyped(
            inputJson: json,
          );
          expect(back, isNotNull);
          expect(
            AppConfig.fromTyped(back!).transferWorkers,
            AppConfig.defaults.transferWorkers,
          );
        },
      );

      test('configAppConfigToJsonTyped emits flat top-level keys', () {
        final json = rust_config.configAppConfigToJsonTyped(
          value: const AppConfig().toTyped(),
        );
        // Flat top-level keys — sub-struct fields land directly.
        expect(json, contains('"font_size"'));
        expect(json, contains('"default_port"'));
        expect(json, contains('"toast_duration_ms"'));
        expect(json, contains('"check_updates_on_start"'));
      });

      test(
        'configAppConfigStripForExportTyped drops per-host security fields',
        () {
          final json = rust_config.configAppConfigStripForExportTyped(
            value: const AppConfig(
              security: SecurityConfig(
                tier: SecurityTier.hardware,
                modifiers: SecurityTierModifiers.defaults,
              ),
            ).toTyped(),
          );
          expect(json, isNot(contains('"security_tier"')));
          expect(json, isNot(contains('"security_modifiers"')));
          // Non-security fields survive.
          expect(json, contains('"font_size"'));
        },
      );

      test(
        'configAppConfigFromJsonTyped round-trips through the canonical JSON',
        () {
          const config = AppConfig(
            terminal: TerminalConfig(fontSize: 18, theme: 'dark'),
            locale: 'ja',
          );
          final json = rust_config.configAppConfigToJsonTyped(
            value: config.toTyped(),
          );
          final back = rust_config.configAppConfigFromJsonTyped(
            inputJson: json,
          );
          expect(back, isNotNull);
          final restored = AppConfig.fromTyped(back!);
          expect(restored, config);
        },
      );

      test('configAppConfigFromJsonTyped returns null for malformed JSON', () {
        expect(
          rust_config.configAppConfigFromJsonTyped(inputJson: 'not json'),
          isNull,
        );
      });
    });

    group('security tier persistence', () {
      test('fresh config has null security — triggers wizard', () {
        // The wizard fires when AppConfig.security is null. After the
        // user completes the wizard the field is non-null for every
        // tier, including plaintext, so the wizard never fires twice.
        expect(const AppConfig().security, isNull);
      });

      test('typed round-trip preserves paranoid tier', () {
        const config = AppConfig(
          security: SecurityConfig(
            tier: SecurityTier.paranoid,
            modifiers: SecurityTierModifiers.defaults,
          ),
        );
        final restored = AppConfig.fromTyped(config.toTyped());
        expect(restored.security, config.security);
      });
    });
  });
}
