//! FRB adapter for `lfs_core::db` DAOs.
//!
//! Each DAO is exposed as `db_<table>_<verb>` async fns. The
//! adapter resolves the running `Db` handle off `AppState`,
//! marshals the row shape across the FRB boundary, and runs the
//! actual rusqlite call inside `tokio::task::spawn_blocking` so
//! the FRB worker thread isn't pinned by disk I/O.

/// Resolve the running `Db` handle off `AppState`. Sibling FRB
/// modules in `crate::api::*` route through here so the
/// "db not initialized" error message stays one place.
pub(crate) fn require_db() -> Result<std::sync::Arc<lfs_core::db::Db>, String> {
    lfs_core::app::instance()
        .db()
        .ok_or_else(|| "db not initialized".to_string())
}

/// Run a sync DAO closure inside `spawn_blocking` against the
/// running `Db` connection. Centralises the boilerplate so each
/// DAO function below is one short call site.
pub(crate) async fn run_db<F, R>(f: F) -> Result<R, String>
where
    F: FnOnce(&lfs_core::db::Connection) -> Result<R, lfs_core::error::Error> + Send + 'static,
    R: Send + 'static,
{
    tokio::task::spawn_blocking(move || {
        let db = require_db()?;
        db.with_conn(f)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("db task: {e}"))?
}

/// Same as [`run_db`] but for closures that need a `&mut Connection`
/// (transactional DAOs that scope rollback / commit via
/// `Connection::transaction`).
pub(crate) async fn run_db_mut<F, R>(f: F) -> Result<R, String>
where
    F: FnOnce(&mut lfs_core::db::Connection) -> Result<R, lfs_core::error::Error> + Send + 'static,
    R: Send + 'static,
{
    tokio::task::spawn_blocking(move || {
        let db = require_db()?;
        db.with_conn_mut(f)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("db task: {e}"))?
}

/// `run_db` + always-fire `SessionsChanged` on Ok. The compile-time
/// pairing means a write-DAO callsite can't accidentally skip the
/// reload-and-notify dance the way explicit post-call helpers
/// allowed.
pub(crate) async fn run_db_writing_sessions<F, R>(f: F) -> Result<R, String>
where
    F: FnOnce(&lfs_core::db::Connection) -> Result<R, lfs_core::error::Error> + Send + 'static,
    R: Send + 'static,
{
    let res = run_db(f).await;
    if res.is_ok() {
        lfs_core::sessions::reload_and_notify(&lfs_core::app::instance());
    }
    res
}

/// Same shape as [`run_db_writing_sessions`] but the notify only
/// fires when the wrapped value satisfies a caller-supplied
/// predicate. Used by DAO endpoints that return `0 / N rows
/// affected` — `n > 0` is the typical predicate so a no-op delete
/// (id resolves to nothing) doesn't waste a bus event.
pub(crate) async fn run_db_writing_sessions_when<F, R, W>(f: F, when: W) -> Result<R, String>
where
    F: FnOnce(&lfs_core::db::Connection) -> Result<R, lfs_core::error::Error> + Send + 'static,
    R: Send + 'static,
    W: Fn(&R) -> bool,
{
    let res = run_db(f).await;
    if let Ok(v) = &res {
        if when(v) {
            lfs_core::sessions::reload_and_notify(&lfs_core::app::instance());
        }
    }
    res
}

/// `run_db_mut` + always-fire `SessionsChanged` on Ok.
pub(crate) async fn run_db_mut_writing_sessions<F, R>(f: F) -> Result<R, String>
where
    F: FnOnce(&mut lfs_core::db::Connection) -> Result<R, lfs_core::error::Error> + Send + 'static,
    R: Send + 'static,
{
    let res = run_db_mut(f).await;
    if res.is_ok() {
        lfs_core::sessions::reload_and_notify(&lfs_core::app::instance());
    }
    res
}

/// `run_db_mut` + conditional `SessionsChanged` on Ok+predicate.
pub(crate) async fn run_db_mut_writing_sessions_when<F, R, W>(f: F, when: W) -> Result<R, String>
where
    F: FnOnce(&mut lfs_core::db::Connection) -> Result<R, lfs_core::error::Error> + Send + 'static,
    R: Send + 'static,
    W: Fn(&R) -> bool,
{
    let res = run_db_mut(f).await;
    if let Ok(v) = &res {
        if when(v) {
            lfs_core::sessions::reload_and_notify(&lfs_core::app::instance());
        }
    }
    res
}

// ---- ssh_keys ----------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbSshKey {
    pub id: String,
    pub label: String,
    pub private_key: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    pub created_at_ms: i64,
    /// FIDO2 credential id for `sk-*` keys; `None` for software keys.
    /// The opaque CTAP2 blob the device matches against on every
    /// assertion; persisted alongside the SSH wire-format public key
    /// so the connect path can resolve it without a separate FRB hop.
    pub credential_id: Option<Vec<u8>>,
    /// FIDO2 `application` field — the SSH RP-id (typically `ssh:`).
    /// `None` for software keys.
    pub application_string: Option<String>,
    /// User-verification bit captured at import. Drives the PIN prompt
    /// on connect.
    pub has_user_verification: bool,
    /// Per-key dispatch policy for the in-process ssh-agent endpoint.
    /// Wire values: `"always"` / `"ask"` / `"deny"`. Default `"ask"`
    /// matches the schema default — the endpoint routes every
    /// SIGN_REQUEST through a Flutter confirmation dialog until the
    /// user promotes the row. Stays a String over the FRB boundary
    /// so the Dart side doesn't need a generated enum mirror; the
    /// `DbAgentPolicy` helpers below map Rust enum <-> String.
    pub agent_policy: String,
    /// Backend discriminator (schema v9). Wire values:
    /// `"software"` / `"fido2"` / `"pkcs11"` / `"tpm"` / `"enclave"` /
    /// `"hello"` / `"keystore"`. Default `"software"`; the connect /
    /// agent dispatcher reads this to route to the right Signer impl.
    pub backend: String,
    /// RFC 7512 `pkcs11:` URI captured at import for PKCS#11 rows.
    /// `None` for every other backend. The connect path prefers this
    /// over the resolved module path so a re-plug under a different
    /// slot still resolves the right token + object.
    pub pkcs11_uri: Option<String>,
    /// Resolved on-disk path of the PKCS#11 module the import wizard
    /// loaded. Cached for fast re-binding; the loader still verifies
    /// the SHA-256 matches before reuse.
    pub pkcs11_module_path: Option<String>,
    /// PKCS#11 token serial captured at import — used to confirm the
    /// same physical token is inserted before signing.
    pub pkcs11_token_serial: Option<String>,
    /// `CKA_ID` of the private-key object on the token. Opaque to
    /// Dart; passed verbatim back to Rust on sign.
    pub pkcs11_object_id: Option<Vec<u8>>,
    /// `CKA_LABEL` of the private-key object — human-readable;
    /// renders alongside the key-manager row.
    pub pkcs11_object_label: Option<String>,
    /// Apple Secure Enclave application-tag bytes (schema v10).
    /// Opaque blob captured at create time; the
    /// `SecItemCopyMatching` lookup matches on it. Only populated
    /// for `backend = 'enclave'` rows on macOS / iOS.
    pub enclave_tag: Option<Vec<u8>>,
    /// Windows Hello CNG persistent-key name (schema v11). UTF-8
    /// string the `NCryptOpenKey` lookup re-binds to on every sign.
    /// Only populated for `backend = 'hello'` rows on Windows.
    pub hello_credential_name: Option<String>,
    /// TPM 2.0 wrapped-blob bytes (schema v12). TSS2 PRIVATE KEY
    /// ASN.1 envelope per TCG draft `draft-bottomley-tpm2-keys-asn1`
    /// for the Linux blob-storage path. `None` for the persistent-
    /// handle mode and every non-TPM backend.
    pub tpm_blob: Option<Vec<u8>>,
    /// Persistent NV handle (`0x81010001..0x8101FFFF`) when the key
    /// was promoted to TPM RAM; `None` for blob mode and non-TPM
    /// rows. The Dart side renders the value as `0x81010001` in
    /// the badge popover.
    pub tpm_handle: Option<u32>,
    /// `"tss-esapi"` (Linux) / `"cng-pcp"` (Windows silent variant)
    /// — discriminator the connect path uses to pick the platform
    /// module. `None` for non-TPM backends.
    pub tpm_provider: Option<String>,
    /// `true` when the key was minted with a `TPM2B_AUTH` value and
    /// requires a PIN on every sign.
    pub tpm_pin_required: bool,
    /// Windows PCP-silent TPM CNG persistent-key name. Uses the
    /// `letsflutssh-tpm-` prefix (distinct from the Hello-gated
    /// `letsflutssh-ssh-` prefix). `None` for non-Windows TPM rows
    /// and every non-TPM backend.
    pub cng_key_name: Option<String>,
    /// Android Hardware Keystore alias (schema v13). UTF-8 string
    /// the `KeyStore.getEntry(alias, null)` lookup re-binds to on
    /// every sign. Only populated for `backend = 'keystore'` rows
    /// on Android. `None` everywhere else.
    pub keystore_alias: Option<String>,
    /// `true` when the row landed in StrongBox HSM (rather than
    /// TEE) at create time. `false` for TEE-only rows and every
    /// non-Keystore backend. Drives the badge label split
    /// ("StrongBox HSM" vs "TEE").
    pub keystore_strongbox: bool,
    /// `true` when the row requires biometric / device-unlock auth
    /// on every sign — always `true` for the current Keystore
    /// wizard. Reserved as a column so a future no-auth variant
    /// lands without a schema bump.
    pub keystore_user_auth_required: bool,
    /// `Build.MODEL` + Android version captured at create time,
    /// e.g. `"Pixel 8 (Android 14)"`. Surfaced read-only in the
    /// badge popover so multi-device users can identify which
    /// phone holds the key. `None` for non-Keystore rows.
    pub keystore_platform: Option<String>,
    /// `true` when the row landed via `.lfs` archive import / WebDAV
    /// sync pull as a public-half-only stub for a device-bound
    /// backend (Apple Secure Enclave / Windows Hello / TPM / Android
    /// Keystore). The key manager renders such rows desaturated; the
    /// session-edit "Key from manager" picker disables them. See
    /// the lfs_core docstring for the full contract.
    pub imported_as_stub: bool,
}

impl From<lfs_core::db::ssh_keys::SshKeyRow> for DbSshKey {
    fn from(r: lfs_core::db::ssh_keys::SshKeyRow) -> Self {
        Self {
            id: r.id,
            label: r.label,
            private_key: r.private_key,
            public_key: r.public_key,
            key_type: r.key_type,
            is_generated: r.is_generated,
            created_at_ms: r.created_at_ms,
            credential_id: r.credential_id,
            application_string: r.application_string,
            has_user_verification: r.has_user_verification,
            agent_policy: r.agent_policy.as_db_str().to_string(),
            backend: r.backend.as_db_str().to_string(),
            pkcs11_uri: r.pkcs11_uri,
            pkcs11_module_path: r.pkcs11_module_path,
            pkcs11_token_serial: r.pkcs11_token_serial,
            pkcs11_object_id: r.pkcs11_object_id,
            pkcs11_object_label: r.pkcs11_object_label,
            enclave_tag: r.enclave_tag,
            hello_credential_name: r.hello_credential_name,
            tpm_blob: r.tpm_blob,
            tpm_handle: r.tpm_handle,
            tpm_provider: r.tpm_provider,
            tpm_pin_required: r.tpm_pin_required,
            cng_key_name: r.cng_key_name,
            keystore_alias: r.keystore_alias,
            keystore_strongbox: r.keystore_strongbox,
            keystore_user_auth_required: r.keystore_user_auth_required,
            keystore_platform: r.keystore_platform,
            imported_as_stub: r.imported_as_stub,
        }
    }
}

impl From<DbSshKey> for lfs_core::db::ssh_keys::SshKeyRow {
    fn from(r: DbSshKey) -> Self {
        Self {
            id: r.id,
            label: r.label,
            private_key: r.private_key,
            public_key: r.public_key,
            key_type: r.key_type,
            is_generated: r.is_generated,
            created_at_ms: r.created_at_ms,
            credential_id: r.credential_id,
            application_string: r.application_string,
            has_user_verification: r.has_user_verification,
            agent_policy: lfs_core::db::ssh_keys::AgentPolicy::from_db(&r.agent_policy),
            backend: lfs_core::db::ssh_keys::KeyBackend::from_db(&r.backend),
            pkcs11_uri: r.pkcs11_uri,
            pkcs11_module_path: r.pkcs11_module_path,
            pkcs11_token_serial: r.pkcs11_token_serial,
            pkcs11_object_id: r.pkcs11_object_id,
            pkcs11_object_label: r.pkcs11_object_label,
            enclave_tag: r.enclave_tag,
            hello_credential_name: r.hello_credential_name,
            tpm_blob: r.tpm_blob,
            tpm_handle: r.tpm_handle,
            tpm_provider: r.tpm_provider,
            tpm_pin_required: r.tpm_pin_required,
            cng_key_name: r.cng_key_name,
            keystore_alias: r.keystore_alias,
            keystore_strongbox: r.keystore_strongbox,
            keystore_user_auth_required: r.keystore_user_auth_required,
            keystore_platform: r.keystore_platform,
            imported_as_stub: r.imported_as_stub,
        }
    }
}

pub async fn db_ssh_keys_list_all() -> Result<Vec<DbSshKey>, String> {
    run_db(lfs_core::db::ssh_keys::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbSshKey::from).collect())
}

