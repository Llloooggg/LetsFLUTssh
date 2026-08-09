/// Unit tests extracted from migration/mod.rs
/// Declared via `#[path] mod tests;` in the source file.
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
    fn source_version(&self) -> i32 {
        self.from
    }
    fn target_version(&self) -> i32 {
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
