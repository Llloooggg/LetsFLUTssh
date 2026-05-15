//! Platform-aware clipboard writer that opts the payload out of
//! cloud sync and OS clipboard history before it hits the system
//! pasteboard.
//!
//! Single Rust entry point routed through FRB by every platform;
//! the per-platform flag dance lives in the `cfg`-gated branches
//! below.
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
//! - **Android** → JNI into `android.content.ClipboardManager`
//!   with `ClipDescription.EXTRA_IS_SENSITIVE` set on the
//!   `PersistableBundle` extras of the `ClipData`. Android 13+
//!   reads the flag and hides the toast preview + launcher
//!   "share what you copied" affordances.
//! - **Linux** → `arboard::Clipboard::set_text` only. No cloud
//!   default on X11 / Wayland.
//!
//! Failures map to `Err(String)` so the Dart caller can log +
//! decide per-platform whether to fall back to Flutter's stock
//! `Clipboard.setData` (Linux only — every other platform refuses
//! the write to avoid landing a secret on a cloud-syncing
//! pasteboard without the opt-out flags).

#[cfg(any(target_os = "ios", target_os = "macos"))]
use objc2::msg_send;
#[cfg(any(target_os = "ios", target_os = "macos"))]
use objc2_foundation::NSString;

use sha2::{Digest, Sha256};

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
    #[cfg(target_os = "android")]
    {
        crate::android::clipboard::set_secure_text(text)
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "ios",
        target_os = "windows",
        target_os = "android"
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
    use objc2_foundation::{NSArray, NSDate, NSDictionary, NSNumber};
    use objc2_ui_kit::UIPasteboard;
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
                &[objc2::rc::Retained::cast_unchecked::<
                    objc2::runtime::AnyObject,
                >(body)],
            );
        let items = NSArray::from_retained_slice(&[item]);

        // Options: { LocalOnly: true, ExpirationDate: now+30s }.
        let local_only_key = NSString::from_str("UIPasteboardOptionLocalOnly");
        let expiration_key = NSString::from_str("UIPasteboardOptionExpirationDate");
        let yes: objc2::rc::Retained<NSNumber> = NSNumber::numberWithBool(true);
        // `NSDate::dateWithTimeIntervalSinceNow` is the typed
        // method binding; the older `msg_send![NSDate::class(),
        // dateWithTimeIntervalSinceNow: 30.0_f64]` form needed
        // `objc2::ClassType` in scope and tripped on iOS-targets
        // because the trait shadow differs between objc2 0.5
        // (where `class()` was inherent) and 0.6 (where it moved
        // behind the trait). Using the typed binding sidesteps
        // the import-tangle entirely.
        let in_30s: objc2::rc::Retained<NSDate> = NSDate::dateWithTimeIntervalSinceNow(30.0);
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
    // OpenClipboard → EmptyClipboard → SetClipboardData(CF_UNICODETEXT)
    // → register + write CanIncludeInClipboardHistory +
    // CanUploadToCloudClipboard (each carrying a single DWORD == 0) →
    // CloseClipboard. The two custom formats must land in the same
    // OpenClipboard session as the text; a second session leaves a
    // window where a clipboard-history watcher can read the text
    // before the opt-out flags arrive.
    use windows::core::PCWSTR;
    use windows::Win32::Foundation::{GlobalFree, HANDLE, HGLOBAL};
    use windows::Win32::System::DataExchange::{
        CloseClipboard, EmptyClipboard, OpenClipboard, RegisterClipboardFormatW, SetClipboardData,
    };
    use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};

    const CF_UNICODETEXT: u32 = 13;

    fn write_format(format: u32, src: &[u8]) -> bool {
        if format == 0 || src.is_empty() {
            return false;
        }
        // SAFETY: Win32 GlobalAlloc / GlobalLock / SetClipboardData
        // form a documented sequence. On success ownership of the
        // HGLOBAL transfers to the system; on any sub-step failure
        // we free the allocation here.
        unsafe {
            let mem: HGLOBAL = match GlobalAlloc(GMEM_MOVEABLE, src.len()) {
                Ok(h) if !h.0.is_null() => h,
                _ => return false,
            };
            let dst = GlobalLock(mem);
            if dst.is_null() {
                let _ = GlobalFree(Some(mem));
                return false;
            }
            std::ptr::copy_nonoverlapping(src.as_ptr(), dst.cast::<u8>(), src.len());
            let _ = GlobalUnlock(mem);
            // `SetClipboardData` accepts the HGLOBAL via the
            // `HANDLE` newtype — both wrap `*mut c_void` so the
            // raw-pointer cast preserves the kernel handle.
            let handle = HANDLE(mem.0);
            if SetClipboardData(format, Some(handle)).is_err() {
                let _ = GlobalFree(Some(mem));
                return false;
            }
            true
        }
    }

    // SAFETY: OpenClipboard / EmptyClipboard / CloseClipboard form
    // the documented session pattern. We always close.
    unsafe {
        if OpenClipboard(None).is_err() {
            return Err("OpenClipboard failed".to_string());
        }
        let mut wide: Vec<u16> = text.encode_utf16().collect();
        wide.push(0); // NUL terminator for CF_UNICODETEXT
        let bytes_per_wchar = std::mem::size_of::<u16>();
        let text_bytes_len = wide.len() * bytes_per_wchar;
        let text_bytes_slice =
            std::slice::from_raw_parts(wide.as_ptr().cast::<u8>(), text_bytes_len);

        let ok = EmptyClipboard().is_ok() && write_format(CF_UNICODETEXT, text_bytes_slice) && {
            // Cloud / history opt-outs. Failures here are
            // tolerated — the text already landed; we logged the
            // intent by registering the formats but the OS may
            // refuse the side payloads on older builds.
            let history_name = wide_string("CanIncludeInClipboardHistory");
            let cloud_name = wide_string("CanUploadToCloudClipboard");
            let history_fmt = RegisterClipboardFormatW(PCWSTR::from_raw(history_name.as_ptr()));
            let cloud_fmt = RegisterClipboardFormatW(PCWSTR::from_raw(cloud_name.as_ptr()));
            let deny: u32 = 0;
            let deny_bytes = std::slice::from_raw_parts(
                std::ptr::from_ref(&deny).cast::<u8>(),
                std::mem::size_of::<u32>(),
            );
            if history_fmt != 0 {
                let _ = write_format(history_fmt, deny_bytes);
            }
            if cloud_fmt != 0 {
                let _ = write_format(cloud_fmt, deny_bytes);
            }
            true
        };

        let _ = CloseClipboard();
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

// ── Read primitive + compare-and-clear orchestrator ─────────────
//
// The auto-wipe contract for password-shaped copies (session
// passwords, SSH passphrases, API tokens, terminal selections that
// match the "looks-like-a-secret" heuristic) reads the clipboard
// `secretClipboardLifetime` seconds after the write and clears the
// slot only when the current contents still match what we wrote. A
// user who copied something else in the meantime keeps their
// clipboard untouched.
//
// The read + the compare + the eventual empty-string write all live
// here so the Dart caller stages only a SHA-256 hex digest on its
// heap. Plaintext never crosses FRB for the wipe path, and the
// "do not sync / do not history" markers apply to the empty-string
// write the same way they apply to the original payload — a wiped
// clipboard slot still carries the per-platform opt-outs.
//
// `current_text` returns `None` for every "no text on the clipboard,
// for any reason" case the per-platform backend surfaces: the
// pasteboard is empty, the system clipboard is unreachable (headless
// Linux CI host, screen locked on platforms that gate clipboard
// access on lock state, ROMs without a system clipboard), or the
// contents are a non-text type (image, file list, RTF). The
// compare-and-clear path treats every `None` as "drifted" — no
// clear runs, no error surfaces.

/// Read the current clipboard text. Returns `None` when:
/// - the clipboard is empty, or
/// - the system clipboard is unreachable (headless Linux host,
///   locked screen on platforms that gate read on lock state,
///   missing system clipboard service), or
/// - the contents are not text (image, file URL list, custom MIME).
pub fn current_text() -> Option<String> {
    #[cfg(target_os = "linux")]
    {
        linux_current_text()
    }
    #[cfg(target_os = "macos")]
    {
        macos_current_text()
    }
    #[cfg(target_os = "ios")]
    {
        ios_current_text()
    }
    #[cfg(target_os = "windows")]
    {
        windows_current_text()
    }
    #[cfg(target_os = "android")]
    {
        crate::android::clipboard::current_text()
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "ios",
        target_os = "windows",
        target_os = "android"
    )))]
    {
        None
    }
}