pub async fn db_ssh_keys_get(id: String) -> Result<Option<DbSshKey>, String> {
    run_db(move |c| lfs_core::db::ssh_keys::get(c, &id))
        .await
        .map(|opt| opt.map(DbSshKey::from))
}

pub async fn db_ssh_keys_upsert(row: DbSshKey) -> Result<(), String> {
    let row: lfs_core::db::ssh_keys::SshKeyRow = row.into();
    run_db(move |c| lfs_core::db::ssh_keys::upsert(c, &row)).await
}

/// Atomic full-table replace. **Don't fan out to N delete +
/// N upsert FRB hops** — that pays 2N round-trips for the same
/// outcome and opens a half-cleared-table race when a transient
/// FRB failure lands mid-loop. This single call lands the whole
/// replacement inside one rusqlite transaction.
pub async fn db_ssh_keys_replace_all(rows: Vec<DbSshKey>) -> Result<(), String> {
    let rows: Vec<lfs_core::db::ssh_keys::SshKeyRow> = rows.into_iter().map(Into::into).collect();
    run_db_mut(move |c| lfs_core::db::ssh_keys::replace_all(c, &rows)).await
}

pub async fn db_ssh_keys_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::ssh_keys::delete(c, &id))
        .await
        .map(|n| n as u32)
}

/// Composite import — Rust composes the dedup-by-fingerprint
/// lookup (public-key first, falling back to private-key) +
/// label-uniqueness + insert in one transaction. Returns the id
/// the caller should use downstream — existing on a content
/// match, freshly inserted otherwise. One FRB call so the whole
/// sequence lands as a single sqlite transaction.
pub async fn db_ssh_keys_import_for_merge(proposed: DbSshKey) -> Result<String, String> {
    let row: lfs_core::db::ssh_keys::SshKeyRow = proposed.into();
    run_db_mut(move |c| lfs_core::db::ssh_keys::import_key_for_merge(c, &row)).await
}

/// Stage the stored key's private PEM bytes into the SecretStore
/// under `key.priv.<id>`. Returns `true` when bytes landed in the
/// store, `false` when the row is missing or the column is empty.
/// Plaintext does not cross the FRB boundary — Dart only sees the
/// boolean.
pub async fn db_ssh_keys_stage_secret(key_id: String) -> Result<bool, String> {
    run_db(move |c| lfs_core::db::ssh_keys::stage_secret_into_store(c, &key_id)).await
}

/// Listing-only view of `ssh_keys` for UIs that don't need the PEM
/// bytes — key manager listing, import dedup, export-selection
/// pickers. The SHA-256 fingerprints are computed inside Rust so
/// callers can compare against scanned keys without pulling
/// plaintext through the FRB boundary.
#[derive(Debug, Clone)]
pub struct DbSshKeyMetadata {
    pub id: String,
    pub label: String,
    pub public_key: String,
    pub key_type: String,
    pub is_generated: bool,
    pub created_at_ms: i64,
    pub private_fingerprint: String,
    pub public_fingerprint: String,
    /// Backend discriminator (schema v9). One of `software` / `fido2` /
    /// `pkcs11` / `tpm` / `enclave` / `hello` / `keystore`. The Dart
    /// key-manager UI picks the per-backend badge variant off this
    /// string.
    pub backend: String,
    /// PKCS#11 module path captured at import. `None` for non-PKCS#11
    /// rows.
    pub pkcs11_module_path: Option<String>,
    /// PKCS#11 token serial captured at import.
    pub pkcs11_token_serial: Option<String>,
    /// PKCS#11 object label (`CKA_LABEL`).
    pub pkcs11_object_label: Option<String>,
    /// Windows Hello CNG persistent-key name captured at import.
    /// `None` for non-`hello` rows.
    pub hello_credential_name: Option<String>,
    /// TPM 2.0 storage mode discriminator + ingredients (schema v12).
    /// `tpm_handle` is `Some(...)` for the persistent-NV-handle mode
    /// (key sits in TPM RAM) and `None` for the on-disk wrapped-blob
    /// mode; the wizard / badge popover renders the value as
    /// `0x81010001` style hex. `tpm_provider` distinguishes the
    /// Linux ESAPI driver from the Windows PCP silent variant.
    /// `tpm_pin_required` flips the badge popover into "type a PIN
    /// per sign" copy. `cng_key_name` is the Windows-side
    /// `NCryptOpenKey` name. None of these columns leak the private
    /// key material — that lives on-chip.
    pub tpm_handle: Option<u32>,
    pub tpm_provider: Option<String>,
    pub tpm_pin_required: bool,
    pub cng_key_name: Option<String>,
    /// Android Hardware Keystore ingredients (schema v13). Surfaced
    /// for the `KeystoreBadge` info popover; the private key material
    /// itself lives in the AndroidKeyStore TEE / StrongBox and never
    /// reaches Dart. `keystore_alias` re-binds the key on every sign;
    /// `keystore_strongbox` splits the badge label (`StrongBox HSM` vs
    /// `TEE`); `keystore_user_auth_required` is `true` for every
    /// current Keystore row; `keystore_platform` carries the
    /// capture-time `Build.MODEL` + Android version so users on
    /// multi-device deployments can identify which phone holds the
    /// key.
    pub keystore_alias: Option<String>,
    pub keystore_strongbox: bool,
    pub keystore_user_auth_required: bool,
    pub keystore_platform: Option<String>,
    /// `true` when the row is a public-half-only stub from a
    /// device-bound backend that travelled through `.lfs` import or
    /// WebDAV sync. The key manager renders the row desaturated +
    /// surfaces "Re-generate here" / "Remove" actions; the
    /// session-edit picker disables stub rows. `false` for every
    /// locally generated row.
    pub imported_as_stub: bool,
}

