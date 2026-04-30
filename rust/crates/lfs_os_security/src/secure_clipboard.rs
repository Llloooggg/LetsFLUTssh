//! Platform-aware clipboard writer that opts the payload out of
//! cloud sync and OS clipboard history before it hits the system
//! pasteboard.
//!
//! Replaces the per-platform Swift / Cpp `ClipboardSecurePlugin`s
//! (macOS / iOS / Windows) with one Rust entry point. Linux uses
//! `arboard` for the basic write — there's no cloud-clipboard
//! default on X11 / Wayland to opt out of. Android keeps its
//! existing `ClipboardSecurePlugin.kt` MethodChannel because
//! `ClipDescription.EXTRA_IS_SENSITIVE` requires the
//! `ClipboardManager` Android API; the Dart wrapper short-
//! circuits to the channel before invoking this Rust function.
//!
//! Per-platform flag set the function applies in the same write
//! session:
//!
//! - **Windows** → register two custom clipboard formats
//!   (`CanIncludeInClipboardHistory`, `CanUploadToCloudClipboard`),
//!   each carrying a 4-byte `DWORD = 0` payload, alongside
//!   `CF_UNICODETEXT`. Win+V history skips it; Microsoft cloud
//!   clipboard refuses to upload.
//! - **macOS** → declare `org.nspasteboard.TransientType` and
//!   `org.nspasteboard.ConcealedType` on the same `NSPasteboardItem`
//!   as the string. Every nspasteboard.org-conforming clipboard
//!   manager (1Password, Maccy, Paste, Alfred, …) honours these.
//!   Universal Clipboard remains a residual leak — Apple ships no
//!   first-party opt-out.
//! - **iOS** → `UIPasteboard.setItems(...,
//!   options: [.localOnly: true])` plus a short
//!   `expirationDate` so a stale copy doesn't survive a reboot.
//!   `localOnly` disables Handoff sync for the write.
//! - **Linux** → `arboard::Clipboard::set_text` only. No cloud
//!   default on X11 / Wayland.
//!
//! Failures map to `Err(String)` so the Dart caller can log +
//! fall back to Flutter's stock `Clipboard.setData` if needed.

#[cfg(any(target_os = "ios", target_os = "macos"))]
use objc2::msg_send;
#[cfg(any(target_os = "ios", target_os = "macos"))]
use objc2_foundation::NSString;

/// Write `text` to the system clipboard with the per-platform
/// "do not sync / do not history" flags applied in the same
/// write session.
pub fn set_secure_text(text: &str) -> Result<(), String> {
    #[cfg(target_os = "linux")]
    {
        linux_set_text(text)
    }
    #[cfg(target_os = "macos")]
    {
        macos_set_secure_text(text)
    }
    #[cfg(target_os = "ios")]
    {
        ios_set_secure_text(text)
    }
    #[cfg(target_os = "windows")]
    {
        windows_set_secure_text(text)
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "ios",
        target_os = "windows"
    )))]
    {
        let _ = text;
        Err("set_secure_text: unsupported platform".to_string())
    }
}

// ── Linux ──────────────────────────────────────────────────────

#[cfg(target_os = "linux")]
fn linux_set_text(text: &str) -> Result<(), String> {
    use arboard::Clipboard;
    let mut cb = Clipboard::new().map_err(|e| format!("arboard new: {e}"))?;
    cb.set_text(text.to_string())
        .map_err(|e| format!("arboard set_text: {e}"))
}

// ── macOS ──────────────────────────────────────────────────────

