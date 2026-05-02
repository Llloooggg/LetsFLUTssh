//! Per-tier unlock orchestrators that drive the
//! [`crate::security::tier_machine`] state machine through the
//! cascade `Locked → Unlocking → Unlocked`. Today the Dart
//! `SecurityInitController` (1167 LOC) owns the equivalent
//! Dart-side orchestration; this module is the staging ground
//! for the per-tier handlers that move into Rust under the
//! retire arc.
//!
//! The DB-open step itself (drift opens `letsflutssh.db` with
//! the resolved master key) stays Dart-side because drift is a
//! Dart ORM and can't be driven from Rust. The orchestrator's
//! contract is therefore "resolve the master key, stage it in
//! the SecretStore under a canonical id, advance the tier
//! machine, return the SecretStore id". The Dart subscriber
//! reads the staged key from the SecretStore once and feeds it
//! to drift.
//!
//! Per-tier orchestrators land one-by-one. Plaintext is the
//! simplest (no secret); subsequent tiers compose with the OS
//! keychain / biometric stack directly via
//! [`lfs_os_security::secure_key_storage`] +
//! [`lfs_os_security::biometric_auth`] for the L1/L2 paths, and
//! with the still-Dart-side hardware-vault prompt registries
//! (`hardware_vault_unlock_prompt`, `hardware_vault_seal_prompt`)
//! for L3 — the latter own platform-bound surfaces (Hello PIN
//! sub-dialog, Touch ID prompt) that have to drive Flutter UI.

use crate::bus::Event;
use crate::security::hardware_vault_seal_prompt;
use crate::security::hardware_vault_unlock_prompt;
use crate::security::tier_machine::{instance_dispatch, TierEvent, UnlockFailureReason};
use crate::security::SecurityTier;

/// Canonical SecretStore id the per-tier orchestrators stage
/// the resolved DB key under just before emitting
/// `UnlockSucceeded`. The Dart bus listener subscribed to
/// `TierStateChanged.unlocked` takes the bytes via
/// `secrets_take` (atomic read-and-remove) and hands them to
/// drift; the SecretStore entry is gone after the take.
///
/// Plaintext stages an empty buffer so the listener's
/// `secrets_take` call returns the empty `Vec` consistent
/// with the "no key" tier shape.
pub const TIER_UNLOCK_KEY_ID: &str = "tier.unlock.key";

/// Result of a per-tier unlock attempt. The bytes never cross
/// FRB — `Staged` means the key sits in the SecretStore under
/// [`TIER_UNLOCK_KEY_ID`] and the Dart [`TierUnlockedListener`]
/// (subscribed to `BusTopic::Tier`) will take them via
/// `secrets_take` on the same `TierStateChanged.unlocked` event
/// the orchestrator just emitted.
///
/// The dialog tiers (L2/L3/Paranoid) interpret the variants for
/// their UI:
///   - `Staged` → close the dialog, the listener owns the rest.
///   - `WrongSecret` → keep the dialog open, surface the
///     wrong-password label, decrement the rate-limiter.
///   - `Cancelled` → user dismissed an inner prompt (hardware
///     vault PIN sub-dialog); the outer dialog stays open.
///   - `PluginError` → unrecoverable plugin/hardware failure;
///     close + fall back to plaintext.
///   - `Corruption` → on-disk KDF/gate state unreadable; close
///     + route through corruption recovery.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UnlockOutcome {
    Staged,
    WrongSecret,
    Cancelled,
    PluginError(String),
    Corruption(String),
}

/// Stage the resolved key in the SecretStore under the
/// canonical id so the Dart bus listener can take it. Called
/// just before `UnlockSucceeded` dispatches; the listener's
/// `secrets_take` runs on the bus event handler.
fn stage_key(bytes: &[u8]) {
    crate::app::instance()
        .secrets
        .put(TIER_UNLOCK_KEY_ID, bytes);
}