impl From<lfs_core::db::ssh_keys::SshKeyMetadata> for DbSshKeyMetadata {
    fn from(m: lfs_core::db::ssh_keys::SshKeyMetadata) -> Self {
        DbSshKeyMetadata {
            id: m.id,
            label: m.label,
            public_key: m.public_key,
            key_type: m.key_type,
            is_generated: m.is_generated,
            created_at_ms: m.created_at_ms,
            private_fingerprint: m.private_fingerprint,
            public_fingerprint: m.public_fingerprint,
            backend: m.backend,
            pkcs11_module_path: m.pkcs11_module_path,
            pkcs11_token_serial: m.pkcs11_token_serial,
            pkcs11_object_label: m.pkcs11_object_label,
            hello_credential_name: m.hello_credential_name,
            tpm_handle: m.tpm_handle,
            tpm_provider: m.tpm_provider,
            tpm_pin_required: m.tpm_pin_required,
            cng_key_name: m.cng_key_name,
            keystore_alias: m.keystore_alias,
            keystore_strongbox: m.keystore_strongbox,
            keystore_user_auth_required: m.keystore_user_auth_required,
            keystore_platform: m.keystore_platform,
            imported_as_stub: m.imported_as_stub,
        }
    }
}

pub async fn db_ssh_keys_list_metadata() -> Result<Vec<DbSshKeyMetadata>, String> {
    run_db(lfs_core::db::ssh_keys::list_metadata)
        .await
        .map(|rows| rows.into_iter().map(DbSshKeyMetadata::from).collect())
}

// ---- ssh_key_certificates ---------------------------------------------

/// FRB mirror of [`lfs_core::db::ssh_key_certificates::CertRecord`].
/// One certificate per stored SSH key — the Dart key-manager UI
/// surfaces the principals / validity / critical-options summary on
/// the matching row.
#[derive(Debug, Clone)]
pub struct DbSshKeyCertificate {
    pub key_id: String,
    pub certificate: Vec<u8>,
    pub valid_after: i64,
    pub valid_before: i64,
    pub principals: String,
    pub critical_options: String,
    pub fingerprint: String,
}

impl From<lfs_core::db::ssh_key_certificates::CertRecord> for DbSshKeyCertificate {
    fn from(r: lfs_core::db::ssh_key_certificates::CertRecord) -> Self {
        Self {
            key_id: r.key_id,
            certificate: r.certificate,
            valid_after: r.valid_after,
            valid_before: r.valid_before,
            principals: r.principals,
            critical_options: r.critical_options,
            fingerprint: r.fingerprint,
        }
    }
}

impl From<DbSshKeyCertificate> for lfs_core::db::ssh_key_certificates::CertRecord {
    fn from(r: DbSshKeyCertificate) -> Self {
        Self {
            key_id: r.key_id,
            certificate: r.certificate,
            valid_after: r.valid_after,
            valid_before: r.valid_before,
            principals: r.principals,
            critical_options: r.critical_options,
            fingerprint: r.fingerprint,
        }
    }
}

/// Fetch the certificate paired with `key_id`, or `None` when the
/// key has no cert attached. Plain read — no SecretStore staging
/// hop; that lives on the connect path
/// ([`db_ssh_key_certificate_stage_secret`]).
pub async fn db_ssh_key_certificate_get(
    key_id: String,
) -> Result<Option<DbSshKeyCertificate>, String> {
    run_db(move |c| lfs_core::db::ssh_key_certificates::get(c, &key_id))
        .await
        .map(|opt| opt.map(DbSshKeyCertificate::from))
}

/// Insert or replace the certificate paired with `rec.key_id`. The
/// caller must have validated the fingerprint pairing
/// (`keys_parse_openssh_cert` + match against the key's public-half
/// fingerprint) before calling — the DAO does not re-check.
pub async fn db_ssh_key_certificate_upsert(rec: DbSshKeyCertificate) -> Result<(), String> {
    let rec: lfs_core::db::ssh_key_certificates::CertRecord = rec.into();
    run_db(move |c| lfs_core::db::ssh_key_certificates::upsert(c, &rec)).await
}

/// Remove the certificate paired with `key_id`. Returns the number
/// of rows affected — `0` is a successful no-op when no cert was
/// attached.
pub async fn db_ssh_key_certificate_delete(key_id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::ssh_key_certificates::delete(c, &key_id))
        .await
        .map(|n| n as u32)
}

/// Every certificate row, ordered by `key_id`. Used by archive
/// export and a future "all certs" diagnostic. Most callers want
/// [`db_ssh_key_certificate_get`] instead.
pub async fn db_ssh_key_certificates_list_all() -> Result<Vec<DbSshKeyCertificate>, String> {
    run_db(lfs_core::db::ssh_key_certificates::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbSshKeyCertificate::from).collect())
}

/// Stage the stored cert blob into the SecretStore under
/// `key.cert.<id>`. Returns `true` when bytes landed, `false` when
/// the key has no cert attached. The cert is public material, but
/// routing it through SecretStore keeps the connect cascade
/// symmetric with `db_ssh_keys_stage_secret` and avoids round-
/// tripping the bytes through the Dart heap.
pub async fn db_ssh_key_certificate_stage_secret(key_id: String) -> Result<bool, String> {
    run_db(move |c| lfs_core::db::ssh_key_certificates::stage_secret_into_store(c, &key_id)).await
}

// ---- folders -----------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbFolder {
    pub id: String,
    pub name: String,
    pub parent_id: Option<String>,
    pub sort_order: i64,
    pub collapsed: bool,
    pub created_at_ms: i64,
}

impl From<lfs_core::db::folders::FolderRow> for DbFolder {
    fn from(r: lfs_core::db::folders::FolderRow) -> Self {
        Self {
            id: r.id,
            name: r.name,
            parent_id: r.parent_id,
            sort_order: r.sort_order,
            collapsed: r.collapsed,
            created_at_ms: r.created_at_ms,
        }
    }
}

impl From<DbFolder> for lfs_core::db::folders::FolderRow {
    fn from(r: DbFolder) -> Self {
        Self {
            id: r.id,
            name: r.name,
            parent_id: r.parent_id,
            sort_order: r.sort_order,
            collapsed: r.collapsed,
            created_at_ms: r.created_at_ms,
        }
    }
}

pub async fn db_folders_list_all() -> Result<Vec<DbFolder>, String> {
    run_db(lfs_core::db::folders::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbFolder::from).collect())
}

pub async fn db_folders_upsert(row: DbFolder) -> Result<(), String> {
    let row: lfs_core::db::folders::FolderRow = row.into();
    run_db_writing_sessions(move |c| lfs_core::db::folders::upsert(c, &row)).await
}

/// Resolve a `/`-separated `path` to a folder id, creating any
/// missing intermediate folders inside one transaction. Empty
/// `path` returns `Ok(None)` (root-level). Always emits
/// `SessionsChanged` on success so the Dart subscriber rehydrates
/// the folder map; redundant fires on no-op (path already exists)
/// are cheap and keep the call site symmetric with
/// `db_folders_upsert`.
///
/// `now_ms` is supplied by the caller so the FRB layer doesn't
/// pull `SystemTime` directly — same pattern as the other
/// `db_folders_*` / `db_sessions_*` write shims.
pub async fn db_folders_resolve_or_create_path(
    path: String,
    now_ms: i64,
) -> Result<Option<String>, String> {
    run_db_mut_writing_sessions(move |c| {
        lfs_core::db::folders::resolve_or_create_path(c, &path, now_ms)
    })
    .await
}

pub async fn db_folders_delete(id: String) -> Result<u32, String> {
    run_db_writing_sessions_when(move |c| lfs_core::db::folders::delete(c, &id), |n| *n > 0)
        .await
        .map(|n| n as u32)
}

pub async fn db_folders_delete_all() -> Result<u32, String> {
    run_db_writing_sessions_when(lfs_core::db::folders::delete_all, |n| *n > 0)
        .await
        .map(|n| n as u32)
}

