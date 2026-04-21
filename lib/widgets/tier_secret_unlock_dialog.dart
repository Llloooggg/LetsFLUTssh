import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/security/password_rate_limiter.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/secret_controller.dart';
import 'app_dialog.dart';
import 'secure_password_field.dart';
import 'secure_screen_scope.dart';

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
    required this.title,
    required this.hint,
    required this.inputLabel,
    required this.wrongSecretLabel,
    required this.verify,
    this.numeric = false,
    this.maxLength,
    this.onReset,
    this.rateLimiter,
  });

  final String title;
  final String hint;
  final String inputLabel;
  final String wrongSecretLabel;
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

  static Future<List<int>?> show(
    BuildContext context, {
    required String title,
    required String hint,
    required String inputLabel,
    required String wrongSecretLabel,
    required Future<List<int>?> Function(String) verify,
    bool numeric = false,
    int? maxLength,
    Future<void> Function()? onReset,
    PasswordRateLimiter? rateLimiter,
  }) {
    return showDialog<List<int>?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TierSecretUnlockDialog(
        title: title,
        hint: hint,
        inputLabel: inputLabel,
        wrongSecretLabel: wrongSecretLabel,
        verify: verify,
        numeric: numeric,
        maxLength: maxLength,
        onReset: onReset,
        rateLimiter: rateLimiter,
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
  Timer? _cooldownTicker;
  RateLimitStatus _cooldown = const RateLimitStatus(
    failureCount: 0,
    cooldownRemaining: Duration.zero,
  );

  @override
  void initState() {
    super.initState();
    _refreshCooldown();
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
            AppDialogAction.secondary(
              label: l10n.cancel,
              onTap: () => Navigator.pop(ctx, false),
            ),
            AppDialogAction.destructive(
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
                    widget.title,
                    style: TextStyle(
                      fontSize: AppFonts.xl,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFonts.md,
                      color: AppTheme.fgDim,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_wrong) ...[
                    Text(
                      widget.wrongSecretLabel,
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
                      labelText: widget.inputLabel,
                      border: const OutlineInputBorder(),
                      counterText: '',
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
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _cooldown.isLocked ? null : _submit,
                        child: Text(l10n.unlock),
                      ),
                    ),
                    if (widget.onReset != null) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _reset,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
