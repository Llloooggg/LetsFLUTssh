import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
      try { e.entry.remove(); } catch (_) {}
      try { e.controller.dispose(); } catch (_) {}
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

    entry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        message: message,
        level: level,
        animation: controller,
        index: _entries.indexWhere((e) => e.entry == entry),
        onDismiss: () => _remove(entry, controller),
      ),
    );

    final toastEntry = _ToastOverlayEntry(
      entry: entry,
      controller: controller,
    );

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
    final bottomOffset = 40.0 + (index < 0 ? 0 : index) * 52.0;

    return Positioned(
      right: 16,
      bottom: bottomOffset,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.3, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          )),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
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
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onDismiss,
                    borderRadius: BorderRadius.circular(8),
                    child: const Icon(Icons.close, size: 14),
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