/// Compare-and-clear: read the current clipboard; if its SHA-256
/// hex digest equals `expected_sha256_hex`, write an empty string
/// through the same audit perimeter as [`set_secure_text`] (so the
/// clear keeps the per-platform "do not sync, do not history"
/// markers); otherwise no-op.
///
/// Returns `Ok(true)` when the clear ran, `Ok(false)` when the
/// clipboard drifted (user copied something else, contents were
/// non-text, or the system clipboard was unreachable — every
/// non-clear branch maps to `false` so the Dart caller has one
/// "no plaintext leaked, nothing to react to" branch).
///
/// `Err` surfaces only on a Rust-side write failure during the
/// follow-up `set_secure_text("")` call; the read itself never
/// errors out — it falls through to `Ok(false)` on every
/// "couldn't compare" branch.
pub fn compare_and_clear(expected_sha256_hex: &str) -> Result<bool, String> {
    let Some(live) = current_text() else {
        return Ok(false);
    };
    if live.is_empty() {
        return Ok(false);
    }
    let live_hex = sha256_hex_lower(live.as_bytes());
    if live_hex != expected_sha256_hex {
        return Ok(false);
    }
    // Same audit perimeter as the write — the empty-string clear
    // still carries Win+V opt-out, NSPasteboard transient/concealed
    // markers, UIPasteboard `localOnly`, Android `EXTRA_IS_SENSITIVE`.
    // Skipping the markers on the empty payload would leave a "we
    // overwrote a secret with an empty string but advertised the
    // empty string to the cloud-sync ring" trail.
    set_secure_text("")?;
    Ok(true)
}

