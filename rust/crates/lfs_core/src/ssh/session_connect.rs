//! Connect/auth matrix for [`Session`] — every transport-
//! establishment variant (password, pubkey, cert, sk/FIDO2,
//! PKCS#11, Enclave, Hello, TPM, Keystore, agent, plus their
//! ProxyJump and owned-secret forms) and `open_shell`. Split out
//! of `ssh/mod.rs` so the module core (handler, types, post-
//! connect operations) stays navigable. A child module, so these
//! impl blocks see `Session`'s module-private fields.

use super::*;
use crate::error::Error;
use russh::keys::{ssh_key, HashAlg};
use std::sync::Arc;
use tokio::sync::Mutex;
use zeroize::Zeroizing;

impl Session {
    /// Connect + authenticate with a username and password. The
    /// returned session stays live until `disconnect` or `Drop`.
    pub async fn connect_password(
        host: &str,
        port: u16,
        user: &str,
        password: &str,
    ) -> Result<Self, Error> {
        let password = Zeroizing::new(password.to_owned());
        let (mut handle, forward_rx) = open_handle_for_session(host, port).await?;

        let auth_result = handle
            .authenticate_password(user, password.as_str())
            .await
            .map_err(|e| Error::Auth(e.to_string()))?;

        check_auth_result(auth_result)?;

        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Connect + authenticate with a username and OpenSSH-format
    /// private key. `passphrase` is required only when the key file
    /// is encrypted.
    pub async fn connect_pubkey(
        host: &str,
        port: u16,
        user: &str,
        private_key: &[u8],
        passphrase: Option<&str>,
    ) -> Result<Self, Error> {
        let passphrase = passphrase.map(|p| Zeroizing::new(p.to_owned()));
        let key = parse_private_key(private_key, passphrase.as_deref().map(|s| &s[..]))?;

        let (mut handle, forward_rx) = open_handle_for_session(host, port).await?;
        finish_authenticate_pubkey(&mut handle, user, key).await?;

        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Connect + authenticate with a hardware-bound `sk-*` SSH key.
    ///
    /// `public_openssh` is the single-line `id_*.pub` body captured
    /// at import; we re-parse it here to recover the SSH `Algorithm`
    /// and `PublicKey` russh's `authenticate_publickey_with` requires.
    /// `credential_id` + `application` come from the same parse; we
    /// take them as parameters so the FRB API stays decoupled from
    /// the public-key text-shape (a future PKCS#11-encoded credential
    /// may not parse out of an `id_*.pub` blob).
    ///
    /// Signing routes through [`sk_signer::FidoSigner`], which drives
    /// `lfs_core::fido2::get_assertion` on every userauth signature
    /// challenge. Private key material lives on the authenticator —
    /// never on the heap.
    pub async fn connect_pubkey_sk(
        host: &str,
        port: u16,
        user: &str,
        public_openssh: &str,
        credential_id: &[u8],
        application: &str,
        pin: Option<&str>,
    ) -> Result<Self, Error> {
        let (mut handle, forward_rx) = open_handle_for_session(host, port).await?;
        finish_authenticate_pubkey_sk(
            &mut handle,
            user,
            public_openssh,
            credential_id,
            application,
            pin,
        )
        .await?;
        Ok(Session::from_handle(handle, forward_rx))
    }

    /// FIDO2 pubkey auth tunnelled through a ProxyJump parent.
    ///
    /// Mirrors the non-proxy [`Session::connect_pubkey_sk`] but
    /// dials the inner SSH transport through a `direct-tcpip` channel
    /// on `parent` instead of opening a fresh TCP socket — exactly
    /// the same composition trick the other `connect_*_via_proxy`
    /// variants use. Used by the cert-via-FIDO composition
    /// ([`Session::connect_pubkey_sk_cert_via_proxy`]); the bare-sk
    /// dispatcher gates this until a future arc wires it through FRB.
    pub async fn connect_pubkey_sk_via_proxy(
        parent: &Session,
        host: &str,
        port: u16,
        args: ConnectPubkeySkArgs<'_>,
    ) -> Result<Self, Error> {
        let (mut handle, forward_rx) = open_handle_via_proxy(parent, host, port).await?;
        finish_authenticate_pubkey_sk(
            &mut handle,
            args.user,
            args.public_openssh,
            args.credential_id,
            args.application,
            args.pin,
        )
        .await?;
        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Connect + authenticate with a FIDO2 hardware-bound `sk-*` key
    /// AND an OpenSSH certificate paired to it. The cert is the
    /// CA-signed credential the server accepts via `TrustedUserCAKeys`;
    /// the device-resident private half signs every userauth round
    /// trip. Free composition of T-1's signer + russh's
    /// `authenticate_certificate_with<S: Signer>` introduced in 0.59.
    ///
    /// `public_openssh` is the captured `id_*.pub` body; we re-parse
    /// it to confirm the algorithm is `sk-*` before driving the cert
    /// handshake. `cert_bytes` is the parsed OpenSSH certificate
    /// (`*-cert-v01@openssh.com`). The cert's inner signing key MUST
    /// match `public_openssh` — the cert-pairing import flow already
    /// verifies the fingerprint match, so any divergence here is a
    /// DB-corruption story rather than an expected failure mode.
    pub async fn connect_pubkey_sk_cert(
        host: &str,
        port: u16,
        args: ConnectPubkeySkCertArgs<'_>,
    ) -> Result<Self, Error> {
        let (mut handle, forward_rx) = open_handle_for_session(host, port).await?;
        finish_authenticate_pubkey_sk_cert(&mut handle, args).await?;
        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Cert-via-FIDO tunnelled through a ProxyJump parent. Same
    /// composition as the non-proxy
    /// [`Session::connect_pubkey_sk_cert`] but the russh handshake
    /// rides a `direct-tcpip` channel on `parent`. Reserved for a
    /// future arc that wires hardware-bound auth through bastions —
    /// the bare-sk dispatcher in `connection::mod` gates both the
    /// `sk` and `sk-cert` arms until that wiring lands.
    pub async fn connect_pubkey_sk_cert_via_proxy(
        parent: &Session,
        host: &str,
        port: u16,
        args: ConnectPubkeySkCertArgs<'_>,
    ) -> Result<Self, Error> {
        let (mut handle, forward_rx) = open_handle_via_proxy(parent, host, port).await?;
        finish_authenticate_pubkey_sk_cert(&mut handle, args).await?;
        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Open a PTY-backed shell channel sized to `cols × rows`. The
    /// returned `Shell` owns both halves of the channel and exposes
    /// concurrent write + read APIs.
    ///
    /// Fixes `term = "xterm-256color"`; a `term` override is a
    /// follow-up alongside the Dart-side wiring.
    pub async fn open_shell(&self, cols: u32, rows: u32) -> Result<Shell, Error> {
        let channel = self
            .handle
            .channel_open_session()
            .await
            .map_err(|e| Error::Io(e.to_string()))?;

        channel
            .request_pty(false, "xterm-256color", cols, rows, 0, 0, &[])
            .await
            .map_err(|e| Error::Io(e.to_string()))?;
        channel
            .request_shell(false)
            .await
            .map_err(|e| Error::Io(e.to_string()))?;

        let (read_half, write_half) = channel.split();
        Ok(Shell {
            write_half,
            read_half: Mutex::new(read_half),
        })
    }

    /// Connect + authenticate with an OpenSSH **certificate** (an SSH
    /// public key signed by a CA, plus the matching private key).
    /// Cert format: `-----BEGIN OPENSSH CERTIFICATE-----` / the
    /// `id_ed25519-cert.pub` companion file produced by `ssh-keygen
    /// -s ca_key id_ed25519.pub`. Server must trust the issuing CA
    /// (`TrustedUserCAKeys` in sshd_config).
    ///
    /// Used by §6.2 SSH certificates. russh recognises every
    /// `*-cert-v01@openssh.com` algorithm name natively — no fork
    /// or upstream patch required.
    pub async fn connect_pubkey_cert(
        host: &str,
        port: u16,
        user: &str,
        private_key: &[u8],
        passphrase: Option<&str>,
        cert_bytes: &[u8],
    ) -> Result<Self, Error> {
        let passphrase = passphrase.map(|p| Zeroizing::new(p.to_owned()));
        let key = parse_private_key(private_key, passphrase.as_deref().map(|s| &s[..]))?;
        let cert = parse_certificate(cert_bytes)?;

        let (mut handle, forward_rx) = open_handle_for_session(host, port).await?;

        let auth_result = handle
            .authenticate_openssh_cert(user, Arc::new(key), cert)
            .await
            .map_err(|e| Error::Auth(e.to_string()))?;

        check_auth_result(auth_result)?;

        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Connect + authenticate by delegating signing to the system
    /// SSH agent ($SSH_AUTH_SOCK on Unix, OpenSSH-style named pipe
    /// on Windows, Pageant on Windows fallback). Iterates over the
    /// agent's identities in order; first one the server accepts
    /// wins. Returns a descriptive `Error::Auth` (identity count, none
    /// accepted) only if every identity is rejected.
    pub async fn connect_agent(host: &str, port: u16, user: &str) -> Result<Self, Error> {
        connect_via_agent(host.to_owned(), port, user.to_owned()).await
    }

    // ---- ProxyJump bastion variants (1.10b) ------------------------
    // Each `connect_*_via_proxy` mirrors its non-proxy counterpart but
    // tunnels the SSH handshake through a `direct-tcpip` channel on
    // `parent` instead of dialing a fresh TCP socket. The child takes
    // a `&Session` reference so it composes — the returned Session can
    // itself act as a parent for the next hop, supporting multi-hop
    // ProxyJump chains (A → B → C) without any special-case logic.

    /// Password auth tunnelled through a ProxyJump parent.
    pub async fn connect_password_via_proxy(
        parent: &Session,
        host: &str,
        port: u16,
        user: &str,
        password: &str,
    ) -> Result<Self, Error> {
        let password = Zeroizing::new(password.to_owned());
        let (mut handle, forward_rx) = open_handle_via_proxy(parent, host, port).await?;

        let auth_result = handle
            .authenticate_password(user, password.as_str())
            .await
            .map_err(|e| Error::Auth(e.to_string()))?;

        check_auth_result(auth_result)?;

        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Pubkey auth tunnelled through a ProxyJump parent.
    pub async fn connect_pubkey_via_proxy(
        parent: &Session,
        host: &str,
        port: u16,
        user: &str,
        private_key: &[u8],
        passphrase: Option<&str>,
    ) -> Result<Self, Error> {
        let passphrase = passphrase.map(|p| Zeroizing::new(p.to_owned()));
        let key = parse_private_key(private_key, passphrase.as_deref().map(|s| &s[..]))?;

        let (mut handle, forward_rx) = open_handle_via_proxy(parent, host, port).await?;
        finish_authenticate_pubkey(&mut handle, user, key).await?;

        Ok(Session::from_handle(handle, forward_rx))
    }

    /// OpenSSH cert auth tunnelled through a ProxyJump parent.
    pub async fn connect_pubkey_cert_via_proxy(
        parent: &Session,
        host: &str,
        port: u16,
        user: &str,
        private_key: &[u8],
        passphrase: Option<&str>,
        cert_bytes: &[u8],
    ) -> Result<Self, Error> {
        let passphrase = passphrase.map(|p| Zeroizing::new(p.to_owned()));
        let key = parse_private_key(private_key, passphrase.as_deref().map(|s| &s[..]))?;
        let cert = parse_certificate(cert_bytes)?;

        let (mut handle, forward_rx) = open_handle_via_proxy(parent, host, port).await?;

        let auth_result = handle
            .authenticate_openssh_cert(user, Arc::new(key), cert)
            .await
            .map_err(|e| Error::Auth(e.to_string()))?;

        check_auth_result(auth_result)?;

        Ok(Session::from_handle(handle, forward_rx))
    }

    // ---- Secret-store-backed connects ─────────────────────────────
    // The plaintext credential never crosses the FRB boundary —
    // callers stash bytes in the process-singleton SecretStore
    // (`lfs_core::app::instance().secrets`) under a stable id, then
    // hand the id (not the bytes) over FRB. These methods resolve
    // the id locally, copy into a Zeroizing buffer, and feed russh
    // exactly as the plaintext variants do. The fetched copy
    // scrubs on drop at the end of the connect call.

    /// Password auth using the SecretStore entry under `secret_id`.
    pub async fn connect_password_with_secret(
        host: &str,
        port: u16,
        user: &str,
        secret_id: &str,
    ) -> Result<Self, Error> {
        let bytes = crate::app::instance()
            .secrets
            .get(secret_id)
            .ok_or_else(|| Error::Auth(format!("no cached secret '{secret_id}'")))?;
        let pwd = std::str::from_utf8(&bytes)
            .map_err(|e| Error::Auth(format!("password not utf-8: {e}")))?;
        Self::connect_password(host, port, user, pwd).await
    }

    /// Owned-arg twin of [`connect_password_with_secret`]. Returns
    /// `Pin<Box<dyn Future + Send + 'static>>` so the FRB layer's
    /// `wrap_async` `Send + 'static` bound is satisfied without
    /// HRTB inference reaching into the `&str`-borrowing internals.
    /// One heap allocation per connect — invisible next to the
    /// russh handshake.
    pub fn connect_password_with_secret_owned(
        host: String,
        port: u16,
        user: String,
        secret_id: String,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(
            async move { Self::connect_password_with_secret(&host, port, &user, &secret_id).await },
        )
    }

    /// Pubkey auth using SecretStore entries — `key_secret_id` for
    /// the private-key bytes and an optional `passphrase_secret_id`
    /// for the decryption passphrase.
    pub async fn connect_pubkey_with_secret(
        host: &str,
        port: u16,
        user: &str,
        key_secret_id: &str,
        passphrase_secret_id: Option<&str>,
    ) -> Result<Self, Error> {
        let store = &crate::app::instance().secrets;
        let key_bytes = store
            .get(key_secret_id)
            .ok_or_else(|| Error::Auth(format!("no cached key '{key_secret_id}'")))?;
        let pass_bytes = match passphrase_secret_id {
            Some(id) => store.get(id),
            None => None,
        };
        let passphrase = match pass_bytes.as_ref() {
            Some(b) => Some(
                std::str::from_utf8(b)
                    .map_err(|e| Error::Auth(format!("passphrase not utf-8: {e}")))?,
            ),
            None => None,
        };
        Self::connect_pubkey(host, port, user, &key_bytes, passphrase).await
    }

    /// Owned-arg twin of [`connect_pubkey_with_secret`]. Boxed for
    /// the same reason as [`connect_password_with_secret_owned`].
    pub fn connect_pubkey_with_secret_owned(
        host: String,
        port: u16,
        user: String,
        key_secret_id: String,
        passphrase_secret_id: Option<String>,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            Self::connect_pubkey_with_secret(
                &host,
                port,
                &user,
                &key_secret_id,
                passphrase_secret_id.as_deref(),
            )
            .await
        })
    }

    /// OpenSSH-cert auth using SecretStore entries — `key_secret_id`
    /// for the private-key bytes, `cert_secret_id` for the cert
    /// blob, optional `passphrase_secret_id`.
    pub async fn connect_pubkey_cert_with_secret(
        host: &str,
        port: u16,
        user: &str,
        key_secret_id: &str,
        cert_secret_id: &str,
        passphrase_secret_id: Option<&str>,
    ) -> Result<Self, Error> {
        let store = &crate::app::instance().secrets;
        let key_bytes = store
            .get(key_secret_id)
            .ok_or_else(|| Error::Auth(format!("no cached key '{key_secret_id}'")))?;
        let cert_bytes = store
            .get(cert_secret_id)
            .ok_or_else(|| Error::Auth(format!("no cached cert '{cert_secret_id}'")))?;
        let pass_bytes = match passphrase_secret_id {
            Some(id) => store.get(id),
            None => None,
        };
        let passphrase = match pass_bytes.as_ref() {
            Some(b) => Some(
                std::str::from_utf8(b)
                    .map_err(|e| Error::Auth(format!("passphrase not utf-8: {e}")))?,
            ),
            None => None,
        };
        Self::connect_pubkey_cert(host, port, user, &key_bytes, passphrase, &cert_bytes).await
    }

    /// Owned-arg twin of [`connect_pubkey_cert_with_secret`]. Boxed
    /// for the same reason as [`connect_password_with_secret_owned`].
    pub fn connect_pubkey_cert_with_secret_owned(
        args: ConnectPubkeyCertOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            Self::connect_pubkey_cert_with_secret(
                &args.host,
                args.port,
                &args.user,
                &args.key_secret_id,
                &args.cert_secret_id,
                args.passphrase_secret_id.as_deref(),
            )
            .await
        })
    }

    /// Owned-arg twin of [`connect_pubkey_sk`]. Reads the optional
    /// PIN out of the SecretStore inside the future so the FRB
    /// `wrap_async` `Send + 'static` bound holds — the resulting
    /// future captures only `String` / `Vec<u8>` by value, and the
    /// PIN bytes never round-trip back to Dart.
    pub fn connect_pubkey_sk_owned(
        args: ConnectPubkeySkOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let pin_bytes = match args.pin_secret_id.as_deref() {
                Some(id) => crate::app::instance().secrets.get(id),
                None => None,
            };
            let pin: Option<String> = match pin_bytes.as_ref() {
                Some(b) => Some(
                    std::str::from_utf8(b)
                        .map_err(|e| Error::Auth(format!("pin not utf-8: {e}")))?
                        .to_owned(),
                ),
                None => None,
            };
            Self::connect_pubkey_sk(
                &args.host,
                args.port,
                &args.user,
                &args.public_openssh,
                &args.credential_id,
                &args.application,
                pin.as_deref(),
            )
            .await
        })
    }

    /// Owned-arg twin of [`connect_pubkey_sk_cert`]. Resolves the
    /// cert blob + optional PIN from the SecretStore inside the
    /// future so the FRB `wrap_async` `Send + 'static` bound holds.
    /// The cert blob is staged by the Dart-side `prepare_auth`
    /// composer under `key.cert.<key_id>` — same shape as the
    /// software cert path — and dropped after the connect attempt
    /// settles.
    pub fn connect_pubkey_sk_cert_owned(
        args: ConnectPubkeySkCertOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let store = &crate::app::instance().secrets;
            let cert_bytes = store
                .get(&args.cert_secret_id)
                .ok_or_else(|| Error::Auth(format!("no cached cert '{}'", args.cert_secret_id)))?;
            let pin_bytes = args.pin_secret_id.as_deref().and_then(|id| store.get(id));
            let pin: Option<String> = match pin_bytes.as_ref() {
                Some(b) => Some(
                    std::str::from_utf8(b)
                        .map_err(|e| Error::Auth(format!("pin not utf-8: {e}")))?
                        .to_owned(),
                ),
                None => None,
            };
            Self::connect_pubkey_sk_cert(
                &args.host,
                args.port,
                ConnectPubkeySkCertArgs {
                    user: &args.user,
                    public_openssh: &args.public_openssh,
                    credential_id: &args.credential_id,
                    application: &args.application,
                    cert_bytes: &cert_bytes,
                    pin: pin.as_deref(),
                },
            )
            .await
        })
    }

    /// Connect + authenticate with a PKCS#11 hardware-token key.
    ///
    /// `public_openssh` is the `id_*.pub` body captured at import;
    /// we re-parse it here to recover the SSH `PublicKey` russh's
    /// `authenticate_publickey_with` needs. `module_path` +
    /// `token_serial` + `cka_id` identify the on-device private key
    /// the signer reaches for on every userauth signature.
    ///
    /// Signing routes through [`crate::ssh::pkcs11_signer::Pkcs11Signer`],
    /// which drives `lfs_os_security::pkcs11::sign_with_pkcs11` on
    /// every challenge. Private key material lives on the token —
    /// never on the heap.
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    pub async fn connect_pubkey_pkcs11(args: ConnectPubkeyPkcs11Args<'_>) -> Result<Self, Error> {
        let (mut handle, forward_rx) = open_handle_for_session(args.host, args.port).await?;
        let parsed_pub = ssh_key::PublicKey::from_openssh(args.public_openssh.trim())
            .map_err(|e| Error::KeyParse(format!("pkcs11 pubkey: {e}")))?;
        // Validate the key_type tag parses cleanly before reaching
        // the russh authenticate call. The Signer reads the SSH
        // algorithm string off the same tag at sign time, so a bad
        // input here fails loudly rather than surfacing as a
        // mid-handshake mismatch.
        let _ = crate::ssh::pkcs11_signer::algorithm_for_key_type(args.key_type)?;
        // RSA defaults to SHA-512 — server-side OpenSSH ≥ 8.2 negotiates
        // `rsa-sha2-512` ahead of the deprecated SHA-1 `ssh-rsa`. ECDSA
        // / Ed25519 paths leave hash_alg = None and let russh's wire
        // negotiation pick.
        let hash_alg = if args.key_type == "rsa" {
            Some(HashAlg::Sha512)
        } else {
            None
        };
        let mut signer = crate::ssh::pkcs11_signer::Pkcs11Signer {
            module_path: args.module_path.to_string(),
            token_serial: args.token_serial.to_string(),
            cka_id: args.cka_id.to_vec(),
            algorithm: crate::ssh::pkcs11_signer::ssh_algorithm_string(args.key_type).to_string(),
            pin: args.pin.map(|p| Zeroizing::new(p.to_string())),
        };
        let auth_result = handle
            .authenticate_publickey_with(args.user, parsed_pub, hash_alg, &mut signer)
            .await
            .map_err(|e| Error::Auth(format!("{e}")))?;
        check_auth_result(auth_result)?;
        Ok(Session::from_handle(handle, forward_rx))
    }

    /// Owned-arg twin of [`connect_pubkey_pkcs11`]. Mirrors the FIDO2
    /// `_owned` shape — resolves the optional PIN out of the
    /// SecretStore inside the future so the caller hands only Send
    /// owned arguments across the FRB worker boundary.
    #[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
    pub fn connect_pubkey_pkcs11_owned(
        args: ConnectPubkeyPkcs11OwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let pin_bytes = match args.pin_secret_id.as_deref() {
                Some(id) => crate::app::instance().secrets.get(id),
                None => None,
            };
            let pin: Option<String> = match pin_bytes.as_ref() {
                Some(b) => Some(
                    std::str::from_utf8(b)
                        .map_err(|e| Error::Auth(format!("pin not utf-8: {e}")))?
                        .to_owned(),
                ),
                None => None,
            };
            Self::connect_pubkey_pkcs11(ConnectPubkeyPkcs11Args {
                host: &args.host,
                port: args.port,
                user: &args.user,
                public_openssh: &args.public_openssh,
                module_path: &args.module_path,
                token_serial: &args.token_serial,
                cka_id: &args.cka_id,
                key_type: &args.key_type,
                pin: pin.as_deref(),
            })
            .await
        })
    }

    /// Mobile stub — PKCS#11 isn't reachable on Android / iOS, so the
    /// owned-arg twin returns a typed unsupported error. The
    /// dispatcher in `connection::mod` calls this on any cfg combo
    /// where the desktop implementation isn't built.
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    pub fn connect_pubkey_pkcs11_owned(
        _args: ConnectPubkeyPkcs11OwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            Err(Error::Unsupported(
                "pkcs11 hardware tokens are not available on this platform".into(),
            ))
        })
    }

    /// Connect + authenticate with an Apple Secure Enclave-bound SSH
    /// key. `public_openssh` is the `id_*.pub` body captured at
    /// create time (always `ecdsa-sha2-nistp256` for SE-bound keys);
    /// `application_tag` is the opaque blob the Keychain
    /// `SecItemCopyMatching` matches on to resolve the on-chip
    /// private half.
    ///
    /// Signing routes through [`crate::ssh::enclave_signer::EnclaveSigner`],
    /// which drives `lfs_os_security::apple_se_ssh::sign` on every
    /// challenge. The OS fires its biometric / passcode prompt at
    /// the `SecKeyCreateSignature` boundary per the ACL flags
    /// chosen at create time. Private key bytes never leave the
    /// chip.
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    pub fn connect_pubkey_enclave_owned(
        args: ConnectPubkeyEnclaveOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let (mut handle, forward_rx) = open_handle_for_session(&args.host, args.port).await?;
            let parsed_pub = ssh_key::PublicKey::from_openssh(args.public_openssh.trim())
                .map_err(|e| Error::KeyParse(format!("enclave pubkey: {e}")))?;
            let mut signer = crate::ssh::enclave_signer::EnclaveSigner {
                application_tag: args.application_tag,
                label: String::new(),
            };
            // ECDSA path leaves `hash_alg = None` — russh's wire
            // negotiation lands on `ecdsa-sha2-nistp256` (the only
            // shape SE supports). russh ignores hash_alg for ECDSA.
            let auth_result = handle
                .authenticate_publickey_with(&args.user, parsed_pub, None, &mut signer)
                .await
                .map_err(|e| Error::Auth(format!("{e}")))?;
            check_auth_result(auth_result)?;
            Ok(Session::from_handle(handle, forward_rx))
        })
    }

    /// Non-Apple platforms — surface a typed unsupported error so the
    /// `ConnectAuthRef::PubkeyEnclave` dispatcher in
    /// `connection::mod` stays cfg-clean. The DB row's
    /// `backend = 'enclave'` discriminator is never created on
    /// non-Apple builds (the wizard hides the toolbar action), so
    /// this arm only fires on cross-device `.lfs` imports the
    /// runtime then refuses with the documented "key cannot leave
    /// this Mac" reason.
    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    pub fn connect_pubkey_enclave_owned(
        _args: ConnectPubkeyEnclaveOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            Err(Error::Unsupported(
                "Apple Secure Enclave keys are available on macOS / iOS only".into(),
            ))
        })
    }

    /// Connect + authenticate with a Windows Hello (NCrypt) SSH key.
    /// Hello fires its PIN / fingerprint / face prompt inside the
    /// `NCryptSignHash` round trip per the UI policy chosen at
    /// create time. Private key bytes live in the TPM (or PCP
    /// software KSP fallback) and never leave.
    #[cfg(target_os = "windows")]
    pub fn connect_pubkey_hello_owned(
        args: ConnectPubkeyHelloOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let (mut handle, forward_rx) = open_handle_for_session(&args.host, args.port).await?;
            let parsed_pub = ssh_key::PublicKey::from_openssh(args.public_openssh.trim())
                .map_err(|e| Error::KeyParse(format!("hello pubkey: {e}")))?;
            let algo = crate::ssh::hello_signer::HelloAlgo::from_key_type(&args.key_type)?;
            let mut signer = crate::ssh::hello_signer::HelloSigner {
                credential_name: args.credential_name,
                algo,
                label: String::new(),
            };
            // RSA SSH userauth selects the hash algorithm at the
            // outer russh layer via `Some(HashAlg::Sha256/Sha512)`;
            // ECDSA passes `None`. We default RSA-2048 to SHA-512.
            let hash_alg = match algo {
                crate::ssh::hello_signer::HelloAlgo::Rsa2048 => Some(HashAlg::Sha512),
                _ => None,
            };
            let auth_result = handle
                .authenticate_publickey_with(&args.user, parsed_pub, hash_alg, &mut signer)
                .await
                .map_err(|e| Error::Auth(format!("{e}")))?;
            check_auth_result(auth_result)?;
            Ok(Session::from_handle(handle, forward_rx))
        })
    }

    /// Non-Windows platforms — surface a typed unsupported error so
    /// the `ConnectAuthRef::PubkeyHello` dispatcher stays cfg-clean.
    #[cfg(not(target_os = "windows"))]
    pub fn connect_pubkey_hello_owned(
        _args: ConnectPubkeyHelloOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            Err(Error::Unsupported(
                "Windows Hello SSH keys are available on Windows only".into(),
            ))
        })
    }

    /// Connect + authenticate with a TPM 2.0-bound SSH key.
    ///
    /// `provider` discriminates between the Linux ESAPI driver
    /// (`"tss-esapi"`, signs via `tss-esapi`-issued `TPM2_Sign`)
    /// and the Windows PCP silent variant (`"cng-pcp"`, signs via
    /// `NCryptSignHash` without firing any OS-level prompt). The
    /// signer routes through [`crate::ssh::tpm_signer::TpmSigner`].
    ///
    /// Private key bytes live in the TPM (Linux) or under the
    /// PCP-managed keystore (Windows); the host never sees them.
    /// PIN-bound keys read their PIN from the SecretStore entry
    /// staged by the Dart caller before dispatch.
    #[cfg(any(target_os = "linux", target_os = "windows"))]
    pub fn connect_pubkey_tpm_owned(
        args: ConnectPubkeyTpmOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let (mut handle, forward_rx) = open_handle_for_session(&args.host, args.port).await?;
            let parsed_pub = ssh_key::PublicKey::from_openssh(args.public_openssh.trim())
                .map_err(|e| Error::KeyParse(format!("tpm pubkey: {e}")))?;
            let algo = crate::ssh::tpm_signer::TpmAlgo::from_key_type(&args.key_type)?;
            let provider = match args.provider.as_str() {
                "tss-esapi" => {
                    let blob = args
                        .blob
                        .ok_or_else(|| Error::Auth("tss-esapi TPM row missing blob".into()))?;
                    crate::ssh::tpm_signer::TpmProvider::TssEsapiBlob(blob)
                }
                "cng-pcp" => {
                    let name = args.cng_key_name.ok_or_else(|| {
                        Error::Auth("cng-pcp TPM row missing cng_key_name".into())
                    })?;
                    crate::ssh::tpm_signer::TpmProvider::CngPcpSilent(name)
                }
                other => {
                    return Err(Error::Auth(format!("unknown TPM provider {other:?}")));
                }
            };
            // PIN resolution: lift the bytes out of the SecretStore
            // once and hand them to the signer; the store entry is a
            // transient id the caller drops after the dial settles.
            // `SecretStore::get` returns the bytes in `Zeroizing<Vec<u8>>`
            // — keep the wrapper so the signer's PIN is wiped on drop.
            let pin = match args.pin_secret_id {
                Some(id) => crate::app::instance().secrets.get(&id),
                None => None,
            };
            let mut signer = crate::ssh::tpm_signer::TpmSigner {
                provider,
                algo,
                pin,
                label: String::new(),
            };
            let hash_alg = match algo {
                crate::ssh::tpm_signer::TpmAlgo::Rsa2048 => Some(HashAlg::Sha256),
                _ => None,
            };
            let auth_result = handle
                .authenticate_publickey_with(&args.user, parsed_pub, hash_alg, &mut signer)
                .await
                .map_err(|e| Error::Auth(format!("{e}")))?;
            check_auth_result(auth_result)?;
            Ok(Session::from_handle(handle, forward_rx))
        })
    }

    /// Non-{linux,windows} platforms — surface a typed unsupported
    /// error so the `ConnectAuthRef::PubkeyTpm` dispatcher stays
    /// cfg-clean. Apple platforms route the wizard at the Secure
    /// Enclave path instead.
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    pub fn connect_pubkey_tpm_owned(
        _args: ConnectPubkeyTpmOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            Err(Error::Unsupported(
                "TPM 2.0 SSH keys are available on Linux + Windows only".into(),
            ))
        })
    }

    /// Connect + authenticate with an Android Hardware Keystore /
    /// StrongBox-bound SSH key. The signer fires
    /// `BiometricPrompt.CryptoObject` inside the per-message sign
    /// hop per the auth requirement set at create time
    /// (`setUserAuthenticationRequired(true)` +
    /// `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)`).
    /// Private key bytes live in the AndroidKeyStore (TEE or
    /// StrongBox) and never leave the chip.
    #[cfg(target_os = "android")]
    pub fn connect_pubkey_keystore_owned(
        args: ConnectPubkeyKeystoreOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let (mut handle, forward_rx) = open_handle_for_session(&args.host, args.port).await?;
            let parsed_pub = ssh_key::PublicKey::from_openssh(args.public_openssh.trim())
                .map_err(|e| Error::KeyParse(format!("keystore pubkey: {e}")))?;
            let algo = crate::ssh::keystore_signer::KeystoreAlgo::from_key_type(&args.key_type)?;
            let mut signer = crate::ssh::keystore_signer::KeystoreSigner {
                keystore_alias: args.keystore_alias,
                algo,
                label: String::new(),
            };
            // RSA SSH userauth selects the hash algorithm at the
            // outer russh layer via `Some(HashAlg::Sha256/Sha512)`;
            // ECDSA / Ed25519 pass `None`. Default RSA-2048 to
            // SHA-256 — AndroidKeyStore RSA keys are configured for
            // `DIGEST_SHA256` only at create time.
            let hash_alg = match algo {
                crate::ssh::keystore_signer::KeystoreAlgo::Rsa2048 => Some(HashAlg::Sha256),
                _ => None,
            };
            let auth_result = handle
                .authenticate_publickey_with(&args.user, parsed_pub, hash_alg, &mut signer)
                .await
                .map_err(|e| Error::Auth(format!("{e}")))?;
            check_auth_result(auth_result)?;
            Ok(Session::from_handle(handle, forward_rx))
        })
    }

    /// Non-Android platforms — surface a typed unsupported error so
    /// the `ConnectAuthRef::PubkeyKeystore` dispatcher stays
    /// cfg-clean. The AndroidKeyStore is intrinsically a per-device
    /// surface; cross-device the key has no meaning.
    #[cfg(not(target_os = "android"))]
    pub fn connect_pubkey_keystore_owned(
        _args: ConnectPubkeyKeystoreOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            Err(Error::Unsupported(
                "Android Hardware Keystore SSH keys are available on Android only".into(),
            ))
        })
    }

    /// Owned-arg twin of [`connect_agent`]. Bridges through
    /// `spawn_blocking + Handle::block_on` because the russh agent
    /// client holds a non-Send dyn trait object that cannot ride
    /// inside an FRB `wrap_async` future. Mirrors the workaround
    /// the legacy FRB `ssh_connect_agent` already uses, so the
    /// connection actor can expose a uniform `_owned` family.
    pub fn connect_agent_owned(
        host: String,
        port: u16,
        user: String,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let handle = tokio::runtime::Handle::current();
            tokio::task::spawn_blocking(move || {
                handle.block_on(Self::connect_agent(&host, port, &user))
            })
            .await
            .map_err(|e| Error::Auth(format!("agent task: {e}")))?
        })
    }

    // ---- ProxyJump + secret-store-backed connects ----------------
    // The `_via_proxy_with_secret_owned_arc` family takes an
    // `Arc<Session>` for the parent (so the returned future owns
    // its parent reference and stays `'static` instead of borrowing
    // for an unspecified lifetime) and a SecretStore id for every
    // credential ingredient. Returned as
    // `Pin<Box<dyn Future + Send + 'static>>` so the connection
    // actor's dispatch path threads through FRB `wrap_async`
    // without HRTB inference reaching into the deeper `&str`
    // borrow plumbing.

    /// Password auth tunnelled through a ProxyJump parent, resolving
    /// the password from the SecretStore. See module docs for the
    /// boxed-future rationale.
    pub fn connect_password_via_proxy_with_secret_owned(
        parent: Arc<Session>,
        host: String,
        port: u16,
        user: String,
        secret_id: String,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let bytes = crate::app::instance()
                .secrets
                .get(&secret_id)
                .ok_or_else(|| Error::Auth(format!("no cached secret '{secret_id}'")))?;
            let pwd = std::str::from_utf8(&bytes)
                .map_err(|e| Error::Auth(format!("password not utf-8: {e}")))?;
            Self::connect_password_via_proxy(&parent, &host, port, &user, pwd).await
        })
    }

    /// Pubkey auth tunnelled through a ProxyJump parent, resolving
    /// key + optional passphrase from the SecretStore.
    pub fn connect_pubkey_via_proxy_with_secret_owned(
        parent: Arc<Session>,
        host: String,
        port: u16,
        user: String,
        key_secret_id: String,
        passphrase_secret_id: Option<String>,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let store = &crate::app::instance().secrets;
            let key_bytes = store
                .get(&key_secret_id)
                .ok_or_else(|| Error::Auth(format!("no cached key '{key_secret_id}'")))?;
            let pass_bytes = passphrase_secret_id.as_deref().and_then(|id| store.get(id));
            let passphrase = match pass_bytes.as_ref() {
                Some(b) => Some(
                    std::str::from_utf8(b)
                        .map_err(|e| Error::Auth(format!("passphrase not utf-8: {e}")))?,
                ),
                None => None,
            };
            Self::connect_pubkey_via_proxy(&parent, &host, port, &user, &key_bytes, passphrase)
                .await
        })
    }

    /// OpenSSH-cert auth tunnelled through a ProxyJump parent.
    pub fn connect_pubkey_cert_via_proxy_with_secret_owned(
        parent: Arc<Session>,
        args: ConnectPubkeyCertOwnedArgs,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let store = &crate::app::instance().secrets;
            let key_bytes = store
                .get(&args.key_secret_id)
                .ok_or_else(|| Error::Auth(format!("no cached key '{}'", args.key_secret_id)))?;
            let cert_bytes = store
                .get(&args.cert_secret_id)
                .ok_or_else(|| Error::Auth(format!("no cached cert '{}'", args.cert_secret_id)))?;
            let pass_bytes = args
                .passphrase_secret_id
                .as_deref()
                .and_then(|id| store.get(id));
            let passphrase = match pass_bytes.as_ref() {
                Some(b) => Some(
                    std::str::from_utf8(b)
                        .map_err(|e| Error::Auth(format!("passphrase not utf-8: {e}")))?,
                ),
                None => None,
            };
            Self::connect_pubkey_cert_via_proxy(
                &parent,
                &args.host,
                args.port,
                &args.user,
                &key_bytes,
                passphrase,
                &cert_bytes,
            )
            .await
        })
    }

    /// Agent auth tunnelled through a ProxyJump parent. Bridges
    /// through `spawn_blocking + Handle::block_on` for the same
    /// non-Send agent-client reason as [`connect_agent_owned`];
    /// the parent `Arc<Session>` cloned into the blocking task so
    /// the spawn boundary doesn't lose the reference.
    pub fn connect_agent_via_proxy_owned(
        parent: Arc<Session>,
        host: String,
        port: u16,
        user: String,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, Error>> + Send>> {
        Box::pin(async move {
            let handle = tokio::runtime::Handle::current();
            tokio::task::spawn_blocking(move || {
                handle.block_on(Self::connect_agent_via_proxy(&parent, &host, port, &user))
            })
            .await
            .map_err(|e| Error::Auth(format!("agent task: {e}")))?
        })
    }

    /// SSH-agent auth tunnelled through a ProxyJump parent. Mirrors
    /// the non-proxy `connect_agent` path: spawn_blocking + Handle
    /// for the agent client whose per-call futures are not Send,
    /// then run authenticate over the proxy-tunnelled handle.
    pub async fn connect_agent_via_proxy(
        parent: &Session,
        host: &str,
        port: u16,
        user: &str,
    ) -> Result<Self, Error> {
        connect_via_agent_proxy(parent, host.to_owned(), port, user.to_owned()).await
    }
}
