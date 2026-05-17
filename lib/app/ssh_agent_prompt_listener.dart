import 'dart:async';

import '../core/bus/app_bus.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/ssh_agent.dart' as rust_ssh_agent;
import '../utils/logger.dart';
import '../widgets/agent_signature_request_dialog.dart';
import 'navigator_key.dart';

/// Subscribes to the `SshAgent` bus topic and surfaces the per-key
/// signature-confirmation dialog whenever the in-process ssh-agent
/// endpoint fires a [rust_bus.BusEvent_SshAgentSignaturePrompt].
/// The user's verdict routes back through
/// `ssh_agent_respond_to_signature_request` and the parked signer
/// future on the Rust side resumes.
///
/// One process-wide subscription. Cold-start wires this from the
/// post-FRB listener block in `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners`
/// so the FRB stream is ready when the first agent SIGN_REQUEST
/// lands.
class SshAgentPromptListener {
  SshAgentPromptListener._();

  static StreamSubscription<rust_bus.BusEvent>? _sub;

  /// Idempotent — repeated calls re-bind to the same singleton
  /// subscription so a hot-reload or a second wire pass doesn't
  /// stack listeners.
  static void start() {
    _sub?.cancel();
    try {
      _sub = AppBus.instance
          .subscribe(rust_bus.BusTopic.sshAgent)
          .listen(_onEvent);
    } catch (e) {
      AppLogger.instance.log(
        'SshAgentPromptListener subscribe failed: $e',
        name: 'SshAgent',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_SshAgentSignaturePrompt) {
      unawaited(_handlePrompt(event));
    }
  }

  static Future<void> _handlePrompt(
    rust_bus.BusEvent_SshAgentSignaturePrompt event,
  ) async {
    AppLogger.instance.log(
      'ssh-agent prompt for key=<${event.keyId}>',
      name: 'SshAgent',
    );
    final decision = await _showDialog(event);
    // Fail-closed: a `null` decision (route popped without a verdict)
    // routes back as Deny so the external client gets an explicit
    // refusal rather than waiting on the gate's timeout.
    final wireDecision = switch (decision) {
      AgentSignatureDecision.authorizeOnce => 'once',
      AgentSignatureDecision.authorizeAlways => 'always',
      _ => 'deny',
    };
    try {
      await rust_ssh_agent.sshAgentRespondToSignatureRequest(
        requestId: event.requestId,
        decision: rust_ssh_agent.DbAgentDecision(kind: wireDecision),
      );
    } catch (e) {
      AppLogger.instance.log(
        'ssh-agent prompt response dispatch failed: $e',
        name: 'SshAgent',
        level: LogLevel.warn,
      );
    }
  }

  static Future<AgentSignatureDecision?> _showDialog(
    rust_bus.BusEvent_SshAgentSignaturePrompt event,
  ) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      // No UI available — fail closed so the external client backs off.
      AppLogger.instance.log(
        'ssh-agent prompt: navigator not mounted, auto-denying',
        name: 'SshAgent',
        level: LogLevel.warn,
      );
      return AgentSignatureDecision.deny;
    }
    return AgentSignatureRequestDialog.show(
      ctx,
      keyLabel: event.keyLabel,
      requesterName: event.requester,
    );
  }
}