/// Storage key for the L1 / L2 DB encryption key in the OS
/// keychain. Mirrors the Dart-era
/// `SecureKeyStorage._keyName` const — both implementations
/// must agree on the slot or an existing install would lose
/// access to its encrypted DB after the unlock cascade flips
/// to the orchestrator.
const ENCRYPTION_KEY_SLOT: &str = "letsflutssh_encryption_key";

/// Stable rate-limiter ids for the Rust-side gates wired into
/// [`unlock_keychain_with_password`] and [`unlock_paranoid`]. Stored
/// in the process-singleton `app::instance().rate_limiters`
/// registry; survive the lifetime of the process and reset on
/// `record_success` (correct password lands).
const L2_UNLOCK_LIMITER_ID: &str = "tier_unlock.keychain_with_password";
const PARANOID_UNLOCK_LIMITER_ID: &str = "tier_unlock.paranoid";

/// Plaintext tier — no secret, no plugin call, no user prompt.
/// Idempotent: re-entry while already `Unlocked` is a no-op
/// because both dispatches are state-guarded.
///
/// 1. Set the active tier to Plaintext + dispatch
///    `UnlockRequested` (state goes to `Unlocking`).
/// 2. Dispatch `UnlockSucceeded` (state goes to `Unlocked`,
///    publishes `BusEvent::TierStateChanged { wire_name:
///    "unlocked" }`).
///
/// The Dart subscriber sees the Unlocked event and runs the
/// drift-open step with an empty key (`AppDatabase` opens the
/// file as plaintext).
pub fn unlock_plaintext() {
    instance_dispatch(SecurityTier::Plaintext, &TierEvent::UnlockRequested);
    // Stage an empty buffer so the Dart `TierUnlockedListener`
    // sees the same "take the staged key, hand it to drift"
    // shape across every tier — drift opens with empty bytes
    // for the plaintext path.
    stage_key(&[]);
    instance_dispatch(SecurityTier::Plaintext, &TierEvent::UnlockSucceeded);
}

/// Keychain tier (L1) — read the DB encryption key directly from
/// the OS keychain via [`lfs_os_security::secure_key_storage`],
/// stage it under [`TIER_UNLOCK_KEY_ID`], dispatch the cascade.
///
/// 1. Set tier to Keychain + dispatch `UnlockRequested`.
/// 2. Call `secure_key_storage::read(ENCRYPTION_KEY_SLOT)` —
///    cfg-dispatched per platform (libsecret on Linux, SecItem on
///    Apple, CredRead on Windows, AndroidKeyStore JNI on Android).
/// 3. On a hit, stage the bytes + dispatch `UnlockSucceeded`;
///    on miss / backend error, dispatch
///    `UnlockFailed { PluginUnavailable }`.
///
/// Plaintext discipline: the key bytes never cross FRB on the
/// return value — the Dart [`TierUnlockedListener`] takes them
/// out of the SecretStore on its `unlocked` handler. The
/// caller branches on the [`UnlockOutcome`] discriminant only.
pub async fn unlock_keychain() -> UnlockOutcome {
    instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockRequested);

    let read_outcome = lfs_os_security::secure_key_storage::read(ENCRYPTION_KEY_SLOT).await;

    match read_outcome {
        Ok(Some(bytes)) if !bytes.is_empty() => {
            stage_key(&bytes);
            instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockSucceeded);
            UnlockOutcome::Staged
        }
        Ok(_) => {
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: "missing_keychain_entry".into(),
                    },
                },
            );
            UnlockOutcome::PluginError("missing_keychain_entry".into())
        }
        Err(e) => {
            let code = format!("keychain_read_failed: {e}");
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable { code: code.clone() },
                },
            );
            UnlockOutcome::PluginError(code)
        }
    }
}

