#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

class HardwareVaultPlugin;
class SessionLockPlugin;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // L3 hardware vault (Windows Hello / KeyCredentialManager). Lives
  // as a member so its MethodChannel binding outlives OnCreate().
  std::unique_ptr<HardwareVaultPlugin> hardware_vault_;

  // ClipboardSecurePlugin retired — secure_clipboard now routes
  // through `lfs_os_security::secure_clipboard` (Win32 OpenClipboard
  // + RegisterClipboardFormatW for the cloud / history opt-out).

  // WTS session-change subscription — fires the Dart-side auto-lock
  // whenever the workstation locks (Win+L, Ctrl+Alt+Del → Lock, GPO
  // enforced lock). Must live on this window because the WTS
  // subscription is HWND-scoped.
  std::unique_ptr<SessionLockPlugin> session_lock_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
