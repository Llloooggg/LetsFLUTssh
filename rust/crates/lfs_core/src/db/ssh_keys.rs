//! SshKeys DAO. Backs the Dart `KeyStore` over FRB.
//!
//! **Secret-store angle**: `private_key` is sensitive PEM text. The
//! [`stage_secret_into_store`] helper reads it inside Rust and pushes
//! it directly into the process-singleton SecretStore so the Dart
//! connect path can resolve a saved key by id without ever
//! materialising the bytes on the Dart heap.

use crate::db::Connection;
use rusqlite::params;
use sha2::{Digest, Sha256};

use crate::error::Error;

#[derive(Debug, Clone)]
pub struct SshKeyRow {
    pub id: String,
    pub label: String,
    pub private_key: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    /// Unix-millis at create time. The drift schema stores a
    /// DateTime value as INTEGER milliseconds-since-epoch via
    /// `DateTimeColumn`'s default mapping.
    pub created_at_ms: i64,
    /// FIDO2 credential id captured at import for `sk-*` keys.
    /// `None` (NULL on disk) for software keys; the wrapped CTAP2
    /// blob the device matches against on every assertion for
    /// hardware-bound keys. Routed through
    /// `lfs_core::fido2::get_assertion` on the SSH connect path.
    pub credential_id: Option<Vec<u8>>,
    /// FIDO2 `application` field — the SSH RP-id captured at import
    /// from the `sk-*` public-key wire body. Typically the literal
    /// string `ssh:`. `None` for software keys.
    pub application_string: Option<String>,
    /// User-verification bit captured at import. When `true` the
    /// connect path prompts the user for a PIN; when `false` the
    /// device accepts a touch-only assertion.
    pub has_user_verification: bool,
    /// Per-key dispatch policy for the in-process ssh-agent endpoint
    /// (`lfs_core::ssh_agent`). One of [`AgentPolicy::Always`] /
    /// [`AgentPolicy::Ask`] / [`AgentPolicy::Deny`]. Default `Ask`
    /// keeps the security-first posture: every SIGN_REQUEST from
    /// an external SSH client (`git`, `ssh`, IDE plugin) on the
    /// same host routes through a Flutter confirmation dialog
    /// until the user explicitly promotes the row.
    pub agent_policy: AgentPolicy,
    /// Backend discriminator (schema v9). One of
    /// [`KeyBackend::Software`] / [`KeyBackend::Fido2`] /
    /// [`KeyBackend::Pkcs11`] / [`KeyBackend::Tpm`] /
    /// [`KeyBackend::Enclave`] / [`KeyBackend::Hello`] /
    /// [`KeyBackend::Keystore`]. Drives the connect / agent
    /// dispatcher's typed signer selection. Default
    /// `Software` for pre-hardware-bound rows; the v8 -> v9
    /// migration flipped pre-existing FIDO2 rows to `Fido2` so
    /// the discriminator is exhaustive.
    pub backend: KeyBackend,
    /// RFC 7512 `pkcs11:` URI captured at import. `None` for every
    /// backend other than [`KeyBackend::Pkcs11`]. Preferred over the
    /// resolved module path so a re-plug under a different slot
    /// still resolves the right token + object.
    pub pkcs11_uri: Option<String>,
    /// Resolved on-disk path of the PKCS#11 module the import wizard
    /// loaded. Cached so the loader can fast-path to the same library
    /// next time; verified against the SHA-256 in the pool dedup
    /// key before reuse.
    pub pkcs11_module_path: Option<String>,
    /// PKCS#11 token serial number captured at import. Used by the
    /// connect / sign path to confirm the same physical token is
    /// inserted before reaching for the key — guards against a
    /// re-plug shuffle.
    pub pkcs11_token_serial: Option<String>,
    /// `CKA_ID` blob of the private-key object. Opaque to us; passed
    /// verbatim to `find_objects` on every sign.
    pub pkcs11_object_id: Option<Vec<u8>>,
    /// `CKA_LABEL` of the private-key object (human-readable, the
    /// import wizard captures it for the key-manager row label).
    pub pkcs11_object_label: Option<String>,
    /// Apple Secure Enclave `kSecAttrApplicationTag` bytes. The
    /// `SecItemCopyMatching` lookup on every sign / list / delete
    /// matches on this opaque blob; we generate it at create time
    /// (UUID-suffixed UTF-8 prefix) and persist verbatim. `None` for
    /// every non-enclave backend; the connect path refuses an
    /// `enclave` row whose `enclave_tag` is `None` (DB corruption).
    pub enclave_tag: Option<Vec<u8>>,
    /// Windows Hello (NCrypt / Microsoft Platform Crypto Provider)
    /// persistent-key name. UTF-8 string the
    /// `NCryptOpenKey(provider, &hKey, name, …)` lookup re-binds to
    /// on every sign. `None` for every non-`hello` backend; the
    /// connect path refuses a `hello` row whose
    /// `hello_credential_name` is `None` (DB corruption).
    pub hello_credential_name: Option<String>,
    /// TPM 2.0 wrapped-blob bytes for the Linux blob-storage path.
    /// The bytes are a TSS2 PRIVATE KEY ASN.1 envelope per TCG draft
    /// `draft-bottomley-tpm2-keys-asn1` so the file round-trips with
    /// `ssh-tpm-agent` / `openssl-tpm2-engine`. `None` for the
    /// persistent-handle path (the chip holds the key, no on-disk
    /// blob needed) and for every non-TPM backend. The connect path
    /// requires either `tpm_blob.is_some()` OR `tpm_handle.is_some()`
    /// on a `KeyBackend::Tpm` row; the schema does not enforce the
    /// XOR but the Rust round-trip is the single writer and clamps
    /// the shape at import.
    pub tpm_blob: Option<Vec<u8>>,
    /// Persistent NV handle in the `0x81010001..0x8101FFFF` range
    /// when the key was promoted to TPM RAM, `None` for blob mode.
    /// `i64` on the wire (rusqlite has no native u32) so the value
    /// must round-trip through `u32::try_from` at the boundary —
    /// the column never holds a negative value but the SQL TYPE
    /// is INTEGER.
    pub tpm_handle: Option<u32>,
    /// One of `"tss-esapi"` (Linux ESAPI driver) / `"cng-pcp"`
    /// (Windows PCP silent variant). `None` for every non-TPM row.
    /// The discriminator lets the connect path pick the right
    /// platform module without re-probing.
    pub tpm_provider: Option<String>,
    /// `true` when the key was minted with a `TPM2B_AUTH` value and
    /// requires a per-sign PIN. `false` for headless-server keys
    /// minted with empty auth. Drives the PIN prompt routing on
    /// connect.
    pub tpm_pin_required: bool,
    /// CNG persistent-key name for the Windows PCP silent TPM
    /// variant (no UI policy property set; key signs without firing
    /// a Hello prompt). Uses the `letsflutssh-tpm-<userhash>-<uuid>`
    /// prefix to distinguish from Hello-gated `letsflutssh-ssh-…`
    /// keys when `NCryptEnumKeys` walks the provider. `None` for
    /// Linux TPM keys and every non-TPM backend.
    pub cng_key_name: Option<String>,
    /// Android Hardware Keystore alias. UTF-8 string the
    /// `KeyStore.getInstance("AndroidKeyStore").getEntry(alias, null)`
    /// lookup rebinds to on every sign. Owned by the `lfs-keystore-`
    /// prefix to keep our keys separate from the `FlutterSecureStorageKeyAlias_`
    /// wrapping-key namespace `lfs_os_security::android::keystore`
    /// already owns. `None` for every non-`keystore` backend; the
    /// connect path refuses a `keystore` row whose `keystore_alias`
    /// is `None` (DB corruption).
    pub keystore_alias: Option<String>,
    /// `true` when the key was minted with `setIsStrongBoxBacked(true)`
    /// and the StrongBox HSM accepted the request. `false` for
    /// TEE-backed keys and for every non-Keystore row. Surfaced in
    /// the badge popover so the user can tell a StrongBox row from a
    /// TEE one without re-probing.
    pub keystore_strongbox: bool,
    /// `true` when the key was minted with
    /// `setUserAuthenticationRequired(true)`. Every sign hops through
    /// `BiometricPrompt.CryptoObject(signature)`; without an
    /// authenticated cipher object the `Signature.initSign` call
    /// throws `UserNotAuthenticatedException`. `false` for empty-auth
    /// rows (none today — the wizard always sets it true) and every
    /// non-Keystore row.
    pub keystore_user_auth_required: bool,
    /// Free-form platform identifier captured at create time —
    /// `android.os.Build.MODEL` + `Build.VERSION.RELEASE`. `None` on
    /// rows minted before this column landed and for every
    /// non-Keystore backend. Surfaced in the badge popover; the
    /// connect path does NOT use it for routing (key resolution
    /// goes via `keystore_alias` alone).
    pub keystore_platform: Option<String>,
    /// `true` when the row landed as a public-half-only stub via
    /// `.lfs` archive import or WebDAV sync pull for a device-bound
    /// backend (Apple Secure Enclave / Windows Hello / TPM / Android
    /// Keystore). The private side cannot travel between devices for
    /// those backends; the stub carries label + public key + backend
    /// discriminator so the key manager renders "this is the key
    /// that was on the other device, re-generate it here". The
    /// session-edit "Key from manager" picker disables stub rows.
    /// Cleared when the user picks "Re-generate here" / "Remove" on
    /// the stub row. `false` for every locally generated row and for
    /// every backend that travels its portable subset across the
    /// wire (software / FIDO2 / PKCS#11).
    pub imported_as_stub: bool,
}

