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
    let ctx = LAContext()
    var err: NSError?
    let canEval = ctx.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, error: &err
    )
    guard canEval else { return false }
    return SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      [.privateKeyUsage, .biometryCurrentSet],
      nil
    ) != nil
  }

  private func backingLevel() -> String {
    isAvailable() ? "hardware_secure_enclave" : "unavailable"
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
    guard let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      [.privateKeyUsage, .biometryCurrentSet],
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
