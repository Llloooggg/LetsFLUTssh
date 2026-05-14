//! Vault-recovery orchestrator — bundles the destructive sequence the
//! Dart `SecurityInitController` used to compose as four separate FRB
//! hops + one Riverpod provider patch into one Rust-side transaction.
//!
//! The user-facing recovery state machine has three entry points the
//! Dart shell still owns (each surfaces a different dialog whose
//! prompts are inherently Flutter widgets):
//!
//! 1. **Legacy state detected** — `detect_legacy_state` returns the
//!    decision the controller used to compute by calling three FRB
//!    functions (`migration_config_target_version`,
//!    `migration_config_version_on_disk`, `wipe_has_any_state`) +
//!    inspecting Dart-side `AppConfig.security`. Bundled here so the
//!    detection logic lives one place.
//! 2. **Vault state missing** — the controller probes the DB readability
//!    first; on failure it shows the corrupt-DB dialog and the user
//!    picks reset / retry / exit. The Dart side keeps the dialog,
//!    Rust owns the destructive sequence the reset arm triggers.
//! 3. **Wipe and restart from scratch** — `run_destructive_reset`
//!    composes the cascade (DB close → file sweep → keychain purge
//!    → hardware-vault primary clear → hardware-vault biometric
//!    overlay clear → return a structured outcome) atomically. The
//!    Dart caller awaits one FRB call instead of sequencing five
//!    separate hops; partial-failure handling lives Rust-side.
//!
//! ## Ordering invariants (load-bearing)
//!
//! - **DB close MUST precede file sweep.** On Windows, an open
//!   SQLCipher handle keeps `letsflutssh.db-wal` locked; the sweep
//!   would then leave the WAL on disk and the next launch would
//!   surface a half-wiped state.
//! - **File sweep + native vault clear MUST precede config reset.**
//!   `config.json` is one of the managed files; the Rust caller writes
//!   the new `security: None` config back AFTER the sweep wipes the
//!   old file, so a mid-sequence crash leaves a fresh empty config
//!   the next launch's wizard can replace, not a stale tier-attached
//!   record over a wiped vault.
//! - **Hardware-vault clear is best-effort and runs AFTER the file
//!   sweep.** The sweep deletes the wrapped-key envelope file from
//!   disk; the per-platform `clear` call drops the persisted
//!   hardware key (Apple SE entry, AndroidKeyStore alias, Windows
//!   CNG persisted key) the file used to wrap. Linux has no
//!   persistent hardware key — the TPM2 envelope is fully on-disk —
//!   so `clear` there is a redundant file-removal that succeeds
//!   trivially after the sweep already dropped the file.
//! - **First-launch re-init MUST run after the cascade returns.** The
//!   wizard is a Flutter widget the Dart caller surfaces; this module
//!   does NOT run it. Callers await `run_destructive_reset` and then
//!   surface the wizard themselves with the freshly-cleared state.
//!
//! ## Why not bus events
//!
//! The destructive cascade is synchronous to completion — typical
//! wall-clock is <1 s on every supported platform (the slowest step
//! is the keychain purge on Linux, dominated by zbus round-trips).
//! Emitting per-phase progress events would cost more in FRB
//! marshalling than it saves in user-perceived feedback. The Rust
//! side logs each phase via `lfs_core::app_log` so a support trace
//! still reconstructs the timeline; Dart subscribes to `CoreLog`
//! topic the same way it does for every other Rust subsystem.

use std::path::Path;

use uuid::Uuid;

use crate::bus::Event;
use crate::security::recovery_prompt::{self, RecoveryPromptKind, RecoveryPromptResponse};
use crate::security::{wipe, wipe_keychain};

/// Branch the Dart caller takes after the orchestrator hands control
/// back. The Rust orchestrator owns the destructive cascade itself —
/// when this variant lands the file sweep, keychain purge, and
/// hardware-vault clear have already run, so the Dart side only
/// needs to re-run the post-cascade re-init (first-launch wizard,
/// retry-under-different-tier path, or quit).
///
/// Typed (not stringly-keyed) so a regression that adds a fourth
/// branch lights up every match site instead of silently falling
/// through.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryOutcome {
    /// User picked Reset. The destructive cascade ran inside this
    /// orchestrator call; the Dart caller drops back to the
    /// first-launch wizard with a freshly-cleared support_dir.
    WipedAndRestarted,
    /// User picked Quit. Dart side calls `SystemNavigator.pop` +
    /// `exit(0)` — those surfaces are Flutter-only and stay
    /// Dart-side, the orchestrator just signals which outcome to
    /// follow.
    UserExited,
    /// User picked TryOtherTier (only offered on the DB-corrupt
    /// and vault-state-missing prompts). The Dart caller runs
    /// `_retryUnlockUnderDifferentTier` — clearing the
    /// `AppConfig.security` field, reinvoking the unlock cascade
    /// under the legacy-infer path, capped by
    /// `_corruptionRetries`. The orchestrator does NOT touch the
    /// support_dir on this branch — the retry path needs the DB +
    /// vault state intact to attempt a different unlock route.
    Continued,
}

