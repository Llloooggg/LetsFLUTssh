/// Unit tests extracted from security/recovery.rs
/// Declared via `#[path] mod tests;` in the source file.
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
    let _g = crate::app::test_serial_lock().lock().await;
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
    let _g = crate::app::test_serial_lock().lock().await;
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
    let _g = crate::app::test_serial_lock().lock().await;
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
    let _g = crate::app::test_serial_lock().lock().await;
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
    let _g = crate::app::test_serial_lock().lock().await;
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
    let _g = crate::app::test_serial_lock().lock().await;
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
    let _g = crate::app::test_serial_lock().lock().await;
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
