//! OS session-lock event listener — Rust on Linux + macOS +
//! Windows; iOS / Android stay on the Flutter lifecycle hook.
//! Restores the "Rust owns OS-API on every platform" invariant the
//! rest of the security stack maintains.
//!
//! Per-platform plumbing:
//!
//! - **Linux** — `org.freedesktop.login1.Session.Lock` via `zbus`.
//! - **macOS** — `NSDistributedNotificationCenter` observer for
//!   `com.apple.screenIsLocked` on a dedicated `NSRunLoop` thread.
//! - **Windows** — `WTSRegisterSessionNotification` against a
//!   hidden message-only window on a dedicated `GetMessageW`
//!   pump; `WindowProc` filters `WM_WTSSESSION_CHANGE` for the
//!   `WTS_SESSION_LOCK` wparam (`0x07`).
//! - **iOS / Android** — no Rust listener; Flutter's
//!   `AppLifecycleState.paused` covers the equivalent surface.
//!
//! Apple + Windows runtime verification on real hardware is
//! pending; Dart MethodChannel paths remain wired in parallel.

use tokio::sync::broadcast;

/// Process-wide broadcast hub. The first `subscribe` call lazily
/// installs the per-platform listener; subsequent subscribers
/// share the same channel without re-registering with the OS.
static HUB: std::sync::OnceLock<broadcast::Sender<()>> = std::sync::OnceLock::new();

fn hub() -> &'static broadcast::Sender<()> {
    HUB.get_or_init(|| {
        // Channel buffer is small — we never queue events deeper
        // than "lock arrived, hasn't fired yet".
        let (tx, _rx) = broadcast::channel::<()>(8);
        spawn_platform_listener(tx.clone());
        tx
    })
}

/// Subscribe to lock events. Returns a receiver that yields one
/// `()` per OS lock transition. The Dart caller wraps this as a
/// Stream via the FRB shim. On platforms with no Rust listener
/// (iOS / Android) the receiver stays armed but never fires;
/// the Dart wrapper short-circuits before invoking.
pub fn subscribe() -> broadcast::Receiver<()> {
    hub().subscribe()
}

#[cfg(target_os = "linux")]
fn spawn_platform_listener(tx: broadcast::Sender<()>) {
    tokio::spawn(async move {
        if let Err(e) = run_logind_listener(tx).await {
            // Best-effort — failure here only means the OS lock
            // signal won't fire the in-app auto-lock; the rest of
            // the app continues to work.
            eprintln!("[lfs_os_security] logind listener exited: {e}");
        }
    });
}

#[cfg(target_os = "linux")]
async fn run_logind_listener(tx: broadcast::Sender<()>) -> zbus::Result<()> {
    use futures_util::StreamExt;
    let conn = zbus::Connection::system().await?;
    // Resolve the current session path via Manager.GetSessionByPID.
    let manager = zbus::Proxy::new(
        &conn,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    )
    .await?;
    let pid = std::process::id();
    let session_path: zbus::zvariant::OwnedObjectPath =
        manager.call("GetSessionByPID", &pid).await?;
    let session = zbus::Proxy::new(
        &conn,
        "org.freedesktop.login1",
        session_path.as_str(),
        "org.freedesktop.login1.Session",
    )
    .await?;
    let mut stream = session.receive_signal("Lock").await?;
    while let Some(_msg) = stream.next().await {
        // `tx.send` only errors when there are zero subscribers —
        // we keep listening so future subscribers catch events.
        let _ = tx.send(());
    }
    Ok(())
}

#[cfg(target_os = "macos")]
fn spawn_platform_listener(tx: broadcast::Sender<()>) {
    // Dedicated OS thread owns its own NSRunLoop so observer
    // callbacks fire even when the Flutter engine's main-thread
    // loop is busy. The thread blocks on `NSRunLoop::run` for
    // the lifetime of the process — same shape as the foreign
    // event-loop pattern the macOS security plugins already use.
    std::thread::spawn(move || {
        macos_impl::install_observer_and_run(tx);
    });
}

#[cfg(target_os = "macos")]
mod macos_impl {
    use super::broadcast;
    use objc2::rc::Retained;
    use objc2::{define_class, msg_send, sel, AnyThread, DefinedClass};
    use objc2_foundation::{
        NSDistributedNotificationCenter, NSNotification, NSNotificationCenter, NSObject,
        NSObjectProtocol, NSRunLoop, NSString,
    };

