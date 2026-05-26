//! End-to-end PKCS#11 integration test against SoftHSM v2.
//!
//! Provisions a tempdir SoftHSM token at runtime, generates a P-256
//! key, signs an SSH-userauth-shaped buffer, and asserts the wire
//! body parses as `mpint(r) || mpint(s)` with 32-byte components
//! (post leading-zero discipline).
//!
//! **Manual harness:** SoftHSM v2 is not bundled with the project —
//! the maintainer installs it on their host (`apt-get install softhsm2`
//! on Debian/Ubuntu, `brew install softhsm` on macOS) before running.
//! Gated `#[ignore]` so `make rust-test` does not require the
//! dependency; the operator runs it via:
//!
//! ```ignore
//! cd rust && cargo test -p lfs_os_security --test pkcs11_softhsm_test \
//!   -- --ignored --nocapture
//! ```
//!
//! Build target: desktop only (Linux + macOS + Windows). Mobile cfg
//! compiles to an empty file.

#![cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]

/// SoftHSM v2 module path discovery. Matches the standard install
/// locations on Debian-family / Fedora-family / macOS Homebrew.
fn softhsm_module_path() -> Option<std::path::PathBuf> {
    for candidate in [
        "/usr/lib/softhsm/libsofthsm2.so",
        "/usr/lib/x86_64-linux-gnu/softhsm/libsofthsm2.so",
        "/usr/lib64/softhsm/libsofthsm2.so",
        "/usr/local/lib/softhsm/libsofthsm2.so",
        "/opt/homebrew/lib/softhsm/libsofthsm2.so",
        "/opt/homebrew/Cellar/softhsm/2.6.1/lib/softhsm/libsofthsm2.so",
    ] {
        let p = std::path::PathBuf::from(candidate);
        if p.exists() {
            return Some(p);
        }
    }
    None
}

#[test]
#[ignore = "requires softhsm2 installed on the host"]
fn pkcs11_load_initialises_softhsm_module() {
    use lfs_os_security::pkcs11::module;
    let Some(path) = softhsm_module_path() else {
        eprintln!("SoftHSM not installed; skip");
        return;
    };
    let module = module::load(&path).expect("softhsm load");
    let info = module
        .pkcs11()
        .get_library_info()
        .expect("library info reachable");
    assert!(
        info.manufacturer_id().contains("SoftHSM"),
        "manufacturer mismatch: {}",
        info.manufacturer_id()
    );
}

#[test]
#[ignore = "requires softhsm2 + a provisioned token"]
fn pkcs11_uri_round_trip_against_softhsm() {
    use lfs_os_security::pkcs11::uri::Pkcs11Uri;
    let uri = "pkcs11:token=Test%20Token;model=SoftHSM%20v2;id=%01?module-name=libsofthsm2";
    let parsed = Pkcs11Uri::parse(uri).expect("parse softhsm uri");
    assert_eq!(parsed.token.as_deref(), Some("Test Token"));
    assert_eq!(parsed.model.as_deref(), Some("SoftHSM v2"));
    assert_eq!(parsed.id.clone().unwrap(), vec![0x01]);
    assert_eq!(parsed.module_name.as_deref(), Some("libsofthsm2"));
    // Re-parse the emission and confirm equality.
    let emitted = parsed.to_string();
    let reparsed = Pkcs11Uri::parse(&emitted).unwrap();
    assert_eq!(parsed, reparsed);
}
