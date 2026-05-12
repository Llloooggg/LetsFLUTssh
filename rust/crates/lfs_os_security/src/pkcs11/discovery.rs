//! Well-known module-path discovery.
//!
//! Vendor-specific PKCS#11 shared libraries land under stable paths
//! on every distro / installer we support. The table below is the
//! single source of truth for "where do JaCarta / Рутокен / eToken /
//! YubiKey PIV / OpenSC / Thales Luna / AWS CloudHSM keep their
//! library?". `scan_well_known_paths` walks the table, filters by
//! existence, and returns the candidates the UI offers in the
//! module picker. Probing each candidate via `Pkcs11::new` happens
//! at a later stage (the picker calls `module::Module::probe` for
//! each surviving entry to confirm the library actually loads).

use std::path::PathBuf;

/// A PKCS#11 library candidate the picker surfaces. `vendor` is the
/// human-readable short name we display on the row; `path` is the
/// resolved on-disk path the loader will `dlopen`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModuleCandidate {
    pub vendor: String,
    pub path: PathBuf,
}

/// Walk the well-known-paths table and return every candidate whose
/// file exists. Probing the library (`Pkcs11::new` + `initialize`)
/// is deferred to the picker — `discovery` only filters by
/// disk-existence so the UI can render the disabled rows for missing
/// vendors without the dlopen cost.
pub fn scan_well_known_paths() -> Vec<ModuleCandidate> {
    let entries = well_known_table();
    let mut out = Vec::new();
    for (vendor, path) in entries {
        let pb = PathBuf::from(path);
        if pb.exists() {
            out.push(ModuleCandidate {
                vendor: vendor.to_string(),
                path: pb,
            });
        }
    }
    out
}

/// Compile-time per-OS table. Linux entries cover the two canonical
/// arches (Debian / Ubuntu `/usr/lib/x86_64-linux-gnu/`, Fedora /
/// RHEL / openSUSE `/usr/lib64/`). Windows entries cover the default
/// vendor-installer paths; macOS covers the brew + framework
/// locations.
///
/// Adding a new vendor: append a `(name, "/path/to/lib")` tuple
/// for each target.
#[cfg(target_os = "linux")]
fn well_known_table() -> &'static [(&'static str, &'static str)] {
    &[
        // OpenSC — covers OpenPGP card, PIV applets, Estonian /
        // Finnish / German eID cards, generic CCID readers.
        ("OpenSC", "/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so"),
        ("OpenSC", "/usr/lib64/pkcs11/opensc-pkcs11.so"),
        ("OpenSC", "/usr/lib/pkcs11/opensc-pkcs11.so"),
        // YubiKey PIV — direct ykcs11 (faster than OpenSC for PIV).
        (
            "YubiKey PIV (ykcs11)",
            "/usr/lib/x86_64-linux-gnu/libykcs11.so",
        ),
        ("YubiKey PIV (ykcs11)", "/usr/local/lib/libykcs11.so"),
        // JaCarta (Aladdin).
        ("JaCarta", "/usr/lib/libjcPKCS11-2.so"),
        ("JaCarta", "/usr/lib64/libjcPKCS11-2.so"),
        // Rutoken (CIS vendor — ECP / ECP2 / Lite series).
        ("Rutoken", "/usr/lib/librtpkcs11ecp.so"),
        ("Rutoken", "/usr/lib64/librtpkcs11ecp.so"),
        // SafeNet / eToken.
        ("eToken / SafeNet", "/usr/lib/libeToken.so"),
        ("eToken / SafeNet", "/usr/lib64/libeTPkcs11.so"),
        // Thales Luna network HSM client library.
        (
            "Thales Luna HSM",
            "/usr/safenet/lunaclient/lib/libCryptoki2_64.so",
        ),
        // AWS CloudHSM.
        ("AWS CloudHSM", "/opt/cloudhsm/lib/libcloudhsm_pkcs11.so"),
    ]
}

#[cfg(target_os = "windows")]
fn well_known_table() -> &'static [(&'static str, &'static str)] {
    &[
        (
            "OpenSC",
            r"C:\Program Files\OpenSC Project\OpenSC\pkcs11\opensc-pkcs11.dll",
        ),
        (
            "YubiKey PIV (ykcs11)",
            r"C:\Program Files\Yubico\Yubico PIV Tool\bin\libykcs11.dll",
        ),
        ("JaCarta", r"C:\Windows\System32\jcPKCS11-2.dll"),
        ("Rutoken", r"C:\Windows\System32\rtPKCS11ECP.dll"),
        ("eToken / SafeNet", r"C:\Windows\System32\eTPKCS11.dll"),
        (
            "Thales Luna HSM",
            r"C:\Program Files\SafeNet\LunaClient\cryptoki.dll",
        ),
    ]
}

#[cfg(target_os = "macos")]
fn well_known_table() -> &'static [(&'static str, &'static str)] {
    &[
        ("OpenSC", "/Library/OpenSC/lib/opensc-pkcs11.so"),
        ("OpenSC", "/opt/homebrew/lib/opensc-pkcs11.so"),
        ("OpenSC", "/usr/local/lib/opensc-pkcs11.so"),
        ("YubiKey PIV (ykcs11)", "/usr/local/lib/libykcs11.dylib"),
        ("YubiKey PIV (ykcs11)", "/opt/homebrew/lib/libykcs11.dylib"),
        (
            "Rutoken",
            "/Library/Frameworks/rtPKCS11.framework/rtpkcs11ecp.dylib",
        ),
        ("eToken / SafeNet", "/usr/local/lib/libeTPkcs11.dylib"),
    ]
}

// Mobile / unknown — empty table; the FRB shim returns the empty
// Vec and the UI renders the row disabled with the
// "Smart-card / PKCS#11 tokens are not available on this platform."
// reason.
#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
fn well_known_table() -> &'static [(&'static str, &'static str)] {
    &[]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn table_is_non_empty_on_desktop() {
        if cfg!(any(
            target_os = "linux",
            target_os = "macos",
            target_os = "windows"
        )) {
            assert!(!well_known_table().is_empty());
        }
    }

    #[test]
    fn scan_returns_only_existing_paths() {
        // Run on whatever host the test runner is on; the function
        // must not panic and every returned entry must point at an
        // existing file.
        for candidate in scan_well_known_paths() {
            assert!(
                candidate.path.exists(),
                "scan returned non-existent path: {:?}",
                candidate.path
            );
            assert!(!candidate.vendor.is_empty());
        }
    }
}