/// KeychainWithPassword tier (L2) — verify the typed user
/// password through the on-disk gate (HMAC-SHA-256 against the
/// stored salt + the keychain pepper), then on success read
/// the DB encryption key from the OS keychain and return its
/// bytes. Dispatches the cascade events along the way; emits
/// `UnlockFailed { WrongSecret }` on gate-mismatch and
/// `UnlockFailed { PluginUnavailable }` on missing keychain
/// entry.
///
/// The Dart caller owns the unlock dialog UI (rate-limit
/// countdown, biometric option, "forgot password" reset);
/// after the user submits the password the caller invokes this
/// orchestrator to drive the verify + key-read + cascade
/// emission in one FRB hop.
///
/// Reads the support dir from the pinned singleton — caller
/// must have invoked `master_password_init` at app startup
/// (the L2 gate shares the same support-dir pin since both
/// store on-disk state under the same root).
pub async fn unlock_keychain_with_password(password: String) -> UnlockOutcome {
    instance_dispatch(
        SecurityTier::KeychainWithPassword,
        &TierEvent::UnlockRequested,
    );

    // Rate-limit gate. The Dart unlock dialog's countdown was the
    // only brake on this verify path — a programmatic FRB caller
    // could fire `unlock_keychain_with_password` in a tight loop
    // and brute-force the L2 gate password (4-12 chars typical) at
    // wall-clock speed. The InMemoryRateLimiter applies the same
    // exponential schedule (1, 5, 15, 30, 60s cap) the Dart-side
    // limiter used. The persisted variant lives on disk and is
    // owned by the L2 gate; the in-memory mirror here is the
    // boundary-level gate that catches direct callers.
    let limiters = &crate::app::instance().rate_limiters;
    let l2_status = limiters.status(L2_UNLOCK_LIMITER_ID);
    if l2_status.is_locked() {
        instance_dispatch(
            SecurityTier::KeychainWithPassword,
            &TierEvent::UnlockFailed {
                reason: UnlockFailureReason::WrongSecret,
            },
        );
        return UnlockOutcome::WrongSecret;
    }

    let support_dir = crate::security::master_password::pinned_support_dir();
    let verify_result =
        crate::security::keychain_password_gate_actor::verify_password(support_dir, &password)
            .await;

    let verified = match verify_result {
        Ok(b) => b,
        Err(detail) => {
            instance_dispatch(
                SecurityTier::KeychainWithPassword,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::Corruption {
                        detail: detail.clone(),
                    },
                },
            );
            return UnlockOutcome::Corruption(detail);
        }
    };

    if !verified {
        limiters.record_failure(L2_UNLOCK_LIMITER_ID);
        instance_dispatch(
            SecurityTier::KeychainWithPassword,
            &TierEvent::UnlockFailed {
                reason: UnlockFailureReason::WrongSecret,
            },
        );
        return UnlockOutcome::WrongSecret;
    }
    limiters.record_success(L2_UNLOCK_LIMITER_ID);

    // Password verified — read the DB encryption key directly
    // from the OS keychain.
    match lfs_os_security::secure_key_storage::read(ENCRYPTION_KEY_SLOT).await {
        Ok(Some(bytes)) if !bytes.is_empty() => {
            stage_key(&bytes);
            instance_dispatch(
                SecurityTier::KeychainWithPassword,
                &TierEvent::UnlockSucceeded,
            );
            UnlockOutcome::Staged
        }
        Ok(_) => {
            instance_dispatch(
                SecurityTier::KeychainWithPassword,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: "missing_keychain_entry_after_verify".into(),
                    },
                },
            );
            UnlockOutcome::PluginError("missing_keychain_entry_after_verify".into())
        }
        Err(e) => {
            let code = format!("keychain_read_failed: {e}");
            instance_dispatch(
                SecurityTier::KeychainWithPassword,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable { code: code.clone() },
                },
            );
            UnlockOutcome::PluginError(code)
        }
    }
}

