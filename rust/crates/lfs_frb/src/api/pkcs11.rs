//! FRB adapter for `lfs_os_security::pkcs11` — module discovery,
//! token enumeration, key listing, and the persist-to-`ssh_keys`
//! import path. Mirrors the FIDO2 shape (`api/fido2.rs`) so the Dart
//! key-manager UI surfaces both backends through a single dispatch
//! layer.
//!
//! Every call wraps the synchronous Cryptoki entry point in
//! `tokio::task::spawn_blocking` — `C_Sign`, `C_Login`,
//! `C_FindObjects` are all blocking syscalls on the underlying
//! .so / .dll, and the FRB worker pool would stall behind a slow
//! token (USB hub re-enumeration after replug routinely takes 200ms+).

use crate::api::frb_err;

/// FRB mirror of `lfs_os_security::pkcs11::discovery::ModuleCandidate`.
/// Rendered by the import wizard's first step.
#[derive(Debug, Clone)]
pub struct DbPkcs11ModuleCandidate {
    pub vendor: String,
    pub path: String,
}

/// FRB mirror of `cryptoki::slot::TokenInfo` — the subset the import
/// wizard's second step needs to render the picker row.
#[derive(Debug, Clone)]
pub struct DbPkcs11TokenInfo {
    pub slot_id: u64,
    pub label: String,
    pub manufacturer: String,
    pub model: String,
    pub serial: String,
    /// `CKF_LOGIN_REQUIRED` — drives the "ask for PIN" prompt.
    pub login_required: bool,
    /// `CKF_PROTECTED_AUTHENTICATION_PATH` — token has a PIN-pad;
    /// skip the in-app PIN prompt and surface the
    /// "confirm on device" toast instead.
    pub protected_auth_path: bool,
    /// `CKF_USER_PIN_FINAL_TRY` — surface the "stop trying" warning
    /// loudly before the user fires one more attempt.
    pub user_pin_final_try: bool,
    /// `CKF_USER_PIN_LOCKED` — token PIN is locked; recovery
    /// requires the SO-PIN / PUK and is out of scope.
    pub user_pin_locked: bool,
}

/// FRB mirror of `pkcs11::key::KeyMeta`. The Dart picker disables
/// rows whose `ssh_key_type` is the empty string (GOST today).
#[derive(Debug, Clone)]
pub struct DbPkcs11KeyMeta {
    pub label: String,
    pub cka_id: Vec<u8>,
    /// SSH key-type short tag (`rsa` / `ecdsa-p256` / `ecdsa-p384` /
    /// `ecdsa-p521` / `ed25519`) or empty for GOST. Drives the
    /// picker's selectability + matches `lfs_core::db::ssh_keys.key_type`.
    pub ssh_key_type: String,
    /// SSH wire-format public-key body (authorized_keys binary).
    pub ssh_public_blob: Vec<u8>,
    /// Human-readable reason rendered on disabled rows. Empty for
    /// signable keys.
    pub disabled_reason: String,
}

/// True when PKCS#11 tokens are reachable on this build target.
/// Sync because the probe is a single cfg check; the well-known
/// scan happens via [`pkcs11_scan_well_known_paths`].
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn pkcs11_is_available() -> bool {
    cfg!(any(
        target_os = "linux",
        target_os = "macos",
        target_os = "windows"
    ))
}

/// Walk the well-known PKCS#11 module paths and return every
/// candidate whose file exists on disk. Mobile builds always
/// return an empty list.
pub async fn pkcs11_scan_well_known_paths() -> Result<Vec<DbPkcs11ModuleCandidate>, String> {
    tokio::task::spawn_blocking(|| {
        let scanned = scan_native();
        Ok::<_, String>(scanned)
    })
    .await
    .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, &format!("spawn_blocking: {e}")))?
}

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
fn scan_native() -> Vec<DbPkcs11ModuleCandidate> {
    lfs_os_security::pkcs11::discovery::scan_well_known_paths()
        .into_iter()
        .map(|c| DbPkcs11ModuleCandidate {
            vendor: c.vendor,
            path: c.path.to_string_lossy().into_owned(),
        })
        .collect()
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
fn scan_native() -> Vec<DbPkcs11ModuleCandidate> {
    Vec::new()
}

/// Probe-load the module at `path`. Surfaces a typed PKCS#11 error
/// envelope when the library cannot be loaded — the UI renders the
/// localized `pkcs11InitializeFailed` toast and offers the
/// "Choose another library" affordance.
pub async fn pkcs11_load_module(path: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || -> Result<(), String> {
        #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
        {
            let _ = lfs_os_security::pkcs11::module::load(std::path::Path::new(&path))
                .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, &e.to_string()))?;
            Ok(())
        }
        #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
        {
            let _ = path; // suppress unused warning
            Err(frb_err::wire(
                frb_err::kind::UNSUPPORTED,
                "pkcs11 not available on this platform",
            ))
        }
    })
    .await
    .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, &format!("spawn_blocking: {e}")))?
}

