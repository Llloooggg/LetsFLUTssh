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

      test('replaces verboseConnectionLog', () {
        expect(
          const SshDefaults()
              .copyWith(verboseConnectionLog: true)
              .verboseConnectionLog,
          isTrue,
        );
      });
    });

    group('equality and hashCode', () {
      test('equal SshDefaults hash equal', () {
        const a = SshDefaults(keepAliveSec: 45, verboseConnectionLog: true);
        const b = SshDefaults(keepAliveSec: 45, verboseConnectionLog: true);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('each field flips equality independently', () {
        const base = SshDefaults();
        expect(base, isNot(equals(const SshDefaults(keepAliveSec: 99))));
        expect(base, isNot(equals(const SshDefaults(defaultPort: 23))));
        expect(base, isNot(equals(const SshDefaults(sshTimeoutSec: 99))));
        expect(
          base,
          isNot(equals(const SshDefaults(verboseConnectionLog: true))),
        );
      });

      test('not equal to a different type', () {
        const Object other = 'ssh';
        expect(const SshDefaults() == other, isFalse);
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

      test('replaces uiScale and showFolderSizes', () {
        final copy = const UiConfig().copyWith(
          uiScale: 1.5,
          showFolderSizes: true,
        );
        expect(copy.uiScale, 1.5);
        expect(copy.showFolderSizes, isTrue);
      });

      test('returns equal object when no arguments given', () {
        const config = UiConfig(uiScale: 1.25, showFolderSizes: true);
        expect(config.copyWith(), config);
      });
    });

    group('equality and hashCode', () {
      test('equal UiConfigs hash equal', () {
        const a = UiConfig(uiScale: 1.25, showFolderSizes: true);
        const b = UiConfig(uiScale: 1.25, showFolderSizes: true);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('each field flips equality independently', () {
        const base = UiConfig();
        expect(base, isNot(equals(const UiConfig(toastDurationMs: 1))));
        expect(base, isNot(equals(const UiConfig(windowWidth: 1))));
        expect(base, isNot(equals(const UiConfig(windowHeight: 1))));
        expect(base, isNot(equals(const UiConfig(uiScale: 2))));
        expect(base, isNot(equals(const UiConfig(showFolderSizes: true))));
      });

      test('not equal to a different type', () {
        const Object other = 'ui';
        expect(const UiConfig() == other, isFalse);
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

    test('copyWith preserves nullable logLevel when omitted (sentinel)', () {
      // The `_unset` sentinel default distinguishes "not passed" from
      // "passed null". Omitting logLevel must leave the current value
      // — a regression to `logLevel ?? this.logLevel` would make
      // clearing impossible; a regression the other way would wipe the
      // value on any unrelated copyWith.
      const config = BehaviorConfig(logLevel: LogLevel.error);
      final copy = config.copyWith(checkUpdatesOnStart: false);
      expect(copy.logLevel, LogLevel.error);
    });

    test('copyWith preserves nullable skippedVersion when omitted', () {
      const config = BehaviorConfig(skippedVersion: '3.1.4');
      final copy = config.copyWith(checkUpdatesOnStart: false);
      expect(copy.skippedVersion, '3.1.4');
    });

    test('copyWith replaces fido2PreferDirectHid', () {
      const config = BehaviorConfig();
      expect(
        config.copyWith(fido2PreferDirectHid: true).fido2PreferDirectHid,
        isTrue,
      );
    });

    test('copyWith with no args returns an equal config', () {
      const config = BehaviorConfig(
        logLevel: LogLevel.warn,
        checkUpdatesOnStart: false,
        skippedVersion: '1.2.3',
        fido2PreferDirectHid: true,
      );
      expect(config.copyWith(), config);
    });

    group('equality and hashCode', () {
      test('equal BehaviorConfigs hash equal', () {
        const a = BehaviorConfig(logLevel: LogLevel.info, skippedVersion: 'v');
        const b = BehaviorConfig(logLevel: LogLevel.info, skippedVersion: 'v');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('each field flips equality independently', () {
        const base = BehaviorConfig();
        expect(
          base,
          isNot(equals(const BehaviorConfig(logLevel: LogLevel.info))),
        );
        expect(
          base,
          isNot(equals(const BehaviorConfig(checkUpdatesOnStart: false))),
        );
        expect(base, isNot(equals(const BehaviorConfig(skippedVersion: 'x'))));
        expect(
          base,
          isNot(equals(const BehaviorConfig(fido2PreferDirectHid: true))),
        );
      });

      test('not equal to a different type', () {
        const Object other = 'behavior';
        expect(const BehaviorConfig() == other, isFalse);
      });
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

      test('replaces recordingsStorageCapBytes', () {
        final copy = const AppConfig().copyWith(recordingsStorageCapBytes: 123);
        expect(copy.recordingsStorageCapBytes, 123);
      });

      test('preserves security and securityProbeCache untouched', () {
        // copyWith is the non-security axis — it must carry the
        // security fields through verbatim so a preferences change
        // never wipes the tier or the Rust-owned probe cache.
        const config = AppConfig(
          security: SecurityConfig(
            tier: SecurityTier.paranoid,
            modifiers: SecurityTierModifiers.defaults,
          ),
        );
        final copy = config.copyWith(transferWorkers: 4);
        expect(copy.security?.tier, SecurityTier.paranoid);
      });

      test('with no args returns an equal config', () {
        const config = AppConfig(transferWorkers: 4, locale: 'de');
        expect(config.copyWith(), config);
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

      const probe = DbSecurityCapabilities(
        keychainAvailable: true,
        hardwareVaultAvailable: false,
        biometricAvailable: false,
        fprintdAvailable: false,
        isLinuxHost: true,
        keychainProbe: DbKeyringProbeResult.available,
        hardwareProbeCode: 'ok',
      );

      test('replaces securityProbeCache with a value', () {
        final copy = const AppConfig().copyWithSecurity(
          securityProbeCache: probe,
        );
        expect(copy.securityProbeCache, probe);
      });

      test('clears securityProbeCache with explicit null', () {
        const config = AppConfig(securityProbeCache: probe);
        final copy = config.copyWithSecurity(securityProbeCache: null);
        expect(copy.securityProbeCache, isNull);
      });

      test('preserves securityProbeCache when omitted', () {
        const config = AppConfig(securityProbeCache: probe);
        final copy = config.copyWithSecurity(security: null);
        expect(copy.securityProbeCache, probe);
      });

      test('leaves the non-security axis untouched', () {
        const config = AppConfig(transferWorkers: 7, locale: 'fr');
        final copy = config.copyWithSecurity(security: null);
        expect(copy.transferWorkers, 7);
        expect(copy.locale, 'fr');
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
        expect(
          const AppConfig(ui: UiConfig(uiScale: 1)),
          isNot(equals(const AppConfig(ui: UiConfig(uiScale: 2)))),
        );
        expect(
          const AppConfig(behavior: BehaviorConfig(logLevel: LogLevel.info)),
          isNot(
            equals(
              const AppConfig(
                behavior: BehaviorConfig(logLevel: LogLevel.warn),
              ),
            ),
          ),
        );
      });

      test('different security make unequal', () {
        expect(
          const AppConfig(
            security: SecurityConfig(
              tier: SecurityTier.keychain,
              modifiers: SecurityTierModifiers.defaults,
            ),
          ),
          isNot(
            equals(
              const AppConfig(
                security: SecurityConfig(
                  tier: SecurityTier.hardware,
                  modifiers: SecurityTierModifiers.defaults,
                ),
              ),
            ),
          ),
        );
      });

      test('different recordingsStorageCapBytes make unequal', () {
        expect(
          const AppConfig(recordingsStorageCapBytes: 1),
          isNot(equals(const AppConfig(recordingsStorageCapBytes: 2))),
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
