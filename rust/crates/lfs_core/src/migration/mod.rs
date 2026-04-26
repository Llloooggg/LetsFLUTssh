//! Startup migration framework.
//!
//! Walks every framework-registered artefact and applies the chain
//! of [`Migration`]s needed to bring on-disk state up to the current
//! build's [`SchemaVersions`]. Runs once per startup, BEFORE any
//! security-init / unlock path opens an artefact, so every later
//! reader sees the post-migration shape.
//!
//! The framework is canonical Rust now — the earlier Dart-side
//! `MigrationRunner` is gone; Dart calls
//! [`run_on_startup`](crate::migration::run_on_startup) over FRB and
//! consumes the [`Report`].
//!
//! Today every registered artefact is at v1 with zero migrations
//! registered, so the runner is effectively a presence-check that
//! returns a no-op `Report` on every install. Future format bumps
//! ship a [`Migration`] impl and bump the matching [`SchemaVersions`]
//! constant.

use std::collections::HashMap;
use std::path::Path;

pub mod artefacts;
pub mod registry;

pub use registry::{build_app_registry, Registry};

/// Canonical current version for every migrate-able artefact.
///
/// Single source of truth for "what version should this artefact be
/// after we are fully up to date". The runner compares each
/// artefact's on-disk version against the constant here and runs
/// the chain of migrations needed to reach it.
///
/// **Rules:**
/// - v1 is the permanent floor. Any on-disk state reporting a version
///   below 1 (pre-framework legacy layouts, unrecognised formats) is
///   treated as corrupt and routed through the reset path — never
///   migrated.
/// - Bump only when shipping a new [`Migration`] that targets the new
///   version. A bump without the matching migration registered in
///   [`registry::build_app_registry`] is caught by the registry-
///   completeness unit test.
/// - Never reuse a previous version number. Versions are monotonic.
pub struct SchemaVersions;

impl SchemaVersions {
    /// `config.json` payload format. `config_schema_version` is
    /// stamped by the config writer on every write; a missing or
    /// mismatched field on read = corrupt.
    pub const CONFIG: i32 = 1;

    /// `credentials.kdf` (Argon2id params + salt). Self-versioned
    /// inside the file via `'LFKD'` magic + version byte; tracked
    /// here so the framework can route future format bumps through
    /// itself.
    pub const KDF: i32 = 1;

    /// `security_pass_hash.bin` — keychain password gate.
    pub const PASS_GATE: i32 = 1;

    /// `hardware_vault_*.bin` — per-platform hw vault blob.
    pub const HW_VAULT_ANDROID: i32 = 1;
    pub const HW_VAULT_APPLE: i32 = 1;
    pub const HW_VAULT_WINDOWS: i32 = 1;
    pub const HW_VAULT_LINUX: i32 = 1;

    /// `hardware_vault_salt.bin` — raw 32-byte salt.
    pub const HW_SALT: i32 = 1;

    /// `.lfs` archive schema carried in `manifest.json`.
    pub const ARCHIVE: i32 = 1;
}

/// A single migrate-able piece of on-disk state.
///
/// `target_version` is the value the runner is trying to reach for
/// this artefact (read from [`SchemaVersions`]). The plan of
/// migrations is computed as the chain whose `from_version` /
/// `to_version` pairs walk from `read_version()` up to
/// `target_version`.
pub trait Artefact: Send + Sync {
    /// Stable string id used in the migration log + error messages.
    /// Use the same name as the file under app-support
    /// (e.g. `"config.json"`, `"hardware_vault_linux.bin"`).
    fn id(&self) -> &'static str;

    /// Canonical target version for this artefact in the current
    /// build. Read straight from a [`SchemaVersions`] constant.
    fn target_version(&self) -> i32;

    /// Inspect the on-disk state and return its current version.
    ///
    /// - `-1` → artefact does not exist on disk yet (clean install
    ///   for this slot). Runner skips migrations for it.
    /// - `>= 1` → artefact present; runner walks the migration chain
    ///   from this value up to [`Artefact::target_version`].
    ///
    /// Values below 1 (corrupt headers, missing schema fields, pre-v1
    /// legacy layouts) must return `Err` — the runner surfaces the
    /// failure as a fatal [`Report::fatal_error`] entry so the caller
    /// can route the user through the reset dialog. Never return a
    /// made-up version for unrecognised state.
    fn read_version(&self, support_dir: &Path) -> Result<i32, String>;
}

