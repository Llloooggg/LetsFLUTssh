import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_icon_button.dart';

/// Toast notification level.
enum ToastLevel { info, success, warning, error }

/// Non-blocking toast notification overlay.
class Toast {
  static final _entries = <_ToastOverlayEntry>[];

  /// Clear all pending toast entries without animation. For testing only.
  @visibleForTesting
  static void clearAllForTest() {
    for (final e in _entries) {
      e.timer?.cancel();
      try {
        e.entry.remove();
      } catch (_) {}
      try {
        e.controller.dispose();
      } catch (_) {}
    }
    _entries.clear();
  }

  /// Show a toast notification.
  static void show(
    BuildContext context, {
    required String message,
    ToastLevel level = ToastLevel.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;

    final controller = AnimationController(
      vsync: overlay,
      duration: const Duration(milliseconds: 200),
    );

    late final _ToastOverlayEntry toastEntry;

    entry = OverlayEntry(
      builder: (ctx) {
        // Update cached index while entry is still in the list;
        // during removal animation indexWhere returns -1, so we
        // fall back to the last known position instead of jumping to 0.
        final liveIndex = _entries.indexWhere((e) => e.entry == entry);
        if (liveIndex >= 0) toastEntry.lastIndex = liveIndex;
        return _ToastWidget(
          message: message,
          level: level,
          animation: controller,
          index: toastEntry.lastIndex,
          onDismiss: () => _remove(entry, controller),
        );
      },
    );

    toastEntry = _ToastOverlayEntry(entry: entry, controller: controller);

    // Rebuild existing entries to update positions before adding new one
    for (final e in _entries) {
      e.entry.markNeedsBuild();
    }

    _entries.add(toastEntry);
    overlay.insert(entry);
    controller.forward();

    toastEntry.timer = Timer(duration, () {
      _remove(entry, controller);
    });
  }

  static void _remove(OverlayEntry entry, AnimationController controller) {
    final idx = _entries.indexWhere((e) => e.entry == entry);
    if (idx < 0) return;
    _entries[idx].timer?.cancel();
    _entries.removeWhere((e) => e.entry == entry);

    controller.reverse().whenComplete(() {
      entry.remove();
      controller.dispose();
      // Rebuild remaining to update positions
      for (final e in _entries) {
        e.entry.markNeedsBuild();
      }
    });
  }
}

class _ToastOverlayEntry {
  final OverlayEntry entry;
  final AnimationController controller;
  Timer? timer;
  int lastIndex = 0;

  _ToastOverlayEntry({required this.entry, required this.controller});
}

class _ToastWidget extends StatelessWidget {
  final String message;
  final ToastLevel level;
  final AnimationController animation;
  final int index;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.level,
    required this.animation,
    required this.index,
    required this.onDismiss,
  });

  (Color, IconData) _levelStyle() {
    return switch (level) {
      ToastLevel.info => (AppTheme.info, Icons.info_outline),
      ToastLevel.success => (AppTheme.connected, Icons.check_circle_outline),
      ToastLevel.warning => (AppTheme.connecting, Icons.warning_amber),
      ToastLevel.error => (AppTheme.disconnected, Icons.error_outline),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _levelStyle();
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final topOffset = statusBarHeight + 16.0 + index * 52.0;

    return Positioned(
      right: 16,
      top: topOffset,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.3, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: Semantics(
            liveRegion: true,
            label: '${level.name}: $message',
            child: Material(
              elevation: 6,
              borderRadius: AppTheme.radiusLg,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: AppTheme.radiusLg,
                  border: Border(left: BorderSide(color: color, width: 3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        style: TextStyle(fontSize: AppFonts.lg),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppIconButton(
                      icon: Icons.close,
                      onTap: onDismiss,
                      dense: true,
                      borderRadius: AppTheme.radiusMd,
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