/// Backend discriminator on `ssh_keys.backend` (schema v9). Drives
/// the connect / agent-endpoint dispatcher's typed signer selection.
/// Stored as TEXT so the on-disk shape stays declarative; the Rust
/// round-trip is the single writer and clamps the value.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyBackend {
    /// Plain-text private-key PEM stored alongside the row. The
    /// agent endpoint MUST NOT expose these rows externally; the
    /// connect path uses `private_key` verbatim.
    Software,
    /// FIDO2 sk-* key — `credential_id` + `application_string`
    /// + `has_user_verification` carry the CTAP2 metadata.
    Fido2,
    /// PKCS#11 smart-card / hardware-token — `pkcs11_*` columns
    /// carry the URI + slot + object id.
    Pkcs11,
    /// TPM 2.0 (Linux ESAPI / Windows PCP). Reserved.
    Tpm,
    /// Apple Secure Enclave. Reserved.
    Enclave,
    /// Windows Hello (NCrypt). Reserved.
    Hello,
    /// Android Hardware Keystore (StrongBox / TEE). Reserved.
    Keystore,
}

impl KeyBackend {
    /// Parse the TEXT column value. Unknown values fall back to
    /// `Software` so a future schema additions / corrupted DB stays
    /// safe-by-default rather than promoting an unknown row to a
    /// hardware-bound signer that doesn't exist.
    pub fn from_db(s: &str) -> Self {
        match s {
            "fido2" => Self::Fido2,
            "pkcs11" => Self::Pkcs11,
            "tpm" => Self::Tpm,
            "enclave" => Self::Enclave,
            "hello" => Self::Hello,
            "keystore" => Self::Keystore,
            _ => Self::Software,
        }
    }

    /// Serialize for the TEXT column.
    pub fn as_db_str(self) -> &'static str {
        match self {
            Self::Software => "software",
            Self::Fido2 => "fido2",
            Self::Pkcs11 => "pkcs11",
            Self::Tpm => "tpm",
            Self::Enclave => "enclave",
            Self::Hello => "hello",
            Self::Keystore => "keystore",
        }
    }
}

/// Per-key dispatch policy for the in-process ssh-agent endpoint.
/// Persisted as TEXT on `ssh_keys.agent_policy` so the DB layer
/// can keep the column declarative (`CHECK` not enforced today,
/// but the Rust round-trip is the single writer and clamps the
/// shape).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentPolicy {
    /// Sign silently. Skip the Flutter confirmation dialog. The
    /// hardware backend's own touch / PIN prompt still fires when
    /// the credential carries the user-verification bit.
    Always,
    /// Route every SIGN_REQUEST through a Flutter confirmation
    /// dialog. Default for newly imported keys.
    Ask,
    /// Refuse SIGN_REQUEST with `SSH_AGENT_FAILURE`. The
    /// `request_identities` listing still includes the row so the
    /// external client sees the key exists but signing is barred.
    Deny,
}

impl AgentPolicy {
    /// Parse the TEXT column value. Unknown values fall back to
    /// `Ask` so a future schema additions / corrupted DB stays
    /// safe-by-default rather than promoting an unknown row to
    /// silent-sign.
    pub fn from_db(s: &str) -> Self {
        match s {
            "always" => Self::Always,
            "deny" => Self::Deny,
            _ => Self::Ask,
        }
    }

