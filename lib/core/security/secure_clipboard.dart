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
/// * **Android 13+** — `ClipDescription.EXTRA_IS_SENSITIVE` hides the
///   preview in the clipboard toast and tells launchers not to cache
///   the content. The flag is set on the `ClipData` extras via JNI
///   into `android.content.ClipboardManager`.
/// * **Linux** — nothing to opt out of; X11 and Wayland have no cloud
///   clipboard default. Falls through to arboard via Rust.
///
/// Routing: every platform calls
/// `lfs_os_security::secure_clipboard::set_secure_text` over FRB.
/// The Rust side does the per-platform sensitive-flag dance in the
/// same write session as the text, so a watcher can't see the string
/// without the marker.
class SecureClipboard {
  /// Construct the writer.
  ///
  /// `rustWriter` and `platformOs` are seams for tests — production
  /// constructs `SecureClipboard()` and the writer routes through
  /// the real FRB call against the host OS. Tests pass a fake
  /// writer + a forced platform string to exercise each branch
  /// without an FRB runtime.
  SecureClipboard({void Function(String text)? rustWriter, String? platformOs})
    : _rustWriter = rustWriter ?? _defaultRustWriter,
      _platformOs = platformOs ?? Platform.operatingSystem;

  static void _defaultRustWriter(String text) {
    rust_os.osSecuritySetSecureClipboard(text: text);
  }

  final void Function(String text) _rustWriter;
  final String _platformOs;

  /// Write [text] to the system clipboard with the per-platform
  /// cloud / history opt-out flags applied. On platforms where the
  /// stock `Clipboard.setData` would silently leak the payload
  /// into a cloud-sync ring (Windows 10+, macOS Universal
  /// Clipboard, iOS Handoff, Android 13+ history) the secure path
  /// **refuses** to write on failure rather than fall back —
  /// "best-effort write" against an attacker who scrapes the
  /// cloud ring is no better than not writing at all. Linux has
  /// no cloud-clipboard default, so the fallback there is the
  /// same posture as a plain copy and the helper degrades to
  /// `Clipboard.setData` on a Rust-side failure.
  ///
  /// Returns `true` when the secure path landed (or the Linux
  /// plain fallback ran), `false` when the cloud-leak gate
  /// refused the write. Callers surface a "copy failed, try
  /// again" toast on `false` instead of silently dropping
  /// material onto a syncing pasteboard.
  Future<bool> setText(String text) async {
    if (_tryRustNative(text)) return true;
    if (_platformOs == 'linux') {
      // No cloud-clipboard default on X11 / Wayland — the plain
      // path is the same posture as the Rust path on Linux.
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    }
    // Win 10+ / macOS / iOS / Android — refusing is the only safe
    // posture; the fallback would deposit the secret into a
    // cloud-sync ring or the Android 13+ history preview without
    // the opt-out flags.
    AppLogger.instance.log(
      'SecureClipboard refusing fallback on $_platformOs — '
      'cloud-clipboard sync would land payload without opt-out flags',
      name: 'SecureClipboard',
      level: LogLevel.warn,
    );
    return false;
  }

  bool _tryRustNative(String text) {
    try {
      _rustWriter(text);
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
}
