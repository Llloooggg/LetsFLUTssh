import 'dart:io' show Platform;

import '../../src/rust/api/os_security.dart' as rust_os;
import '../../utils/logger.dart';

/// Platform-aware clipboard writer that opts the payload out of cloud
/// sync and OS clipboard history before it hits the system pasteboard.
///
/// Flutter's stock `Clipboard.setData` lands the text on the system
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
///   clipboard default. The Rust path drives arboard, which picks
///   the right backend per session type.
///
/// Routing: every platform calls
/// `lfs_os_security::secure_clipboard::set_secure_text` over FRB.
/// The Rust side does the per-platform sensitive-flag dance in the
/// same write session as the text, so a watcher can't see the string
/// without the marker. There is no Dart-side fallback — the single
/// audit perimeter for clipboard writes lives in
/// `lfs_os_security::secure_clipboard`, and every platform refuses
/// the write on Rust-side failure rather than depositing the
/// payload through a stock pasteboard call that bypasses the flags.
class SecureClipboard {
  /// Construct the writer.
  ///
  /// `rustWriter` and `platformOs` are seams for tests — production
  /// constructs `SecureClipboard()` and the writer routes through
  /// the real FRB call against the host OS. Tests pass a fake
  /// writer + a forced platform string to exercise each branch
  /// without an FRB runtime.
  SecureClipboard({void Function(String text)? rustWriter, String? platformOs})
    : _rustWriter = rustWriter ?? debugRustWriterOverride ?? _defaultRustWriter,
      _platformOs = platformOs ?? Platform.operatingSystem;

  /// Test seam — installed by widget tests that exercise call sites
  /// constructing `SecureClipboard()` with no args (the QR copy
  /// button, `ClipboardSecret`, in-place factories). Production
  /// leaves this `null`; the default constructor then resolves to
  /// the FRB-backed writer. Tests set it in `setUp` and reset via
  /// [debugResetRustWriter] in `tearDown`. Per-instance overrides
  /// via the `rustWriter:` constructor argument still win — the
  /// override only applies when no explicit writer is passed.
  static void Function(String text)? debugRustWriterOverride;

  /// Reset the default writer to the FRB-backed production path.
  static void debugResetRustWriter() {
    debugRustWriterOverride = null;
  }

  static void _defaultRustWriter(String text) {
    rust_os.osSecuritySetSecureClipboard(text: text);
  }

  final void Function(String text) _rustWriter;
  final String _platformOs;

  /// Write [text] to the system clipboard with the per-platform
  /// cloud / history opt-out flags applied. Every platform routes
  /// through the Rust `set_secure_text` helper — there is no
  /// Dart-side fallback. On Rust-side failure the helper
  /// **refuses** to write rather than deposit the payload through
  /// a stock pasteboard call that would bypass the per-platform
  /// "do not sync, do not history" markers (Windows Win+V ring,
  /// macOS Universal Clipboard, iOS Handoff, Android 13+ history
  /// preview). Linux has no cloud-clipboard default, but the same
  /// refusal keeps the audit perimeter on the Rust side instead of
  /// silently routing around it through Flutter's stock channel.
  ///
  /// Returns `true` when the secure path landed, `false` when the
  /// Rust write failed. Callers surface a "copy failed, try again"
  /// toast on `false` instead of silently dropping material onto a
  /// syncing pasteboard.
  Future<bool> setText(String text) async {
    if (_tryRustNative(text)) return true;
    AppLogger.instance.log(
      'SecureClipboard refusing fallback on $_platformOs — '
      'stock Clipboard.setData would bypass the Rust audit perimeter',
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
        'SecureClipboard Rust write failed: $e',
        name: 'SecureClipboard',
        level: LogLevel.warn,
      );
      return false;
    }
  }
}