/// List the tokens (slots-with-token) the module at `path` exposes.
/// Login-required + protected-authentication-path + PIN-counter
/// flags are forwarded so the UI can render the lockout warning
/// before the user types a PIN.
pub async fn pkcs11_list_tokens(path: String) -> Result<Vec<DbPkcs11TokenInfo>, String> {
    tokio::task::spawn_blocking(move || -> Result<Vec<DbPkcs11TokenInfo>, String> {
        #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
        {
            let module = lfs_os_security::pkcs11::module::load(std::path::Path::new(&path))
                .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, &e.to_string()))?;
            let slots = module
                .pkcs11()
                .get_slots_with_token()
                .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, &format!("get_slots: {e}")))?;
            let mut out = Vec::with_capacity(slots.len());
            for slot in slots {
                if let Ok(info) = module.pkcs11().get_token_info(slot) {
                    out.push(DbPkcs11TokenInfo {
                        slot_id: slot.id(),
                        label: info.label().to_string(),
                        manufacturer: info.manufacturer_id().to_string(),
                        model: info.model().to_string(),
                        serial: info.serial_number().to_string(),
                        login_required: info.login_required(),
                        protected_auth_path: info.protected_authentication_path(),
                        user_pin_final_try: info.user_pin_final_try(),
                        user_pin_locked: info.user_pin_locked(),
                    });
                }
            }
            Ok(out)
        }
        #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
        {
            let _ = path;
            Err(frb_err::wire(
                frb_err::kind::UNSUPPORTED,
                "pkcs11 not available on this platform",
            ))
        }
    })
    .await
    .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, &format!("spawn_blocking: {e}")))?
}

/// Enumerate signable keys (CKK_RSA / CKK_EC / CKK_EC_EDWARDS) on
/// the token in `slot_id`. `pin_secret_id` is the SecretStore entry
/// the Dart caller staged after collecting the PIN — `None` for
/// protected-authentication-path tokens or no-login tokens.
pub async fn pkcs11_list_keys(
    path: String,
    slot_id: u64,
    pin_secret_id: Option<String>,
) -> Result<Vec<DbPkcs11KeyMeta>, String> {
    tokio::task::spawn_blocking(move || -> Result<Vec<DbPkcs11KeyMeta>, String> {
        #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
        {
            use lfs_os_security::pkcs11::key::KeyClass;
            let module = lfs_os_security::pkcs11::module::load(std::path::Path::new(&path))
                .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, &e.to_string()))?;
            // Find slot by id.
            let slots = module
                .pkcs11()
                .get_slots_with_token()
                .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, &format!("get_slots: {e}")))?;
            let slot = slots
                .into_iter()
                .find(|s| s.id() == slot_id)
                .ok_or_else(|| {
                    frb_err::wire(
                        frb_err::kind::PKCS11,
                        "unplugged: slot id not found in present-token list",
                    )
                })?;
            let pin = pin_secret_id.as_deref().and_then(|id| {
                lfs_core::app::instance()
                    .secrets
                    .get(id)
                    .and_then(|b| std::str::from_utf8(&b).ok().map(|s| s.to_string()))
            });
            let session = lfs_os_security::pkcs11::session::for_slot(&module, slot);
            let metas = session
                .with_session(pin.as_deref(), |ck| {
                    lfs_os_security::pkcs11::key::list_signable_keys(ck)
                })
                .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, &e.to_string()))?;
            let mut out = Vec::with_capacity(metas.len());
            for m in metas {
                let (ssh_key_type, disabled_reason) = match &m.class {
                    KeyClass::Rsa => ("rsa".to_string(), String::new()),
                    KeyClass::EcdsaP256 => ("ecdsa-p256".into(), String::new()),
                    KeyClass::EcdsaP384 => ("ecdsa-p384".into(), String::new()),
                    KeyClass::EcdsaP521 => ("ecdsa-p521".into(), String::new()),
                    KeyClass::Ed25519 => ("ed25519".into(), String::new()),
                    KeyClass::Gost(_) => (String::new(), "gost-not-supported".into()),
                };
                out.push(DbPkcs11KeyMeta {
                    label: m.label,
                    cka_id: m.id,
                    ssh_key_type,
                    ssh_public_blob: m.ssh_public_blob,
                    disabled_reason,
                });
            }
            Ok(out)
        }
        #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
        {
            let _ = (path, slot_id, pin_secret_id);
            Err(frb_err::wire(
                frb_err::kind::UNSUPPORTED,
                "pkcs11 not available on this platform",
            ))
        }
    })
    .await
    .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, &format!("spawn_blocking: {e}")))?
}

/// Bundled input for [`pkcs11_import_key`].
///
/// `pin_secret_id` is the SecretStore id under which the Dart caller
/// stages the PIN before this hop; we use it once (for the listing /
/// label fetch the import flow drove) and drop it on the way out so
/// the bytes never persist beyond the import.
#[derive(Debug, Clone)]
pub struct DbPkcs11ImportArgs {
    pub label: String,
    pub module_path: String,
    pub token_serial: String,
    pub cka_id: Vec<u8>,
    pub cka_label: String,
    pub ssh_key_type: String,
    pub ssh_public_blob: Vec<u8>,
    /// `pkcs11:` URI (RFC 7512) captured at import. Preferred over
    /// the resolved module path so a re-plug under a different slot
    /// still resolves the same token + object.
    pub pkcs11_uri: String,
}