pub async fn db_folders_toggle_collapsed(id: String) -> Result<u32, String> {
    run_db_writing_sessions_when(
        move |c| lfs_core::db::folders::toggle_collapsed(c, &id),
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

pub async fn db_folders_update_name_parent(
    id: String,
    name: String,
    parent_id: Option<String>,
) -> Result<u32, String> {
    run_db_writing_sessions_when(
        move |c| lfs_core::db::folders::update_name_parent(c, &id, &name, parent_id.as_deref()),
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

/// Composite folder rename / move — Rust resolves the existing
/// folder by `old_path`, computes the new leaf name + new parent
/// path, ensures the new parent exists, then updates the row in
/// one transaction. The single-FRB-call shape keeps the rename +
/// re-parent atomic — the row's `parent_id` is read freshly inside
/// the transaction, so a cross-tree move never racing a stale
/// row-cache value.
///
/// Returns 1 on success, 0 when `old_path` resolves to nothing.
/// `Err` for cycle moves (folder under its own descendant).
pub async fn db_folders_rename_path_cascade(
    old_path: String,
    new_path: String,
    now_ms: i64,
) -> Result<u32, String> {
    run_db_mut_writing_sessions_when(
        move |c| lfs_core::db::folders::rename_path_cascade(c, &old_path, &new_path, now_ms),
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

pub async fn db_folders_delete_recursive(id: String) -> Result<u32, String> {
    run_db_writing_sessions_when(
        move |c| lfs_core::db::folders::delete_recursive(c, &id),
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

// ---- sessions ----------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbSession {
    pub id: String,
    pub label: String,
    pub folder_id: Option<String>,
    /// Transport tag — one of `"ssh"` / `"webdav"` / `"s3"`.
    /// Empty string upserts the SSH wire value (the DAO normalises
    /// before the SQL hop). Read side never returns empty because
    /// the column is `NOT NULL DEFAULT 'ssh'`.
    pub kind: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_path: String,
    pub key_data: String,
    pub key_id: Option<String>,
    pub passphrase: String,
    pub sort_order: i64,
    pub notes: String,
    pub last_connected_at_ms: Option<i64>,
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

impl From<lfs_core::db::sessions::SessionRow> for DbSession {
    fn from(r: lfs_core::db::sessions::SessionRow) -> Self {
        Self {
            id: r.id,
            label: r.label,
            folder_id: r.folder_id,
            kind: r.kind,
            host: r.host,
            port: r.port,
            user: r.user,
            auth_type: r.auth_type,
            password: r.password,
            key_path: r.key_path,
            key_data: r.key_data,
            key_id: r.key_id,
            passphrase: r.passphrase,
            sort_order: r.sort_order,
            notes: r.notes,
            last_connected_at_ms: r.last_connected_at_ms,
            extras: r.extras,
            via_session_id: r.via_session_id,
            via_host: r.via_host,
            via_port: r.via_port,
            via_user: r.via_user,
            created_at_ms: r.created_at_ms,
            updated_at_ms: r.updated_at_ms,
        }
    }
}

impl From<DbSession> for lfs_core::db::sessions::SessionRow {
    fn from(r: DbSession) -> Self {
        Self {
            id: r.id,
            label: r.label,
            folder_id: r.folder_id,
            kind: r.kind,
            host: r.host,
            port: r.port,
            user: r.user,
            auth_type: r.auth_type,
            password: r.password,
            key_path: r.key_path,
            key_data: r.key_data,
            key_id: r.key_id,
            passphrase: r.passphrase,
            sort_order: r.sort_order,
            notes: r.notes,
            last_connected_at_ms: r.last_connected_at_ms,
            extras: r.extras,
            via_session_id: r.via_session_id,
            via_host: r.via_host,
            via_port: r.via_port,
            via_user: r.via_user,
            created_at_ms: r.created_at_ms,
            updated_at_ms: r.updated_at_ms,
        }
    }
}

pub async fn db_sessions_list_all() -> Result<Vec<DbSession>, String> {
    run_db(lfs_core::db::sessions::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbSession::from).collect())
}

pub async fn db_sessions_get(id: String) -> Result<Option<DbSession>, String> {
    run_db(move |c| lfs_core::db::sessions::get(c, &id))
        .await
        .map(|opt| opt.map(DbSession::from))
}

pub async fn db_sessions_upsert(row: DbSession) -> Result<(), String> {
    let row: lfs_core::db::sessions::SessionRow = row.into();
    run_db_writing_sessions(move |c| lfs_core::db::sessions::upsert(c, &row)).await
}

pub async fn db_sessions_delete(id: String) -> Result<u32, String> {
    run_db_writing_sessions_when(move |c| lfs_core::db::sessions::delete(c, &id), |n| *n > 0)
        .await
        .map(|n| n as u32)
}

/// Mirror of [`lfs_core::db::sessions::StagedSecrets`] crossing FRB.
#[derive(Debug, Clone)]
pub struct DbStagedSecrets {
    pub auth_type: String,
    pub has_password: bool,
    pub has_key_data: bool,
    pub has_passphrase: bool,
}

impl From<lfs_core::db::sessions::StagedSecrets> for DbStagedSecrets {
    fn from(r: lfs_core::db::sessions::StagedSecrets) -> Self {
        Self {
            auth_type: r.auth_type,
            has_password: r.has_password,
            has_key_data: r.has_key_data,
            has_passphrase: r.has_passphrase,
        }
    }
}

/// Read the credential columns for [`session_id`] and push every
/// non-empty value straight into the process-singleton SecretStore
/// under the canonical `sess.<slot>.<id>` ids — bytes never cross
/// back to Dart. Returns metadata describing which slots were staged
/// so the caller can dispatch to the matching connect variant. Null
/// when the row no longer exists.
pub async fn db_sessions_stage_secrets(
    session_id: String,
) -> Result<Option<DbStagedSecrets>, String> {
    run_db(move |c| lfs_core::db::sessions::stage_secrets_into_store(c, &session_id))
        .await
        .map(|opt| opt.map(DbStagedSecrets::from))
}

/// Mirror of [`lfs_core::db::sessions::SessionMetadata`] crossing
/// FRB. Carries every column except the credential triplet so the
/// edit dialog can save metadata without reading old secret bytes
/// back onto the Dart heap.
#[derive(Debug, Clone)]
pub struct DbSessionMetadata {
    pub id: String,
    pub label: String,
    pub folder_id: Option<String>,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub key_path: String,
    pub key_id: Option<String>,
    pub sort_order: i64,
    pub notes: String,
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub updated_at_ms: i64,
}

impl From<DbSessionMetadata> for lfs_core::db::sessions::SessionMetadata {
    fn from(m: DbSessionMetadata) -> Self {
        Self {
            id: m.id,
            label: m.label,
            folder_id: m.folder_id,
            host: m.host,
            port: m.port,
            user: m.user,
            auth_type: m.auth_type,
            key_path: m.key_path,
            key_id: m.key_id,
            sort_order: m.sort_order,
            notes: m.notes,
            extras: m.extras,
            via_session_id: m.via_session_id,
            via_host: m.via_host,
            via_port: m.via_port,
            via_user: m.via_user,
            updated_at_ms: m.updated_at_ms,
        }
    }
}

/// Update non-credential metadata on a session row without touching
/// the `password` / `key_data` / `passphrase` columns. Lets the
/// edit dialog save a label / host / proxy change without first
/// reading the existing secret bytes back onto the Dart heap.
pub async fn db_sessions_update_metadata(metadata: DbSessionMetadata) -> Result<u32, String> {
    let m: lfs_core::db::sessions::SessionMetadata = metadata.into();
    run_db_writing_sessions_when(
        move |c| lfs_core::db::sessions::update_metadata(c, &m),
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

/// Replace one credential column (`"password"` / `"key_data"` /
/// `"passphrase"`) on a session. Crosses FRB plaintext one direction
/// only (Dart → Rust → DB); pairs with `db_sessions_stage_secrets`
/// for the read direction. Empty `value` clears the slot.
pub async fn db_sessions_set_secret(
    id: String,
    slot: String,
    value: String,
    updated_at_ms: i64,
) -> Result<u32, String> {
    run_db_writing_sessions_when(
        move |c| lfs_core::db::sessions::set_secret_column(c, &id, &slot, &value, updated_at_ms),
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

/// Copy a saved session row to a new id + label, optionally
/// re-parented under [`target_folder_id`]. Credentials flow column-
/// to-column inside SQLite and never cross the FRB boundary, so the
/// duplicate path no longer carries plaintext on the Dart heap.
pub async fn db_sessions_duplicate(
    src_id: String,
    new_id: String,
    new_label: String,
    target_folder_id: Option<String>,
    now_ms: i64,
) -> Result<(), String> {
    run_db_writing_sessions(move |c| {
        lfs_core::db::sessions::duplicate_session(
            c,
            &src_id,
            &new_id,
            &new_label,
            target_folder_id.as_deref(),
            now_ms,
        )
    })
    .await
}

/// FRB mirror of `lfs_core::db::sessions::RestoreSessionInput`.
/// Same field set as `DbSession` but carries `folder_path`
/// instead of `folder_id` — the snapshot caller (undo history)
/// only knows the path, and the post-restore folder tree is
/// re-minted inside the same transaction so any prior id is
/// stale anyway.
#[derive(Debug, Clone)]
pub struct DbRestoreSessionInput {
    pub id: String,
    pub label: String,
    pub folder_path: String,
    /// Transport tag — empty string round-trips as the SSH default
    /// on the DAO side. See [`DbSession::kind`].
    pub kind: String,
    pub host: String,
    pub port: i64,
    pub user: String,
    pub auth_type: String,
    pub password: String,
    pub key_path: String,
    pub key_data: String,
    pub key_id: Option<String>,
    pub passphrase: String,
    pub sort_order: i64,
    pub notes: String,
    pub last_connected_at_ms: Option<i64>,
    pub extras: String,
    pub via_session_id: Option<String>,
    pub via_host: Option<String>,
    pub via_port: Option<i64>,
    pub via_user: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

impl From<DbRestoreSessionInput> for lfs_core::db::sessions::RestoreSessionInput {
    fn from(d: DbRestoreSessionInput) -> Self {
        Self {
            id: d.id,
            label: d.label,
            folder_path: d.folder_path,
            kind: d.kind,
            host: d.host,
            port: d.port,
            user: d.user,
            auth_type: d.auth_type,
            password: d.password,
            key_path: d.key_path,
            key_data: d.key_data,
            key_id: d.key_id,
            passphrase: d.passphrase,
            sort_order: d.sort_order,
            notes: d.notes,
            last_connected_at_ms: d.last_connected_at_ms,
            extras: d.extras,
            via_session_id: d.via_session_id,
            via_host: d.via_host,
            via_port: d.via_port,
            via_user: d.via_user,
            created_at_ms: d.created_at_ms,
            updated_at_ms: d.updated_at_ms,
        }
    }
}

/// Atomic restore from an undo-history snapshot. One transaction
/// covers: wipe live sessions + folders, rebuild the folder tree
/// from session paths + the bare empty-folder list, re-insert every
/// session under the freshly-resolved folder id. Single-FRB-call
/// shape keeps the rebuild + re-insert atomic so a partial restore
/// can't leave the DB in an inconsistent shape.
pub async fn db_sessions_restore_snapshot(
    sessions: Vec<DbRestoreSessionInput>,
    empty_folder_paths: Vec<String>,
    now_ms: i64,
) -> Result<(), String> {
    let typed: Vec<lfs_core::db::sessions::RestoreSessionInput> =
        sessions.into_iter().map(Into::into).collect();
    run_db_mut_writing_sessions(move |c| {
        lfs_core::db::sessions::restore_snapshot(c, typed, empty_folder_paths, now_ms)
    })
    .await
}

/// Composite duplicate — Rust composes label-uniqueness +
/// folder-path resolution + duplicate-insert in one transaction.
/// Returns the new session id. Single FRB call so a caller that
/// only knows the source id + a target folder path keeps the
/// whole rename + reparent + insert atomic against concurrent
/// label collisions.
pub async fn db_sessions_duplicate_with_path(
    src_id: String,
    target_folder_path: String,
    now_ms: i64,
) -> Result<String, String> {
    run_db_mut_writing_sessions(move |c| {
        lfs_core::db::sessions::duplicate_with_path(c, &src_id, &target_folder_path, now_ms)
    })
    .await
}

pub async fn db_sessions_delete_multiple(ids: Vec<String>) -> Result<u32, String> {
    run_db_writing_sessions_when(
        move |c| lfs_core::db::sessions::delete_multiple(c, &ids),
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

pub async fn db_sessions_delete_all() -> Result<u32, String> {
    run_db_writing_sessions_when(lfs_core::db::sessions::delete_all, |n| *n > 0)
        .await
        .map(|n| n as u32)
}

pub async fn db_sessions_move_to_folder(
    session_id: String,
    folder_id: Option<String>,
    updated_at_ms: i64,
) -> Result<u32, String> {
    run_db_writing_sessions_when(
        move |c| {
            lfs_core::db::sessions::move_to_folder(
                c,
                &session_id,
                folder_id.as_deref(),
                updated_at_ms,
            )
        },
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

pub async fn db_sessions_move_multiple(
    ids: Vec<String>,
    folder_id: Option<String>,
    updated_at_ms: i64,
) -> Result<u32, String> {
    run_db_writing_sessions_when(
        move |c| {
            lfs_core::db::sessions::move_multiple(c, &ids, folder_id.as_deref(), updated_at_ms)
        },
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

// ---- known_hosts -------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbKnownHost {
    pub id: i64,
    pub host: String,
    pub port: i64,
    pub key_type: String,
    pub key_base64: String,
    pub added_at_ms: i64,
}

impl From<lfs_core::db::known_hosts::KnownHostRow> for DbKnownHost {
    fn from(r: lfs_core::db::known_hosts::KnownHostRow) -> Self {
        Self {
            id: r.id,
            host: r.host,
            port: r.port,
            key_type: r.key_type,
            key_base64: r.key_base64,
            added_at_ms: r.added_at_ms,
        }
    }
}

pub async fn db_known_hosts_list_all() -> Result<Vec<DbKnownHost>, String> {
    run_db(lfs_core::db::known_hosts::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbKnownHost::from).collect())
}

pub async fn db_known_hosts_get_by_host_port(
    host: String,
    port: i64,
) -> Result<Option<DbKnownHost>, String> {
    run_db(move |c| lfs_core::db::known_hosts::get_by_host_port(c, &host, port))
        .await
        .map(|opt| opt.map(DbKnownHost::from))
}

pub async fn db_known_hosts_upsert_by_host_port(
    host: String,
    port: i64,
    key_type: String,
    key_base64: String,
    added_at_ms: i64,
) -> Result<i64, String> {
    let row_id = run_db(move |c| {
        lfs_core::db::known_hosts::upsert_by_host_port(
            c,
            &host,
            port,
            &key_type,
            &key_base64,
            added_at_ms,
        )
    })
    .await?;
    lfs_core::known_hosts::notify_changed(&lfs_core::app::instance());
    Ok(row_id)
}

pub async fn db_known_hosts_delete_by_host_port(host: String, port: i64) -> Result<u32, String> {
    let n = run_db(move |c| lfs_core::db::known_hosts::delete_by_host_port(c, &host, port))
        .await
        .map(|n| n as u32)?;
    if n > 0 {
        lfs_core::known_hosts::notify_changed(&lfs_core::app::instance());
    }
    Ok(n)
}

pub async fn db_known_hosts_clear_all() -> Result<u32, String> {
    let n = run_db(lfs_core::db::known_hosts::clear_all)
        .await
        .map(|n| n as u32)?;
    if n > 0 {
        lfs_core::known_hosts::notify_changed(&lfs_core::app::instance());
    }
    Ok(n)
}

/// FRB mirror of `lfs_core::known_hosts::ImportSummary`.
#[derive(Debug, Clone)]
pub struct DbKnownHostsImportSummary {
    pub added: i64,
    pub skipped_existing: i64,
    pub skipped_hashed: i64,
}

impl From<lfs_core::known_hosts::ImportSummary> for DbKnownHostsImportSummary {
    fn from(s: lfs_core::known_hosts::ImportSummary) -> Self {
        Self {
            added: s.added,
            skipped_existing: s.skipped_existing,
            skipped_hashed: s.skipped_hashed,
        }
    }
}

/// Bulk-import `content` (LetsFLUTssh + OpenSSH known_hosts wire
/// formats — see `lfs_core::known_hosts_parser::parse_line`)
/// against the running DB. Existing host:port entries are
/// preserved; only fresh rows insert. Emits a single
/// `KnownHostsChanged` bus event when at least one row landed.
pub async fn db_known_hosts_import_from_string(
    content: String,
    now_ms: i64,
) -> Result<DbKnownHostsImportSummary, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        let db = app.db().ok_or_else(|| "db not initialized".to_string())?;
        lfs_core::known_hosts::import_from_string(&db, &app.bus, &content, now_ms)
            .map(DbKnownHostsImportSummary::from)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("known-hosts import task: {e}"))?
}

/// Read `path` from disk (UTF-8) and dispatch to
/// [`db_known_hosts_import_from_string`]. The Rust I/O keeps the
/// raw bytes out of the Dart heap on the way to the parser, so a
/// curl-piped `~/.ssh/known_hosts` import never materialises in
/// the FRB layer twice. Returns the same summary the string-shape
/// import does. Missing file = `Ok(empty summary)` — matches the
/// Dart-era `importFromFile` contract.
pub async fn db_known_hosts_import_from_path(
    path: String,
    now_ms: i64,
) -> Result<DbKnownHostsImportSummary, String> {
    tokio::task::spawn_blocking(move || {
        let p = std::path::Path::new(&path);
        let content = match std::fs::read_to_string(p) {
            Ok(s) => s,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                return Ok(DbKnownHostsImportSummary {
                    added: 0,
                    skipped_existing: 0,
                    skipped_hashed: 0,
                });
            }
            Err(e) => return Err(format!("read {path}: {e}")),
        };
        let app = lfs_core::app::instance();
        let db = app.db().ok_or_else(|| "db not initialized".to_string())?;
        lfs_core::known_hosts::import_from_string(&db, &app.bus, &content, now_ms)
            .map(DbKnownHostsImportSummary::from)
            .map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("known-hosts import task: {e}"))?
}

/// Render every known-hosts row to the LetsFLUTssh wire format
/// (`host:port keytype base64key` per line). Used by `.lfs`
/// archive export.
pub async fn db_known_hosts_export_to_string() -> Result<String, String> {
    tokio::task::spawn_blocking(move || {
        let app = lfs_core::app::instance();
        let db = app.db().ok_or_else(|| "db not initialized".to_string())?;
        lfs_core::known_hosts::export_to_string(&db).map_err(|e| crate::api::frb_err::from_core(&e))
    })
    .await
    .map_err(|e| format!("known-hosts export task: {e}"))?
}

// ---- app_configs -------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbAppConfig {
    pub data: String,
    pub updated_at_ms: i64,
    pub auto_lock_minutes: i64,
}

impl From<lfs_core::db::app_configs::AppConfigRow> for DbAppConfig {
    fn from(r: lfs_core::db::app_configs::AppConfigRow) -> Self {
        Self {
            data: r.data,
            updated_at_ms: r.updated_at_ms,
            auto_lock_minutes: r.auto_lock_minutes,
        }
    }
}

impl From<DbAppConfig> for lfs_core::db::app_configs::AppConfigRow {
    fn from(r: DbAppConfig) -> Self {
        Self {
            data: r.data,
            updated_at_ms: r.updated_at_ms,
            auto_lock_minutes: r.auto_lock_minutes,
        }
    }
}

pub async fn db_app_configs_get() -> Result<Option<DbAppConfig>, String> {
    run_db(lfs_core::db::app_configs::get)
        .await
        .map(|opt| opt.map(DbAppConfig::from))
}

pub async fn db_app_configs_upsert(row: DbAppConfig) -> Result<(), String> {
    let row: lfs_core::db::app_configs::AppConfigRow = row.into();
    run_db(move |c| lfs_core::db::app_configs::upsert(c, &row)).await
}

// ---- snippets ----------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbSnippet {
    pub id: String,
    pub title: String,
    pub command: String,
    pub description: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

impl From<lfs_core::db::snippets::SnippetRow> for DbSnippet {
    fn from(r: lfs_core::db::snippets::SnippetRow) -> Self {
        Self {
            id: r.id,
            title: r.title,
            command: r.command,
            description: r.description,
            created_at_ms: r.created_at_ms,
            updated_at_ms: r.updated_at_ms,
        }
    }
}

impl From<DbSnippet> for lfs_core::db::snippets::SnippetRow {
    fn from(r: DbSnippet) -> Self {
        Self {
            id: r.id,
            title: r.title,
            command: r.command,
            description: r.description,
            created_at_ms: r.created_at_ms,
            updated_at_ms: r.updated_at_ms,
        }
    }
}

pub async fn db_snippets_list_all() -> Result<Vec<DbSnippet>, String> {
    run_db(lfs_core::db::snippets::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbSnippet::from).collect())
}

pub async fn db_snippets_upsert(row: DbSnippet) -> Result<(), String> {
    let row: lfs_core::db::snippets::SnippetRow = row.into();
    run_db(move |c| lfs_core::db::snippets::upsert(c, &row)).await
}

pub async fn db_snippets_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::snippets::delete(c, &id))
        .await
        .map(|n| n as u32)
}

pub async fn db_snippets_delete_all() -> Result<u32, String> {
    run_db(lfs_core::db::snippets::delete_all)
        .await
        .map(|n| n as u32)
}

pub async fn db_snippets_list_for_session(session_id: String) -> Result<Vec<DbSnippet>, String> {
    run_db(move |c| lfs_core::db::snippets::list_for_session(c, &session_id))
        .await
        .map(|rows| rows.into_iter().map(DbSnippet::from).collect())
}

pub async fn db_session_snippets_link(
    session_id: String,
    snippet_id: String,
) -> Result<(), String> {
    run_db(move |c| lfs_core::db::snippets::link_session_snippet(c, &session_id, &snippet_id)).await
}

pub async fn db_session_snippets_unlink(
    session_id: String,
    snippet_id: String,
) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::snippets::unlink_session_snippet(c, &session_id, &snippet_id))
        .await
        .map(|n| n as u32)
}

pub async fn db_session_snippets_list_ids(session_id: String) -> Result<Vec<String>, String> {
    run_db(move |c| lfs_core::db::snippets::list_session_snippet_ids(c, &session_id)).await
}

// ---- port_forwards -----------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbPortForwardRule {
    pub id: String,
    pub session_id: String,
    pub kind: String,
    pub bind_host: String,
    pub bind_port: i64,
    pub remote_host: String,
    pub remote_port: i64,
    pub description: String,
    pub enabled: bool,
    pub sort_order: i64,
    pub created_at_ms: i64,
}

impl From<lfs_core::db::port_forwards::PortForwardRuleRow> for DbPortForwardRule {
    fn from(r: lfs_core::db::port_forwards::PortForwardRuleRow) -> Self {
        Self {
            id: r.id,
            session_id: r.session_id,
            kind: r.kind,
            bind_host: r.bind_host,
            bind_port: r.bind_port,
            remote_host: r.remote_host,
            remote_port: r.remote_port,
            description: r.description,
            enabled: r.enabled,
            sort_order: r.sort_order,
            created_at_ms: r.created_at_ms,
        }
    }
}

impl From<DbPortForwardRule> for lfs_core::db::port_forwards::PortForwardRuleRow {
    fn from(r: DbPortForwardRule) -> Self {
        Self {
            id: r.id,
            session_id: r.session_id,
            kind: r.kind,
            bind_host: r.bind_host,
            bind_port: r.bind_port,
            remote_host: r.remote_host,
            remote_port: r.remote_port,
            description: r.description,
            enabled: r.enabled,
            sort_order: r.sort_order,
            created_at_ms: r.created_at_ms,
            // `updated_at_ms` is stamped by the DAO at upsert time so
            // the Dart-visible FRB DTO does not need to carry it. The
            // sync apply path uses `upsert_with_stamp` with the peer's
            // timestamp directly.
            updated_at_ms: 0,
        }
    }
}

pub async fn db_port_forwards_list_for_session(
    session_id: String,
) -> Result<Vec<DbPortForwardRule>, String> {
    run_db(move |c| lfs_core::db::port_forwards::list_for_session(c, &session_id))
        .await
        .map(|rows| rows.into_iter().map(DbPortForwardRule::from).collect())
}

pub async fn db_port_forwards_upsert(row: DbPortForwardRule) -> Result<(), String> {
    let row: lfs_core::db::port_forwards::PortForwardRuleRow = row.into();
    run_db(move |c| lfs_core::db::port_forwards::upsert(c, &row)).await
}

pub async fn db_port_forwards_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::port_forwards::delete(c, &id))
        .await
        .map(|n| n as u32)
}

// ---- sftp_bookmarks ----------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbSftpBookmark {
    pub id: String,
    pub session_id: String,
    pub remote_path: String,
    pub label: String,
    pub created_at_ms: i64,
}

impl From<lfs_core::db::sftp_bookmarks::SftpBookmarkRow> for DbSftpBookmark {
    fn from(r: lfs_core::db::sftp_bookmarks::SftpBookmarkRow) -> Self {
        Self {
            id: r.id,
            session_id: r.session_id,
            remote_path: r.remote_path,
            label: r.label,
            created_at_ms: r.created_at_ms,
        }
    }
}

impl From<DbSftpBookmark> for lfs_core::db::sftp_bookmarks::SftpBookmarkRow {
    fn from(r: DbSftpBookmark) -> Self {
        Self {
            id: r.id,
            session_id: r.session_id,
            remote_path: r.remote_path,
            label: r.label,
            created_at_ms: r.created_at_ms,
        }
    }
}

pub async fn db_sftp_bookmarks_list_for_session(
    session_id: String,
) -> Result<Vec<DbSftpBookmark>, String> {
    run_db(move |c| lfs_core::db::sftp_bookmarks::list_for_session(c, &session_id))
        .await
        .map(|rows| rows.into_iter().map(DbSftpBookmark::from).collect())
}

pub async fn db_sftp_bookmarks_upsert(row: DbSftpBookmark) -> Result<(), String> {
    let row: lfs_core::db::sftp_bookmarks::SftpBookmarkRow = row.into();
    run_db(move |c| lfs_core::db::sftp_bookmarks::upsert(c, &row)).await
}

pub async fn db_sftp_bookmarks_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::sftp_bookmarks::delete(c, &id))
        .await
        .map(|n| n as u32)
}

// ---- webdav_session_details -------------------------------------------

/// FRB mirror of
/// [`lfs_core::db::webdav_sessions::WebDavSessionRow`]. Carries the
/// WebDAV transport-config tuple keyed by session id.
#[derive(Debug, Clone)]
pub struct DbWebDavSessionDetails {
    pub session_id: String,
    pub base_url: String,
    pub username: String,
    /// `"basic"` / `"digest"` / `"bearer"`. The connect path parses
    /// this into the typed `lfs_core::webdav::AuthMethod`.
    pub auth_method: String,
    pub self_signed_fingerprint: Option<String>,
}

impl From<lfs_core::db::webdav_sessions::WebDavSessionRow> for DbWebDavSessionDetails {
    fn from(r: lfs_core::db::webdav_sessions::WebDavSessionRow) -> Self {
        Self {
            session_id: r.session_id,
            base_url: r.base_url,
            username: r.username,
            auth_method: r.auth_method,
            self_signed_fingerprint: r.self_signed_fingerprint,
        }
    }
}

impl From<DbWebDavSessionDetails> for lfs_core::db::webdav_sessions::WebDavSessionRow {
    fn from(r: DbWebDavSessionDetails) -> Self {
        Self {
            session_id: r.session_id,
            base_url: r.base_url,
            username: r.username,
            auth_method: r.auth_method,
            self_signed_fingerprint: r.self_signed_fingerprint,
        }
    }
}

/// Fetch the WebDAV detail row paired with `session_id`. `None`
/// when the session is not a WebDAV kind or has not been configured
/// yet — not an error.
pub async fn db_webdav_session_details_get(
    session_id: String,
) -> Result<Option<DbWebDavSessionDetails>, String> {
    run_db(move |c| lfs_core::db::webdav_sessions::get(c, &session_id))
        .await
        .map(|opt| opt.map(DbWebDavSessionDetails::from))
}

/// Insert or replace the WebDAV detail row for `rec.session_id`.
/// Caller stamps the matching `sessions` row with `kind = 'webdav'`
/// — the DAO does not enforce the pairing because the sync apply
/// path may need to insert detail rows ahead of the parent inside
/// one transaction.
pub async fn db_webdav_session_details_upsert(rec: DbWebDavSessionDetails) -> Result<(), String> {
    let rec: lfs_core::db::webdav_sessions::WebDavSessionRow = rec.into();
    run_db_writing_sessions(move |c| lfs_core::db::webdav_sessions::upsert(c, &rec)).await
}

/// Remove the WebDAV detail row for `session_id`. Returns the
/// number of rows affected; `0` is the idempotent no-op for a
/// session that was never a WebDAV kind. The parent session row
/// is untouched.
pub async fn db_webdav_session_details_delete(session_id: String) -> Result<u32, String> {
    run_db_writing_sessions_when(
        move |c| lfs_core::db::webdav_sessions::delete(c, &session_id),
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

/// Every WebDAV detail row, ordered by `session_id`. Used by
/// archive export and a future "all WebDAV sessions" diagnostic.
pub async fn db_webdav_session_details_list_all() -> Result<Vec<DbWebDavSessionDetails>, String> {
    run_db(lfs_core::db::webdav_sessions::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbWebDavSessionDetails::from).collect())
}

/// Canonical SecretStore id for a WebDAV session's password /
/// bearer token. Mirrors `lfs_core::db::webdav_sessions::webdav_secret_id`
/// for the Dart caller — the connect path needs the same shape to
/// resolve the secret on lookup.
#[flutter_rust_bridge::frb(sync)]
pub fn db_webdav_session_details_secret_id(session_id: String) -> String {
    lfs_core::db::webdav_sessions::webdav_secret_id(&session_id)
}

// ---- s3_session_details ------------------------------------------------

/// FRB mirror of
/// [`lfs_core::db::s3_sessions::S3SessionRow`]. Carries the S3
/// transport-config tuple keyed by session id.
#[derive(Debug, Clone)]
pub struct DbS3SessionDetails {
    pub session_id: String,
    pub access_key_id: String,
    pub region: String,
    pub endpoint: String,
    pub path_style: bool,
    pub default_bucket: String,
    pub default_prefix: String,
}

impl From<lfs_core::db::s3_sessions::S3SessionRow> for DbS3SessionDetails {
    fn from(r: lfs_core::db::s3_sessions::S3SessionRow) -> Self {
        Self {
            session_id: r.session_id,
            access_key_id: r.access_key_id,
            region: r.region,
            endpoint: r.endpoint,
            path_style: r.path_style,
            default_bucket: r.default_bucket,
            default_prefix: r.default_prefix,
        }
    }
}

impl From<DbS3SessionDetails> for lfs_core::db::s3_sessions::S3SessionRow {
    fn from(r: DbS3SessionDetails) -> Self {
        Self {
            session_id: r.session_id,
            access_key_id: r.access_key_id,
            region: r.region,
            endpoint: r.endpoint,
            path_style: r.path_style,
            default_bucket: r.default_bucket,
            default_prefix: r.default_prefix,
        }
    }
}

/// Fetch the S3 detail row paired with `session_id`. `None` when
/// the session is not an S3 kind or has not been configured yet —
/// not an error.
pub async fn db_s3_session_details_get(
    session_id: String,
) -> Result<Option<DbS3SessionDetails>, String> {
    run_db(move |c| lfs_core::db::s3_sessions::get(c, &session_id))
        .await
        .map(|opt| opt.map(DbS3SessionDetails::from))
}

/// Insert or replace the S3 detail row for `rec.session_id`.
/// Caller stamps the matching `sessions` row with `kind = 's3'`.
pub async fn db_s3_session_details_upsert(rec: DbS3SessionDetails) -> Result<(), String> {
    let rec: lfs_core::db::s3_sessions::S3SessionRow = rec.into();
    run_db_writing_sessions(move |c| lfs_core::db::s3_sessions::upsert(c, &rec)).await
}

/// Remove the S3 detail row for `session_id`. Returns the number
/// of rows affected; `0` is the idempotent no-op for a session
/// that was never an S3 kind. The parent session row is untouched.
pub async fn db_s3_session_details_delete(session_id: String) -> Result<u32, String> {
    run_db_writing_sessions_when(
        move |c| lfs_core::db::s3_sessions::delete(c, &session_id),
        |n| *n > 0,
    )
    .await
    .map(|n| n as u32)
}

/// Every S3 detail row, ordered by `session_id`. Used by archive
/// export.
pub async fn db_s3_session_details_list_all() -> Result<Vec<DbS3SessionDetails>, String> {
    run_db(lfs_core::db::s3_sessions::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbS3SessionDetails::from).collect())
}

/// Canonical SecretStore id for an S3 session's secret access
/// key. Mirrors `lfs_core::db::s3_sessions::s3_secret_id` for the
/// Dart caller — the connect path needs the same shape to resolve
/// the secret on lookup.
#[flutter_rust_bridge::frb(sync)]
pub fn db_s3_session_details_secret_id(session_id: String) -> String {
    lfs_core::db::s3_sessions::s3_secret_id(&session_id)
}

// ---- tags + M2M --------------------------------------------------------

#[derive(Debug, Clone)]
pub struct DbTag {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub created_at_ms: i64,
}

impl From<lfs_core::db::tags::TagRow> for DbTag {
    fn from(r: lfs_core::db::tags::TagRow) -> Self {
        Self {
            id: r.id,
            name: r.name,
            color: r.color,
            created_at_ms: r.created_at_ms,
        }
    }
}

impl From<DbTag> for lfs_core::db::tags::TagRow {
    fn from(r: DbTag) -> Self {
        Self {
            id: r.id,
            name: r.name,
            color: r.color,
            created_at_ms: r.created_at_ms,
        }
    }
}

pub async fn db_tags_list_all() -> Result<Vec<DbTag>, String> {
    run_db(lfs_core::db::tags::list_all)
        .await
        .map(|rows| rows.into_iter().map(DbTag::from).collect())
}

pub async fn db_tags_upsert(row: DbTag) -> Result<(), String> {
    let row: lfs_core::db::tags::TagRow = row.into();
    run_db(move |c| lfs_core::db::tags::upsert(c, &row)).await
}

pub async fn db_tags_delete(id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::tags::delete(c, &id))
        .await
        .map(|n| n as u32)
}

pub async fn db_tags_delete_all() -> Result<u32, String> {
    run_db(lfs_core::db::tags::delete_all)
        .await
        .map(|n| n as u32)
}

pub async fn db_tags_list_for_session(session_id: String) -> Result<Vec<DbTag>, String> {
    run_db(move |c| lfs_core::db::tags::list_for_session(c, &session_id))
        .await
        .map(|rows| rows.into_iter().map(DbTag::from).collect())
}

pub async fn db_tags_list_for_folder(folder_id: String) -> Result<Vec<DbTag>, String> {
    run_db(move |c| lfs_core::db::tags::list_for_folder(c, &folder_id))
        .await
        .map(|rows| rows.into_iter().map(DbTag::from).collect())
}

pub async fn db_session_tags_link(session_id: String, tag_id: String) -> Result<(), String> {
    run_db(move |c| lfs_core::db::tags::link_session_tag(c, &session_id, &tag_id)).await
}

pub async fn db_session_tags_unlink(session_id: String, tag_id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::tags::unlink_session_tag(c, &session_id, &tag_id))
        .await
        .map(|n| n as u32)
}