    /// Serialize for the TEXT column.
    pub fn as_db_str(self) -> &'static str {
        match self {
            Self::Always => "always",
            Self::Ask => "ask",
            Self::Deny => "deny",
        }
    }
}

fn row_from(row: &rusqlite::Row<'_>) -> rusqlite::Result<SshKeyRow> {
    let agent_policy_raw: String = row.get("agent_policy")?;
    let backend_raw: String = row.get("backend")?;
    Ok(SshKeyRow {
        id: row.get("id")?,
        label: row.get("label")?,
        private_key: row.get("private_key")?,
        public_key: row.get("public_key")?,
        key_type: row.get("key_type")?,
        // drift maps Bool to int 0/1
        is_generated: row.get::<_, i64>("is_generated")? != 0,
        created_at_ms: row.get("created_at")?,
        credential_id: row.get("credential_id")?,
        application_string: row.get("application_string")?,
        has_user_verification: row.get::<_, i64>("has_user_verification")? != 0,
        agent_policy: AgentPolicy::from_db(&agent_policy_raw),
        backend: KeyBackend::from_db(&backend_raw),
        pkcs11_uri: row.get("pkcs11_uri")?,
        pkcs11_module_path: row.get("pkcs11_module_path")?,
        pkcs11_token_serial: row.get("pkcs11_token_serial")?,
        pkcs11_object_id: row.get("pkcs11_object_id")?,
        pkcs11_object_label: row.get("pkcs11_object_label")?,
        enclave_tag: row.get("enclave_tag")?,
        hello_credential_name: row.get("hello_credential_name")?,
        tpm_blob: row.get("tpm_blob")?,
        // SQLite carries INTEGER as i64; clamp to u32 at the
        // boundary so the schema's persistent-handle range
        // (`0x81010001..0x8101FFFF`) round-trips. Out-of-range
        // values stored by a hypothetical future writer would land
        // as None rather than wrap.
        tpm_handle: row
            .get::<_, Option<i64>>("tpm_handle")?
            .and_then(|v| u32::try_from(v).ok()),
        tpm_provider: row.get("tpm_provider")?,
        tpm_pin_required: row.get::<_, i64>("tpm_pin_required")? != 0,
        cng_key_name: row.get("cng_key_name")?,
        keystore_alias: row.get("keystore_alias")?,
        keystore_strongbox: row.get::<_, i64>("keystore_strongbox")? != 0,
        keystore_user_auth_required: row.get::<_, i64>("keystore_user_auth_required")? != 0,
        keystore_platform: row.get("keystore_platform")?,
        imported_as_stub: row.get::<_, i64>("imported_as_stub")? != 0,
    })
}

pub fn list_all(conn: &impl crate::db::DbAccess) -> Result<Vec<SshKeyRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at, \
                    credential_id, application_string, has_user_verification, agent_policy, \
                    backend, pkcs11_uri, pkcs11_module_path, pkcs11_token_serial, \
                    pkcs11_object_id, pkcs11_object_label, enclave_tag, \
                    hello_credential_name, tpm_blob, tpm_handle, tpm_provider, \
                    tpm_pin_required, cng_key_name, keystore_alias, \
                    keystore_strongbox, keystore_user_auth_required, keystore_platform, \
                    imported_as_stub \
             FROM ssh_keys WHERE deleted_at IS NULL ORDER BY created_at DESC",
        )
        .map_err(|e| Error::Db(format!("ssh_keys list prepare: {e}")))?;
    let rows = stmt
        .query_map([], row_from)
        .map_err(|e| Error::Db(format!("ssh_keys list query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("ssh_keys row: {e}")))?);
    }
    Ok(out)
}

pub fn get(conn: &impl crate::db::DbAccess, id: &str) -> Result<Option<SshKeyRow>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at, \
                    credential_id, application_string, has_user_verification, agent_policy, \
                    backend, pkcs11_uri, pkcs11_module_path, pkcs11_token_serial, \
                    pkcs11_object_id, pkcs11_object_label, enclave_tag, \
                    hello_credential_name, tpm_blob, tpm_handle, tpm_provider, \
                    tpm_pin_required, cng_key_name, keystore_alias, \
                    keystore_strongbox, keystore_user_auth_required, keystore_platform, \
                    imported_as_stub \
             FROM ssh_keys WHERE id = ?1 AND deleted_at IS NULL",
        )
        .map_err(|e| Error::Db(format!("ssh_keys get prepare: {e}")))?;
    let mut rows = stmt
        .query_map(params![id], row_from)
        .map_err(|e| Error::Db(format!("ssh_keys get query: {e}")))?;
    match rows.next() {
        Some(Ok(row)) => Ok(Some(row)),
        Some(Err(e)) => Err(Error::Db(format!("ssh_keys get row: {e}"))),
        None => Ok(None),
    }
}

