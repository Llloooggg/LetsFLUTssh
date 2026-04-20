#include "clipboard_secure_plugin.h"

#include <windows.h>

#include <string>
#include <variant>

ClipboardSecurePlugin::ClipboardSecurePlugin(flutter::FlutterEngine* engine) {
  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), kChannel,
          &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const MethodCall& call, std::unique_ptr<MethodResult> result) {
        HandleMethodCall(call, std::move(result));
      });
}

ClipboardSecurePlugin::~ClipboardSecurePlugin() = default;

// UTF-8 → UTF-16. Empty input returns an empty wstring (valid, writes
// an empty clipboard which is what the wipe path does on Dart side).
static std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int needed = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (needed <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(needed), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                        static_cast<int>(utf8.size()), out.data(), needed);
  return out;
}

// Allocate an HGLOBAL holding `bytes` bytes copied from `src` and
// hand it to SetClipboardData under `format`. On failure, frees the
// allocation and returns false so the caller can abort the session.
static bool WriteFormat(UINT format, const void* src, size_t bytes) {
  HGLOBAL mem = ::GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!mem) return false;
  void* dst = ::GlobalLock(mem);
  if (!dst) {
    ::GlobalFree(mem);
    return false;
  }
  ::memcpy(dst, src, bytes);
  ::GlobalUnlock(mem);
  if (!::SetClipboardData(format, mem)) {
    ::GlobalFree(mem);
    return false;
  }
  // SetClipboardData transfers ownership — the system frees it.
  return true;
}

static bool WriteSecureText(const std::wstring& text) {
  if (!::OpenClipboard(nullptr)) return false;
  bool ok = false;
  do {
    if (!::EmptyClipboard()) break;

    // Text payload — include the NUL terminator so paste consumers
    // that rely on C-string semantics stay happy.
    size_t bytes = (text.size() + 1) * sizeof(wchar_t);
    if (!WriteFormat(CF_UNICODETEXT, text.c_str(), bytes)) break;

    // Cloud / history opt-out formats. Each is a 4-byte DWORD == 0.
    // RegisterClipboardFormatW returns the same ID across the OS, so
    // the history / cloud consumers on the other end of the bus see
    // the flag.
    UINT history_fmt = ::RegisterClipboardFormatW(
        L"CanIncludeInClipboardHistory");
    UINT cloud_fmt = ::RegisterClipboardFormatW(
        L"CanUploadToCloudClipboard");
    DWORD deny = 0;
    if (history_fmt != 0) {
      WriteFormat(history_fmt, &deny, sizeof(deny));
    }
    if (cloud_fmt != 0) {
      WriteFormat(cloud_fmt, &deny, sizeof(deny));
    }
    ok = true;
  } while (false);
  ::CloseClipboard();
  return ok;
}

void ClipboardSecurePlugin::HandleMethodCall(
    const MethodCall& call, std::unique_ptr<MethodResult> result) {
  if (call.method_name() != "setSecureText") {
    result->NotImplemented();
    return;
  }
  const auto* args =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (!args) {
    result->Error("BAD_ARGS", "setSecureText requires {text: String}");
    return;
  }
  auto it = args->find(flutter::EncodableValue("text"));
  if (it == args->end() ||
      !std::holds_alternative<std::string>(it->second)) {
    result->Error("BAD_ARGS", "setSecureText requires {text: String}");
    return;
  }
  const auto& utf8 = std::get<std::string>(it->second);
  std::wstring wide = Utf8ToWide(utf8);
  if (!WriteSecureText(wide)) {
    result->Error("CLIPBOARD_FAILED",
                  "OpenClipboard / SetClipboardData failed");
    return;
  }
  result->Success(flutter::EncodableValue(true));
}