/// One step in the migration chain for a single artefact.
///
/// Each [`Migration`] covers exactly one
/// `(artefact_id, from_version -> to_version)` transition. To go from
/// version 1 to version 3 the runner composes two migrations
/// (1->2, 2->3). Skipping versions is forbidden — if the gap matters,
/// ship the intermediate migrations.
///
/// Atomicity contract: [`Migration::apply`] is responsible for
/// atomicity end-to-end. The standard pattern is to write the new
/// artefact bytes to a sibling temp file, fsync, then `rename` over
/// the original. If `apply` returns `Err` before the rename, the
/// original file is untouched and the runner records the failure as
/// a fatal entry.
//
// `from_version` reads as a constructor name to clippy's
// `wrong_self_convention` lint, but here it's the artefact-version
// getter that the runner pairs with `to_version`. Renaming both
// makes the registration site harder to scan, so silence the lint.
#[allow(clippy::wrong_self_convention)]
pub trait Migration: Send + Sync {
    /// id of the artefact this migration acts on. Must match an
    /// [`Artefact::id`] registered in the registry.
    fn artefact_id(&self) -> &'static str;

    /// Version of the artefact this migration expects to read.
    fn from_version(&self) -> i32;

    /// Version of the artefact this migration produces.
    fn to_version(&self) -> i32;

    /// Run the conversion. Implementations must be atomic — any
    /// failure must leave the artefact at `from_version` on disk.
    /// Return `Err(message)` on any failure.
    fn apply(&self, support_dir: &Path) -> Result<(), String>;
}

/// Per-step record of a migration the runner ran (or tried to run).
#[derive(Clone, Debug)]
pub struct Step {
    pub artefact_id: String,
    pub from_version: i32,
    pub to_version: i32,
    pub succeeded: bool,
    pub error: Option<String>,
}

/// On-disk version was higher than anything the current build knows
/// how to handle. The user is running an older binary against newer-
/// format state — usually the result of downgrading after a forward
/// migration ran. Runner surfaces this via the report and refuses to
/// start the unlock flow; data is preserved so a re-upgrade recovers
/// cleanly.
#[derive(Clone, Debug)]
pub struct UnsupportedFutureVersion {
    pub artefact_id: String,
    pub on_disk_version: i32,
    pub known_target_version: i32,
}

/// Aggregate result of one [`run_on_startup`] call.
#[derive(Clone, Debug, Default)]
pub struct Report {
    pub steps: Vec<Step>,
    pub future_versions: Vec<UnsupportedFutureVersion>,
    pub fatal_error: Option<String>,
}

impl Report {
    /// True when the runner encountered any kind of failure — fatal
    /// throw, a future-version artefact, or a non-succeeded step.
    pub fn has_failures(&self) -> bool {
        self.fatal_error.is_some()
            || !self.future_versions.is_empty()
            || self.steps.iter().any(|s| !s.succeeded)
    }

    /// True when the runner is entirely satisfied — every artefact
    /// is already at its target version, nothing migrated, no errors.
    pub fn no_op(&self) -> bool {
        self.steps.is_empty() && self.future_versions.is_empty() && self.fatal_error.is_none()
    }

    /// Count of successful migrations; useful for the post-run toast.
    pub fn migrated_count(&self) -> usize {
        self.steps.iter().filter(|s| s.succeeded).count()
    }
}

/// Walk every registered artefact, compute the migration chain, and
/// apply each step in dependency order. Returns a [`Report`]; caller
/// decides whether to surface failures via dialog.
pub fn run_on_startup(support_dir: &Path, registry: &Registry) -> Report {
    let mut steps: Vec<Step> = Vec::new();
    let mut future = Vec::new();

    let ordered = match topo_sort(registry) {
        Ok(o) => o,
        Err(e) => {
            return Report {
                steps,
                future_versions: future,
                fatal_error: Some(e),
            };
        }
    };

    let mut fatal = None;
    for &idx in &ordered {
        let artefact = &*registry.artefacts[idx];
        match migrate_artefact(support_dir, artefact, registry, &mut steps) {
            ArtefactOutcome::Ok => {}
            ArtefactOutcome::Future(f) => future.push(f),
            ArtefactOutcome::Fatal(e) => {
                fatal = Some(e);
                break;
            }
        }
    }

    Report {
        steps,
        future_versions: future,
        fatal_error: fatal,
    }
}