pub async fn db_session_tags_list_ids(session_id: String) -> Result<Vec<String>, String> {
    run_db(move |c| lfs_core::db::tags::list_session_tag_ids(c, &session_id)).await
}

pub async fn db_folder_tags_link(folder_id: String, tag_id: String) -> Result<(), String> {
    run_db(move |c| lfs_core::db::tags::link_folder_tag(c, &folder_id, &tag_id)).await
}

pub async fn db_folder_tags_unlink(folder_id: String, tag_id: String) -> Result<u32, String> {
    run_db(move |c| lfs_core::db::tags::unlink_folder_tag(c, &folder_id, &tag_id))
        .await
        .map(|n| n as u32)
}

pub async fn db_folder_tags_list_ids(folder_id: String) -> Result<Vec<String>, String> {
    run_db(move |c| lfs_core::db::tags::list_folder_tag_ids(c, &folder_id)).await
}

#[cfg(test)]
mod tests {
    use super::*;

    // The DAO endpoints (`db_*_list_all` / `_upsert` / `_delete` /
    // import / export) route through `lfs_core::db::Db` against an
    // open SQLCipher connection; covered by the Dart `db_*_test.dart`
    // integration suites that drive an in-memory + tempdir DB
    // through `requireFrbLoaded`. The standalone tests below pin
    // the wire-shape `From` round-trips that cross the FRB boundary
    // on every list / upsert call regardless of DB state, plus the
    // `require_db` missing-DB contract.

