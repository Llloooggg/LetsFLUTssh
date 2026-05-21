import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/tier_unlocked_listener.dart';
import '../providers/lock_state.dart';
import '../core/security/tier_unlock_attempt.dart';
import '../l10n/app_localizations.dart';
import '../providers/master_password_provider.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import 'app_button.dart';
import '../utils/secret_controller.dart';
import 'secure_password_field.dart';
import 'secure_screen_scope.dart';

/// Full-screen lock overlay shown while [lockStateProvider] is true.
///
/// Paranoid-only re-auth surface today. `_submitPassword` drives
/// [MasterPasswordManager.unlockAttempt] which routes through the
/// `tier_unlock_paranoid` orchestrator: stage key in SecretStore +
/// emit unlock cascade. Rust's `run_post_unlock_cascade` opens the
/// DB, publishes the store-changed events, and finally publishes
/// `BusEvent::UnlockCascadeReady`; [LockStateNotifier] is subscribed
/// to that terminal event and flips the overlay off on its own. The
/// screen awaits `TierUnlockedListener.awaitNextUnlock` only to gate
/// the busy spinner on the orchestrator round-trip, not the overlay
/// flip.
///
/// The biometric overlay surfaces only on tiers that carry an
/// OS-managed biometric slot for the typed password (T1+pw, T2);
/// Paranoid forbids biometric by design (see ARCHITECTURE §3.6 →
/// Biometric unlock for the rationale). The dispatcher that
/// renders the lock screen on a non-Paranoid tier supplies a
/// biometric retry button keyed off the live overlay state; this
/// surface keeps the password-only entry for the Paranoid branch.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pwCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _busy = false;
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pwCtrl.wipeAndClear();
    _pwCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitPassword() async {
    if (_busy) return;
    final password = _pwCtrl.text;
    if (password.isEmpty) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    final manager = ref.read(masterPasswordProvider);
    final listener = ref.read(tierUnlockedListenerProvider)..start();
    final unlockDone = listener.awaitNextUnlock(onlyUnlocked: true);
    try {
      // Routes through `tier_unlock_paranoid` — single Argon2id,
      // stages the derived key in the SecretStore + dispatches
      // Rust's `run_post_unlock_cascade` (DB open, tier persist,
      // store-changed events, `UnlockCascadeReady`). The Dart
      // Riverpod half (`securityStateProvider.setActive`, overlay
      // flip) lives off the terminal bus event.
      final attempt = await manager.unlockAttempt(
        Uint8List.fromList(utf8.encode(password)),
      );
      if (!mounted) return;
      switch (attempt) {
        case TierUnlockAttempt.staged:
          // Wait for the Rust cascade to settle so the busy spinner
          // stays up across the round-trip. The overlay flip itself
          // is driven by `LockStateNotifier` subscribing to
          // `BusEvent::UnlockCascadeReady` — by the time
          // `awaitNextUnlock` resolves, the same event has already
          // flipped `lockStateProvider` to `false` and the workspace
          // re-mounts on the next frame.
          await unlockDone.timeout(
            tierUnlockedListenerWaitTimeout,
            onTimeout: () => TierUnlockOutcome.failed,
          );
          if (!mounted) return;
        case TierUnlockAttempt.wrongSecret:
          listener.cancelPending();
          setState(() {
            _busy = false;
            _wrong = true;
          });
          // Zero the prior string instead of a bare `clear()` — the
          // wrong-password buffer is a secret the user just typed
          // and we have no reason to let the interim `String` on
          // the Dart heap wait for GC any longer than the
          // accepted-password path does.
          _pwCtrl.wipeAndClear();
          _focusNode.requestFocus();
        case TierUnlockAttempt.cancelled:
        case TierUnlockAttempt.error:
          listener.cancelPending();
          setState(() {
            _busy = false;
            _wrong = true;
          });
          _pwCtrl.wipeAndClear();
          _focusNode.requestFocus();
      }
    } catch (e) {
      listener.cancelPending();
      AppLogger.instance.log('Unlock failed: $e', name: 'LockScreen', error: e);
      if (mounted) {
        setState(() {
          _busy = false;
          _wrong = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return SecureScreenScope(
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: AppTheme.bg0,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.lock_outline, size: 56, color: AppTheme.accent),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      l10n.lockScreenTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.fg,
                        fontSize: AppFonts.xl,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.lockScreenSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.fgDim,
                        fontSize: AppFonts.sm,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SecurePasswordField(
                      controller: _pwCtrl,
                      focusNode: _focusNode,
                      enabled: !_busy,
                      onSubmitted: (_) => _submitPassword(),
                      decoration: AppTheme.inputDecoration(
                        labelText: l10n.masterPassword,
                      ),
                    ),
                    if (_wrong) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      // `liveRegion: true` so screen readers (TalkBack /
                      // VoiceOver / NVDA) re-announce the wrong-password
                      // text on every retry. Without it the message
                      // appears visually but stays silent for assistive
                      // tech — the user submits, hears nothing, and
                      // assumes the unlock spun without a reason.
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.wrongPassword,
                          style: TextStyle(
                            color: AppTheme.red,
                            fontSize: AppFonts.xs,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    // The button renders a busy ellipsis label
                    // instead of the standard `CircularProgressIndicator`
                    // shape: the spinner animates indefinitely under
                    // flutter_test's `pumpAndSettle`, which the lock
                    // screen tests need to use to traverse the
                    // verify -> unlock state transition. The
                    // ellipsis is a discrete state that pumpAndSettle
                    // can settle on.
                    AppButton.primary(
                      label: _busy ? '...' : l10n.unlock,
                      onTap: _busy ? null : _submitPassword,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
