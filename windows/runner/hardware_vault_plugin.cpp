#include "hardware_vault_plugin.h"

#include <windows.h>

#include <ncrypt.h>
#include <bcrypt.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Storage.Streams.h>

#include <filesystem>
#include <fstream>
#include <optional>
#include <string>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

// ── Storage paths ─────────────────────────────────────────────────

constexpr wchar_t kPrimaryFileName[] = L"hardware_vault_windows.bin";
constexpr wchar_t kOverlayFileName[] =
    L"hardware_vault_password_overlay_windows.bin";

// Magic byte that distinguishes the NCrypt-era vault from any earlier
// format. Bumps to 0x03 the day we change the wire format again.
constexpr uint8_t kVaultMagicV2 = 0x02;

// ── CNG key names ─────────────────────────────────────────────────
//
// NCrypt persists keys by name inside the provider's key store.
// Stable names per install; rotating them by suffix (_v2, _v3, …) is
// the forward-compat plan if we ever need to ship a second key
// alongside the first.

constexpr wchar_t kPrimaryKeyName[] = L"LetsFLUTssh-DBKey-v2";
constexpr wchar_t kOverlayKeyName[] = L"LetsFLUTssh-BioOverlay-v2";

std::filesystem::path LocalAppDir() {
  wchar_t buffer[MAX_PATH] = {0};
  DWORD len = GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, MAX_PATH);
  std::filesystem::path base = (len > 0 && len < MAX_PATH)
                                   ? std::filesystem::path(buffer)
                                   : std::filesystem::temp_directory_path();
  base /= L"LetsFLUTssh";
  std::filesystem::create_directories(base);
  return base;
}

std::filesystem::path PrimaryPath() { return LocalAppDir() / kPrimaryFileName; }
std::filesystem::path OverlayPath() { return LocalAppDir() / kOverlayFileName; }

// ── Byte-stream helpers ───────────────────────────────────────────

void WriteU32(std::vector<uint8_t>& out, uint32_t v) {
  out.push_back(static_cast<uint8_t>((v >> 24) & 0xFF));
  out.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
  out.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
  out.push_back(static_cast<uint8_t>(v & 0xFF));
}

bool ReadU32(const std::vector<uint8_t>& buf, size_t& pos, uint32_t& out) {
  if (pos + 4 > buf.size()) return false;
  out = (static_cast<uint32_t>(buf[pos]) << 24) |
        (static_cast<uint32_t>(buf[pos + 1]) << 16) |
        (static_cast<uint32_t>(buf[pos + 2]) << 8) |
        static_cast<uint32_t>(buf[pos + 3]);
  pos += 4;
  return true;
}

bool ConstantTimeEquals(const std::vector<uint8_t>& a,
                        const std::vector<uint8_t>& b) {
  if (a.size() != b.size()) return false;
  uint8_t diff = 0;
  for (size_t i = 0; i < a.size(); ++i) diff |= a[i] ^ b[i];
  return diff == 0;
}

bool WriteAll(const std::filesystem::path& path,
              const std::vector<uint8_t>& data) {
  std::ofstream ofs(path, std::ios::binary | std::ios::trunc);
  if (!ofs) return false;
  ofs.write(reinterpret_cast<const char*>(data.data()),
            static_cast<std::streamsize>(data.size()));
  return ofs.good();
}

std::optional<std::vector<uint8_t>> ReadAll(const std::filesystem::path& path) {
  std::ifstream ifs(path, std::ios::binary);
  if (!ifs) return std::nullopt;
  return std::vector<uint8_t>((std::istreambuf_iterator<char>(ifs)),
                              std::istreambuf_iterator<char>());
}

// ── NCrypt primary path ───────────────────────────────────────────
//
// All functions here run on the calling thread. The Flutter plugin
// already dispatches off the UI thread for store/read, so the
// synchronous NCrypt calls are safe to run inline — they never
// touch the UI.

struct ProviderHandle {
  NCRYPT_PROV_HANDLE handle = 0;
  bool is_hardware = false;  // Platform Crypto Provider (TPM) vs software.
  ~ProviderHandle() {
    if (handle) NCryptFreeObject(handle);
  }
};

