//! FRB adapter for `lfs_core::security::recovery` — the vault-
//! recovery orchestrator the Dart `SecurityInitController` used to
//! drive across four separate FRB hops + a Riverpod state patch.
//!
//! Surfaces two endpoints:
//!
//! - [`recovery_detect_legacy_state`] — bundles the legacy-state
//!   detection probes (`config.json` version + orphan artefacts on
//!   disk) into one async call. The Dart caller passes
//!   `has_current_security_config` from its `AppConfig.security`
//!   snapshot; the orphan branch short-circuits when that is `true`.
//! - [`recovery_run_destructive_reset`] — composes the destructive
//!   cascade (DB close → file sweep → keychain purge →
//!   hardware-vault primary clear → hardware-vault biometric
//!   overlay clear) atomically. The Dart caller follows up with
//!   the first-launch wizard, which cannot move Rust-side without
//!   breaking the "Flutter renders dialogs" invariant.

use lfs_core::security::recovery;

/// FRB mirror of [`recovery::LegacyStateDetection`]. Surfaces both
/// signals + the auxiliary version fields so the Dart caller can log
/// the diagnostic reason without re-running the probes.
#[derive(Debug, Clone)]
pub struct DbLegacyStateDetection {
    /// `config.json` is at a schema version below the build's target.
    pub legacy_config: bool,
    /// A security-bearing managed artefact lives in the support-dir
    /// while the Dart-side `AppConfig.security` is `None`.
    pub orphan_artefacts: bool,
    /// Probed schema version of `config.json` — `-1` when absent.
    pub config_version_on_disk: i32,
    /// Build's target schema version for `config.json`.
    pub config_target_version: i32,
    /// Convenience aggregator — true when the bootstrap path should
    /// surface the `TierResetDialog`. Mirrors
    /// [`recovery::LegacyStateDetection::should_prompt_reset`] so the
    /// Dart caller branches without re-deriving the predicate.
    pub should_prompt_reset: bool,
}

impl From<recovery::LegacyStateDetection> for DbLegacyStateDetection {
    fn from(d: recovery::LegacyStateDetection) -> Self {
        let should_prompt_reset = d.should_prompt_reset();
        DbLegacyStateDetection {
            legacy_config: d.legacy_config,
            orphan_artefacts: d.orphan_artefacts,
            config_version_on_disk: d.config_version_on_disk,
            config_target_version: d.config_target_version,
            should_prompt_reset,
        }
    }
}

/// FRB mirror of [`recovery::DestructiveResetReport`]. Mirrors the
/// shape of `wipe::FileSweepReport` + the keychain purge outcome,
/// so the Dart caller surfaces partial failures the same way the
/// user-driven "Reset all data" path already does.
#[derive(Debug, Clone)]
pub struct DbDestructiveResetReport {
    pub deleted_files: Vec<String>,
    pub failed_files: Vec<String>,
    pub keychain_purge_succeeded: bool,
    /// True when the per-platform hardware-vault primary key was
    /// dropped (or no hardware tier is present on this build).
    pub hw_vault_cleared: bool,
    /// True when the per-platform hardware-vault biometric overlay
    /// was dropped (or no hardware tier is present on this build).
    pub hw_vault_biometric_cleared: bool,
}

impl From<recovery::DestructiveResetReport> for DbDestructiveResetReport {
    fn from(r: recovery::DestructiveResetReport) -> Self {
        DbDestructiveResetReport {
            deleted_files: r.deleted_files,
            failed_files: r.failed_files,
            keychain_purge_succeeded: r.keychain_purge_succeeded,
            hw_vault_cleared: r.hw_vault_cleared,
            hw_vault_biometric_cleared: r.hw_vault_biometric_cleared,
        }
    }
}

