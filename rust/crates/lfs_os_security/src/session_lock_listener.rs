//! OS session-lock event listener.
//!
//! Replaces the Linux native plugin's logind subscription with a
//! Rust zbus listener. macOS + Windows keep their existing
//! native plugins because both platforms' lock subscriptions are
//! window/observer-bound to plumbing the Flutter engine already
//! provides:
//!
//! - **Windows** — `WTSRegisterSessionNotification` is HWND-scoped;
//!   the main `flutter::FlutterViewController` window is the
//!   natural pump for `WM_WTSSESSION_CHANGE`.
//! - **macOS** — `DistributedNotificationCenter` observers need
//!   a Cocoa run loop; the Flutter app's main thread already
//!   carries one. Re-registering on a Rust-spawned thread would
//!   duplicate that loop.
//!
//! On Linux the existing native plugin used the Dart `dbus`
//! package over the system bus; that path migrates here so the
//! `dbus` Dart dep can drop entirely (already removed by the
//! `fprintd_client` migration). iOS / Android use Flutter's
//! lifecycle-paused hook instead — no Rust listener wired.

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
/// (everything except Linux today) the receiver stays armed but
/// never fires; the Dart wrapper short-circuits before invoking.
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

#[cfg(not(target_os = "linux"))]
fn spawn_platform_listener(_tx: broadcast::Sender<()>) {
    // Windows / macOS keep their existing native plugins; iOS /
    // Android route through the Flutter lifecycle-paused hook.
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
