import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/providers/version_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppVersionNotifier', () {
    test('initial state is empty string', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(appVersionProvider), '');
    });

    test('load() reads version from PackageInfo', () async {
      // Mock the platform channel that PackageInfo uses
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (call) async {
          if (call.method == 'getAll') {
            return <String, dynamic>{
              'appName': 'letsflutssh',
              'packageName': 'com.example.letsflutssh',
              'version': '1.5.0',
              'buildNumber': '106',
              'buildSignature': '',
              'installerStore': '',
            };
          }
          return null;
        },
      );

      final container = ProviderContainer();
      addTearDown(() {
        container.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          null,
        );
      });

      await container.read(appVersionProvider.notifier).load();
      expect(container.read(appVersionProvider), '1.5.0');
    });
  });
}