// Try the Platform Crypto Provider first; fall back to the Microsoft
// Software Key Storage Provider. Caller owns the returned handle.
std::unique_ptr<ProviderHandle> OpenProvider() {
  auto p = std::make_unique<ProviderHandle>();
  SECURITY_STATUS s = NCryptOpenStorageProvider(
      &p->handle, MS_PLATFORM_CRYPTO_PROVIDER, 0);
  if (s == ERROR_SUCCESS) {
    p->is_hardware = true;
    return p;
  }
  s = NCryptOpenStorageProvider(&p->handle, MS_KEY_STORAGE_PROVIDER, 0);
  if (s == ERROR_SUCCESS) {
    p->is_hardware = false;
    return p;
  }
  return nullptr;
}

// Probe only — no key creation. Used by `isAvailable` / `backingLevel`.
enum class AvailabilityTier {
  kUnavailable,
  kSoftware,  // KSP available, Platform provider missing.
  kHardware,  // Platform Crypto Provider reachable.
};

AvailabilityTier ProbeAvailability() {
  auto p = OpenProvider();
  if (!p) return AvailabilityTier::kUnavailable;
  return p->is_hardware ? AvailabilityTier::kHardware
                        : AvailabilityTier::kSoftware;
}

// Open an existing persistent key, or create one. `require_ui` flips
// `NCRYPT_UI_POLICY_PROPERTY` with `NCRYPT_UI_PROTECT_KEY_FLAG` so
// Windows prompts (via Hello on a Hello-configured system) before
// every usage — used for the biometric-overlay key. The primary
// DB-wrap key leaves the UI policy unset so unlock stays silent.
NCRYPT_KEY_HANDLE OpenOrCreateKey(ProviderHandle& prov,
                                  const wchar_t* key_name, bool require_ui) {
  NCRYPT_KEY_HANDLE key = 0;
  SECURITY_STATUS s = NCryptOpenKey(prov.handle, &key, key_name, 0, 0);
  if (s == ERROR_SUCCESS) return key;

  // Create fresh.
  s = NCryptCreatePersistedKey(prov.handle, &key, BCRYPT_RSA_ALGORITHM,
                               key_name, 0, 0);
  if (s != ERROR_SUCCESS) return 0;

  // 2048-bit RSA — TPM Platform Crypto Provider supports this; the
  // software KSP supports it too. Anything larger would shrink the
  // OAEP payload window below the DB key length, and we do not need
  // beyond 112-bit security margin for a key-wrapping key whose
  // plaintext is already a 32-byte random key.
  DWORD len = 2048;
  NCryptSetProperty(key, NCRYPT_LENGTH_PROPERTY,
                    reinterpret_cast<PBYTE>(&len), sizeof(len),
                    NCRYPT_PERSIST_FLAG);

  if (require_ui) {
    NCRYPT_UI_POLICY ui = {0};
    ui.dwVersion = 1;
    ui.dwFlags = NCRYPT_UI_PROTECT_KEY_FLAG;
    ui.pszCreationTitle = L"LetsFLUTssh — confirm biometric unlock";
    ui.pszFriendlyName = L"LetsFLUTssh biometric overlay";
    ui.pszDescription =
        L"LetsFLUTssh wants to use your Windows Hello PIN or biometric "
        L"to unlock the stored password for faster sign-in.";
    NCryptSetProperty(key, NCRYPT_UI_POLICY_PROPERTY,
                      reinterpret_cast<PBYTE>(&ui), sizeof(ui),
                      NCRYPT_PERSIST_FLAG);
  }

  s = NCryptFinalizeKey(key, 0);
  if (s != ERROR_SUCCESS) {
    NCryptFreeObject(key);
    return 0;
  }
  return key;
}

// RSA-OAEP SHA-256 encrypt. Returns the ciphertext or an empty
// vector on failure (no partial results).
std::vector<uint8_t> RsaOaepEncrypt(NCRYPT_KEY_HANDLE key,
                                    const std::vector<uint8_t>& plain) {
  BCRYPT_OAEP_PADDING_INFO pad = {0};
  pad.pszAlgId = BCRYPT_SHA256_ALGORITHM;
  DWORD ct_len = 0;
  SECURITY_STATUS s = NCryptEncrypt(
      key, const_cast<PBYTE>(plain.data()), static_cast<DWORD>(plain.size()),
      &pad, nullptr, 0, &ct_len, NCRYPT_PAD_OAEP_FLAG);
  if (s != ERROR_SUCCESS || ct_len == 0) return {};
  std::vector<uint8_t> ct(ct_len);
  s = NCryptEncrypt(key, const_cast<PBYTE>(plain.data()),
                    static_cast<DWORD>(plain.size()), &pad, ct.data(), ct_len,
                    &ct_len, NCRYPT_PAD_OAEP_FLAG);
  if (s != ERROR_SUCCESS) return {};
  ct.resize(ct_len);
  return ct;
}

