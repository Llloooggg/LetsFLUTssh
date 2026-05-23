//! russh verbose-log capture (ssh -vvv-style connection trace).
//!
//! russh emits its handshake / auth diagnostics through the `log`
//! crate — kex / cipher / host-key algorithms, the offered public-key
//! algorithms, `server-sig-algs`, and the per-method userauth
//! accept / reject lines. That is the material that explains *why* an
//! auth attempt was accepted or rejected, one layer below the
//! remaining-methods detail [`super::check_auth_result`] already
//! surfaces. This module installs a process-global [`log::Log`] that
//! forwards those records into the opt-in file log (`AppLogger`) via
//! the CoreLog bus, tagged with the connecting session's id so a
//! multi-connection log stays readable.
//!
//! Off by default: the bridge does nothing until [`set_verbose`] is
//! called with `true` (wired from `AppConfig.ssh.verbose_connection_log`).
//! When off, `log`'s max level is `Off`, so no `log`-using crate even
//! formats its macro arguments — zero steady-state cost. The verbose
//! trace lands only in the file log, never on the pre-terminal
//! connection screen: it is hundreds of lines per connect and would
//! drown the high-level phase view; the screen keeps the phase steps +
//! the [`super::check_auth_result`] reason.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Once;

use crate::bus::CoreLogLevel;

static VERBOSE: AtomicBool = AtomicBool::new(false);
static INSTALL: Once = Once::new();

tokio::task_local! {
    /// Connection id bound around a connect future so russh records
    /// emitted on that task are attributed to the right session.
    static CONNECT_ID: String;
}

struct RusshLogBridge;

impl log::Log for RusshLogBridge {
    fn enabled(&self, meta: &log::Metadata<'_>) -> bool {
        VERBOSE.load(Ordering::Relaxed) && is_ssh_target(meta.target())
    }

    fn log(&self, record: &log::Record<'_>) {
        if !self.enabled(record.metadata()) {
            return;
        }
        let id = CONNECT_ID
            .try_with(|id| id.clone())
            .unwrap_or_else(|_| "?".to_string());
        let level = match record.level() {
            log::Level::Error => CoreLogLevel::Error,
            log::Level::Warn => CoreLogLevel::Warn,
            _ => CoreLogLevel::Info,
        };
        // `publish` runs the same secret + PII redaction the rest of
        // the file log uses, so a russh line carrying a host / algo /
        // user fragment is sanitized before it lands.
        crate::app_log::publish(
            level,
            "SSHVerbose",
            format!("[{id}] {}: {}", record.target(), record.args()),
        );
    }

    fn flush(&self) {}
}

fn is_ssh_target(target: &str) -> bool {
    target.starts_with("russh")
}

/// Install the bridge as the process logger. Idempotent (a `Once`
/// guard) so it can be called from every `set_verbose`. A logger
/// already installed by another dep / a test harness wins, and we
/// degrade silently — verbose capture is a diagnostic, never
/// load-bearing.
fn install() {
    INSTALL.call_once(|| {
        if log::set_boxed_logger(Box::new(RusshLogBridge)).is_ok() {
            log::set_max_level(log::LevelFilter::Off);
        }
    });
}

/// Toggle russh verbose capture. `true` raises `log`'s max level so
/// russh records reach the bridge; `false` drops it back to `Off` so
/// no `log`-using crate pays the macro-formatting cost.
pub fn set_verbose(on: bool) {
    install();
    VERBOSE.store(on, Ordering::Relaxed);
    log::set_max_level(if on {
        log::LevelFilter::Trace
    } else {
        log::LevelFilter::Off
    });
}

/// Whether verbose capture is currently enabled.
#[must_use]
pub fn is_verbose() -> bool {
    VERBOSE.load(Ordering::Relaxed)
}

/// Run `fut` with the connecting session's id bound so russh records
/// emitted on this task are attributed to it in the verbose log.
pub async fn scoped<F, T>(id: String, fut: F) -> T
where
    F: std::future::Future<Output = T>,
{
    CONNECT_ID.scope(id, fut).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ssh_target_filter_matches_russh_only() {
        assert!(is_ssh_target("russh"));
        assert!(is_ssh_target("russh::client::encrypted"));
        assert!(is_ssh_target("russh_sftp::client"));
        assert!(!is_ssh_target("tokio::net"));
        assert!(!is_ssh_target("reqwest"));
    }

    #[test]
    fn set_verbose_flips_the_flag() {
        set_verbose(true);
        assert!(is_verbose());
        set_verbose(false);
        assert!(!is_verbose());
    }
}
