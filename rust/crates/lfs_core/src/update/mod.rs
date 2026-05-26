//! Auto-update subsystem: HTTP fetch/download ([`http`]), release
//! metadata + version comparison ([`metadata`]), Ed25519 signature
//! verification ([`signing`]), and the orchestrator that checks for,
//! downloads, and verifies a release ([`orchestrator`]).

pub mod http;
pub mod metadata;
pub mod orchestrator;
pub mod signing;