std::vector<uint8_t> RsaOaepDecrypt(NCRYPT_KEY_HANDLE key,
                                    const std::vector<uint8_t>& ct) {
  BCRYPT_OAEP_PADDING_INFO pad = {0};
  pad.pszAlgId = BCRYPT_SHA256_ALGORITHM;
  DWORD pt_len = 0;
  SECURITY_STATUS s = NCryptDecrypt(key, const_cast<PBYTE>(ct.data()),
                                    static_cast<DWORD>(ct.size()), &pad,
                                    nullptr, 0, &pt_len, NCRYPT_PAD_OAEP_FLAG);
  if (s != ERROR_SUCCESS || pt_len == 0) return {};
  std::vector<uint8_t> pt(pt_len);
  s = NCryptDecrypt(key, const_cast<PBYTE>(ct.data()),
                    static_cast<DWORD>(ct.size()), &pad, pt.data(), pt_len,
                    &pt_len, NCRYPT_PAD_OAEP_FLAG);
  if (s != ERROR_SUCCESS) return {};
  pt.resize(pt_len);
  return pt;
}

// ── Vault file format v2 ─────────────────────────────────────────
//
// byte[1]  magic = 0x02
// u32      pin_hmac_len
// byte[]   pin_hmac       (empty for the biometric overlay)
// u32      ct_len
// byte[]   ciphertext     (RSA-OAEP-SHA256 wrap of the payload)

struct VaultBlob {
  std::vector<uint8_t> pin_hmac;
  std::vector<uint8_t> ciphertext;
};

std::vector<uint8_t> EncodeBlob(const VaultBlob& blob) {
  std::vector<uint8_t> out;
  out.push_back(kVaultMagicV2);
  WriteU32(out, static_cast<uint32_t>(blob.pin_hmac.size()));
  out.insert(out.end(), blob.pin_hmac.begin(), blob.pin_hmac.end());
  WriteU32(out, static_cast<uint32_t>(blob.ciphertext.size()));
  out.insert(out.end(), blob.ciphertext.begin(), blob.ciphertext.end());
  return out;
}

std::optional<VaultBlob> DecodeBlob(const std::vector<uint8_t>& raw) {
  if (raw.empty() || raw[0] != kVaultMagicV2) return std::nullopt;
  size_t pos = 1;
  VaultBlob blob;
  auto take = [&](std::vector<uint8_t>& target) {
    uint32_t len = 0;
    if (!ReadU32(raw, pos, len)) return false;
    if (pos + len > raw.size()) return false;
    target.assign(raw.begin() + pos, raw.begin() + pos + len);
    pos += len;
    return true;
  };
  if (!take(blob.pin_hmac)) return std::nullopt;
  if (!take(blob.ciphertext)) return std::nullopt;
  return blob;
}

// ── Primary: DB-key wrap (silent, no UI) ─────────────────────────

bool PrimaryStore(const std::vector<uint8_t>& db_key,
                  const std::vector<uint8_t>& pin_hmac) {
  auto prov = OpenProvider();
  if (!prov) return false;
  NCRYPT_KEY_HANDLE key =
      OpenOrCreateKey(*prov, kPrimaryKeyName, /*require_ui=*/false);
  if (!key) return false;
  auto ct = RsaOaepEncrypt(key, db_key);
  NCryptFreeObject(key);
  if (ct.empty()) return false;
  VaultBlob blob{pin_hmac, std::move(ct)};
  return WriteAll(PrimaryPath(), EncodeBlob(blob));
}

std::optional<std::vector<uint8_t>> PrimaryRead(
    const std::vector<uint8_t>& pin_hmac) {
  auto raw = ReadAll(PrimaryPath());
  if (!raw) return std::nullopt;
  auto blob = DecodeBlob(*raw);
  if (!blob) return std::nullopt;
  if (!ConstantTimeEquals(blob->pin_hmac, pin_hmac)) return std::nullopt;
  auto prov = OpenProvider();
  if (!prov) return std::nullopt;
  NCRYPT_KEY_HANDLE key =
      OpenOrCreateKey(*prov, kPrimaryKeyName, /*require_ui=*/false);
  if (!key) return std::nullopt;
  auto pt = RsaOaepDecrypt(key, blob->ciphertext);
  NCryptFreeObject(key);
  if (pt.empty()) return std::nullopt;
  return pt;
}

