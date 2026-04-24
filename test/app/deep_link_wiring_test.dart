import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/deep_link_wiring.dart';
import 'package:letsflutssh/core/deeplink/deeplink_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // `AppLinks().getInitialLink()` hits a native method channel —
    // stub it so `handler.init()` doesn't throw on the test bench.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfomofa.app_links/messages'),
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfomofa.app_links/messages'),
          null,
        );
  });

  testWidgets(
    'wireDeepLinks assigns every callback on the handler + calls init',
    (tester) async {
      final handler = DeepLinkHandler();

      // Every callback is null before wiring.
      expect(handler.onConnect, isNull);
      expect(handler.onLfsFileOpened, isNull);
      expect(handler.onKeyFileOpened, isNull);
      expect(handler.onQrImport, isNull);
      expect(handler.onQrImportVersionTooNew, isNull);

      // Mount a minimal Consumer to obtain a live WidgetRef. The
      // wiring does not trigger any provider read until a callback
      // fires — safe to pass a bare ref without provider overrides.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (ctx, ref, _) {
                wireDeepLinks(handler, ref);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      // Every callback installed — a future refactor that dropped
      // one of the five URI shapes (connect / LFS / key-file / QR
      // import / QR version-too-new) would regress silently
      // otherwise.
      expect(handler.onConnect, isNotNull);
      expect(handler.onLfsFileOpened, isNotNull);
      expect(handler.onKeyFileOpened, isNotNull);
      expect(handler.onQrImport, isNotNull);
      expect(handler.onQrImportVersionTooNew, isNotNull);
    },
  );
}