/// Outcome of [`detect_legacy_state`]. Mirrors the Dart-side
/// `legacyConfig || orphanArtefacts` decision: a true value in
/// either field means the bootstrap path must surface the
/// `TierResetDialog` before running the regular unlock cascade.
///
/// Kept as a struct (not a single `bool`) so the Dart caller can log
/// which signal fired — `legacy_config` and `orphan_artefacts` carry
/// different meaning for support diagnostics (legacy schema vs. a
/// fresh install on top of an old support-dir).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LegacyStateDetection {
    /// `config.json` is at a schema version below the build's
    /// target — the migration runner already had a chance to walk
    /// the chain; if the field is still true here the install
    /// genuinely predates the current schema floor.
    pub legacy_config: bool,
    /// At least one **security-bearing** managed artefact lives in
    /// the app-support dir while `AppConfig.security` is `None` —
    /// signals an install whose security config was dropped (manual
    /// edit, partial migration, lost keychain) and would otherwise
    /// fall into the plaintext branch silently.
    pub orphan_artefacts: bool,
    /// Probed schema version of `config.json` — `-1` when the file
    /// is absent (fresh install). Surfaced so the Dart caller can
    /// log it under the `legacy_config` branch without re-reading
    /// the same probe.
    pub config_version_on_disk: i32,
    /// Build's target schema version for `config.json` — the
    /// `< target` comparison happens Rust-side so a future schema
    /// bump doesn't leak the threshold into Dart.
    pub config_target_version: i32,
}

impl LegacyStateDetection {
    /// True when the bootstrap path must surface the
    /// `TierResetDialog`. Mirrors the Dart-side `legacyConfig ||
    /// orphanArtefacts` predicate.
    pub fn should_prompt_reset(&self) -> bool {
        self.legacy_config || self.orphan_artefacts
    }
}

/// Probe whether the install needs a legacy-state reset prompt.
///
/// `has_current_security_config` is supplied by the Dart caller from
/// the Riverpod `configProvider.security` view: when the running
/// process already has a `SecurityConfig` snapshot in Dart memory
/// (the regular unlock path), the orphan probe short-circuits to
/// false because the orphan-artefact branch only fires when the
/// security config is `None`.
///
/// Returns the typed [`LegacyStateDetection`] regardless of outcome
/// — callers branch on [`LegacyStateDetection::should_prompt_reset`]
/// and use the auxiliary fields for diagnostic logging.
///
/// Synchronous because the underlying probes are file-existence
/// checks against `support_dir` — bounded, single-digit-ms. The FRB
/// shim wraps in `spawn_blocking` so the worker thread never stalls
/// even on the slowest filesystem.
pub fn detect_legacy_state(
    support_dir: &Path,
    has_current_security_config: bool,
) -> LegacyStateDetection {
    use crate::migration::artefacts::ConfigArtefact;
    use crate::migration::{Artefact, SchemaVersions};

    let target = SchemaVersions::CONFIG;
    // ConfigArtefact::read_version returns `-1` when the file is
    // absent (fresh install) and `Err(...)` when present but
    // unreadable. Treat any error path as `-1` for the legacy
    // decision — a corrupt config gets caught by the migration
    // runner upstream and surfaces through the fatal-error report,
    // not through this probe.
    let version_on_disk = ConfigArtefact.read_version(support_dir).unwrap_or(-1);
    let legacy_config = version_on_disk >= 0 && version_on_disk < target;
    let orphan_artefacts = !has_current_security_config && wipe::has_any_state(support_dir);
    LegacyStateDetection {
        legacy_config,
        orphan_artefacts,
        config_version_on_disk: version_on_disk,
        config_target_version: target,
    }
}