/// Paranoid tier — derive the DB key from the typed master
/// password via Argon2id; dispatch the cascade events along
/// the way; return the key bytes on success or `None` on a
/// wrong password / corrupted KDF record.
///
/// The Dart caller owns the unlock dialog UI (rate-limit
/// countdown, "forgot password" reset path, biometric option
/// where applicable); after the user submits the password the
/// caller invokes this orchestrator to drive the verify +
/// cascade emission in one FRB hop.
///
/// `support_dir` is read from the pinned singleton inside the
/// `master_password` FRB layer (see `master_password_init`).
/// `password` crosses FRB once on the way in; the key bytes
/// cross once on the way out for the Dart caller to hand to
/// drift.
pub async fn unlock_paranoid(password: String) -> UnlockOutcome {
    instance_dispatch(SecurityTier::Paranoid, &TierEvent::UnlockRequested);

    // In-memory rate-limit gate. Argon2id at production params
    // already costs ~400-1500ms per attempt, so a brute-force on
    // the typed master password is bounded by KDF cost — but the
    // Dart dialog's exponential-cooldown brake made that bound
    // tighter and was the only enforcement. A direct FRB caller
    // could otherwise fire `unlock_paranoid` in a tight loop and
    // pay only the KDF cost. In-memory (not persisted) per the
    // tier docstring — Paranoid sessions are short-lived and the
    // limiter does not need to survive a process restart.
    let limiters = &crate::app::instance().rate_limiters;
    let p_status = limiters.status(PARANOID_UNLOCK_LIMITER_ID);
    if p_status.is_locked() {
        instance_dispatch(
            SecurityTier::Paranoid,
            &TierEvent::UnlockFailed {
                reason: UnlockFailureReason::WrongSecret,
            },
        );
        return UnlockOutcome::WrongSecret;
    }

    // Argon2id is CPU + memory heavy (400-1500ms wall-clock at
    // production profile); spawn_blocking frees the FRB worker
    // for the duration. The pinned support_dir lives inside the
    // `master_password` singleton (set at startup via
    // `master_password::pin_support_dir`).
    let key = tokio::task::spawn_blocking(move || {
        let path = crate::security::master_password::pinned_support_dir();
        crate::security::master_password::verify_and_derive(path, &password)
    })
    .await;

    match key {
        Ok(Ok(Some(bytes))) if !bytes.is_empty() => {
            limiters.record_success(PARANOID_UNLOCK_LIMITER_ID);
            stage_key(&bytes);
            instance_dispatch(SecurityTier::Paranoid, &TierEvent::UnlockSucceeded);
            UnlockOutcome::Staged
        }
        Ok(Ok(_)) => {
            limiters.record_failure(PARANOID_UNLOCK_LIMITER_ID);
            instance_dispatch(
                SecurityTier::Paranoid,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::WrongSecret,
                },
            );
            UnlockOutcome::WrongSecret
        }
        Ok(Err(detail)) => {
            instance_dispatch(
                SecurityTier::Paranoid,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::Corruption {
                        detail: detail.clone(),
                    },
                },
            );
            UnlockOutcome::Corruption(detail)
        }
        Err(_) => {
            let detail = "Argon2id task panicked".to_string();
            instance_dispatch(
                SecurityTier::Paranoid,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::Corruption {
                        detail: detail.clone(),
                    },
                },
            );
            UnlockOutcome::Corruption(detail)
        }
    }
}