pub fn upsert(conn: &impl crate::db::DbAccess, row: &SshKeyRow) -> Result<(), Error> {
    conn.raw().execute(
        "INSERT INTO ssh_keys (id, label, private_key, public_key, key_type, is_generated, created_at, \
                               credential_id, application_string, has_user_verification, agent_policy, \
                               backend, pkcs11_uri, pkcs11_module_path, pkcs11_token_serial, \
                               pkcs11_object_id, pkcs11_object_label, enclave_tag, \
                               hello_credential_name, tpm_blob, tpm_handle, tpm_provider, \
                               tpm_pin_required, cng_key_name, keystore_alias, \
                               keystore_strongbox, keystore_user_auth_required, keystore_platform, \
                               imported_as_stub) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29) \
         ON CONFLICT(id) DO UPDATE SET \
           label = excluded.label, \
           private_key = excluded.private_key, \
           public_key = excluded.public_key, \
           key_type = excluded.key_type, \
           is_generated = excluded.is_generated, \
           created_at = excluded.created_at, \
           credential_id = excluded.credential_id, \
           application_string = excluded.application_string, \
           has_user_verification = excluded.has_user_verification, \
           agent_policy = excluded.agent_policy, \
           backend = excluded.backend, \
           pkcs11_uri = excluded.pkcs11_uri, \
           pkcs11_module_path = excluded.pkcs11_module_path, \
           pkcs11_token_serial = excluded.pkcs11_token_serial, \
           pkcs11_object_id = excluded.pkcs11_object_id, \
           pkcs11_object_label = excluded.pkcs11_object_label, \
           enclave_tag = excluded.enclave_tag, \
           hello_credential_name = excluded.hello_credential_name, \
           tpm_blob = excluded.tpm_blob, \
           tpm_handle = excluded.tpm_handle, \
           tpm_provider = excluded.tpm_provider, \
           tpm_pin_required = excluded.tpm_pin_required, \
           cng_key_name = excluded.cng_key_name, \
           keystore_alias = excluded.keystore_alias, \
           keystore_strongbox = excluded.keystore_strongbox, \
           keystore_user_auth_required = excluded.keystore_user_auth_required, \
           keystore_platform = excluded.keystore_platform, \
           imported_as_stub = excluded.imported_as_stub, \
           deleted_at = NULL",
        params![
            row.id,
            row.label,
            row.private_key,
            row.public_key,
            row.key_type,
            if row.is_generated { 1 } else { 0 },
            row.created_at_ms,
            row.credential_id,
            row.application_string,
            if row.has_user_verification { 1 } else { 0 },
            row.agent_policy.as_db_str(),
            row.backend.as_db_str(),
            row.pkcs11_uri,
            row.pkcs11_module_path,
            row.pkcs11_token_serial,
            row.pkcs11_object_id,
            row.pkcs11_object_label,
            row.enclave_tag,
            row.hello_credential_name,
            row.tpm_blob,
            row.tpm_handle.map(|h| h as i64),
            row.tpm_provider,
            if row.tpm_pin_required { 1 } else { 0 },
            row.cng_key_name,
            row.keystore_alias,
            if row.keystore_strongbox { 1 } else { 0 },
            if row.keystore_user_auth_required { 1 } else { 0 },
            row.keystore_platform,
            if row.imported_as_stub { 1 } else { 0 },
        ],
    )
    .map_err(|e| Error::Db(format!("ssh_keys upsert: {e}")))?;
    Ok(())
}

/// Listing-only view of an `ssh_keys` row. Carries the metadata
/// needed by the key manager / import-dedup / export-selection UIs
/// **without** the `private_key` PEM bytes. `private_fingerprint`
/// and `public_fingerprint` are pre-hashed inside Rust so that
/// dedup paths (`SshDirImportDialog`, etc.) can compare against
/// scanned key material without ever pulling the PEM through the
/// FRB boundary.
#[derive(Debug, Clone)]
pub struct SshKeyMetadata {
    pub id: String,
    pub label: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    pub created_at_ms: i64,
    /// SHA-256 hex of the normalized PEM (trimmed, CRLF→LF), or the
    /// empty string if the row has no private key. Mirrors
    /// `KeyStore.privateKeyFingerprint` exactly so existing dedup
    /// sets continue to compare against scanned PEMs.
    pub private_fingerprint: String,
    /// SHA-256 hex of the normalized OpenSSH public key, or the
    /// empty string if the row has no public half. Mirrors
    /// `KeyStore.publicKeyFingerprint`.
    pub public_fingerprint: String,
    /// Backend discriminator (schema v9). One of `software` / `fido2` /
    /// `pkcs11` / `tpm` / `enclave` / `hello` / `keystore`. Surfaced
    /// here so the key-manager UI can pick the correct badge variant
    /// without a second FRB hop.
    pub backend: String,
    /// PKCS#11 module path captured at import. `None` for non-PKCS#11
    /// rows; carried so the info popover can show which vendor
    /// library serviced the token.
    pub pkcs11_module_path: Option<String>,
    /// PKCS#11 token serial captured at import.
    pub pkcs11_token_serial: Option<String>,
    /// PKCS#11 object label (`CKA_LABEL`). Distinct from the row's
    /// `label` (user-typed), which may diverge from the on-token name.
    pub pkcs11_object_label: Option<String>,
    /// Windows Hello CNG persistent-key name captured at import.
    /// `None` for non-`hello` rows; surfaced so the key-manager UI
    /// can render the row badge's info popover with the CNG name.
    pub hello_credential_name: Option<String>,
    /// TPM 2.0 row ingredients exposed for the badge popover (the
    /// PEM-wrapped blob bytes themselves stay Rust-side — only the
    /// discriminator + lookup ingredients cross). `tpm_handle`
    /// `None` = on-disk wrapped blob; `Some(handle)` = persistent
    /// NV slot. `tpm_provider` is `"tss-esapi"` / `"cng-pcp"`.
    pub tpm_handle: Option<u32>,
    pub tpm_provider: Option<String>,
    pub tpm_pin_required: bool,
    pub cng_key_name: Option<String>,
    /// Android Keystore alias for `backend = 'keystore'` rows. Surfaced
    /// for the `KeystoreBadge` info popover (truncated for display).
    /// `None` for every non-Keystore row.
    pub keystore_alias: Option<String>,
    /// `true` when the row's hardware key was minted with
    /// `setIsStrongBoxBacked(true)`. Drives the badge label split
    /// ("StrongBox HSM" vs "TEE").
    pub keystore_strongbox: bool,
    /// `true` when the row requires biometric / device-unlock auth
    /// on every sign. Always `true` for current Keystore rows;
    /// reserved for a future no-auth variant.
    pub keystore_user_auth_required: bool,
    /// Capture-time `Build.MODEL` + Android version (e.g.
    /// `"Pixel 8 (Android 14)"`). Surfaced read-only in the badge
    /// popover so users on multi-device deployments can identify
    /// which phone holds the key.
    pub keystore_platform: Option<String>,
    /// `true` when the row landed via `.lfs` archive import / WebDAV
    /// sync pull as a public-half-only stub for a device-bound
    /// backend. Drives the key manager's desaturated render + the
    /// session-edit picker disable. See [`SshKeyRow::imported_as_stub`]
    /// for the full contract.
    pub imported_as_stub: bool,
}

