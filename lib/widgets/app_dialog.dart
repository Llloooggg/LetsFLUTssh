import 'package:flutter/material.dart';

import '../core/progress/progress_reporter.dart';
import '../widgets/shortcut_registry.dart';
import '../theme/app_theme.dart';
import '../utils/platform.dart';
import 'app_button.dart';
import 'app_icon_button.dart';
import 'app_selection_area.dart';

// AppButton moved to `app_button.dart` (used outside dialogs too). Keep
// it re-exported here so the many `import 'app_dialog.dart'` callsites
// that pair the dialog shell with its footer buttons don't each need a
// second import line.
export 'app_button.dart' show AppButton;

// ════════════════════════════════════════════════════════════════════
//  AppDialog — unified dialog shell
// ════════════════════════════════════════════════════════════════════

/// Standard dialog matching the app's visual language.
///
/// Provides:
/// * Dark background (`AppTheme.bg1`)
/// * Header bar with title and close button
/// * Scrollable content area
/// * Footer bar with action buttons
///
/// For complex dialogs (e.g. with tabs between header and content),
/// compose from [AppDialogHeader], [AppDialogFooter], and [AppButton]
/// directly instead.
class AppDialog extends StatelessWidget {
  final String title;
  final double maxWidth;
  final Widget content;
  final List<Widget> actions;
  final EdgeInsets contentPadding;
  final bool scrollable;
  final bool dismissible;

  const AppDialog({
    super.key,
    required this.title,
    this.maxWidth = 460,
    required this.content,
    this.actions = const [],
    this.contentPadding = const EdgeInsets.all(AppSpacing.lg),
    this.scrollable = true,
    this.dismissible = true,
  });

  /// Convenience: show this dialog with standard options.
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget Function(BuildContext) builder,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      animationStyle: AnimationStyle.noAnimation,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body = Padding(padding: contentPadding, child: content);
    // Both branches wrap in `Flexible` so the body honours the
    // dialog's inherited height cap (Material `Dialog` clamps to
    // viewport minus inset). The scrollable branch additionally
    // routes overflow to a vertical scroll view; the non-
    // scrollable branch leaves layout to the caller — which can
    // place its own `Flexible` / `Expanded` inside [content] to
    // let oversized children (e.g. the playback dialog's xterm
    // panel) shrink under pressure instead of overflowing the
    // dialog with the classic yellow / black stripe pattern.
    if (scrollable) {
      body = Flexible(child: SingleChildScrollView(child: body));
    } else {
      body = Flexible(fit: FlexFit.loose, child: body);
    }

    // Clamp requested [maxWidth] to the available screen width minus
    // the Dialog's 24-px inset on each side. Without the clamp, a
    // dialog asking for 900 px on a 400-px-wide phone gets a fixed
    // 900-px content box, clipped by the screen and visually letting
    // content "run off" the modal. With the clamp, narrow hosts fall
    // back to full-width-minus-inset and the content reflows.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final effectiveMaxWidth = maxWidth > screenWidth - 48
        ? screenWidth - 48
        : maxWidth;

