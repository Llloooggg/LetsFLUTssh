// Apple AuthenticationServices bridge for the Rust
// `lfs_os_security::fido2_broker::apple` module.
//
// Exposes two C-ABI entry points the Rust side resolves through
// `dlopen("")` at first use:
//
// * `lfs_security_key_broker_is_available` — synchronous probe.
//   Returns `0` when the API surface is present (macOS 12+), `1`
//   when the OS is too old (macOS pre-12). The entitlement state
//   is NOT probed here — AuthenticationServices has no synchronous
//   "do I have the entitlement?" check, and the probe runs before
//   any UI is shown so a heavy entitlement-discovery dance is the
//   wrong place to put it. The entitlement-missing arm surfaces
//   later, on the first `get_assertion` call, as an
//   `ASAuthorizationError` the Rust dispatcher maps to the
//   BrokerError catch-all; the next dispatch falls through to
//   the direct HID path with no user-visible regression.
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
// hit `kSecurityKeyAuthorizationErrorCanceled` immediately on the
// first `get_assertion` dispatch; the Rust dispatcher catches the
// error and the next dispatch falls back to the direct HID path.
// `lfs_security_key_broker_is_available` cannot detect this state
// in advance (no synchronous entitlement check exists).

import AuthenticationServices
import Foundation
import os.log

#if canImport(AppKit)
import AppKit
#endif

// Status codes mirror the Rust `on_complete` contract in
// `lfs_os_security::fido2_broker::apple` (see SwiftCallback doc in
// `rust/crates/lfs_os_security/src/fido2_broker.rs`): the Swift
// glue must hand back exactly these integers so the Rust side can
// map them to `BrokerError`. Keep the numeric values in lockstep
// with the iOS variant and the Rust match arm.
private enum BrokerStatus {
    static let ok: Int32 = 0
    static let cancelled: Int32 = 1
    static let timeout: Int32 = 2
    static let noCredential: Int32 = 4
    static let transport: Int32 = 5
    static let other: Int32 = 6
}

// Reaper window. ASAuthorizationController's callbacks are not
// guaranteed to fire on every code path (app deactivated, force-
// quit mid-prompt, OS dialog dismissed by some system event) —
// the pending map would leak the delegate + controller until
// process exit. 30 s comfortably outlasts a real user tap on a
// security key while still bounding orphan retention.
private let pendingTimeoutSeconds: TimeInterval = 30

private let brokerLog = OSLog(
    subsystem: "io.lfs.securitykey",
    category: "SecurityKeyBroker",
)

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
        case ASAuthorizationError.notInteractive.rawValue:
            status = BrokerStatus.other
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
        // Fire the callback exactly once even when the message is not
        // UTF-8 convertible — otherwise `cleanup()` drops the pending
        // entry and the Rust `oneshot` receiver hangs forever.
        if let msg = nsErr.localizedDescription.cString(using: .utf8) {
            msg.withUnsafeBufferPointer { ptr in
                callback(tag, status, nil, 0, nil, 0, nil, 0, ptr.baseAddress)
            }
        } else {
            callback(tag, status, nil, 0, nil, 0, nil, 0, nil)
        }
        cleanup()
    }

    private func cleanup() {
        // Drop the strong reference from the pending map so the
        // delegate + controller can be reclaimed.
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
//   3. `NSApplication.didResignActiveNotification` fires → every
//      remaining entry is drained with `BrokerStatus.timeout`.
// Whichever wins, the others find the tag absent and no-op.
@available(macOS 12.0, *)
private final class SecurityKeyBroker {
    static let shared = SecurityKeyBroker()

    private var pending: [UInt64: (SecurityKeyDelegate, ASAuthorizationController)] = [:]
    private let lock = NSLock()
    private var resignActiveObserver: NSObjectProtocol?

    init() {
        #if canImport(AppKit)
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.drainAllAsTimeout(reason: "app resigned active")
        }
        #endif
    }

    deinit {
        if let observer = resignActiveObserver {
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
        // Fire the callback exactly once even when the message is not
        // UTF-8 convertible — otherwise the Rust `oneshot` receiver
        // for this tag hangs forever.
        if let msg = "security-key prompt timed out".cString(using: .utf8) {
            msg.withUnsafeBufferPointer { ptr in
                delegate.callback(
                    tag,
                    BrokerStatus.timeout,
                    nil, 0,
                    nil, 0,
                    nil, 0,
                    ptr.baseAddress,
                )
            }
        } else {
            delegate.callback(
                tag,
                BrokerStatus.timeout,
                nil, 0,
                nil, 0,
                nil, 0,
                nil,
            )
        }
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