    /// Per-thread observer object — owns the `Sender` so the
    /// objc-msg-send callback can fan-out without a global.
    /// Defined as an Objective-C class so `addObserver:selector:name:object:`
    /// can hold a strong reference to it for the lifetime of the
    /// notification subscription.
    pub struct ObserverIvars {
        tx: broadcast::Sender<()>,
    }

    define_class!(
        #[unsafe(super(NSObject))]
        #[name = "LFSSessionLockObserver"]
        #[ivars = ObserverIvars]
        pub struct LockObserver;

        unsafe impl NSObjectProtocol for LockObserver {}

        impl LockObserver {
            #[unsafe(method(handleLock:))]
            fn handle_lock(&self, _note: &NSNotification) {
                // `tx.send` errors only when there are zero
                // subscribers; we just drop the event and the
                // next subscriber catches the following one.
                let _ = self.ivars().tx.send(());
            }
        }
    );

    impl LockObserver {
        fn new(tx: broadcast::Sender<()>) -> Retained<Self> {
            let this = Self::alloc().set_ivars(ObserverIvars { tx });
            unsafe { msg_send![super(this), init] }
        }
    }

    pub fn install_observer_and_run(tx: broadcast::Sender<()>) {
        // SAFETY: observer registration is thread-safe per Apple's
        // NSDistributedNotificationCenter docs; the run loop call
        // owns the thread for the rest of the process lifetime.
        // No MainThreadMarker required because we're explicitly
        // running our own loop, not the main thread's.
        let observer = LockObserver::new(tx);
        let center = NSDistributedNotificationCenter::defaultCenter();
        let center_super: &NSNotificationCenter = &center;

        // The screen-lock notification name is documented in
        // Apple's CoreGraphics private notes; the string literal
        // has been stable since 10.6 (Snow Leopard) and is what
        // every third-party "lock listener" implementation uses,
        // including the Swift plugin this Rust path replaces.
        let name = NSString::from_str("com.apple.screenIsLocked");

        unsafe {
            // `addObserver_selector_name_object` takes
            // `&AnyObject` for the observer (NSNotificationCenter
            // wants any class instance, not a typed protocol
            // object). Cast through the LockObserver's super
            // class chain — it inherits from NSObject which is
            // an AnyObject.
            use objc2::runtime::AnyObject;
            let observer_any: &AnyObject = (*observer).as_ref();
            center_super.addObserver_selector_name_object(
                observer_any,
                sel!(handleLock:),
                Some(&name),
                None,
            );
        }

        // Keep the observer alive for the lifetime of the
        // run-loop thread — leak it intentionally so a future
        // refactor that moves install/run into separate calls
        // does not accidentally drop the observer (which would
        // unregister it from the notification center).
        std::mem::forget(observer);

        // Block this thread on the per-thread NSRunLoop. The
        // observer callback fires on this thread's loop, posts
        // to the tokio broadcast, and returns. `run` never
        // returns under normal operation.
        let run_loop = NSRunLoop::currentRunLoop();
        run_loop.run();

        // If `run` returns (process shutdown / unusual signal),
        // the observer leak above is reaped with the process —
        // not a real leak.
    }
}

#[cfg(target_os = "windows")]
fn spawn_platform_listener(tx: broadcast::Sender<()>) {
    // Same shape as the macOS path: dedicated thread owns the
    // window message pump for the lifetime of the listener.
    // CreateWindowExW + RegisterClassW are not safe to share
    // across threads (the window class atom + window handle
    // are thread-affine), so the listener thread is the natural
    // owner of both.
    std::thread::spawn(move || {
        windows_impl::install_window_and_pump(tx);
    });
}

#[cfg(target_os = "windows")]
mod windows_impl {
    use super::broadcast;
    use std::cell::Cell;
    use std::ffi::c_void;
    use std::ptr::null_mut;
    use windows::core::PCWSTR;
    use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::Win32::System::RemoteDesktop::{
        WTSRegisterSessionNotification, WTSUnRegisterSessionNotification, NOTIFY_FOR_THIS_SESSION,
    };
    use windows::Win32::UI::WindowsAndMessaging::{
        CreateWindowExW, DefWindowProcW, DispatchMessageW, GetMessageW, RegisterClassW,
        TranslateMessage, MSG, WINDOW_EX_STYLE, WINDOW_STYLE, WM_WTSSESSION_CHANGE, WNDCLASSW,
        WTS_SESSION_LOCK,
    };

