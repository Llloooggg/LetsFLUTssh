import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/logger.dart';

/// Widget that opts its subtree into OS-level screen-capture
/// protection for as long as it is mounted.
///
/// On Android this sets `WindowManager.LayoutParams.FLAG_SECURE` via
/// the `com.letsflutssh/secure_screen` MethodChannel. The native
/// side keeps a refcount so nested scopes (e.g. an unlock dialog
/// inside the wizard) do not step on each other. The flag blocks:
///
/// - System screenshots (`PowerKey + Volume-` / accessibility API).
/// - Screen recording (MediaProjection).
/// - The app-switcher thumbnail (Android replaces the preview with
///   a solid colour while the flag is active).
///
/// On iOS / macOS the OS already renders password fields as
/// privacy-shielded when the system detects screen recording via
/// `UIScreen.main.isCaptured`; Flutter's `obscureText: true` inherits
/// that protection. A per-scope channel call would add nothing at
/// this level — so the wrapper is a no-op on Apple platforms.
///
/// On Linux / Windows there is no OS-level screen-capture gate
/// equivalent to `FLAG_SECURE`. The scope is a no-op; protection
/// must come from the host OS (Wayland screencast consent prompt
/// is the closest equivalent but is user-driven, not app-driven).
class SecureScreenScope extends StatefulWidget {
  const SecureScreenScope({super.key, required this.child});

  final Widget child;

  @override
  State<SecureScreenScope> createState() => _SecureScreenScopeState();
}

class _SecureScreenScopeState extends State<SecureScreenScope> {
  static const _channel = MethodChannel('com.letsflutssh/secure_screen');

  @override
  void initState() {
    super.initState();
    _setSecure(true);
  }

  @override
  void dispose() {
    _setSecure(false);
    super.dispose();
  }

  Future<void> _setSecure(bool secure) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } catch (e) {
      // Channel missing / MainActivity not wired up — log and move
      // on. Losing the FLAG_SECURE call should never break the
      // sensitive screen itself.
      AppLogger.instance.log(
        'SecureScreenScope setSecure($secure) failed: $e',
        name: 'SecureScreenScope',
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
