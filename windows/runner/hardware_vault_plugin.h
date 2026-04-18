#pragma once

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

/// Hardware-backed L3 vault for Windows (KeyCredentialManager /
/// Windows Hello).
///
/// Design:
///  - Per-install named KeyCredential created via
///    `KeyCredentialManager::RequestCreateAsync` with a stable
///    identifier (`"letsflutssh_hw_vault_l3"`). The Windows
///    platform places the private half inside the TPM when a TPM is
///    present, otherwise in the Hello software enclave. The
///    `KeyCredentialAttestationStatus` on the create call tells us
///    which path was taken — surfaced through `backingLevel` so the
///    Settings row can render an honest label.
///  - The DB key is signed (wrapped) via
///    `KeyCredential::RequestSignAsync` and the signature + PIN-HMAC
///    + payload are written to `hardware_vault_windows.bin` in the
///    app's LocalAppData dir, ACL-tightened to the current user.
///  - Unseal presents Hello via the same `RequestSignAsync` call,
///    producing the same signature; the wrap is stable because the
///    per-credential key is deterministic.
///  - PIN is an external HMAC gate: Hello cannot be asked to accept
///    an arbitrary PIN as auth, so the gate is checked *before* the
///    Hello prompt. Wrong PIN fails without prompting the user.
///
/// Untested on a Windows host — shipped for the device-testing pass.
/// Compiles only when the MSBuild + WinRT toolchain is present;
/// Flutter ignores the folder on non-Windows hosts.
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
