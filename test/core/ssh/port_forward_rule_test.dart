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

  group('PortForwardRule.validate — error-ordering grammar', () {
    test('bind port is checked before any target field', () {
      // The Rust validator's branch order is documented at
      // `lfs_core::portforward::validate_rule` — bind_port range first,
      // then per-kind target checks, then bind_host. A rule with BOTH
      // a bad bind port AND an empty target must surface
      // `BindPortOutOfRange` (not `TargetHostRequired`) so the editor
      // highlights the field the user actually has to fix first.
      final r = PortForwardRule(
        kind: PortForwardKind.local,
        bindHost: '127.0.0.1',
        bindPort: 0,
        remoteHost: '',
        remotePort: 0,
      );
      expect(r.validate(), 'Bind port out of range');
    });

    test('rejects target port over the 65535 ceiling on local rules', () {
      final r = PortForwardRule(
        kind: PortForwardKind.local,
        bindHost: '127.0.0.1',
        bindPort: 8080,
        remoteHost: 'h',
        remotePort: 70000,
      );
      expect(r.validate(), 'Target port out of range');
    });

    test(
      'remote forward to a public bind validates and flags non-loopback',
      () {
        // Remote forwards routinely bind on the server side at 0.0.0.0 so
        // the published port reaches every NIC. Validation must pass
        // (the rule is well-formed), and `bindsLoopbackOnly` must return
        // false so the UI surfaces the multi-NIC warning.
        final r = PortForwardRule(
          kind: PortForwardKind.remote,
          bindHost: '0.0.0.0',
          bindPort: 9000,
          remoteHost: 'svc.internal',
          remotePort: 22,
        );
        expect(r.validate(), isNull);
        expect(r.bindsLoopbackOnly, isFalse);
      },
    );

    test(
      'dynamic forward rejects empty bind host even though target is skipped',
      () {
        // Dynamic forwards skip the target host/port check but still
        // require a bind host so the listener has something to bind to.
        // Empty bind host must still trip `BindHostRequired`.
        final r = PortForwardRule(
          kind: PortForwardKind.dynamic_,
          bindHost: '',
          bindPort: 1080,
          remoteHost: '',
          remotePort: 0,
        );
        expect(r.validate(), 'Bind host required');
      },
    );
  });

  group('PortForwardRule construction defaults', () {
    test('id defaults to a unique UUID per instance', () {
      // The constructor's `id ?? const Uuid().v4()` ensures every
      // freshly-built rule carries its own stable identifier even when
      // the caller omits one — the DAO uses this as the row PK.
      final a = PortForwardRule(
        kind: PortForwardKind.local,
        bindPort: 1,
        remoteHost: 'h',
        remotePort: 1,
      );
      final b = PortForwardRule(
        kind: PortForwardKind.local,
        bindPort: 1,
        remoteHost: 'h',
        remotePort: 1,
      );
      expect(a.id, isNotEmpty);
      expect(b.id, isNotEmpty);
      expect(a.id, isNot(b.id));
    });

    test('bindHost defaults to loopback', () {
      // Loopback default is a security posture — a fresh rule must not
      // accidentally publish to every NIC. The constructor declares
      // `this.bindHost = '127.0.0.1'` for exactly this reason.
      final r = PortForwardRule(
        kind: PortForwardKind.local,
        bindPort: 1,
        remoteHost: 'h',
        remotePort: 1,
      );
      expect(r.bindHost, '127.0.0.1');
      expect(r.bindsLoopbackOnly, isTrue);
      expect(r.enabled, isTrue);
      expect(r.description, isEmpty);
      expect(r.sortOrder, 0);
    });

    test('createdAt defaults to a fresh DateTime when omitted', () {
      final before = DateTime.now();
      final r = PortForwardRule(
        kind: PortForwardKind.local,
        bindPort: 1,
        remoteHost: 'h',
        remotePort: 1,
      );
      final after = DateTime.now();
      // The stamp must sit inside the call window — a fixed sentinel
      // (epoch zero) here would mean every fresh rule shares the same
      // creation timestamp.
      expect(
        r.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        r.createdAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  group('PortForwardRule.copyWith semantics', () {
    PortForwardRule baseRule() => PortForwardRule(
      id: 'fixed-id',
      kind: PortForwardKind.local,
      bindHost: '127.0.0.1',
      bindPort: 8080,
      remoteHost: 'svc.local',
      remotePort: 22,
      description: 'orig',
      enabled: true,
      sortOrder: 3,
      createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    );

    test('omitted fields fall through to the receiver', () {
      // `copyWith` is used by every per-row UI mutation (toggle, edit).
      // Omitting all the optional named args must produce a value-equal
      // rule so the UI can swap the reference without triggering a
      // spurious "dirty" mark.
      final base = baseRule();
      final copy = base.copyWith();
      expect(copy, equals(base));
      expect(identical(copy, base), isFalse);
    });

    test('overrides surface on the copy but leave the original intact', () {
      final base = baseRule();
      final copy = base.copyWith(
        bindPort: 9090,
        remoteHost: 'svc2.local',
        enabled: false,
        description: 'edited',
        sortOrder: 7,
      );
      expect(copy.bindPort, 9090);
      expect(copy.remoteHost, 'svc2.local');
      expect(copy.enabled, isFalse);
      expect(copy.description, 'edited');
      expect(copy.sortOrder, 7);
      // Original is immutable — copyWith does not mutate the receiver.
      expect(base.bindPort, 8080);
      expect(base.remoteHost, 'svc.local');
      expect(base.enabled, isTrue);
    });

    test('id and createdAt are preserved across copyWith', () {
      // Stable id keeps the DB row mapping consistent across edits, and
      // `createdAt` is intentionally NOT a copyWith parameter — the
      // record's birth timestamp is immutable.
      final base = baseRule();
      final copy = base.copyWith(bindPort: 1);
      expect(copy.id, base.id);
      expect(copy.createdAt, base.createdAt);
    });
  });

  group('PortForwardRule equality and hashCode', () {
    PortForwardRule make({String id = 'A', int sortOrder = 0}) =>
        PortForwardRule(
          id: id,
          kind: PortForwardKind.local,
          bindHost: '127.0.0.1',
          bindPort: 1,
          remoteHost: 'h',
          remotePort: 1,
          sortOrder: sortOrder,
          createdAt: DateTime.utc(2026, 1, 1),
        );

    test('same field set produces equal rules with equal hashCode', () {
      // The DAO compares rules by value when reconciling DB rows
      // against the in-memory list — equality must follow the declared
      // operator==, not Dart's identity default.
      final a = make();
      final b = make();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different id breaks equality', () {
      expect(make(id: 'A'), isNot(equals(make(id: 'B'))));
    });

    test('different sortOrder breaks equality', () {
      // sortOrder participates in equality so a drag-reorder is a
      // detectable change against the prior list.
      expect(make(sortOrder: 0), isNot(equals(make(sortOrder: 1))));
    });

    test('createdAt is excluded from equality', () {
      // The operator== contract leaves `createdAt` out — two rules with
      // the same logical content but different birth timestamps still
      // compare equal so a refreshed DB read does not invalidate the
      // selection by mistake.
      final a = PortForwardRule(
        id: 'X',
        kind: PortForwardKind.local,
        bindHost: '127.0.0.1',
        bindPort: 1,
        remoteHost: 'h',
        remotePort: 1,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final b = PortForwardRule(
        id: 'X',
        kind: PortForwardKind.local,
        bindHost: '127.0.0.1',
        bindPort: 1,
        remoteHost: 'h',
        remotePort: 1,
        createdAt: DateTime.utc(2030, 6, 6),
      );
      expect(a, equals(b));
    });
  });
}
