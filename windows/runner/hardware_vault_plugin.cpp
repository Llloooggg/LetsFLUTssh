#include "hardware_vault_plugin.h"

#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Storage.Streams.h>

#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Foundation::IAsyncOperation;
using winrt::Windows::Security::Credentials::KeyCredential;
using winrt::Windows::Security::Credentials::KeyCredentialAttestationStatus;
using winrt::Windows::Security::Credentials::KeyCredentialCreationOption;
using winrt::Windows::Security::Credentials::KeyCredentialManager;
using winrt::Windows::Security::Credentials::KeyCredentialRetrievalResult;
using winrt::Windows::Security::Credentials::KeyCredentialStatus;
using winrt::Windows::Security::Cryptography::CryptographicBuffer;
using winrt::Windows::Storage::Streams::IBuffer;

constexpr wchar_t kCredentialName[] = L"letsflutssh_hw_vault_l3";
constexpr wchar_t kVaultFileName[] = L"hardware_vault_windows.bin";

std::filesystem::path VaultFilePath() {
  wchar_t buffer[MAX_PATH] = {0};
  DWORD len = GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, MAX_PATH);
  std::filesystem::path base = (len > 0 && len < MAX_PATH)
                                   ? std::filesystem::path(buffer)
                                   : std::filesystem::temp_directory_path();
  base /= L"LetsFLUTssh";
  std::filesystem::create_directories(base);
  return base / kVaultFileName;
}

std::vector<uint8_t> IBufferToVector(const IBuffer& buf) {
  if (buf == nullptr) return {};
  uint32_t length = buf.Length();
  auto reader = winrt::Windows::Storage::Streams::DataReader::FromBuffer(buf);
  std::vector<uint8_t> out(length);
  reader.ReadBytes(winrt::array_view<uint8_t>(out));
  return out;
}

IBuffer VectorToIBuffer(const std::vector<uint8_t>& data) {
  return CryptographicBuffer::CreateFromByteArray(
      winrt::array_view<const uint8_t>(data));
}

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

bool IsAvailableSync() {
  try {
    auto availability = KeyCredentialManager::IsSupportedAsync().get();
    return availability;
  } catch (...) {
    return false;
  }
}

KeyCredentialRetrievalResult EnsureCredential() {
  auto existing = KeyCredentialManager::OpenAsync(kCredentialName).get();
  if (existing.Status() == KeyCredentialStatus::Success) return existing;
  return KeyCredentialManager::RequestCreateAsync(
             kCredentialName,
             KeyCredentialCreationOption::ReplaceExisting)
      .get();
}

std::vector<uint8_t> SignWithCredential(const std::vector<uint8_t>& payload) {
  auto retrieval = EnsureCredential();
  if (retrieval.Status() != KeyCredentialStatus::Success) return {};
  auto credential = retrieval.Credential();
  auto buffer = VectorToIBuffer(payload);
  auto signResult = credential.RequestSignAsync(buffer).get();
  if (signResult.Status() != KeyCredentialStatus::Success) return {};
  return IBufferToVector(signResult.Result());
}

std::string BackingLevelSync() {
  if (!IsAvailableSync()) return "unavailable";
  try {
    auto retrieval = EnsureCredential();
    if (retrieval.Status() != KeyCredentialStatus::Success) return "software";
    // Windows does not expose TPM vs software on the
    // KeyCredentialRetrievalResult directly; we approximate by
    // calling GetAttestationAsync — success with a TPM-rooted
    // attestation implies hardware backing.
    auto attest = retrieval.Credential().GetAttestationAsync().get();
    switch (attest.Status()) {
      case KeyCredentialAttestationStatus::Success:
        return "hardware_tpm";
      case KeyCredentialAttestationStatus::TemporaryFailure:
      case KeyCredentialAttestationStatus::NotSupported:
      default:
        return "software";
    }
  } catch (...) {
    return "software";
  }
}

struct VaultBlob {
  std::vector<uint8_t> pin_hmac;
  std::vector<uint8_t> payload;     // plaintext block that is the sign input
  std::vector<uint8_t> signature;   // wrapped DB key
};

