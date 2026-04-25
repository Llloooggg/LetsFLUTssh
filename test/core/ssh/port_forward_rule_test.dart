import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/ssh/port_forward_rule.dart';

void main() {
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

  group('PortForwardRule JSON roundtrip', () {
    test('round-trips every field', () {
      final r = PortForwardRule(
        id: 'fixed-id',
        kind: PortForwardKind.local,
        bindHost: '127.0.0.1',
        bindPort: 9090,
        remoteHost: 'svc.local',
        remotePort: 443,
        description: 'prod tunnel',
        enabled: false,
        sortOrder: 5,
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final back = PortForwardRule.fromJson(r.toJson());
      expect(back, equals(r));
    });

    test('fromJson defaults missing fields safely', () {
      final r = PortForwardRule.fromJson({'bind_port': 22});
      expect(r.kind, PortForwardKind.local);
      expect(r.bindHost, '127.0.0.1');
      expect(r.enabled, isTrue);
    });

    test('fromJson maps unknown kind to local', () {
      final r = PortForwardRule.fromJson({'bind_port': 1, 'kind': 'who-knows'});
      expect(r.kind, PortForwardKind.local);
    });
  });
}
