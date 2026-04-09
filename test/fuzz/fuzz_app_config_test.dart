import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';

/// Fuzz tests for [AppConfig.fromJson] and sub-config parsers.
///
/// Verifies that no malformed config JSON can crash the parser.
/// All fromJson methods must either return a valid object or throw
/// a predictable type error — never an unhandled exception.
void main() {
  group('Fuzz TerminalConfig.fromJson', () {
    final rng = Random(42);

    test('handles 1000 random configs without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final json = _randomTerminalJson(rng);
        try {
          final config = TerminalConfig.fromJson(json);
          // Sanitized config must always be valid
          expect(config.validate(), isNull);
        } on TypeError {
          // Expected for type mismatches
        }
      }
    });

    test('handles extreme numeric values', () {
      final extremes = [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        double.minPositive,
        double.maxFinite,
        -1e308,
        0.0,
        -0.0,
      ];
      for (final v in extremes) {
        try {
          final config = TerminalConfig.fromJson({'font_size': v});
          // Sanitized config clamps to valid range
          expect(config.fontSize, isNotNaN);
        } on TypeError {
          // Expected
        }
      }
    });
  });

  group('Fuzz SshDefaults.fromJson', () {
    final rng = Random(42);

    test('handles 1000 random configs without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final json = _randomSshJson(rng);
        try {
          final config = SshDefaults.fromJson(json);
          expect(config.validate(), isNull);
        } on TypeError {
          // Expected
        }
      }
    });

    test('handles extreme port values', () {
      final ports = [-1, 0, 1, 22, 65535, 65536, -2147483648, 2147483647];
      for (final p in ports) {
        final config = SshDefaults.fromJson({'default_port': p});
        // Sanitized port must be in valid range
        expect(config.defaultPort, greaterThanOrEqualTo(1));
        expect(config.defaultPort, lessThanOrEqualTo(65535));
      }
    });
  });

  group('Fuzz UiConfig.fromJson', () {
    final rng = Random(42);

    test('handles 1000 random configs without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final json = _randomUiJson(rng);
        try {
          UiConfig.fromJson(json);
        } on TypeError {
          // Expected
        }
      }
    });
  });

  group('Fuzz BehaviorConfig.fromJson', () {
    final rng = Random(42);

    test('handles 1000 random configs without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final json = _randomBehaviorJson(rng);
        try {
          BehaviorConfig.fromJson(json);
        } on TypeError {
          // Expected
        }
      }
    });
  });

  group('Fuzz AppConfig.fromJson', () {
    final rng = Random(42);

    test('handles 1000 random composite configs without crashing', () {
      for (var i = 0; i < 1000; i++) {
        final json = <String, dynamic>{
          ..._randomTerminalJson(rng),
          ..._randomSshJson(rng),
          ..._randomUiJson(rng),
          ..._randomBehaviorJson(rng),
          if (rng.nextBool()) 'transfer_workers': _randomValue(rng),
          if (rng.nextBool()) 'max_history': _randomValue(rng),
          if (rng.nextBool()) 'locale': _randomValue(rng),
        };
        try {
          AppConfig.fromJson(json);
        } on TypeError {
          // Expected
        }
      }
    });

    test('handles empty map', () {
      final config = AppConfig.fromJson({});
      expect(config, isNotNull);
    });

    test('handles map with all wrong types', () {
      try {
        AppConfig.fromJson({
          'font_size': 'big',
          'theme': 42,
          'scrollback': 'lots',
          'keepalive_sec': false,
          'default_port': 'twenty-two',
          'ssh_timeout_sec': [],
          'toast_duration_ms': {},
          'window_width': true,
          'window_height': null,
          'ui_scale': 'large',
          'enable_logging': 'yes',
          'check_updates_on_start': 0,
          'transfer_workers': 'four',
          'max_history': 9.99,
        });
      } on TypeError {
        // Expected
      }
    });
  });
}

Map<String, dynamic> _randomTerminalJson(Random rng) {
  return {
    if (rng.nextBool()) 'font_size': _randomValue(rng),
    if (rng.nextBool()) 'theme': _randomValue(rng),
    if (rng.nextBool()) 'scrollback': _randomValue(rng),
  };
}

Map<String, dynamic> _randomSshJson(Random rng) {
  return {
    if (rng.nextBool()) 'keepalive_sec': _randomValue(rng),
    if (rng.nextBool()) 'default_port': _randomValue(rng),
    if (rng.nextBool()) 'ssh_timeout_sec': _randomValue(rng),
  };
}

Map<String, dynamic> _randomUiJson(Random rng) {
  return {
    if (rng.nextBool()) 'toast_duration_ms': _randomValue(rng),
    if (rng.nextBool()) 'window_width': _randomValue(rng),
    if (rng.nextBool()) 'window_height': _randomValue(rng),
    if (rng.nextBool()) 'ui_scale': _randomValue(rng),
    if (rng.nextBool()) 'show_folder_sizes': _randomValue(rng),
  };
}

Map<String, dynamic> _randomBehaviorJson(Random rng) {
  return {
    if (rng.nextBool()) 'enable_logging': _randomValue(rng),
    if (rng.nextBool()) 'check_updates_on_start': _randomValue(rng),
    if (rng.nextBool()) 'skipped_version': _randomValue(rng),
  };
}

Object? _randomValue(Random rng) {
  switch (rng.nextInt(10)) {
    case 0:
      return null;
    case 1:
      return rng.nextInt(100000) - 50000;
    case 2:
      return rng.nextDouble() * 200 - 100;
    case 3:
      return rng.nextBool();
    case 4:
      return '';
    case 5:
      return 'dark';
    case 6:
      return 'light';
    case 7:
      return 'system';
    case 8:
      return <String>[];
    default:
      return 'random_${rng.nextInt(999)}';
  }
}
