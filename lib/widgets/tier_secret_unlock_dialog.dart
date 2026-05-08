import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/security/password_rate_limiter.dart';
import '../core/security/tier_unlock_attempt.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../utils/secret_controller.dart';
import 'app_dialog.dart';
import 'app_icon_button.dart';
import 'secure_password_field.dart';
import 'secure_screen_scope.dart';

/// Localised text + input shape for a [TierSecretUnlockDialog].
///
/// Bundles the four label strings with the input-mode flags
/// (`numeric`, `maxLength`). Keeping them in one struct is both
/// ergonomic at the call site (T1+pw / T2 paths in `main.dart` pass a
/// single value) and keeps `show()` under the S107 parameter-count
/// threshold.
class TierSecretUnlockLabels {
  final String title;
  final String hint;
  final String inputLabel;
  final String wrongSecretLabel;

  /// When true, show a numeric keyboard and restrict the field to
  /// digits only. Legacy T2 PIN paths set this; free-form password
  /// paths leave it off.
  final bool numeric;

  /// Optional hard cap on the input length. Null = unlimited.
  final int? maxLength;

  const TierSecretUnlockLabels({
    required this.title,
    required this.hint,
    required this.inputLabel,
    required this.wrongSecretLabel,
    this.numeric = false,
    this.maxLength,
  });
}

/// Bundles the two biometric-unlock parameters so [show] stays under
/// the S107 parameter-count threshold. `unlock` returns `true` on a
/// successful unseal (the caller has already staged the bytes in
/// the SecretStore via `tier_unlock_biometric_commit` and emitted
/// the unlock cascade — the dialog just closes and the caller
/// awaits the listener). When [autoTrigger] is true the dialog
/// fires `unlock` on first frame; callers that already tried
/// biometrics before opening the dialog (e.g. the startup
/// `_unlockKeychainWithPassword` path) pass `autoTrigger: false`
/// and rely on the retry button inside the dialog.
class TierSecretUnlockBiometric {
  final Future<bool> Function() unlock;
  final bool autoTrigger;

  const TierSecretUnlockBiometric({
    required this.unlock,
    this.autoTrigger = true,
  });
}

/// Shared unlock-dialog shell for the tier-secret paths (T1+pw short
/// password, T2 PIN). Owns the retry loop: the host supplies a
/// [verify] callback that returns a [TierUnlockAttempt]; the dialog
/// re-prompts on `wrongSecret`, closes on `staged` (success →
/// pop(true) so the caller awaits the post-unlock listener cascade)
/// or `error` (pop(false) so the caller falls back), and pops with
/// `null` on dismissal / reset.
///
/// Plaintext discipline: the dialog never sees raw key bytes. The
/// orchestrator stages them in the SecretStore on `staged`; the
/// [TierUnlockedListener] takes them via `secrets_take` on the
/// `BusEvent::TierStateChanged.unlocked` event and hands them to
/// drift.
///
/// Cooldown support is deliberate. The dialog refuses to call
/// [verify] while [rateLimiter] is locked, records `wrongSecret`
/// as a failure + `staged` as a success, and renders a countdown
/// over the submit button.
class TierSecretUnlockDialog extends StatefulWidget {
  const TierSecretUnlockDialog({
    super.key,
    required this.labels,
    required this.verify,
    this.onReset,
    this.rateLimiter,
    this.biometric,
  });

  final TierSecretUnlockLabels labels;

  /// Verify the entered secret. Returns the [TierUnlockAttempt]
  /// shape that drives dialog UI: `staged` closes with success,
  /// `wrongSecret` keeps the dialog open + decrements the limiter,
  /// `error` closes with the failure signal so the caller falls
  /// back to plaintext / corruption recovery, `cancelled` is
  /// treated as "stay open" (the inner sub-prompt was dismissed
  /// — the user can re-attempt).
  final Future<TierUnlockAttempt> Function(String secret) verify;

  /// "Forgot password" / reset escape hatch. Returning void + the
  /// caller popping with null is the signal to the controller that
  /// the user abandoned this tier and we should fall back to
  /// plaintext / wipe.
  final Future<void> Function()? onReset;

  /// Optional rate limiter. When provided, the dialog refuses to
  /// call [verify] while the limiter is locked, records success /
  /// failure automatically, and renders a countdown over the submit
  /// button. The caller owns the limiter's lifecycle.
  final PasswordRateLimiter? rateLimiter;

