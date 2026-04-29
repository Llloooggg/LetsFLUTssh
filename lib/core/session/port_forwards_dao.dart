import '../../src/rust/api/db.dart' as rust_db;
import '../../utils/logger.dart';
import '../ssh/port_forward_rule.dart';

/// Standalone DAO helpers for the per-session port-forward rule
/// table. Pulled out of `SessionStore` because none of the three
/// methods touch the in-memory session cache — they're 1-line
/// FRB wrappers that the editing UI calls directly.
///
/// Failure semantics match the legacy `SessionStore` shape:
/// FRB-unreachable contexts (flutter_test without `RustLib`) log
/// + return empty / no-op so the UI doesn't surface an error
/// dialog for a missing native lib.

/// Read every saved port-forward rule for [sessionId], sorted by
/// the user-defined order. Empty when the session has no rules
/// (the runtime then skips attaching a `PortForwardRuntime` and
/// the connection pays no cost).
Future<List<PortForwardRule>> loadPortForwards(String sessionId) async {
  try {
    final rows = await rust_db.dbPortForwardsListForSession(
      sessionId: sessionId,
    );
    return rows
        .map(
          (r) => PortForwardRule(
            id: r.id,
            kind: PortForwardKindExt.fromWireName(r.kind),
            bindHost: r.bindHost,
            bindPort: r.bindPort,
            remoteHost: r.remoteHost,
            remotePort: r.remotePort,
            description: r.description,
            enabled: r.enabled,
            sortOrder: r.sortOrder,
            createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAtMs),
          ),
        )
        .toList(growable: false);
  } catch (e) {
    AppLogger.instance.log(
      'loadPortForwards failed: $e',
      name: 'PortForwardsDao',
      level: LogLevel.warn,
    );
    return const [];
  }
}

/// Insert or update [rule] for [sessionId]. Idempotent on the rule
/// id — re-saving a rule with the same id overwrites.
Future<void> upsertPortForward(String sessionId, PortForwardRule rule) async {
  try {
    await rust_db.dbPortForwardsUpsert(
      row: rust_db.DbPortForwardRule(
        id: rule.id,
        sessionId: sessionId,
        kind: rule.kind.wireName,
        bindHost: rule.bindHost,
        bindPort: rule.bindPort,
        remoteHost: rule.remoteHost,
        remotePort: rule.remotePort,
        description: rule.description,
        enabled: rule.enabled,
        sortOrder: rule.sortOrder,
        createdAtMs: rule.createdAt.millisecondsSinceEpoch,
      ),
    );
  } catch (e) {
    AppLogger.instance.log(
      'upsertPortForward failed: $e',
      name: 'PortForwardsDao',
      level: LogLevel.warn,
    );
  }
}

/// Drop a single rule by id. Returns true when something was
/// removed (helpful for the UI confirm-toast).
Future<bool> deletePortForward(String ruleId) async {
  try {
    final n = await rust_db.dbPortForwardsDelete(id: ruleId);
    return n > 0;
  } catch (e) {
    AppLogger.instance.log(
      'deletePortForward failed: $e',
      name: 'PortForwardsDao',
      level: LogLevel.warn,
    );
    return false;
  }
}