    #[test]
    fn require_db_returns_err_when_db_not_initialized() {
        // The shim returns `Err("db not initialized")` rather than
        // panic when no DB has been opened — every DAO call routes
        // through here, so the contract is load-bearing.
        let _ = lfs_core::app::init();
        // Ensure no DB is registered (close any leftover from prior
        // tests in the same binary).
        lfs_core::app::instance().db_close();
        match require_db() {
            // `Arc<Db>` doesn't implement `Debug`, so unwrap_err
            // can't compile — pattern-match instead.
            Err(msg) => assert!(msg.contains("db not initialized")),
            Ok(_) => panic!("expected Err for missing DB"),
        }
    }

    #[test]
    fn db_ssh_key_round_trips_through_core() {
        let db = DbSshKey {
            id: "key-1".into(),
            label: "alpha".into(),
            private_key: "-----BEGIN…".into(),
            public_key: "ssh-ed25519 AAAA…".into(),
            key_type: "ed25519".into(),
            is_generated: true,
            created_at_ms: 1_700_000_000,
            credential_id: None,
            application_string: None,
            has_user_verification: false,
            agent_policy: "ask".into(),
            backend: "software".into(),
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
        };
        let core: lfs_core::db::ssh_keys::SshKeyRow = db.clone().into();
        let back: DbSshKey = core.into();
        assert_eq!(back.id, db.id);
        assert_eq!(back.label, db.label);
        assert_eq!(back.private_key, db.private_key);
        assert_eq!(back.public_key, db.public_key);
        assert_eq!(back.key_type, db.key_type);
        assert_eq!(back.is_generated, db.is_generated);
        assert_eq!(back.created_at_ms, db.created_at_ms);
    }

