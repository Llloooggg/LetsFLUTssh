#pragma once

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

/// Bridges the Windows Terminal Services session-change notification
/// into the `com.letsflutssh/session_lock` method channel.
///
/// Windows fires `WM_WTSSESSION_CHANGE` with `WTS_SESSION_LOCK` on
/// the user's window every time the workstation locks (`Win+L`,
/// session switch, Ctrl+Alt+Del → Lock, GPO-enforced lock, etc).
/// The subscription is per-HWND — the Flutter window has to call
/// `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)`
/// once on create — so the plugin lives in the runner, not in a
/// plugin DLL, and the window forwards its WndProc messages to
/// `HandleMessage`.
///
/// The session-change message also covers `WTS_CONSOLE_CONNECT`,
/// `WTS_SESSION_UNLOCK`, and friends; the plugin ignores everything
/// except `WTS_SESSION_LOCK` because the Dart side only wants the
/// enter-locked transition (the unlock path is handled by the app's
/// own authentication flow on return).
class SessionLockPlugin {
 public:
  static constexpr const char* kChannel = "com.letsflutssh/session_lock";

  explicit SessionLockPlugin(flutter::FlutterEngine* engine);
  ~SessionLockPlugin();

  SessionLockPlugin(const SessionLockPlugin&) = delete;
  SessionLockPlugin& operator=(const SessionLockPlugin&) = delete;

  /// Register the WTS subscription on [hwnd]. Must be called once
  /// the window HWND is known (from `FlutterWindow::OnCreate`).
  /// Idempotent — a second call with the same hwnd is a no-op.
  void Attach(HWND hwnd);

  /// Release the WTS subscription. Called on window destroy so the
  /// OS does not keep delivering messages to a dead HWND.
  void Detach();

  /// Forwarded from `FlutterWindow::MessageHandler`. Returns true if
  /// the message was a session-change we handled, false otherwise
  /// (so the caller can keep propagating other messages).
  bool HandleMessage(UINT message, WPARAM wparam);

 private:
  using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
  using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND hwnd_ = nullptr;

  void HandleMethodCall(const MethodCall& call,
                        std::unique_ptr<MethodResult> result);
  void FireLocked();
};