#[cfg(target_os = "macos")]
fn macos_set_secure_text(text: &str) -> Result<(), String> {
    use objc2_app_kit::NSPasteboard;
    // SAFETY: every objc2 call here returns a managed Retained<T>
    // (autoreleased) or sends a documented Cocoa selector. No raw
    // pointer arithmetic; lifetimes scoped to the unsafe block.
    unsafe {
        let pb = NSPasteboard::generalPasteboard();
        let _: i64 = msg_send![&*pb, clearContents];

        // Declare all three types up front so a watcher can never
        // observe the string without the transient marker.
        let str_type = NSString::from_str("public.utf8-plain-text");
        let transient = NSString::from_str("org.nspasteboard.TransientType");
        let concealed = NSString::from_str("org.nspasteboard.ConcealedType");
        let types = objc2_foundation::NSArray::from_retained_slice(&[
            str_type.clone(),
            transient.clone(),
            concealed.clone(),
        ]);
        let _: i64 = msg_send![&*pb, declareTypes: &*types, owner: std::ptr::null_mut::<objc2::runtime::AnyObject>()];

        let body = NSString::from_str(text);
        let _: bool = msg_send![&*pb, setString: &*body, forType: &*str_type];

        // Empty NSData payloads — clipboard managers check for the
        // type's presence, not the bytes.
        let empty = objc2_foundation::NSData::new();
        let _: bool = msg_send![&*pb, setData: &*empty, forType: &*transient];
        let _: bool = msg_send![&*pb, setData: &*empty, forType: &*concealed];
    }
    Ok(())
}

// ── iOS ────────────────────────────────────────────────────────

#[cfg(target_os = "ios")]
fn ios_set_secure_text(text: &str) -> Result<(), String> {
    use objc2_ui_kit::UIPasteboard;
    use objc2_foundation::{NSArray, NSDictionary, NSDate, NSNumber};
    // SAFETY: UIPasteboard.setItems:options: is a standard public
    // selector. Lifetimes scoped to the unsafe block.
    unsafe {
        let pb = UIPasteboard::generalPasteboard();

        // Item dict: { "public.utf8-plain-text" : <body> }.
        let item_key = NSString::from_str("public.utf8-plain-text");
        let body = NSString::from_str(text);
        let item: objc2::rc::Retained<NSDictionary<NSString, objc2::runtime::AnyObject>> =
            NSDictionary::from_retained_objects(
                &[&*item_key],
                &[objc2::rc::Retained::cast_unchecked::<objc2::runtime::AnyObject>(body)],
            );
        let items = NSArray::from_retained_slice(&[item]);

        // Options: { LocalOnly: true, ExpirationDate: now+30s }.
        let local_only_key = NSString::from_str("UIPasteboardOptionLocalOnly");
        let expiration_key = NSString::from_str("UIPasteboardOptionExpirationDate");
        let yes: objc2::rc::Retained<NSNumber> = NSNumber::numberWithBool(true);
        let in_30s: objc2::rc::Retained<NSDate> =
            msg_send![NSDate::class(), dateWithTimeIntervalSinceNow: 30.0_f64];
        let opts: objc2::rc::Retained<NSDictionary<NSString, objc2::runtime::AnyObject>> =
            NSDictionary::from_retained_objects(
                &[&*local_only_key, &*expiration_key],
                &[
                    objc2::rc::Retained::cast_unchecked::<objc2::runtime::AnyObject>(yes),
                    objc2::rc::Retained::cast_unchecked::<objc2::runtime::AnyObject>(in_30s),
                ],
            );

        let _: () = msg_send![&*pb, setItems: &*items, options: &*opts];
    }
    Ok(())
}

// ── Windows ────────────────────────────────────────────────────

