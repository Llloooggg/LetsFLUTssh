import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';

/// Native-memory-backed secure text input.
///
/// Flutter's stock [TextField] accumulates a Dart `String` per
/// keystroke inside [TextEditingValue] — immutable and GC-relocatable,
/// so the bytes can't be zeroed after the fact. This widget hosts a
/// real platform text input (Android [EditText], iOS [UITextField],
/// macOS [NSSecureTextField]) through a [PlatformView], keeps the
/// typed bytes in the platform's own buffer, and emits them to Dart
/// **once** — on submit — as a mutable [Uint8List]. The caller
/// copies the bytes into a page-locked [SecretBuffer] and zeroes
/// the Uint8List in the same frame; residency on the Dart heap
/// collapses to a single one-frame window instead of the
/// per-keystroke trail the TextField path leaves behind.
///
/// Platform coverage:
///
/// | Platform | Backend | Status |
/// |----------|---------|--------|
/// | Android  | EditText + TYPE_TEXT_VARIATION_PASSWORD | **supported** |
/// | iOS      | UITextField + isSecureTextEntry | **supported** |
/// | macOS    | NSSecureTextField | **supported** |
/// | Windows  | Win32 EDIT control (ES_PASSWORD) via PlatformView | **pending** — Flutter Windows platform views still experimental for custom host-window integration; falls back to [SecurePasswordField] |
/// | Linux    | GtkEntry visibility=false | **pending** — Flutter Linux platform views are not officially supported upstream; falls back to [SecurePasswordField] |
/// | Web      | N/A | intentionally unsupported (browser owns the DOM) |
///
/// [isSupported] gates the feature: callers use it to pick between
/// this widget and the fallback [SecurePasswordField]. An unsupported
/// platform reports `false` so UI can downgrade gracefully without
/// a runtime branch at every call site.
class SecureNativeTextField extends StatefulWidget {
  const SecureNativeTextField({
    super.key,
    required this.onSubmit,
    this.onChanged,
    this.autofocus = false,
    this.height = 48,
  });

  /// Fires when the user presses IME Done (or a parent calls
  /// [SecureNativeTextFieldController.submit]). Receives a **mutable**
  /// [Uint8List] of UTF-8 bytes. The callback must:
  /// 1. Copy the bytes into a `SecretBuffer` immediately.
  /// 2. Overwrite every byte of the Uint8List with 0 before returning.
  ///
  /// Failure to do step 2 leaves the bytes on the Dart heap until
  /// the next GC — negates the whole point of the widget.
  final ValueChanged<Uint8List> onSubmit;

  /// Notifies of empty ↔ non-empty transitions so the parent can
  /// gate a submit button. Never exposes the actual content — only
  /// the boolean.
  final ValueChanged<bool>? onChanged;

  final bool autofocus;

  /// Fixed height for the platform view. Dart can't measure the
  /// native view's intrinsic size, so parents allocate a slot.
  final double height;

  /// Whether a native backend is wired on this platform. Android,
  /// iOS, and macOS are supported today; Windows and Linux fall
  /// back to [SecurePasswordField] (platform-view support for the
  /// Win32 EDIT control and GtkEntry is still upstream-experimental).
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  @override
  State<SecureNativeTextField> createState() => _SecureNativeTextFieldState();
}

class _SecureNativeTextFieldState extends State<SecureNativeTextField> {
  MethodChannel? _channel;

  Future<void> _onPlatformViewCreated(int id) async {
    _channel = MethodChannel('com.letsflutssh/secure_text_$id');
    _channel!.setMethodCallHandler(_handleCall);
    if (widget.autofocus) {
      try {
        await _channel!.invokeMethod<bool>('focus');
      } catch (e) {
        AppLogger.instance.log(
          'SecureNativeTextField focus failed: $e',
          name: 'SecureNativeTextField',
        );
      }
    }
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'onChanged':
        final hasText = (call.arguments as Map?)?['hasText'] as bool? ?? false;
        widget.onChanged?.call(hasText);
        return null;
      case 'onSubmit':
        final raw = call.arguments;
        if (raw is Uint8List) {
          widget.onSubmit(raw);
        } else if (raw is List) {
          widget.onSubmit(Uint8List.fromList(raw.cast<int>()));
        }
        return null;
    }
    return null;
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      channel.setMethodCallHandler(null);
      // Explicit clear — the platform view's own dispose also wipes
      // the Editable, but if Dart tears down before the view does
      // (route pop), this nudge ensures the wipe runs.
      channel.invokeMethod<bool>('clear').catchError((e) {
        AppLogger.instance.log(
          'SecureNativeTextField clear on dispose failed: $e',
          name: 'SecureNativeTextField',
        );
        return false;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!SecureNativeTextField.isSupported) {
      return const SizedBox.shrink();
    }
    const viewType = 'com.letsflutssh/secure_text';
    return SizedBox(
      height: widget.height,
      child: Platform.isAndroid
          ? AndroidView(
              viewType: viewType,
              onPlatformViewCreated: _onPlatformViewCreated,
              creationParamsCodec: const StandardMessageCodec(),
            )
          : Platform.isIOS
          ? UiKitView(
              viewType: viewType,
              onPlatformViewCreated: _onPlatformViewCreated,
              creationParamsCodec: const StandardMessageCodec(),
            )
          : Platform.isMacOS
          ? AppKitView(
              viewType: viewType,
              onPlatformViewCreated: _onPlatformViewCreated,
              creationParamsCodec: const StandardMessageCodec(),
            )
          : const SizedBox.shrink(),
    );
  }
}
