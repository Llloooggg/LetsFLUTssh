//! FRB adapter for `lfs_core::logger::file_sink`.
//!
//! Dart's `AppLogger` formats + sanitises each line and broadcasts
//! it to the live viewer; the on-disk file lives Rust-side under
//! `lfs_core::logger::file_sink`. This shim is the one-way bridge:
//! every `dart:io File`/`Directory` operation Dart used to run
//! against `<app_support>/logs/letsflutssh.log` now routes through
//! one of the functions below.
//!
//! Sync vs async split: the hot path (`logger_append_line`,
//! `logger_append_critical`, `logger_flush`, `logger_close_sink`)
//! is one syscall per call and stays sync so the live writer does
//! not pay an FRB-runtime hop per log line. The slower
//! lifecycle / browse ops (`logger_open_sink`, `logger_read_all`,
//! `logger_rotate_if_needed`, `logger_clear_all`) are async +
//! `spawn_blocking` because they touch directory create / stat /
//! rename / multi-file delete, all of which can wedge the Dart
//! event loop on slow disks.

/// Open the routine-write sink rooted under [`app_support_dir`].
/// Resolves to `<app_support_dir>/logs/letsflutssh.log`, creates
/// the `logs/` parent directory if absent, opens the file in
/// append mode, hardens to `0600` on POSIX. Returns the resolved
/// log-path string.
///
/// Idempotent — calling twice with the same directory keeps the
/// same sink. Switching directory closes the prior sink and
/// reopens at the new path.
pub async fn logger_open_sink(app_support_dir: String) -> Result<String, String> {
    tokio::task::spawn_blocking(move || lfs_core::logger::file_sink::open_sink(&app_support_dir))
        .await
        .map_err(|e| format!("logger_open_sink join: {e}"))?
}

/// Append a single rendered line (no trailing newline — the
/// helper appends `\n`). The caller is responsible for
/// sanitising the line (`AppLogger.sanitize`).
///
/// Sync because each call is one buffered write + one flush; the
/// FRB worker hop would otherwise add async overhead per log
/// line. No-op when the sink is closed (routine logging off).
#[flutter_rust_bridge::frb(sync)]
pub fn logger_append_line(line: String) -> Result<(), String> {
    lfs_core::logger::file_sink::append_line(&line)
}

/// Append a critical entry (header line plus continuation lines
/// such as `"  Error: …"` / stack-trace frames). Opens a fresh
/// append handle inside Rust so the write lands even when the
/// routine sink is closed. Always flushed before return.
///
/// Sync — same reasoning as [`logger_append_line`]. The crash
/// path calls this from inside `FlutterError.onError` /
/// `PlatformDispatcher.onError`, where reaching back across an
/// async boundary risks the handler returning before the line
/// is durable.
#[flutter_rust_bridge::frb(sync)]
pub fn logger_append_critical(line: String, continuations: Vec<String>) -> Result<(), String> {
    lfs_core::logger::file_sink::append_critical(&line, &continuations)
}

/// Flush the held `BufWriter`. Best-effort; no-op when the sink
/// is closed. Sync because the Dart `readLog` path needs to
/// flush + immediately read the file inside one async function.
#[flutter_rust_bridge::frb(sync)]
pub fn logger_flush() -> Result<(), String> {
    lfs_core::logger::file_sink::flush()
}

/// Read the entire current log file. Flushes the held sink
/// before reading. Returns an empty string when no log path is
/// registered or the file does not exist.
pub async fn logger_read_all() -> Result<String, String> {
    tokio::task::spawn_blocking(lfs_core::logger::file_sink::read_all)
        .await
        .map_err(|e| format!("logger_read_all join: {e}"))?
}

/// Rotate the current log file if it exceeds [`max_bytes`]. The
/// rotation chain is `<log>.N → <log>.N+1` for `N` from
/// `max_rotated - 1` down to `1`, then `<log> → <log>.1`. Closes
/// the held sink before the rename, reopens on the same path
/// afterwards.
///
/// Caller (Dart) decides the policy (`maxLogSizeBytes`,
/// `_maxRotatedFiles`). No-op when no log path is registered or
/// the file does not exist.
pub async fn logger_rotate_if_needed(max_bytes: u64, max_rotated: u32) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::logger::file_sink::rotate_if_needed(max_bytes, max_rotated)
    })
    .await
    .map_err(|e| format!("logger_rotate_if_needed join: {e}"))?
}

/// Delete the current log file plus every rotated sibling up to
/// `<log>.<max_rotated>`. Closes the held sink first. The caller
/// decides whether to call [`logger_open_sink`] again afterwards.
pub async fn logger_clear_all(max_rotated: u32) -> Result<(), String> {
    tokio::task::spawn_blocking(move || lfs_core::logger::file_sink::clear_all(max_rotated))
        .await
        .map_err(|e| format!("logger_clear_all join: {e}"))?
}

/// Flush + close the held writer. Idempotent. Sync — the close
/// path runs from `AppLogger.setThreshold(null)` and `dispose()`,
/// both of which the caller awaits inline so blocking the FRB
/// worker through a sync hop is the cheaper shape.
#[flutter_rust_bridge::frb(sync)]
pub fn logger_close_sink() -> Result<(), String> {
    lfs_core::logger::file_sink::close_sink()
}

/// Copy the current log file's contents to the user-picked
/// `target_path`. Returns the number of bytes written; `0`
/// when there is no log to export (empty file or no sink open).
/// The Dart settings-screen "Export log" action wires this to
/// the platform file-picker's selected destination so the log
/// content never crosses the FRB boundary on the Dart-write
/// side.
pub async fn logger_export_to(target_path: String) -> Result<u64, String> {
    tokio::task::spawn_blocking(move || {
        lfs_core::logger::file_sink::export_to(std::path::Path::new(&target_path))
    })
    .await
    .map_err(|e| format!("logger_export_to join: {e}"))?
}

/// `true` when the held log path exists and is non-empty.
/// Sync because the Settings → Logs widget probes this on every
/// rebuild to decide whether to render the viewer block;
/// `FutureBuilder` on every frame would be the wrong shape for
/// what is one `stat` syscall.
#[flutter_rust_bridge::frb(sync)]
pub fn logger_log_file_has_content() -> bool {
    lfs_core::logger::file_sink::log_file_has_content()
}
