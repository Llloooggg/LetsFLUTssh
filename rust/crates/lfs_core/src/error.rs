//! Typed error enum surfaced across the public API.
//!
//! Adapters translate these variants into frontend-friendly shapes
//! (FRB exception, tauri command error, CLI exit code). Core code
//! returns `Result<T, Error>` and never panics on transport faults.
//!
//! Display strings here are intended for log output, not for
//! user-facing UI — UI strings are localized on the Dart side via
//! the `S.of(context)` lookup, keyed off the variant.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    #[error("connect failed: {0}")]
    Connect(String),

    #[error("ssh handshake failed: {0}")]
    Handshake(String),

    #[error("authentication failed")]
    AuthFailed,

    #[error("auth error: {0}")]
    Auth(String),

    #[error("key parse failed: {0}")]
    KeyParse(String),

    #[error("passphrase required")]
    PassphraseRequired,

    #[error("passphrase incorrect")]
    PassphraseIncorrect,

    #[error("host key rejected")]
    HostKeyRejected,

    #[error("io: {0}")]
    Io(String),

    /// SQLCipher / rusqlite / DAO-layer failures. Carved out of the
    /// generic `Io` bucket so frontend matchers (toast routing, retry
    /// gating, the corrupt-DB recovery dialog) can pattern-match the
    /// variant directly instead of substring-matching the message.
    #[error("db: {0}")]
    Db(String),

    /// SFTP-protocol errors surfaced from the russh-sftp client. Same
    /// motivation as `Db` — carving them out keeps transfer-driver +
    /// file-browser surfaces from substring-matching `"sftp …"` to
    /// distinguish a remote refusal (permission denied, no such file)
    /// from a transport drop (`russh::Error → Io`).
    #[error("sftp: {0}")]
    Sftp(String),

    /// Connection / session registry misses — the caller asked for a
    /// session id that has no live transport, or the orchestrator's
    /// async branch raced a teardown. Frontend can route these into
    /// the "stale handle, retry connect" recovery rather than the
    /// generic IO toast.
    #[error("session unavailable: {0}")]
    SessionUnavailable(String),

    /// Recorder pipeline errors — registry miss on an unknown id,
    /// frame-write failure, magic-bytes corruption, etc. Frontend's
    /// recorder panel renders these inline rather than surfacing them
    /// as a generic IO toast.
    #[error("recorder: {0}")]
    Recorder(String),

    /// Archive (`.lfs`) build / parse / apply errors. Frontend's
    /// import + export dialogs render these in their own toast rail
    /// (the corruption-recovery dialog also matches a subset of
    /// these by variant rather than substring).
    #[error("archive: {0}")]
    Archive(String),

    /// Transport-level failures inside the connection / port-forward
    /// / transfer drivers. These are state-machine errors above the
    /// raw `russh::Error → Io` layer (e.g. "connection actor
    /// shutdown", "transfer task missing context") that the UI needs
    /// to distinguish from a low-level IO drop.
    #[error("transport: {0}")]
    Transport(String),

    /// Hardware-vault (TPM / Keychain / Keystore / CNG) round-trip
    /// errors. Frontend routes these into the tier-specific
    /// recovery rail rather than a generic IO toast.
    #[error("vault: {0}")]
    Vault(String),

    /// Update-channel HTTP / parse / installer-spawn failures. The
    /// update dialog renders these inline so the user knows the
    /// retry button hits the same network condition vs. a generic
    /// "something went wrong".
    #[error("update: {0}")]
    Update(String),

    /// WebDAV transport failures surfaced from
    /// `lfs_core::webdav` — multistatus XML parse, transport drop
    /// mid-PROPFIND, auth challenge that did not yield a recognised
    /// scheme, ETag mismatch on a conditional PUT, server returning
    /// a forbidden `depth=infinity` listing. Carved out of the
    /// generic `Io` bucket so the sync orchestrator and the
    /// file-browser provider can route a 412 (etag-mismatch needs
    /// a re-read) differently from a 401 (credential prompt)
    /// without substring matching the message.
    #[error("webdav: {0}")]
    WebDav(String),

    /// S3 transport failures surfaced from `lfs_core::s3` and the
    /// matching `storage::Provider` adapter. The AWS REST surface
    /// returns the same XML error-document shape across every
    /// S3-compatible vendor (AWS, MinIO, Wasabi, R2, Backblaze
    /// B2-S3, DigitalOcean Spaces, Scaleway); this variant carries
    /// the canonical message extracted from the body or a verbatim
    /// transport error when the body could not be parsed. Carved
    /// out of `Io` so the file-browser can route a 401/403 (re-prompt
    /// credentials) differently from a 404 (path missing) or a 5xx
    /// (retryable) without substring matching.
    #[error("s3: {0}")]
    S3(String),

    /// Platform-tooling subprocess errors (Linux `tpm2-tools`, macOS
    /// `security` / `codesign` / `productsign`). The first-launch
    /// wizard + Settings → Security surfaces these against the
    /// per-tier capability snapshot rather than as generic IO.
    #[error("platform: {0}")]
    Platform(String),

    #[error("crypto: {0}")]
    Crypto(String),

    /// FIDO2 / CTAP2 hardware-key failures surfaced by
    /// `lfs_core::fido2` — no device reachable, PIN rejected, user
    /// timeout (the device LED stopped blinking without a tap), HID
    /// transport drop. Carved out of `Io` / `Platform` so the connect
    /// path's hardware-key prompt dialog can route a `wrong PIN`
    /// retry differently from a `no device reachable` cancel.
    #[error("fido2: {0}")]
    Fido2(String),

    /// PKCS#11 (Cryptoki) hardware-token failures surfaced by
    /// `lfs_os_security::pkcs11` — module load failure, slot empty,
    /// PIN rejected, lockout imminent / final-try, sign mechanism
    /// refused, GOST-only token, dropped session. Carved out of
    /// `Io` / `Platform` so the connect path's smart-card prompt
    /// dialog can route a `wrong PIN` retry, a `pin locked` halt,
    /// and a `token unplugged` replug branch independently.
    #[error("pkcs11: {0}")]
    Pkcs11(String),

    /// Apple Secure Enclave failures surfaced by
    /// `lfs_os_security::apple_se_ssh` — `errSecMissingEntitlement`
    /// on an ad-hoc-signed bundle, biometric cancel, key not found
    /// after a Keychain reset, `SecKeyCreateSignature` refused
    /// (signing-identity mismatch). Carved out of `Io` /
    /// `Platform` so the connect path's biometric prompt dialog
    /// can route a code-sign reason ("re-sign the app") differently
    /// from a cancel ("touch the sensor again") or a missing-key
    /// state ("re-generate the key on this device").
    #[error("enclave: {0}")]
    Enclave(String),

    /// Windows Hello / NCrypt failures surfaced by
    /// `lfs_os_security::windows::ncrypt_ssh` — Hello not configured,
    /// no TPM (software-KSP fallback selected at create time and
    /// later disallowed by policy), PCP provider open failed, user
    /// dismissed the Hello prompt, P-384 unsupported by the host TPM
    /// firmware. Carved out of `Io` / `Platform` so the connect path's
    /// Hello prompt dialog can route a `cancelled` reason ("authenticate
    /// again") differently from a hardware-absent reason ("re-import
    /// on this PC").
    #[error("hello: {0}")]
    Hello(String),

    /// TPM 2.0 SSH-signer failures surfaced by
    /// `lfs_os_security::linux::tpm_ssh` (Linux ESAPI) and
    /// `lfs_os_security::windows::ncrypt_ssh` silent-variant path
    /// (Windows PCP without UI policy). Covers no-TPM detection,
    /// PIN rejected, dictionary-attack lockout, malformed cross-tool
    /// `.tpm` blob, persistent-slot in use, missing `tss` group
    /// membership on the Linux device node. Carved out of `Io` /
    /// `Platform` so the connect path can route a `wrong PIN` retry
    /// distinctly from a hardware-wide lockout cooldown.
    #[error("tpm-ssh: {0}")]
    Tpm(String),

    /// Android Hardware Keystore / StrongBox SSH-signer failures
    /// surfaced by `lfs_os_security::android::keystore_signer` — no
    /// biometric enrolled, key invalidated by a fresh enrolment
    /// (`KeyPermanentlyInvalidatedException`), StrongBox refused
    /// (`StrongBoxUnavailableException`), per-op auth window expired
    /// (`UserNotAuthenticatedException`) after a `BiometricPrompt`
    /// dismissal, generic JNI failure. Carved out of `Io` /
    /// `Platform` so the Dart connect / wizard dialog can route an
    /// `invalidated:` reason ("re-register the public key on your
    /// servers") differently from a `strongbox unavailable:`
    /// fallback choice and a `cancelled:` retry.
    #[error("keystore: {0}")]
    Keystore(String),

    #[error("timeout")]
    Timeout,

    /// Operation was cancelled cooperatively — typically a long-
    /// running walker (recursive SFTP transfer, archive build)
    /// noticed its progress callback returned `false` and stopped
    /// at the next yield point.
    #[error("cancelled")]
    Cancelled,

    /// `.lfs` archive's manifest reports a `schema_version` newer
    /// than `migration::SchemaVersions::ARCHIVE`, or an
    /// out-of-range value (`<= 0`). The Display format is parsed
    /// Dart-side into `UnsupportedLfsVersionException`, which the
    /// import dialog renders with the "update the app" message —
    /// keep the `found=` / `supported=` shape stable. `found` is
    /// `i64` so the raw manifest value reaches the user / log
    /// trace verbatim instead of being clamped to `i32::MAX`.
    #[error("unsupported_archive_version: found={found}, supported={supported}")]
    ArchiveFutureVersion { found: i64, supported: i32 },

    /// Operation is structurally unavailable on this build target — the
    /// in-process ssh-agent endpoint on Android / iOS, or any future
    /// capability the platform fundamentally cannot host. Frontend
    /// renders the matching control disabled-with-reason instead of
    /// attempting the call and surfacing a less-actionable downstream
    /// error.
    #[error("unsupported: {0}")]
    Unsupported(String),
}

impl From<russh::Error> for Error {
    fn from(e: russh::Error) -> Self {
        // russh wraps a number of underlying conditions in one variant;
        // we keep the message verbatim and let UI branch on the typed
        // wrapper variant chosen by the caller (Connect/Handshake/Auth).
        Error::Io(e.to_string())
    }
}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::Io(e.to_string())
    }
}