  /// Optional biometric unlock spec. When non-null the dialog
  /// auto-fires it on first frame (unless `biometric.autoTrigger` is
  /// false) and renders a retry button so the user can re-invoke the
  /// system biometric prompt without relaunching.
  final TierSecretUnlockBiometric? biometric;

  static Future<bool?> show(
    BuildContext context, {
    required TierSecretUnlockLabels labels,
    required Future<TierUnlockAttempt> Function(String) verify,
    Future<void> Function()? onReset,
    PasswordRateLimiter? rateLimiter,
    TierSecretUnlockBiometric? biometric,
  }) {
    return showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TierSecretUnlockDialog(
        labels: labels,
        verify: verify,
        onReset: onReset,
        rateLimiter: rateLimiter,
        biometric: biometric,
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
    final bio = widget.biometric;
    if (bio != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (bio.autoTrigger) {
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
    final cb = widget.biometric?.unlock;
    if (cb == null || _biometricInFlight || _busy) return;
    if (_cooldown.isLocked) return;
    _biometricInFlight = true;
    setState(() {
      _biometricOffered = true;
      _bioError = null;
    });
    try {
      final ok = await cb();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _biometricInFlight = false;
          _bioError = S.of(context).biometricUnlockCancelled;
        });
        _focus.requestFocus();
        return;
      }
      Navigator.of(context).pop(true);
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
    final outcome = await widget.verify(secret);
    if (!mounted) return;
    switch (outcome) {
      case TierUnlockAttempt.staged:
        limiter?.recordSuccess();
        Navigator.of(context).pop(true);
      case TierUnlockAttempt.wrongSecret:
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
      case TierUnlockAttempt.cancelled:
        // Inner sub-prompt cancelled (e.g. hardware vault PIN
        // sub-dialog). Outer dialog stays open — user can re-
        // attempt by tapping submit again.
        setState(() {
          _busy = false;
        });
        _focus.requestFocus();
      case TierUnlockAttempt.error:
        // Plugin / hardware / corruption — close with the
        // failure signal so the caller falls back to plaintext
        // / corruption recovery.
        Navigator.of(context).pop(false);
    }
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
                  ..._buildStatusMessages(theme, l10n),
                  _buildInputField(),
                  const SizedBox(height: 20),
                  ..._buildActions(l10n),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Inline status banners — wrong secret, cooldown countdown, last
  /// biometric error. Extracted so [build] stays under the S3776
  /// cognitive-complexity threshold; every banner is independent so
  /// the list may be empty, one, or all three at once.
  List<Widget> _buildStatusMessages(ThemeData theme, S l10n) {
    final errorStyle = TextStyle(
      color: theme.colorScheme.error,
      fontSize: AppFonts.sm,
    );
    return [
      if (_wrong) ...[
        Text(widget.labels.wrongSecretLabel, style: errorStyle),
        const SizedBox(height: 8),
      ],
      if (_cooldown.isLocked) ...[
        Text(
          l10n.tierCooldownHint(_cooldown.cooldownRemaining!.inSeconds + 1),
          style: errorStyle,
        ),
        const SizedBox(height: 8),
      ],
      if (_bioError != null) ...[
        Text(_bioError!, textAlign: TextAlign.center, style: errorStyle),
        const SizedBox(height: 8),
      ],
    ];
  }

  /// Secret input row — password field + obscure toggle. Extracted so
  /// [build] stays under the S3776 cognitive-complexity threshold.
  Widget _buildInputField() {
    return SecurePasswordField(
      controller: _ctrl,
      focusNode: _focus,
      autofocus: true,
      obscureText: _obscure,
      enabled: !_busy,
      keyboardType: widget.labels.numeric
          ? TextInputType.number
          : TextInputType.visiblePassword,
      inputFormatters: widget.labels.numeric
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      maxLength: widget.labels.maxLength,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: widget.labels.inputLabel,
        border: const OutlineInputBorder(),
        counterText: '',
        suffixIcon: AppIconButton(
          icon: _obscure ? Icons.visibility_off : Icons.visibility,
          dense: true,
          onTap: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }

  /// Action row — spinner while `_busy` / `_biometricInFlight`, or the
  /// Unlock + optional biometric + optional reset buttons. Extracted so
  /// [build] stays under the S3776 cognitive-complexity threshold.
  List<Widget> _buildActions(S l10n) {
    if (_busy || _biometricInFlight) {
      return const [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ];
    }
    return [
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
    ];
  }
}
