//! FRB adapter for `lfs_core::security::tier_unlock_orchestrator`.
//!
//! Per-tier unlock orchestrators that drive the tier-machine
//! through `Locked → Unlocking → Unlocked` in a single FRB hop.
//! The Dart `SecurityInitController` calls one orchestrator per
//! tier and sees the cascade resolve in a single round-trip rather
//! than walking the `set_tier` + `dispatch` + `try_advance` chain
//! by hand.
//!
//! Sync — every orchestrator is a chain of mutex-guarded
//! transition-table lookups + bus publishes, sub-microsecond.

use lfs_core::security::tier_unlock_orchestrator::{self, UnlockOutcome};

/// FRB-mirrored result of a per-tier unlock attempt. Mirrors
/// `lfs_core::security::tier_unlock_orchestrator::UnlockOutcome`
/// for the codegen wire — the Dart caller branches on the
/// discriminant only (key bytes never cross FRB on the return
/// value; the `TierUnlockedListener` reads them out of the
/// SecretStore via `secrets_take` on the cascade event).
pub enum DbUnlockOutcome {
    /// Key staged under `tier.unlock.key` + `UnlockSucceeded`
    /// dispatched. Listener handles the post-unlock cascade.
    Staged,
    /// Wrong password / PIN. Dialog stays open for retry.
    WrongSecret,
    /// User cancelled an inner prompt (e.g. hardware vault PIN
    /// sub-dialog). Outer dialog stays open.
    Cancelled,
    /// Plugin / hardware unrecoverable error. Carries the
    /// machine-readable code for log + diagnostics.
    PluginError(String),
    /// On-disk KDF/gate state corrupt. Caller routes through
    /// corruption recovery.
    Corruption(String),
}

impl From<UnlockOutcome> for DbUnlockOutcome {
    fn from(o: UnlockOutcome) -> Self {
        match o {
            UnlockOutcome::Staged => Self::Staged,
            UnlockOutcome::WrongSecret => Self::WrongSecret,
            UnlockOutcome::Cancelled => Self::Cancelled,
            UnlockOutcome::PluginError(s) => Self::PluginError(s),
            UnlockOutcome::Corruption(s) => Self::Corruption(s),
        }
    }
}

/// Plaintext tier — no secret, no plugin call, no user prompt.
/// Dispatches `UnlockRequested` then `UnlockSucceeded` against
/// the singleton tier machine; subscribers see two
/// `BusEvent::TierStateChanged` events (`unlocking` →
/// `unlocked`) on the `tier` topic. The Dart caller still owns
/// the drift-open step (drift is a Dart ORM); the orchestrator
/// just fast-paths the cascade visibility.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_unlock_plaintext() {
    tier_unlock_orchestrator::unlock_plaintext();
}

/// Keychain tier (T1) — read the DB encryption key from the OS
/// keychain via the prompt registry; emit cascade events along
/// the way; stage the bytes in the SecretStore. Returns the
/// outcome discriminant — bytes never cross FRB.
///
/// Async — round-trips through the bus to the Dart subscriber
/// for the `flutter_secure_storage.read` call. The receiver
/// completes as soon as the subscriber resolves the prompt;
/// the FRB worker frees during the wait so the unlock dialog
/// stays responsive.
pub async fn tier_unlock_keychain() -> DbUnlockOutcome {
    tier_unlock_orchestrator::unlock_keychain().await.into()
}

/// KeychainWithPassword tier (L2) — verify the typed user
/// password through the on-disk gate, then read the DB
/// encryption key from the OS keychain. Stages bytes in the
/// SecretStore on success + returns the outcome.
///
/// The Dart caller owns the unlock dialog UI (rate-limit
/// countdown, biometric option); after the user submits the
/// password the caller invokes this orchestrator to drive the
/// verify + key-read + cascade emission in one FRB hop. The
/// dialog interprets `WrongSecret` as "keep open + decrement
/// rate limiter"; `Staged` triggers dialog close + the
/// post-unlock listener cascade.
pub async fn tier_unlock_keychain_with_password(password: Vec<u8>) -> DbUnlockOutcome {
    tier_unlock_orchestrator::unlock_keychain_with_password(password)
        .await
        .into()
}

/// Paranoid tier — derive the DB key from the typed master
/// password via Argon2id; stage in the SecretStore + emit
/// cascade. Returns the outcome.
///
/// Reads the support dir from the pinned singleton — caller
/// must have invoked `master_password_init` at app startup.
pub async fn tier_unlock_paranoid(password: Vec<u8>) -> DbUnlockOutcome {
    tier_unlock_orchestrator::unlock_paranoid(password)
        .await
        .into()
}

/// Hardware tier (T2) — fan out a hardware-vault-unlock prompt
/// to the Dart subscriber + emit cascade events. `pin` is the
/// typed user secret for the password modifier; pass `None`
/// for the passwordless variant. Stages the unsealed bytes in
/// the SecretStore on success.
pub async fn tier_unlock_hardware(pin: Option<String>) -> DbUnlockOutcome {
    tier_unlock_orchestrator::unlock_hardware(pin).await.into()
}

