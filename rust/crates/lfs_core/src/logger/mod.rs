//! Rust-side ownership of the app's on-disk log file.
//!
//! The Dart `AppLogger` (in `lib/utils/logger.dart`) formats +
//! sanitises log lines, broadcasts them to the in-app viewer, and
//! holds an in-memory pre-FRB ring buffer for `logCritical`. The
//! actual file I/O on `<app_support>/logs/letsflutssh.log` —
//! create, append, rotate, read, clear, chmod — lives here so the
//! `Rust owns data; Flutter renders it` invariant covers the log
//! sink end to end.
//!
//! Submodules:
//!
//! * [`file_sink`] — process-wide held [`std::fs::File`] +
//!   `BufWriter` behind a `Mutex`, plus the rotation / clear /
//!   read / chmod surface.

pub mod file_sink;
