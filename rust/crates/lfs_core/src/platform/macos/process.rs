//! Thin process helper for the macOS code-signing flow.
//!
//! Wraps `std::process::Command` so every spawn lands behind a
//! single typed surface — testable via the [`Runner`] trait
//! (production [`SystemRunner`] dispatches to the real CLI;
//! tests substitute a [`MockRunner`] that asserts on argv).
//!
//! Mirrors the Dart `process_runner.dart` shape verb-for-verb.

use std::process::{Command, Output};

/// Captured result of a one-shot subprocess. UTF-8-decoded
/// stdout / stderr (lossy on invalid sequences — same fallback
/// the Dart impl picks).
#[derive(Debug, Clone)]
pub struct ProcOutput {
    pub status: i32,
    pub stdout: String,
    pub stderr: String,
}

impl ProcOutput {
    pub fn success(&self) -> bool {
        self.status == 0
    }

    pub(crate) fn from_std(o: Output) -> Self {
        Self {
            status: o.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
        }
    }
}

/// Process runner abstraction. Tests substitute a [`MockRunner`]
/// that records the spawn arguments + returns canned exit codes
/// without touching the host.
pub trait Runner: Send + Sync {
    fn run(&self, executable: &str, args: &[&str]) -> std::io::Result<ProcOutput>;
}

/// Production runner — `std::process::Command` directly. Used
/// when the caller is happy with the host's `PATH` resolution.
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemRunner;

impl Runner for SystemRunner {
    fn run(&self, executable: &str, args: &[&str]) -> std::io::Result<ProcOutput> {
        let output = Command::new(executable).args(args).output()?;
        Ok(ProcOutput::from_std(output))
    }
}

#[cfg(test)]
pub(crate) mod test_support {
    use super::*;
    use std::sync::Mutex;

    /// Records every spawn for assertion + replays canned
    /// outputs. Each enqueued reply matches one `run` call in
    /// the order the test pushed them.
    pub struct MockRunner {
        replies: Mutex<Vec<ProcOutput>>,
        log: Mutex<Vec<MockCall>>,
    }

    #[derive(Debug, Clone)]
    pub struct MockCall {
        pub executable: String,
        pub args: Vec<String>,
    }

    impl MockRunner {
        pub fn new() -> Self {
            Self {
                replies: Mutex::new(Vec::new()),
                log: Mutex::new(Vec::new()),
            }
        }

        pub fn enqueue(&self, status: i32, stdout: &str, stderr: &str) {
            self.replies.lock().unwrap().push(ProcOutput {
                status,
                stdout: stdout.to_string(),
                stderr: stderr.to_string(),
            });
        }

        pub fn calls(&self) -> Vec<MockCall> {
            self.log.lock().unwrap().clone()
        }

        fn next_reply(&self) -> ProcOutput {
            self.replies.lock().unwrap().pop().unwrap_or(ProcOutput {
                status: 0,
                stdout: String::new(),
                stderr: String::new(),
            })
        }
    }

    impl Default for MockRunner {
        fn default() -> Self {
            Self::new()
        }
    }

    impl Runner for MockRunner {
        fn run(&self, executable: &str, args: &[&str]) -> std::io::Result<ProcOutput> {
            self.log.lock().unwrap().push(MockCall {
                executable: executable.to_string(),
                args: args.iter().map(|s| s.to_string()).collect(),
            });
            Ok(self.next_reply())
        }
    }
}
