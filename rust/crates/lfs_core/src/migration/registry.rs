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

use super::artefacts::{ConfigArtefact, HwSaltArtefact, KdfArtefact, PassGateArtefact};
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

/// Build the registry the live app uses at startup. Lists every
/// artefact whose on-disk slot lives under the app-support
/// directory and whose version is queryable without invoking a
/// platform OS-API. The framework runner walks the registered
/// artefacts to pull each up to its [`super::SchemaVersions`]
/// target version; absent artefacts (clean install) are skipped.
///
/// Three [`super::SchemaVersions`] slots stay deliberately
/// unregistered:
/// - `HW_VAULT_*` — the per-platform vault file is bound to the OS
///   hardware backend (Secure Enclave / NCrypt / StrongBox / TPM)
///   and a magic-mismatch / version-mismatch envelope is rejected
///   at unwrap time via [`HardwareVaultError::Corrupt`]. The
///   tier-reset cascade owns recovery; a registry-side migration
///   is the wrong shape (the wrapped key cannot survive a v1→v2
///   rewrite because the inner crypto changed).
/// - `ARCHIVE` — `.lfs` files are user-supplied import payloads
///   that never persist under app-support. Future-version archives
///   are rejected by [`crate::archive::read_archive_to_pending`].
/// - `QR_PAYLOAD` — the QR / paste-link envelope is a transient
///   wire format, not on-disk state. Future-version payloads are
///   rejected at decode time.
pub fn build_app_registry() -> Registry {
    let mut reg = Registry::default();
    reg.artefacts.push(Box::new(ConfigArtefact));
    reg.artefacts.push(Box::new(KdfArtefact));
    reg.artefacts.push(Box::new(PassGateArtefact));
    reg.artefacts.push(Box::new(HwSaltArtefact));
    // No [`super::Migration`] impls registered — every artefact sits
    // at v1 and the runner only performs the presence + version probe
    // pass. Future format bumps add the matching `reg.migrations.push`
    // line alongside the impl + its registry-completeness unit test.
    reg
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_registry_has_every_on_disk_artefact() {
        let reg = build_app_registry();
        let ids: Vec<&'static str> = reg.artefacts.iter().map(|a| a.id()).collect();
        assert!(ids.contains(&"config.json"));
        assert!(ids.contains(&"credentials.kdf"));
        assert!(ids.contains(&"security_pass_hash.bin"));
        assert!(ids.contains(&"hardware_vault_salt.bin"));
    }

    #[test]
    fn every_dependency_endpoint_is_a_registered_artefact() {
        // Invariant: a dependency declaration references an artefact
        // that the registry actually knows about. Forward-declared
        // entries on unregistered artefacts would silently no-op
        // in `topo_sort` and degrade future cross-checks. Pin the
        // invariant here so a future commit that re-introduces a
        // dead dependency edge fails at test time.
        let reg = build_app_registry();
        let registered: std::collections::HashSet<&'static str> =
            reg.artefacts.iter().map(|a| a.id()).collect();
        for (id, deps) in &reg.dependencies {
            assert!(
                registered.contains(id.as_str()),
                "dependency declared on unregistered artefact '{id}' (no Artefact in registry)"
            );
            for pre in deps {
                assert!(
                    registered.contains(pre.as_str()),
                    "artefact '{id}' depends on unregistered '{pre}'"
                );
            }
        }
    }

    #[test]
    fn app_registry_has_no_migrations_at_v1_baseline() {
        // Every artefact currently sits at v1 — the registry exposes
        // only the artefact list, no `Migration` impls. Pin the
        // invariant so a future commit that adds a migration without
        // bumping `SchemaVersions` is caught immediately.
        let reg = build_app_registry();
        assert!(
            reg.migrations.is_empty(),
            "no migration impls expected at the v1 baseline, found {}",
            reg.migrations.len(),
        );
    }
}