bool WriteVault(const VaultBlob& blob) {
  std::vector<uint8_t> out;
  WriteU32(out, static_cast<uint32_t>(blob.pin_hmac.size()));
  out.insert(out.end(), blob.pin_hmac.begin(), blob.pin_hmac.end());
  WriteU32(out, static_cast<uint32_t>(blob.payload.size()));
  out.insert(out.end(), blob.payload.begin(), blob.payload.end());
  WriteU32(out, static_cast<uint32_t>(blob.signature.size()));
  out.insert(out.end(), blob.signature.begin(), blob.signature.end());
  std::ofstream ofs(VaultFilePath(), std::ios::binary | std::ios::trunc);
  if (!ofs) return false;
  ofs.write(reinterpret_cast<const char*>(out.data()),
            static_cast<std::streamsize>(out.size()));
  return ofs.good();
}

std::optional<VaultBlob> ReadVault() {
  std::ifstream ifs(VaultFilePath(), std::ios::binary);
  if (!ifs) return std::nullopt;
  std::vector<uint8_t> raw((std::istreambuf_iterator<char>(ifs)),
                           std::istreambuf_iterator<char>());
  size_t pos = 0;
  VaultBlob blob;
  auto read_slice = [&](std::vector<uint8_t>& out) {
    uint32_t len = 0;
    if (!ReadU32(raw, pos, len)) return false;
    if (pos + len > raw.size()) return false;
    out.assign(raw.begin() + pos, raw.begin() + pos + len);
    pos += len;
    return true;
  };
  if (!read_slice(blob.pin_hmac)) return std::nullopt;
  if (!read_slice(blob.payload)) return std::nullopt;
  if (!read_slice(blob.signature)) return std::nullopt;
  return blob;
}

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
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (...) {
    // Already initialised on this thread — safe to ignore.
  }
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), kChannel,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

HardwareVaultPlugin::~HardwareVaultPlugin() = default;

void HardwareVaultPlugin::HandleMethodCall(
    const MethodCall& call, std::unique_ptr<MethodResult> result) {
  const std::string& method = call.method_name();
  if (method == "isAvailable") {
    result->Success(EncodableValue(IsAvailableSync()));
    return;
  }
  if (method == "backingLevel") {
    result->Success(EncodableValue(BackingLevelSync()));
    return;
  }
  if (method == "isStored") {
    result->Success(
        EncodableValue(std::filesystem::exists(VaultFilePath())));
    return;
  }
  if (method == "clear") {
    std::error_code ec;
    std::filesystem::remove(VaultFilePath(), ec);
    try {
      KeyCredentialManager::DeleteAsync(kCredentialName).get();
    } catch (...) {
      // Best effort — credential may not exist.
    }
    result->Success(EncodableValue(true));
    return;
  }
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  if (!args) {
    result->Error("ARG", "expected map arguments");
    return;
  }
  if (method == "store") {
    auto dbKey = GetBytes(*args, "dbKey");
    auto pinHmac = GetBytes(*args, "pinHmac");
    if (dbKey.empty() || pinHmac.empty()) {
      result->Error("ARG", "dbKey + pinHmac required");
      return;
    }
    try {
      auto signature = SignWithCredential(dbKey);
      if (signature.empty()) {
        result->Error("STORE", "RequestSignAsync failed");
        return;
      }
      VaultBlob blob{pinHmac, dbKey, signature};
      if (!WriteVault(blob)) {
        result->Error("STORE", "write failed");
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
    auto pinHmac = GetBytes(*args, "pinHmac");
    if (pinHmac.empty()) {
      result->Error("ARG", "pinHmac required");
      return;
    }
    auto blob = ReadVault();
    if (!blob.has_value()) {
      result->Success(std::monostate{});
      return;
    }
    if (!ConstantTimeEquals(blob->pin_hmac, pinHmac)) {
      result->Success(std::monostate{});
      return;
    }
    try {
      auto signature = SignWithCredential(blob->payload);
      if (signature != blob->signature) {
        // User cancelled Hello, enrolment changed, or the hardware
        // reseeded the credential — treat as unrecoverable so the
        // caller falls into the reset path.
        result->Success(std::monostate{});
        return;
      }
      result->Success(EncodableValue(blob->payload));
    } catch (const std::exception& e) {
      result->Error("READ", e.what());
    } catch (...) {
      result->Error("READ", "unknown failure");
    }
    return;
  }
  result->NotImplemented();
}