enum ArtefactOutcome {
    Ok,
    Future(UnsupportedFutureVersion),
    Fatal(String),
}

fn migrate_artefact(
    support_dir: &Path,
    artefact: &dyn Artefact,
    registry: &Registry,
    steps: &mut Vec<Step>,
) -> ArtefactOutcome {
    let on_disk = match artefact.read_version(support_dir) {
        Ok(v) => v,
        Err(e) => return ArtefactOutcome::Fatal(format!("{}: {}", artefact.id(), e)),
    };

    if on_disk < 0 {
        return ArtefactOutcome::Ok;
    }

    let target = artefact.target_version();
    if on_disk == target {
        return ArtefactOutcome::Ok;
    }
    if on_disk > target {
        return ArtefactOutcome::Future(UnsupportedFutureVersion {
            artefact_id: artefact.id().to_string(),
            on_disk_version: on_disk,
            known_target_version: target,
        });
    }

    walk_chain(support_dir, artefact, registry, on_disk, target, steps)
}

fn walk_chain(
    support_dir: &Path,
    artefact: &dyn Artefact,
    registry: &Registry,
    on_disk: i32,
    target: i32,
    steps: &mut Vec<Step>,
) -> ArtefactOutcome {
    let mut current = on_disk;
    while current < target {
        let step = match find_migration(registry, artefact.id(), current) {
            Some(m) => m,
            None => {
                let err = format!(
                    "no migration registered for {} from version {}",
                    artefact.id(),
                    current
                );
                steps.push(Step {
                    artefact_id: artefact.id().to_string(),
                    from_version: current,
                    to_version: current + 1,
                    succeeded: false,
                    error: Some(err.clone()),
                });
                return ArtefactOutcome::Fatal(err);
            }
        };

        match step.apply(support_dir) {
            Ok(()) => {
                steps.push(Step {
                    artefact_id: artefact.id().to_string(),
                    from_version: step.from_version(),
                    to_version: step.to_version(),
                    succeeded: true,
                    error: None,
                });
                current = step.to_version();
            }
            Err(e) => {
                steps.push(Step {
                    artefact_id: artefact.id().to_string(),
                    from_version: step.from_version(),
                    to_version: step.to_version(),
                    succeeded: false,
                    error: Some(e.clone()),
                });
                return ArtefactOutcome::Fatal(e);
            }
        }
    }
    ArtefactOutcome::Ok
}

fn find_migration<'a>(
    registry: &'a Registry,
    artefact_id: &str,
    from: i32,
) -> Option<&'a dyn Migration> {
    for m in &registry.migrations {
        if m.artefact_id() == artefact_id && m.from_version() == from {
            return Some(&**m);
        }
    }
    None
}