/// Hardware tier (L3) — unseal the DB key via the platform
/// hardware vault (Linux TPM via `tpm2-tools`, Apple Secure
/// Enclave / Android StrongBox / Windows Hello via method
/// channel). Dispatches the cascade events along the way;
/// returns the unsealed key bytes on success or `None` on
/// wrong PIN / cancelled dialog / plugin failure.
///
/// `pin` is the typed user secret for the password-modifier
/// variant; pass `None` for the passwordless variant where
/// the vault was sealed without a user secret.
///
/// The Dart caller owns the L3 unlock dialog UI (PIN input,
/// rate-limit countdown, biometric option, "forgot PIN" reset)
/// and the platform channel call itself; the orchestrator
/// publishes a `HardwareVaultUnlockPromptRequest` and the
/// `HardwareVaultUnlockPromptListener` Dart subscriber calls
/// `HardwareTierVault.read(pin)` which fans out per-platform.
pub async fn unlock_hardware(pin: Option<String>) -> UnlockOutcome {
    instance_dispatch(SecurityTier::Hardware, &TierEvent::UnlockRequested);

    let prompt_id = generate_prompt_id();
    let receiver = hardware_vault_unlock_prompt::instance().register(prompt_id.clone());
    crate::app::instance()
        .bus
        .publish(Event::HardwareVaultUnlockPromptRequest {
            prompt_id: prompt_id.clone(),
            pin,
        });

    match receiver.await {
        Ok(Ok(Some(bytes))) if !bytes.is_empty() => {
            stage_key(&bytes);
            instance_dispatch(SecurityTier::Hardware, &TierEvent::UnlockSucceeded);
            UnlockOutcome::Staged
        }
        Ok(Ok(_)) => {
            instance_dispatch(
                SecurityTier::Hardware,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::WrongSecret,
                },
            );
            UnlockOutcome::WrongSecret
        }
        Ok(Err(detail)) => {
            instance_dispatch(
                SecurityTier::Hardware,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: detail.clone(),
                    },
                },
            );
            UnlockOutcome::PluginError(detail)
        }
        Err(_) => {
            hardware_vault_unlock_prompt::instance().cancel(&prompt_id);
            instance_dispatch(
                SecurityTier::Hardware,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: "hardware_vault_prompt_cancelled".into(),
                    },
                },
            );
            UnlockOutcome::PluginError("hardware_vault_prompt_cancelled".into())
        }
    }
}

// ── First-launch orchestrators ─────────────────────────────────
//
// Symmetric with the unlock orchestrators above — instead of
// recovering the DB key from on-disk state, they generate a fresh
// key + persist it through the per-tier mechanism (Argon2id KDF,
// OS keychain, hardware vault) + stage in the SecretStore + emit
// the cascade. The Dart `TierUnlockedListener` runs the same
// post-unlock cascade (caches, drift open, securityStateProvider,
// config persist) for both paths so the Dart-side first-launch
// helpers shrink to "dispatch + await listener".

/// First-launch L0 (Plaintext). No secret, no plugin call. Stages
/// the empty buffer + emits the cascade so the listener opens the
/// DB unencrypted via `ensureRustDbOpen(key: empty)`.
pub fn first_launch_plaintext() {
    instance_dispatch(SecurityTier::Plaintext, &TierEvent::UnlockRequested);
    stage_key(&[]);
    instance_dispatch(SecurityTier::Plaintext, &TierEvent::UnlockSucceeded);
}

/// First-launch Paranoid. Runs `master_password::enable` (Argon2id +
/// writes `credentials.kdf` + `credentials.verify` atomically) then
/// stages the derived key + emits the cascade.
pub async fn first_launch_paranoid(password: String) -> UnlockOutcome {
    instance_dispatch(SecurityTier::Paranoid, &TierEvent::UnlockRequested);
    let result = tokio::task::spawn_blocking(move || {
        let path = crate::security::master_password::pinned_support_dir();
        crate::security::master_password::enable(
            path,
            &password,
            &crate::security::master_password::KdfParams::defaults(),
        )
    })
    .await;
    let detail = match result {
        Ok(Ok(bytes)) if !bytes.is_empty() => {
            stage_key(&bytes);
            instance_dispatch(SecurityTier::Paranoid, &TierEvent::UnlockSucceeded);
            return UnlockOutcome::Staged;
        }
        Ok(Ok(_)) => "master_password::enable returned empty key".into(),
        Ok(Err(e)) => e,
        Err(_) => "Argon2id task panicked".into(),
    };
    instance_dispatch(
        SecurityTier::Paranoid,
        &TierEvent::UnlockFailed {
            reason: UnlockFailureReason::Corruption {
                detail: detail.clone(),
            },
        },
    );
    UnlockOutcome::Corruption(detail)
}

