import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/security/password_rate_limiter.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../utils/secret_controller.dart';
import 'app_dialog.dart';
import 'app_icon_button.dart';
import 'secure_password_field.dart';
import 'secure_screen_scope.dart';

/// Localised text for a [TierSecretUnlockDialog].
///
/// Grouped into a separate value so [TierSecretUnlockDialog.show]
/// keeps a reasonable parameter count — each caller (L2 / L3 unlock
/// paths in `main.dart`) passes a single `labels` bundle instead of
/// four `String` arguments threaded through every invocation.
class TierSecretUnlockLabels {
  final String title;
  final String hint;
  final String inputLabel;
  final String wrongSecretLabel;

  const TierSecretUnlockLabels({
    required this.title,
    required this.hint,
    required this.inputLabel,
    required this.wrongSecretLabel,
  });
}

/// Shared unlock-dialog shell for the tier-secret paths (L2 short
/// password, L3 PIN). Owns the retry loop: the host supplies a
/// [verify] callback that returns the resulting key (or null on
/// mismatch); the dialog re-prompts on wrong input and pops with
/// either the verified key or `null` when the user resets.
///
/// Cooldown support is deliberate. `verify` may return null for
/// "wrong secret" OR surface a blocking cooldown through
/// [cooldownFn] — when set, the button is disabled + a countdown
/// renders until the limiter clears.
class TierSecretUnlockDialog extends StatefulWidget {
  const TierSecretUnlockDialog({
    super.key,
    required this.labels,
    required this.verify,
    this.numeric = false,
    this.maxLength,
    this.onReset,
    this.rateLimiter,
    this.biometricUnlock,
    this.autoTriggerBiometric = true,
  });

  final TierSecretUnlockLabels labels;
  final bool numeric;
  final int? maxLength;

  /// Verify the entered secret and, on success, return the key to
  /// inject. Null = wrong secret.
  final Future<List<int>?> Function(String secret) verify;

  /// "Forgot password" / reset escape hatch. Returning void + the
  /// caller popping with null is the signal to main.dart that the
  /// user abandoned this tier and we should fall back to plaintext /
  /// wipe.
  final Future<void> Function()? onReset;

  /// Optional rate limiter. When provided, the dialog refuses to
  /// call [verify] while the limiter is locked, records success /
  /// failure automatically, and renders a countdown over the submit
  /// button. The caller owns the limiter's lifecycle.
  final PasswordRateLimiter? rateLimiter;

  /// Optional biometric unlock callback. When non-null, the dialog
  /// auto-fires it on first frame (unless [autoTriggerBiometric] is
  /// false) and renders a retry button under the Unlock action so
  /// the user can re-invoke the system biometric prompt without
  /// relaunching the app. Returns the unwrapped key on success, or
  /// null on any failure / cancellation / missing prerequisite.
  final Future<List<int>?> Function()? biometricUnlock;

  /// Whether to auto-fire [biometricUnlock] on first frame. Callers
  /// that already tried biometrics before opening the dialog (e.g.
  /// the startup `_unlockKeychainWithPassword` path) pass `false`
  /// to avoid a double-cancellation loop while keeping the retry
  /// button reachable from the dialog itself.
  final bool autoTriggerBiometric;

  static Future<List<int>?> show(
    BuildContext context, {
    required TierSecretUnlockLabels labels,
    required Future<List<int>?> Function(String) verify,
    bool numeric = false,
    int? maxLength,
    Future<void> Function()? onReset,
    PasswordRateLimiter? rateLimiter,
    Future<List<int>?> Function()? biometricUnlock,
    bool autoTriggerBiometric = true,
  }) {
    return showDialog<List<int>?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TierSecretUnlockDialog(
        labels: labels,
        verify: verify,
        numeric: numeric,
        maxLength: maxLength,
        onReset: onReset,
        rateLimiter: rateLimiter,
        biometricUnlock: biometricUnlock,
        autoTriggerBiometric: autoTriggerBiometric,
      ),
    );
  }

  @override
  State<TierSecretUnlockDialog> createState() => _TierSecretUnlockDialogState();
}

