import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/session_manager/session_port_validator.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  // The validator routes through the same Rust grammar the
  // port-forward editor uses; bootstrap FRB so the native call
  // does not throw `flutter_rust_bridge has not been initialized`.
  setUpAll(requireFrbLoaded);

  group('isValidConnectionPort', () {
    test('accepts the legal TCP range', () {
      expect(isValidConnectionPort('1'), isTrue);
      expect(isValidConnectionPort('22'), isTrue);
      expect(isValidConnectionPort('65535'), isTrue);
    });

    test('rejects out-of-range numbers', () {
      expect(isValidConnectionPort('0'), isFalse);
      expect(isValidConnectionPort('-1'), isFalse);
      expect(isValidConnectionPort('65536'), isFalse);
      expect(isValidConnectionPort('999999'), isFalse);
    });

    test('rejects null, empty, and non-numeric input', () {
      // The form-validator caller passes the raw controller text;
      // every shape that cannot be parsed as a single decimal int
      // must reject so the dialog gates Save / Connect on a clear
      // grammar error and never converts a bad string to the
      // silent fallback (22).
      expect(isValidConnectionPort(null), isFalse);
      expect(isValidConnectionPort(''), isFalse);
      expect(isValidConnectionPort('   '), isFalse);
      expect(isValidConnectionPort('22a'), isFalse);
      expect(isValidConnectionPort('twenty-two'), isFalse);
    });
  });
}
