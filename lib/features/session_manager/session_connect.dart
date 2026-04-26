import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection/connection.dart';
import '../../core/session/session.dart';
import '../../core/ssh/errors.dart';
import '../../core/ssh/port_forward_runtime.dart';
import '../../core/ssh/ssh_config.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/connection_provider.dart';
import '../../providers/key_provider.dart';
import '../../providers/session_provider.dart';
import '../../utils/logger.dart';
import '../../widgets/toast.dart';
import '../workspace/workspace_controller.dart';

/// Shared connection logic used by both main.dart and mobile_shell.dart.
///
/// Opens tabs immediately (in connecting state), connection happens in background.
/// Connection status is shown inside the terminal/SFTP tab, not as a toast.
class SessionConnect {
  SessionConnect._();

  /// Open a terminal tab and connect to session in background.
  /// Returns false if session is invalid (missing credentials).
  static Future<bool> connectTerminal(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final conn = await _createConnection(context, ref, session, 'terminal');
    if (conn == null) return false;
    ref.read(workspaceProvider.notifier).addTerminalTab(conn);
    return true;
  }

  /// Open an SFTP tab and connect to session in background.
  /// Returns false if session is invalid (missing credentials).
  static Future<bool> connectSftp(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final conn = await _createConnection(context, ref, session, 'SFTP');
    if (conn == null) return false;
    ref.read(workspaceProvider.notifier).addSftpTab(conn);
    return true;
  }

  /// Hard cap on ProxyJump chain depth. Catches typo loops before
  /// they spend real bandwidth dialing 50 hops, while still leaving
  /// room for realistic enterprise stacks (corp gateway → region →
  /// cluster → service ≈ 4, doubled for safety).
  static const int maxProxyJumpDepth = 8;

  /// Validate session and create a background connection, or return null on failure.
  ///
  /// The [session] passed in comes from the in-memory cache and carries no
  /// credentials — we reload it from the DB here so the plaintext password/
  /// keyData/passphrase are only on the Dart heap for the duration of the
  /// connect handshake, not for the whole app lifetime.
  static Future<Connection?> _createConnection(
    BuildContext context,
    WidgetRef ref,
    Session session,
    String logLabel,
  ) async {
    // No `loadWithCredentials` round-trip — the cached `session`
    // carries the metadata + per-slot stored-secret flags that
    // `Session.hasCredentials` reads. The connect path inside
    // `ConnectionManager._authFromConfig` stages the actual
    // credential bytes directly from the DB into the SecretStore
    // via `db_sessions_stage_secrets`, so plaintext never has to
    // ride the Dart heap.
    if (!session.isValid) {
      if (context.mounted) _showIncompleteMessage(context);
      return null;
    }
    final fresh = session;
    AppLogger.instance.log(
      'Opening $logLabel for ${fresh.label}',
      name: 'Session',
    );
    final config = await _resolveConfig(ref, fresh);
    final manager = ref.read(connectionManagerProvider);

    // ProxyJump chain — connect every bastion bottom-up before the
    // final session. ConnectionManager._doConnect reads the bastion's
    // transport off `conn.bastion?.transport` and tunnels via
    // `connectViaProxy`.
    Connection? bastion;
    if (fresh.hasProxyJump) {
      try {
        bastion = await _ensureBastion(ref, fresh, <String>{fresh.id});
      } on SSHError catch (e) {
        if (context.mounted) {
          Toast.show(
            context,
            message: e.userMessage,
            level: ToastLevel.warning,
          );
        }
        return null;
      }
    }

    final conn = manager.connectAsync(
      config,
      label: fresh.label.isNotEmpty ? fresh.label : fresh.displayName,
      sessionId: fresh.id,
      bastion: bastion,
    );
    await _attachPortForwards(ref, fresh.id, conn);
    return conn;
  }

