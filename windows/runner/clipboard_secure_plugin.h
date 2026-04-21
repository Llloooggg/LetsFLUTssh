#pragma once

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

/// Clipboard writer that opts the payload out of Windows 10/11
/// clipboard history and Microsoft cloud sync.
///
/// Windows 10 1809 added the Win+V clipboard-history ring. Newer
/// builds optionally sync that ring to Microsoft's servers and to
/// other devices signed into the same account ("Clipboard
/// synchronization"). A copied password or SSH passphrase lands in
/// both paths by default — the history ring persists it locally
/// until it rolls over, and cloud sync exfiltrates it off-device.
///
/// The opt-out is two undocumented-but-stable registered clipboard
/// formats — `CanIncludeInClipboardHistory` and
/// `CanUploadToCloudClipboard`. Each is a `DWORD` set to 0, written
/// in the same `OpenClipboard` session as the text. Microsoft's own
/// Password Manager and Edge "Copy without formatting" flow use the
/// same mechanism; third-party password managers (1Password,
/// Bitwarden) do too.
///
/// The plugin owns the whole clipboard write: it opens the
/// clipboard, empties it, writes `CF_UNICODETEXT` with our bytes,
/// writes the two opt-out DWORDs, and closes. Going via Flutter's
/// stock `Clipboard.setData` would leave the opt-out write in a
/// separate `OpenClipboard` session, which means the brief window
/// between the two sessions lets clipboard-history watchers scoop
/// the text before the flag lands.
class ClipboardSecurePlugin {
 public:
  static constexpr const char* kChannel = "com.letsflutssh/clipboard_secure";

  explicit ClipboardSecurePlugin(flutter::FlutterEngine* engine);
  ~ClipboardSecurePlugin();

  ClipboardSecurePlugin(const ClipboardSecurePlugin&) = delete;
  ClipboardSecurePlugin& operator=(const ClipboardSecurePlugin&) = delete;

 private:
  using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
  using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  void HandleMethodCall(const MethodCall& call,
                        std::unique_ptr<MethodResult> result);
};
