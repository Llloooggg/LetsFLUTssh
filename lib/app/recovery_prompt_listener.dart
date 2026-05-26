import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bus/app_bus.dart';
import '../src/rust/api/bus.dart' as rust_bus;
import '../src/rust/api/recovery.dart' as rust_recovery;
import '../utils/logger.dart';
import '../widgets/security/db_corrupt_dialog.dart';
import '../widgets/security/tier_reset_dialog.dart';
import 'navigator_key.dart';

/// Subscribes to the `SecurityPrompt` bus topic and dispatches
/// `BusEvent::RecoveryPromptRequest` events to the matching
/// Flutter dialog widget:
///
/// - `BusRecoveryPromptKind.dbCorruptDetected` /
///   `BusRecoveryPromptKind.vaultStateMissing` →
///   [DbCorruptDialog] (three-choice variant).
/// - `BusRecoveryPromptKind.legacyStateFound` → [TierResetDialog]
///   (two-choice variant).
///
/// The user's choice is dispatched back via
/// [rust_recovery.recoveryPromptResolve]; Rust then either runs
/// the destructive cascade and returns
/// `DbRecoveryOutcome.wipedAndRestarted` to the awaiting
/// `recoveryHandle*` caller, or returns `userExited` /
/// `continued` for the other branches.
///
/// Process-singleton subscription. Cold-start wiring lives in
/// `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners`
/// alongside the other prompt listeners — the start call happens
/// AFTER FRB init so the bus subscription never races the native
/// lib load.
class RecoveryPromptListener {
  RecoveryPromptListener._();

  static StreamSubscription<rust_bus.BusEvent>? _sub;

  /// Override for tests — the dialogs themselves are not
  /// trivially mountable under `flutter_test` and a stub
  /// dispatcher lets the listener's event-routing logic be
  /// covered without painting widgets.
  static Future<DbCorruptChoice> Function()? _debugDbCorruptShow;
  static Future<TierResetChoice> Function()? _debugTierResetShow;

  /// Inject stubs for tests. Pass `null` to restore production.
  static void debugSetDialogs({
    Future<DbCorruptChoice> Function()? dbCorrupt,
    Future<TierResetChoice> Function()? tierReset,
  }) {
    _debugDbCorruptShow = dbCorrupt;
    _debugTierResetShow = tierReset;
  }

  static void debugResetDialogs() {
    _debugDbCorruptShow = null;
    _debugTierResetShow = null;
  }

  static void start() {
    _sub?.cancel();
    try {
      _sub = AppBus.instance
          .subscribe(rust_bus.BusTopic.securityPrompt)
          .listen(_onEvent);
    } catch (e) {
      AppLogger.instance.log(
        'RecoveryPromptListener subscribe failed: $e',
        name: 'Recovery',
        level: LogLevel.warn,
      );
    }
  }

  static void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static void _onEvent(rust_bus.BusEvent event) {
    if (event is rust_bus.BusEvent_RecoveryPromptRequest) {
      unawaited(_handlePrompt(event));
    }
  }

  static Future<void> _handlePrompt(
    rust_bus.BusEvent_RecoveryPromptRequest event,
  ) async {
    // Switch on the typed kind — each scenario routes to a dialog
    // shape whose buttons match the orchestrator's choice set.
    final String wire = await switch (event.kind) {
      rust_bus.BusRecoveryPromptKind_DbCorruptDetected() => _routeDbCorrupt(),
      rust_bus.BusRecoveryPromptKind_VaultStateMissing() => _routeDbCorrupt(),
      rust_bus.BusRecoveryPromptKind_LegacyStateFound() => _routeTierReset(),
    };
    try {
      rust_recovery.recoveryPromptResolve(
        promptId: event.promptId,
        choiceWire: wire,
      );
    } catch (e) {
      AppLogger.instance.log(
        'recoveryPromptResolve dispatch failed: $e',
        name: 'Recovery',
        level: LogLevel.warn,
      );
    }
  }

  static Future<String> _routeDbCorrupt() async {
    final stub = _debugDbCorruptShow;
    final choice = stub != null ? await stub() : await _showDbCorrupt();
    return switch (choice) {
      DbCorruptChoice.resetAndSetupFresh => 'reset',
      DbCorruptChoice.tryOtherTier => 'tryOtherTier',
      DbCorruptChoice.exitApp => 'quit',
    };
  }

  static Future<String> _routeTierReset() async {
    final stub = _debugTierResetShow;
    final choice = stub != null ? await stub() : await _showTierReset();
    return switch (choice) {
      TierResetChoice.resetAndSetupFresh => 'reset',
      TierResetChoice.exitApp => 'quit',
    };
  }

  /// Production dialog launch. Falls back to `exitApp` when the
  /// navigator is not mounted (cold-boot race / teardown).
  static Future<DbCorruptChoice> _showDbCorrupt() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(DbCorruptChoice.exitApp);
    return DbCorruptDialog.show(ctx);
  }

  static Future<TierResetChoice> _showTierReset() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(TierResetChoice.exitApp);
    return TierResetDialog.show(ctx);
  }

  /// Maps a [BuildContext]-bound dialog to an unbound `Future`.
  /// Reserved for tests that need to drive the routing without
  /// touching real dialog widgets.
  @visibleForTesting
  static Future<void> debugDispatchEvent(
    rust_bus.BusEvent_RecoveryPromptRequest event,
  ) => _handlePrompt(event);
}
