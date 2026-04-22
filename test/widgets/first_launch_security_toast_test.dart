import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/security_tier.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/first_launch_banner_provider.dart';
import 'package:letsflutssh/widgets/first_launch_security_toast.dart';

Widget _host({
  required FirstLaunchBannerData data,
  required VoidCallback onOpenSettings,
  required VoidCallback onDismiss,
}) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => FirstLaunchSecurityToast.show(
              ctx,
              data: data,
              onOpenSettings: onOpenSettings,
              onDismiss: onDismiss,
            ),
            child: const Text('Show'),
          ),
        ),
      ),
    ),
  );
}

const _bannerNoUpgrade = FirstLaunchBannerData(
  activeTier: SecurityTier.keychain,
  hardwareUpgradeAvailable: false,
);

const _bannerWithUpgrade = FirstLaunchBannerData(
  activeTier: SecurityTier.keychain,
  hardwareUpgradeAvailable: true,
);

void main() {
  group('FirstLaunchSecurityToast', () {
    testWidgets('renders title + body on the hardware-unavailable branch', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(data: _bannerNoUpgrade, onOpenSettings: () {}, onDismiss: () {}),
      );
      await tester.tap(find.text('Show'));
      await tester.pump();

      final l10n = S.of(tester.element(find.text('Show')));
      expect(find.text(l10n.firstLaunchSecurityTitle), findsOneWidget);
      expect(find.text(l10n.firstLaunchSecurityBody), findsOneWidget);
      // Upgrade branch not rendered → Open Settings button not present.
      expect(find.text(l10n.firstLaunchSecurityOpenSettings), findsNothing);
    });

    testWidgets(
      'renders upgrade line + Open Settings button when upgrade available',
      (tester) async {
        await tester.pumpWidget(
          _host(
            data: _bannerWithUpgrade,
            onOpenSettings: () {},
            onDismiss: () {},
          ),
        );
        await tester.tap(find.text('Show'));
        await tester.pump();

        final l10n = S.of(tester.element(find.text('Show')));
        expect(
          find.text(l10n.firstLaunchSecurityUpgradeAvailable),
          findsOneWidget,
        );
        expect(find.text(l10n.firstLaunchSecurityOpenSettings), findsOneWidget);
      },
    );

    testWidgets('close icon fires onDismiss and removes the overlay', (
      tester,
    ) async {
      var dismissed = 0;
      await tester.pumpWidget(
        _host(
          data: _bannerNoUpgrade,
          onOpenSettings: () {},
          onDismiss: () => dismissed++,
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(dismissed, 1);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('Open Settings button fires onOpenSettings + dismisses', (
      tester,
    ) async {
      var openedSettings = 0;
      var dismissed = 0;
      await tester.pumpWidget(
        _host(
          data: _bannerWithUpgrade,
          onOpenSettings: () => openedSettings++,
          onDismiss: () => dismissed++,
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pump();

      final l10n = S.of(tester.element(find.text('Show')));
      await tester.tap(find.text(l10n.firstLaunchSecurityOpenSettings));
      await tester.pump();
      expect(openedSettings, 1);
      // onDismiss is not invoked by the Open Settings path — only the
      // internal `_dismiss` side-effect runs, which clears the overlay.
      // The caller wires whatever cleanup it needs via the Settings
      // callback itself.
      expect(dismissed, 0);
      expect(find.byIcon(Icons.shield_outlined), findsNothing);
    });

    testWidgets('auto-dismisses after the display duration', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        _host(
          data: _bannerNoUpgrade,
          onOpenSettings: () {},
          onDismiss: () => dismissed++,
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

      // `_displayDuration` is 8 s; fast-forward past it.
      await tester.pump(const Duration(seconds: 9));
      expect(dismissed, 1);
      expect(find.byIcon(Icons.shield_outlined), findsNothing);
    });

    testWidgets('a second show() replaces the first overlay', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        _host(
          data: _bannerNoUpgrade,
          onOpenSettings: () {},
          onDismiss: () => dismissed++,
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.tap(find.text('Show'));
      await tester.pump();

      // Exactly one toast on screen; earlier timer cancelled so the
      // earlier onDismiss never fires.
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      expect(dismissed, 0);

      await tester.pump(const Duration(seconds: 9));
      expect(dismissed, 1);
    });
  });
}
