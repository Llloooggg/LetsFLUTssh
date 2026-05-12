// iOS variant of the Apple AuthenticationServices bridge — same C
// ABI as `macos/Runner/SecurityKeyBroker.swift`. iOS 15.5+ for the
// `ASAuthorizationSecurityKeyPublicKeyCredentialProvider` surface;
// covers USB CTAP2 + NFC transparently. No CoreNFC entitlement
// required — the OS handles the NFC ISO7816 dance internally.
//
// Returns a `UIWindow`-backed presentation anchor since iOS does
// not have NSWindow / NSApplication.

import AuthenticationServices
import Foundation
import UIKit

@available(iOS 15.5, *)
private final class SecurityKeyDelegate: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    typealias CallbackFn = @convention(c) (
        UInt64,
        Int32,
        UnsafePointer<UInt8>?, Int,
        UnsafePointer<UInt8>?, Int,
        UnsafePointer<UInt8>?, Int,
        UnsafePointer<CChar>?
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
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }
            ?? ASPresentationAnchor()
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
        SecurityKeyBroker.shared.drop(tag: tag)
    }
}

@available(iOS 15.5, *)
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

@_cdecl("lfs_security_key_broker_is_available")
public func lfs_security_key_broker_is_available() -> Int32 {
    if #available(iOS 15.5, *) {
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
    guard #available(iOS 15.5, *) else { return 1 }
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
