import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var qrScanning = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private let hardwareVault = HardwareVaultPlugin()
  private let backupExclusion = BackupExclusionPlugin()
  private let clipboardSecure = ClipboardSecurePlugin()
  private var secureText: SecureTextPlugin?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerQrScanner(with: engineBridge)
    registerHardwareVault(with: engineBridge)
    registerBackupExclusion(with: engineBridge)
    registerClipboardSecure(with: engineBridge)
    registerSecureText(with: engineBridge)
  }

  private func registerHardwareVault(with engineBridge: FlutterImplicitEngineBridge) {
    guard let messenger = engineBridge.pluginRegistry.registrar(
      forPlugin: "com.letsflutssh.hardware_vault",
    )?.messenger() else { return }
    hardwareVault.register(with: messenger)
  }

  private func registerBackupExclusion(with engineBridge: FlutterImplicitEngineBridge) {
    guard let messenger = engineBridge.pluginRegistry.registrar(
      forPlugin: "com.letsflutssh.backup_exclusion",
    )?.messenger() else { return }
    backupExclusion.register(with: messenger)
  }

  private func registerClipboardSecure(with engineBridge: FlutterImplicitEngineBridge) {
    guard let messenger = engineBridge.pluginRegistry.registrar(
      forPlugin: "com.letsflutssh.clipboard_secure",
    )?.messenger() else { return }
    clipboardSecure.register(with: messenger)
  }

  private func registerSecureText(with engineBridge: FlutterImplicitEngineBridge) {
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "com.letsflutssh.secure_text",
    ), let messenger = registrar.messenger() else { return }
    let plugin = SecureTextPlugin(messenger: messenger)
    plugin.register(with: registrar)
    secureText = plugin
  }

  private func registerQrScanner(with engineBridge: FlutterImplicitEngineBridge) {
    guard let messenger = engineBridge.pluginRegistry.registrar(
      forPlugin: "com.letsflutssh.qrscanner",
    )?.messenger() else { return }
    let channel = FlutterMethodChannel(
      name: "com.letsflutssh/qrscanner",
      binaryMessenger: messenger,
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "scan" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.presentQrScanner(result: result)
    }
  }

  private func presentQrScanner(result: @escaping FlutterResult) {
    if qrScanning {
      result(FlutterError(code: "BUSY", message: "Scan already in progress", details: nil))
      return
    }
    guard #available(iOS 13.0, *) else {
      result(nil)
      return
    }
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })?
      .rootViewController
    else {
      result(nil)
      return
    }
    qrScanning = true
    let scanner = QrScannerController { [weak self] value in
      self?.qrScanning = false
      result(value)
    }
    root.present(scanner, animated: true)
  }
}