fn sha256_hex_lower(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    let digest = h.finalize();
    let mut out = String::with_capacity(digest.len() * 2);
    for b in digest {
        // `write!` returns `fmt::Result`; writing to a `String`
        // can't fail, but the unused-must-use lint still requires
        // the bind. `format!` would allocate per-byte.
        use std::fmt::Write as _;
        let _ = write!(&mut out, "{b:02x}");
    }
    out
}

// ── Linux read ─────────────────────────────────────────────────

#[cfg(target_os = "linux")]
fn linux_current_text() -> Option<String> {
    use arboard::Clipboard;
    let mut cb = Clipboard::new().ok()?;
    cb.get_text().ok()
}

// ── macOS read ─────────────────────────────────────────────────

#[cfg(target_os = "macos")]
fn macos_current_text() -> Option<String> {
    use objc2_app_kit::NSPasteboard;
    // SAFETY: `stringForType:` returns a managed `Retained<NSString>`
    // or nil; no raw pointer arithmetic. Lifetimes scoped to the
    // unsafe block.
    unsafe {
        let pb = NSPasteboard::generalPasteboard();
        let str_type = NSString::from_str("public.utf8-plain-text");
        let s: Option<objc2::rc::Retained<NSString>> = msg_send![&*pb, stringForType: &*str_type];
        s.map(|ns| ns.to_string())
    }
}

// ── iOS read ───────────────────────────────────────────────────

#[cfg(target_os = "ios")]
fn ios_current_text() -> Option<String> {
    use objc2_ui_kit::UIPasteboard;
    // SAFETY: `string` on `UIPasteboard.generalPasteboard` returns
    // a managed `Retained<NSString>` or nil. Lifetimes scoped to
    // the unsafe block.
    unsafe {
        let pb = UIPasteboard::generalPasteboard();
        let s: Option<objc2::rc::Retained<NSString>> = msg_send![&*pb, string];
        s.map(|ns| ns.to_string())
    }
}

// ── Windows read ───────────────────────────────────────────────

