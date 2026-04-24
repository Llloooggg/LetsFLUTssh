import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/security_reinit_provider.dart';

void main() {
  group('securityReinitProvider', () {
    test('starts at 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(securityReinitProvider), 0);
    });

    test('bump() advances the counter so listeners see each event', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(securityReinitProvider.notifier);
      notifier.bump();
      expect(container.read(securityReinitProvider), 1);
      notifier.bump();
      expect(container.read(securityReinitProvider), 2);
    });

    test('each bump is distinct so listenManual fires every time', () {
      // Riverpod suppresses `==`-equal state emissions; the counter
      // shape guarantees every `bump` is a strictly new value so
      // `ref.listenManual(securityReinitProvider, …)` delivers one
      // callback per event. Two sequential resets on a boolean
      // toggle would coalesce — this test pins the counter
      // contract.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final observed = <int>[];
      container.listen<int>(
        securityReinitProvider,
        (prev, next) => observed.add(next),
      );
      final notifier = container.read(securityReinitProvider.notifier);
      notifier.bump();
      notifier.bump();
      notifier.bump();
      expect(observed, [1, 2, 3]);
    });
  });
}
