import FlutterMacOS
import Foundation

/// Flags the app-support directory so Time Machine skips it. See
/// `lib/core/security/backup_exclusion.dart` for the rationale.
///
/// `URLResourceValues.isExcludedFromBackup = true` writes the
/// `com.apple.metadata:com_apple_backup_excludeItem` extended
/// attribute, which Time Machine honours for the directory and
/// everything under it. One call on startup is enough — if a user
/// action strips the xattr (e.g. restoring from an older backup that
/// didn't have it) the next launch sets it again.
final class BackupExclusionPlugin: NSObject {
  static let channelName = "com.letsflutssh/backup_exclusion"

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: BackupExclusionPlugin.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "excludeFromBackup":
      excludeFromBackup(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func excludeFromBackup(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterError(
        code: "BAD_ARGS",
        message: "excludeFromBackup requires {path: String}",
        details: nil
      ))
      return
    }
    var url = URL(fileURLWithPath: path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try url.setResourceValues(values)
      result(true)
    } catch {
      result(FlutterError(
        code: "EXCLUDE_FAILED",
        message: "setResourceValues failed: \(error.localizedDescription)",
        details: nil
      ))
    }
  }
}