/// Report returned by [`run_destructive_reset`]. Mirrors the shape
/// of [`crate::security::wipe::FileSweepReport`] + the keychain
/// purge outcome flag, so the Dart caller can surface partial
/// failures via the same toast / logger pipeline the user-driven
/// "Reset all data" path already uses.
#[derive(Debug, Clone)]
pub struct DestructiveResetReport {
    /// Filenames the sweep removed under `support_dir`.
    pub deleted_files: Vec<String>,
    /// Filenames the sweep tried to remove but failed (locked /
    /// permission denied / disappearing mid-walk). Non-empty here
    /// is a soft failure — the caller surfaces a warning toast but
    /// does NOT abort the first-launch wizard, since the wiped
    /// state on disk is already enough to make the new install
    /// consistent.
    pub failed_files: Vec<String>,
    /// True when every managed OS-keychain key was either deleted
    /// or already absent. False when at least one entry returned
    /// an unexpected status from the platform plugin.
    pub keychain_purge_succeeded: bool,
    /// True when the per-platform hardware-vault primary key was
    /// dropped (Apple SE / AndroidKeyStore / Windows CNG persisted
    /// key, or the on-disk TPM2 envelope on Linux). Best-effort:
    /// `PlatformUnsupported` (no hardware tier on this build) and
    /// already-absent both count as success — the contract is "no
    /// vault state remains", not "we executed a delete syscall".
    pub hw_vault_cleared: bool,
    /// True when the per-platform hardware-vault biometric overlay
    /// was dropped. Same best-effort semantics as
    /// [`Self::hw_vault_cleared`].
    pub hw_vault_biometric_cleared: bool,
}

/// Compose the destructive cascade Dart used to drive across five
/// separate FRB hops + a Riverpod state patch:
///
/// 1. DB close — release the SQLCipher handle so the file sweep
///    can drop `letsflutssh.db` cleanly on Windows.
/// 2. File sweep — Rust-side [`wipe::sweep_files`] walks every
///    managed artefact + the logs directory.
/// 3. Keychain purge — Rust-side [`wipe_keychain::run`] drops every
///    OS-keychain entry the workspace audits.
/// 4. Hardware-vault primary clear — per-platform dispatch into
///    `lfs_os_security::hardware_tier_vault::clear` (Apple SE /
///    AndroidKeyStore / Windows CNG persisted key) or the in-crate
///    `hardware_tier_vault::linux::clear` (TPM2 envelope file).
///    Best-effort: a `PlatformUnsupported` or already-absent
///    outcome counts as success; only a hard backend error counts
///    as a failure and the cascade still continues.
/// 5. Hardware-vault biometric overlay clear — same dispatch shape
///    as step 4 against the `clear_biometric_password` surface.
/// 6. (Implicit) — `config.json` is in the managed-files list, so
///    step 2 leaves the install with no on-disk config. The next
///    Dart-side `configStoreInit` call seeds a fresh
///    `AppConfig.defaults` shape automatically, dropping the
///    explicit Riverpod patch the controller used to issue.
///
/// Returns the structured outcome regardless of partial failures.
/// The cascade does not abort on a sweep / keychain / hw-vault
/// failure (one stuck file or hardware backend must not block the
/// rest of the wipe); the caller surfaces the outcome via the
/// existing logging + toast paths.
pub async fn run_destructive_reset(support_dir: &Path) -> DestructiveResetReport {
    crate::app_log_warn!(
        "Recovery",
        "destructive_reset: starting cascade for support_dir={}",
        support_dir.display()
    );

    // 1. Drop the live DB handle. Idempotent on an already-closed
    //    or never-opened handle — the wipe path is reachable from
    //    cold-start before any unlock has run.
    crate::app::instance().db_close();
    crate::app_log_info!("Recovery", "destructive_reset: db_close complete");

    // 2. File sweep. Internally writes the `.wipe-pending` marker
    //    before any delete so a mid-cascade crash leaves a
    //    detectable trail the next launch picks up.
    let file_report = wipe::sweep_files(support_dir);
    crate::app_log_info!(
        "Recovery",
        "destructive_reset: sweep_files complete deleted={} failed={}",
        file_report.deleted_files.len(),
        file_report.failed_files.len()
    );

    // 3. Keychain purge — every managed alias dropped via the
    //    `lfs_os_security::secure_key_storage` actor. Async because
    //    each per-key delete awaits the platform plugin (libsecret /
    //    Keychain Services / Credential Manager / AndroidKeyStore
    //    JNI); total time is O(N keys × plugin latency).
    let kc_report = wipe_keychain::run().await;
    let kc_ok = kc_report.iter().all(|(_, o)| o.is_success());
    crate::app_log_info!(
        "Recovery",
        "destructive_reset: keychain_purge complete all_succeeded={}",
        kc_ok
    );

    // 4. Hardware-vault primary clear. Drops the persisted hardware
    //    key the wrapped-envelope file (already deleted in step 2)
    //    used to unwrap. Apple / Android / Windows release the
    //    persistent key; Linux is a redundant file-remove (file
    //    already gone from step 2 — returns `Ok(())`).
    let hw_ok = clear_hw_vault_primary(support_dir);
    crate::app_log_info!(
        "Recovery",
        "destructive_reset: hw_vault_clear complete succeeded={}",
        hw_ok
    );

    // 5. Hardware-vault biometric overlay clear. Same dispatch
    //    shape; on Linux the persistent state is the on-disk
    //    overlay file (step 2 already removed it). Apple / Android
    //    / Windows additionally drop the overlay's persistent key
    //    so a stale biometric binding cannot resurface.
    let hw_bio_ok = clear_hw_vault_biometric(support_dir);
    crate::app_log_info!(
        "Recovery",
        "destructive_reset: hw_vault_biometric_clear complete succeeded={}",
        hw_bio_ok
    );

    DestructiveResetReport {
        deleted_files: file_report.deleted_files,
        failed_files: file_report.failed_files,
        keychain_purge_succeeded: kc_ok,
        hw_vault_cleared: hw_ok,
        hw_vault_biometric_cleared: hw_bio_ok,
    }
}

