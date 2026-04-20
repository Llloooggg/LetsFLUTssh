import Flutter
import UIKit

/// Native-memory-backed secure text field for iOS. Sibling to the
/// Android `SecureTextPlugin` — same contract, same channel names,
/// same one-shot `submit` emission. See
/// `lib/widgets/secure_native_text_field.dart` for the rationale.
///
/// Typed bytes live in the `UITextField` `.text` (Swift `String` —
/// value type, still heap-allocated but mutable and explicitly
/// zero-able). On IME Return the bytes are UTF-8 encoded, delivered
/// to Dart as a mutable `FlutterStandardTypedData(.bytes)`, and the
/// text field content is wiped in place before the call returns.
///
/// The trade-off vs Flutter `TextField`: Dart-heap residency
/// collapses from many per-keystroke String allocations to a single
/// one-frame Uint8List. Swift-heap residency (the actual typing
/// buffer) is still there, but Swift `String` backing is mutable —
/// the widget overwrites it with NUL before clearing, the same
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
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return SecureTextView(
            frame: frame,
            viewId: viewId,
            messenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

final class SecureTextView: NSObject, FlutterPlatformView, UITextFieldDelegate {
    private let container: UIView
    private let textField: UITextField
    private let channel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        self.container = UIView(frame: frame)
        self.textField = UITextField(frame: container.bounds)
        self.channel = FlutterMethodChannel(
            name: "com.letsflutssh/secure_text_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        textField.isSecureTextEntry = true
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.smartInsertDeleteType = .no
        textField.textContentType = .password
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addTarget(
            self,
            action: #selector(onEditingChanged),
            for: .editingChanged
        )
        textField.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.textColor = .black
        container.addSubview(textField)

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    func view() -> UIView { container }

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

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let bytes = emitAndWipe()
        channel.invokeMethod(
            "onSubmit",
            arguments: FlutterStandardTypedData(bytes: bytes)
        )
        textField.resignFirstResponder()
        return true
    }

    @objc private func onEditingChanged(_ sender: UITextField) {
        let hasText = !(sender.text?.isEmpty ?? true)
        channel.invokeMethod("onChanged", arguments: ["hasText": hasText])
    }

    // MARK: - Wipe

    /// UTF-8 encode current content + overwrite the backing String
    /// with NUL before clearing. Swift `String` is a value type
    /// backed by a heap-allocated `_StringStorage`; overwriting
    /// produces the same NUL bytes in whichever arena the value
    /// currently resides in, so the GC-equivalent reclamation
    /// cannot resurrect the original characters.
    private func emitAndWipe() -> Data {
        let text = textField.text ?? ""
        let bytes = Data(text.utf8)
        wipeField()
        return bytes
    }

    private func wipeField() {
        if let t = textField.text, !t.isEmpty {
            let nulls = String(repeating: "\0", count: t.count)
            textField.text = nulls
        }
        textField.text = ""
    }
}
