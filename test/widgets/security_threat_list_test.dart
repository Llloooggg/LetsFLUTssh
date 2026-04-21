import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/threat_vocabulary.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/security_threat_list.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: S.supportedLocales,
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

void main() {
  group('SecurityThreatList smoke', () {
    for (final tier in ThreatTier.values) {
      testWidgets('renders every threat title for ${tier.name}', (
        tester,
      ) async {
        final model = ThreatModel(
          tier: tier,
          password: tier == ThreatTier.paranoid,
        );
        await tester.pumpWidget(_wrap(SecurityThreatList(model: model)));
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(SecurityThreatList));
        final l10n = S.of(context);
        for (final threat in SecurityThreat.values) {
          expect(
            find.text(threatTitle(threat, l10n)),
            findsOneWidget,
            reason: 'Missing threat "${threat.name}" on tier "${tier.name}"',
          );
        }
      });
    }
  });

  group('locale smoke — every threat title resolves in every locale', () {
    for (final locale in S.supportedLocales) {
      testWidgets(
        'locale ${locale.languageCode}: every threat title is non-empty',
        (tester) async {
          await tester.pumpWidget(
            _wrap(
              const SecurityThreatList(
                model: ThreatModel(tier: ThreatTier.keychain, password: true),
              ),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          final context = tester.element(find.byType(SecurityThreatList));
          final l10n = S.of(context);
          for (final threat in SecurityThreat.values) {
            final t = threatTitle(threat, l10n);
            expect(
              t,
              isNotEmpty,
              reason: '${locale.languageCode}/${threat.name}',
            );
            final d = threatDescription(threat, l10n);
            expect(
              d,
              isNotEmpty,
              reason: '${locale.languageCode}/${threat.name}/desc',
            );
          }
        },
      );
    }
  });
}
