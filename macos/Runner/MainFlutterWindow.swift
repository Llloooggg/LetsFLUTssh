import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let hardwareVault = HardwareVaultPlugin()
  private let backupExclusion = BackupExclusionPlugin()
  private let clipboardSecure = ClipboardSecurePlugin()
  private let sessionLock = SessionLockPlugin()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    hardwareVault.register(with: flutterViewController.engine.binaryMessenger)
    backupExclusion.register(with: flutterViewController.engine.binaryMessenger)
    clipboardSecure.register(with: flutterViewController.engine.binaryMessenger)
    sessionLock.register(with: flutterViewController.engine.binaryMessenger)

    // Minimum window size to prevent layout overflow.
    self.contentMinSize = NSSize(width: 480, height: 360)

    super.awakeFromNib()
  }
}
