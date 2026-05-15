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
import os.log

// Status codes mirror the Rust `on_complete` contract in
// `lfs_os_security::fido2_broker::apple` (see SwiftCallback doc in
// `rust/crates/lfs_os_security/src/fido2_broker.rs`): the Swift
// glue must hand back exactly these integers so the Rust side can
// map them to `BrokerError`. Keep the numeric values in lockstep
// with the macOS variant and the Rust match arm.
private enum BrokerStatus {
    static let ok: Int32 = 0
    static let cancelled: Int32 = 1
    static let timeout: Int32 = 2
    static let noCredential: Int32 = 4
    static let transport: Int32 = 5
    static let other: Int32 = 6
}

// Reaper window. ASAuthorizationController's callbacks are not
// guaranteed to fire on every code path (background, force-quit
// mid-prompt, OS dialog dismissed by some system event) — the
// pending map would leak the delegate + controller until process
// exit. 30 s comfortably outlasts a real user tap on a security
// key while still bounding orphan retention.
private let pendingTimeoutSeconds: TimeInterval = 30

private let brokerLog = OSLog(
    subsystem: "io.lfs.securitykey",
    category: "SecurityKeyBroker",
)

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
            os_log(
                "didCompleteWithAuthorization tag=%{public}llu unexpected credential type",
                log: brokerLog,
                type: .info,
                tag,
            )
            callback(tag, BrokerStatus.other, nil, 0, nil, 0, nil, 0, "unexpected credential type")
            cleanup()
            return
        }
        let sig = Array(cred.signature)
        let auth = Array(cred.rawAuthenticatorData)
        let userHandle = Array(cred.userID)
        // Log lengths only — never signature or auth-data contents.
        os_log(
            "didCompleteWithAuthorization tag=%{public}llu sigLen=%d authLen=%d uhLen=%d",
            log: brokerLog,
            type: .info,
            tag,
            sig.count,
            auth.count,
            userHandle.count,
        )
        sig.withUnsafeBufferPointer { sigBuf in
            auth.withUnsafeBufferPointer { authBuf in
                userHandle.withUnsafeBufferPointer { uhBuf in
                    callback(
                        tag,
                        BrokerStatus.ok,
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
            status = BrokerStatus.cancelled
        case ASAuthorizationError.failed.rawValue:
            status = BrokerStatus.transport
        case ASAuthorizationError.notHandled.rawValue:
            status = BrokerStatus.noCredential
        default:
            status = BrokerStatus.other
        }
        // `localizedDescription` is an OS-localized message — safe to log.
        os_log(
            "didCompleteWithError tag=%{public}llu status=%d code=%ld desc=%{public}@",
            log: brokerLog,
            type: .info,
            tag,
            status,
            nsErr.code,
            nsErr.localizedDescription,
        )
        let msg = nsErr.localizedDescription.cString(using: .utf8)
        msg?.withUnsafeBufferPointer { ptr in
            callback(tag, status, nil, 0, nil, 0, nil, 0, ptr.baseAddress)
        }
        cleanup()
    }

    private func cleanup() {
        os_log(
            "cleanup tag=%{public}llu",
            log: brokerLog,
            type: .info,
            tag,
        )
        SecurityKeyBroker.shared.drop(tag: tag)
    }
}

// Pending-entry lifetime invariant: a tag registered via `retain`
// cannot outlive the OS-level prompt. Exactly one of three paths
// removes it and signals Rust:
//   1. The `ASAuthorizationController` callback runs → the delegate
//      invokes the C callback, then calls `drop(tag:)`.
//   2. The 30 s reaper scheduled in `retain` fires → if the tag is
//      still present it is force-removed and the Rust callback is
//      invoked with `BrokerStatus.timeout`.
//   3. `UIApplication.didEnterBackgroundNotification` fires → every
//      remaining entry is drained with `BrokerStatus.timeout`.
// Whichever wins, the others find the tag absent and no-op.
@available(iOS 15.5, *)
private final class SecurityKeyBroker {
    static let shared = SecurityKeyBroker()

    private var pending: [UInt64: (SecurityKeyDelegate, ASAuthorizationController)] = [:]
    private let lock = NSLock()
    private var backgroundObserver: NSObjectProtocol?

    init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.drainAllAsTimeout(reason: "app entered background")
        }
    }

    deinit {
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func retain(
        tag: UInt64,
        delegate: SecurityKeyDelegate,
        controller: ASAuthorizationController
    ) {
        lock.lock()
        pending[tag] = (delegate, controller)
        lock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + pendingTimeoutSeconds) { [weak self] in
            self?.reapIfStillPending(tag: tag)
        }
    }

    func drop(tag: UInt64) {
        lock.lock()
        pending.removeValue(forKey: tag)
        lock.unlock()
    }

    private func reapIfStillPending(tag: UInt64) {
        lock.lock()
        let entry = pending.removeValue(forKey: tag)
        lock.unlock()
        guard let entry = entry else { return }
        os_log(
            "Security-key prompt for tag %{public}llu timed out after %.0fs",
            log: brokerLog,
            type: .info,
            tag,
            pendingTimeoutSeconds,
        )
        signalTimeout(tag: tag, delegate: entry.0)
    }

    private func drainAllAsTimeout(reason: String) {
        lock.lock()
        let drained = pending
        pending.removeAll()
        lock.unlock()
        guard !drained.isEmpty else { return }
        os_log(
            "Draining %d pending security-key prompt(s) as timeout (%{public}@)",
            log: brokerLog,
            type: .info,
            drained.count,
            reason,
        )
        for (tag, entry) in drained {
            signalTimeout(tag: tag, delegate: entry.0)
        }
    }

    private func signalTimeout(tag: UInt64, delegate: SecurityKeyDelegate) {
        let msg = "security-key prompt timed out".cString(using: .utf8)
        msg?.withUnsafeBufferPointer { ptr in
            delegate.callback(
                tag,
                BrokerStatus.timeout,
                nil, 0,
                nil, 0,
                nil, 0,
                ptr.baseAddress,
            )
        }
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

    // Entry-point breadcrumb — lengths and UV flag only, no credential
    // or challenge bytes.
    os_log(
        "get_assertion tag=%{public}llu rpId=%{public}@ credIdLen=%d challengeLen=%d requireUv=%d",
        log: brokerLog,
        type: .info,
        tag,
        rpIdStr,
        credentialIdLen,
        challengeLen,
        requireUv,
    )

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
