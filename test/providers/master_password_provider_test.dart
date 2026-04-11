import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/master_password.dart';
import 'package:letsflutssh/providers/master_password_provider.dart';

void main() {
  group('masterPasswordProvider', () {
    test('returns MasterPasswordManager instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final manager = container.read(masterPasswordProvider);
      expect(manager, isA<MasterPasswordManager>());
    });

    test('returns same instance on repeated reads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final manager1 = container.read(masterPasswordProvider);
      final manager2 = container.read(masterPasswordProvider);
      expect(identical(manager1, manager2), isTrue);
    });
  });
}
