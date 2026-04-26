//! Registry of artefacts + migrations the runner walks at startup.
//!
//! Composition is explicit ([`build_app_registry`]) — no service-
//! locator scanning. The list of artefacts is intentionally simple;
//! ordering inside one artefact is by `from_version`, ordering
//! between artefacts is encoded via [`Registry::dependencies`] so
//! the runner can run one artefact's migrations after another's
//! (e.g. config before vault, since vault layout reads tier from
//! config).

use std::collections::HashMap;

use super::artefacts::{ConfigArtefact, KdfArtefact};
use super::{Artefact, Migration};

/// Mutable registry of every artefact + migration the runner knows
/// about.
#[derive(Default)]
pub struct Registry {
    pub artefacts: Vec<Box<dyn Artefact>>,
    pub migrations: Vec<Box<dyn Migration>>,
    /// `{artefact_id: [other_artefact_ids…]}` — every entry in the
    /// value list must run its migrations BEFORE the key artefact
    /// runs its own. Used by the runner's topological sort.
    pub dependencies: HashMap<String, Vec<String>>,
}

/// Build the registry the live app uses at startup. Today only
/// presence-only artefact wrappers are registered, no migrations
/// — the runner is therefore a no-op on every install where on-disk
/// state already matches [`super::SchemaVersions`]. Future format
/// bumps add concrete [`Migration`] impls here.
pub fn build_app_registry() -> Registry {
    let mut reg = Registry::default();
    reg.artefacts.push(Box::new(ConfigArtefact));
    reg.artefacts.push(Box::new(KdfArtefact));

    // Vault + password-gate layouts depend on tier read from config —
    // keep config ahead of every future vault artefact in the
    // dependency graph. Declared up front so vault artefacts can be
    // added later without having to re-state the relationship.
    let dependents = [
        "hardware_vault.bin",
        "hardware_vault_android.bin",
        "hardware_vault_ios.bin",
        "hardware_vault_macos.bin",
        "hardware_vault_windows.bin",
        "hardware_vault_linux.bin",
        "hardware_vault_salt.bin",
        "security_pass_hash.bin",
    ];
    for id in dependents {
        reg.dependencies
            .entry(id.to_string())
            .or_default()
            .push(ConfigArtefact::FILE_NAME.to_string());
    }
    reg
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_registry_has_config_and_kdf() {
        let reg = build_app_registry();
        let ids: Vec<&'static str> = reg.artefacts.iter().map(|a| a.id()).collect();
        assert!(ids.contains(&"config.json"));
        assert!(ids.contains(&"credentials.kdf"));
    }

    #[test]
    fn vault_artefacts_depend_on_config() {
        let reg = build_app_registry();
        for id in [
            "hardware_vault.bin",
            "hardware_vault_linux.bin",
            "hardware_vault_salt.bin",
            "security_pass_hash.bin",
        ] {
            let deps = reg.dependencies.get(id).expect(id);
            assert!(deps.contains(&"config.json".to_string()));
        }
    }

    #[test]
    fn no_migrations_registered_today() {
        let reg = build_app_registry();
        assert!(reg.migrations.is_empty());
    }
}