pub fn list_metadata(conn: &impl crate::db::DbAccess) -> Result<Vec<SshKeyMetadata>, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached(
            "SELECT id, label, private_key, public_key, key_type, is_generated, created_at, \
                    credential_id, application_string, has_user_verification, agent_policy, \
                    backend, pkcs11_uri, pkcs11_module_path, pkcs11_token_serial, \
                    pkcs11_object_id, pkcs11_object_label, enclave_tag, \
                    hello_credential_name, tpm_blob, tpm_handle, tpm_provider, \
                    tpm_pin_required, cng_key_name, keystore_alias, \
                    keystore_strongbox, keystore_user_auth_required, keystore_platform, \
                    imported_as_stub \
             FROM ssh_keys WHERE deleted_at IS NULL ORDER BY created_at DESC \
             /* list_metadata */",
        )
        .map_err(|e| Error::Db(format!("ssh_keys list_metadata prepare: {e}")))?;
    let rows = stmt
        .query_map([], |row| {
            let private_key: String = row.get("private_key")?;
            let public_key: String = row.get("public_key")?;
            let backend_raw: String = row.get("backend")?;
            Ok(SshKeyMetadata {
                id: row.get("id")?,
                label: row.get("label")?,
                key_type: row.get("key_type")?,
                is_generated: row.get::<_, i64>("is_generated")? != 0,
                created_at_ms: row.get("created_at")?,
                private_fingerprint: normalized_sha256_hex(&private_key),
                public_fingerprint: normalized_sha256_hex(&public_key),
                public_key,
                backend: KeyBackend::from_db(&backend_raw).as_db_str().to_string(),
                pkcs11_module_path: row.get("pkcs11_module_path")?,
                pkcs11_token_serial: row.get("pkcs11_token_serial")?,
                pkcs11_object_label: row.get("pkcs11_object_label")?,
                hello_credential_name: row.get("hello_credential_name")?,
                tpm_handle: row
                    .get::<_, Option<i64>>("tpm_handle")?
                    .and_then(|v| u32::try_from(v).ok()),
                tpm_provider: row.get("tpm_provider")?,
                tpm_pin_required: row.get::<_, i64>("tpm_pin_required")? != 0,
                cng_key_name: row.get("cng_key_name")?,
                keystore_alias: row.get("keystore_alias")?,
                keystore_strongbox: row.get::<_, i64>("keystore_strongbox")? != 0,
                keystore_user_auth_required: row.get::<_, i64>("keystore_user_auth_required")? != 0,
                keystore_platform: row.get("keystore_platform")?,
                imported_as_stub: row.get::<_, i64>("imported_as_stub")? != 0,
            })
        })
        .map_err(|e| Error::Db(format!("ssh_keys list_metadata query: {e}")))?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| Error::Db(format!("ssh_keys list_metadata row: {e}")))?);
    }
    Ok(out)
}

/// Mirrors `KeyStore.privateKeyFingerprint` /
/// `KeyStore.publicKeyFingerprint`: trim, CRLF→LF, SHA-256 hex.
/// Empty input returns an empty string so set-membership checks
/// don't false-match on missing keys.
fn normalized_sha256_hex(s: &str) -> String {
    let normalized = s.replace("\r\n", "\n");
    let trimmed = normalized.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let mut hasher = Sha256::new();
    hasher.update(trimmed.as_bytes());
    let digest = hasher.finalize();
    let mut hex = String::with_capacity(digest.len() * 2);
    for b in digest.iter() {
        use std::fmt::Write as _;
        let _ = write!(hex, "{b:02x}");
    }
    hex
}

/// Replace the live `ssh_keys` set with `rows` inside a single
/// transaction. Used by `KeysNotifier.saveAll` in place of N
/// delete + N upsert FRB hops — the per-row hop is the dominant
/// cost when the notifier flushes its in-memory cache.
///
/// Soft-delete shape: the clearing step tombstones every live
/// row, then each row in `rows` is upserted with
/// `deleted_at = NULL` so collisions revive existing keys rather
/// than fail the insert. The net effect on `list_all` is the same
/// as the old physical-delete model — only the supplied set is
/// visible afterwards — but the residual tombstones let a
/// sync-merge replay the removal across devices. Physical
/// teardown of the tombstones runs through
/// [`purge_tombstones`].
///
/// Atomicity: the tombstone + upserts run inside a single
/// `conn.inner_mut().transaction()`; a failure mid-loop rolls
/// back so the table never lands half-cleared.
pub fn replace_all(conn: &mut Connection, rows: &[SshKeyRow]) -> Result<(), Error> {
    let now_ms = now_unix_ms();
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("ssh_keys replace_all: begin tx: {e}")))?;
    tx.execute(
        "UPDATE ssh_keys SET deleted_at = ?1 WHERE deleted_at IS NULL",
        params![now_ms],
    )
    .map_err(|e| Error::Db(format!("ssh_keys replace_all: tombstone: {e}")))?;
    {
        let mut stmt = tx
            .prepare_cached(
                "INSERT INTO ssh_keys (id, label, private_key, public_key, key_type, is_generated, created_at, \
                                       credential_id, application_string, has_user_verification, agent_policy, \
                                       backend, pkcs11_uri, pkcs11_module_path, pkcs11_token_serial, \
                                       pkcs11_object_id, pkcs11_object_label, enclave_tag, \
                                       hello_credential_name, tpm_blob, tpm_handle, tpm_provider, \
                                       tpm_pin_required, cng_key_name, keystore_alias, \
                                       keystore_strongbox, keystore_user_auth_required, keystore_platform, \
                                       imported_as_stub) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29) \
                 ON CONFLICT(id) DO UPDATE SET \
                   label = excluded.label, \
                   private_key = excluded.private_key, \
                   public_key = excluded.public_key, \
                   key_type = excluded.key_type, \
                   is_generated = excluded.is_generated, \
                   created_at = excluded.created_at, \
                   credential_id = excluded.credential_id, \
                   application_string = excluded.application_string, \
                   has_user_verification = excluded.has_user_verification, \
                   agent_policy = excluded.agent_policy, \
                   backend = excluded.backend, \
                   pkcs11_uri = excluded.pkcs11_uri, \
                   pkcs11_module_path = excluded.pkcs11_module_path, \
                   pkcs11_token_serial = excluded.pkcs11_token_serial, \
                   pkcs11_object_id = excluded.pkcs11_object_id, \
                   pkcs11_object_label = excluded.pkcs11_object_label, \
                   enclave_tag = excluded.enclave_tag, \
                   hello_credential_name = excluded.hello_credential_name, \
                   tpm_blob = excluded.tpm_blob, \
                   tpm_handle = excluded.tpm_handle, \
                   tpm_provider = excluded.tpm_provider, \
                   tpm_pin_required = excluded.tpm_pin_required, \
                   cng_key_name = excluded.cng_key_name, \
                   keystore_alias = excluded.keystore_alias, \
                   keystore_strongbox = excluded.keystore_strongbox, \
                   keystore_user_auth_required = excluded.keystore_user_auth_required, \
                   keystore_platform = excluded.keystore_platform, \
                   imported_as_stub = excluded.imported_as_stub, \
                   deleted_at = NULL",
            )
            .map_err(|e| Error::Db(format!("ssh_keys replace_all: prepare insert: {e}")))?;
        for row in rows {
            stmt.execute(params![
                row.id,
                row.label,
                row.private_key,
                row.public_key,
                row.key_type,
                if row.is_generated { 1 } else { 0 },
                row.created_at_ms,
                row.credential_id,
                row.application_string,
                if row.has_user_verification { 1 } else { 0 },
                row.agent_policy.as_db_str(),
                row.backend.as_db_str(),
                row.pkcs11_uri,
                row.pkcs11_module_path,
                row.pkcs11_token_serial,
                row.pkcs11_object_id,
                row.pkcs11_object_label,
                row.enclave_tag,
                row.hello_credential_name,
                row.tpm_blob,
                row.tpm_handle.map(|h| h as i64),
                row.tpm_provider,
                if row.tpm_pin_required { 1 } else { 0 },
                row.cng_key_name,
                row.keystore_alias,
                if row.keystore_strongbox { 1 } else { 0 },
                if row.keystore_user_auth_required {
                    1
                } else {
                    0
                },
                row.keystore_platform,
                if row.imported_as_stub { 1 } else { 0 },
            ])
            .map_err(|e| Error::Db(format!("ssh_keys replace_all: insert: {e}")))?;
        }
    }
    tx.commit()
        .map_err(|e| Error::Db(format!("ssh_keys replace_all: commit: {e}")))?;
    Ok(())
}