    #[test]
    fn db_ssh_key_certificate_round_trips_through_core() {
        let db = DbSshKeyCertificate {
            key_id: "key-1".into(),
            certificate: vec![0xDE, 0xAD, 0xBE, 0xEF],
            valid_after: 1_700_000_000,
            valid_before: 1_700_086_400,
            principals: r#"["alice","root"]"#.into(),
            critical_options: r#"{"force-command":"echo hi"}"#.into(),
            fingerprint: "SHA256:abc".into(),
        };
        let core: lfs_core::db::ssh_key_certificates::CertRecord = db.clone().into();
        let back: DbSshKeyCertificate = core.into();
        assert_eq!(back.key_id, db.key_id);
        assert_eq!(back.certificate, db.certificate);
        assert_eq!(back.valid_after, db.valid_after);
        assert_eq!(back.valid_before, db.valid_before);
        assert_eq!(back.principals, db.principals);
        assert_eq!(back.critical_options, db.critical_options);
        assert_eq!(back.fingerprint, db.fingerprint);
    }

    #[test]
    fn db_folder_round_trips_through_core() {
        let db = DbFolder {
            id: "folder-1".into(),
            name: "production".into(),
            parent_id: Some("root".into()),
            sort_order: 5,
            collapsed: true,
            created_at_ms: 1_700_000_000,
        };
        let core: lfs_core::db::folders::FolderRow = db.clone().into();
        let back: DbFolder = core.into();
        assert_eq!(back.id, db.id);
        assert_eq!(back.name, db.name);
        assert_eq!(back.parent_id, db.parent_id);
        assert_eq!(back.sort_order, db.sort_order);
        assert_eq!(back.collapsed, db.collapsed);
    }

