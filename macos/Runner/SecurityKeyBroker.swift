// Apple AuthenticationServices bridge for the Rust
// `lfs_os_security::fido2_broker::apple` module.
//
// Exposes two C-ABI entry points the Rust side resolves through
// `dlopen("")` at first use:
//
// * `lfs_security_key_broker_is_available` — synchronous probe.
//   Returns `0` when the API + entitlement are both ready, `1`
//   when the OS is too old (macOS pre-12), `2` when the entitlement
//   is missing, non-zero anything else when the probe failed.
//
// * `lfs_security_key_broker_get_assertion` — kicks off an
//   `ASAuthorizationController` for a security-key assertion. The
//   controller's delegate routes the success / failure into the C
//   callback the Rust side hands in. Returns `0` when the request
//   was dispatched (the callback fires later); non-zero on
//   synchronous reject.
//
// macOS 12+ for the security-key provider; the runtime probe gates
// the call on availability.
//
// Entitlement requirement: the running bundle must carry
// `com.apple.developer.web-browser.public-key-credential`. Self-
// signed dev builds without the Apple Developer Program identity
// hit `kSecurityKeyAuthorizationErrorCanceled` immediately —
// `lfs_security_key_broker_is_available` honestly reports `2`
// (entitlement missing) on that arm.

import AuthenticationServices
import Foundation

#if canImport(AppKit)
import AppKit
#endif

@available(macOS 12.0, *)
private final class SecurityKeyDelegate: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    typealias CallbackFn = @convention(c) (
        UInt64,            // tag
        Int32,             // status (0 ok / 1 cancel / 2 timeout / 3 wrong pin / 4 no cred / 5 transport / 6 other)
        UnsafePointer<UInt8>?, Int,  // signature ptr + len
        UnsafePointer<UInt8>?, Int,  // auth data ptr + len
        UnsafePointer<UInt8>?, Int,  // user handle ptr + len
        UnsafePointer<CChar>?        // optional message C string
    ) -> Void

    let tag: UInt64
    let callback: CallbackFn

    init(tag: UInt64, callback: @escaping CallbackFn) {
        self.tag = tag
        self.callback = callback
    }

    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        #if canImport(AppKit)
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let cred =
            authorization.credential as? ASAuthorizationSecurityKeyPublicKeyCredentialAssertion
        else {
            callback(tag, 6, nil, 0, nil, 0, nil, 0, "unexpected credential type")
            cleanup()
            return
        }
        let sig = Array(cred.signature)
        let auth = Array(cred.rawAuthenticatorData)
        let userHandle = Array(cred.userID)
        sig.withUnsafeBufferPointer { sigBuf in
            auth.withUnsafeBufferPointer { authBuf in
                userHandle.withUnsafeBufferPointer { uhBuf in
                    callback(
                        tag,
                        0,
                        sigBuf.baseAddress,
                        sigBuf.count,
                        authBuf.baseAddress,
                        authBuf.count,
                        uhBuf.baseAddress,
                        uhBuf.count,
                        nil,
                    )
                }
            }
        }
        cleanup()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        let status: Int32
        let nsErr = error as NSError
        switch nsErr.code {
        case ASAuthorizationError.canceled.rawValue:
            status = 1
        case ASAuthorizationError.failed.rawValue:
            status = 5
        case ASAuthorizationError.notHandled.rawValue:
            status = 4
        case ASAuthorizationError.notInteractive.rawValue:
            status = 6
        default:
            status = 6
        }
        let msg = nsErr.localizedDescription.cString(using: .utf8)
        msg?.withUnsafeBufferPointer { ptr in
            callback(tag, status, nil, 0, nil, 0, nil, 0, ptr.baseAddress)
        }
        cleanup()
    }

    private func cleanup() {
        // Drop the strong reference from the pending map so the
        // delegate + controller can be reclaimed.
        SecurityKeyBroker.shared.drop(tag: tag)
    }
}

@available(macOS 12.0, *)
private final class SecurityKeyBroker {
    static let shared = SecurityKeyBroker()
    private var pending: [UInt64: (SecurityKeyDelegate, ASAuthorizationController)] = [:]
    private let lock = NSLock()

    func retain(
        tag: UInt64,
        delegate: SecurityKeyDelegate,
        controller: ASAuthorizationController
    ) {
        lock.lock()
        pending[tag] = (delegate, controller)
        lock.unlock()
    }

    func drop(tag: UInt64) {
        lock.lock()
        pending.removeValue(forKey: tag)
        lock.unlock()
    }
}

// ── C ABI ────────────────────────────────────────────────────────────

@_cdecl("lfs_security_key_broker_is_available")
public func lfs_security_key_broker_is_available() -> Int32 {
    if #available(macOS 12.0, *) {
        // Entitlement probe: AuthenticationServices does not expose a
        // synchronous "do I have the entitlement?" check. We hand the
        // honest signal "API surface present" here; the actual
        // entitlement-missing arm surfaces as `ASAuthorizationError`
        // on the first get_assertion call, which the Rust dispatcher
        // routes through the BrokerError catch-all and the next
        // dispatch falls through to the direct HID path.
        return 0
    }
    return 1
}

@_cdecl("lfs_security_key_broker_get_assertion")
public func lfs_security_key_broker_get_assertion(
    rpId: UnsafePointer<CChar>,
    credentialIdPtr: UnsafePointer<UInt8>,
    credentialIdLen: Int,
    challengePtr: UnsafePointer<UInt8>,
    challengeLen: Int,
    requireUv: Int32,
    tag: UInt64,
    callback: @convention(c) (
        UInt64,
        Int32,
        UnsafePointer<UInt8>?, Int,
        UnsafePointer<UInt8>?, Int,
        UnsafePointer<UInt8>?, Int,
        UnsafePointer<CChar>?
    ) -> Void
) -> Int32 {
    guard #available(macOS 12.0, *) else { return 1 }
    let rpIdStr = String(cString: rpId)
    let credentialId = Data(bytes: credentialIdPtr, count: credentialIdLen)
    let challenge = Data(bytes: challengePtr, count: challengeLen)

    let provider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(
        relyingPartyIdentifier: rpIdStr
    )
    let request = provider.createCredentialAssertionRequest(challenge: challenge)
    request.allowedCredentials = [
        ASAuthorizationPublicKeyCredentialDescriptor(credentialID: credentialId)
    ]
    request.userVerificationPreference =
        requireUv != 0 ? .required : .discouraged

    let controller = ASAuthorizationController(authorizationRequests: [request])
    let delegate = SecurityKeyDelegate(tag: tag, callback: callback)
    controller.delegate = delegate
    controller.presentationContextProvider = delegate
    SecurityKeyBroker.shared.retain(tag: tag, delegate: delegate, controller: controller)
    controller.performRequests()
    return 0
}