/// Soft-delete a single stored key by id. Flips `deleted_at` to
/// `now_unix_ms()`; the row survives so the sync-merge layer
/// (`§8b`) can replay the deletion. `ON DELETE CASCADE` on
/// `ssh_key_certificates.key_id` is preserved because the
/// physical row is not removed — the cert table is kept in
/// lock-step manually wherever the connect path resolves the
/// key; see ARCHITECTURE.md §11.
pub fn delete(conn: &impl crate::db::DbAccess, id: &str) -> Result<usize, Error> {
    let now_ms = now_unix_ms();
    let n = conn
        .raw()
        .execute(
            "UPDATE ssh_keys SET deleted_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now_ms, id],
        )
        .map_err(|e| Error::Db(format!("ssh_keys delete: {e}")))?;
    Ok(n)
}

/// Physically remove `ssh_keys` rows whose `deleted_at` is older
/// than `before_ms`. Reserved for sync-merge teardown (`§8b`);
/// production paths use [`delete`] / [`replace_all`].
pub fn purge_tombstones(conn: &impl crate::db::DbAccess, before_ms: i64) -> Result<u32, Error> {
    conn.raw()
        .execute(
            "DELETE FROM ssh_keys WHERE deleted_at IS NOT NULL AND deleted_at < ?1",
            params![before_ms],
        )
        .map(|n| n as u32)
        .map_err(|e| Error::Db(format!("ssh_keys purge_tombstones: {e}")))
}

/// Current unix-millis. Shared across every soft-delete path in
/// this DAO so the `deleted_at` stamp matches `created_at` shape.
fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Composite import — looks up an existing key by content
/// fingerprint (public-key first, falling back to private-key);
/// returns the existing id when a match is found. Otherwise mints
/// a new id (when the proposed id collides with a stored key) and
/// inserts a fresh row under a unique-suffixed label. All in one
/// transaction.
///
/// Returns the id the caller should use downstream (existing or
/// freshly inserted). Mirrors the Dart
/// `KeyStore.importForMerge` orchestration; folding the steps
/// Rust-side keeps the dedup-by-fingerprint + label-uniqueness +
/// insert sequence atomic and lets the Dart caller drop to a
/// single FRB call.
pub fn import_key_for_merge(conn: &mut Connection, proposed: &SshKeyRow) -> Result<String, Error> {
    use rand::Rng;
    let tx = conn
        .inner_mut()
        .transaction()
        .map_err(|e| Error::Db(format!("ssh_keys import_for_merge tx: {e}")))?;

    let public_target = crate::keys::normalized_text_fingerprint(&proposed.public_key);
    let private_target = crate::keys::normalized_text_fingerprint(&proposed.private_key);

    // Two-phase fingerprint lookup mirrors the Dart side: public
    // wins (cheap, never touches private material); private is the
    // fallback for stored rows that have no public key.
    let metadata = list_metadata(&tx)?;
    if !public_target.is_empty() {
        if let Some(found) = metadata
            .iter()
            .find(|m| m.public_fingerprint == public_target)
        {
            return Ok(found.id.clone());
        }
    } else if !private_target.is_empty() {
        if let Some(found) = metadata
            .iter()
            .find(|m| m.private_fingerprint == private_target)
        {
            return Ok(found.id.clone());
        }
    }

    // No content match — insert a fresh row. Uniqueify the label
    // against the live set, mint a new id when the proposed id
    // collides with a stored key.
    let labels: std::collections::HashSet<String> =
        metadata.iter().map(|m| m.label.clone()).collect();
    let new_label = crate::sessions::unique_label(&proposed.label, &labels);
    let id_collision = metadata.iter().any(|m| m.id == proposed.id);
    let new_id = if id_collision {
        let mut bytes = [0u8; 16];
        rand::rng().fill_bytes(&mut bytes);
        bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
    } else {
        proposed.id.clone()
    };

    upsert(
        &tx,
        &SshKeyRow {
            id: new_id.clone(),
            label: new_label,
            private_key: proposed.private_key.clone(),
            public_key: proposed.public_key.clone(),
            key_type: proposed.key_type.clone(),
            is_generated: proposed.is_generated,
            created_at_ms: proposed.created_at_ms,
            credential_id: proposed.credential_id.clone(),
            application_string: proposed.application_string.clone(),
            has_user_verification: proposed.has_user_verification,
            agent_policy: proposed.agent_policy,
            backend: proposed.backend,
            pkcs11_uri: proposed.pkcs11_uri.clone(),
            pkcs11_module_path: proposed.pkcs11_module_path.clone(),
            pkcs11_token_serial: proposed.pkcs11_token_serial.clone(),
            pkcs11_object_id: proposed.pkcs11_object_id.clone(),
            pkcs11_object_label: proposed.pkcs11_object_label.clone(),
            enclave_tag: proposed.enclave_tag.clone(),
            hello_credential_name: proposed.hello_credential_name.clone(),
            tpm_blob: proposed.tpm_blob.clone(),
            tpm_handle: proposed.tpm_handle,
            tpm_provider: proposed.tpm_provider.clone(),
            tpm_pin_required: proposed.tpm_pin_required,
            cng_key_name: proposed.cng_key_name.clone(),
            keystore_alias: proposed.keystore_alias.clone(),
            keystore_strongbox: proposed.keystore_strongbox,
            keystore_user_auth_required: proposed.keystore_user_auth_required,
            keystore_platform: proposed.keystore_platform.clone(),
            imported_as_stub: proposed.imported_as_stub,
        },
    )?;
    tx.commit()
        .map_err(|e| Error::Db(format!("ssh_keys import_for_merge commit: {e}")))?;
    Ok(new_id)
}

