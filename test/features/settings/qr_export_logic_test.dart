import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/features/settings/qr_export_logic.dart';
import 'package:letsflutssh/src/rust/api/config.dart' as rust_config;

import '../../helpers/frb_bootstrap.dart';

void main() {
  // The QR export config encoder routes through
  // `configAppConfigToJsonTyped` on the FRB boundary; tests that
  // build a non-null cfg need the native blob loaded. Tests that
  // don't touch cfg are unaffected — the bootstrap is cheap
  // (one-time .so load).
  setUpAll(requireFrbLoaded);

  group('qrPayloadDeepLink', () {
    test('wraps payload in the canonical scheme + d= parameter', () {
      expect(qrPayloadDeepLink('xyz'), 'letsflutssh://import?d=xyz');
    });

    test('preserves the payload byte-for-byte (no escaping)', () {
      // The payload is a deflated + base64url-no-pad string from the
      // Rust composer; the wrap must not URL-encode it because the
      // receiver strips a string-equal `d=` value.
      const payload =
          'eJzL_2_pAcDV3-3jK8nfdY_QmTMV2y2cQHQ-EzUzCwUq_MDLAlf-fxAKw7lQ';
      expect(qrPayloadDeepLink(payload), 'letsflutssh://import?d=$payload');
    });

    test('empty payload still yields the scheme prefix', () {
      // Defensive: caller never passes an empty string today, but the
      // wrap is a one-liner concat — assert it doesn't drop the
      // prefix on the trivial input.
      expect(qrPayloadDeepLink(''), 'letsflutssh://import?d=');
    });
  });

  group('qrPayloadHasCredentials', () {
    test('all-off options carry no credentials', () {
      const opts = ExportOptions();
      expect(qrPayloadHasCredentials(opts), isFalse);
    });

    test('passwords toggle alone flips the flag', () {
      const opts = ExportOptions(includePasswords: true);
      expect(qrPayloadHasCredentials(opts), isTrue);
    });

    test('embedded keys toggle alone flips the flag', () {
      const opts = ExportOptions(includeEmbeddedKeys: true);
      expect(qrPayloadHasCredentials(opts), isTrue);
    });

    test('manager keys (selected sessions only) flips via hasManagerKeys', () {
      const opts = ExportOptions(includeManagerKeys: true);
      expect(qrPayloadHasCredentials(opts), isTrue);
    });

    test('all manager keys flips via hasManagerKeys', () {
      const opts = ExportOptions(includeAllManagerKeys: true);
      expect(qrPayloadHasCredentials(opts), isTrue);
    });

    test('non-credential toggles never flip the flag on their own', () {
      // Sessions / config / known-hosts / tags / snippets are
      // metadata; they don't carry password / key bytes by
      // themselves. Combinations stay false.
      for (final opts in const [
        ExportOptions(includeSessions: true),
        ExportOptions(includeConfig: true),
        ExportOptions(includeKnownHosts: true),
        ExportOptions(includeTags: true),
        ExportOptions(includeSnippets: true),
        ExportOptions(
          includeSessions: true,
          includeKnownHosts: true,
          includeTags: true,
          includeSnippets: true,
        ),
      ]) {
        expect(
          qrPayloadHasCredentials(opts),
          isFalse,
          reason: 'options $opts must not be flagged credential-bearing',
        );
      }
    });
  });

  group('buildDbQrExportInput', () {
    test('forwards every options toggle into DbQrExportOptions verbatim', () {
      const options = ExportOptions(
        includeSessions: true,
        includeConfig: false,
        includeKnownHosts: true,
        includePasswords: true,
        includeEmbeddedKeys: true,
        includeManagerKeys: false,
        includeAllManagerKeys: true,
        includeTags: true,
        includeSnippets: false,
      );
      final input = buildDbQrExportInput(
        options: options,
        selectedSessionIds: const ['s1', 's2'],
        selectedEmptyFolders: const ['Prod'],
        cfg: null,
      );
      expect(input.options.includeSessions, isTrue);
      expect(input.options.includeConfig, isFalse);
      expect(input.options.includeKnownHosts, isTrue);
      expect(input.options.includePasswords, isTrue);
      expect(input.options.includeEmbeddedKeys, isTrue);
      expect(input.options.includeManagerKeys, isFalse);
      expect(input.options.includeAllManagerKeys, isTrue);
      expect(input.options.includeTags, isTrue);
      expect(input.options.includeSnippets, isFalse);
      expect(input.selectedSessionIds, ['s1', 's2']);
      expect(input.selectedEmptyFolders, ['Prod']);
    });

    test(
      'cfg=null + includeConfig=true → flag flipped off + configJson null',
      () {
        // The belt-and-braces clamp on the includeConfig flag protects
        // the Rust composer from emitting a `c` block with no payload.
        const options = ExportOptions(includeConfig: true);
        final input = buildDbQrExportInput(
          options: options,
          selectedSessionIds: const [],
          selectedEmptyFolders: const [],
          cfg: null,
        );
        expect(input.options.includeConfig, isFalse);
        expect(input.configJson, isNull);
      },
    );

    test('cfg=non-null + includeConfig=true → JSON-encoded payload', () {
      final cfg = AppConfig.defaults.copyWith(locale: 'ru');
      final input = buildDbQrExportInput(
        options: const ExportOptions(includeConfig: true),
        selectedSessionIds: const [],
        selectedEmptyFolders: const [],
        cfg: cfg,
      );
      expect(input.options.includeConfig, isTrue);
      // configJson is the canonical Rust-emitted JSON of cfg.toTyped().
      expect(input.configJson, isNotNull);
      expect(
        input.configJson,
        rust_config.configAppConfigToJsonTyped(value: cfg.toTyped()),
      );
    });

    test('cfg=non-null + includeConfig=false → configJson null', () {
      // No config wanted on the export — payload must not slip in
      // even when the caller resolved a snapshot.
      const cfg = AppConfig.defaults;
      final input = buildDbQrExportInput(
        options: const ExportOptions(includeConfig: false),
        selectedSessionIds: const [],
        selectedEmptyFolders: const [],
        cfg: cfg,
      );
      expect(input.options.includeConfig, isFalse);
      expect(input.configJson, isNull);
    });

    test('preserves selected ids + empty folder lists by reference shape', () {
      final input = buildDbQrExportInput(
        options: const ExportOptions(),
        selectedSessionIds: const ['a', 'b', 'c'],
        selectedEmptyFolders: const ['F1', 'F2/F3'],
        cfg: null,
      );
      expect(input.selectedSessionIds, hasLength(3));
      expect(input.selectedEmptyFolders, ['F1', 'F2/F3']);
    });
  });
}
