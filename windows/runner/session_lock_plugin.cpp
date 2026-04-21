#include "session_lock_plugin.h"

#include <wtsapi32.h>

#include <variant>

SessionLockPlugin::SessionLockPlugin(flutter::FlutterEngine* engine) {
  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), kChannel,
          &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const MethodCall& call, std::unique_ptr<MethodResult> result) {
        HandleMethodCall(call, std::move(result));
      });
}

SessionLockPlugin::~SessionLockPlugin() { Detach(); }

void SessionLockPlugin::Attach(HWND hwnd) {
  if (hwnd_ == hwnd) return;
  if (hwnd_ != nullptr) Detach();
  if (hwnd == nullptr) return;
  if (::WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)) {
    hwnd_ = hwnd;
  }
  // A failure here means the OS refused the subscription — log nothing to
  // avoid a startup-time MessageBox surprise; the Dart side keeps its
  // idle-timer fallback, so the app remains secure, just without the OS
  // signal amplification.
}

void SessionLockPlugin::Detach() {
  if (hwnd_ == nullptr) return;
  ::WTSUnRegisterSessionNotification(hwnd_);
  hwnd_ = nullptr;
}

bool SessionLockPlugin::HandleMessage(UINT message, WPARAM wparam) {
  if (message != WM_WTSSESSION_CHANGE) return false;
  if (wparam == WTS_SESSION_LOCK) {
    FireLocked();
  }
  // Return true for every session-change so the caller doesn't re-dispatch
  // to the default handler — the default handler is a no-op anyway, but
  // keeping the contract explicit avoids surprises.
  return true;
}

void SessionLockPlugin::HandleMethodCall(
    const MethodCall& call, std::unique_ptr<MethodResult> result) {
  // The Dart side calls `start` once to signal readiness. The subscription
  // itself already runs from Attach() — `start` is a handshake that tells
  // Dart the native side is reachable.
  if (call.method_name() == "start") {
    result->Success(flutter::EncodableValue(true));
    return;
  }
  result->NotImplemented();
}

void SessionLockPlugin::FireLocked() {
  if (channel_ == nullptr) return;
  channel_->InvokeMethod("sessionLocked", nullptr);
}