    Widget child = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppDialogHeader(
            title: title,
            onClose: dismissible ? () => Navigator.of(context).pop() : null,
          ),
          body,
          if (actions.isNotEmpty) AppDialogFooter(actions: actions),
        ],
      ),
    );

    if (dismissible) {
      child = CallbackShortcuts(
        bindings: AppShortcutRegistry.instance.buildCallbackMap({
          AppShortcut.dismissDialog: () => Navigator.of(context).pop(),
        }),
        child: Focus(autofocus: true, child: child),
      );
    } else {
      // Non-dismissible dialogs still need an autofocus anchor so
      // the OS focus ring lands inside the dialog (instead of
      // staying on whatever widget had focus before the dialog
      // opened — which lets the user tab into background widgets
      // they're meant to be modally blocked from). No
      // CallbackShortcuts wrapper because Esc must NOT dismiss a
      // non-dismissible dialog by design.
      child = Focus(autofocus: true, child: child);
    }

    return Dialog(
      backgroundColor: AppTheme.bg1,
      insetPadding: const EdgeInsets.all(24),
      // Every dialog opens in the root Overlay, above the
      // MainScreen-level `SelectionArea` — so drag-to-select and
      // Ctrl+C do not reach Text widgets inside the dialog without
      // an inner wrapper. Putting the wrap at the `AppDialog` base
      // gives every caller the right behaviour with zero per-site
      // code. A `SelectionArea` that is a no-op on a button-only
      // dialog costs nothing at runtime.
      child: AppSelectionArea(child: child),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  AppDialogHeader
// ════════════════════════════════════════════════════════════════════

/// Header bar for dialogs: title on the left, close button on the right.
class AppDialogHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onClose;

  const AppDialogHeader({super.key, required this.title, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTheme.barHeightMd,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(border: AppTheme.borderBottom),
      child: Row(
        children: [
          Text(
            title,
            style: AppFonts.inter(
              fontSize: AppFonts.md,
              fontWeight: FontWeight.w600,
              color: AppTheme.fg,
            ),
          ),
          const Spacer(),
          if (onClose != null)
            AppIconButton(icon: Icons.close, onTap: onClose!, dense: true),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  AppDialogFooter
// ════════════════════════════════════════════════════════════════════

/// Footer bar for dialogs: action buttons aligned to the right.
///
/// Desktop: horizontal [Row] with [Flexible] children — buttons shrink
/// proportionally instead of wrapping to a second line.
/// Mobile: vertical [Column] with full-width buttons in reversed order
/// (primary action on top, cancel at bottom).
class AppDialogFooter extends StatelessWidget {
  final List<Widget> actions;

  const AppDialogFooter({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final mobile = isMobilePlatform;
    return Container(
      constraints: const BoxConstraints(minHeight: AppTheme.barHeightMd),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: mobile ? 12 : 7),
      decoration: BoxDecoration(border: AppTheme.borderTop),
      child: mobile ? _mobileLayout() : _desktopLayout(),
    );
  }

  Widget _desktopLayout() {
    // `Wrap` instead of `Row` so long-locale button labels (Russian
    // "Сгенерировать ключ", German "Passwort generieren", etc.) fall
    // to a second line inside the modal instead of overflowing the
    // right edge. Trap: `FittedBox(fit: BoxFit.scaleDown)` inside
    // `AppButton.build` would shrink the font to fit, producing
    // barely-readable 10-pt labels on narrow modals (and the scaled
    // result still clips on very long translations). Wrapping keeps
    // button text at its native size and lets the footer grow
    // vertically instead. `alignment: end` preserves the desktop
    // convention of primary CTA on the right.
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: actions,
    );
  }

  Widget _mobileLayout() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _intersperse(
        const SizedBox(height: AppSpacing.sm),
        actions.reversed
            .map((a) => SizedBox(width: double.infinity, child: a))
            .toList(),
      ),
    );
  }

  static List<Widget> _intersperse(Widget spacer, List<Widget> items) {
    return [
      for (int i = 0; i < items.length; i++) ...[if (i > 0) spacer, items[i]],
    ];
  }
}

// ════════════════════════════════════════════════════════════════════
//  AppProgressBarDialog — non-dismissible progress bar with label/%
// ════════════════════════════════════════════════════════════════════

/// Modal progress bar with a phase label and percentage / step counter.
///
/// The caller owns a [ProgressReporter] and pushes phase and step
/// updates — the dialog subscribes via a [StreamBuilder] and
/// rebuilds only the progress panel.  Non-dismissible: the surrounding
/// operation is responsible for popping the dialog in a `finally`.
class AppProgressBarDialog extends StatelessWidget {
  final ProgressReporter reporter;

  /// Optional cancel callback. When non-null, the dialog renders a
  /// "Cancel" action under the progress panel and routes the tap
  /// to this callback. Caller is responsible for popping the
  /// dialog (the cancel handler typically flips a cancellation
  /// flag and lets the surrounding `finally` close the dialog
  /// once the operation observes the flag and unwinds).
  final VoidCallback? onCancel;

  const AppProgressBarDialog({
    super.key,
    required this.reporter,
    this.onCancel,
  });

  /// Show a non-dismissible progress bar.  The caller must pop it after
  /// the operation completes (success or failure) — typically in a
  /// `try/finally` pair with a `mounted` check. Pass `onCancel` to
  /// surface a Cancel button.
  static void show(
    BuildContext context,
    ProgressReporter reporter, {
    VoidCallback? onCancel,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) =>
          AppProgressBarDialog(reporter: reporter, onCancel: onCancel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: AppTheme.bg2,
          elevation: 4,
          borderRadius: AppTheme.radiusLg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<ProgressState>(
                  stream: reporter.stream,
                  initialData: reporter.current,
                  builder: (_, snap) =>
                      _ProgressPanel(state: snap.data ?? reporter.current),
                ),
                if (onCancel != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AppButton.cancel(onTap: onCancel),
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

class _ProgressPanel extends StatelessWidget {
  final ProgressState state;
  const _ProgressPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final hasSteps = state.current != null && state.total != null;
    final stepText = hasSteps ? '${state.current} / ${state.total}' : '';
    final pctText = state.percent != null
        ? '${(state.percent! * 100).round()}%'
        : '…';
    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.label,
            style: TextStyle(color: AppTheme.fg, fontSize: AppFonts.md),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: AppTheme.radiusSm,
            child: LinearProgressIndicator(
              value: state.percent,
              minHeight: 6,
              backgroundColor: AppTheme.bg3,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                stepText,
                style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
              ),
              Text(
                pctText,
                style: TextStyle(color: AppTheme.fgDim, fontSize: AppFonts.sm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
