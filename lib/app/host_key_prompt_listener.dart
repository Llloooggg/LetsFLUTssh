import 'dart:async';

import '../core/bus/app_bus.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../utils/logger.dart';
import '../widgets/host_key_dialog.dart';
import 'navigator_key.dart';

/// Subscribes to the `KnownHosts` bus topic and surfaces the
/// host-key TOFU dialog whenever the russh handler fires a
/// `KnownHostPromptRequest`. The user's choice routes back over
/// the bus as `KnownHostPromptResponse`; the awaiting handler
/// resumes the SSH handshake and (when accepted) the new entry
/// persists into `known_hosts` Rust-side.
///
/// One process-wide subscription. Cold-start init from
/// `MainScreenState` after the navigator is mounted; the
/// subscription survives unlock cycles because the bus is a
/// process singleton.
class HostKeyPromptListener {
  HostKeyPromptListener._();

  static StreamSubscription<rust_bus.BusEvent>? _sub;

  /// Idempotent — repeated calls re-bind to the same singleton
  /// subscription so a hot-reload or a second wire pass doesn't
  /// stack listeners.
  static void start() {
    _sub?.cancel();
    try {
      _sub = AppBus.instance
          .subscribe(rust_bus.BusTopic.knownHosts)
          .listen(_onEvent);
    } catch (e) {
      AppLogger.instance.log(
        'HostKeyPromptListener subscribe failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_KnownHostPromptRequest) {
      unawaited(_handlePrompt(event));
    }
  }

  static Future<void> _handlePrompt(
    rust_bus.BusEvent_KnownHostPromptRequest event,
  ) async {
    AppLogger.instance.log(
      'TOFU prompt: ${event.kind.name} for ${event.host}:${event.port}',
      name: 'KnownHosts',
    );
    final accepted = await _showDialog(event);
    try {
      await AppBus.instance.dispatch(
        rust_bus.BusCommand.knownHostPromptResponse(
          promptId: event.promptId,
          accepted: accepted,
        ),
      );
    } catch (e) {
      AppLogger.instance.log(
        'TOFU prompt response dispatch failed: $e',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
    }
  }

  static Future<bool> _showDialog(
    rust_bus.BusEvent_KnownHostPromptRequest event,
  ) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      // No UI available — fail closed (reject the host) so the
      // handshake aborts rather than silently accepting.
      AppLogger.instance.log(
        'TOFU prompt: navigator not mounted, auto-rejecting',
        name: 'KnownHosts',
        level: LogLevel.warn,
      );
      return false;
    }
    switch (event.kind) {
      case rust_bus.BusKnownHostPromptKind.newHost:
        return HostKeyDialog.showNewHost(
          ctx,
          host: event.host,
          port: event.port.toInt(),
          keyType: event.keyType,
          fingerprint: event.fingerprint,
        );
      case rust_bus.BusKnownHostPromptKind.keyChanged:
        return HostKeyDialog.showKeyChanged(
          ctx,
          host: event.host,
          port: event.port.toInt(),
          keyType: event.keyType,
          fingerprint: event.fingerprint,
        );
    }
  }
}