/// First-launch L1 (Keychain). Generates a random AES-GCM key,
/// writes it directly to the OS keychain via
/// [`lfs_os_security::secure_key_storage::write`], then stages
/// the bytes + emits the cascade. On a write failure dispatches
/// `UnlockFailed { PluginUnavailable }` so the caller falls back
/// to plaintext.
pub async fn first_launch_keychain() -> UnlockOutcome {
    instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockRequested);
    let key = crate::crypto::aes_gcm_random_key();
    match write_to_keychain(&key).await {
        Ok(()) => {
            stage_key(&key);
            instance_dispatch(SecurityTier::Keychain, &TierEvent::UnlockSucceeded);
            UnlockOutcome::Staged
        }
        Err(detail) => {
            instance_dispatch(
                SecurityTier::Keychain,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: detail.clone(),
                    },
                },
            );
            UnlockOutcome::PluginError(detail)
        }
    }
}

/// First-launch L2 (KeychainWithPassword). Sets the gate password
/// (Rust-side actor writes the salt + verifier files), generates a
/// random key, writes it to the OS keychain via the Dart
/// subscriber, stages the bytes + emits the cascade.
pub async fn first_launch_keychain_with_password(password: String) -> UnlockOutcome {
    instance_dispatch(
        SecurityTier::KeychainWithPassword,
        &TierEvent::UnlockRequested,
    );
    let support_dir = crate::security::master_password::pinned_support_dir();
    if let Err(detail) =
        crate::security::keychain_password_gate_actor::set_password(support_dir, &password).await
    {
        instance_dispatch(
            SecurityTier::KeychainWithPassword,
            &TierEvent::UnlockFailed {
                reason: UnlockFailureReason::Corruption {
                    detail: detail.clone(),
                },
            },
        );
        return UnlockOutcome::Corruption(detail);
    }
    let key = crate::crypto::aes_gcm_random_key();
    match write_to_keychain(&key).await {
        Ok(()) => {
            stage_key(&key);
            instance_dispatch(
                SecurityTier::KeychainWithPassword,
                &TierEvent::UnlockSucceeded,
            );
            UnlockOutcome::Staged
        }
        Err(detail) => {
            // Roll back the gate so a follow-up retry sees a
            // fresh "not configured" state instead of stale
            // verifier files keyed off a password that the user
            // can't reproduce after the failed first-launch.
            let _ = crate::security::keychain_password_gate_actor::clear(support_dir).await;
            instance_dispatch(
                SecurityTier::KeychainWithPassword,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: detail.clone(),
                    },
                },
            );
            UnlockOutcome::PluginError(detail)
        }
    }
}

/// First-launch L3 (Hardware). Generates a fresh AES-GCM key,
/// publishes a `HardwareVaultSealPromptRequest` so the Dart
/// subscriber wraps it via `HardwareTierVault.store(dbKey: bytes,
/// pin: pin)`, stages the same bytes + emits the cascade. `pin`
/// is `None` for the passwordless variant.
pub async fn first_launch_hardware(pin: Option<String>) -> UnlockOutcome {
    instance_dispatch(SecurityTier::Hardware, &TierEvent::UnlockRequested);
    let key = crate::crypto::aes_gcm_random_key();
    let prompt_id = generate_prompt_id();
    let receiver = hardware_vault_seal_prompt::instance().register(prompt_id.clone());
    crate::app::instance()
        .bus
        .publish(Event::HardwareVaultSealPromptRequest {
            prompt_id: prompt_id.clone(),
            // The seal-prompt event still carries the plaintext DB key
            // across the broadcast bus — the bus-event redesign is the
            // separate sub-arc that replaces this with a SecretRef
            // handle. Until then `(*key).clone()` is needed to satisfy
            // the `Vec<u8>` field; `key` is now `Zeroizing<Vec<u8>>`.
            db_key: (*key).clone(),
            pin,
        });
    let outcome = match receiver.await {
        Ok(Ok(())) => {
            stage_key(&key);
            instance_dispatch(SecurityTier::Hardware, &TierEvent::UnlockSucceeded);
            UnlockOutcome::Staged
        }
        Ok(Err(detail)) => {
            instance_dispatch(
                SecurityTier::Hardware,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: detail.clone(),
                    },
                },
            );
            UnlockOutcome::PluginError(detail)
        }
        Err(_) => {
            hardware_vault_seal_prompt::instance().cancel(&prompt_id);
            let detail = "hardware_vault_seal_prompt_cancelled".to_string();
            instance_dispatch(
                SecurityTier::Hardware,
                &TierEvent::UnlockFailed {
                    reason: UnlockFailureReason::PluginUnavailable {
                        code: detail.clone(),
                    },
                },
            );
            UnlockOutcome::PluginError(detail)
        }
    };
    outcome
}