/// Persist resolved PKCS#11 module path back onto the row after a
/// first-use re-bind. The Signer scans `well_known_paths` keyed by
/// `pkcs11_token_serial`; on hit it calls this helper so the next
/// connect short-circuits the scan. No-op when the row is not a
/// PKCS#11 backend or the new path equals what is already stored.
pub fn set_pkcs11_module_path(
    conn: &impl crate::db::DbAccess,
    key_id: &str,
    module_path: &str,
) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "UPDATE ssh_keys SET pkcs11_module_path = ?1 \
             WHERE id = ?2 AND deleted_at IS NULL AND backend = 'pkcs11'",
            params![module_path, key_id],
        )
        .map_err(|e| Error::Db(format!("ssh_keys set_pkcs11_module_path: {e}")))
}

/// Clear the `imported_as_stub` flag on `key_id`. Called when the
/// user picks "Re-generate here" on a stub row (the regenerate
/// path writes a fresh hardware-backed row over the public-half) or
/// confirms "Remove stub" (the delete path soft-tombstones the row,
/// at which point the flag is irrelevant — clearing keeps the
/// semantics consistent with a refresh of the row). The wizard's
/// regenerate flow upserts a full row in one shot today, which
/// implicitly clears the column via the upsert; this helper is the
/// targeted path the UI uses when the user wants to manually
/// "promote" the row to live status without regenerating.
pub fn clear_stub_flag(conn: &impl crate::db::DbAccess, key_id: &str) -> Result<usize, Error> {
    conn.raw()
        .execute(
            "UPDATE ssh_keys SET imported_as_stub = 0 \
             WHERE id = ?1 AND deleted_at IS NULL",
            params![key_id],
        )
        .map_err(|e| Error::Db(format!("ssh_keys clear_stub_flag: {e}")))
}

/// Canonical secret-store id for a stored key's private PEM bytes.
/// Mirrors the `sess.<slot>.<id>` pattern used by the sessions DAO.
pub fn private_key_secret_id(key_id: &str) -> String {
    format!("key.priv.{key_id}")
}

/// Read `private_key` for [`key_id`] and push its bytes into the
/// process-singleton SecretStore under [`private_key_secret_id`].
/// Returns `Ok(true)` when something landed in the store, `Ok(false)`
/// when the row is missing or the column is empty. Plaintext never
/// crosses the FRB boundary back to Dart — the Dart connect path
/// only sees the secret id and constructs the matching
/// `SshAuthPubkeyRef` variant.
pub fn stage_secret_into_store(
    conn: &impl crate::db::DbAccess,
    key_id: &str,
) -> Result<bool, Error> {
    let mut stmt = conn
        .raw()
        .prepare_cached("SELECT private_key FROM ssh_keys WHERE id = ?1 AND deleted_at IS NULL")
        .map_err(|e| Error::Db(format!("ssh_keys stage prepare: {e}")))?;
    let private_key: Option<String> = stmt.query_row(params![key_id], |row| row.get(0)).ok();
    let Some(pem) = private_key else {
        return Ok(false);
    };
    if pem.is_empty() {
        return Ok(false);
    }
    let store = &crate::app::instance().secrets;
    store.put(&private_key_secret_id(key_id), pem.as_bytes());
    Ok(true)
}

#[cfg(test)]
mod import_for_merge_tests {
    use super::*;
    use crate::db::{bootstrap_schema, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn key(id: &str, label: &str, public: &str, private: &str) -> SshKeyRow {
        SshKeyRow {
            id: id.into(),
            label: label.into(),
            private_key: private.into(),
            public_key: public.into(),
            key_type: "ed25519".into(),
            is_generated: false,
            created_at_ms: 0,
            credential_id: None,
            application_string: None,
            has_user_verification: false,
            agent_policy: AgentPolicy::Ask,
            backend: KeyBackend::Software,
            pkcs11_uri: None,
            pkcs11_module_path: None,
            pkcs11_token_serial: None,
            pkcs11_object_id: None,
            pkcs11_object_label: None,
            enclave_tag: None,
            hello_credential_name: None,
            tpm_blob: None,
            tpm_handle: None,
            tpm_provider: None,
            tpm_pin_required: false,
            cng_key_name: None,
            keystore_alias: None,
            keystore_strongbox: false,
            keystore_user_auth_required: false,
            keystore_platform: None,
            imported_as_stub: false,
        }
    }

    #[test]
    fn import_for_merge_returns_existing_id_on_public_match() {
        let db = db();
        db.with_conn(|c| upsert(c, &key("existing", "lab", "PUB1\n", "PRIV1")))
            .unwrap();
        let proposed = key("imported", "Different label", "PUB1", "PRIV1");
        let id = db
            .with_conn_mut(|c| import_key_for_merge(c, &proposed))
            .unwrap();
        assert_eq!(id, "existing");
        // Stored row count unchanged.
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
    }

    #[test]
    fn import_for_merge_inserts_when_no_match() {
        let db = db();
        let proposed = key("imported-id", "lab", "PUB-NEW", "PRIV-NEW");
        let id = db
            .with_conn_mut(|c| import_key_for_merge(c, &proposed))
            .unwrap();
        assert_eq!(id, "imported-id");
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].public_key, "PUB-NEW");
    }

    #[test]
    fn import_for_merge_uniqueifies_label_against_taken_set() {
        let db = db();
        db.with_conn(|c| upsert(c, &key("e1", "Web", "PUB1", "PRIV1")))
            .unwrap();
        let proposed = key("imported", "Web", "PUB-DIFF", "PRIV-DIFF");
        let id = db
            .with_conn_mut(|c| import_key_for_merge(c, &proposed))
            .unwrap();
        let rows = db.with_conn(list_all).unwrap();
        let inserted = rows.iter().find(|r| r.id == id).unwrap();
        assert_eq!(inserted.label, "Web (copy)");
    }

    #[test]
    fn import_for_merge_mints_new_id_on_id_collision() {
        let db = db();
        db.with_conn(|c| upsert(c, &key("collision", "Web", "PUB1", "PRIV1")))
            .unwrap();
        let proposed = key("collision", "Other", "PUB-NEW", "PRIV-NEW");
        let id = db
            .with_conn_mut(|c| import_key_for_merge(c, &proposed))
            .unwrap();
        assert_ne!(id, "collision");
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 2);
    }

    #[test]
    fn import_for_merge_falls_back_to_private_when_public_empty() {
        let db = db();
        db.with_conn(|c| upsert(c, &key("e1", "lab", "", "PRIV-MATCH")))
            .unwrap();
        let proposed = key("imported", "lab2", "", "PRIV-MATCH");
        let id = db
            .with_conn_mut(|c| import_key_for_merge(c, &proposed))
            .unwrap();
        assert_eq!(id, "e1");
    }
}

