import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/utils/secret_controller.dart';

void main() {
  group('SecretController.wipeAndClear', () {
    test('overwrites text with null bytes then clears', () {
      final ctrl = TextEditingController(text: 'hunter2');
      // Capture the listener's view of the value to ensure no listener
      // ever sees the original secret after wipeAndClear is called.
      String? observed;
      ctrl.addListener(() => observed = ctrl.text);

      ctrl.wipeAndClear();

      expect(ctrl.text, isEmpty);
      // Listener fired at least once with non-secret content.
      expect(observed, isNotNull);
      expect(
        observed,
        anyOf(isEmpty, equals('\u0000\u0000\u0000\u0000\u0000\u0000\u0000')),
      );

      ctrl.dispose();
    });

    test('idempotent on an empty controller', () {
      final ctrl = TextEditingController();
      expect(() => ctrl.wipeAndClear(), returnsNormally);
      expect(ctrl.text, isEmpty);
      ctrl.dispose();
    });

    test(
      'intermediate overwrite preserves length so listeners cannot infer the secret length post-wipe',
      () {
        final ctrl = TextEditingController(text: 'abc');
        String? lastNonEmpty;
        ctrl.addListener(() {
          if (ctrl.text.isNotEmpty) lastNonEmpty = ctrl.text;
        });

        ctrl.wipeAndClear();

        // The intermediate overwrite (before clear()) must have been
        // null-byte filler of the original length.
        expect(lastNonEmpty, '\u0000\u0000\u0000');
        ctrl.dispose();
      },
    );
  });
}
