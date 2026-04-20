import 'dart:io' show Platform;

import 'package:flutter/services.dart';

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
///   clipboard default. Falls through to [Clipboard.setData].
///
/// Channel: `com.letsflutssh/clipboard_secure`, method `setSecureText`
/// taking `{text: String}` and returning `bool`. If the channel is
/// missing (test harness, platform not yet wired), the call falls
/// through to the stock Flutter clipboard — a best-effort write is
/// better than refusing to copy.
class SecureClipboard {
  SecureClipboard({MethodChannel? channel, bool? hasNativePlugin})
    : _channel = channel ?? const MethodChannel(_channelName),
      _hasNativePlugin = hasNativePlugin ?? !Platform.isLinux;

  static const _channelName = 'com.letsflutssh/clipboard_secure';

  final MethodChannel _channel;
  final bool _hasNativePlugin;

  /// Write [text] to the system clipboard with the per-platform
  /// cloud / history opt-out flags applied. Falls back to
  /// [Clipboard.setData] on Linux and on any platform where the
  /// native plugin is unavailable.
  Future<void> setText(String text) async {
    if (await _tryNative(text)) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<bool> _tryNative(String text) async {
    if (!_hasNativePlugin) return false;
    try {
      await _channel.invokeMethod<bool>('setSecureText', {'text': text});
      return true;
    } on MissingPluginException {
      return false;
    } catch (e) {
      AppLogger.instance.log(
        'SecureClipboard native write failed, falling back: $e',
        name: 'SecureClipboard',
      );
      return false;
    }
  }
}