    #[test]
    fn db_session_round_trips_every_field_through_core() {
        let db = DbSession {
            id: "sess-1".into(),
            label: "Edge".into(),
            folder_id: Some("folder-1".into()),
            kind: "ssh".into(),
            host: "edge.example.com".into(),
            port: 2222,
            user: "deploy".into(),
            auth_type: "key".into(),
            password: String::new(),
            key_path: "/keys/edge".into(),
            key_data: "-----BEGIN…".into(),
            key_id: Some("key-1".into()),
            passphrase: String::new(),
            sort_order: 0,
            notes: "primary".into(),
            last_connected_at_ms: Some(1_700_000_000),
            extras: r#"{"agent": false}"#.into(),
            via_session_id: None,
            via_host: None,
            via_port: None,
            via_user: None,
            created_at_ms: 1_700_000_000,
            updated_at_ms: 1_700_000_000,
        };
        let core: lfs_core::db::sessions::SessionRow = db.clone().into();
        let back: DbSession = core.into();
        assert_eq!(back.id, db.id);
        assert_eq!(back.label, db.label);
        assert_eq!(back.folder_id, db.folder_id);
        assert_eq!(back.kind, "ssh");
        assert_eq!(back.host, db.host);
        assert_eq!(back.port, db.port);
        assert_eq!(back.user, db.user);
        assert_eq!(back.auth_type, db.auth_type);
        assert_eq!(back.key_id, db.key_id);
        assert_eq!(back.last_connected_at_ms, db.last_connected_at_ms);
        assert_eq!(back.extras, db.extras);
    }

    #[test]
    fn db_webdav_session_details_round_trips_through_core() {
        let db = DbWebDavSessionDetails {
            session_id: "sess-1".into(),
            base_url: "https://example.com/remote.php/dav/files/alice/".into(),
            username: "alice".into(),
            auth_method: "basic".into(),
            self_signed_fingerprint: Some("SHA256:abc".into()),
        };
        let core: lfs_core::db::webdav_sessions::WebDavSessionRow = db.clone().into();
        let back: DbWebDavSessionDetails = core.into();
        assert_eq!(back.session_id, db.session_id);
        assert_eq!(back.base_url, db.base_url);
        assert_eq!(back.username, db.username);
        assert_eq!(back.auth_method, db.auth_method);
        assert_eq!(back.self_signed_fingerprint, db.self_signed_fingerprint);
    }

    #[test]
    fn db_known_host_carries_every_field_through() {
        let core = lfs_core::db::known_hosts::KnownHostRow {
            id: 7,
            host: "edge.example.com".into(),
            port: 2222,
            key_type: "ssh-ed25519".into(),
            key_base64: "AAAA…".into(),
            added_at_ms: 1_700_000_000,
        };
        let db: DbKnownHost = core.into();
        assert_eq!(db.id, 7);
        assert_eq!(db.host, "edge.example.com");
        assert_eq!(db.port, 2222);
        assert_eq!(db.key_type, "ssh-ed25519");
        assert_eq!(db.key_base64, "AAAA…");
    }

    #[test]
    fn db_known_hosts_import_summary_carries_counts() {
        let core = lfs_core::known_hosts::ImportSummary {
            added: 5,
            skipped_existing: 2,
            skipped_hashed: 1,
        };
        let db: DbKnownHostsImportSummary = core.into();
        assert_eq!(db.added, 5);
        assert_eq!(db.skipped_existing, 2);
        assert_eq!(db.skipped_hashed, 1);
    }

    #[test]
    fn db_app_config_round_trips_through_core() {
        let db = DbAppConfig {
            data: r#"{"theme": "dark"}"#.into(),
            updated_at_ms: 1_700_000_000,
            auto_lock_minutes: 5,
        };
        let core: lfs_core::db::app_configs::AppConfigRow = db.clone().into();
        let back: DbAppConfig = core.into();
        assert_eq!(back.data, db.data);
        assert_eq!(back.updated_at_ms, db.updated_at_ms);
        assert_eq!(back.auto_lock_minutes, db.auto_lock_minutes);
    }

    #[test]
    fn db_snippet_round_trips_through_core() {
        let db = DbSnippet {
            id: "snip-1".into(),
            title: "Restart nginx".into(),
            command: "sudo systemctl restart nginx".into(),
            description: "production reload".into(),
            created_at_ms: 1_700_000_000,
            updated_at_ms: 1_700_000_000,
        };
        let core: lfs_core::db::snippets::SnippetRow = db.clone().into();
        let back: DbSnippet = core.into();
        assert_eq!(back.id, db.id);
        assert_eq!(back.title, db.title);
        assert_eq!(back.command, db.command);
        assert_eq!(back.description, db.description);
    }

    #[test]
    fn db_port_forward_rule_round_trips_through_core() {
        let db = DbPortForwardRule {
            id: "rule-1".into(),
            session_id: "sess-1".into(),
            kind: "local".into(),
            bind_host: "127.0.0.1".into(),
            bind_port: 6379,
            remote_host: "redis.internal".into(),
            remote_port: 6379,
            description: "redis".into(),
            enabled: true,
            sort_order: 0,
            created_at_ms: 1_700_000_000,
        };
        let core: lfs_core::db::port_forwards::PortForwardRuleRow = db.clone().into();
        let back: DbPortForwardRule = core.into();
        assert_eq!(back.id, db.id);
        assert_eq!(back.session_id, db.session_id);
        assert_eq!(back.kind, db.kind);
        assert_eq!(back.bind_port, db.bind_port);
        assert_eq!(back.remote_port, db.remote_port);
        assert_eq!(back.description, db.description);
        assert_eq!(back.enabled, db.enabled);
    }

    #[test]
    fn db_tag_round_trips_through_core() {
        let db = DbTag {
            id: "tag-prod".into(),
            name: "Production".into(),
            color: Some("#FF5722".into()),
            created_at_ms: 1_700_000_000,
        };
        let core: lfs_core::db::tags::TagRow = db.clone().into();
        let back: DbTag = core.into();
        assert_eq!(back.id, db.id);
        assert_eq!(back.name, db.name);
        assert_eq!(back.color, db.color);
    }

    #[test]
    fn db_sftp_bookmark_round_trips_through_core() {
        let db = DbSftpBookmark {
            id: "bm-1".into(),
            session_id: "sess-1".into(),
            remote_path: "/var/log/app".into(),
            label: "logs".into(),
            created_at_ms: 1_700_000_000,
        };
        let core: lfs_core::db::sftp_bookmarks::SftpBookmarkRow = db.clone().into();
        let back: DbSftpBookmark = core.into();
        assert_eq!(back.id, db.id);
        assert_eq!(back.session_id, db.session_id);
        assert_eq!(back.remote_path, db.remote_path);
    }
}