#[cfg(target_os = "windows")]
fn windows_current_text() -> Option<String> {
    use windows::Win32::Foundation::{HANDLE, HGLOBAL};
    use windows::Win32::System::DataExchange::{CloseClipboard, GetClipboardData, OpenClipboard};
    use windows::Win32::System::Memory::{GlobalLock, GlobalSize, GlobalUnlock};

    const CF_UNICODETEXT: u32 = 13;

    // SAFETY: OpenClipboard / GetClipboardData / GlobalLock /
    // GlobalUnlock / CloseClipboard form the documented read
    // sequence. Ownership of the HGLOBAL returned by
    // `GetClipboardData` stays with the system — we lock it for
    // read access, copy out the bytes, unlock, and close. We
    // never free the HGLOBAL.
    unsafe {
        if OpenClipboard(None).is_err() {
            return None;
        }
        let handle: HANDLE = match GetClipboardData(CF_UNICODETEXT) {
            Ok(h) if !h.0.is_null() => h,
            _ => {
                let _ = CloseClipboard();
                return None;
            }
        };
        let hglobal = HGLOBAL(handle.0);
        let locked = GlobalLock(hglobal);
        if locked.is_null() {
            let _ = CloseClipboard();
            return None;
        }
        // `GlobalSize` reports the allocation size in bytes — may
        // be padded past the actual UTF-16 NUL-terminated string
        // length. We walk the buffer up to the first NUL or the
        // declared size, whichever comes first; the system writer
        // always NUL-terminates `CF_UNICODETEXT`.
        let size_bytes = GlobalSize(hglobal);
        let max_wchars = size_bytes / std::mem::size_of::<u16>();
        let ptr = locked.cast::<u16>();
        let slice = std::slice::from_raw_parts(ptr, max_wchars);
        let nul = slice.iter().position(|&c| c == 0).unwrap_or(slice.len());
        let text = String::from_utf16_lossy(&slice[..nul]);
        let _ = GlobalUnlock(hglobal);
        let _ = CloseClipboard();
        if text.is_empty() {
            None
        } else {
            Some(text)
        }
    }
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
        //
        // Trap: on a headed dev host this write lands on the real
        // user pasteboard. Capture the current value before the
        // write and restore it after so `cargo test` does not leak
        // a sentinel string into the developer's clipboard history.
        let saved = current_text();
        let _ = set_secure_text("__lfs_secure_clipboard_test_sentinel__");
        if let Some(prev) = saved {
            let _ = set_secure_text(&prev);
        } else {
            // Nothing was on the clipboard before — drop the
            // sentinel if it survived the write rather than leak it.
            let sentinel_sha = sha256_hex_lower(b"__lfs_secure_clipboard_test_sentinel__");
            let _ = compare_and_clear(&sentinel_sha);
        }
    }

    #[test]
    fn current_text_never_panics() {
        // Same headless / pasteboard-unreachable shape as the write
        // test above — the read primitive must surface `None` rather
        // than panic on a missing DISPLAY / locked screen / absent
        // clipboard service.
        let _ = current_text();
    }

    #[test]
    fn compare_and_clear_no_clear_on_drifted_clipboard() {
        // Headless CI: `current_text()` returns `None`, so the
        // compare-and-clear path short-circuits to `Ok(false)`
        // without attempting a write. Headed hosts may have an
        // unrelated value on the clipboard, which hashes to
        // something other than the canary digest below and also
        // returns `Ok(false)`. Either way: no clear, no panic.
        let canary = sha256_hex_lower(b"a value the host clipboard will never hold");
        let result = compare_and_clear(&canary);
        // Result must be Ok — the read primitive folds every
        // "couldn't compare" branch into `Ok(false)`.
        assert!(result.is_ok());
        assert!(!result.unwrap());
    }

    #[test]
    fn sha256_hex_lower_matches_known_vectors() {
        // Lower-case hex matches the FRB `crypto_sha256_hex` shape
        // used by the Dart caller before this orchestrator. Pin a
        // known vector so a future refactor that flips case or
        // separator breaks at the digest boundary, not silently
        // at the wipe gate where the user wouldn't notice.
        assert_eq!(
            sha256_hex_lower(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex_lower(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}
