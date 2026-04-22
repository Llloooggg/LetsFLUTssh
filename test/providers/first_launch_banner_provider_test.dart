import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/first_launch_banner_provider.dart';

void main() {
  group('defaultHardwareUnavailableReason', () {
    // The function keys off Platform, which is not override-able in pure
    // VM tests. We assert only the current-host branch here — other
    // platforms are validated manually during the per-OS release smoke
    // pass. The goal is a canary against a refactor that drops the host
    // branch entirely.
    test('returns the expected per-host default on the test runner', () {
      final reason = defaultHardwareUnavailableReason();
      if (Platform.isWindows) {
        expect(reason, HardwareUnavailableReason.noTpm);
      } else if (Platform.isMacOS || Platform.isIOS) {
        expect(reason, HardwareUnavailableReason.noSecureEnclave);
      } else if (Platform.isLinux) {
        expect(reason, HardwareUnavailableReason.noTpm2Tools);
      } else if (Platform.isAndroid) {
        expect(reason, HardwareUnavailableReason.noAndroidKeystoreHardware);
      } else {
        expect(reason, HardwareUnavailableReason.generic);
      }
    });

    test('enum enumerates every documented reason, unchanged order', () {
      // Order locks the probe order documented in ARCHITECTURE §13.
      // Reordering changes the "first match wins" behaviour of the
      // capability probe and is a breaking change.
      expect(HardwareUnavailableReason.values, <HardwareUnavailableReason>[
        HardwareUnavailableReason.noSecureEnclave,
        HardwareUnavailableReason.noTpm,
        HardwareUnavailableReason.noTpm2Tools,
        HardwareUnavailableReason.noAndroidKeystoreHardware,
        HardwareUnavailableReason.generic,
      ]);
    });
  });

  group('hardwareUnavailableReasonText', () {
    testWidgets('always resolves to the generic string regardless of reason', (
      tester,
    ) async {
      // The per-platform variants were a best-guess inference that
      // misled users; the current implementation deliberately collapses
      // every reason to the generic copy. This test locks that contract
      // — a future "helpful" expansion must update the assertions here
      // to be visible in review.
      late S l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.supportedLocales,
          home: Builder(
            builder: (ctx) {
              l10n = S.of(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final generic = l10n.firstLaunchSecurityHardwareUnavailableGeneric;
      for (final reason in HardwareUnavailableReason.values) {
        expect(
          hardwareUnavailableReasonText(l10n, reason),
          generic,
          reason:
              'Every reason must surface the generic string until a '
              'real root-cause probe lands.',
        );
      }
    });
  });

  group('FirstLaunchBannerData', () {
    test('holds the fields the banner renders, no defaults', () {
      const data = FirstLaunchBannerData(
        activeTier: SecurityTier.keychain,
        hardwareUpgradeAvailable: true,
        hardwareUnavailableReason: HardwareUnavailableReason.noTpm,
      );
      expect(data.activeTier, SecurityTier.keychain);
      expect(data.hardwareUpgradeAvailable, isTrue);
      expect(data.hardwareUnavailableReason, HardwareUnavailableReason.noTpm);
    });

    test('hardwareUnavailableReason is optional', () {
      const data = FirstLaunchBannerData(
        activeTier: SecurityTier.keychain,
        hardwareUpgradeAvailable: true,
      );
      expect(data.hardwareUnavailableReason, isNull);
    });
  });

  group('firstLaunchBannerProvider', () {
    test('builds as null — no banner until auto-setup reports one', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(firstLaunchBannerProvider), isNull);
    });

    test('set(value) flips state and set(null) dismisses', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(firstLaunchBannerProvider.notifier);
      const data = FirstLaunchBannerData(
        activeTier: SecurityTier.keychain,
        hardwareUpgradeAvailable: false,
        hardwareUnavailableReason: HardwareUnavailableReason.generic,
      );
      notifier.set(data);
      expect(container.read(firstLaunchBannerProvider), same(data));
      notifier.set(null);
      expect(container.read(firstLaunchBannerProvider), isNull);
    });
  });
}
