import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let hardwareVault = HardwareVaultPlugin()
  // BackupExclusionPlugin retired — backup_exclusion now routes
  // through `lfs_os_security::backup_exclusion` (objc2 →
  // NSURL.setResourceValue:forKey:NSURLIsExcludedFromBackupKey).
  // The Swift plugin file stays on disk until the next Xcode
  // pbxproj cleanup so this commit doesn't have to touch the
  // project file.
  // ClipboardSecurePlugin retired — secure_clipboard now routes
  // through `lfs_os_security::secure_clipboard` (objc2-app-kit
  // → NSPasteboard with transient/concealed marker types). The
  // Swift plugin file stays on disk pending an Xcode pbxproj
  // cleanup so this commit doesn't have to touch the project file.
  private let sessionLock = SessionLockPlugin()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    hardwareVault.register(with: flutterViewController.engine.binaryMessenger)
    sessionLock.register(with: flutterViewController.engine.binaryMessenger)

    // Minimum window size to prevent layout overflow.
    self.contentMinSize = NSSize(width: 480, height: 360)

    super.awakeFromNib()
  }
}