/// Bundle the legacy-state probes into one async call.
///
/// `has_current_security_config` is the Dart-side
/// `AppConfig.security != null` snapshot — passing it lets the
/// orphan-artefact branch short-circuit when the running process
/// already has a valid security config, matching the Dart-era
/// `currentSecurity == null && wiper.hasAnyState()` predicate.
///
/// Async + `spawn_blocking` — the underlying probes touch the
/// filesystem (config version read + orphan-file existence walk);
/// running on the FRB worker thread would block other calls.
pub async fn recovery_detect_legacy_state(
    support_dir: String,
    has_current_security_config: bool,
) -> Result<DbLegacyStateDetection, String> {
    tokio::task::spawn_blocking(move || {
        let det = recovery::detect_legacy_state(
            std::path::Path::new(&support_dir),
            has_current_security_config,
        );
        DbLegacyStateDetection::from(det)
    })
    .await
    .map_err(|e| format!("recovery_detect_legacy_state task: {e}"))
}

/// Compose the destructive cascade Dart used to drive across five
/// separate FRB hops:
///
/// 1. `db_close` — release the SQLCipher handle.
/// 2. `wipe_sweep_files` — Rust-side file sweep + log directory wipe.
/// 3. `wipe_keychain_run` — OS-keychain alias purge.
/// 4. `hardware_tier_vault_clear` — per-platform primary key drop
///    (Apple SE / AndroidKeyStore / Windows CNG / Linux TPM2
///    envelope file).
/// 5. `hardware_tier_vault_clear_biometric_password` — per-platform
///    biometric-overlay drop, same dispatch shape.
/// 6. (Implicit) `config.json` is in the managed-files list so
///    step 2 leaves the install without a config; the next
///    `configStoreInit` re-seeds defaults, dropping the explicit
///    Riverpod patch the controller used to issue.
pub async fn recovery_run_destructive_reset(
    support_dir: String,
) -> Result<DbDestructiveResetReport, String> {
    let path = std::path::PathBuf::from(support_dir);
    let report = recovery::run_destructive_reset(&path).await;
    Ok(DbDestructiveResetReport::from(report))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Pin the predicate aggregation — the FRB mirror's
    /// `should_prompt_reset` must agree with the core
    /// `LegacyStateDetection::should_prompt_reset()` accessor on every
    /// signal combination. A regression here would silently break the
    /// Dart bootstrap branch that reads the convenience flag.
    #[test]
    fn db_legacy_state_detection_should_prompt_reset_truth_table() {
        for (legacy, orphan, expected) in [
            (false, false, false),
            (true, false, true),
            (false, true, true),
            (true, true, true),
        ] {
            let det = recovery::LegacyStateDetection {
                legacy_config: legacy,
                orphan_artefacts: orphan,
                config_version_on_disk: 1,
                config_target_version: 7,
            };
            let mirror: DbLegacyStateDetection = det.into();
            assert_eq!(mirror.should_prompt_reset, expected);
        }
    }

    /// Empty support-dir + no Dart-side security config — both probe
    /// signals report false, `should_prompt_reset` aggregates to false.
    #[tokio::test]
    async fn recovery_detect_legacy_state_empty_support_dir() {
        let tmp = tempfile::tempdir().expect("tmp");
        let path = tmp.path().to_string_lossy().into_owned();
        let det = recovery_detect_legacy_state(path, false).await.expect("ok");
        assert!(!det.legacy_config);
        assert!(!det.orphan_artefacts);
        assert!(!det.should_prompt_reset);
        assert_eq!(det.config_version_on_disk, -1);
    }

    /// Clean support-dir — destructive reset reports zero deletions
    /// and zero failures; the cascade is idempotent on an already-
    /// wiped install. Keychain purge result is plugin-dependent — on
    /// hosts where the keyring backend is reachable the call
    /// short-circuits with no managed aliases present; on hosts where
    /// it is not, the loop still terminates without panicking.
    #[tokio::test]
    async fn recovery_run_destructive_reset_on_clean_dir() {
        // The cascade touches `lfs_core::app::instance()` for the
        // SecretStore clear + db_close — initialise the singleton
        // before the call.
        let _ = lfs_core::app::init();
        let tmp = tempfile::tempdir().expect("tmp");
        let path = tmp.path().to_string_lossy().into_owned();
        let report = recovery_run_destructive_reset(path).await.expect("ok");
        assert!(report.deleted_files.is_empty());
        assert!(report.failed_files.is_empty());
    }
}