  /// Recursively connect every bastion in the chain bottom-up,
  /// returning the immediate hop the final session connects through.
  /// Each hop tunnels through its parent's `RustTransport` via
  /// `connectViaProxy`; the bottom hop talks to its server directly.
  ///
  /// [visited] tracks session ids already in the chain (cycle guard).
  /// Depth ceiling is [maxProxyJumpDepth] to bound runaway loops
  /// even when no cycle exists.
  static Future<Connection> _ensureBastion(
    WidgetRef ref,
    Session current,
    Set<String> visited,
  ) async {
    if (visited.length >= maxProxyJumpDepth) {
      throw ProxyJumpDepthError(visited.length);
    }
    // Resolve the bastion: saved-session id wins over override.
    Session? bastionSession;
    SSHConfig bastionConfig;
    String bastionLabel;
    if (current.viaSessionId != null) {
      // Same shape as the non-bastion connect: read the cached
      // session (no credentials on the heap) and let the connect
      // path stage secrets directly from the DB into the
      // SecretStore.
      final store = ref.read(sessionStoreProvider);
      bastionSession = store.get(current.viaSessionId!);
      if (bastionSession == null) {
        throw ProxyJumpBastionError(
          current.viaSessionId!,
          'bastion session missing',
        );
      }
      if (visited.contains(bastionSession.id)) {
        throw ProxyJumpCycleError(bastionSession.id);
      }
      bastionConfig = await _resolveConfig(ref, bastionSession);
      bastionLabel = bastionSession.label.isNotEmpty
          ? bastionSession.label
          : bastionSession.displayName;
    } else {
      // Override bastion — reuses the final session's credentials.
      // Documented limitation: for distinct bastion auth, save the
      // bastion as its own session and link via viaSessionId.
      final ov = current.viaOverride!;
      bastionConfig = SSHConfig(
        server: ServerAddress(host: ov.host, port: ov.port, user: ov.user),
        auth: current.toSSHConfig().auth,
      );
      bastionLabel = '${ov.user}@${ov.host}:${ov.port}';
    }

    final manager = ref.read(connectionManagerProvider);

    // Recursively materialise this bastion's own bastion chain.
    Connection? upstream;
    if (bastionSession != null && bastionSession.hasProxyJump) {
      upstream = await _ensureBastion(ref, bastionSession, {
        ...visited,
        bastionSession.id,
      });
    }

    final conn = manager.connectAsync(
      bastionConfig,
      label: bastionLabel,
      sessionId: bastionSession?.id,
      bastion: upstream,
      internal: true,
    );
    return conn;
  }

  /// Read the saved port-forward rules for [sessionId] and attach a
  /// runtime that opens listeners on connect / closes them on
  /// disconnect. Cheap when the rule list is empty — the runtime is
  /// only constructed when the user has configured at least one rule.
  static Future<void> _attachPortForwards(
    WidgetRef ref,
    String sessionId,
    Connection conn,
  ) async {
    final store = ref.read(sessionStoreProvider);
    final rules = await store.loadPortForwards(sessionId);
    if (rules.isEmpty) return;
    final runtime = PortForwardRuntime(rules: rules);
    conn.addExtension(runtime);
  }

  /// Build SSHConfig, resolving keyId from the key store if set.
  static Future<SSHConfig> _resolveConfig(
    WidgetRef ref,
    Session session,
  ) async {
    final config = session.toSSHConfig();
    if (session.keyId.isEmpty) return config;

    final keyStore = ref.read(keyStoreProvider);
    final entry = await keyStore.get(session.keyId);
    if (entry == null) {
      AppLogger.instance.log(
        'Key ${session.keyId} not found in key store',
        name: 'Session',
      );
      return config;
    }
    // Key label is free-form user-chosen text (e.g. "Burzuf",
    // "work-laptop"), so there is no regex the sanitiser could match
    // without false positives. Log the marker `<label>` so the log
    // tells us "keyId X resolved to a label" without leaking the
    // label itself.
    AppLogger.instance.log(
      'Resolved keyId ${session.keyId} → <label>',
      name: 'Session',
    );
    return config.copyWith(
      auth: config.auth.copyWith(keyData: entry.privateKey),
    );
  }

  static void _showIncompleteMessage(BuildContext context) {
    Toast.show(
      context,
      message: S.of(context).sessionNoCredentials,
      level: ToastLevel.warning,
    );
  }

  /// Open a terminal tab with SSHConfig directly (quick connect).
  static void connectConfig(
    BuildContext context,
    WidgetRef ref,
    SSHConfig config,
  ) {
    AppLogger.instance.log('Quick connect to ${config.host}', name: 'Session');
    final manager = ref.read(connectionManagerProvider);
    final conn = manager.connectAsync(config);
    ref.read(workspaceProvider.notifier).addTerminalTab(conn);
  }
}
