import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/lock_state.dart';
import '../core/security/security_tier.dart';
import '../l10n/app_localizations.dart';
import '../providers/master_password_provider.dart';
import '../providers/security_provider.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import 'app_button.dart';
import '../utils/secret_controller.dart';
import 'secure_password_field.dart';
import 'secure_screen_scope.dart';

/// Full-screen lock overlay shown while [lockStateProvider] is true.
///
/// Currently a Paranoid-only re-auth surface: `_releaseLock` pushes a
/// master-password-derived key into [securityStateProvider] under
/// `SecurityTier.paranoid`, and `_submitPassword` drives
/// [MasterPasswordManager]. Biometric unlock is deliberately absent —
/// Paranoid opts out of biometric by design (see ARCHITECTURE §3.6 →
/// Biometric unlock for the rationale), so there is nothing to
/// auto-trigger and no fingerprint affordance to render.
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

  void _releaseLock(Uint8List key) {
    ref.read(securityStateProvider.notifier).set(SecurityTier.paranoid, key);
    ref.read(lockStateProvider.notifier).unlock();
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
    try {
      // Single Argon2id: verify + derive in one isolate spawn.
      // `useRateLimit` on — mid-session lock screen is a user-typed
      // path and should slow down a passerby the same way the
      // first-launch UnlockDialog does.
      final key = await manager.verifyAndDerive(password, useRateLimit: true);
      if (key == null) {
        setState(() {
          _busy = false;
          _wrong = true;
        });
        _pwCtrl.clear();
        _focusNode.requestFocus();
        return;
      }
      if (!mounted) return;
      _releaseLock(key);
    } catch (e) {
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
                    const SizedBox(height: 16),
                    Text(
                      l10n.lockScreenTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.fg,
                        fontSize: AppFonts.xl,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.lockScreenSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.fgDim,
                        fontSize: AppFonts.sm,
                      ),
                    ),
                    const SizedBox(height: 20),
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
                      const SizedBox(height: 6),
                      Text(
                        l10n.wrongPassword,
                        style: TextStyle(
                          color: AppTheme.red,
                          fontSize: AppFonts.xs,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // The button renders as a plain `Text('...')` under
                    // the busy flag rather than `loading: _busy`. A
                    // real `CircularProgressIndicator` here ticks
                    // forever on test `pumpAndSettle` — the verify
                    // call kicks the state machine through `_busy`
                    // during the async gap the tests wait on, and a
                    // spinning indicator prevents settle from ever
                    // resolving. The string variant matches the
                    // pre-migration behaviour exactly.
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
