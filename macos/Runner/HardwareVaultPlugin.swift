import FlutterMacOS
import Foundation
import LocalAuthentication
import Security

/// Hardware-backed L3 vault for macOS.
///
/// Mirrors the iOS plugin (see `ios/Runner/HardwareVaultPlugin.swift`):
/// Secure Enclave P-256 keypair with `biometryCurrentSet` + external
/// PIN HMAC gate + ECIES-GCM wrap of the DB key. The only delta
/// between the platforms is the Flutter framework (`FlutterMacOS`
/// vs `Flutter`) and the lack of a file-protection class on macOS
/// (replaced with 0600 permissions via `FileManager` defaults).
///
/// Secure Enclave on macOS requires T2 / Apple Silicon. On older
/// Intel Macs `LAContext.canEvaluatePolicy(...)` will return false
/// and `isAvailable` reports unavailable — L3 wizard row stays
/// disabled with a tooltip.
///
/// Untested on real devices — shipped for the device-testing pass.
final class HardwareVaultPlugin: NSObject {
  static let channelName = "com.letsflutssh/hardware_vault"

  private static let keyTag = "com.letsflutssh.hw_vault.l3"
  private static let vaultFileName = "hardware_vault_apple.bin"
  // Secondary SE key for the bank-style biometric overlay — holds the
  // user's typed password bytes, gated by biometryCurrentSet so any
  // enrolment change invalidates the entry. Never touches the DB
  // wrapping key.
  private static let bioPasswordKeyTag = "com.letsflutssh.hw_password_overlay"
  private static let bioPasswordFileName = "hardware_vault_password_overlay_apple.bin"

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: HardwareVaultPlugin.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(isAvailable())
    case "backingLevel":
      result(backingLevel())
    case "probeDetail":
      result(probeDetail())
    case "isStored":
      result(FileManager.default.fileExists(atPath: vaultFileURL().path))
    case "store":
      store(call: call, result: result)
    case "read":
      read(call: call, result: result)
    case "clear":
      clearInternal()
      result(true)
    case "storeBiometricPassword":
      storeBiometricPassword(call: call, result: result)
    case "readBiometricPassword":
      readBiometricPassword(result: result)
    case "clearBiometricPassword":
      clearBiometricPasswordInternal()
      result(true)
    case "isBiometricPasswordStored":
      result(FileManager.default.fileExists(atPath: bioPasswordFileURL().path))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func isAvailable() -> Bool {
    // Silent primary key — passcode-only policy is enough, biometric
    // Touch ID on Mac is an optional modifier overlay handled
    // separately.
    //
    // `canEvaluatePolicy` + `SecAccessControlCreateWithFlags` only
    // verify that SE hardware is present and the API surface exists;
    // they don't detect the signing-identity rejection that happens
    // on ad-hoc-signed bundles (`errSecMissingEntitlement` / -34018).
    // Do a real write probe at the end: create a short-lived SE
    // private key under a scratch tag, delete it immediately. The
    // SE materialises the key lazily on first use, so the round-trip
    // is the only way to catch identity-based rejection short of
    // invoking `store` on real user data.
    let ctx = LAContext()
    var err: NSError?
    let canEval = ctx.canEvaluatePolicy(
      .deviceOwnerAuthentication, error: &err
    )
    guard canEval else { return false }
    guard SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      [.privateKeyUsage],
      nil
    ) != nil else { return false }
    return probeRealSecureEnclaveWrite()
  }

  /// True when [probeRealSecureEnclaveWriteCode] returns
  /// `"available"`. Convenience wrapper for `isAvailable`.
  private func probeRealSecureEnclaveWrite() -> Bool {
    return probeRealSecureEnclaveWriteCode() == "available"
  }

  /// Same Secure Enclave write round-trip as
  /// [probeRealSecureEnclaveWrite] but returns the classified
  /// reason code:
  ///
  /// * `available` — the throw-away SE key created and deleted
  ///   without error.
  /// * `macosSigningIdentityMissing` — `SecKeyCreateRandomKey`
  ///   failed with `errSecMissingEntitlement` (-34018), the
  ///   signature ad-hoc Code Directory hash macOS Keychain Services
  ///   refuses to bind keys to. The user fix is to run the bundled
  ///   `macos-resign.sh` script which gives the bundle a stable
  ///   self-signed identity.
  /// * `macosGeneric` — any other `SecKeyCreateRandomKey` failure.
  ///   Logged but no narrower copy.
  ///
  /// Deletion is best-effort: a leftover probe key would be
  /// garbage-collected by the OS on next reboot and does not gate
  /// any user data.
  private func probeRealSecureEnclaveWriteCode() -> String {
    let probeTag = "com.letsflutssh.hw_vault.probe"
    guard let ac = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      [.privateKeyUsage],
      nil
    ) else { return "macosGeneric" }
    let attrs: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String:
          probeTag.data(using: .utf8) as Any,
        kSecAttrAccessControl as String: ac,
      ] as [String: Any],
    ]
    var createErr: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &createErr)
    else {
      // Classify the CFError code so the wizard can point the user
      // at the macos-resign.sh script when the failure is
      // signing-identity rejection rather than a generic SE issue.
      // -34018 (`errSecMissingEntitlement`) is what ad-hoc-signed
      // bundles surface on every macOS release tested so far.
      let code = createErr?.takeRetainedValue().map { CFErrorGetCode($0) } ?? 0
      if code == -34018 { return "macosSigningIdentityMissing" }
      return "macosGeneric"
    }
    // Drop the probe key immediately. The macOS Security framework
    // deletes it by matching on the application tag.
    let delQuery: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecAttrApplicationTag as String:
        probeTag.data(using: .utf8) as Any,
    ]
    _ = SecItemDelete(delQuery as CFDictionary)
    // Reference `key` so ARC holds it past the delete call.
    _ = key
    return "available"
  }

  private func backingLevel() -> String {
    isAvailable() ? "hardware_secure_enclave" : "unavailable"
  }

  // Classified probe — mirrors the enum surface Dart exposes as
  // `HardwareProbeDetail`. Returns one of:
  //   * `available`                       — Secure Enclave reachable + passcode set.
  //   * `macosNoSecureEnclave`            — `LAContext` refuses
  //                                         `.deviceOwnerAuthentication`, typically
  //                                         a pre-T2 Intel Mac with no Secure
  //                                         Enclave hardware at all.
  //   * `macosPasscodeNotSet`             — SE hardware present but device passcode
  //                                         unset; L3 requires one for
  //                                         `biometryCurrentSet` binding.
  //   * `macosSigningIdentityMissing`     — Secure Enclave rejected the real
  //                                         key-create with -34018
  //                                         (`errSecMissingEntitlement`). Ad-hoc
  //                                         signing without a stable identity is
  //                                         the usual cause; the wizard surfaces
  //                                         the bundled `macos-resign.sh` script
  //                                         as the actionable fix.
  //   * `macosGeneric`                    — any other LAError fall-through
  //                                         (e.g. biometryLockout) or any other
  //                                         SE create failure. Logged for
  //                                         diagnostics; UI shows generic copy.
  private func probeDetail() -> String {
    let ctx = LAContext()
    var err: NSError?
    let canEval = ctx.canEvaluatePolicy(
      .deviceOwnerAuthentication, error: &err
    )
    if canEval {
      if SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
        [.privateKeyUsage],
        nil
      ) != nil {
        // Real Secure Enclave write round-trip — the shallow checks
        // above both pass on ad-hoc-signed bundles that the SE will
        // then reject with `errSecMissingEntitlement` (-34018) on the
        // first actual key create. Probe it once and use the typed
        // reason code so the wizard can route the user at the right
        // fix (resign script vs generic "unavailable") instead of
        // silent-dropping to T0.
        return probeRealSecureEnclaveWriteCode()
      }
      return "macosGeneric"
    }
    // Classify via the NSError code against LAError.Code rather than
    // the Swift bridge — the `_nsError:` initialiser on LAError is
    // internal API and varies across SDK releases. Integer codes are
    // stable on the LAErrorDomain wire protocol.
    guard let nsErr = err, nsErr.domain == LAErrorDomain else {
      return "macosGeneric"
    }
    switch LAError.Code(rawValue: nsErr.code) {
    case .some(.passcodeNotSet):
      return "macosPasscodeNotSet"
    case .some(.biometryNotAvailable), .some(.touchIDNotAvailable):
      // Intel Mac with no T2, or macOS that explicitly reports biometric
      // hardware missing. `.deviceOwnerAuthentication` falling through to
      // `biometryNotAvailable` without a passcode also signals no SE.
      return "macosNoSecureEnclave"
    default:
      return "macosGeneric"
    }
  }

  // MARK: - store / read

  private func store(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let dbKey = (args["dbKey"] as? FlutterStandardTypedData)?.data
    else {
      result(FlutterError(code: "ARG", message: "dbKey required", details: nil))
      return
    }
    // Optional pinHmac: null means the primary SE key is the sole
    // gate (passwordless T2).
    let pinHmac =
      (args["pinHmac"] as? FlutterStandardTypedData)?.data ?? Data()
    do {
      let publicKey = try ensureKey()
      let wrapped = try encrypt(dbKey: dbKey, publicKey: publicKey)
      try writeVault(pinHmac: pinHmac, wrapped: wrapped)
      result(true)
    } catch {
      result(FlutterError(code: "STORE", message: String(describing: error), details: nil))
    }
  }

  private func read(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let pinHmac =
      (args?["pinHmac"] as? FlutterStandardTypedData)?.data ?? Data()
    guard let vault = readVault() else {
      result(nil)
      return
    }
    guard constantTimeEquals(vault.pinHmac, pinHmac) else {
      result(nil)
      return
    }
    do {
      let dbKey = try decrypt(ciphertext: vault.wrapped)
      result(FlutterStandardTypedData(bytes: dbKey))
    } catch {
      result(FlutterError(code: "READ", message: String(describing: error), details: nil))
    }
  }

  // MARK: - biometric password overlay

  private func storeBiometricPassword(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let args = call.arguments as? [String: Any],
      let passwordBytes = (args["passwordBytes"] as? FlutterStandardTypedData)?.data
    else {
      result(FlutterError(
        code: "ARG",
        message: "passwordBytes required",
        details: nil
      ))
      return
    }
    do {
      let publicKey = try ensureBioPasswordKey()
      let wrapped = try encrypt(dbKey: passwordBytes, publicKey: publicKey)
      try writeBioPasswordBlob(wrapped: wrapped)
      result(true)
    } catch {
      result(FlutterError(
        code: "STORE_BIO_PW",
        message: String(describing: error),
        details: nil
      ))
    }
  }

  private func readBiometricPassword(result: @escaping FlutterResult) {
    guard let wrapped = readBioPasswordBlob() else {
      result(nil)
      return
    }
    do {
      let privateKey = try loadBioPasswordPrivateKey()
      let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA256AESGCM
      guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
        result(FlutterError(code: "READ_BIO_PW", message: "algorithm unsupported", details: nil))
        return
      }
      var err: Unmanaged<CFError>?
      guard let plain = SecKeyCreateDecryptedData(
        privateKey, algorithm, wrapped as CFData, &err
      ) else {
        throw (err?.takeRetainedValue() as Error?) ??
          NSError(domain: "HardwareVaultPlugin", code: -11)
      }
      result(FlutterStandardTypedData(bytes: plain as Data))
    } catch {
      result(FlutterError(code: "READ_BIO_PW", message: String(describing: error), details: nil))
    }
  }

  private func ensureBioPasswordKey() throws -> SecKey {
    if let existing = try? loadBioPasswordPublicKey() {
      return existing
    }
    guard let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      [.privateKeyUsage, .biometryCurrentSet],
      nil
    ) else {
      throw NSError(domain: "HardwareVaultPlugin", code: -20)
    }
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: HardwareVaultPlugin.bioPasswordKeyTag,
        kSecAttrAccessControl as String: access,
      ],
    ]
    var err: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &err) else {
      throw (err?.takeRetainedValue() as Error?) ??
        NSError(domain: "HardwareVaultPlugin", code: -21)
    }
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      throw NSError(domain: "HardwareVaultPlugin", code: -22)
    }
    return publicKey
  }

  private func loadBioPasswordPrivateKey() throws -> SecKey {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: HardwareVaultPlugin.bioPasswordKeyTag,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let key = item else {
      throw NSError(domain: "HardwareVaultPlugin", code: Int(status))
    }
    return key as! SecKey
  }

  private func loadBioPasswordPublicKey() throws -> SecKey {
    let privateKey = try loadBioPasswordPrivateKey()
    guard let pub = SecKeyCopyPublicKey(privateKey) else {
      throw NSError(domain: "HardwareVaultPlugin", code: -23)
    }
    return pub
  }

  private func bioPasswordFileURL() -> URL {
    let dir = try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let base = dir ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent(HardwareVaultPlugin.bioPasswordFileName)
  }

  private func writeBioPasswordBlob(wrapped: Data) throws {
    var out = Data()
    out.append(u32(wrapped.count))
    out.append(wrapped)
    try out.write(to: bioPasswordFileURL(), options: .atomic)
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: bioPasswordFileURL().path
    )
  }

  private func readBioPasswordBlob() -> Data? {
    guard let raw = try? Data(contentsOf: bioPasswordFileURL()) else { return nil }
    var pos = 0
    guard pos + 4 <= raw.count else { return nil }
    let len = Int(
      UInt32(raw[pos]) << 24 | UInt32(raw[pos + 1]) << 16 |
        UInt32(raw[pos + 2]) << 8 | UInt32(raw[pos + 3])
    )
    pos += 4
    guard pos + len <= raw.count else { return nil }
    return raw.subdata(in: pos..<(pos + len))
  }

  private func clearBiometricPasswordInternal() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: HardwareVaultPlugin.bioPasswordKeyTag,
    ]
    SecItemDelete(query as CFDictionary)
    try? FileManager.default.removeItem(at: bioPasswordFileURL())
  }

  private func ensureKey() throws -> SecKey {
    if let existing = try? loadPublicKey() { return existing }
    // Primary SE key is silent on macOS too — biometric (Touch ID)
    // lives on the overlay key, not here.
    guard let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      [.privateKeyUsage],
      nil
    ) else {
      throw NSError(domain: "HardwareVaultPlugin", code: -1)
    }
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: HardwareVaultPlugin.keyTag,
        kSecAttrAccessControl as String: access,
      ],
    ]
    var err: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &err) else {
      throw (err?.takeRetainedValue() as Error?) ??
        NSError(domain: "HardwareVaultPlugin", code: -2)
    }
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      throw NSError(domain: "HardwareVaultPlugin", code: -3)
    }
    return publicKey
  }

  private func loadPrivateKey() throws -> SecKey {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: HardwareVaultPlugin.keyTag,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let key = item else {
      throw NSError(domain: "HardwareVaultPlugin", code: Int(status))
    }
    return key as! SecKey
  }

  private func loadPublicKey() throws -> SecKey {
    let privateKey = try loadPrivateKey()
    guard let pub = SecKeyCopyPublicKey(privateKey) else {
      throw NSError(domain: "HardwareVaultPlugin", code: -4)
    }
    return pub
  }

  private func encrypt(dbKey: Data, publicKey: SecKey) throws -> Data {
    let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA256AESGCM
    guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
      throw NSError(domain: "HardwareVaultPlugin", code: -5)
    }
    var err: Unmanaged<CFError>?
    guard let cipher = SecKeyCreateEncryptedData(
      publicKey, algorithm, dbKey as CFData, &err
    ) else {
      throw (err?.takeRetainedValue() as Error?) ??
        NSError(domain: "HardwareVaultPlugin", code: -6)
    }
    return cipher as Data
  }

  private func decrypt(ciphertext: Data) throws -> Data {
    let privateKey = try loadPrivateKey()
    let algorithm = SecKeyAlgorithm.eciesEncryptionCofactorVariableIVX963SHA256AESGCM
    guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, algorithm) else {
      throw NSError(domain: "HardwareVaultPlugin", code: -7)
    }
    var err: Unmanaged<CFError>?
    guard let plain = SecKeyCreateDecryptedData(
      privateKey, algorithm, ciphertext as CFData, &err
    ) else {
      throw (err?.takeRetainedValue() as Error?) ??
        NSError(domain: "HardwareVaultPlugin", code: -8)
    }
    return plain as Data
  }

  // MARK: - disk I/O

  private struct VaultBlob {
    let pinHmac: Data
    let wrapped: Data
  }

  private func vaultFileURL() -> URL {
    let dir = try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let base = dir ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent(HardwareVaultPlugin.vaultFileName)
  }

  private func writeVault(pinHmac: Data, wrapped: Data) throws {
    var out = Data()
    out.append(u32(pinHmac.count))
    out.append(pinHmac)
    out.append(u32(wrapped.count))
    out.append(wrapped)
    try out.write(to: vaultFileURL(), options: .atomic)
    // macOS lacks iOS data-protection classes; harden via POSIX mode.
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: vaultFileURL().path
    )
  }

  private func readVault() -> VaultBlob? {
    guard let raw = try? Data(contentsOf: vaultFileURL()) else { return nil }
    var pos = 0
    func slice() -> Data? {
      guard pos + 4 <= raw.count else { return nil }
      let len = Int(
        UInt32(raw[pos]) << 24 | UInt32(raw[pos + 1]) << 16 |
          UInt32(raw[pos + 2]) << 8 | UInt32(raw[pos + 3])
      )
      pos += 4
      guard pos + len <= raw.count else { return nil }
      let out = raw.subdata(in: pos..<(pos + len))
      pos += len
      return out
    }
    guard let pinHmac = slice(), let wrapped = slice() else { return nil }
    return VaultBlob(pinHmac: pinHmac, wrapped: wrapped)
  }

  private func clearInternal() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: HardwareVaultPlugin.keyTag,
    ]
    SecItemDelete(query as CFDictionary)
    try? FileManager.default.removeItem(at: vaultFileURL())
    clearBiometricPasswordInternal()
  }

  private func u32(_ value: Int) -> Data {
    let v = UInt32(value)
    return Data([
      UInt8((v >> 24) & 0xFF),
      UInt8((v >> 16) & 0xFF),
      UInt8((v >> 8) & 0xFF),
      UInt8(v & 0xFF),
    ])
  }

  private func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count { diff |= a[i] ^ b[i] }
    return diff == 0
  }
}
