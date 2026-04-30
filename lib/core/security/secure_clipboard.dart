import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../src/rust/api/os_security.dart' as rust_os;
import '../../utils/logger.dart';

/// Platform-aware clipboard writer that opts the payload out of cloud
/// sync and OS clipboard history before it hits the system pasteboard.
///
/// Flutter's stock [Clipboard.setData] lands the text on the system
/// clipboard as a plain string. Every modern OS ships some form of
/// "remember what you copied" or "sync to the other device" feature
/// that then scoops it up:
///
/// * **Windows 10 1809+** keeps a clipboard-history ring (`Win+V`) and
///   optionally syncs it to Microsoft cloud + other signed-in
///   devices. The opt-out is two registered clipboard formats —
///   `CanIncludeInClipboardHistory` and `CanUploadToCloudClipboard`,
///   each a `DWORD` set to 0 — written in the same `OpenClipboard`
///   session as the text. Without them a copied password lives in
///   the history list until the ring rolls over.
/// * **macOS** sends the general pasteboard through Universal
///   Clipboard / Handoff to nearby Apple devices signed into the same
///   iCloud account. There is no first-party opt-out; the de-facto
///   standard (per `nspasteboard.org`) is to also declare
///   `org.nspasteboard.TransientType` and
///   `org.nspasteboard.ConcealedType` on the same pasteboard item.
///   Well-behaved clipboard managers (1Password, Maccy, Paste) skip
///   the item; Handoff remains a best-effort gap until Apple ships
///   an official API.
/// * **iOS** — `UIPasteboard.setItems(..., options: [.localOnly: true])`
///   disables Handoff sync for that write. Also sets a short
///   expiration so a stale copy does not survive a reboot.
/// * **Android 13+** — `ClipDescription.EXTRA_IS_SENSITIVE` (or the
///   raw `"android.content.extra.IS_SENSITIVE"` key on older SDKs
///   that honour it) hides the preview in the clipboard toast and
///   tells launchers not to cache the content.
/// * **Linux** — nothing to opt out of; X11 and Wayland have no cloud
///   clipboard default. Falls through to arboard via Rust.
///
/// Routing:
/// * **Android** — keeps the `com.letsflutssh/clipboard_secure`
///   MethodChannel (the `EXTRA_IS_SENSITIVE` flag needs the platform
///   `ClipboardManager` API). The Dart wrapper short-circuits here.
/// * **All other targets** — single FRB call into
///   `lfs_os_security::secure_clipboard::set_secure_text`. The Rust
///   side does the per-platform sensitive-flag dance in the same
///   write session as the text, so a watcher can't see the string
///   without the marker.
class SecureClipboard {
  SecureClipboard({MethodChannel? channel, bool? isAndroidPlatform})
    : _channel = channel ?? const MethodChannel(_androidChannelName),
      _isAndroidPlatform = isAndroidPlatform ?? Platform.isAndroid;

  static const _androidChannelName = 'com.letsflutssh/clipboard_secure';

  final MethodChannel _channel;
  final bool _isAndroidPlatform;

  /// Write [text] to the system clipboard with the per-platform
  /// cloud / history opt-out flags applied. Falls back to
  /// [Clipboard.setData] when both the Rust path and the Android
  /// MethodChannel fail — a best-effort write is better than
  /// refusing to copy.
  Future<void> setText(String text) async {
    if (_isAndroidPlatform) {
      if (await _tryAndroidNative(text)) return;
    } else if (_tryRustNative(text)) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  bool _tryRustNative(String text) {
    try {
      rust_os.osSecuritySetSecureClipboard(text: text);
      return true;
    } catch (e) {
      AppLogger.instance.log(
        'SecureClipboard Rust write failed, falling back: $e',
        name: 'SecureClipboard',
        level: LogLevel.warn,
      );
      return false;
    }
  }

  Future<bool> _tryAndroidNative(String text) async {
    try {
      await _channel.invokeMethod<bool>('setSecureText', {'text': text});
      return true;
    } on MissingPluginException {
      return false;
    } catch (e) {
      AppLogger.instance.log(
        'SecureClipboard Android channel write failed, falling back: $e',
        name: 'SecureClipboard',
        level: LogLevel.warn,
      );
      return false;
    }
  }
}
