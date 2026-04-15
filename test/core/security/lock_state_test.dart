import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/lock_state.dart';

void main() {
  group('LockStateNotifier', () {
    test('starts unlocked', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(lockStateProvider), isFalse);
    });

    test('lock() flips to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(lockStateProvider.notifier).lock();
      expect(container.read(lockStateProvider), isTrue);
    });

    test('unlock() flips back', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(lockStateProvider.notifier);
      notifier.lock();
      notifier.unlock();
      expect(container.read(lockStateProvider), isFalse);
    });

    test('lock() is idempotent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(lockStateProvider.notifier);
      var events = 0;
      container.listen(lockStateProvider, (_, _) => events++);
      notifier.lock();
      notifier.lock();
      notifier.lock();
      expect(events, 1);
    });
  });
}