/// Kahn's algorithm — order artefacts so every dependency is
/// migrated before the artefact that depends on it. Returns indices
/// into `registry.artefacts`; an unrecognised dependency endpoint is
/// silently skipped (matches the Dart-side behaviour of allowing
/// dependency declarations for not-yet-registered artefacts).
fn topo_sort(registry: &Registry) -> Result<Vec<usize>, String> {
    let n = registry.artefacts.len();
    let id_to_idx: HashMap<&str, usize> = registry
        .artefacts
        .iter()
        .enumerate()
        .map(|(i, a)| (a.id(), i))
        .collect();

    let mut indegree = vec![0usize; n];
    let mut adjacency: Vec<Vec<usize>> = vec![Vec::new(); n];

    for (id, after) in &registry.dependencies {
        let Some(&dep_idx) = id_to_idx.get(id.as_str()) else {
            continue;
        };
        for pre in after {
            let Some(&pre_idx) = id_to_idx.get(pre.as_str()) else {
                continue;
            };
            adjacency[pre_idx].push(dep_idx);
            indegree[dep_idx] += 1;
        }
    }

    let mut queue: Vec<usize> = indegree
        .iter()
        .enumerate()
        .filter_map(|(i, d)| if *d == 0 { Some(i) } else { None })
        .collect();
    let mut ordered = Vec::with_capacity(n);
    while let Some(i) = queue.pop() {
        ordered.push(i);
        // pop() consumes from end — gives stack-shape walk; that's
        // fine here because Kahn's gives "any topological order".
        for &next in &adjacency[i] {
            indegree[next] -= 1;
            if indegree[next] == 0 {
                queue.push(next);
            }
        }
    }
    if ordered.len() != n {
        return Err("cycle in migration dependencies".into());
    }
    Ok(ordered)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    struct StaticArtefact {
        id: &'static str,
        target: i32,
        on_disk: i32,
    }

    impl Artefact for StaticArtefact {
        fn id(&self) -> &'static str {
            self.id
        }
        fn target_version(&self) -> i32 {
            self.target
        }
        fn read_version(&self, _: &Path) -> Result<i32, String> {
            Ok(self.on_disk)
        }
    }

    struct RecordingMigration {
        artefact_id: &'static str,
        from: i32,
        to: i32,
        log: std::sync::Arc<Mutex<Vec<String>>>,
        fail: bool,
    }

    impl Migration for RecordingMigration {
        fn artefact_id(&self) -> &'static str {
            self.artefact_id
        }
        fn from_version(&self) -> i32 {
            self.from
        }
        fn to_version(&self) -> i32 {
            self.to
        }
        fn apply(&self, _: &Path) -> Result<(), String> {
            self.log
                .lock()
                .unwrap()
                .push(format!("{}:{}->{}", self.artefact_id, self.from, self.to));
            if self.fail {
                Err(format!(
                    "{}:{}->{} failed",
                    self.artefact_id, self.from, self.to
                ))
            } else {
                Ok(())
            }
        }
    }

    fn empty_dir() -> std::path::PathBuf {
        std::env::temp_dir()
    }

    #[test]
    fn no_op_when_artefact_at_target() {
        let reg = Registry {
            artefacts: vec![Box::new(StaticArtefact {
                id: "x",
                target: 1,
                on_disk: 1,
            })],
            migrations: vec![],
            dependencies: HashMap::new(),
        };
        let report = run_on_startup(&empty_dir(), &reg);
        assert!(report.no_op());
        assert!(!report.has_failures());
        assert_eq!(report.migrated_count(), 0);
    }

    #[test]
    fn skips_absent_artefact() {
        let reg = Registry {
            artefacts: vec![Box::new(StaticArtefact {
                id: "absent",
                target: 1,
                on_disk: -1,
            })],
            migrations: vec![],
            dependencies: HashMap::new(),
        };
        let report = run_on_startup(&empty_dir(), &reg);
        assert!(report.no_op());
    }

    #[test]
    fn future_version_collected() {
        let reg = Registry {
            artefacts: vec![Box::new(StaticArtefact {
                id: "future",
                target: 1,
                on_disk: 5,
            })],
            migrations: vec![],
            dependencies: HashMap::new(),
        };
        let report = run_on_startup(&empty_dir(), &reg);
        assert_eq!(report.future_versions.len(), 1);
        assert!(report.has_failures());
        assert_eq!(report.future_versions[0].on_disk_version, 5);
    }

    #[test]
    fn walks_full_chain() {
        let log = std::sync::Arc::new(Mutex::new(Vec::new()));
        let reg = Registry {
            artefacts: vec![Box::new(StaticArtefact {
                id: "x",
                target: 3,
                on_disk: 1,
            })],
            migrations: vec![
                Box::new(RecordingMigration {
                    artefact_id: "x",
                    from: 1,
                    to: 2,
                    log: log.clone(),
                    fail: false,
                }),
                Box::new(RecordingMigration {
                    artefact_id: "x",
                    from: 2,
                    to: 3,
                    log: log.clone(),
                    fail: false,
                }),
            ],
            dependencies: HashMap::new(),
        };
        let report = run_on_startup(&empty_dir(), &reg);
        assert_eq!(report.migrated_count(), 2);
        assert_eq!(*log.lock().unwrap(), vec!["x:1->2", "x:2->3"]);
    }

    #[test]
    fn missing_step_is_fatal() {
        let log = std::sync::Arc::new(Mutex::new(Vec::new()));
        let reg = Registry {
            artefacts: vec![Box::new(StaticArtefact {
                id: "x",
                target: 3,
                on_disk: 1,
            })],
            migrations: vec![Box::new(RecordingMigration {
                artefact_id: "x",
                from: 1,
                to: 2,
                log: log.clone(),
                fail: false,
            })],
            dependencies: HashMap::new(),
        };
        let report = run_on_startup(&empty_dir(), &reg);
        assert!(report.fatal_error.is_some());
        assert_eq!(report.steps.iter().filter(|s| s.succeeded).count(), 1);
        assert_eq!(report.steps.iter().filter(|s| !s.succeeded).count(), 1);
    }

    #[test]
    fn failed_step_is_fatal_and_recorded() {
        let log = std::sync::Arc::new(Mutex::new(Vec::new()));
        let reg = Registry {
            artefacts: vec![Box::new(StaticArtefact {
                id: "x",
                target: 2,
                on_disk: 1,
            })],
            migrations: vec![Box::new(RecordingMigration {
                artefact_id: "x",
                from: 1,
                to: 2,
                log,
                fail: true,
            })],
            dependencies: HashMap::new(),
        };
        let report = run_on_startup(&empty_dir(), &reg);
        assert!(report.fatal_error.is_some());
        assert_eq!(report.steps.len(), 1);
        assert!(!report.steps[0].succeeded);
    }

    #[test]
    fn dependency_order_respected() {
        let log = std::sync::Arc::new(Mutex::new(Vec::new()));
        let reg = Registry {
            artefacts: vec![
                Box::new(StaticArtefact {
                    id: "depends_on_a",
                    target: 2,
                    on_disk: 1,
                }),
                Box::new(StaticArtefact {
                    id: "a",
                    target: 2,
                    on_disk: 1,
                }),
            ],
            migrations: vec![
                Box::new(RecordingMigration {
                    artefact_id: "depends_on_a",
                    from: 1,
                    to: 2,
                    log: log.clone(),
                    fail: false,
                }),
                Box::new(RecordingMigration {
                    artefact_id: "a",
                    from: 1,
                    to: 2,
                    log: log.clone(),
                    fail: false,
                }),
            ],
            dependencies: HashMap::from_iter([("depends_on_a".to_string(), vec!["a".to_string()])]),
        };
        let report = run_on_startup(&empty_dir(), &reg);
        assert_eq!(report.migrated_count(), 2);
        let log_snapshot = log.lock().unwrap().clone();
        let a_pos = log_snapshot
            .iter()
            .position(|e| e == "a:1->2")
            .expect("a recorded");
        let dep_pos = log_snapshot
            .iter()
            .position(|e| e == "depends_on_a:1->2")
            .expect("depends_on_a recorded");
        assert!(a_pos < dep_pos, "dep ran before a — order violated");
    }

    #[test]
    fn cycle_in_dependencies_is_fatal() {
        let reg = Registry {
            artefacts: vec![
                Box::new(StaticArtefact {
                    id: "a",
                    target: 1,
                    on_disk: 1,
                }),
                Box::new(StaticArtefact {
                    id: "b",
                    target: 1,
                    on_disk: 1,
                }),
            ],
            migrations: vec![],
            dependencies: HashMap::from_iter([
                ("a".to_string(), vec!["b".to_string()]),
                ("b".to_string(), vec!["a".to_string()]),
            ]),
        };
        let report = run_on_startup(&empty_dir(), &reg);
        assert!(report.fatal_error.is_some());
        assert!(report.fatal_error.unwrap().contains("cycle"));
    }

    #[test]
    fn dangling_dependency_endpoint_is_ignored() {
        let reg = Registry {
            artefacts: vec![Box::new(StaticArtefact {
                id: "a",
                target: 1,
                on_disk: 1,
            })],
            migrations: vec![],
            dependencies: HashMap::from_iter([("a".to_string(), vec!["unregistered".to_string()])]),
        };
        let report = run_on_startup(&empty_dir(), &reg);
        assert!(report.no_op());
    }
}
