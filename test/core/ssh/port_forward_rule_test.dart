import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/port_forward_rule.dart';
import 'package:letsflutssh/src/rust/api/forward.dart' as rust_forward;

import '../../helpers/frb_bootstrap.dart';

void main() {
  setUpAll(requireFrbLoaded);

  group('PortForwardRule.validate', () {
    PortForwardRule rule({
      PortForwardKind kind = PortForwardKind.local,
      String bindHost = '127.0.0.1',
      int bindPort = 8080,
      String remoteHost = 'app.internal',
      int remotePort = 80,
    }) => PortForwardRule(
      kind: kind,
      bindHost: bindHost,
      bindPort: bindPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
    );

    test('passes for a complete local forward', () {
      expect(rule().validate(), isNull);
    });

    test('rejects empty bind host', () {
      expect(rule(bindHost: '').validate(), 'Bind host required');
    });

    test('rejects bind port out of range', () {
      expect(rule(bindPort: 0).validate(), 'Bind port out of range');
      expect(rule(bindPort: 70000).validate(), 'Bind port out of range');
    });

    test('rejects empty target host on local rules', () {
      expect(rule(remoteHost: '').validate(), 'Target host required');
    });

    test('rejects target port out of range on local rules', () {
      expect(rule(remotePort: 0).validate(), 'Target port out of range');
    });

    test('dynamic forwards do not require a target host/port', () {
      final r = PortForwardRule(
        kind: PortForwardKind.dynamic_,
        bindHost: '127.0.0.1',
        bindPort: 1080,
        remoteHost: '',
        remotePort: 0,
      );
      expect(r.validate(), isNull);
    });
  });

  group('PortForwardRule.bindsLoopbackOnly', () {
    test('flags 127.0.0.1, ::1, and localhost as loopback', () {
      for (final host in ['127.0.0.1', '::1', 'localhost']) {
        final r = PortForwardRule(
          kind: PortForwardKind.local,
          bindHost: host,
          bindPort: 1,
          remoteHost: 'h',
          remotePort: 1,
        );
        expect(r.bindsLoopbackOnly, isTrue, reason: host);
      }
    });

    test('flags 0.0.0.0 / public bind as non-loopback', () {
      final r = PortForwardRule(
        kind: PortForwardKind.local,
        bindHost: '0.0.0.0',
        bindPort: 1,
        remoteHost: 'h',
        remotePort: 1,
      );
      expect(r.bindsLoopbackOnly, isFalse);
    });
  });

  group('PortForwardRule canonical-JSON roundtrip (FRB-routed)', () {
    // The Dart-side `toJson` / `fromJson` codec was retired in favour
    // of `portForwardRuleToJsonTyped` / `portForwardRuleFromJsonTyped`,
    // which route both directions through the canonical Rust codec
    // in `lfs_core::portforward`. The tests here exercise the FRB
    // shim and pin the round-trip + missing-field-default contract
    // so a future shape drift on either side surfaces immediately.

    test('round-trips every field through the typed FRB codec', () {
      const input = rust_forward.DbPortForwardRuleJson(
        id: 'fixed-id',
        kind: PortForwardKind.local,
        bindHost: '127.0.0.1',
        bindPort: 9090,
        remoteHost: 'svc.local',
        remotePort: 443,
        description: 'prod tunnel',
        enabled: false,
        sortOrder: 5,
        createdAtIso8601: '2026-01-02T03:04:05.000Z',
      );
      final json = rust_forward.portForwardRuleToJsonTyped(rule: input);
      final back = rust_forward.portForwardRuleFromJsonTyped(
        json: json,
        nowMs: 0,
      );
      expect(back, equals(input));
    });

    test('fromJson defaults missing fields safely', () {
      final r = rust_forward.portForwardRuleFromJsonTyped(
        json: '{"bind_port": 22}',
        nowMs: 12345,
      );
      expect(r.kind, PortForwardKind.local);
      expect(r.bindHost, '127.0.0.1');
      expect(r.enabled, isTrue);
      expect(r.bindPort, 22);
      // Missing `created_at` falls back to the supplied `now_ms` so
      // a freshly built rule carries a sensible timestamp.
      expect(r.createdAtIso8601, '1970-01-01T00:00:12.345Z');
    });

    test('fromJson maps unknown kind to local', () {
      final r = rust_forward.portForwardRuleFromJsonTyped(
        json: '{"bind_port": 1, "kind": "who-knows"}',
        nowMs: 0,
      );
      expect(r.kind, PortForwardKind.local);
    });

    test('toJson omits empty description (matches prior codec)', () {
      const input = rust_forward.DbPortForwardRuleJson(
        id: 'k',
        kind: PortForwardKind.local,
        bindHost: '127.0.0.1',
        bindPort: 1,
        remoteHost: 'h',
        remotePort: 1,
        description: '',
        enabled: true,
        sortOrder: 0,
        createdAtIso8601: '2026-01-02T03:04:05.000Z',
      );
      final json = rust_forward.portForwardRuleToJsonTyped(rule: input);
      expect(json.contains('description'), isFalse);
    });
  });
}
