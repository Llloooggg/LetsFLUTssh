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

use super::artefacts::{
    ConfigArtefact, ConfigV1ToV2, ConfigV2ToV3, ConfigV3ToV4, ConfigV4ToV5, ConfigV5ToV6,
    ConfigV6ToV7, HwSaltArtefact, KdfArtefact, PassGateArtefact,
};
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
    // v4 → v5: stamp `recordings_storage_cap_bytes` with the
    // canonical 500 MiB default when absent so the recorder's LRU
    // eviction sweep has a configurable byte ceiling persisted
    // alongside the rest of the user preferences.
    reg.migrations.push(Box::new(ConfigV4ToV5));
    // v5 → v6: stamp the `sync_*` family of fields with the
    // canonical `SyncConfig::default` so the WebDAV sync
    // orchestrator sees the same shape every read produces.
    reg.migrations.push(Box::new(ConfigV5ToV6));
    // v6 → v7: flip the Hardware (T2) tier to always carry
    // `security_modifiers.password=true`. Pre-flip Hardware
    // installs with `password=false` also get a sibling
    // `.hardware_v7_password_set_pending` marker so the next
    // bootstrap routes the Tier-C password-set wizard ahead of
    // the regular unlock path.
    reg.migrations.push(Box::new(ConfigV6ToV7));
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

    #[test]
    fn config_v4_to_v5_migration_registered() {
        let reg = build_app_registry();
        assert!(
            reg.migrations
                .iter()
                .any(|m| m.artefact_id() == "config.json"
                    && m.source_version() == 4
                    && m.target_version() == 5),
            "ConfigV4ToV5 must be registered so v4 installs migrate \
             to v5 on the next launch (stamp default recordings \
             storage cap)",
        );
    }

    #[test]
    fn config_v5_to_v6_migration_registered() {
        let reg = build_app_registry();
        assert!(
            reg.migrations
                .iter()
                .any(|m| m.artefact_id() == "config.json"
                    && m.source_version() == 5
                    && m.target_version() == 6),
            "ConfigV5ToV6 must be registered so v5 installs migrate \
             to v6 on the next launch (stamp default sync settings)",
        );
    }

    #[test]
    fn config_v6_to_v7_migration_registered() {
        let reg = build_app_registry();
        assert!(
            reg.migrations
                .iter()
                .any(|m| m.artefact_id() == "config.json"
                    && m.source_version() == 6
                    && m.target_version() == 7),
            "ConfigV6ToV7 must be registered so v6 installs migrate \
             to v7 on the next launch (flip Hardware tier to always \
             carry the password modifier + stamp password-set marker)",
        );
    }
}