/// Publish a recovery prompt onto the bus and wait for the Dart
/// caller's choice. Shared between the three orchestrator entry
/// points below.
///
/// Returns the typed [`RecoveryPromptResponse`] the Dart subscriber
/// dispatched, or `RecoveryPromptResponse::Quit` when the receiver
/// is dropped (no subscriber / wire-name decode failure / Dart
/// dismiss-without-dispatch) — the fail-safe is to NOT wipe the
/// user's data on an ambiguous outcome.
async fn await_prompt_choice(
    kind: RecoveryPromptKind,
    choices: &[RecoveryPromptResponse],
) -> RecoveryPromptResponse {
    let app = crate::app::instance();
    let prompt_id = Uuid::new_v4().to_string();
    let rx = recovery_prompt::instance().register(prompt_id.clone());
    let wire_choices: Vec<String> = choices.iter().map(|c| c.wire_name().to_string()).collect();
    app.bus.publish(Event::RecoveryPromptRequest {
        prompt_id: prompt_id.clone(),
        kind: kind.clone(),
        choices: wire_choices,
    });
    match rx.await {
        Ok(wire) => RecoveryPromptResponse::from_wire_name(&wire).unwrap_or_else(|| {
            crate::app_log_warn!(
                "Recovery",
                "recovery_prompt: unknown wire response {wire:?} — defaulting to Quit"
            );
            RecoveryPromptResponse::Quit
        }),
        Err(_) => {
            crate::app_log_warn!(
                "Recovery",
                "recovery_prompt: receiver dropped for prompt_id={prompt_id} \
                 (no subscriber / dialog dismissed) — defaulting to Quit"
            );
            RecoveryPromptResponse::Quit
        }
    }
}

/// Surface "the database integrity probe failed" to the user and
/// branch on the choice. Reused by the migration-runner failure
/// path — same dialog, same three choices, same destructive
/// cascade.
///
/// On `Reset` the destructive cascade runs Rust-side and the
/// outcome lands as [`RecoveryOutcome::WipedAndRestarted`]; the
/// Dart caller picks up first-launch re-init. On `Quit` /
/// `TryOtherTier` the cascade does NOT run — the Dart caller
/// either exits or re-attempts the unlock under a different tier
/// against the existing on-disk state.
pub async fn recovery_handle_corrupt_db(support_dir: &Path, reason: String) -> RecoveryOutcome {
    crate::app_log_warn!(
        "Recovery",
        "recovery_handle_corrupt_db: reason={reason} — publishing prompt"
    );
    let choices = [
        RecoveryPromptResponse::Reset,
        RecoveryPromptResponse::TryOtherTier,
        RecoveryPromptResponse::Quit,
    ];
    let response =
        await_prompt_choice(RecoveryPromptKind::DbCorruptDetected { reason }, &choices).await;
    match response {
        RecoveryPromptResponse::Reset => {
            run_destructive_reset(support_dir).await;
            RecoveryOutcome::WipedAndRestarted
        }
        RecoveryPromptResponse::Quit => RecoveryOutcome::UserExited,
        RecoveryPromptResponse::TryOtherTier => RecoveryOutcome::Continued,
    }
}

