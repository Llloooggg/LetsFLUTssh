import Cocoa
import FlutterMacOS

// All previously-registered platform plugins have moved Rust-side
// under `lfs_os_security`:
//
// * HardwareVaultPlugin            → `lfs_os_security::hardware_tier_vault::apple`
// * SessionLockPlugin              → `lfs_os_security::session_lock_listener::macos_impl`
// * ClipboardSecurePlugin          → `lfs_os_security::secure_clipboard::apple`
// * BackupExclusionPlugin          → `lfs_os_security::backup_exclusion`
//
// The Dart wrappers route every call through FRB → `lfs_frb::api::*`,
// so this file no longer needs to instantiate / register any Swift
// MethodChannel handler. `RegisterGeneratedPlugins` still wires the
// pub.dev plugins (file_picker etc.) the project depends on.
class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Minimum window size to prevent layout overflow.
    self.contentMinSize = NSSize(width: 480, height: 360)

    super.awakeFromNib()
  }
}
