/// Unit tests extracted from migration/registry.rs
/// Declared via `#[path] mod tests;` in the source file.
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