/// Surface "the configured tier is unreachable — vault state
/// missing" to the user and branch on the choice. Same dialog +
/// cascade as the corrupt-DB path, framed for the security-state
/// loss scenario.
pub async fn recovery_handle_vault_state_missing(
    support_dir: &Path,
    tier_label: String,
) -> RecoveryOutcome {
    crate::app_log_warn!(
        "Recovery",
        "recovery_handle_vault_state_missing: tier_label={tier_label} — publishing prompt"
    );
    let choices = [
        RecoveryPromptResponse::Reset,
        RecoveryPromptResponse::TryOtherTier,
        RecoveryPromptResponse::Quit,
    ];
    let response = await_prompt_choice(
        RecoveryPromptKind::VaultStateMissing { tier_label },
        &choices,
    )
    .await;
    match response {
        RecoveryPromptResponse::Reset => {
            run_destructive_reset(support_dir).await;
            RecoveryOutcome::WipedAndRestarted
        }
        RecoveryPromptResponse::Quit => RecoveryOutcome::UserExited,
        RecoveryPromptResponse::TryOtherTier => RecoveryOutcome::Continued,
    }
}

/// Surface "legacy state on disk detected" to the user and branch
/// on the choice. The dialog (`TierResetDialog`) offers two
/// choices — `Reset` and `Quit`; a stray `TryOtherTier` from a
/// hand-rolled subscriber maps to `Continued` so the Dart caller
/// falls through to its regular unlock path against the
/// untouched on-disk state.
pub async fn recovery_handle_legacy_state(
    support_dir: &Path,
    config_version_on_disk: i32,
    orphan_artefacts: bool,
) -> RecoveryOutcome {
    crate::app_log_warn!(
        "Recovery",
        "recovery_handle_legacy_state: config_version_on_disk={config_version_on_disk} \
         orphan_artefacts={orphan_artefacts} — publishing prompt"
    );
    let choices = [RecoveryPromptResponse::Reset, RecoveryPromptResponse::Quit];
    let response = await_prompt_choice(
        RecoveryPromptKind::LegacyStateFound {
            config_version_on_disk,
            orphan_artefacts,
        },
        &choices,
    )
    .await;
    match response {
        RecoveryPromptResponse::Reset => {
            run_destructive_reset(support_dir).await;
            RecoveryOutcome::WipedAndRestarted
        }
        RecoveryPromptResponse::Quit => RecoveryOutcome::UserExited,
        RecoveryPromptResponse::TryOtherTier => RecoveryOutcome::Continued,
    }
}

