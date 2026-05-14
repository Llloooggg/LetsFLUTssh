import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../helpers/frb_bootstrap.dart';

/// Fuzz tests for the AppConfig JSON parser.
///
/// The Dart side no longer carries a Map-based decoder; the
/// canonical parser lives in `lfs_core::config::AppConfig::
/// from_json_value` and crosses the FRB boundary via
/// `configAppConfigFromJsonTyped`. The fuzz targets the same
/// untrusted-input shape (hand-edited `config.json`, archive
/// `config.json` blob) through that entrypoint.
///
/// Contract: the parser either returns a valid [AppConfig] (every
/// field clamped inside its sanitiser range) or `null` for a blob
/// that fails serde JSON parsing at the top level. Never throws,
/// never crashes the process.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('Fuzz configAppConfigFromJsonTyped (Rust canonical parser)', () {
    final rng = Random(42);

    test('handles 1000 random composite blobs without crashing', () {
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
        final encoded = _safeJsonEncode(json);
        if (encoded == null) continue;
        final typed = rust_config.configAppConfigFromJsonTyped(
          inputJson: encoded,
        );
        if (typed != null) {
          // Sanitiser clamps every field — the build-side Dart
          // wrapper accepts the snapshot without further coercion.
          AppConfig.fromTyped(typed);
        }
      }
    });

    test('handles map with all wrong types — never crashes', () {
      final pathological = jsonEncode({
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
        'check_updates_on_start': 0,
        'transfer_workers': 'four',
        'max_history': 9.99,
      });
      final typed = rust_config.configAppConfigFromJsonTyped(
        inputJson: pathological,
      );
      // Parser tolerates the wrong types — falls back to defaults
      // for every field that fails its serde guard. Shape lands as
      // canonical AppConfig defaults.
      expect(typed, isNotNull);
    });

    test('handles extreme numeric values for fontSize', () {
      final extremes = [
        // NaN / infinities are not valid JSON numbers — serde rejects
        // the blob at the top level, the parser returns null. The
        // finite extremes survive and clamp via the sanitiser.
        double.minPositive,
        double.maxFinite,
        -1e308,
        0.0,
        -0.0,
      ];
      for (final v in extremes) {
        final encoded = _safeJsonEncode({'font_size': v});
        if (encoded == null) continue;
        final typed = rust_config.configAppConfigFromJsonTyped(
          inputJson: encoded,
        );
        if (typed != null) {
          final config = AppConfig.fromTyped(typed);
          expect(config.terminal.fontSize, isNotNaN);
          expect(config.terminal.fontSize, greaterThanOrEqualTo(6.0));
          expect(config.terminal.fontSize, lessThanOrEqualTo(72.0));
        }
      }
    });

    test('handles extreme port values', () {
      final ports = [-1, 0, 1, 22, 65535, 65536, -2147483648, 2147483647];
      for (final p in ports) {
        final encoded = jsonEncode({'default_port': p});
        final typed = rust_config.configAppConfigFromJsonTyped(
          inputJson: encoded,
        );
        if (typed != null) {
          final config = AppConfig.fromTyped(typed);
          expect(config.ssh.defaultPort, greaterThanOrEqualTo(1));
          expect(config.ssh.defaultPort, lessThanOrEqualTo(65535));
        }
      }
    });

    test('garbage input collapses to null', () {
      expect(
        rust_config.configAppConfigFromJsonTyped(inputJson: 'not json'),
        isNull,
      );
      expect(rust_config.configAppConfigFromJsonTyped(inputJson: ''), isNull);
      expect(
        rust_config.configAppConfigFromJsonTyped(inputJson: '[]'),
        // Array root parses as JSON but the parser returns defaults
        // (its `as_object()` guard collapses non-objects to
        // `AppConfig::default()`).
        isNotNull,
      );
    });

    test('empty object collapses to defaults', () {
      final typed = rust_config.configAppConfigFromJsonTyped(inputJson: '{}');
      expect(typed, isNotNull);
      expect(AppConfig.fromTyped(typed!), AppConfig.defaults);
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
    if (rng.nextBool()) 'log_level': _randomValue(rng),
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

/// `jsonEncode` throws on values like NaN / Infinity (Dart's JSON
/// encoder is strict). The fuzz harness skips those rather than
/// teach every test about the codec's edge cases.
String? _safeJsonEncode(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return null;
  }
}
