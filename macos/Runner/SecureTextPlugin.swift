import AppKit
import FlutterMacOS

/// Native-memory-backed secure text field for macOS. Sibling to the
/// Android / iOS `SecureTextPlugin` — same contract, same channel
/// names, same one-shot `submit` emission. See
/// `lib/widgets/secure_native_text_field.dart` for the rationale.
///
/// `NSSecureTextField` is the AppKit equivalent of UIKit's
/// `UITextField(isSecureTextEntry: true)` — mask-rendered, no copy,
/// no drag-select, no dictation. The typed bytes live inside the
/// field's `stringValue` (Swift `String`). On Return we UTF-8-encode,
/// deliver the bytes to Dart as `FlutterStandardTypedData.bytes`,
/// and overwrite the field with NUL before clearing — same
/// discipline Android's EditText wipe follows.
final class SecureTextPlugin {
    static let viewType = "com.letsflutssh/secure_text"

    private let messenger: FlutterBinaryMessenger
    private var factory: SecureTextFactory?

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
    }

    func register(with registrar: FlutterPluginRegistrar) {
        let factory = SecureTextFactory(messenger: messenger)
        registrar.register(factory, withId: SecureTextPlugin.viewType)
        self.factory = factory
    }
}

final class SecureTextFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withViewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> NSView {
        return SecureTextView(viewId: viewId, messenger: messenger).view()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

final class SecureTextView: NSObject, FlutterPlatformView, NSTextFieldDelegate {
    private let container: NSView
    private let textField: NSSecureTextField
    private let channel: FlutterMethodChannel

    init(viewId: Int64, messenger: FlutterBinaryMessenger) {
        self.container = NSView()
        self.textField = NSSecureTextField()
        self.channel = FlutterMethodChannel(
            name: "com.letsflutssh/secure_text_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.delegate = self
        textField.target = self
        textField.action = #selector(onAction)
        textField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textField.topAnchor.constraint(equalTo: container.topAnchor),
            textField.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    func view() -> NSView { container }

    // MARK: - Channel methods

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "submit":
            let bytes = emitAndWipe()
            result(FlutterStandardTypedData(bytes: bytes))
        case "focus":
            textField.becomeFirstResponder()
            result(true)
        case "clear":
            wipeField()
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        let hasText = !(textField.stringValue.isEmpty)
        channel.invokeMethod("onChanged", arguments: ["hasText": hasText])
    }

    // MARK: - Action (Return key)

    @objc private func onAction(_ sender: NSSecureTextField) {
        let bytes = emitAndWipe()
        channel.invokeMethod(
            "onSubmit",
            arguments: FlutterStandardTypedData(bytes: bytes)
        )
    }

    // MARK: - Wipe

    private func emitAndWipe() -> Data {
        let text = textField.stringValue
        let bytes = Data(text.utf8)
        wipeField()
        return bytes
    }

    private func wipeField() {
        let current = textField.stringValue
        if !current.isEmpty {
            textField.stringValue = String(repeating: "\0", count: current.count)
        }
        textField.stringValue = ""
    }
}
