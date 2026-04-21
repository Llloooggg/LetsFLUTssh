#pragma once

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

/// Hardware-backed L3 vault for Windows.
///
/// Two-key design, split across the Windows crypto stack:
///
///  - **Primary DB-wrap key** uses Windows CNG's `NCrypt` API on the
///    Microsoft Platform Crypto Provider (TPM 2.0). A persistent
///    RSA-2048 keypair named `LetsFLUTssh-DBKey-v2` is created once
///    per install with `NCryptCreatePersistedKey`, finalized with
///    `NCryptFinalizeKey`, and kept in the TPM for the lifetime of
///    the install. `NCryptEncrypt` / `NCryptDecrypt` wrap the DB key
///    with RSA-OAEP / SHA-256. **Silent** — no Windows Hello prompt,
///    no UI, so the unlock path does not ask the user twice when
///    the password modifier is on. When the Platform Crypto Provider
///    is unavailable (no TPM, unsupported firmware), the plugin
///    falls back to the Microsoft Software Key Storage Provider —
///    still stronger than DPAPI (key material stays in the CNG
///    store, not in the DPAPI blob in the user profile) but reported
///    honestly as software backing.
///  - **Biometric password overlay** keeps the existing
///    `KeyCredentialManager` / Windows Hello path. This is the
///    secondary entry that stores the user's typed password so the
///    next unlock can be biometric-only. It fires a Hello prompt by
///    design — the biometric gate is the whole point.
///
///  - PIN is an external HMAC gate: checked before the decrypt so a
///    wrong PIN fails silently without leaking whether the stored
///    blob exists.
///  - Vault file at `%LOCALAPPDATA%\LetsFLUTssh\hardware_vault_windows.bin`
///    (primary) and `hardware_vault_password_overlay_windows.bin`
///    (biometric overlay), ACL-inherited from LocalAppData
///    (current-user only).
///  - `backingLevel` reports `hardware_tpm` when the Platform Crypto
///    Provider backed the primary key and `software` when the
///    software provider was used.
///
/// Rewrite history: the first shipped revision used
/// `KeyCredentialManager::RequestSignAsync` for the primary wrap,
/// which fired Hello on every read. Switching to NCrypt removed
/// that double-prompt UX for password-modifier users.
class HardwareVaultPlugin {
 public:
  static constexpr const char* kChannel = "com.letsflutssh/hardware_vault";

  explicit HardwareVaultPlugin(flutter::FlutterEngine* engine);
  ~HardwareVaultPlugin();

  HardwareVaultPlugin(const HardwareVaultPlugin&) = delete;
  HardwareVaultPlugin& operator=(const HardwareVaultPlugin&) = delete;

 private:
  using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
  using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  void HandleMethodCall(const MethodCall& call,
                        std::unique_ptr<MethodResult> result);
};