void PrimaryClear() {
  std::error_code ec;
  std::filesystem::remove(PrimaryPath(), ec);
  auto prov = OpenProvider();
  if (!prov) return;
  NCRYPT_KEY_HANDLE key = 0;
  if (NCryptOpenKey(prov->handle, &key, kPrimaryKeyName, 0, 0) ==
      ERROR_SUCCESS) {
    NCryptDeleteKey(key, 0);
    // NCryptDeleteKey frees the handle on success.
  }
}

// ── Biometric overlay: password wrap (Hello-gated) ───────────────
//
// Same encrypt / decrypt path as the primary, but the overlay key is
// created with NCRYPT_UI_PROTECT_KEY_FLAG so every decrypt pops the
// Hello consent dialog. The overlay blob stores only the ciphertext
// (no pin_hmac — the biometric itself is the gate).

bool OverlayStore(const std::vector<uint8_t>& password) {
  auto prov = OpenProvider();
  if (!prov) return false;
  NCRYPT_KEY_HANDLE key =
      OpenOrCreateKey(*prov, kOverlayKeyName, /*require_ui=*/true);
  if (!key) return false;
  auto ct = RsaOaepEncrypt(key, password);
  NCryptFreeObject(key);
  if (ct.empty()) return false;
  VaultBlob blob{{}, std::move(ct)};
  return WriteAll(OverlayPath(), EncodeBlob(blob));
}

std::optional<std::vector<uint8_t>> OverlayRead() {
  auto raw = ReadAll(OverlayPath());
  if (!raw) return std::nullopt;
  auto blob = DecodeBlob(*raw);
  if (!blob) return std::nullopt;
  auto prov = OpenProvider();
  if (!prov) return std::nullopt;
  NCRYPT_KEY_HANDLE key =
      OpenOrCreateKey(*prov, kOverlayKeyName, /*require_ui=*/true);
  if (!key) return std::nullopt;
  // Decrypt fires the Hello prompt because of NCRYPT_UI_PROTECT_KEY.
  auto pt = RsaOaepDecrypt(key, blob->ciphertext);
  NCryptFreeObject(key);
  if (pt.empty()) return std::nullopt;
  return pt;
}

void OverlayClear() {
  std::error_code ec;
  std::filesystem::remove(OverlayPath(), ec);
  auto prov = OpenProvider();
  if (!prov) return;
  NCRYPT_KEY_HANDLE key = 0;
  if (NCryptOpenKey(prov->handle, &key, kOverlayKeyName, 0, 0) ==
      ERROR_SUCCESS) {
    NCryptDeleteKey(key, 0);
  }
}

bool OverlayStored() {
  std::error_code ec;
  return std::filesystem::exists(OverlayPath(), ec);
}

// ── Arg parsing ──────────────────────────────────────────────────

std::vector<uint8_t> GetBytes(const EncodableMap& args, const char* key) {
  auto it = args.find(EncodableValue(key));
  if (it == args.end()) return {};
  if (auto* bytes = std::get_if<std::vector<uint8_t>>(&it->second)) {
    return *bytes;
  }
  return {};
}

}  // namespace

HardwareVaultPlugin::HardwareVaultPlugin(flutter::FlutterEngine* engine) {
  // WinRT init kept for the biometric-overlay code paths that may
  // still call into Windows.Security.Cryptography helpers if a
  // future revision needs them. Safe to leave here even when the
  // biometric path is pure CNG — the call is idempotent.
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
    // Already initialised on this thread — safe to ignore.
  }
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), kChannel,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

HardwareVaultPlugin::~HardwareVaultPlugin() = default;

