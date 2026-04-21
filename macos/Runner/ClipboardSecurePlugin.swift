import FlutterMacOS
import Foundation
import AppKit

/// Clipboard writer that flags every copy as sensitive so the
/// nspasteboard.org-style clipboard managers skip it.
///
/// macOS sends `NSPasteboard.general` through Universal Clipboard to
/// other Apple devices on the same iCloud account. Apple does not
/// expose a first-party opt-out for that path; the best the app can
/// do is declare the de-facto community types
/// `org.nspasteboard.TransientType` and
/// `org.nspasteboard.ConcealedType` on the same pasteboard item.
/// 1Password, Maccy, Paste, Alfred and every other third-party
/// clipboard manager honours these markers. Universal Clipboard
/// itself remains a residual leak until Apple ships a real API —
/// documented in `docs/ARCHITECTURE.md §3.6`.
final class ClipboardSecurePlugin: NSObject {
  static let channelName = "com.letsflutssh/clipboard_secure"

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
    let pb = NSPasteboard.general
    pb.clearContents()
    // Declare the markers up front so the pasteboard item carries
    // them from the moment the text lands. Declaring after the
    // `setString` would leave a single-frame window where a watcher
    // sees the string without the transient marker.
    pb.declareTypes([
      .string,
      NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
      NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
    ], owner: nil)
    pb.setString(text, forType: .string)
    // Empty Data payload is conventional for these marker types —
    // the type being present is what the clipboard manager checks,
    // the payload is ignored.
    pb.setData(Data(),
               forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    pb.setData(Data(),
               forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    result(true)
  }
}