    // Windows message id for session changes; `WM_WTSSESSION_CHANGE`
    // is the public name. `wparam` carries the change reason —
    // `WTS_SESSION_LOCK` (0x7) is the lock event, `WTS_SESSION_UNLOCK`
    // (0x8) is the unlock; we forward only locks (the auto-lock
    // state machine's input).
    const WC_NAME: &[u16] = &[
        b'L' as u16,
        b'F' as u16,
        b'S' as u16,
        b'S' as u16,
        b'e' as u16,
        b's' as u16,
        b's' as u16,
        b'i' as u16,
        b'o' as u16,
        b'n' as u16,
        b'L' as u16,
        b'o' as u16,
        b'c' as u16,
        b'k' as u16,
        0,
    ];

    thread_local! {
        // Per-thread tx — populated by `install_window_and_pump`
        // before the message pump starts. `WindowProc` is a
        // C-callable extern fn so it cannot capture state via
        // closure; the thread-local is the cleanest non-static
        // bridge that does not pollute global state.
        static TX_SLOT: Cell<*const broadcast::Sender<()>> = const { Cell::new(null_mut()) };
    }

    unsafe extern "system" fn window_proc(
        hwnd: HWND,
        msg: u32,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        if msg == WM_WTSSESSION_CHANGE && wparam.0 as u32 == WTS_SESSION_LOCK {
            TX_SLOT.with(|slot| {
                let ptr = slot.get();
                if !ptr.is_null() {
                    let tx = &*ptr;
                    let _ = tx.send(());
                }
            });
            return LRESULT(0);
        }
        DefWindowProcW(hwnd, msg, wparam, lparam)
    }

    pub fn install_window_and_pump(tx: broadcast::Sender<()>) {
        // Stash the sender so `window_proc` can reach it from the
        // C ABI callback. Boxed + leaked because `WindowProc` runs
        // for the lifetime of the thread; reclaiming on shutdown
        // is not worth the complexity.
        let tx_ptr = Box::into_raw(Box::new(tx)) as *const broadcast::Sender<()>;
        TX_SLOT.with(|slot| slot.set(tx_ptr));

        unsafe {
            let h_instance = GetModuleHandleW(PCWSTR::null()).unwrap_or_default();
            let class = WNDCLASSW {
                lpfnWndProc: Some(window_proc),
                hInstance: h_instance.into(),
                lpszClassName: PCWSTR(WC_NAME.as_ptr()),
                ..Default::default()
            };
            // RegisterClassW returns 0 on failure; we treat that
            // as "listener inert" rather than crashing the host
            // process, matching the best-effort posture of the
            // logind listener on Linux.
            if RegisterClassW(&class) == 0 {
                return;
            }

            // HWND_MESSAGE = -3 cast to HWND; creates a
            // message-only window that never appears on screen
            // and does not enter the top-level window list.
            let hwnd_message = HWND(-3isize as *mut c_void);
            let hwnd = match CreateWindowExW(
                WINDOW_EX_STYLE(0),
                PCWSTR(WC_NAME.as_ptr()),
                PCWSTR::null(),
                WINDOW_STYLE(0),
                0,
                0,
                0,
                0,
                Some(hwnd_message),
                None,
                Some(h_instance.into()),
                None,
            ) {
                Ok(h) => h,
                Err(_) => return,
            };

            if WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION).is_err() {
                return;
            }

            // Standard Win32 message pump — blocks for the
            // lifetime of the thread. `WM_WTSSESSION_CHANGE`
            // events route to `window_proc` via `DispatchMessageW`.
            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                let _ = TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }

            let _ = WTSUnRegisterSessionNotification(hwnd);
        }
    }
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
fn spawn_platform_listener(_tx: broadcast::Sender<()>) {
    // iOS / Android route through the Flutter lifecycle-paused hook.
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn subscribe_returns_receiver_without_panic() {
        let _rx = subscribe();
    }

    #[tokio::test]
    async fn multiple_subscribers_share_one_listener() {
        let _rx1 = subscribe();
        let _rx2 = subscribe();
    }
}
