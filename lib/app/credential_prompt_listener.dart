import 'dart:async';

import '../core/bus/app_bus.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/credential_prompt.dart' as rust_cred;
import '../utils/logger.dart';
import '../widgets/security/credential_prompt_dialog.dart';
import 'navigator_key.dart';

/// Subscribes to the `SecurityPrompt` bus topic and surfaces the
/// credential overlay whenever the Rust connect actor fires a
/// `CredentialPromptRequest` — the mid-connect prompt for a private-key
/// passphrase (or, later, a session password) that was never saved.
/// The typed secret routes back over FRB
/// (`credential_prompt_resolve_submit`); the awaiting connect handler
/// stages it and resumes the handshake.
///
/// One process-wide subscription, started from `MainScreenState`
/// alongside the other prompt listeners. The subscription survives
/// unlock cycles because the bus is a process singleton.
class CredentialPromptListener {
  CredentialPromptListener._();

  static StreamSubscription<rust_bus.BusEvent>? _sub;

  /// Idempotent — repeated calls re-bind to the same singleton
  /// subscription so a hot-reload or a second wire pass doesn't stack
  /// listeners.
  static void start() {
    _sub?.cancel();
    try {
      _sub = AppBus.instance
          .subscribe(rust_bus.BusTopic.securityPrompt)
          .listen(_onEvent);
    } catch (e) {
      AppLogger.instance.log(
        'CredentialPromptListener subscribe failed: $e',
        name: 'CredentialPrompt',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_CredentialPromptRequest) {
      unawaited(_handlePrompt(event));
    }
  }

  static Future<void> _handlePrompt(
    rust_bus.BusEvent_CredentialPromptRequest event,
  ) async {
    final isPassphrase = event.kindWireName == 'passphrase';
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      // No UI available — cancel so the connect attempt fails fast
      // instead of hanging on the Rust-side await.
      AppLogger.instance.log(
        'Credential prompt: navigator not mounted, cancelling',
        name: 'CredentialPrompt',
        level: LogLevel.warn,
      );
      rust_cred.credentialPromptResolveCancel(promptId: event.promptId);
      return;
    }
    final result = await CredentialPromptDialog.show(
      ctx,
      isPassphrase: isPassphrase,
    );
    if (result == null) {
      rust_cred.credentialPromptResolveCancel(promptId: event.promptId);
      return;
    }
    rust_cred.credentialPromptResolveSubmit(
      promptId: event.promptId,
      secretBytes: result.secret,
      rememberForSession: result.remember,
    );
  }
}
