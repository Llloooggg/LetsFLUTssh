import Flutter
import Foundation
import UIKit

/// Clipboard writer that disables Handoff / Universal Clipboard on
/// every copy and stamps the item with a short expiration.
///
/// `UIPasteboard.general.setItems` with `.localOnly = true` keeps the
/// payload on the current device — the iCloud-backed Handoff path
/// that normally mirrors a copy to a paired Mac / iPad / iPhone is
/// skipped. Adding `.expirationDate` in the same call marks the
/// clipboard entry as short-lived so iOS clears it automatically
/// after the window, without the app having to remember to wipe.
/// Apple's Password-AutoFill copy path uses exactly this pattern.
final class ClipboardSecurePlugin: NSObject {
  static let channelName = "com.letsflutssh/clipboard_secure"

  /// Extra safety net on top of the Dart-side auto-wipe timer. iOS
  /// will drop the clipboard entry no later than this window even if
  /// the app has crashed / been backgrounded before the Dart wipe
  /// could fire.
  private static let expiration: TimeInterval = 60

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: ClipboardSecurePlugin.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "setSecureText" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let text = args["text"] as? String else {
      result(FlutterError(
        code: "BAD_ARGS",
        message: "setSecureText requires {text: String}",
        details: nil
      ))
      return
    }
    let item: [String: Any] = [UIPasteboard.typeAutomatic: text]
    let options: [UIPasteboard.OptionsKey: Any] = [
      .localOnly: true,
      .expirationDate: Date(timeIntervalSinceNow: ClipboardSecurePlugin.expiration),
    ]
    UIPasteboard.general.setItems([item], options: options)
    result(true)
  }
}