/// Persist the picked PKCS#11 key as a new `ssh_keys` row. Returns
/// the assigned id. The connect path resolves the row by id +
/// `backend = 'pkcs11'` and reaches into `pkcs11_module_path` +
/// `pkcs11_object_id` for the signing primitives.
pub async fn pkcs11_import_key(args: DbPkcs11ImportArgs) -> Result<String, String> {
    crate::api::db::run_db_mut(move |conn| {
        let row = lfs_core::db::ssh_keys::SshKeyRow {
            id: lfs_core::id::random_handle_hex_32(),
            label: args.label,
            // Hardware-bound rows keep `private_key` non-empty per the
            // schema's `NOT NULL` shape; the empty-string sentinel is
            // the standing convention from the FIDO2 path.
            private_key: String::new(),
            public_key: encode_authorized_keys_line(&args.ssh_public_blob, &args.cka_label),
            key_type: args.ssh_key_type,
            is_generated: false,
            created_at_ms: now_unix_ms(),
            credential_id: None,
            application_string: None,
            has_user_verification: false,
            agent_policy: lfs_core::db::ssh_keys::AgentPolicy::Ask,
            backend: lfs_core::db::ssh_keys::KeyBackend::Pkcs11,
            pkcs11_uri: Some(args.pkcs11_uri),
            pkcs11_module_path: Some(args.module_path),
            pkcs11_token_serial: Some(args.token_serial),
            pkcs11_object_id: Some(args.cka_id),
            pkcs11_object_label: Some(args.cka_label),
            enclave_tag: None,
            hello_credential_name: None,
            tpm_blob: None,
            tpm_handle: None,
            tpm_provider: None,
            tpm_pin_required: false,
            cng_key_name: None,
        };
        lfs_core::db::ssh_keys::import_key_for_merge(conn, &row)
    })
    .await
}

fn encode_authorized_keys_line(blob: &[u8], label: &str) -> String {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    let b64 = STANDARD.encode(blob);
    let algo = match blob.get(0..4) {
        Some([0, 0, 0, len]) if (*len as usize) <= blob.len().saturating_sub(4) => {
            std::str::from_utf8(&blob[4..4 + *len as usize])
                .unwrap_or("ssh-unknown")
                .to_string()
        }
        _ => "ssh-unknown".to_string(),
    };
    if label.is_empty() {
        format!("{algo} {b64}")
    } else {
        format!("{algo} {b64} {label}")
    }
}

fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Parse a `pkcs11:` URI per RFC 7512. Vendored parser; surfaces a
/// typed PKCS#11 error for malformed input so the import wizard's
/// "Paste URI" affordance can route the user back into the picker
/// with a localized reason. Sync because the parser is pure
/// in-process work.
#[flutter_rust_bridge::frb(sync)]
pub fn pkcs11_parse_uri(uri: String) -> Result<DbPkcs11UriParts, String> {
    let parsed = lfs_os_security::pkcs11::uri::Pkcs11Uri::parse(&uri)
        .map_err(|e| frb_err::wire(frb_err::kind::PKCS11, e.0))?;
    Ok(DbPkcs11UriParts {
        token_label: parsed.token,
        serial: parsed.serial,
        object_label: parsed.object,
        object_id: parsed.id,
        module_path: parsed.module_path,
    })
}

/// FRB mirror of the parsed URI subset the import flow consumes.
#[derive(Debug, Clone)]
pub struct DbPkcs11UriParts {
    pub token_label: Option<String>,
    pub serial: Option<String>,
    pub object_label: Option<String>,
    pub object_id: Option<Vec<u8>>,
    pub module_path: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn authorized_keys_line_round_trips() {
        // Build an ed25519 wire body + verify the algo extraction.
        let mut blob = Vec::new();
        blob.extend_from_slice(&(b"ssh-ed25519".len() as u32).to_be_bytes());
        blob.extend_from_slice(b"ssh-ed25519");
        blob.extend_from_slice(&[0xAA; 36]);
        let line = encode_authorized_keys_line(&blob, "my-token");
        assert!(line.starts_with("ssh-ed25519 "));
        assert!(line.ends_with("my-token"));
    }

    #[test]
    fn parse_uri_round_trips_token_label() {
        let r = pkcs11_parse_uri("pkcs11:token=Yubico%20PIV;id=%01".into()).unwrap();
        assert_eq!(r.token_label.as_deref(), Some("Yubico PIV"));
        assert_eq!(r.object_id.unwrap(), vec![0x01]);
    }

    #[test]
    fn is_available_matches_target() {
        let expected = cfg!(any(
            target_os = "linux",
            target_os = "macos",
            target_os = "windows"
        ));
        assert_eq!(pkcs11_is_available(), expected);
    }
}
