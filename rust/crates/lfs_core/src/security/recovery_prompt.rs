//! Per-prompt registry for vault-recovery dialogs the Rust
//! orchestrator publishes onto the bus.
//!
//! Three Dart-shell dialogs route through here:
//!
//! - `DbCorruptDialog` — surfaced for the integrity-probe failure,
//!   the migration-runner failure, and the vault-state-missing
//!   scenario.
//! - `TierResetDialog` — surfaced for the legacy-state detection.
//!
//! The orchestrator calls [`PromptRegistry::register`], publishes a
//! [`crate::bus::Event::RecoveryPromptRequest`] with the matching
//! [`RecoveryPromptKind`], and awaits the receiver. The Dart
//! subscriber renders the right widget and dispatches the user's
//! choice back through the `recovery_prompt_resolve` FRB shim — which
//! converts the typed [`RecoveryPromptResponse`] back into the wire
//! string the registry stores. The orchestrator then branches on the
//! decoded enum (Reset / Quit / TryOtherTier) and either runs the
//! destructive cascade (Rust-side via
//! [`super::recovery::run_destructive_reset`]) or returns a
//! [`super::recovery::RecoveryOutcome`] telling Dart what to do next.
//!
//! Backed by the generic [`super::prompt_registry::PromptRegistry`].

use super::prompt_registry::PromptRegistry as Generic;

/// Which dialog Dart must surface. Each variant maps onto an
/// existing widget so the listener picks the right one without
/// re-classifying — see the `RecoveryPromptListener` Dart-side
/// `switch (event.kind)` dispatcher.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RecoveryPromptKind {
    /// Database integrity probe failed (or the migration runner
    /// failed) — surface `DbCorruptDialog`. Three choices:
    /// `Reset` / `TryOtherTier` / `Quit`.
    DbCorruptDetected { reason: String },
    /// Configured tier is unreachable (vault state file missing,
    /// keychain entry gone, hardware-vault blob lost) — surface
    /// `DbCorruptDialog` framed as security-state loss.
    /// Three choices: `Reset` / `TryOtherTier` / `Quit`.
    VaultStateMissing { tier_label: String },
    /// Unrecognised state on disk (an out-of-range config schema
    /// version or orphan artefacts with no security config) —
    /// surface `TierResetDialog`. Two choices: `Reset` / `Quit`.
    LegacyStateFound {
        config_version_on_disk: i32,
        orphan_artefacts: bool,
    },
}

impl RecoveryPromptKind {
    /// Stable wire-name tag for the prompt kind. Dart subscriber
    /// branches on this without parsing the inner payload across
    /// FRB.
    pub fn wire_name(&self) -> &'static str {
        match self {
            RecoveryPromptKind::DbCorruptDetected { .. } => "dbCorruptDetected",
            RecoveryPromptKind::VaultStateMissing { .. } => "vaultStateMissing",
            RecoveryPromptKind::LegacyStateFound { .. } => "legacyStateFound",
        }
    }
}

/// What the user picked. Mirrors the union of choices the two
/// dialogs offer. The legacy-state prompt rejects `TryOtherTier`
/// (the widget never offers it); the orchestrator treats any
/// out-of-band value as `Quit` so a stale dispatch from a
/// dismissed dialog can never lose the user's data.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryPromptResponse {
    /// User accepted the destructive reset. Orchestrator runs
    /// the cascade and returns `WipedAndRestarted`.
    Reset,
    /// User chose to quit. Orchestrator returns `UserExited`;
    /// Dart-side caller runs `SystemNavigator.pop` + `exit(0)`.
    Quit,
    /// User asked to retry the unlock path under a different
    /// tier. Only valid for `DbCorruptDetected` and
    /// `VaultStateMissing`; the legacy-state widget never
    /// offers this choice. Orchestrator returns `Continued`;
    /// the caller's Dart side runs `_retryUnlockUnderDifferentTier`.
    TryOtherTier,
}

impl RecoveryPromptResponse {
    /// Stable wire name for the bus / FRB boundary. Each variant
    /// maps to a kebab-style tag so a hand-rolled subscriber
    /// (integration tests, future native non-Flutter shell)
    /// can dispatch without sharing the Rust enum module.
    pub fn wire_name(self) -> &'static str {
        match self {
            RecoveryPromptResponse::Reset => "reset",
            RecoveryPromptResponse::Quit => "quit",
            RecoveryPromptResponse::TryOtherTier => "tryOtherTier",
        }
    }

    pub fn from_wire_name(s: &str) -> Option<Self> {
        match s {
            "reset" => Some(RecoveryPromptResponse::Reset),
            "quit" => Some(RecoveryPromptResponse::Quit),
            "tryOtherTier" => Some(RecoveryPromptResponse::TryOtherTier),
            _ => None,
        }
    }
}

/// Process-singleton registry alias parameterised over the wire
/// string of [`RecoveryPromptResponse`]. The wire-string round-trip
/// is the same shape every other probe-prompt registry uses; this
/// keeps the FRB-side resolve shim string-keyed and lets the
/// `from_wire_name` round-trip handle stale / unknown dispatches
/// safely without panicking.
pub type PromptRegistry = Generic<String>;

pub fn instance() -> &'static PromptRegistry {
    static GLOBAL: std::sync::OnceLock<PromptRegistry> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(PromptRegistry::new)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn response_wire_name_round_trips() {
        for r in [
            RecoveryPromptResponse::Reset,
            RecoveryPromptResponse::Quit,
            RecoveryPromptResponse::TryOtherTier,
        ] {
            assert_eq!(
                RecoveryPromptResponse::from_wire_name(r.wire_name()),
                Some(r)
            );
        }
    }

    #[test]
    fn response_from_wire_name_unknown_yields_none() {
        assert_eq!(RecoveryPromptResponse::from_wire_name(""), None);
        assert_eq!(RecoveryPromptResponse::from_wire_name("RESET"), None);
        assert_eq!(RecoveryPromptResponse::from_wire_name("Unknown"), None);
    }

    #[test]
    fn kind_wire_name_is_stable() {
        assert_eq!(
            RecoveryPromptKind::DbCorruptDetected { reason: "x".into() }.wire_name(),
            "dbCorruptDetected"
        );
        assert_eq!(
            RecoveryPromptKind::VaultStateMissing {
                tier_label: "T1".into()
            }
            .wire_name(),
            "vaultStateMissing"
        );
        assert_eq!(
            RecoveryPromptKind::LegacyStateFound {
                config_version_on_disk: 3,
                orphan_artefacts: true,
            }
            .wire_name(),
            "legacyStateFound"
        );
    }

    #[tokio::test]
    async fn register_and_resolve_round_trips_wire_string() {
        let reg = PromptRegistry::new();
        let rx = reg.register("p1".into());
        assert!(reg.resolve("p1", RecoveryPromptResponse::Reset.wire_name().into()));
        let wire = rx.await.unwrap();
        assert_eq!(
            RecoveryPromptResponse::from_wire_name(&wire),
            Some(RecoveryPromptResponse::Reset)
        );
    }

    #[test]
    fn cancel_drops_without_resolving() {
        let reg = PromptRegistry::new();
        let _rx = reg.register("p".into());
        reg.cancel("p");
        assert_eq!(reg.pending_count(), 0);
        assert!(!reg.resolve("p", "reset".into()));
    }

    #[test]
    fn resolve_unknown_id_is_noop() {
        let reg = PromptRegistry::new();
        assert!(!reg.resolve("ghost", "reset".into()));
    }
}