#[cfg(target_os = "windows")]
fn windows_set_secure_text(text: &str) -> Result<(), String> {
    // Reproduces `windows/runner/clipboard_secure_plugin.cpp`:
    // OpenClipboard → EmptyClipboard → SetClipboardData(CF_UNICODETEXT)
    // → register + write CanIncludeInClipboardHistory + CanUploadToCloudClipboard
    // (each carrying a single DWORD == 0) → CloseClipboard.
    use std::ffi::c_void;

    // ── Win32 FFI surface ────────────────────────────────────
    type HWND = *mut c_void;
    type HANDLE = *mut c_void;
    type HGLOBAL = *mut c_void;
    type DWORD = u32;
    type UINT = u32;
    type WCHAR = u16;
    type BOOL = i32;

    const CF_UNICODETEXT: UINT = 13;
    const GMEM_MOVEABLE: UINT = 0x0002;

    extern "system" {
        fn OpenClipboard(hWndNewOwner: HWND) -> BOOL;
        fn CloseClipboard() -> BOOL;
        fn EmptyClipboard() -> BOOL;
        fn SetClipboardData(uFormat: UINT, hMem: HANDLE) -> HANDLE;
        fn RegisterClipboardFormatW(lpszFormat: *const WCHAR) -> UINT;
        fn GlobalAlloc(uFlags: UINT, dwBytes: usize) -> HGLOBAL;
        fn GlobalLock(hMem: HGLOBAL) -> *mut c_void;
        fn GlobalUnlock(hMem: HGLOBAL) -> BOOL;
        fn GlobalFree(hMem: HGLOBAL) -> HGLOBAL;
    }

    fn write_format(format: UINT, src: &[u8]) -> bool {
        if format == 0 || src.is_empty() {
            return false;
        }
        // SAFETY: Win32 GlobalAlloc / GlobalLock / SetClipboardData
        // form a documented sequence. On success ownership of the
        // HGLOBAL transfers to the system; on any sub-step failure
        // we free the allocation here.
        unsafe {
            let mem = GlobalAlloc(GMEM_MOVEABLE, src.len());
            if mem.is_null() {
                return false;
            }
            let dst = GlobalLock(mem);
            if dst.is_null() {
                GlobalFree(mem);
                return false;
            }
            std::ptr::copy_nonoverlapping(src.as_ptr(), dst as *mut u8, src.len());
            GlobalUnlock(mem);
            if SetClipboardData(format, mem).is_null() {
                GlobalFree(mem);
                return false;
            }
            true
        }
    }

    // SAFETY: OpenClipboard / EmptyClipboard / CloseClipboard form
    // the documented session pattern. We always close.
    unsafe {
        if OpenClipboard(std::ptr::null_mut()) == 0 {
            return Err("OpenClipboard failed".to_string());
        }
        let mut wide: Vec<WCHAR> = text.encode_utf16().collect();
        wide.push(0); // NUL terminator for CF_UNICODETEXT
        let bytes_per_wchar = std::mem::size_of::<WCHAR>();
        let text_bytes_len = wide.len() * bytes_per_wchar;
        let text_bytes_slice =
            std::slice::from_raw_parts(wide.as_ptr() as *const u8, text_bytes_len);

        let mut ok = false;
        loop {
            if EmptyClipboard() == 0 {
                break;
            }
            if !write_format(CF_UNICODETEXT, text_bytes_slice) {
                break;
            }
            // Cloud / history opt-outs.
            let history_name = wide_string("CanIncludeInClipboardHistory");
            let cloud_name = wide_string("CanUploadToCloudClipboard");
            let history_fmt = RegisterClipboardFormatW(history_name.as_ptr());
            let cloud_fmt = RegisterClipboardFormatW(cloud_name.as_ptr());
            let deny: DWORD = 0;
            let deny_bytes = std::slice::from_raw_parts(
                &deny as *const DWORD as *const u8,
                std::mem::size_of::<DWORD>(),
            );
            if history_fmt != 0 {
                let _ = write_format(history_fmt, deny_bytes);
            }
            if cloud_fmt != 0 {
                let _ = write_format(cloud_fmt, deny_bytes);
            }
            ok = true;
            break;
        }

        CloseClipboard();
        if ok {
            Ok(())
        } else {
            Err("clipboard write session failed".to_string())
        }
    }
}

#[cfg(target_os = "windows")]
fn wide_string(s: &str) -> Vec<u16> {
    let mut v: Vec<u16> = s.encode_utf16().collect();
    v.push(0);
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn returns_error_or_success_without_panic() {
        // Linux CI hosts often don't have a display server attached;
        // arboard returns Err in that case and the test asserts only
        // "no panic". Same for the other platforms when their
        // pasteboard isn't reachable in test contexts.
        let _ = set_secure_text("hello");
    }
}