/// Direct keychain write via [`lfs_os_security::secure_key_storage`].
/// Returns `Ok(())` on success or `Err(plugin_code)` on failure.
async fn write_to_keychain(bytes: &[u8]) -> Result<(), String> {
    lfs_os_security::secure_key_storage::write(ENCRYPTION_KEY_SLOT, bytes)
        .await
        .map_err(|e| format!("keychain_write_failed: {e}"))
}

/// Stage [`bytes`] in the SecretStore + drive the tier machine
/// `Locked → Unlocking → Unlocked` cascade for [`tier`] without
/// going through a per-tier verify (gate / Argon2id /
/// keychain-read / hardware unseal). Used by the biometric
/// fast-path on L2/L3 — the bytes come from the OS-managed
/// `BiometricKeyVault` (Dart-side flutter plugin), so the
/// per-tier orchestrator's verify step is bypassed; the
/// cascade still has to fire so the [`TierUnlockedListener`]
/// runs the same post-unlock cascade (caches, drift open,
/// config persist) as the typed-secret path.
///
/// Idempotent against the tier-machine state guards. Caller is
/// responsible for ensuring the bytes really do unlock the DB
/// (the biometric vault is keyed off the same DB key that the
/// keychain / hardware vault stores).
pub fn commit_biometric_unlock(tier: SecurityTier, bytes: &[u8]) {
    instance_dispatch(tier, &TierEvent::UnlockRequested);
    stage_key(bytes);
    instance_dispatch(tier, &TierEvent::UnlockSucceeded);
}

/// Cancel an in-flight unlock attempt for [`tier`]. Dispatches
/// `UnlockFailed { UserCancelled }` so the tier machine flips
/// from `Unlocking` back to `Locked` instead of staying wedged
/// in the half-state when the user dismisses the dialog
/// without submitting.
///
/// Idempotent — the dispatch is state-guarded; calling against
/// a tier that's already `Locked` is a no-op. The Dart unlock
/// dialog calls this on its dismiss handler so every
/// `request_unlock` lands a paired terminal-state event.
pub fn cancel_unlock(tier: SecurityTier) {
    instance_dispatch(
        tier,
        &TierEvent::UnlockFailed {
            reason: UnlockFailureReason::UserCancelled,
        },
    );
}

/// UUIDv4-shaped prompt id. Mirrors the same id-shape every
/// other prompt registry caller uses.
fn generate_prompt_id() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::tier_machine::{instance, TierState};

    #[test]
    fn unlock_plaintext_self_advances_to_unlocked() {
        // Drive the singleton through the cascade. Other tests
        // in this binary touch the same singleton so we don't
        // assert from any starting state — only that the final
        // state is Unlocked under the Plaintext tier.
        unlock_plaintext();
        let m = instance();
        let g = m.lock().expect("tier machine mutex");
        assert_eq!(g.state(), TierState::Unlocked);
        assert_eq!(g.tier(), SecurityTier::Plaintext);
    }
}
