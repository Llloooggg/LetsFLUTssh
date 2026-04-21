import FlutterMacOS
import Foundation
import AppKit

/// Bridges macOS screen-lock notifications into the
/// `com.letsflutssh/session_lock` method channel.
///
/// macOS posts `com.apple.screenIsLocked` to the distributed
/// notification center every time the screen enters the locked
/// state — the lock-screen, `Ctrl+Cmd+Q`, power-button lock, Screen
/// Saver with "require password" on, and `pmset displaysleepnow`
/// all funnel into the same notification. Subscribing via
/// `NSDistributedNotificationCenter` is the long-standing supported
/// path; it costs nothing when idle and fires exactly once per
/// transition.
///
/// Paired on the unlock side by `com.apple.screenIsUnlocked`, which
/// the plugin does not forward — the Dart side only wants the
/// enter-locked transition (authenticated re-entry handles unlock).
final class SessionLockPlugin: NSObject {
  static let channelName = "com.letsflutssh/session_lock"

  private var channel: FlutterMethodChannel?
  private var observer: NSObjectProtocol?

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: SessionLockPlugin.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    self.channel = channel
    subscribe()
  }

  deinit {
    if let observer = observer {
      DistributedNotificationCenter.default().removeObserver(observer)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    // `start` is the Dart-side handshake — subscription already
    // runs from `register`, so `start` just confirms the channel is
    // live.
    if call.method == "start" {
      result(true)
      return
    }
    result(FlutterMethodNotImplemented)
  }

  private func subscribe() {
    guard observer == nil else { return }
    observer = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("com.apple.screenIsLocked"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.channel?.invokeMethod("sessionLocked", arguments: nil)
    }
  }
}