#[cfg(test)]
mod tombstone_tests {
    use super::*;
    use crate::db::{bootstrap_schema, Db};

    fn db() -> Db {
        let conn = Connection::open_in_memory().unwrap();
        conn.raw()
            .execute_batch("PRAGMA foreign_keys = ON")
            .unwrap();
        bootstrap_schema(&conn).unwrap();
        Db::from_raw_for_tests(conn)
    }

    fn seed(db: &Db, id: &str) {
        db.with_conn(|c| {
            upsert(
                c,
                &SshKeyRow {
                    id: id.into(),
                    label: id.into(),
                    private_key: "PRIV".into(),
                    public_key: "PUB".into(),
                    key_type: "ed25519".into(),
                    is_generated: false,
                    created_at_ms: 0,
                    credential_id: None,
                    application_string: None,
                    has_user_verification: false,
                    agent_policy: AgentPolicy::Ask,
                    backend: KeyBackend::Software,
                    pkcs11_uri: None,
                    pkcs11_module_path: None,
                    pkcs11_token_serial: None,
                    pkcs11_object_id: None,
                    pkcs11_object_label: None,
                    enclave_tag: None,
                    hello_credential_name: None,
                    tpm_blob: None,
                    tpm_handle: None,
                    tpm_provider: None,
                    tpm_pin_required: false,
                    cng_key_name: None,
                    keystore_alias: None,
                    keystore_strongbox: false,
                    keystore_user_auth_required: false,
                    keystore_platform: None,
                    imported_as_stub: false,
                },
            )
        })
        .unwrap();
    }

    fn raw_deleted_at(db: &Db, id: &str) -> Option<i64> {
        db.with_conn(|c| {
            let row: Option<i64> = c
                .raw()
                .query_row(
                    "SELECT deleted_at FROM ssh_keys WHERE id = ?1",
                    params![id],
                    |r| r.get(0),
                )
                .ok()
                .flatten();
            Ok(row)
        })
        .unwrap()
    }

    #[test]
    fn delete_writes_tombstone_instead_of_removing_row() {
        let db = db();
        seed(&db, "k1");
        let n = db.with_conn(|c| delete(c, "k1")).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "k1").is_some());
    }

    #[test]
    fn list_all_and_get_skip_tombstoned_rows() {
        let db = db();
        seed(&db, "alive");
        seed(&db, "dead");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
        assert!(db.with_conn(|c| get(c, "dead")).unwrap().is_none());
    }

    #[test]
    fn list_metadata_skips_tombstoned_rows() {
        // list_metadata also filters — dedup paths must not match
        // against tombstoned keys.
        let db = db();
        seed(&db, "alive");
        seed(&db, "dead");
        db.with_conn(|c| delete(c, "dead")).unwrap();
        let rows = db.with_conn(list_metadata).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "alive");
    }

    #[test]
    fn purge_tombstones_physically_removes_old_rows() {
        let db = db();
        seed(&db, "k1");
        db.with_conn(|c| delete(c, "k1")).unwrap();
        let n = db.with_conn(|c| purge_tombstones(c, i64::MAX)).unwrap();
        assert_eq!(n, 1);
        assert!(raw_deleted_at(&db, "k1").is_none());
    }

    #[test]
    fn replace_all_tombstones_old_rows_and_revives_collisions() {
        // replace_all's clearing step tombstones every live row;
        // the upsert loop revives any id in the new set, leaving
        // the rest visibly gone but available for sync replay.
        let db = db();
        seed(&db, "kept");
        seed(&db, "purged");
        let new_set = vec![SshKeyRow {
            id: "kept".into(),
            label: "renamed".into(),
            private_key: "PRIV2".into(),
            public_key: "PUB2".into(),
            key_type: "ed25519".into(),
            is_generated: true,
            created_at_ms: 0,
            credential_id: None,
            application_string: None,
            has_user_verification: false,
            agent_policy: AgentPolicy::Ask,
            backend: KeyBackend::Software,
            pkcs11_uri: None,
            pkcs11_module_path: None,
            pkcs11_token_serial: None,
            pkcs11_object_id: None,
            pkcs11_object_label: None,
            enclave_tag: None,
            hello_credential_name: None,
            tpm_blob: None,
            tpm_handle: None,
            tpm_provider: None,
            tpm_pin_required: false,
            cng_key_name: None,
            keystore_alias: None,
            keystore_strongbox: false,
            keystore_user_auth_required: false,
            keystore_platform: None,
            imported_as_stub: false,
        }];
        db.with_conn_mut(|c| replace_all(c, &new_set)).unwrap();
        let rows = db.with_conn(list_all).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "kept");
        assert_eq!(rows[0].label, "renamed");
        assert!(raw_deleted_at(&db, "kept").is_none());
        assert!(raw_deleted_at(&db, "purged").is_some());
    }

    #[test]
    fn upsert_revives_tombstoned_row() {
        let db = db();
        seed(&db, "k1");
        db.with_conn(|c| delete(c, "k1")).unwrap();
        seed(&db, "k1");
        assert!(db.with_conn(|c| get(c, "k1")).unwrap().is_some());
        assert!(raw_deleted_at(&db, "k1").is_none());
    }
}