void HardwareVaultPlugin::HandleMethodCall(
    const MethodCall& call, std::unique_ptr<MethodResult> result) {
  const std::string& method = call.method_name();

  if (method == "isAvailable") {
    result->Success(
        EncodableValue(ProbeAvailability() != AvailabilityTier::kUnavailable));
    return;
  }

  if (method == "backingLevel") {
    auto tier = ProbeAvailability();
    const char* label = tier == AvailabilityTier::kHardware ? "hardware_tpm"
                        : tier == AvailabilityTier::kSoftware ? "software"
                                                              : "unavailable";
    result->Success(EncodableValue(std::string(label)));
    return;
  }

  // Classified probe — the hardware tier is considered unavailable unless
  // the Microsoft Platform Crypto Provider (TPM 2.0) opens. Software KSP
  // still works for the rest of the app, but T2 requires real hardware.
  //
  // Returned codes mirror the enum surface Dart exposes as
  // `HardwareProbeDetail`:
  //   * `available`            — Platform Crypto Provider reachable.
  //   * `windowsSoftwareOnly`  — only the software KSP is reachable;
  //                               the host has no TPM 2.0 or it is
  //                               disabled in UEFI / Group Policy.
  //   * `windowsProvidersMissing` — neither CNG provider opens. Very
  //                               unusual — corrupted crypto subsystem
  //                               or locked-down enterprise config.
  if (method == "probeDetail") {
    auto tier = ProbeAvailability();
    const char* code = tier == AvailabilityTier::kHardware
                           ? "available"
                       : tier == AvailabilityTier::kSoftware
                           ? "windowsSoftwareOnly"
                           : "windowsProvidersMissing";
    result->Success(EncodableValue(std::string(code)));
    return;
  }

  if (method == "isStored") {
    std::error_code ec;
    result->Success(
        EncodableValue(std::filesystem::exists(PrimaryPath(), ec)));
    return;
  }

  if (method == "isBiometricPasswordStored") {
    result->Success(EncodableValue(OverlayStored()));
    return;
  }

  if (method == "clear") {
    PrimaryClear();
    OverlayClear();
    result->Success(EncodableValue(true));
    return;
  }

  if (method == "clearBiometricPassword") {
    OverlayClear();
    result->Success(EncodableValue(true));
    return;
  }

  const auto* args = std::get_if<EncodableMap>(call.arguments());
  if (!args) {
    result->Error("ARG", "expected map arguments");
    return;
  }

  if (method == "store") {
    auto db_key = GetBytes(*args, "dbKey");
    auto pin_hmac = GetBytes(*args, "pinHmac");
    if (db_key.empty() || pin_hmac.empty()) {
      result->Error("ARG", "dbKey + pinHmac required");
      return;
    }
    try {
      if (!PrimaryStore(db_key, pin_hmac)) {
        result->Error("STORE", "NCrypt encrypt or file write failed");
        return;
      }
      result->Success(EncodableValue(true));
    } catch (const std::exception& e) {
      result->Error("STORE", e.what());
    } catch (...) {
      result->Error("STORE", "unknown failure");
    }
    return;
  }

  if (method == "read") {
    auto pin_hmac = GetBytes(*args, "pinHmac");
    if (pin_hmac.empty()) {
      result->Error("ARG", "pinHmac required");
      return;
    }
    try {
      auto pt = PrimaryRead(pin_hmac);
      if (!pt) {
        result->Success(std::monostate{});
        return;
      }
      result->Success(EncodableValue(*pt));
    } catch (const std::exception& e) {
      result->Error("READ", e.what());
    } catch (...) {
      result->Error("READ", "unknown failure");
    }
    return;
  }

  if (method == "storeBiometricPassword") {
    auto password = GetBytes(*args, "passwordBytes");
    if (password.empty()) {
      result->Error("ARG", "passwordBytes required");
      return;
    }
    try {
      if (!OverlayStore(password)) {
        result->Error("STORE_BIO_PW", "NCrypt encrypt or file write failed");
        return;
      }
      result->Success(EncodableValue(true));
    } catch (const std::exception& e) {
      result->Error("STORE_BIO_PW", e.what());
    } catch (...) {
      result->Error("STORE_BIO_PW", "unknown failure");
    }
    return;
  }

  if (method == "readBiometricPassword") {
    try {
      auto pt = OverlayRead();
      if (!pt) {
        result->Success(std::monostate{});
        return;
      }
      result->Success(EncodableValue(*pt));
    } catch (const std::exception& e) {
      result->Error("READ_BIO_PW", e.what());
    } catch (...) {
      result->Error("READ_BIO_PW", "unknown failure");
    }
    return;
  }

  result->NotImplemented();
}
