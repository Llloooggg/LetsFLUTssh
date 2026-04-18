import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/master_password.dart';
import '../l10n/app_localizations.dart';
import '../providers/security_provider.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../utils/secret_controller.dart';

/// Full-screen unlock dialog shown at startup when master password is enabled.
///
/// Non-dismissible — the user must enter the correct password or reset.
/// Returns the derived encryption key on success, or null if reset was chosen.
///
/// When biometric unlock is opted in, the dialog auto-triggers the biometric
/// prompt on first frame (unless [autoTriggerBiometric] is false). The
/// password field remains the fallback so users can still type if biometrics
/// fail or are cancelled. The retry button stays available whenever the
/// vault is stashed + platform reports biometric ready.
class UnlockDialog extends ConsumerStatefulWidget {
  final MasterPasswordManager manager;

  /// Whether the dialog should auto-fire the biometric prompt on first
  /// frame. Set to `false` by main.dart when it already tried biometric
  /// before showing the dialog — avoids a double-cancellation loop.
  final bool autoTriggerBiometric;

  const UnlockDialog({
    super.key,
    required this.manager,
    this.autoTriggerBiometric = true,
  });

  /// Show the unlock dialog and return the derived key.
  ///
  /// Returns `null` if the user chose to reset (forgot password).
  static Future<Uint8List?> show(
    BuildContext context, {
    required MasterPasswordManager manager,
    bool autoTriggerBiometric = true,
  }) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => UnlockDialog(
        manager: manager,
        autoTriggerBiometric: autoTriggerBiometric,
      ),
    );
  }

  @override
  ConsumerState<UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends ConsumerState<UnlockDialog> {
  final _passwordCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  bool _wrongPassword = false;
  bool _biometricTried = false;

  /// Whether biometric unlock is even possible here: vault has a stashed
  /// key AND platform reports a real sensor with enrolled credentials.
  /// Null while async probe is running. Drives the retry button.
  bool? _biometricOffered;
  String? _bioError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.autoTriggerBiometric) {
        _tryBiometric();
      } else {
        _probeBiometricOffered();
      }
    });
  }

  /// Probe whether biometric unlock is available without firing the prompt.
  /// Used when the caller (main.dart) already tried biometrics once — the
  /// retry button should still be rendered, but we must not auto-invoke
  /// the system prompt a second time.
  Future<void> _probeBiometricOffered() async {
    try {
      final vault = ref.read(biometricKeyVaultProvider);
      if (!await vault.isStored()) {
        _markBiometricUnavailable();
        return;
      }
      final bio = ref.read(biometricAuthProvider);
      if (!await bio.isAvailable()) {
        _markBiometricUnavailable();
        return;
      }
      if (mounted) setState(() => _biometricOffered = true);
      _focusNode.requestFocus();
    } catch (_) {
      _markBiometricUnavailable();
    }
  }

  @override
  void dispose() {
    _passwordCtrl.wipeAndClear();
    _passwordCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Probe biometric vault + platform; on success pop with the cached key.
  /// Every failure path surfaces a visible error instead of leaving the
  /// user staring at a dead dialog — mirrors LockScreen._tryBiometric.
  Future<void> _tryBiometric() async {
    if (_biometricTried) return;
    _biometricTried = true;
    try {
      final vault = ref.read(biometricKeyVaultProvider);
      final stored = await vault.isStored();
      if (!stored) {
        _markBiometricUnavailable();
        return;
      }
      final bio = ref.read(biometricAuthProvider);
      if (!await bio.isAvailable()) {
        _markBiometricUnavailable();
        return;
      }
      if (mounted) setState(() => _biometricOffered = true);
      if (!mounted) return;
      final reason = S.of(context).biometricUnlockPrompt;
      final ok = await bio.authenticate(reason);
      if (!ok) {
        _reportBiometricFailure(
          mounted ? S.of(context).biometricUnlockCancelled : null,
        );
        return;
      }
      final key = await vault.read();
      if (key == null) {
        _reportBiometricFailure(
          mounted ? S.of(context).biometricUnlockFailed : null,
        );
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop(key);
    } catch (e) {
      AppLogger.instance.log(
        'Biometric unlock failed: $e',
        name: 'UnlockDialog',
        error: e,
      );
      _reportBiometricFailure(
        mounted ? S.of(context).biometricUnlockFailed : null,
      );
    }
  }

  void _markBiometricUnavailable() {
    if (!mounted) return;
    setState(() => _biometricOffered = false);
    _focusNode.requestFocus();
  }

  void _reportBiometricFailure(String? message) {
    if (!mounted) return;
    setState(() => _bioError = message);
    _focusNode.requestFocus();
  }

  /// Re-arm biometric and run it again — mirrors LockScreen retry.
  Future<void> _retryBiometric() async {
    if (_busy) return;
    setState(() => _bioError = null);
    _biometricTried = false;
    await _tryBiometric();
  }

  Future<void> _unlock() async {
    final password = _passwordCtrl.text;
    if (password.isEmpty) return;

    setState(() {
      _busy = true;
      _wrongPassword = false;
    });

    // Single Argon2id run: verify + derive in one isolate spawn so
    // unlock latency is not doubled on mid-tier mobiles. `useRateLimit`
    // is on because this is the user-typed unlock path — the
    // in-memory limiter slows down anyone poking at the dialog by
    // hand (real brake against offline brute is still Argon2id).
    final key = await widget.manager.verifyAndDerive(
      password,
      useRateLimit: true,
    );

    if (!mounted) return;

    if (key == null) {
      setState(() {
        _busy = false;
        _wrongPassword = true;
      });
      _passwordCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _passwordCtrl.text.length,
      );
      _focusNode.requestFocus();
      return;
    }

    Navigator.of(context).pop(key);
  }

  Future<void> _forgotPassword() async {
    final confirmed = await _showResetConfirmation();
    if (confirmed != true || !mounted) return;

    await widget.manager.reset();
    if (mounted) {
      Navigator.of(context).pop(null);
    }
  }

  Future<bool?> _showResetConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = S.of(ctx);
        return AlertDialog(
          title: Text(l10n.forgotPassword),
          content: Text(
            l10n.forgotPasswordWarning,
            style: TextStyle(color: AppTheme.fgDim),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.resetAndDeleteCredentials),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  l10n.masterPassword,
                  style: TextStyle(
                    fontSize: AppFonts.xl,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.enterMasterPassword,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppFonts.md,
                    color: AppTheme.fgDim,
                  ),
                ),
                const SizedBox(height: 20),
                if (_wrongPassword) ...[
                  Text(
                    l10n.wrongMasterPassword,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: AppFonts.sm,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_bioError != null) ...[
                  Text(
                    _bioError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: AppFonts.sm,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _passwordCtrl,
                  focusNode: _focusNode,
                  obscureText: _obscure,
                  enabled: !_busy,
                  onSubmitted: (_) => _unlock(),
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_busy) ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.derivingKey,
                    style: TextStyle(
                      fontSize: AppFonts.sm,
                      color: AppTheme.fgDim,
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _unlock,
                      child: Text(l10n.unlock),
                    ),
                  ),
                  if (_biometricOffered == true) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _retryBiometric,
                      icon: const Icon(Icons.fingerprint, size: 18),
                      label: Text(l10n.biometricUnlockTitle),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _forgotPassword,
                    child: Text(
                      l10n.forgotPassword,
                      style: TextStyle(
                        fontSize: AppFonts.sm,
                        color: AppTheme.fgDim,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
