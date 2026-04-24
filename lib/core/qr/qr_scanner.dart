import 'package:flutter/services.dart';

import '../../utils/logger.dart';

/// The MethodChannel backing [scanQrCode]. Exposed so tests can mock the
/// channel handler without the production code branching on `Platform`.
const qrScannerChannel = MethodChannel('com.letsflutssh/qrscanner');

/// Dart-side entry point for the native QR scanner.
///
/// Android: `QrScannerActivity` launches CameraX + ZXing-core, decoded
/// payloads come back through [Activity.onActivityResult].
/// iOS: `QrScannerController` presents a modal AVFoundation scanner.
/// Desktop: no implementation — the channel call resolves to
/// [MissingPluginException] and the function returns `null`.
///
/// Returns the decoded QR text, or `null` when the user cancels, denies
/// camera permission, or the platform has no scanner implementation.
Future<String?> scanQrCode() async {
  try {
    return await qrScannerChannel.invokeMethod<String>('scan');
  } on PlatformException catch (e) {
    AppLogger.instance.log(
      'QR scan failed: ${e.code}: ${e.message}',
      name: 'QrScanner',
    );
    return null;
  } on MissingPluginException catch (e) {
    AppLogger.instance.log(
      'QR scanner not available on this platform: $e',
      level: LogLevel.warn,
      name: 'QrScanner',
    );
    return null;
  }
}
