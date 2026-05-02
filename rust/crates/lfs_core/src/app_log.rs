//! Rust-core log fan-out via the bus.
//!
//! Without this surface, internal Rust failures (panics caught by
//! FRB, errors swallowed in catch-arms, diagnostic traces) never
//! reach the on-disk `letsflutssh.log` — only Dart-side
//! `AppLogger.log(...)` calls do. The `[lfs_os_security] logind
//! listener exited` line was visible only because `lfs_os_security`
//! prints to stderr; everything else was silent.
//!
//! Every internal log site uses one of [`info!`] / [`warn!`] /
//! [`error!`] (re-exported here). Each call publishes a
//! [`Event::CoreLog`] on the bus; the Dart-side `AppLogger`
//! subscribes to [`EventTopic::CoreLog`] and folds the line into
//! the same on-disk file every Dart call writes through. From the
//! user's perspective, Rust log lines are indistinguishable from
//! Dart ones in the in-app viewer + log file.
//!
//! ## Sanitisation
//!
//! Run [`crate::log_sanitize::sanitize_error`] (or `redact_secrets`
//! for the message body) at the call site **before** passing into
//! these macros. The bus does not sanitise — too easy to lose
//! per-callsite context. The shipped macros call `sanitize` for
//! you, so prefer them over publishing `Event::CoreLog` directly.
//!
//! ## Pre-subscriber drops
//!
//! Lines published before the Dart subscriber attaches (cold-boot
//! windows, very early init) are dropped — the broadcast channel
//! has no replay. Acceptable for the diagnostics use case;
//! load-bearing failures use bus events that the connection /
//! security paths already publish through dedicated topics.

use crate::bus::{CoreLogLevel, Event};
use crate::log_sanitize::{redact_secrets, sanitize_error_message};

/// Publish a single log line on the bus. Prefer the [`info!`] /
/// [`warn!`] / [`error!`] macros — they call this with the right
/// sanitisation chain and bus handle.
pub fn publish(level: CoreLogLevel, name: impl Into<String>, message: impl Into<String>) {
    let raw = message.into();
    // Two-pass sanitise mirrors the Dart `AppLogger.sanitize`
    // contract: secrets first (PEM / long base64), then PII
    // (IPv4 / user@host / home paths).
    let safe = sanitize_error_message(&redact_secrets(&raw));
    let app = crate::app::instance();
    app.bus.publish(Event::CoreLog {
        level,
        name: name.into(),
        message: safe,
    });
}

/// Info-level log line. Used for routine state transitions —
/// "session loaded", "tier switched", "DB open". The default
/// rung; degrades to [`warn!`] / [`error!`] when the line
/// describes a fallback / failure.
#[macro_export]
macro_rules! app_log_info {
    ($name:expr, $($arg:tt)*) => {
        $crate::app_log::publish(
            $crate::bus::CoreLogLevel::Info,
            $name,
            format!($($arg)*),
        )
    };
}

/// Warn-level log line. Used for degraded-but-recoverable paths —
/// fallback fired, probe failed, rate-limit kicked in.
#[macro_export]
macro_rules! app_log_warn {
    ($name:expr, $($arg:tt)*) => {
        $crate::app_log::publish(
            $crate::bus::CoreLogLevel::Warn,
            $name,
            format!($($arg)*),
        )
    };
}

/// Error-level log line. Used for failures the user likely cares
/// about — connect timeout, DB corruption, lost credentials.
#[macro_export]
macro_rules! app_log_error {
    ($name:expr, $($arg:tt)*) => {
        $crate::app_log::publish(
            $crate::bus::CoreLogLevel::Error,
            $name,
            format!($($arg)*),
        )
    };
}