/// Resolve a pending hardware-vault unlock with success bytes.
/// `Ok(Some(bytes))` on a successful unseal; the orchestrator
/// dispatches `UnlockSucceeded` against the tier machine.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_unlock_prompt_resolve(prompt_id: String, bytes: Vec<u8>) -> bool {
    use lfs_core::security::hardware_vault_unlock_prompt;
    let payload = if bytes.is_empty() { None } else { Some(bytes) };
    hardware_vault_unlock_prompt::instance().resolve(&prompt_id, Ok(payload))
}

/// Resolve a pending hardware-vault unlock with the
/// "wrong PIN / user cancel / hardware reported failure"
/// signal. `Ok(None)`. Orchestrator dispatches `UnlockFailed
/// { WrongSecret }`.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_unlock_prompt_resolve_wrong(prompt_id: String) -> bool {
    use lfs_core::security::hardware_vault_unlock_prompt;
    hardware_vault_unlock_prompt::instance().resolve(&prompt_id, Ok(None))
}

/// Resolve a pending hardware-vault unlock with a plugin
/// error message. Orchestrator dispatches `UnlockFailed
/// { PluginUnavailable { code: message } }`.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_unlock_prompt_resolve_error(prompt_id: String, message: String) -> bool {
    use lfs_core::security::hardware_vault_unlock_prompt;
    hardware_vault_unlock_prompt::instance().resolve(&prompt_id, Err(message))
}

/// Cancel a pending hardware-vault unlock without resolving —
/// used by the Dart subscriber when the unlock dialog is torn
/// down before the platform call returns. Idempotent on a
/// missing id.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_unlock_prompt_cancel(prompt_id: String) {
    use lfs_core::security::hardware_vault_unlock_prompt;
    hardware_vault_unlock_prompt::instance().cancel(&prompt_id);
}

/// First-launch T0 (Plaintext). Dispatches the cascade with an
/// empty staged key so the listener opens the DB unencrypted via
/// `ensureRustDbOpen(key: empty)`. Identical wire shape to
/// `tier_unlock_plaintext` — first-launch and re-unlock converge
/// on the same listener path.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_first_launch_plaintext() {
    tier_unlock_orchestrator::first_launch_plaintext();
}

/// First-launch Paranoid. Runs `master_password::enable`
/// (Argon2id + writes `credentials.kdf` + `credentials.verify`),
/// stages the derived key + emits the cascade. Async — Argon2id
/// is CPU-heavy and runs on `spawn_blocking`.
pub async fn tier_first_launch_paranoid(password: Vec<u8>) -> DbUnlockOutcome {
    tier_unlock_orchestrator::first_launch_paranoid(password)
        .await
        .into()
}

/// First-launch T1 (Keychain). Generates a fresh AES-GCM key,
/// publishes a `KeychainOpPromptRequest { Write }` so the Dart
/// subscriber writes it via `flutter_secure_storage`, stages
/// the bytes + emits the cascade.
pub async fn tier_first_launch_keychain() -> DbUnlockOutcome {
    tier_unlock_orchestrator::first_launch_keychain()
        .await
        .into()
}

/// First-launch L2 (KeychainWithPassword). Sets the on-disk gate
/// password (HMAC-SHA-256 salt + verifier files), generates a
/// fresh AES-GCM key, writes it to the OS keychain via the Dart
/// subscriber, stages + emits cascade. On a keychain write
/// failure the gate is rolled back so a retry sees the
/// "not configured" state.
pub async fn tier_first_launch_keychain_with_password(password: Vec<u8>) -> DbUnlockOutcome {
    tier_unlock_orchestrator::first_launch_keychain_with_password(password)
        .await
        .into()
}

/// First-launch T2 (Hardware). Generates a fresh AES-GCM key,
/// publishes a `HardwareVaultSealPromptRequest` so the Dart
/// subscriber wraps it via `HardwareTierVault.store(...)`,
/// stages + emits cascade. Pass `pin: None` for the passwordless
/// variant.
pub async fn tier_first_launch_hardware(pin: Option<String>) -> DbUnlockOutcome {
    tier_unlock_orchestrator::first_launch_hardware(pin)
        .await
        .into()
}

/// Resolve a pending hardware-vault seal prompt with success.
/// `Ok(())` — the orchestrator stages the bytes it generated and
/// dispatches `UnlockSucceeded`.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_seal_prompt_resolve(prompt_id: String) -> bool {
    use lfs_core::security::hardware_vault_seal_prompt;
    hardware_vault_seal_prompt::instance().resolve(&prompt_id, Ok(()))
}

/// Resolve a pending hardware-vault seal prompt with a plugin
/// error. Orchestrator dispatches `UnlockFailed
/// { PluginUnavailable { code: message } }` so the Dart caller
/// falls back to plaintext.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_seal_prompt_resolve_error(prompt_id: String, message: String) -> bool {
    use lfs_core::security::hardware_vault_seal_prompt;
    hardware_vault_seal_prompt::instance().resolve(&prompt_id, Err(message))
}