class _TierSecretUnlockDialogState extends State<TierSecretUnlockDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _wrong = false;
  bool _obscure = true;
  bool _biometricInFlight = false;

  /// Null while the initial probe runs, then true when a biometric
  /// retry button should render, false when the callback is missing
  /// or the probe failed. Mirrors `UnlockDialog._biometricOffered`
  /// so the user sees the same two-state button behaviour.
  bool? _biometricOffered;
  String? _bioError;
  Timer? _cooldownTicker;
  RateLimitStatus _cooldown = const RateLimitStatus(
    failureCount: 0,
    cooldownRemaining: Duration.zero,
  );

  @override
  void initState() {
    super.initState();
    _refreshCooldown();
    if (widget.biometricUnlock != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.autoTriggerBiometric) {
          _tryBiometric();
        } else {
          // Probe so the retry button renders; do not fire the
          // system prompt — caller already tried once.
          setState(() => _biometricOffered = true);
        }
      });
    }
  }

  Future<void> _tryBiometric() async {
    final cb = widget.biometricUnlock;
    if (cb == null || _biometricInFlight || _busy) return;
    if (_cooldown.isLocked) return;
    _biometricInFlight = true;
    setState(() {
      _biometricOffered = true;
      _bioError = null;
    });
    try {
      final key = await cb();
      if (!mounted) return;
      if (key == null) {
        setState(() {
          _biometricInFlight = false;
          _bioError = S.of(context).biometricUnlockCancelled;
        });
        _focus.requestFocus();
        return;
      }
      Navigator.of(context).pop(key);
    } catch (e) {
      AppLogger.instance.log(
        'Tier-secret dialog biometric unlock threw: $e',
        name: 'TierSecretUnlockDialog',
        error: e,
      );
      if (!mounted) return;
      setState(() {
        _biometricInFlight = false;
        _bioError = S.of(context).biometricUnlockFailed;
      });
      _focus.requestFocus();
    }
  }

  void _refreshCooldown() {
    final limiter = widget.rateLimiter;
    if (limiter == null) return;
    final status = limiter is PersistedRateLimiter ? null : limiter.status();
    if (status != null) {
      _cooldown = status;
      if (status.isLocked) _startTicker();
    } else if (limiter is PersistedRateLimiter) {
      limiter.statusAsync().then((s) {
        if (!mounted) return;
        setState(() => _cooldown = s);
        if (s.isLocked) _startTicker();
      });
    }
  }

  void _startTicker() {
    _cooldownTicker?.cancel();
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final limiter = widget.rateLimiter;
      if (limiter == null || !mounted) {
        _cooldownTicker?.cancel();
        return;
      }
      final next = limiter.status();
      setState(() => _cooldown = next);
      if (!next.isLocked) {
        _cooldownTicker?.cancel();
        _cooldownTicker = null;
      }
    });
  }

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    _ctrl.wipeAndClear();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final secret = _ctrl.text;
    if (secret.isEmpty) return;
    final limiter = widget.rateLimiter;
    if (limiter != null && limiter.status().isLocked) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    final key = await widget.verify(secret);
    if (!mounted) return;
    if (key == null) {
      limiter?.recordFailure();
      final status = limiter?.status();
      setState(() {
        _busy = false;
        _wrong = true;
        if (status != null) _cooldown = status;
      });
      if (status != null && status.isLocked) _startTicker();
      _ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _ctrl.text.length,
      );
      _focus.requestFocus();
      return;
    }
    limiter?.recordSuccess();
    Navigator.of(context).pop(key);
  }

  /// Confirmation uses [AppDialog] so the body copy is selectable
  /// via the global dialog-level [SelectionArea] and the button
  /// labels match the Settings → Data → Reset All Data flow
  /// exactly. Earlier revisions used raw [AlertDialog] with its own
  /// bespoke button text ("Reset and delete credentials"), which
  /// drifted from the Settings path and gave the user two copies
  /// for the same action.
  Future<void> _reset() async {
    final onReset = widget.onReset;
    if (onReset == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = S.of(ctx);
        return AppDialog(
          title: l10n.resetAllDataConfirmTitle,
          content: Text(
            l10n.resetAllDataConfirmBody,
            style: TextStyle(color: AppTheme.fg),
          ),
          actions: [
            AppButton.secondary(
              label: l10n.cancel,
              onTap: () => Navigator.pop(ctx, false),
            ),
            AppButton.destructive(
              label: l10n.resetAllDataConfirmAction,
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await onReset();
    if (!mounted) return;
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final theme = Theme.of(context);
    return SecureScreenScope(
      child: PopScope(
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
                    widget.labels.title,
                    style: TextStyle(
                      fontSize: AppFonts.xl,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.labels.hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFonts.md,
                      color: AppTheme.fgDim,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_wrong) ...[
                    Text(
                      widget.labels.wrongSecretLabel,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: AppFonts.sm,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_cooldown.isLocked) ...[
                    Text(
                      l10n.tierCooldownHint(
                        _cooldown.cooldownRemaining!.inSeconds + 1,
                      ),
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
                  SecurePasswordField(
                    controller: _ctrl,
                    focusNode: _focus,
                    autofocus: true,
                    obscureText: _obscure,
                    enabled: !_busy,
                    keyboardType: widget.numeric
                        ? TextInputType.number
                        : TextInputType.visiblePassword,
                    inputFormatters: widget.numeric
                        ? [FilteringTextInputFormatter.digitsOnly]
                        : null,
                    maxLength: widget.maxLength,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: widget.labels.inputLabel,
                      border: const OutlineInputBorder(),
                      counterText: '',
                      suffixIcon: AppIconButton(
                        icon: _obscure
                            ? Icons.visibility_off
                            : Icons.visibility,
                        dense: true,
                        onTap: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_busy || _biometricInFlight) ...[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ] else ...[
                    AppButton.primary(
                      label: l10n.unlock,
                      fullWidth: true,
                      onTap: _cooldown.isLocked ? null : _submit,
                    ),
                    if (_biometricOffered == true) ...[
                      const SizedBox(height: 8),
                      AppButton(
                        label: l10n.biometricUnlockTitle,
                        icon: Icons.fingerprint,
                        onTap: _cooldown.isLocked ? null : _tryBiometric,
                      ),
                    ],
                    if (widget.onReset != null) ...[
                      const SizedBox(height: 12),
                      AppButton(label: l10n.forgotPassword, onTap: _reset),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
