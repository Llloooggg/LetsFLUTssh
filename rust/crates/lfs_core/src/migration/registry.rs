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

use super::artefacts::{ConfigArtefact, ConfigV1ToV2, ConfigV2ToV3, ConfigV3ToV4, KdfArtefact};
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
    // v1 → v2: `security_probe_cache` always emitted as an explicit
    // value (object or `null`) on the wire; v1 writers omitted on
    // `None`, collapsing the round-trip distinction.
    reg.migrations.push(Box::new(ConfigV1ToV2));
    // v2 → v3: collapse the legacy `keychain_with_password` tier
    // wire value into `keychain` + `security_modifiers.password =
    // true`. Finishes the half-migration to the bank-style tier
    // model so the enum carries one value per key-storage strategy
    // and password is purely a modifier.
    reg.migrations.push(Box::new(ConfigV2ToV3));
    // v3 → v4: drop the legacy `biometric_shortcut` and
    // `pin_length` fields from `security_modifiers`. Both were
    // backward-compat carries (deprecated alias / advisory) with
    // no runtime caller in either Rust or Dart by the time the
    // bank-style password modifier landed; v4 retires them.
    reg.migrations.push(Box::new(ConfigV3ToV4));

    // The hw-vault + password-gate artefacts have their own
    // version envelopes (`HW_VAULT_*` / DISK_BLOB_VERSION) and
    // run their own corruption-detection cascade outside the
    // generic `migration` framework, so a dependency declaration
    // here is dead weight — no `Artefact` is registered to match,
    // and `topo_sort` would silently skip them. Removing the
    // forward declarations keeps the registry's invariant honest:
    // every dependency endpoint is a registered artefact.
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
    fn config_v1_to_v2_migration_registered() {
        let reg = build_app_registry();
        assert!(
            reg.migrations
                .iter()
                .any(|m| m.artefact_id() == "config.json"
                    && m.source_version() == 1
                    && m.target_version() == 2),
            "ConfigV1ToV2 must be registered so v1 installs migrate \
             to v2 on the next launch",
        );
    }

    #[test]
    fn config_v2_to_v3_migration_registered() {
        let reg = build_app_registry();
        assert!(
            reg.migrations
                .iter()
                .any(|m| m.artefact_id() == "config.json"
                    && m.source_version() == 2
                    && m.target_version() == 3),
            "ConfigV2ToV3 must be registered so v2 installs migrate \
             to v3 on the next launch (keychain_with_password tier \
             collapse into bank-style modifier)",
        );
    }

    #[test]
    fn config_v3_to_v4_migration_registered() {
        let reg = build_app_registry();
        assert!(
            reg.migrations
                .iter()
                .any(|m| m.artefact_id() == "config.json"
                    && m.source_version() == 3
                    && m.target_version() == 4),
            "ConfigV3ToV4 must be registered so v3 installs migrate \
             to v4 on the next launch (drop legacy biometric_shortcut \
             + pin_length fields)",
        );
    }
}