/// Cancel a pending hardware-vault seal prompt without resolving
/// — used by the Dart subscriber when the wizard / first-launch
/// flow tears down before the platform call returns.
#[flutter_rust_bridge::frb(sync)]
pub fn hardware_vault_seal_prompt_cancel(prompt_id: String) {
    use lfs_core::security::hardware_vault_seal_prompt;
    hardware_vault_seal_prompt::instance().cancel(&prompt_id);
}

/// Stage [`bytes`] in the SecretStore + emit the unlock cascade
/// for [`tier_wire_name`] without running the per-tier verify
/// step. Used by the biometric fast-path: the bytes come from
/// the OS-managed `BiometricKeyVault` (Dart-side flutter
/// plugin), so the orchestrator's verify is bypassed but the
/// `TierUnlockedListener` still runs the post-unlock cascade
/// (caches, drift open, config persist) off the staged key.
///
/// `tier_wire_name` is the same kebab-case wire name the
/// `tier_machine` exposes (`keychain_with_password`,
/// `hardware`, etc.). Returns `false` on an unrecognised wire
/// name so the Dart caller can fall back to inline injection.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_unlock_biometric_commit(tier_wire_name: String, bytes: Vec<u8>) -> bool {
    use lfs_core::security::SecurityTier;
    let tier = match tier_wire_name.as_str() {
        "plaintext" => SecurityTier::Plaintext,
        "keychain" => SecurityTier::Keychain,
        // Pre-v3 wire-name; v3 collapse rewrites stored configs already, but FRB callers may still hand the legacy string from in-flight bus events captured pre-restart. Map to Keychain identical to the new wire name.
        "keychain_with_password" => SecurityTier::Keychain,
        "hardware" => SecurityTier::Hardware,
        "paranoid" => SecurityTier::Paranoid,
        _ => return false,
    };
    tier_unlock_orchestrator::commit_biometric_unlock(tier, &bytes);
    true
}

/// SecretRef variant of [`tier_unlock_biometric_commit`]. The bytes
/// are already in the SecretStore under `secret_id` (staged by the
/// biometric-vault SecretRef read shims) and never cross the FRB
/// boundary on this path. The orchestrator atomically renames the
/// slot into the canonical active id before firing the unlock
/// cascade.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_unlock_biometric_commit_from_secret(tier_wire_name: String, secret_id: String) -> bool {
    use lfs_core::security::SecurityTier;
    let tier = match tier_wire_name.as_str() {
        "plaintext" => SecurityTier::Plaintext,
        "keychain" => SecurityTier::Keychain,
        // Pre-v3 wire-name; v3 collapse rewrites stored configs already, but FRB callers may still hand the legacy string from in-flight bus events captured pre-restart. Map to Keychain identical to the new wire name.
        "keychain_with_password" => SecurityTier::Keychain,
        "hardware" => SecurityTier::Hardware,
        "paranoid" => SecurityTier::Paranoid,
        _ => return false,
    };
    tier_unlock_orchestrator::commit_biometric_unlock_from_secret(tier, &secret_id)
}

/// Cancel an in-flight Keychain (T1) unlock attempt. Dispatches
/// `UnlockFailed { UserCancelled }` so the tier machine flips
/// back to `Locked`. Used by the Dart unlock-flow caller when
/// the T1 cascade is torn down before the keychain read lands
/// (e.g. user invoked a tier reset mid-unlock).
#[flutter_rust_bridge::frb(sync)]
pub fn tier_unlock_keychain_cancel() {
    use lfs_core::security::SecurityTier;
    tier_unlock_orchestrator::cancel_unlock(SecurityTier::Keychain);
}

/// Cancel an in-flight L2 unlock attempt. Dispatches
/// `UnlockFailed { UserCancelled }` so the tier machine flips
/// back to `Locked` when the user dismisses the L2 unlock
/// dialog without submitting a password.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_unlock_keychain_with_password_cancel() {
    use lfs_core::security::SecurityTier;
    tier_unlock_orchestrator::cancel_unlock(SecurityTier::Keychain);
}

/// Cancel an in-flight T2 unlock attempt. Dispatches
/// `UnlockFailed { UserCancelled }` so the tier machine flips
/// back to `Locked` when the user dismisses the T2 PIN dialog
/// without submitting.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_unlock_hardware_cancel() {
    use lfs_core::security::SecurityTier;
    tier_unlock_orchestrator::cancel_unlock(SecurityTier::Hardware);
}

/// Cancel an in-flight Paranoid unlock attempt. Dispatches
/// `UnlockFailed { UserCancelled }` so the tier machine flips
/// back to `Locked` when the user dismisses the master-
/// password unlock dialog without submitting. The Dart
/// "forgot password" reset flow also routes through this
/// before kicking off the wipe.
#[flutter_rust_bridge::frb(sync)]
pub fn tier_unlock_paranoid_cancel() {
    use lfs_core::security::SecurityTier;
    tier_unlock_orchestrator::cancel_unlock(SecurityTier::Paranoid);
}
