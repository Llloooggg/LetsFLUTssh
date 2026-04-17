import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/lock_state.dart';
import '../core/security/security_level.dart';
import '../l10n/app_localizations.dart';
import '../providers/master_password_provider.dart';
import '../providers/security_provider.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../utils/secret_controller.dart';

/// Full-screen lock overlay shown while [lockStateProvider] is true.
///
/// Tries biometric unlock first (if the user enabled it) and falls back to
/// a master-password form. On success it re-derives the DB key, pushes it
/// into [securityStateProvider], and flips [lockStateProvider] back to
/// unlocked — the root widget tree is rebuilt to the normal app UI.
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
  bool _biometricTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  @override
  void dispose() {
    _pwCtrl.wipeAndClear();
    _pwCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    if (_biometricTried) return;
    _biometricTried = true;
    final vault = ref.read(biometricKeyVaultProvider);
    if (!await vault.isStored()) {
      if (mounted) _focusNode.requestFocus();
      return;
    }
    final bio = ref.read(biometricAuthProvider);
    if (!await bio.isAvailable()) {
      if (mounted) _focusNode.requestFocus();
      return;
    }
    if (!mounted) return;
    final reason = S.of(context).biometricUnlockPrompt;
    final ok = await bio.authenticate(reason);
    if (!ok) {
      if (mounted) _focusNode.requestFocus();
      return;
    }
    final key = await vault.read();
    if (key != null && mounted) _releaseLock(key);
  }

  void _releaseLock(Uint8List key) {
    ref
        .read(securityStateProvider.notifier)
        .set(SecurityLevel.masterPassword, key);
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
      final ok = await manager.verify(password);
      if (!ok) {
        setState(() {
          _busy = false;
          _wrong = true;
        });
        _pwCtrl.clear();
        _focusNode.requestFocus();
        return;
      }
      final key = await manager.deriveKey(password);
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
    return PopScope(
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
                  TextField(
                    controller: _pwCtrl,
                    focusNode: _focusNode,
                    obscureText: true,
                    enabled: !_busy,
                    onSubmitted: (_) => _submitPassword(),
                    style: TextStyle(color: AppTheme.fg),
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
                  FilledButton(
                    onPressed: _busy ? null : _submitPassword,
                    child: Text(_busy ? '...' : l10n.unlock),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _biometricTried = false,
                    icon: const Icon(Icons.fingerprint, size: 18),
                    label: Text(l10n.biometricUnlockTitle),
                    onLongPress: _tryBiometric,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