/// Best-effort dispatch into the per-platform hardware-vault
/// primary clear. Linux routes through the in-crate TPM2 module;
/// every other target routes through `lfs_os_security`. Returns
/// `true` when the backend reports success OR `PlatformUnsupported`
/// (no hardware tier compiled for this build); `false` only when
/// the backend errored on a present hardware surface.
fn clear_hw_vault_primary(support_dir: &Path) -> bool {
    let support_dir_str = support_dir.to_string_lossy();
    #[cfg(target_os = "linux")]
    {
        match crate::security::hardware_tier_vault::linux::clear(&support_dir_str) {
            Ok(()) => true,
            Err(e) => {
                crate::app_log_warn!(
                    "Recovery",
                    "destructive_reset: linux hw_vault clear failed: {}",
                    e
                );
                false
            }
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        use lfs_os_security::hardware_tier_vault::{self as hv, HardwareVaultError};
        match hv::clear(&support_dir_str) {
            Ok(()) => true,
            Err(HardwareVaultError::PlatformUnsupported) => true,
            Err(e) => {
                crate::app_log_warn!(
                    "Recovery",
                    "destructive_reset: hw_vault clear failed: {:?}",
                    e
                );
                false
            }
        }
    }
}

/// Best-effort dispatch into the per-platform hardware-vault
/// biometric-overlay clear. Same semantics as
/// [`clear_hw_vault_primary`].
fn clear_hw_vault_biometric(support_dir: &Path) -> bool {
    let support_dir_str = support_dir.to_string_lossy();
    #[cfg(target_os = "linux")]
    {
        match crate::security::hardware_tier_vault::linux::clear_biometric_password(
            &support_dir_str,
        ) {
            Ok(()) => true,
            Err(e) => {
                crate::app_log_warn!(
                    "Recovery",
                    "destructive_reset: linux hw_vault clear_biometric failed: {}",
                    e
                );
                false
            }
        }
    }
    #[cfg(not(target_os = "linux"))]
    {
        use lfs_os_security::hardware_tier_vault::{self as hv, HardwareVaultError};
        match hv::clear_biometric_password(&support_dir_str) {
            Ok(()) => true,
            Err(HardwareVaultError::PlatformUnsupported) => true,
            Err(e) => {
                crate::app_log_warn!(
                    "Recovery",
                    "destructive_reset: hw_vault clear_biometric failed: {:?}",
                    e
                );
                false
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    /// Pin the `should_prompt_reset` predicate truth table. The
    /// Dart caller branches on this directly; a regression here
    /// silently breaks bootstrap recovery.
    #[test]
    fn should_prompt_reset_truth_table() {
        let none_field = LegacyStateDetection {
            legacy_config: false,
            orphan_artefacts: false,
            config_version_on_disk: -1,
            config_target_version: 7,
        };
        assert!(!none_field.should_prompt_reset());

        let legacy_only = LegacyStateDetection {
            legacy_config: true,
            orphan_artefacts: false,
            config_version_on_disk: 3,
            config_target_version: 7,
        };
        assert!(legacy_only.should_prompt_reset());

        let orphan_only = LegacyStateDetection {
            legacy_config: false,
            orphan_artefacts: true,
            config_version_on_disk: -1,
            config_target_version: 7,
        };
        assert!(orphan_only.should_prompt_reset());

        let both = LegacyStateDetection {
            legacy_config: true,
            orphan_artefacts: true,
            config_version_on_disk: 3,
            config_target_version: 7,
        };
        assert!(both.should_prompt_reset());
    }

    /// Empty support-dir + no Dart-side security config → neither
    /// signal fires. The wizard surfaces directly because the
    /// install is fresh, not because of a legacy/orphan state.
    #[test]
    fn detect_legacy_state_empty_support_dir_yields_no_prompt() {
        let tmp = tempfile::tempdir().expect("tmp");
        let det = detect_legacy_state(tmp.path(), false);
        assert!(!det.legacy_config);
        assert!(!det.orphan_artefacts);
        assert_eq!(det.config_version_on_disk, -1);
        assert!(!det.should_prompt_reset());
    }

    /// Dart has a `SecurityConfig` in memory + the support-dir
    /// holds the expected artefacts. The orphan branch short-
    /// circuits to false even though the dir is not empty — the
    /// `has_current_security_config` gate is what blocks the
    /// false-positive here.
    #[test]
    fn detect_legacy_state_with_security_config_skips_orphan_branch() {
        let tmp = tempfile::tempdir().expect("tmp");
        // Drop one of the orphan-probe-tracked files so the
        // existence walk would surface a hit if it ran.
        fs::write(tmp.path().join("hardware_vault.bin"), b"x").unwrap();
        let det = detect_legacy_state(tmp.path(), true);
        assert!(
            !det.orphan_artefacts,
            "orphan probe must short-circuit when AppConfig.security is Some"
        );
    }

    /// No `AppConfig.security` + a security-bearing artefact on
    /// disk → orphan branch fires.
    #[test]
    fn detect_legacy_state_orphan_artefact_without_security_config_fires() {
        let tmp = tempfile::tempdir().expect("tmp");
        fs::write(tmp.path().join("hardware_vault.bin"), b"x").unwrap();
        let det = detect_legacy_state(tmp.path(), false);
        assert!(det.orphan_artefacts);
        assert!(det.should_prompt_reset());
    }

    /// Pin the cascade contract — `run_destructive_reset` must
    /// remove every managed file the sweep covers and leave the
    /// directory in a state where neither legacy probe fires on a
    /// follow-up call. Mirrors the integration-style "wipe and
    /// re-probe" pattern the Dart bootstrap follows.
    #[tokio::test]
    async fn run_destructive_reset_wipes_managed_files() {
        // `run_destructive_reset` touches `crate::app::instance()`
        // for the SecretStore clear + db_close; the process-wide
        // singleton needs initialising before the cascade runs.
        // Idempotent on a repeat call across tests in the same
        // process.
        let _ = crate::app::init();
        let tmp = tempfile::tempdir().expect("tmp");
        let p = tmp.path();
        // Seed the dir with one file from each managed bucket so
        // the sweep has something to delete in every category.
        fs::write(p.join("config.json"), b"{}").unwrap();
        fs::write(p.join("hardware_vault.bin"), b"x").unwrap();
        fs::write(p.join("credentials.kdf"), b"x").unwrap();

        let report = run_destructive_reset(p).await;

        // Every seeded file is reported as deleted (or already
        // absent — sweep_files only records files it found and
        // tried to delete; treat the contract as "the path no
        // longer exists" rather than name-equality).
        assert!(!p.join("config.json").exists());
        assert!(!p.join("hardware_vault.bin").exists());
        assert!(!p.join("credentials.kdf").exists());
        // Cascade should report at least these three deletions.
        // Use `>=` because the sweep also probes other managed
        // names that happened to not exist on this run.
        assert!(report.deleted_files.len() >= 3);
        // Hardware-vault clear runs on every target — Linux is a
        // file-remove against the already-swept envelope (succeeds);
        // Apple / Android / Windows surface `PlatformUnsupported`
        // under cargo test (no hardware backend available in the
        // workspace harness) which the helper still counts as
        // success. Either way the boolean is true.
        assert!(report.hw_vault_cleared);
        assert!(report.hw_vault_biometric_cleared);
        // Wipe-pending marker cleared at the end of the cascade
        // so the next launch does not loop back into resume-wipe.
        assert!(!wipe::has_pending_wipe(p));
        // Follow-up legacy probe — neither flag should fire after
        // the cascade has cleared the support-dir.
        let det = detect_legacy_state(p, false);
        assert!(!det.legacy_config);
        assert!(!det.orphan_artefacts);
    }

    /// `run_destructive_reset` on an already-clean dir is a no-op
    /// from the file-deletion angle but still drops the SecretStore
    /// + the DB handle, and the report shape stays well-formed
    /// (empty `deleted_files`, no failures).
    #[tokio::test]
    async fn run_destructive_reset_on_clean_dir_returns_empty_report() {
        let _ = crate::app::init();
        let tmp = tempfile::tempdir().expect("tmp");
        let report = run_destructive_reset(tmp.path()).await;
        assert!(report.deleted_files.is_empty());
        assert!(report.failed_files.is_empty());
        // Idempotent across the hw-vault arms too — clearing
        // an already-empty support_dir leaves both flags true
        // (no backend state to drop ⇒ success).
        assert!(report.hw_vault_cleared);
        assert!(report.hw_vault_biometric_cleared);
    }

    // ─── Orchestrator state-machine entry points ─────────────────
    // The three `recovery_handle_*` entry points publish a
    // `RecoveryPromptRequest` event and await the receiver. The
    // tests below stand in for the Dart subscriber by spawning a
    // task that subscribes to the bus, picks the published event
    // up, and resolves the matching prompt id through the
    // registry — driving each `RecoveryOutcome` branch.

    use crate::bus::{Event, EventTopic};
    use crate::security::recovery_prompt::{self, RecoveryPromptResponse};

    /// Serializes every test that drives the orchestrator end-to-
    /// end. `recovery_prompt::instance()` + `app::init().bus` are
    /// process-wide singletons across `#[tokio::test]` runs; without
    /// the lock parallel tests' driver tasks race each other into
    /// the wrong prompt id and the awaiting handler stalls
    /// indefinitely. Mirror of `AUTOLOCK_TEST_LOCK` in `bus.rs`.
    static RECOVERY_TEST_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    /// Drive one orchestrator round-trip — subscribe to the bus,
    /// dispatch the chosen response back through the prompt
    /// registry the moment the event lands. Mirrors what the
    /// Dart `RecoveryPromptListener` does in production.
    async fn drive_dart_response(response: RecoveryPromptResponse) -> tokio::task::JoinHandle<()> {
        let app = crate::app::init();
        let mut rx = app.bus.subscribe(EventTopic::SecurityPrompt);
        tokio::spawn(async move {
            loop {
                match rx.recv().await {
                    Ok(Event::RecoveryPromptRequest { prompt_id, .. }) => {
                        recovery_prompt::instance()
                            .resolve(&prompt_id, response.wire_name().to_string());
                        return;
                    }
                    Ok(_) => continue,
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(_) => return,
                }
            }
        })
    }

    #[tokio::test]
    async fn recovery_handle_corrupt_db_reset_wipes_and_returns_wiped() {
        let _g = RECOVERY_TEST_LOCK.lock().await;
        let _ = crate::app::init();
        let tmp = tempfile::tempdir().expect("tmp");
        let p = tmp.path();
        fs::write(p.join("credentials.kdf"), b"x").unwrap();
        let driver = drive_dart_response(RecoveryPromptResponse::Reset).await;
        let outcome = recovery_handle_corrupt_db(p, "probe failed".into()).await;
        driver.await.unwrap();
        assert_eq!(outcome, RecoveryOutcome::WipedAndRestarted);
        assert!(!p.join("credentials.kdf").exists());
    }

    #[tokio::test]
    async fn recovery_handle_corrupt_db_quit_returns_user_exited() {
        let _g = RECOVERY_TEST_LOCK.lock().await;
        let _ = crate::app::init();
        let tmp = tempfile::tempdir().expect("tmp");
        let p = tmp.path();
        fs::write(p.join("credentials.kdf"), b"x").unwrap();
        let driver = drive_dart_response(RecoveryPromptResponse::Quit).await;
        let outcome = recovery_handle_corrupt_db(p, "probe failed".into()).await;
        driver.await.unwrap();
        assert_eq!(outcome, RecoveryOutcome::UserExited);
        // Cascade did NOT run on Quit — file is still on disk.
        assert!(p.join("credentials.kdf").exists());
    }

    #[tokio::test]
    async fn recovery_handle_corrupt_db_try_other_tier_returns_continued() {
        let _g = RECOVERY_TEST_LOCK.lock().await;
        let _ = crate::app::init();
        let tmp = tempfile::tempdir().expect("tmp");
        let p = tmp.path();
        fs::write(p.join("credentials.kdf"), b"x").unwrap();
        let driver = drive_dart_response(RecoveryPromptResponse::TryOtherTier).await;
        let outcome = recovery_handle_corrupt_db(p, "probe failed".into()).await;
        driver.await.unwrap();
        assert_eq!(outcome, RecoveryOutcome::Continued);
        // TryOtherTier preserves on-disk state for the retry path.
        assert!(p.join("credentials.kdf").exists());
    }

    #[tokio::test]
    async fn recovery_handle_vault_state_missing_reset_branch() {
        let _g = RECOVERY_TEST_LOCK.lock().await;
        let _ = crate::app::init();
        let tmp = tempfile::tempdir().expect("tmp");
        let p = tmp.path();
        fs::write(p.join("hardware_vault.bin"), b"x").unwrap();
        let driver = drive_dart_response(RecoveryPromptResponse::Reset).await;
        let outcome = recovery_handle_vault_state_missing(p, "T2 hardware".into()).await;
        driver.await.unwrap();
        assert_eq!(outcome, RecoveryOutcome::WipedAndRestarted);
        assert!(!p.join("hardware_vault.bin").exists());
    }

    #[tokio::test]
    async fn recovery_handle_legacy_state_reset_branch() {
        let _g = RECOVERY_TEST_LOCK.lock().await;
        let _ = crate::app::init();
        let tmp = tempfile::tempdir().expect("tmp");
        let p = tmp.path();
        fs::write(p.join("config.json"), b"{}").unwrap();
        let driver = drive_dart_response(RecoveryPromptResponse::Reset).await;
        let outcome = recovery_handle_legacy_state(p, 3, true).await;
        driver.await.unwrap();
        assert_eq!(outcome, RecoveryOutcome::WipedAndRestarted);
        assert!(!p.join("config.json").exists());
    }

    #[tokio::test]
    async fn recovery_handle_legacy_state_quit_branch_preserves_disk() {
        let _g = RECOVERY_TEST_LOCK.lock().await;
        let _ = crate::app::init();
        let tmp = tempfile::tempdir().expect("tmp");
        let p = tmp.path();
        fs::write(p.join("config.json"), b"{}").unwrap();
        let driver = drive_dart_response(RecoveryPromptResponse::Quit).await;
        let outcome = recovery_handle_legacy_state(p, 3, false).await;
        driver.await.unwrap();
        assert_eq!(outcome, RecoveryOutcome::UserExited);
        // Quit preserves on-disk state — user may export their data
        // from an older install before accepting the reset.
        assert!(p.join("config.json").exists());
    }

    #[tokio::test]
    async fn recovery_handle_corrupt_db_no_subscriber_defaults_to_quit() {
        // No Dart subscriber and no other handler resolves the prompt.
        // Cancel the registry entry to simulate Dart dropping the
        // subscription mid-flight; the receiver returns Err and the
        // orchestrator must fall through to Quit so the user's data
        // is preserved.
        let _g = RECOVERY_TEST_LOCK.lock().await;
        let _ = crate::app::init();
        let tmp = tempfile::tempdir().expect("tmp");
        let p = tmp.path();
        fs::write(p.join("credentials.kdf"), b"x").unwrap();
        // Spawn a task that cancels every pending prompt the
        // orchestrator publishes — simulates the Dart subscriber
        // dismissing the dialog without dispatching a choice.
        let app = crate::app::init();
        let mut rx = app.bus.subscribe(EventTopic::SecurityPrompt);
        let canceller = tokio::spawn(async move {
            loop {
                match rx.recv().await {
                    Ok(Event::RecoveryPromptRequest { prompt_id, .. }) => {
                        recovery_prompt::instance().cancel(&prompt_id);
                        return;
                    }
                    Ok(_) => continue,
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(_) => return,
                }
            }
        });
        let outcome = recovery_handle_corrupt_db(p, "probe failed".into()).await;
        canceller.await.unwrap();
        assert_eq!(outcome, RecoveryOutcome::UserExited);
        // No cascade ran — data preserved.
        assert!(p.join("credentials.kdf").exists());
    }
}
