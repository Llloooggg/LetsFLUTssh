//! Per-prompt-type registry for connection credential prompts.
//!
//! Typed `tokio::oneshot::Sender<CredentialResponse>` per prompt
//! id, registered by the awaiting Rust connection handler,
//! resolved by the Dart subscriber after the user types a secret
//! into the unlock dialog.
//!
//! Typed per-prompt response (not a generic JSON shape) so a
//! Dart-side typo at the wire layer surfaces as a decode failure
//! at the registry boundary rather than a silent miscompare in
//! the connect cascade. The Dart UI dialog stays Dart-side
//! because UI rendering is not portable through Rust; the Rust
//! actor publishes the request + awaits the response.
//!
//! Backed by the generic
//! [`super::prompt_registry::PromptRegistry`].
//!
//! **Currently not wired into the production connect path.**
//! Lands ahead of the connection-credential-overlay actor work
//! so the FRB shim layer + the Dart subscriber bus wiring can
//! target a stable registry API.

use super::prompt_registry::PromptRegistry as Generic;

/// What the connection actor is asking the user for. Mirrors the
/// Dart-era prompt variants (`PasswordPromptDialog` /
/// `PassphrasePromptDialog`) so the UI subscriber picks the right
/// dialog widget without re-classifying.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CredentialPromptKind {
    /// SSH password for the session.
    Password,
    /// Passphrase to decrypt the session's private key.
    Passphrase,
}

impl CredentialPromptKind {
    /// Stable wire name for the bus boundary. Each variant maps
    /// to a string so Dart subscribers branch without parsing
    /// the enum across FRB.
    pub fn wire_name(self) -> &'static str {
        match self {
            CredentialPromptKind::Password => "password",
            CredentialPromptKind::Passphrase => "passphrase",
        }
    }

    pub fn from_wire_name(s: &str) -> Option<Self> {
        match s {
            "password" => Some(CredentialPromptKind::Password),
            "passphrase" => Some(CredentialPromptKind::Passphrase),
            _ => None,
        }
    }
}

/// What the user did. `Cancel` is a terminal outcome the
/// connection actor treats as "auth refused, drop the
/// connect attempt"; `Submit` carries the secret bytes + a
/// "remember for this session" flag.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CredentialResponse {
    /// User typed a secret + tapped Submit. `secret` is moved
    /// into the awaiting Rust handler which stages it in the
    /// SecretStore (so Dart heap drops the plaintext as soon
    /// as the FRB call returns).
    Submit {
        secret: Vec<u8>,
        /// User ticked "Remember for this session" — the
        /// connection actor caches the secret in the per-session
        /// `SecretStore` slot so the next reconnect skips the
        /// dialog.
        remember_for_session: bool,
    },
    /// User dismissed the dialog or tapped Cancel. The
    /// connection actor drops the connect attempt with a
    /// localised "auth cancelled" error.
    Cancel,
}

/// Process-singleton registry alias parameterised over
/// [`CredentialResponse`]. Tests use `PromptRegistry::new`
/// directly so they don't share state through `instance()`.
pub type PromptRegistry = Generic<CredentialResponse>;

/// Process-singleton instance — the connection actor and the
/// FRB response shim share this. Tests use `PromptRegistry::new`
/// directly so they don't share state through `instance()`.
pub fn instance() -> &'static PromptRegistry {
    static GLOBAL: std::sync::OnceLock<PromptRegistry> = std::sync::OnceLock::new();
    GLOBAL.get_or_init(PromptRegistry::new)
}
#[cfg(test)]
#[path = "../../tests/unit/security_credential_prompt.rs"]
mod tests;
