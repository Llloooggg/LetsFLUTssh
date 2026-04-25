import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

void main() {
  group('Session ProxyJump fields', () {
    Session session({String? viaSessionId, ProxyJumpOverride? viaOverride}) =>
        Session(
          id: 's',
          label: 'l',
          server: const ServerAddress(host: 'h', user: 'u'),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          viaSessionId: viaSessionId,
          viaOverride: viaOverride,
        );

    test('default has no proxy jump', () {
      final s = session();
      expect(s.hasProxyJump, isFalse);
      expect(s.viaSessionId, isNull);
      expect(s.viaOverride, isNull);
    });

    test('saved-session jump sets viaSessionId only', () {
      final s = session(viaSessionId: 'bastion-id');
      expect(s.hasProxyJump, isTrue);
      expect(s.viaSessionId, 'bastion-id');
      expect(s.viaOverride, isNull);
    });

    test('override jump sets viaOverride only', () {
      final s = session(
        viaOverride: const ProxyJumpOverride(
          host: 'b.example.com',
          user: 'u',
          port: 2222,
        ),
      );
      expect(s.hasProxyJump, isTrue);
      expect(s.viaOverride!.host, 'b.example.com');
      expect(s.viaOverride!.port, 2222);
    });

    test('copyWith clears proxy jump explicitly', () {
      final s = session(viaSessionId: 'bastion-id');
      final cleared = s.copyWith(viaSessionId: null, viaOverride: null);
      expect(cleared.hasProxyJump, isFalse);
    });

    test('copyWith leaves proxy jump untouched when not passed', () {
      final s = session(viaSessionId: 'bastion-id');
      final renamed = s.copyWith(label: 'new');
      expect(renamed.viaSessionId, 'bastion-id');
    });

    test('JSON roundtrip preserves both fields', () {
      final s = session(viaSessionId: 'bastion-id');
      final back = Session.fromJson(s.toJson());
      expect(back.viaSessionId, 'bastion-id');
    });

    test('JSON roundtrip preserves override', () {
      final s = session(
        viaOverride: const ProxyJumpOverride(
          host: 'b.example.com',
          port: 2222,
          user: 'jumper',
        ),
      );
      final back = Session.fromJson(s.toJson());
      expect(back.viaOverride, equals(s.viaOverride));
    });

    test('toJson omits proxy fields when none set', () {
      final s = session();
      expect(s.toJson().containsKey('via_session_id'), isFalse);
      expect(s.toJson().containsKey('via_override'), isFalse);
    });

    test('equality includes proxy jump fields', () {
      final a = session(viaSessionId: 'b1');
      final b = session(viaSessionId: 'b1');
      final c = session(viaSessionId: 'b2');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('ProxyJumpOverride', () {
    test('roundtrips through JSON', () {
      const o = ProxyJumpOverride(host: 'h', port: 2200, user: 'u');
      final back = ProxyJumpOverride.fromJson(o.toJson());
      expect(back, equals(o));
    });

    test('default port is 22', () {
      final back = ProxyJumpOverride.fromJson(const {'host': 'h', 'user': 'u'});
      expect(back.port, 22);
    });
  });
}
