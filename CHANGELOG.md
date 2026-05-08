# Changelog

All notable changes are tracked here. The project follows
[Semantic Versioning](https://semver.org) — major bumps for
breaking on-disk format changes, minor for new features that
ride alongside the existing tier ladder, patch for fixes.

The latest stable build is built from `main`; the active
development branch lives on `dev`. Per-release notes appear in
their corresponding GitHub release tag.

## Unreleased

### Security

- Persisted-format hardening sweep: magic + version envelopes on
  `.tier-transition-pending` and `.wipe-pending`; `O_NOFOLLOW`
  on every read of a credential / KDF / verifier artefact;
  `O_NOFOLLOW | O_EXCL` on the atomic-write tmp open; parent
  directories under `app-support` chmod 0700 from creation;
  SQLCipher DB + WAL / SHM sidecars hardened to 0600 after
  bootstrap.
- Plain-ZIP `.lfs` export retired UI-side: the export password
  dialog now rejects empty passwords. Plain-ZIP carries no
  integrity tag; an unencrypted export shipped an
  unauthenticated archive that readers couldn't tamper-detect.
  Import still reads plain ZIPs from older installs (backward
  compatible).
- `credentials.kdf` header (magic + version + algo + params +
  salt) now binds into the `credentials.verify` AES-GCM AAD —
  a tampered KDF header (memory_kib bumped to 1 GiB to DoS-lock
  the user, iterations bumped beyond reason) fails verification
  before Argon2id ever runs against attacker-supplied params.
- Hardware-vault on-disk envelopes now stamp a common header
  (`LFHV` + version + platform_id) so a cross-platform file
  copy / version downgrade lands on the typed `Corrupt` path.
- Apple Keychain non-biometric writes pin
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so the
  entry never syncs to iCloud Keychain.
- Windows hw-vault NCryptCreatePersistedKey now sets
  `NCRYPT_EXPORT_POLICY_PROPERTY = 0` before
  `NCryptFinalizeKey` so the software-KSP fallback path
  enforces non-exportability.
- Android Keystore key generation: builder calls
  `setInvalidatedByBiometricEnrollment(true)` on biometric keys
  + `setUnlockedDeviceRequired(true)` unconditionally (API 28+).
- SSH connection drops legacy `ssh-rsa` (SHA-1 host-key) +
  `hmac-sha1` MACs from the russh `Preferred` set.
- T2 hardware-vault unlock now mirrors the
  `unlock_keychain_with_password` rate-limit shape so a
  programmatic FRB caller hits the same exponential schedule
  the other tier limiters use.
- Persisted rate-limit signing key derives via HKDF-SHA-256
  with a non-empty per-purpose salt (RFC 5869 §3.1).
- `subtle::ConstantTimeEq` replaces hand-rolled XOR loops in
  Apple PIN-HMAC compare; `Zeroizing` wraps the recorder
  AES-256 key end-to-end.
- TOFU host-key dialog flags non-ASCII hostnames with an
  IDN homograph warning.
- Snippet-command copy routes through `SecureClipboard` so
  inline credentials don't leak into OS-level cloud-sync rings
  (Windows 10+ history, macOS Universal Clipboard, iOS Handoff,
  Android 13+ history).
- `bidi`/`Trojan-Source` codepoint redaction across log /
  hostname / file-row rendering surfaces.

### Reliability

- Drop guards on `RecorderQueue::WorkerHandle`,
  `ListenerHandle` (port-forward + SOCKS5), and Windows hw-vault
  NCRYPT handles. Tokio `watch` shutdown signal threaded
  through accept loops so a port-forward stop closes the
  listener cleanly without orphaning a per-accept worker.
- Connect-driver failure path lands on `app_log_warn!` instead
  of Info; configstore ticker logs the first consecutive
  disk-write failure (edge-trigger, no spam during a slider
  drag against a wedged FS).
- `pump` (port-forward bidirectional copy) now surfaces
  non-EOF I/O errors via `StatusReporter` so a real fault
  reaches the rule-status panel rather than collapsing to a
  silent disconnect.

### Performance

- `workspace_view` rebuilds subscribe to the derived
  `connectionSummaryProvider` instead of a comma-joined
  `${id}:${state}` string, dropping one allocation per
  `Connection` mutation.
- New `db_ssh_keys_replace_all` FRB endpoint replaces
  `KeysNotifier.saveAll`'s 2N hop loop with a single
  transactional call.

### Errors

- Typed FRB error envelope (`{kind, detail}`) covers every
  `lfs_frb::api::*` failure path; Dart router switches on
  `kind` instead of substring-matching English error text.
- `secrets_take` / `secrets_get` return `Option<Vec<u8>>`
  so callers can distinguish missing slot from intentionally
  empty bytes.

### Migration framework

- `read_archive_to_pending` enforces a 256 MiB on-disk cap
  + a 1 GiB total-uncompressed cap (zip-bomb defence).
- `bootstrap_schema` stamps `user_version` only on a fresh
  DB so a v1 build opening a v2 file no longer silently
  downgrades the version.
