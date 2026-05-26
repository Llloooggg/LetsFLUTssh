//! Mint `tests/fixtures/storage_primary_template_v1.bin`.
//!
//! Run once whenever the storage-primary template intentionally
//! changes (tss-esapi major bump that reshuffles a field, or a
//! deliberate template tweak shipping with a `SchemaVersions::HW_VAULT_LINUX`
//! bump). The `tpm_native::tests::storage_primary_template_marshalls_to_fixture`
//! test compares `build_primary_template().marshall()` against the
//! emitted bytes on every `cargo test`; failure means an upstream
//! default flipped silently and the fixture needs an intentional
//! re-mint paired with the schema bump.
//!
//! Linux-only — the rest of the crate's `tpm_*` modules are
//! `#[cfg(target_os = "linux")]`.
//!
//! ```bash
//! cargo run -p lfs_os_security --example mint_storage_primary_template_fixture
//! ```

#[cfg(target_os = "linux")]
fn main() {
    use lfs_os_security::linux::tpm_native;
    use tss_esapi::{structures::PublicBuffer, traits::Marshall};

    let template = tpm_native::build_primary_template().expect("build_primary_template");
    let buffer = PublicBuffer::try_from(template).expect("PublicBuffer::try_from");
    let bytes = buffer.marshall().expect("marshall");
    let path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/storage_primary_template_v1.bin");
    std::fs::create_dir_all(path.parent().unwrap()).expect("mkdir fixtures");
    std::fs::write(&path, &bytes).expect("write fixture");
    println!("wrote {} bytes to {}", bytes.len(), path.display());
}

#[cfg(not(target_os = "linux"))]
fn main() {
    eprintln!("mint_storage_primary_template_fixture is Linux-only — skipping on this target.");
}
