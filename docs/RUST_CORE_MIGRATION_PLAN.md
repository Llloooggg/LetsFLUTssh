# Rust core migration plan

Live tracker. Internal planning doc, not user-facing. Backend in
Rust: **~95%**. The remaining tail is **Phase 6** below.

The Rust side follows a **ports-and-adapters (hexagonal)** layout:
a pure-Rust `lfs_core` crate with no frontend awareness, plus a
thin `lfs_frb` adapter that exposes the core through
[`flutter_rust_bridge`](https://github.com/fzyzcjy/flutter_rust_bridge).
Future adapters (`lfs_tauri`, `lfs_cli`) plug into the same core
without touching its internals — so a Flutter→Tauri pivot, a
headless CLI, or a wasm/web frontend stays a small adapter
rewrite, not a core rewrite.

This file is the single source of truth for the migration. Two
prior trackers (`RUST_MIGRATION_NEXT_PLAN.md`,
`RUST_MIGRATION_REMAINING.md`) folded into this one — every
locked architectural decision and every still-open item lives
below.

---

## North star

**"Flutter renders, Rust thinks."** Every state machine, every
byte of business logic, every persisted derivation, every secret
ever typed by the user lives in `lfs_core`. Dart shrinks to:

- widgets, dialogs, theme, l10n
- Riverpod subscribers over typed bus events
- thin platform-plugin proxies (and a roadmap to retire them)

Litmus test for any review: if the answer to *"what does Dart
need to know about this?"* is anything beyond *"what to draw on
screen right now"*, the design is wrong.

Three priorities, in order: **safety, best-practice, speed**.
Every arc weighs against those — never "shipped because Dart
was easier".

---

## Why Rust

`dartssh2` 2.17.1 was the original bottleneck for SSH
certificates, FIDO2-sk keys, and `$SSH_AUTH_SOCK` agent client —
none of which can be added without forking a large pure-Dart
codebase. Moving the SSH/crypto core to Rust solves the feature
gaps in one architectural shift and brings memory safety to the
highest-risk code path (parsing untrusted server bytes, handling
key material).

We picked **`russh` (pure Rust, async, tokio-based)** over
**libssh / libssh2 (C, FFI)**:

|                        | russh + FRB                            | libssh + FFI                      |
|------------------------|----------------------------------------|-----------------------------------|
| Memory safety          | Rust — safe                            | C — historical CVE pattern        |
| Bindings               | FRB auto-generates from Rust signatures| ~200 funcs hand-bound             |
| Async                  | tokio native, FRB → Future / Stream    | blocking, requires Isolate workers|
| Crypto crates          | RustCrypto / ring — modern, audited    | lib-internal                      |
| Cross-compile          | `cargo --target`                       | autoconf / cmake mess             |
| Maturity               | ~5 yrs, GitButler, Pijul               | ~25 yrs, FileZilla, Bitvise       |

The `Native Over Dart When Better` rule (`docs/AGENT_RULES.md`)
explicitly authorises this when zero-install holds (rung 1 of
the 3-rung ladder — bundle native blobs, end-user installs
nothing).

---

## Boundary contract

The FRB boundary lives **only** in `lfs_frb`. `lfs_core` is
frontend-agnostic — no `flutter_rust_bridge` import, no FRB
attributes, no Dart-shaped types. Everything crossing the bridge
passes through `lfs_frb`, which delegates to `lfs_core`.

Rule of thumb in the adapter:

- **Plain data** (host, port, user, key bytes, opaque tokens) —
  pass by value.
- **Long-lived handles** (active session, channel, sftp client) —
  `lfs_core` returns an opaque struct; `lfs_frb` registers it in a
  handle registry and exposes a numeric ID to Dart. The Dart side
  never sees the inner Rust state.
- **Streams** (terminal stdout, port-forward connection events,
  sftp progress) — `lfs_core` produces a `tokio::sync::mpsc`;
  `lfs_frb` wraps it in an FRB `Stream<T>`.
- **Async** — every transport call is `async fn` in `lfs_core`.
  FRB codegen maps it to a Dart `Future<T>`.
- **Errors** — `lfs_core` returns `Result<T, lfs_core::Error>` with
  a typed enum (`NoRoute`, `AuthFailed`, `HostKeyMismatch`, …).
  `lfs_frb` converts to a Dart-friendly variant.

**Discipline**: the temptation will be to short-circuit and put a
tiny FRB-specific concern into `lfs_core`. Don't. If `lfs_core`
ever depends on `flutter_rust_bridge` or `tauri`, the hexagonal
property is broken. CI enforces this via `cargo tree -p lfs_core`
+ a deny-list assertion on the dependency graph.

---

## Workspace layout

```
rust/
├── Cargo.toml                    # workspace root
├── crates/
│   ├── lfs_core/                 # pure Rust, forbid(unsafe_code)
│   │   ├── ssh/                  # russh wrappers (transport, channels)
│   │   ├── sftp/                 # russh-sftp wrappers + recursive walks
│   │   ├── forward/              # -L / -D / -R drivers
│   │   ├── crypto/               # AES-GCM, HKDF, Argon2id, Ed25519, SHA-256
│   │   ├── keys/                 # PPK, OpenSSH PEM, fingerprints
│   │   ├── archive/              # .lfs encrypt/decrypt/apply, QR codec
│   │   ├── connection/           # connection registry actor
│   │   ├── transfer/             # queue + worker pool
│   │   ├── recorder/             # ring buffer + per-frame encrypt
│   │   ├── auto_lock/            # lifecycle state machine
│   │   ├── sessions/             # registry + folder cascade
│   │   ├── known_hosts/          # parser + TOFU policy + prompt registry
│   │   ├── update_orchestrator/  # GitHub release parse + signed manifest
│   │   ├── ssh_config/           # OpenSSH config grammar
│   │   ├── log_sanitize/         # PEM / IP / paths redaction
│   │   ├── security/             # tier machine, capabilities, rate-limit
│   │   ├── config/               # AppConfig schema mirror
│   │   ├── config_store/         # debounce + atomic write actor
│   │   ├── platform/             # per-OS wrappers
│   │   │   ├── linux/            # tpm, fprintd
│   │   │   ├── macos/            # process helper
│   │   │   └── windows/          # path hardening, winbio
│   │   ├── format/               # size, duration, timestamp formatters
│   │   ├── path/                 # write_bytes_atomic, harden_file_perms
│   │   └── bus/                  # tokio broadcast Cmd/Evt bus
│   └── lfs_frb/                  # FRB adapter, cdylib + staticlib
│       ├── api/                  # one file per FRB-exposed module
│       └── frb_generated.rs      # generated; do not edit
├── deny.toml                     # cargo-deny: advisories + licenses + bans
└── .gitignore
```

`lfs_core` MUST NOT depend on `flutter_rust_bridge` or any
frontend crate. Verified by CI.

---

## Status snapshot (April 2026)

| Area | Status | Rust module |
|---|---|---|
| Crypto (AES-GCM / HKDF / Argon2id / Ed25519 / SHA-256) | DONE | `lfs_core::crypto` |
| KDF + master-password verify | DONE | `lfs_core::security::master_password` |
| SSH transport (russh, ProxyJump, SOCKS5, agent, certs) | DONE | `lfs_core::ssh` |
| SFTP byte-level + streaming + recursive walks (leaf ops) | DONE | `lfs_core::sftp` |
| Port-forward driver (`-L` / `-D` / `-R`) | DONE | `lfs_core::forward` |
| Transfer queue + worker pool | DONE | `lfs_core::transfer` |
| Recorder ring buffer + per-frame AES-GCM | DONE | `lfs_core::recorder` |
| Connection lifecycle actor + bus events | DONE | `lfs_core::connection` |
| Auto-lock state machine | DONE | `lfs_core::auto_lock` |
| Session registry + folder cascade + dedup-import | DONE | `lfs_core::sessions` |
| `.lfs` archive encrypt / decrypt / apply | DONE | `lfs_core::archive` |
| QR codec (encode + decode + handle registry) | DONE | `lfs_core::qr_codec` |
| Known-hosts + TOFU prompt protocol | DONE | `lfs_core::known_hosts` |
| Update orchestrator (GitHub parse + signed-manifest verify) | DONE | `lfs_core::update_orchestrator` |
| OpenSSH config grammar (parse + glob + comment + tokenise) | DONE | `lfs_core::ssh_config` |
| Log sanitiser (PEM / IP / `user@host` / paths) | DONE | `lfs_core::log_sanitize` |
| TPM seal / unseal (Linux subprocess) | DONE — non-ideal, see [NI-1](#ni-1--linux-tpm2-via-subprocess-shell-out) | `lfs_core::platform::linux::tpm` |
| Hardware-vault disk-blob format + auth resolver | DONE | `lfs_core::security::hardware_tier_vault` |
| Capabilities orchestrator + cache + prompt registries | DONE | `lfs_core::security::capabilities_orchestrator` |
| Tier state machine (per-tier sub-machines, prompt protocol) | DONE | `lfs_core::security::tier_machine` |
| Wipe catalogue + crash markers | DONE | `lfs_core::security::wipe` |
| Persisted rate-limit (HMAC-authenticated frame) | DONE | `lfs_core::security::persisted_rate_limit` |
| `app_config` schema mirror | DONE | `lfs_core::config` |
| Config store actor (debounce + atomic write + bus events) | DONE | `lfs_core::config_store` |
| Tail-end Dart retire — Phase 6 Tier 1 (host_info, session_tree, single_instance) | DONE | `lfs_core::host_info`, `lfs_core::session_tree`, `lfs_os_security::single_instance` |
| Tail-end Dart retire — Phase 6 Tier 2 (clipboard, session_lock, backup_excl, fprintd, LocalFS, ssh_config Include, SFTP recursive) | DONE | `lfs_os_security::*`, `lfs_core::fs::local`, `lfs_core::ssh_config`, `lfs_core::sftp::recursive_walk` |
| Tail-end Dart retire — Phase 6 Tier 3 desktop + Apple (secure key storage, biometric vault, biometric auth, wipe service) | DONE | `lfs_os_security::secure_key_storage`, `lfs_os_security::biometric_auth`, `lfs_core::security::wipe`, `lfs_core::wipe_keychain` |
| **Tail-end Dart retire — Phase 6 Tier 3 Android JNI** | **PLANNED** | direct JNI to platform Java APIs (no Kotlin shim); gated on Android dev-loop only — see [Tier 3 Android JNI bridge ledger](#tier-3--android-jni-bridge-ledger-planned-approach) |
| **Tail-end Dart retire — Phase 6 Tier 4 native ports** | **OPT-IN** | per-item Three Pillars evaluation, see Tier 4 § |
| **Non-ideal items (TPM2 subprocess, Apple/Windows verification, session_lock_listener mac/win)** | **PLANNED** | see [Non-ideal items § NI-1..3](#non-ideal-items--planned-to-ideal) |

---

## Closed phases — history

The path taken to get here, abbreviated:

- **Phase 1 — Workspace bring-up + SSH transport.** Cargo
  workspace at `rust/`, `flutter_rust_bridge_codegen` integrated
  via cargokit. `lfs_core` ships SSH (russh + russh-keys), SFTP
  byte-level + streaming, port forwards (`-L` / `-D` / `-R`),
  ProxyJump, ssh-agent client, SSH certificates, FIDO2-sk via
  agent. `lfs_frb` exposes opaque session / shell / channel /
  sftp / forward types; FRB stream sinks deliver shell events to
  Dart. `Dart-side `SshTransport` abstraction → `Dartssh2Transport`
  + `RustTransport` factory; `kUseRustSshTransport` ramped from
  experimental flag to default-on. `dartssh2` removed from
  `pubspec.yaml`. Deferred: legacy PEM PKCS#1/PKCS#8 (blocked on
  upstream `pkcs8 0.11.0-rc.11` + `pkcs5 0.8.0` mismatch);
  direct CTAP2 without agent (covered by agent path).

- **Phase 2 — Crypto envelopes.** AES-GCM, HKDF, Ed25519,
  Argon2id, SHA-256, PPK codec all moved Rust-side. Wire
  formats byte-identical to the legacy `pointycastle` /
  `pinenacl` envelopes — existing `credentials.verify`, `.lfs`,
  and `.lfsr` files round-trip without migration. `pointycastle`
  and `pinenacl` removed from `pubspec.yaml`. PPK codec
  (`PrivateKey::from_ppk`) covers v2 + v3 (Argon2id);
  `KeyFileHelper.tryReadPemKey` is now async and routes through
  Rust.

- **Phase 3 — Native plugin Rust ports.** `TpmClient`,
  `FprintdClient`, `WinBioProbe`, macOS code-signing all routed
  through `lfs_core::platform::*`. OpenSSH config grammar + log
  sanitiser + path helpers (`write_bytes_atomic`,
  `harden_file_perms`, `basename`, `is_suspicious_path`,
  `sibling_candidate`) consolidated Rust-side. Config-parser
  glob / comment-strip / keyword-value / host-pattern split
  retired their Dart copies.

- **Phase 4 — Boundary contract.** Every credential byte stays
  Rust-side: `SecretStore` actor owns the only cached plaintext;
  `Session::connect_*_with_secret` resolves IDs against the
  store inside Rust; quick-connect (no session id) keys a
  transient store entry off a fresh UUID. Plaintext does not
  cross FRB at the russh handshake. Drift retired in favour of
  `rusqlite` + SQLCipher inside `lfs_core::db`. `.lfs` archive
  composition runs entirely Rust-side via `db_export_archive`.

- **Phase 5 — Cmd/Evt bus + per-domain Rust actors.**
  `lfs_core::bus` ships typed `Command` / `Event` / `EventTopic`
  enums + a `tokio::sync::broadcast`-backed `EventBus` broker.
  Per-domain Rust actors landed (Connection / PortForward /
  TransferQueue / Recorder / AutoLock / KnownHosts / Sessions /
  Update orchestrator / Tier state machine / `.lfs` import
  handle registry). Dart classes shrunk to view subscribers
  (`StreamProvider` over bus topics + thin command dispatchers).

- **Apr-2026 grind.** `_crypto_compat.dart` deleted (~600 LOC of
  shim helpers inlined). Silent FRB-error fallbacks dropped
  across `update_service`, `download_service`, `config_store`,
  `session_provider`, `tpm_client`, `keychain_password_gate`,
  `password_rate_limiter`, `qr_codec`, `import_service`. Doc-drift
  fixed across `ARCHITECTURE.md`. `tpm_client.dart` reduced from
  491 LOC to ~180 LOC after the Dart subprocess pipeline retired.
  `probeCapabilities` Dart-mirror pipeline + dialog/prompter
  parameter cascade retired (-414 LOC). `_checkForUpdateDart`
  parse walk routed through new Rust `update_check_from_body` FRB
  call; redundant Dart helper-tests deleted (-172 LOC).

---

## Locked architectural decisions

Six load-bearing decisions that gate every remaining arc.

### Decision 1 — Rust↔Dart prompt protocol

**Locked: extend `KnownHostPromptRegistry` per-prompt-type.**

Each prompt that needs Dart UI / Dart-plugin response gets:

- `BusEvent::XxxPromptRequest { req_id, ...typed payload }`
- FRB shim `xxx_prompt_response(req_id, ...typed response)`
- Per-type `PromptRegistry<XxxRequest, XxxResponse>` actor with
  `tokio::oneshot` per request

Why: race-free single-shot resolution; compile-time typed contract
per prompt (drift impossible); plaintext window stays the same as
the existing Dart `flutter_secure_storage.read()` call; pattern
already proven in production for the russh `check_server_key`
handshake-blocking case.

Rejected: generic JSON registry (loses compile-time safety); FRB
callback type (reentrancy / deadlock risk on mutex paths, already
burned us in `connection_manager`).

### Decision 2 — Platform plugin paths (keychain / biometric / hardware vault)

**Locked: callback-up via Decision 1 for the prompt-driven paths.**

Plugins stay Dart for the *prompt-driven* surface (keychain
read / write, biometric prompt UI, per-platform hardware-vault
method-channel). Rust actor publishes `PluginRequest` event, Dart
subscriber executes the `flutter_secure_storage` / `local_auth` /
`MethodChannel` call, returns response via FRB.

**Phase 6 Tier 3 below revisits this** for direct-API
replacements: `security-framework`, `wincred`, `secret-service`,
`objc2`, `windows-rs`, `keyring-rs` — when a Rust crate covers
the plugin's surface end-to-end, the Flutter plugin retires.

Why (today): plaintext discipline window doesn't grow (credential
already lives in Dart heap during plugin call); audit perimeter
stays put (existing plugins audited a year+); existing Dart tests
for plugin paths keep working.

### Decision 3 — Subprocess infra in `lfs_core`

**Locked: subprocess driver lives in `lfs_core`, target-gated,
async exposed via `spawn_blocking` at the FRB boundary.**

Driver lives under `lfs_core::platform::<os>::*` (per-OS
namespace). Implementation uses `std::process::Command` + an
internal mpsc timeout thread because (a) the rest of the
platform code already does the same, (b) the cores are
fundamentally serial (once-per-unlock TPM,
once-per-launch macOS code-sign), (c) the FRB shim wraps every
call in `tokio::task::spawn_blocking`, so the FRB worker thread
never stalls.

`tempfile` is NOT used — drivers ship a hand-rolled RAII
`WorkDir` that zero-overwrites every file before unlink, which
the off-the-shelf `tempfile::TempDir` does not do.

Why: `lfs_core` already spawns `std::process::Command` (path
hardening on Windows, macOS auth helper, TPM driver) — subprocess
is an existing pattern. Plaintext auth bytes never cross FRB twice
(single hop into the shim, written to a 0600 file inside the RAII
work dir, passed via `file:<path>` so they never appear in
`/proc/<pid>/cmdline`).

### Decision 4 — Tier state machine actor scope

**Locked: scaffold-first + per-tier sub-machines under feature
gate.**

Sequence: typed `tier_machine` scaffold + bus events + FRB shim →
per-tier handler hooks (`try_advance` per state) → flip Dart
`SecurityInitController` to the actor incrementally, one tier
modifier at a time. Each tier sub-machine ships with its own unit
tests + integration test that drives a real bootstrap end-to-end.

Why: the security boot flow is the highest-blast-radius code in
the app. Incremental migration with feature flags lets us roll
back if a single tier regresses without dragging the rest.

### Decision 5 — App config debounce + persistence

**Locked: Rust actor owns debounce + atomic file I/O + bus event.**

`lfs_core::config_store::Store` actor owns the in-memory snapshot,
300 ms debounce, atomic write through `path::write_bytes_atomic`,
publishes `ConfigChanged` after save. Dart `ConfigNotifier` is a
thin shim: `update` calls FRB; subscribes to `ConfigChanged` for
state refresh.

Side note: the actor's `start_background_ticker` spawns a tokio
task at init, which panics from sync FRB calls without a runtime.
Guard added — `tokio::runtime::Handle::try_current()` skips the
spawn when no runtime is reachable, leaving the `OnceLock` armed
for a later runtime-equipped call. This unblocked dropping the
silent FRB fallback in `_saveAppConfigToDisk`.

Why: single source of truth for config + debounce + persistence;
bus pattern uniformity; atomic-write discipline already
centralised; lost-write window on crash (300 ms) is inherent to
debounce, equal across all variants.

### Decision 6 — Export controller estimator

**Locked: extract `compose_qr_payload` shared helper Rust-side,
estimator routes through it via typed FRB inputs.**

`lfs_core::archive::qr_export_payload::compose_qr_payload(input:
QrPayloadInput) -> Value` is the single producer used by both
the production export path (DB → typed input → helper) and the
live size estimator (Dart builds typed input via FRB → calls
helper → returns size only). Same `QrPayloadInput` struct, both
consumers.

Why: closes the recurring wire-shape drift. Already burned us
once on `encodeSessionCompact`. Plaintext exposure window doesn't
grow. Sync FRB call is fast enough (< 10 ms for 100 sessions).

---

## Phase 6 — Tail-end Dart retire

The Apr-2026 live audit (28 of 28 non-UI files in `lib/core/`,
`lib/utils/`, `lib/app/`, `lib/platform/macos/`) classified the
remaining ~9 600 LOC of `lib/core/`-and-friends into four tiers
by cost-of-move. UI surface (`lib/widgets/`, `lib/features/`,
`lib/l10n/`, `lib/theme/`, most of `lib/providers/` and
`lib/app/`) is permanent Dart — see [§ Permanent Dart
surface](#permanent-dart-surface).

### Tier 1 — Trivial wins (~730 LOC, 1–2 days)

Pure logic that already runs through `dart:ffi` to libc or against
plain data — the Rust crate is shorter than the Dart wrapper.

| File | LOC | Replaces | Crate |
|---|---|---|---|
| `core/security/secret_buffer.dart` | 215 | `dart:ffi` to libc `mlock` / `munlock` / `madvise(MADV_DONTDUMP)` | `nix` / `libc` |
| `core/security/process_hardening.dart` | 172 | `dart:ffi` to libc `prctl(PR_SET_DUMPABLE)` | `nix` / `libc` |
| `core/security/libc_loader.dart` | 30 | retires after the two above | — |
| ~~`utils/platform.dart`~~ | ~~44~~ | ~~`Platform.environment['HOME' \| 'USERPROFILE' \| 'EXTERNAL_STORAGE']`~~ | done — `lfs_core::host_info` (`home_directory()` + cfg-gated `is_mobile/is_desktop/is_macos`); Dart wrapper caches first FRB read, falls back to `dart:io Platform.isXyz` for the booleans only when FRB is not bootstrapped (mathematically identical answer — same compile-time constants tied to the same binary target — so the fallback exists for widget-test ergonomics, not as a correctness divergence) |
| ~~`core/session/session_tree.dart`~~ | ~~128~~ | ~~folder-tree builder (pure data)~~ | done — `lfs_core::session_tree` (forest builder + sort + recursive count); Dart class is now a thin FRB wrapper that re-binds the live `Session` handle to leaf nodes by id |
| ~~`core/session/session_history.dart`~~ | ~~58~~ | ~~undo/redo snapshot stack (pure data)~~ | done — `lfs_core::session_history` (per-handle bounded LIFO actor); Dart class wraps the actor handle and serialises `SessionSnapshot` ↔ JSON bytes |
| `core/single_instance/single_instance.dart` | 85 | flock-based single-instance gate | `fd-lock` |

Acceptance criteria:

- Each file's Dart-side public surface either deletes outright or
  shrinks to a thin FRB shim with no business logic.
- No `dart:ffi` imports remain in `lib/core/security/`.
- `pubspec.yaml` does not gain new deps; Rust gains `nix` (or
  `libc` if `nix` adds platform churn) + `fd-lock` + `directories`.
- Rust unit tests cover the libc paths under each target OS the
  CI exercises (Linux + macOS + Windows; Android skipped — JNI is
  Tier 4).

### Tier 2 — Pure logic + small platform consolidation (~1 580 LOC, 3–5 days)

Code that's Dart by historical inertia, not architectural need.
Most of these have a direct Rust crate replacement.

| File | LOC | Replaces / consolidates | Path |
|---|---|---|---|
| ~~`core/security/secure_clipboard.dart` + `clipboard_secret.dart`~~ | ~~180~~ | ~~`MethodChannel` to per-platform clipboard plugins~~ | done — `lfs_os_security::secure_clipboard::set_secure_text` covers Linux (arboard), macOS (NSPasteboard transient/concealed via objc2-app-kit), Windows (Win32 OpenClipboard + RegisterClipboardFormatW for cloud / history opt-out via raw extern), iOS (UIPasteboard.localOnly + expirationDate via objc2-ui-kit). Android keeps the `EXTRA_IS_SENSITIVE` MethodChannel. **Verification pending on macOS / iOS / Windows hardware.** |
| ~~`core/security/session_lock_listener.dart`~~ | ~~88~~ | ~~`MethodChannel` for screen-lock events~~ | Linux done, macOS/Windows non-ideal — Linux migrated to `lfs_os_security::session_lock_listener` (zbus → `org.freedesktop.login1.Session.Lock`, FRB Stream forwards). macOS + Windows kept on Dart MethodChannel by an earlier decision since reclassified as **non-ideal** — see [NI-3](#ni-3--session_lock_listener-macos--windows-on-dart-methodchannel) for the planned `objc2` / `windows-rs` migration. iOS / Android remain no-ops (lifecycle hook covers). |
| ~~`core/security/backup_exclusion.dart`~~ | ~~66~~ | ~~`MethodChannel` for `NSURLIsExcludedFromBackupKey`~~ | done — `lfs_os_security::backup_exclusion::exclude_from_backup` (objc2 + objc2-foundation; cfg-gated to Apple targets, no-op elsewhere). The Swift plugin file stays on disk pending an Xcode pbxproj cleanup; the property + register call dropped from MainFlutterWindow / AppDelegate. **Verification pending on actual macOS / iOS hardware.** |
| ~~`core/security/linux/fprintd_client.dart`~~ | ~~248~~ | ~~Dart `dbus` package → fprintd D-Bus~~ | done — wired Dart `FprintdClient` to the existing `lfs_core::platform::linux::fprintd` (zbus, signal stream for Verify) via FRB shim; dropped `dbus` package from `pubspec.yaml`. |
| ~~`core/sftp/file_system.dart`~~ (LocalFS) | ~~200~~ | ~~`dart:io` `File` / `Directory` ops~~ | done — `lfs_core::fs::local` (`list / mkdir / remove / remove_dir / rename / dir_size`) on `tokio::fs`; `windows_hidden_names` runs `attrib` via `tokio::process`; Dart side keeps only `initialDir` because that path uses `path_provider` (iOS sandbox / Android scoped storage) — no clean Rust analog |
| ~~`core/ssh/openssh_config_parser.dart`~~ (Include expansion) | ~~150~~ | ~~filesystem walk + glob + tilde expansion~~ | done — `lfs_core::ssh_config::parse_openssh_config_with_fs` owns the recursion + cycle detection + glob walk + 1 MiB per-file cap + CR/CRLF normalisation; the Dart parser is now a single FRB call (test seam still routes through `parse_openssh_config_with_includes` for canned-map injection) |
| ~~`core/import/openssh_config_importer.dart`~~ | ~~249~~ | ~~orchestrates parsed entries → `ImportResult`~~ | done — `lfs_core::import::openssh_config::build_preview` owns the full pipeline (parse + Include resolution + identity-file resolution + suspicious-path filter + dedup by fingerprint + UUID minting + auth-type decision). The Dart `OpenSshConfigImporter` shrinks to a wire-record → `Session` / `SshKeyEntry` / `ImportResult` mapper; `expandHome` routes through Rust too. Returns `DbOpenSshImportPreview` (named uniquely to avoid collision with archive's `DbImportPreview`). |
| ~~`core/import/ssh_dir_key_scanner.dart`~~ | ~~95~~ | ~~directory scanner with `keysIsObviousNonKeyFilename`~~ | done — `lfs_core::ssh_dir_scan::scan` owns the directory walk + non-key filename filter + 32 KiB per-file cap + PEM / PPK detection (PPK→PEM conversion via `lfs_core::keys::import_ppk`); Dart wrapper keeps the `listDir` / `readPem` test seams for the existing in-memory unit suite |
| ~~`core/sftp/sftp_fs.dart`~~ (recursive walks) | ~~300~~ | ~~`uploadDir` / `downloadDir` / `removeDir` recursion on top of leaf ops~~ | done — `Sftp::remove_dir_recursive` / `upload_dir` / `download_dir` in `lfs_core::sftp`. Per-file streaming + recursion + depth cap (100) Rust-side; per-file completion events flow back via FRB Stream → Dart `TransferProgress`. Cooperative cancellation: Dart cancels the subscription → Rust callback returns `false` → walker returns `Error::Cancelled` at next yield. Concurrency (the prior 4-files-per-level parallelism) is sequential in this first cut — JoinSet-based parallelism is a follow-up. |

Acceptance criteria:

- Each Tier 2 retire ships with property-based tests on the Rust
  side (config-parser, recursive walk, glob).
- `pubspec.yaml` drops the pure-Dart `dbus` package after the
  `fprintd_client` move.
- `lib/core/sftp/file_system.dart` retires to a single FRB call;
  Local + Remote both use the same Rust filesystem abstraction.
- Existing 17-skipped fuzz tests (kdf, qr_codec, ssh_config) keep
  passing; new fuzz tests for the recursive walker (random tree
  depth + leaf permissions).

### Tier 3 — Flutter security plugins → native Rust crates (~1 170 LOC, 1–2 weeks)

Strategic axis: drop `flutter_secure_storage` and `local_auth`
from `pubspec.yaml`, own the security stack end-to-end via Rust
crates with explicit cipher policies.

| File | LOC | Replacement |
|---|---|---|
| ~~`core/security/secure_key_storage.dart`~~ | ~~376~~ | desktop + Apple done, Android JNI planned — `lfs_os_security::secure_key_storage` covers Linux (`secret-service` crate, D-Bus → libsecret / gnome-keyring / KWallet), Apple (`security-framework` + raw `SecItemAdd` for the biometric path with `SecAccessControl` + `kSecAccessControlBiometryCurrentSet`), Windows (raw `CredReadW`/`CredWriteW`/`CredDeleteW` extern). The Dart wrapper routes those platforms through FRB; **Android stays on `flutter_secure_storage`** until the direct-JNI to `java.security.KeyStore` (provider `"AndroidKeyStore"`) lands per the [Tier 3 Android JNI bridge ledger](#tier-3--android-jni-bridge-ledger-planned-approach). **Apple / Windows verification pending on actual hardware.** |
| ~~`core/security/biometric_key_vault.dart`~~ | ~~255~~ | done on Apple, Win/Android planned — Apple now routes through the proper `SecAccessControl`-bound Rust path so the `biometryCurrentSet` enrolment-change invariant is preserved; Linux keeps the TPM seal first + libsecret-marker fallback (TPM is strictly stronger backing); Android stays on `flutter_secure_storage` until the direct-JNI to `BiometricPrompt`-gated `KeyStore` keys lands; Windows keeps `flutter_secure_storage` (Credential Manager has no biometric-bound storage class — Windows Hello protection lives in the hardware-vault plugin). |
| ~~`core/security/biometric_auth.dart`~~ | ~~314~~ | Linux + Apple + Windows done, Android JNI planned — Linux uses `FprintdClient` (Tier 2 `lfs_core::platform::linux::fprintd`), Apple uses `lfs_os_security::biometric_auth` (LAContext via `objc2-local-authentication`; `evaluatePolicy` reply block bridged to a tokio oneshot via `block2::RcBlock`), Windows uses the `windows` crate (`UserConsentVerifier::CheckAvailabilityAsync` + `RequestVerificationAsync`). Apple LAError codes (-6 / -7 / -8) and Windows `UserConsentVerifierAvailability` variants both map to the same `BiometricUnavailableReason` the Settings UI consumes. **Android remains on `local_auth`** until direct-JNI to `androidx.biometric.BiometricPrompt` lands per the planned-approach ledger. **Apple + Windows verification pending on actual hardware.** |
| ~~`core/security/wipe_all_service.dart`~~ | ~~223~~ | done — file sweep + crash marker live in `lfs_core::security::wipe`, keychain purge lives in `lfs_core::wipe_keychain`. The Dart class is pure orchestration around three FRB calls plus an in-process credential-cache flush (Riverpod-bound, intentionally Dart-side) and the `com.letsflutssh/hardware_vault` MethodChannel call (Tier 4 territory — retires when the hw-vault plugin migrates). |

Pre-conditions:

1. **Audit**: confirm each crate's cipher policy. Apple requires
   `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` +
   `kSecAccessControlBiometryCurrentSet` for the biometric ACL.
   Verify `security-framework`'s defaults match — patch upstream
   if not. Same for AndroidKeystore biometric binding.
2. **CI matrix expansion**: add Linux + macOS + Windows runners
   for Tier 3 tests. Android keystore tests stay manual until the
   CI gets a JNI-capable Android target.
3. **Plugin removal sequencing**: `flutter_secure_storage` /
   `local_auth` come out of `pubspec.yaml` only after every
   call site is confirmed routed through the new Rust path.

Acceptance criteria:

- `flutter_secure_storage` and `local_auth` deps gone.
- Threat model in `SECURITY.md` reflects the new attack surface
  (smaller — fewer plugin maintainers).
- Per-platform integration test that exercises the unlock cascade
  end-to-end against a real keychain on each desktop CI runner.

#### Tier 3 — Android JNI bridge ledger (planned approach)

The remaining "drop `flutter_secure_storage` / `local_auth`
from `pubspec.yaml`" gates on Android JNI work. **Approved
approach: direct JNI to platform Java APIs, no Kotlin shim.**

Earlier revisions of this section rejected the move on the
grounds that "AndroidKeystore is Java-first, replacing
`flutter_secure_storage` with our own Kotlin shim adds audit
surface without buying Rust ownership". That reasoning held
**only for the Kotlin-shim variant** — and there is a
strictly better option:

`java.security.KeyStore` (with the `"AndroidKeyStore"`
provider) IS the OS-level crypto API on Android — same
status as `SecItemAdd` on macOS, `CredWriteW` on Windows,
or libsecret D-Bus on Linux. It happens to live in the JVM
because Android exposes its system services through Java
class contracts; that is a calling-convention difference,
not an architectural one. The `jni` Rust crate calls these
classes directly — no Kotlin in the call chain.

**Architecture, mirroring the other four platforms:**

| Platform | OS-API | How Rust talks to it |
|---|---|---|
| Linux | libsecret / D-Bus | `secret-service` crate |
| macOS / iOS | `SecItemAdd` etc. | `security-framework-sys` + `objc2` |
| Windows | `CredWriteW` etc. | `extern "system"` via `windows-sys` |
| **Android** | **`java.security.KeyStore` (provider `"AndroidKeyStore"`)** | **`jni` crate, direct method calls** |

Same applies to:

- `androidx.biometric.BiometricPrompt` for `biometric_auth`
- `KeyGenParameterSpec.Builder.setIsStrongBoxBacked(true)`
  for `hardware_tier_vault` (StrongBox-backed keys are still
  surfaced through the same `java.security.KeyStore` API)

**Why this restores the Three-Pillars math:**

- **No Kotlin shim** — we do not add a hand-written Kotlin
  layer that would be ours to audit. JNI calls go straight to
  Android-platform classes that already carry Google's
  long-term API contract (stable since API 1 for `KeyStore`,
  since API 28 for `BiometricPrompt`).
- **Single source of truth** — the `lfs_os_security` crate
  becomes the only owner of OS-level security calls across
  all five platforms; Dart shrinks to a thin FRB wrapper as
  on every other platform.
- **Audit surface shrinks** — drop `flutter_secure_storage`
  + `local_auth` deps (third-party Kotlin maintained by
  another team) and replace with `jni` calls auditable line
  by line in our own Rust source.
- **Cargokit already builds Android targets** — the existing
  `build-release.yml::build-android` job installs
  `cargo-ndk` and the `aarch64-linux-android` /
  `armv7-linux-androideabi` / `x86_64-linux-android` /
  `i686-linux-android` Rust targets, then builds
  `liblfs_frb.so` per ABI. The infrastructure is already in
  place; this work adds Rust source, not build plumbing.

**Cost (honest):**

- **`jni` crate boilerplate** — cached `JMethodID` /
  `JFieldID` lookups at first call, `JNIEnv` lifetime tracking
  per call. Standard pattern; the `jni` crate's docs walk it
  through. Not unique risk.
- **Real-device verification gate** — JNI signature mismatches
  surface only at runtime, so the test loop must include an
  actual Android device or emulator. Same gate as Apple SE
  verification carries today.
- **JavaVM handle plumbing** — JNI calls need a `JavaVM`
  handle, captured once at `JNI_OnLoad` and cached for the
  process lifetime. Cargokit's Android template emits a
  `JNI_OnLoad` entry point already; we extend it to stash the
  handle in a `OnceLock<JavaVM>` for `lfs_os_security` to read.

**Status: approved, deferred until Android dev-loop available
(device or emulator + Android Studio for breakpoint debugging
during JNI signature bring-up).** Not blocking the rest of
Phase 6.

### Tier 4 — Heavy native ports (~1 600 LOC, 3–4 weeks, **only on explicit go-ahead**)

| File | LOC | Replacement | Risk |
|---|---|---|---|
| `core/security/hardware_tier_vault.dart` | 404 | **Apple done (2026-05) — verification pending.** `lfs_os_security::hardware_tier_vault` ports the SE primary key (`ECIESEncryptionCofactorVariableIVX963SHA256AESGCM` wrap, `WhenPasscodeSet` + `PrivateKeyUsage` ACL) + biometric overlay key (`BiometryCurrentSet`) + on-disk envelope (length-prefixed, chmod 0600) byte-for-byte from `HardwareVaultPlugin.swift`. Probe surfaces `macosSigningIdentityMissing` (-34018) classified separately. Dart `HardwareTierVault` routes Apple through FRB instead of MethodChannel; Swift plugin stays as rollback until a real Mac confirms parity. Windows still on MethodChannel (TBS API has no Rust crate; separate per-platform arc). Android still on MethodChannel — planned to migrate via direct JNI to `KeyGenParameterSpec.Builder.setIsStrongBoxBacked(true)` + `java.security.KeyStore`, no Kotlin shim, per the planned-approach ledger. |
| `platform/macos/code_signing/{cert_factory,codesigner,keychain,process_runner,resign_service}.dart` | 715 | `tokio::process::Command` over `openssl` / `security` / `codesign` / `hdiutil` / `rsync` | macOS-only; CI needs a real macOS runner |
| `platform/macos/installer/macos_installer.dart` | 212 | `tokio::process::Command` for atomic DMG install + relaunch | same as above |
| `core/connection/foreground_service.dart` | 191 | direct JNI Android service (drop `flutter_foreground_task`) | Android lifecycle ownership; foreground-service permission model breaks on Doze |
| `core/qr/qr_scanner.dart` | 36 | `objc2` (AVCaptureSession) + JNI (CameraX) | platform-specific UI surfaces stay native |
| `utils/android_storage_permission.dart` | 39 | JNI Permission API | Android storage permission model changes per OS version |

Tier 4 is **opt-in per item** — none are blocking the
"backend in Rust" milestone. Rationale for keeping each
Tier-4 item Dart by default:

- **macOS code-signing + installer**: macOS-only; the only path
  that benefits from Rust is auditability of the cipher /
  signing chain, but the chain is already opaque OS calls.
- **Android foreground service**: lifecycle ownership is bound
  to `MainActivity`; JNI lifecycle wiring duplicates what
  Flutter's plugin layer already does.
- **QR scanner / Android storage permission**: tiny shims; FFI
  cost > Rust gain.

Acceptance criteria (per item, when ramped):

- Each native plugin retires only after a real-device test on the
  target OS confirms parity.
- Threat-model section updated for any change in the
  trusted-code surface.

---

## Non-ideal items — planned to ideal

Honest accounting of every place where the current Rust
backend is "good enough" rather than "ideal" by Three Pillars
math. None of these are blocking, but each one is a debt — by
the rule "the bar to skip is moving makes the system worse,
inconvenience is not the bar", every item below has been
re-classified from "skipped" to "deferred but planned".

### NI-1 — Linux TPM2 via subprocess shell-out

**Status**: **native backend landed (2026-05) behind
`LFS_TPM_BACKEND=native` env-var opt-in; subprocess remains
the verified-working default until real-TPM verification
(NI-2 gate) flips it.**

**Current**: `lfs_core::platform::linux::tpm` exposes both
backends behind a unified public surface (`probe` / `seal` /
`unseal`). [`TpmConfig::backend`] selects which path runs:

- `TpmBackend::Subprocess` (default) — historical
  `tpm2-tools` shell-out; spawns `tpm2 createprimary` /
  `tpm2 create` / `tpm2 load` / `tpm2 unseal` per operation;
  every seal-secret bytes write to a 0600 file inside an
  RAII work dir; auth values pass through `file:<path>`
  rather than `hex:<hex>` argv to keep the HMAC out of
  `/proc/<pid>/cmdline`. Verified-working in the field.
- `TpmBackend::Native` (opt-in) — direct calls into
  `libtss2-esys` through the `tss-esapi` crate. Module
  [`lfs_core::platform::linux::tpm_native`]: no fork, no
  temp files, type-safe `TPMT_PUBLIC` /
  `TPMT_SENSITIVE_CREATE` building.

**Byte-compat invariant**: both backends produce the same
on-disk envelope shape (`[u32 BE pub_len][pub][u32 BE
priv_len][priv]`) holding `TPM2B_PUBLIC` + `TPM2B_PRIVATE`
marshalled bytes. The native path uses tss-esapi's
`PublicBuffer::marshall` for the public side (calls
`Tss2_MU_TPM2B_PUBLIC_Marshal` internally — same function
tpm2-tools uses) and a hand-rolled `[u16 BE size][bytes]`
TPM2B layout for the private side (tss-esapi 7.7 has no
`PrivateBuffer` analogue; the layout is the simplest one
in the TCG spec, kept in safe Rust to honour
`unsafe_code = "forbid"`). Primary template
([`build_primary_template`]) mirrors `tpm2 createprimary
-C o`'s default field-for-field — RSA 2048, SHA-256 name
hash, AES-128-CFB symmetric, restricted decryption key with
the standard ObjectAttributes — so the TPM-derived primary
key is byte-identical regardless of which backend created
the envelope.

**Build dep**: `libtss2-dev` added to `ci.yml`,
`build-release.yml::build-linux-x64`, and
`reproducibility-check.yml` Linux deps step. The native
module is compiled into every Linux release build (so a
future flip needs no rebuild) but stays inert at runtime
unless `LFS_TPM_BACKEND=native` is set.

**Verification gate (NI-2 territory)**: real-TPM end-to-end
test must confirm a sealed envelope round-trips between
the two backends (subprocess seal → native unseal, and
vice versa) before the env-var opt-in flips to
default-on and the subprocess path retires.

### NI-2 — Apple + Windows Rust ports verification-pending

**Current**: Apple stack (`hardware_tier_vault::apple`,
`secure_key_storage::apple`, `biometric_auth::apple`,
`secure_clipboard::apple`, `backup_exclusion`) + Windows
stack (`secure_key_storage::windows`,
`biometric_auth::windows`) — written, compile-checked on
ubuntu-latest only, **never run on real hardware**. The
Swift / Kotlin native plugins remain in place as rollback
behind `_useRustHardwareVault` / equivalent flags.

**Ideal**: every "done" status promoted from "compile-checks
on Linux" to "verified end-to-end on a real Mac / iPhone /
Windows machine". The Swift / native plugin scaffolding then
deletes outright.

**Why it is debt**: by Three Pillars math, "verified
working" is part of done. Code that compiles but has never
executed against the real OS-API is not done — it is
*plausible*. Shipping plausible-but-unverified security code
violates the safety pillar even when the code is correct on
review.

**Cost (honest)**:
- Apple verification: needs a real Mac with iCloud signed in
  (Secure Enclave is gated on a passcode being set + Apple
  ID enrolment for the SE key creation to succeed). `is_available()`
  returns `false` on a non-enrolled Mac, so a CI runner alone
  is insufficient — manual single-pass verification by the
  maintainer suffices.
- iOS verification: real iPhone + the user's own Apple ID,
  built through `flutter build ios --release` with a
  development provisioning profile (no App Store needed for
  installation onto the maintainer's own device).
- Windows verification: real Windows machine with Windows
  Hello enrolled (Hello biometric APIs gate on the device
  having an enrolled face / fingerprint). VM with passthrough
  is insufficient — Hello probes for the actual TPM-attached
  biometric sensor.

**Status**: gated on hardware access. CI Wave 1
(`rust-cross-check` matrix) closes the *compile-validation*
gap on every PR; the *runtime-verification* gap stays manual
until ramped.

### NI-3 — `session_lock_listener` macOS / Windows on Dart MethodChannel

**Status**: **Rust paths landed (2026-05) for all three desktop
platforms; Dart MethodChannel kept in parallel until
real-device verification (NI-2 gate) flips them off.**

**Current**: `lfs_os_security::session_lock_listener` covers
Linux + macOS + Windows behind a single `subscribe()` →
`broadcast::Receiver<()>` API. iOS / Android stay on the
Flutter `AppLifecycleState.paused` hook (no Rust listener
needed — the OS lifecycle event already fires the same way
desktop screen-lock does):

- **Linux** — `zbus` subscription to
  `org.freedesktop.login1.Session.Lock` (unchanged).
- **macOS** — dedicated thread owns its own `NSRunLoop`,
  registers an `NSDistributedNotificationCenter` observer
  for `com.apple.screenIsLocked` via an `objc2`-defined
  `LFSSessionLockObserver` class. Observer callback
  forwards on the broadcast channel; the `NSRunLoop::run`
  loop holds the thread for the process lifetime so
  callbacks fire reliably without contending with the
  Flutter engine's main-thread loop.
- **Windows** — dedicated thread creates a hidden
  message-only window (`HWND_MESSAGE` parent), registers
  `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)`,
  and pumps `GetMessageW` / `DispatchMessageW`. The
  `WindowProc` filters `WM_WTSSESSION_CHANGE` for
  `WTS_SESSION_LOCK` (wparam `0x07`) and forwards on the
  broadcast channel via a thread-local `Sender` pointer.

**Side effect — Windows-cfg pre-existing breakage caught**:
the rust-cross-check matrix (CI Wave 1) compile-validates
`lfs_os_security::biometric_auth` on Windows MSVC for the
first time. The pre-existing `op.get()` calls on
`IAsyncOperation<T>` (windows-rs 0.62 dropped that
convenience method) failed to compile. Fixed in the same
arc with a `block_on` helper that polls
`IAsyncOperation::Status` and calls `GetResults` once the
operation leaves the `Started` state — the canonical
windows-rs 0.62 sync-block pattern. `windows-future = "0.3"`
added as a direct dep to surface `IAsyncOperation` +
`AsyncStatus`.

**Verification status**: cross-platform compile validation
lands via the rust-cross-check matrix every PR. End-to-end
runtime verification on real macOS + Windows is the NI-2
gate; the Dart MethodChannel paths remain wired in
parallel until that gate flips.

---

## Permanent Dart surface (~92 000 LOC)

Architecturally Dart-bound — neither moves nor improves by going
Rust:

| Where | LOC | Why |
|---|---|---|
| `lib/widgets/` | 12 540 | Flutter widgets, Material, theme |
| `lib/features/` | 26 095 | feature screens, navigation, dialogs |
| `lib/l10n/` | 43 136 | 15+ generated locale files (`intl_utils`) |
| `lib/theme/` | 932 | Material `ThemeData`, `ColorScheme` |
| `lib/providers/` | 3 633 | Riverpod notifiers + view-stream subscribers |
| `lib/app/` | ~3 500 | shell, navigator, bus prompt listeners, dialog wiring |
| `core/connection/connections_notifier.dart` | 582 | Riverpod registry mirror |
| Files coupled to `xterm.dart` (`progress_writer`, `shell_helper`, `terminal_scrubber`, `terminal_clipboard`) | ~430 | xterm is Dart-only |
| Misc `BuildContext` / `Material` / Riverpod helpers (`secret_controller`, `lock_state`, `secure_ref`, `progress_reporter`) | ~500 | Flutter primitives |

Riverpod and Flutter widgets cannot run inside `lfs_core`. Files
that ride on `xterm.dart` (terminal pane stack) cannot move
unless the terminal renderer itself migrates — out of scope.

---

## Refactor backlog

Items that aren't migration moves but still need addressing for
best-practice + maintainability. Live audit (Apr 2026) findings:

### Lint suppressions to remove (CLAUDE.md violations)

`Never suppress issues` rule — every `// ignore:` outside generated
code is a debt to clear. Status (2026-05): all hand-written
suppressions cleared; the only `// ignore:` directives left in
`lib/` live inside generated artefacts (`lib/src/rust/*.freezed.dart`
from FRB / freezed codegen, `lib/l10n/*.dart` from `intl_utils`),
which the codegen owns.

- ~~`lib/platform/macos/code_signing/resign_service.dart:159, 162`
  — `// ignore: invalid_use_of_visible_for_overriding_member`.~~
  Done — `_DefaultKeychain` restructured so the linter is satisfied
  without the suppression.
- ~~`lib/app/global_error_dialog.dart:70` +
  `lib/providers/config_provider.dart:180` —
  `// ignore: unawaited_futures`.~~ Done — both replaced with
  explicit `unawaited(...)`.
- `lib/l10n/*.dart` (13 files) — `// ignore: unused_import`.
  Generated by `intl_utils`; not our code, leave alone.

### Oversized files — split into modules

Each file below is >1 000 LOC of human-written code; readability
+ test isolation suffer. Split each in a focused refactor arc:

| File | LOC | Suggested split |
|---|---|---|
| `lib/app/security_init_controller.dart` | **696** + 432 (unlock) + 440 (first-launch) | done (2026-05) — per-tier unlock flows (L1 / L2 / L3 / Paranoid + L2/L3 dialog scaffolding) and the first-launch wizard (per-tier appliers + macOS self-sign offer + orchestrator dispatch) live in two `extension on SecurityInitController` part siblings. SecurityInitController is a regular class, no setState wrapper needed. Main keeps the bootstrap → migration → init → corruption-recovery spine + the public API + the shared `_injectDatabase` / `_tryBiometricCommit` helpers. |
| `lib/features/settings/settings_sections_security.dart` | **784** + 248 (apply) + 194 (biometric) + 192 (macos) | done (2026-05) — tier-apply pipeline, biometric capture / pending-toggle flow, and the macOS keychain enable/remove block each in their own `extension on _SecuritySectionState` part sibling. Adds a `rebuild(VoidCallback)` wrapper on the State so the extensions go through it instead of touching protected `setState`. Main keeps `build` / `_buildTierCard` / the biometric-spec + auto-lock-row resolvers + `onSelectTier` + `_rerunTierProbes` + `_tierName` + the helper widgets `_AutoLockTile` / `_DisabledDropdownTrigger`. |
| `lib/features/session_manager/session_edit_dialog.dart` | **606** + 178 (connection) + 402 (auth) + 205 (options) | done (2026-05) — per-tab UI in three `extension on _SessionEditDialogState` part siblings (connection / auth / options). Adds a `rebuild(VoidCallback)` wrapper on the State so the extensions go through it instead of `setState`. Main keeps the dialog scaffold (build / header / tab bar / footer), state + lifecycle (initState / dispose / _loadForwards / _resolveKeyLabel), the Save pipeline (_buildSession / _validateAuth / _tabWithFirstError / _save), and `_requiredValidator`. |
| `lib/features/session_manager/session_panel.dart` | **550** + 329 (session-actions) + 406 (folder-actions) + 326 (widgets) | done (2026-05) — session context menu + dialog flows and folder context menu + dialog flows in two `extension on SessionPanelState` part siblings, on top of the existing `session_panel_widgets.dart` part. Main keeps build / lifecycle / shortcut bindings / bulk-ops / sidebar layout — no public surface change, the `@visibleForTesting` getters stay where the tests expect them. |
| `lib/widgets/expandable_tier_card.dart` | **685** + 145 + 187 + 144 (parts) | done (2026-05) — seven private helper widgets (_Header / _CurrentBadge / _ThreatListFixed / _ThreatLine / _UnavailableReason / _ModifierRow / _PasswordPair) live in three `part` siblings (header / threats / inputs), same pattern as `settings_screen.dart`. Public API unchanged. The remaining 685 LOC is the State + per-tier branching, which the original "per-tier card variants" slice would split into separate stateful widgets; deferred until the State logic stabilises further. |
| `rust/crates/lfs_core/src/archive/` | mod.rs **477** + apply.rs 850 + compose.rs 461 + qr_compose.rs 366 + envelope.rs 226 + iso8601.rs 156 | done (2026-05) — five focused submodules: `compose` (export side: ExportOptions/Input + build_zip + per-entity build_*_value helpers + manifest writer), `qr_compose` (QR-share payload), `envelope` (LFSE Argon2id+AES-GCM wrapper + import-time KDF caps), `iso8601` (timestamp helpers shared with `archive_stage`, eliminating the duplicate Howard-Hinnant body), `apply` (whole import-apply driver). `mod.rs` now scopes to the pending-import types + `parse_pending_import` / `read_archive_to_pending` + the two pub(super) DB-aggregate helpers (build_known_hosts / build_folder_paths) that both compose and qr_compose embed. |
| `rust/crates/lfs_core/src/ssh/mod.rs` | 1 608 | acceptable (central SSH module — refactor only if a clean split appears) |

Effort per file: 0.5–1 day each, low-risk. Tests stay green
because the surface doesn't change — only file boundaries move.

### Test debt — skipped tests sweep

Status (2026-05): 18 → 9 → **2** skips. Both halves swept: the
recoverable Rust-touching tests are alive under `requireFrbLoaded`;
the dead Dart-mock tests for the retired `_defaultFetchDart` /
`_defaultDownloadDart` shims are deleted along with the
`_FakeHttpOverrides` scaffolding. Only the two remaining skips need
infrastructure (Rust DB + SecretStore staging, live SFTP connection
registry) the unit-test harness cannot stand up.

| File | Skips | Disposition |
|---|---|---|
| ~~`test/core/session/session_recorder_test.dart`~~ | ~~6~~ → 0 | done — `requireFrbLoaded` boots the real recorder; 4 round-trip tests + 1 close-idempotency + 1 non-ASCII payload all unskipped. The 6th (encrypted-mode round-trip) was an empty placeholder pointing at the reader test below — deleted. |
| ~~`test/features/recordings/recording_reader_test.dart`~~ | ~~3~~ → 0 | done — cast roundtrip + encrypted roundtrip + readMeta dimensions all unskipped under `requireFrbLoaded`. |
| ~~`test/core/update/update_service_test.dart`~~ | ~~7~~ → 0 | done — the seven `_defaultFetchDart` / `_defaultDownloadDart` `HttpOverrides`-mock tests + the `_FakeHttpOverrides` scaffolding (~480 LOC) deleted; `defaultFetch` / `defaultDownload` are now FRB shims around `lfs_core::update_http::fetch_text` / `download_to_file` and the HTTP semantics live in `lfs_core::update_http::tests` + `integration_test/`. The Dart-side fail-fast guard for an untrusted URL stays as the one live test in the group. |
| `test/providers/connection_provider_test.dart` | 1 | retained with tightened rationale — `connectAsync` needs `db_init` + SecretStore staging in addition to FRB; integration_test/ is the right home. |
| `test/features/mobile/mobile_shell_test.dart:823` | 1 | retained — SFTP-from-context-menu nav needs a live Rust connection-registry session (the fake handle doesn't resolve). Coverage lives in `integration_test/`. |

---

## Optimization backlog

Performance + footprint items, separate from migration. Run
`cargo build --timings` + a profiling pass before committing
any of these — measure twice.

### Bundle size — `liblfs_frb.so` (release)

Pre-tighten baseline: 20 MiB. After applying the documented
quick wins (`strip = "symbols"` + `panic = "abort"` on top of
the existing `lto = "fat"` + `codegen-units = 1` + `opt-level = 3`):
**16.6 MiB**, ~17% saved (3.4 MiB).

```toml
[profile.release]
codegen-units = 1
lto = "fat"
opt-level = 3
strip = "symbols"           # drop debug + symbol tables
panic = "abort"             # drop unwinding tables / landing pads
```

Heavy deps by `cargo tree -p lfs_core --depth 1` (for context):
`russh`, `russh-sftp`, `reqwest`, `zbus`, `zip`, `rusqlite`,
`regex`. Each is load-bearing — none is a candidate for removal
without a feature loss. The optimization is on the build profile,
not the dep set.

Plan target was < 14 MiB; we landed at 16.6 MiB. The gap is the
new objc2 / security-framework / arboard / secret-service / windows
dep tree the Tier 2 + Tier 3 native migrations brought in
(none on the original 19 MiB baseline). Further shrinking would
need (a) feature-gating zbus down (currently `default-features = false +
features = ["tokio"]` is the minimum set for fprintd + logind); (b)
considering `opt-level = "z"` (smaller code at the cost of speed —
needs profiling on the SSH cipher hot path before flipping); (c)
splitting the cdylib so per-platform features ship only what they
need (cargo workspaces don't make this easy without separate adapter
crates per platform). All three are individual focused arcs.

`panic = "abort"` trade-off: a panic anywhere in our Rust code
or a transitive dep aborts the process instead of unwinding into
Dart's catch handlers. Acceptable because every `Result<_, Error>`
boundary is explicit; panics in our code only fire on programming
errors (poisoned mutex, debug-only integer overflow); the user-
visible "what changed" between graceful failure and hard abort is
the same thing they'd see if the OOM killer fired.

### Hot-path candidates (need profiling, not assumption)

- **SFTP recursive walks** (Tier 2 candidate) — Dart driver +
  per-file FRB round-trip. Move walker Rust-side eliminates the
  per-file FRB cost.
- **Recorder per-frame AES-GCM** — should be fast (RustCrypto
  `aes-gcm` is hand-tuned), but worth a benchmark on a long
  recording (10+ MB). If the encrypt loop shows up in profiles,
  consider hardware AES (`aes` crate's `aesni` feature on x86-64).
- **Session list folder-cascade on large collections** (1 000+
  sessions) — already Rust-side; benchmark `lfs_core::sessions::
  filter_sessions` against a synthetic 5 000-session dataset to
  confirm the filter doesn't degrade beyond linear.
- **QR-export size estimator** — sync FRB call on every checkbox
  toggle. If user drag-toggles fast, could jank. Add Dart-side
  debounce (50 ms idle window) before reaching for the Rust
  helper.

### Memory profile checks

- `lfs_core::secrets::SecretStore` — confirm eviction on session
  delete + on tier reset. No unbounded growth.
- Bus broadcast backlog — `tokio::sync::broadcast` drops oldest
  when capacity hits. Verify the capacity is sane (per-topic
  basis) and that subscribers don't lag long enough to lose
  events on a busy connection.
- Connection actor handles — verify `disconnect(id)` actually
  drops the `Arc<Session>` (no leaked transport on rapid
  reconnect cycles). Stress test: 100 connect / disconnect
  cycles, assert RSS doesn't grow.

### Compile time

`cargo build --timings` baseline: capture once, set a budget,
re-check on every dep bump. `russh` + `reqwest` + `zbus` are the
heavy ones. Suggestion: split `lfs_frb` into multiple smaller
crates only if `lfs_frb`'s build dominates (it currently
doesn't — `lfs_core` is the longer leg).

---

## Sequence

```
Tier 1   (libc/dart:ffi → Rust nix; pure data carriers)
   ↓
Tier 2   (pure logic + small platform consolidation, parallel batches)
   ↓
[strategic gate — keep flutter_secure_storage / local_auth?]
   ↓
Tier 3   (security plugins → native Rust crates)
   ↓
[strategic gate — Android dev-loop available?]
   ↓
Tier 3 Android JNI (direct java.security.KeyStore / BiometricPrompt)
   ↓
Tier 4   (per-item, only with explicit justification)
```

Tier 1 and Tier 2 land regardless. The decision point before
Tier 3 Android is logistical (real device or emulator + Android
Studio for breakpoint debugging during JNI bring-up), not
architectural — the approach itself is locked: direct JNI to
platform Java APIs, no Kotlin shim. Tier 4 stays per-item with
its own ongoing-cost trade-off justification.

---

## Testing strategy

Per tier:

- **Tier 1**: Rust unit tests cover the libc paths against each
  target OS. Dart-side: integration tests that exercise the
  `mlock` / `prctl` paths under a real FRB-loaded runtime.
- **Tier 2**: property-based tests on the Rust side (config-parser,
  recursive walk, glob, clipboard timed-wipe). Replace the Dart
  fuzz-test family that targets the retired Dart shim with the
  Rust property tests.
- **Tier 3**: per-platform integration tests on real CI runners.
  Add an "auth-required" smoke test that exercises the full
  unlock cascade against the live system keychain — gated by an
  env var so CI doesn't try it on every push.
- **Tier 4**: real-device parity tests; manual until CI grows the
  matrix.

Cross-cutting:

- Every retire commit ships with a single combined PR that drops
  the Dart shim, updates `ARCHITECTURE.md` for the moved §, and
  removes the test file that targeted the retired surface — no
  half-merges.
- The 17 currently-skipped tests after the orchestration retires
  closed (Apr 2026) stay skipped *only if* they cover code that
  no longer exists. Retire those tests in the same arc that
  retires their target code.

---

## Risks

1. **Tier 3 cipher policy drift** — replacement crates' defaults
   may not match the Apple / Android ACL invariants the current
   plugins enforce. Mitigation: audit per-platform before drop;
   patch upstream if needed; keep the Dart plugin path behind a
   feature flag during rollout.
2. **JNI signature drift** — every direct-JNI call to a
   `java.security.KeyStore` / `androidx.biometric.BiometricPrompt`
   method names a Java method by literal string + JNI signature
   (e.g. `"getInstance"` `"(Ljava/lang/String;)Ljava/security/KeyStore;"`).
   When Google rotates an API name or signature in a future
   Android release the failure surfaces only at runtime on the
   target API level, not at compile time. Mitigation: lookup
   table + cached `JMethodID` keyed on a single resolution pass
   at `JNI_OnLoad`; integration tests run against the API levels
   the app's `minSdkVersion` and `targetSdkVersion` declare; CI
   matrix grows an Android emulator runner once the JNI work
   ramps. Tier 4 native-Android items (`foreground_service`,
   `qr_scanner`, `android_storage_permission`) remain explicitly
   opt-in regardless — they are tiny shims where FFI cost
   dominates Rust gain even with the direct-JNI approach.
3. **CI runner coverage** — Tier 3 + Tier 4 require Linux + macOS
   + Windows + Android runners with real keychain / biometric
   APIs. Today the CI has Linux only. Mitigation: stage Tier 3
   per platform; macOS / Windows / Android tests stay manual
   until CI grows.
4. **`zbus` runtime overlap** — the D-Bus crate pulls a runtime;
   verify it shares the existing tokio one rather than spawning a
   parallel async-std. Mitigation: stick to the tokio feature
   flag, smoke-test the Linux build for double-runtime panics.
5. **`directories` crate platform surface** — if its `home_dir()`
   doesn't match the existing Android `EXTERNAL_STORAGE`
   fallback, Android file-browser breaks. Mitigation: golden
   test the directory resolution per OS before flipping the call
   site.
6. **Test-suite gravity on data models** — `Session`, `AppConfig`,
   `PortForwardRule` and similar value classes feed thousands of
   test fixtures. Moving them Rust-side is a 3–5 day test
   refactor for no functional gain. **Decision**: keep these
   models Dart-side; only the orchestration around them moves.

---

## Prioritized action list

In execution order. Each item is a self-contained arc — start
one, ship it, then pick the next.

### Now — must-fix (CLAUDE.md compliance)

1. ~~**Drop the two `// ignore: invalid_use_of_visible_for_overriding_member`** in
   `lib/platform/macos/code_signing/resign_service.dart`. Restructure
   `_DefaultKeychain` so the linter is satisfied without the
   suppression.~~ Done — file no longer carries any
   `// ignore:` directives.
2. ~~**Replace the two `// ignore: unawaited_futures`** in
   `lib/app/global_error_dialog.dart` and
   `lib/providers/config_provider.dart` with explicit
   `unawaited(...)` calls.~~ Done — both files are
   suppression-free; remaining `// ignore:` directives in `lib/`
   live only inside generated artefacts (`lib/src/rust/*.freezed.dart`,
   `lib/l10n/*.dart`) which the codegen owns.

### Next — Phase 6 Tier 1 (1–2 days, free wins)

3. ~~`secret_buffer.dart` + `process_hardening.dart` +
   `libc_loader.dart` → `lfs_core::os_security` via `nix` /
   `libc`. Drops `dart:ffi` from the security module.~~ Done in
   substance — `libc_loader.dart` deleted, `process_hardening.dart`
   shrunk to a 60-LOC façade over
   `osSecurityApplyStartupHardening` (FRB sync), `secret_buffer.dart`
   keeps a thin Dart-side `dart:ffi` wrapper because the
   `NativeFinalizer` GC backstop has no Rust analogue and
   migrating the buffer ownership to Rust would force every
   `bytes` accessor through an FFI copy that defeats the
   in-place-zero discipline. The two `lock_memory` /
   `unlock_memory` calls already route through `lfs_os_security`.
4. ~~`utils/platform.dart` `homeDirectory` → Rust via
   `directories` crate. Smoke-test Android `EXTERNAL_STORAGE`
   resolution before flipping.~~ Done — landed as
   `lfs_core::host_info` with direct env-var resolution (not
   the `directories` crate; Android wants `EXTERNAL_STORAGE`
   specifically and the crate doesn't expose that bucket
   cleanly). All four queries (`home_directory` /
   `is_mobile` / `is_desktop` / `is_macos`) are sync FRB
   shims; the Dart wrapper caches each result on first read.
5. ~~`core/session/session_tree.dart` + `session_history.dart` +
   `core/single_instance/single_instance.dart` → Rust pure-data
   modules + `fd-lock` for the file lock.~~ Done — `session_history`
   landed as `lfs_core::session_history` (per-handle actor),
   `session_tree` landed as `lfs_core::session_tree` (immutable
   forest builder); `single_instance` rewritten on `libc::flock`
   (POSIX) / `LockFileEx` (Windows) inside `lfs_os_security`
   (the `fd-lock` plan was rejected — its `fcntl(F_SETLK)` lock
   namespace doesn't see Dart's `RandomAccessFile.lock`/`flock()`
   on Linux, so cross-process contention silently passed).

### Parallel — test debt sweep (any time)

6. ~~Move 16 Rust-covered skipped tests (update_service, recorder,
   recording_reader) to `integration_test/`; investigate the 2
   ad-hoc skips (connection_provider, mobile_shell).~~ Done
   (2026-05) — recorder + recording_reader unskipped via
   `requireFrbLoaded`; the seven `update_service` HTTP-mock tests
   were deleted along with the `_FakeHttpOverrides` scaffolding
   (Rust now owns the HTTP path; the mock could never reach
   production). Only the 2 ad-hoc skips remain — both legitimately
   need integration_test/ infra (Rust DB + SecretStore for
   connection_provider; live SFTP connection registry for
   mobile_shell). See test-debt table above.

### Parallel — refactor backlog (any time, low risk)

7. ~~Split `rust/crates/lfs_core/src/archive.rs` (2 362 LOC) into
   focused submodules.~~ Done (2026-05) — see split-modules row in
   the oversized-files table above.
8. ~~Split the four oversized Dart files (`security_init_controller`,
   `settings_sections_security`, `session_edit_dialog`,
   `session_panel`) — one file per arc, surface unchanged.~~ Done
   (2026-05) — all four landed alongside `expandable_tier_card`;
   see the oversized-files table above for the per-file layout.

### Soon — Phase 6 Tier 2 (3–5 days)

9. ~~Clipboard stack (`secure_clipboard` + `clipboard_secret`) →
   `arboard` crate; Android sensitive-flag stays MethodChannel.~~
   Done (2026-05) — `lfs_os_security::secure_clipboard` covers
   Linux (arboard), macOS (NSPasteboard transient/concealed),
   iOS (UIPasteboard.localOnly), Windows (raw OpenClipboard +
   RegisterClipboardFormatW for cloud/history opt-out).
10. ~~`session_lock_listener` → `objc2` / `windows-rs` / zbus.~~
    Done (2026-05) — Linux logind Session.Lock via zbus +
    tokio::sync::broadcast in `lfs_os_security::session_lock_listener`.
    macOS / Windows kept on existing native plugins (window /
    run-loop bound).
11. ~~`backup_exclusion` → `objc2` Foundation `xattr`.~~ Done
    (2026-05) — Apple `NSURL.setResourceValue` with
    `NSURLIsExcludedFromBackupKey` via objc2 in
    `lfs_os_security::backup_exclusion`.
12. ~~`linux/fprintd_client` → `zbus`.~~ Done (2026-05) — zbus
    proxy lives in `lfs_core::platform::linux::fprintd`; the Dart
    `FprintdClient` shim routes through FRB.
13. ~~`core/sftp/file_system.dart` LocalFS → `tokio::fs` in
    `lfs_core::fs::local`.~~ Done — module landed with all
    six fs ops (`list`, `mkdir`, `remove`, `remove_dir`,
    `rename`, `dir_size`) plus `windows_hidden_names`; Dart
    keeps only `initialDir` (Flutter `path_provider` dep).
14. ~~OpenSSH config Include resolution + `ssh_dir_key_scanner` →
    `lfs_core::import::ssh_config`.~~ Done — Include + glob
    walk lives in `lfs_core::ssh_config::parse_openssh_config_with_fs`;
    `~/.ssh` directory scan lives in `lfs_core::ssh_dir_scan::scan`.
    `openssh_config_importer` orchestration glue (the in-memory
    preview path → `ImportPreview`) also landed in
    `lfs_core::import::openssh_config::build_preview` — now used
    by the Dart importer through FRB.
15. ~~SFTP recursive walks (`uploadDir` / `downloadDir` /
    `removeDir`) → `lfs_core::sftp::recursive_walk`.~~ Done —
    `lfs_core::sftp` exposes `Sftp::remove_dir_recursive`,
    `Sftp::upload_dir`, and `Sftp::download_dir` with sync
    callback closure for per-file progress + cancellation; the
    65 KiB chunking lives in `stream_upload_file` /
    `stream_download_file`. Cooperative cancel through
    `AtomicBool` propagated via the FRB closure.

### Bundle size — single tweak arc (after Tier 2)

16. ~~Tighten `[profile.release]` in `rust/Cargo.toml`:
    `strip = true` + `lto = "fat"` + `codegen-units = 1` +
    `panic = "abort"`. Measure size before / after; target
    < 14 MiB for `liblfs_frb.so`.~~ Done (2026-05) — landed at
    16.6 MiB (3.4 MiB / ~17 % saved). Plan-target 14 MiB gap
    explained in the "Bundle size" status section above (Tier 2 +
    Tier 3 native deps account for the residual ~2.6 MiB).

### Strategic gate — Phase 6 Tier 3 (1–2 weeks)

17. ~~**Decision required before starting**: do we drop
    `flutter_secure_storage` + `local_auth` from `pubspec.yaml`?~~
    Decided: yes for desktop / Apple, deferred for Android (see
    Tier 3 ledger above).
18. ~~`secure_key_storage` + `biometric_key_vault` +
    `biometric_auth` + `wipe_all_service` → `security-framework`
    / `wincred` / `secret-service` / `objc2` / `windows-rs` / JNI.~~
    Done on desktop + Apple (2026-05) — see Tier 3 table above for
    the per-file split. Android stays on flutter_secure_storage /
    local_auth pending JNI bridge work.

### Strategic gate — Phase 6 Tier 3 Android JNI (1 week, gated on dev-loop)

19. ~~**Decision required before starting**: do we take on JNI
    maintenance for the Android-only paths?~~ **Decided
    (2026-05): yes — direct JNI to platform Java APIs (no
    Kotlin shim) is the planned approach.** Restores
    cross-platform uniformity (Rust owns OS-API call on all 5
    platforms) and treats `java.security.KeyStore` as the
    Android equivalent of `SecItemAdd` / `CredWriteW`. See
    [Tier 3 Android JNI bridge ledger](#tier-3--android-jni-bridge-ledger-planned-approach).
    Logistical gate only: needs a real Android device or
    emulator + Android Studio for breakpoint debugging during
    JNI signature bring-up.
20. When ramped (per file, in this order — easiest to hardest):
    a. `secure_key_storage` — JNI to `java.security.KeyStore`
       provider `"AndroidKeyStore"` (smallest surface, most
       documented signatures).
    b. `biometric_auth` — JNI to `androidx.biometric.BiometricPrompt`
       (lifecycle-bound to `FragmentActivity` — cargokit's
       `JNI_OnLoad` plus a `MainActivity` reference cached
       from a Dart-side bootstrap call).
    c. `biometric_key_vault` — composes (a) + (b) once both land.
    d. `hardware_tier_vault` Android — extends (a) with
       `KeyGenParameterSpec.Builder.setIsStrongBoxBacked(true)`
       on supported devices (API 28+).
    Each ships with a real-device parity test before the
    corresponding Dart plugin gets dropped from `pubspec.yaml`.

### Strategic gate — Phase 6 Tier 4 (3–4 weeks, opt-in per item)

21. **Decision required before starting**: take on each Tier-4
    item only when the security or audit story justifies the
    ongoing cost. Per-item evaluation.
22. If yes (per item): `platform/macos/code_signing` /
    `macos_installer` / `foreground_service` / `qr_scanner` /
    `android_storage_permission`.

### CI maximum — full hygiene buildout (parallel arc)

Every CI gap that prevents the project from being "ideal" by
the Three Pillars rule, in execution waves. Each wave is a
self-contained commit set; waves below depend only on the
ones above.

**Wave 1 — cfg-gated Rust compile coverage on every PR.**
`ci.yml::rust-cross-check` matrix job that runs `cargo check
--workspace --all-targets --target <T>` per target:

- `aarch64-apple-darwin` (macos-latest)
- `x86_64-apple-darwin` (macos-latest)
- `aarch64-apple-ios` (macos-latest) — iOS Apple-cfg validates
  here; we cannot ship an .ipa without an Apple Dev account but
  compile-validation already catches every type / API drift in
  the iOS path.
- `x86_64-pc-windows-msvc` (windows-latest)
- `aarch64-linux-android` + `armv7-linux-androideabi` (ubuntu
  via cargo-ndk) — gates the upcoming JNI work.

Why: today `rust-ci` only runs on `ubuntu-latest`. The Apple
hardware-vault Rust port (~700 LOC under `cfg(any(target_os
= "macos", target_os = "ios"))`) is never compile-checked on
PR — failure surfaces only on release tag through
`build-release.yml::build-macos`. Same for any future
Windows-cfg / Android-cfg code.

**Wave 2 — Rust quality gates parity with Dart.**

- `cargo-llvm-cov --workspace --lcov` step in `rust-ci`,
  artifact `rust-lcov.info`, uploaded to SonarCloud alongside
  the Dart `lcov.info`.
- `cargo machete` — fails on unused workspace dependencies.
- `Cargo.lock` parity — `cargo update --workspace --locked`
  + `git diff --exit-code` (mirrors the existing ARB parity
  check).
- MSRV pin in `rust/rust-toolchain.toml` (currently `channel
  = "stable"` without a minor pin → runner-image rotation can
  silently break).

**Wave 3 — supply-chain hardening.**

Landed in initial increment:

- Weekly `cargo deny check advisories` cron in
  `.github/workflows/rust-audit.yml` — catches CVE drift in
  RustSec between dependency-bump PRs. Same `rust/deny.toml`
  config as `ci.yml::rust-ci`'s on-PR check, narrows the
  unnoticed-CVE window from "next dependency-bump PR" to "one
  week worst-case".
- Rust SBOM via `cargo cyclonedx` in
  `build-release.yml::release` — every transitive crate
  (russh, tokio, RustCrypto family, …) with version, license,
  source URL, attached to the release as
  `letsflutssh-<version>.rust-sbom.cdx.tar.gz`.

Wave 3 follow-ups:

- ~~**Cosign keyless signing** alongside the existing Ed25519
  manifest signature.~~ Landed (2026-05) —
  `sigstore/cosign-installer@cad07c2e89fa2edd6e2d7bab4c1aa38e53f76003 # v4.1.1`
  pinned to the verified upstream release SHA + cosign
  binary `v3.0.6` pinned via the action's `cosign-release`
  input. Output is a Sigstore-format
  `letsflutssh-<v>.sha256sums.cosign-bundle` (signature +
  certificate + Rekor transparency-log entry in one blob,
  ready for `cosign verify-blob --bundle …`). Two-anchor
  signing achieved: Ed25519 for in-app updater, cosign
  keyless for public verifiability via GitHub OIDC identity
  `https://github.com/<repo>/.github/workflows/build-release.yml@<ref>`.
- **Dart SBOM** alongside the Rust one. No published-and-
  pinnable CycloneDX tool exists for Dart pub today; GitHub's
  automatic dependency graph derives the same data from
  `pubspec.lock`. Add a sibling step here when a stable
  Dart cyclonedx tool ships.

**Wave 4 — reproducibility verification.**

- Nightly cron job that builds Linux artefacts (`tar.gz` /
  `.deb` / `.AppImage`) twice on the same SHA + diffs sha256.
  On mismatch, runs `diffoscope` and uploads its report. The
  build-release.yml comments today *claim* Linux is byte-
  identical across runs; nothing currently verifies it.

**Wave 5 — platform expansion (release artefacts).** Each
sub-item is its own independent arc; none gate the others.

- `aarch64-unknown-linux-gnu` (Linux ARM64 — RPi 5, Asahi,
  Graviton, Ampere). Cross-compile via the runner's
  `gcc-aarch64-linux-gnu` toolchain plus `cargo --target`.
- `aarch64-pc-windows-msvc` (Windows ARM64 — Surface Pro X,
  Snapdragon X). Cross-compile from `windows-latest`.
- iOS unsigned `.ipa` (compile-only, no distribution) — same
  Apple-stack as macOS, gated on an Apple Dev account for
  actual install but compile validation already catches every
  type drift.

**Wave 6 — distribution channels (PRs into external repos).**

- Snap manifest → publish to Snap Store.
- Flatpak manifest → submit to Flathub.
- Homebrew cask → PR to `homebrew/homebrew-cask`.
- WinGet manifest → PR to `microsoft/winget-pkgs`.

These are not in our repo's CI but in third-party flows; each
wave-6 item requires a separate manifest + maintainer review
on the external side.

**Out of scope (Three Pillars "moving makes worse" or
externally blocked):**

- macOS notarization — needs Apple Developer Program ($99/yr).
- Windows EV cert — $300+/yr + Yubikey HSM. Self-signed
  Authenticode is the best zero-cost option.
- iOS App Store distribution — same as notarization.
- SLSA L4 — needs hermetic builders we cannot stand up
  inside GitHub-hosted runners.

### Non-ideal items — promote to ideal (parallel arc)

23. ~~**NI-1**: Linux TPM2 → `tss-esapi` crate.~~ Native
    backend landed (2026-05) as `TpmBackend::Native` in
    `lfs_core::platform::linux::tpm_native`; opt-in via
    `LFS_TPM_BACKEND=native` env var. Subprocess remains
    default until real-TPM verification (NI-2 gate) flips
    it. `libtss2-dev` added to `ci.yml`,
    `build-release.yml::build-linux-x64`, and
    `reproducibility-check.yml` Linux deps. `BSL-1.0`
    added to `deny.toml` allow-list (pre-existing
    `arboard`/`clipboard-win` dependency surfaced when the
    deny gate started firing in CI).
24. **NI-2**: Apple + Windows real-device verification gate.
    Single-pass manual verification per platform by the
    maintainer; once green, delete the parallel native
    plugins (`HardwareVaultPlugin.swift`,
    `BiometricVaultPlugin.swift`,
    `SecureKeyStoragePlugin.swift` and Windows equivalents)
    and drop the `_useRustHardwareVault` flag.
25. ~~**NI-3**: `session_lock_listener` macOS + Windows →
    `objc2` (`NSDistributedNotificationCenter`) + Win32
    hidden HWND with our own `WindowProc`.~~ Landed
    (2026-05). macOS observer registers on a dedicated
    `NSRunLoop` thread; Windows hidden message-only window
    on a dedicated `GetMessageW` pump. Forwards via
    `tokio::sync::broadcast` → FRB Stream identical to the
    Linux logind path. Side fix: `biometric_auth.rs` Windows
    `op.get()` migrated to a `block_on` helper polling
    `IAsyncOperation::Status` (the windows-rs 0.62 canonical
    sync-block pattern); `windows-future = "0.3"` added as a
    direct dep. Native plugin retires once NI-2 verifies the
    Rust paths on real Mac + Win hardware.

### Final — close the migration

26. Delete this file. Backend is fully in Rust; remaining Dart
    is widgets + Riverpod + permanent platform glue.
