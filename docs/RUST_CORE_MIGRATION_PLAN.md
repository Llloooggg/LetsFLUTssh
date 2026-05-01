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
| TPM seal / unseal (Linux subprocess) | DONE | `lfs_core::platform::linux::tpm` |
| Hardware-vault disk-blob format + auth resolver | DONE | `lfs_core::security::hardware_tier_vault` |
| Capabilities orchestrator + cache + prompt registries | DONE | `lfs_core::security::capabilities_orchestrator` |
| Tier state machine (per-tier sub-machines, prompt protocol) | DONE | `lfs_core::security::tier_machine` |
| Wipe catalogue + crash markers | DONE | `lfs_core::security::wipe` |
| Persisted rate-limit (HMAC-authenticated frame) | DONE | `lfs_core::security::persisted_rate_limit` |
| `app_config` schema mirror | DONE | `lfs_core::config` |
| Config store actor (debounce + atomic write + bus events) | DONE | `lfs_core::config_store` |
| **Tail-end Dart retire (Phase 6)** | **PENDING** | per-Tier below |

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
| ~~`core/security/session_lock_listener.dart`~~ | ~~88~~ | ~~`MethodChannel` for screen-lock events~~ | partially done — Linux migrated to `lfs_os_security::session_lock_listener` (zbus → `org.freedesktop.login1.Session.Lock`, FRB Stream forwards). macOS + Windows keep their existing native plugins because `WTSRegisterSessionNotification` is HWND-scoped and `NSDistributedNotificationCenter` needs the Cocoa run loop the Flutter engine already pumps — re-implementing both in Rust would duplicate plumbing without a correctness or perf gain. iOS / Android remain no-ops (lifecycle hook covers). |
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
| ~~`core/security/secure_key_storage.dart`~~ | ~~376~~ | desktop done, Android pending — `lfs_os_security::secure_key_storage` covers Linux (`secret-service` crate, D-Bus → libsecret / gnome-keyring / KWallet), Apple (`security-framework` + raw `SecItemAdd` for the biometric path with `SecAccessControl` + `kSecAccessControlBiometryCurrentSet`), Windows (raw `CredReadW`/`CredWriteW`/`CredDeleteW` extern). The Dart wrapper routes those platforms through FRB; **Android stays on `flutter_secure_storage`** until the AndroidKeystore JNI bridge lands. **Apple / Windows verification pending on actual hardware.** |
| ~~`core/security/biometric_key_vault.dart`~~ | ~~255~~ | done on Apple, deferred on Win/Android — Apple now routes through the proper `SecAccessControl`-bound Rust path so the `biometryCurrentSet` enrolment-change invariant is preserved; Linux keeps the TPM seal first + libsecret-marker fallback (TPM is strictly stronger backing); Android + Windows keep `flutter_secure_storage` (Android until the JNI bridge lands; Windows because Credential Manager has no biometric-bound storage class — Windows Hello protection lives in the hardware-vault plugin). |
| ~~`core/security/biometric_auth.dart`~~ | ~~314~~ | Linux + Apple done, Windows / Android pending — Linux uses `FprintdClient` (Tier 2 `lfs_core::platform::linux::fprintd`), Apple uses `lfs_os_security::biometric_auth` (LAContext via `objc2-local-authentication`; `evaluatePolicy` reply block bridged to a tokio oneshot via `block2::RcBlock`). LAError codes (-6 noSensor / -7 notEnrolled / -8 systemServiceMissing) map to the same `BiometricUnavailableReason` the Settings UI consumes. **Windows + Android remain on `local_auth`** — Windows because `KeyCredentialManager` / `UserConsentVerifier` need a real Windows runtime to verify; Android because `BiometricPrompt` requires a JNI bridge with Java-side hooks. **Apple verification pending on macOS / iOS hardware.** |
| `core/security/wipe_all_service.dart` | 223 | mostly already Rust-routed via `lfs_core::security::wipe` (file sweep + crash marker) and `lfs_core::wipe_keychain` (keychain purge). Remaining Dart-side concern is the `com.letsflutssh/hardware_vault` MethodChannel call — Tier 4 territory once the hw-vault plugin retires. |

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

### Tier 4 — Heavy native ports (~1 600 LOC, 3–4 weeks, **only on explicit go-ahead**)

| File | LOC | Replacement | Risk |
|---|---|---|---|
| `core/security/hardware_tier_vault.dart` | 404 | rewrite the per-platform `HardwareVaultPlugin.{swift,kt,cpp}` natives in Rust via `objc2` + Security framework / `windows-rs` + TBS API / JNI StrongBox | Apple ACL drift; Android JNI maintenance; Windows TBS edge-cases |
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
code is a debt to clear:

- `lib/platform/macos/code_signing/resign_service.dart:159, 162` —
  `// ignore: invalid_use_of_visible_for_overriding_member`. The
  `_DefaultKeychain implements Keychain` class reaches `keychainPath`
  / `runner` getters marked `@visibleForOverriding`, which the
  linter rejects across class boundaries. **Fix**: lift those
  getters out of `@visibleForOverriding` (make them part of the
  public `Keychain` contract) or restructure `_DefaultKeychain`
  to inherit rather than compose.
- `lib/app/global_error_dialog.dart:70` + `lib/providers/config_provider.dart:180` —
  `// ignore: unawaited_futures`. Replace with explicit
  `unawaited(...)` from `dart:async` so intent is in code, not in
  a linter directive.
- `lib/l10n/*.dart` (13 files) — `// ignore: unused_import`.
  Generated by `intl_utils`; not our code, leave alone.

### Oversized files — split into modules

Each file below is >1 000 LOC of human-written code; readability
+ test isolation suffer. Split each in a focused refactor arc:

| File | LOC | Suggested split |
|---|---|---|
| `lib/app/security_init_controller.dart` | 1 535 | per-tier sub-controllers (L1 / L2 / L3 / Paranoid) + corruption flow + first-launch flow as separate files |
| `lib/features/settings/settings_sections_security.dart` | 1 394 | tier-card builder + hw-vault remove flow + key-rotate flow as separate widgets |
| `lib/features/session_manager/session_edit_dialog.dart` | 1 358 | per-tab widgets (auth / advanced / port-forwards / snippets) |
| `lib/features/session_manager/session_panel.dart` | 1 264 | tree-view section + folder-actions section + bulk-ops section |
| `lib/widgets/expandable_tier_card.dart` | 1 120 | per-tier card variants |
| `rust/crates/lfs_core/src/archive.rs` | **2 362** | `archive::{encrypt, decrypt, apply, manifest, qr_compose}` submodules |
| `rust/crates/lfs_core/src/ssh/mod.rs` | 1 608 | acceptable (central SSH module — refactor only if a clean split appears) |

Effort per file: 0.5–1 day each, low-risk. Tests stay green
because the surface doesn't change — only file boundaries move.

### Test debt — skipped tests sweep (~18 tests)

Every skipped test today carries the rationale "Rust covered;
flutter_test runner has no FRB native lib". Three categories:

| File | Count | Disposition |
|---|---|---|
| `test/core/update/update_service_test.dart` | 7 | Move to `integration_test/` or delete (`lfs_core::update_orchestrator::tests` covers parse + asset selection + signed-manifest verify) |
| `test/core/session/session_recorder_test.dart` | 6 | Move to `integration_test/` (recorder open/write/close + encrypted variant; `lfs_core::recorder::queue::tests` covers the ring-buffer + worker) |
| `test/features/recordings/recording_reader_test.dart` | 3 | Move to `integration_test/` (HKDF + AES-GCM round-trip; `lfs_core::crypto::tests` covers KAT) |
| `test/providers/connection_provider_test.dart` | 1 | Investigate — single skip, may be obsolete |
| `test/features/mobile/mobile_shell_test.dart:823` | 1 | `skip: true` with no rationale string — investigate, likely obsolete after Apr-2026 grind |

Action: one consolidated arc — move every legitimate skip to
`integration_test/`, delete every redundant skip, document
remaining skips with bus-event-shape rationale. Brings the test
output back to a clean signal.

---

## Optimization backlog

Performance + footprint items, separate from migration. Run
`cargo build --timings` + a profiling pass before committing
any of these — measure twice.

### Bundle size — `liblfs_frb.so` = 19 MiB (release)

Heavy for a single shared object. Quick wins in `rust/Cargo.toml`
under `[profile.release]`:

```toml
[profile.release]
strip = true                 # drop debug symbols
lto = "fat"                  # whole-program LTO
codegen-units = 1            # slower link, smaller binary
panic = "abort"              # if no production catch_unwind
```

Heavy deps by `cargo tree -p lfs_core --depth 1` (for context):
`russh`, `russh-sftp`, `reqwest`, `zbus`, `zip`, `rusqlite`,
`regex`. Each is load-bearing — none is a candidate for removal
without a feature loss. The optimization is on the build profile,
not the dep set.

Target: pin a measured baseline (current 19 MiB) + a goal
(< 14 MiB after strip + LTO + codegen-units = 1).

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
[strategic gate — JNI maintenance buy-in?]
   ↓
Tier 4   (per-item, only with explicit justification)
```

Tier 1 and Tier 2 land regardless. The decision points before
Tier 3 / Tier 4 are real — neither is forced by the
"Flutter renders, Rust thinks" north star alone, both have
ongoing-cost trade-offs that need a deliberate yes.

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
2. **JNI maintenance cost** — every Android JNI surface (Tier 3
   AndroidKeystore + biometric, Tier 4 foreground service /
   storage permission) is one more place where Google's Java
   API breakage flows directly into our build. Mitigation: only
   take it on if the security or audit story justifies the
   ongoing cost. Tier 4 explicitly is opt-in.
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

1. **Drop the two `// ignore: invalid_use_of_visible_for_overriding_member`** in
   `lib/platform/macos/code_signing/resign_service.dart`. Restructure
   `_DefaultKeychain` so the linter is satisfied without the
   suppression.
2. **Replace the two `// ignore: unawaited_futures`** in
   `lib/app/global_error_dialog.dart` and
   `lib/providers/config_provider.dart` with explicit
   `unawaited(...)` calls.

### Next — Phase 6 Tier 1 (1–2 days, free wins)

3. `secret_buffer.dart` + `process_hardening.dart` +
   `libc_loader.dart` → `lfs_core::os_security` via `nix` /
   `libc`. Drops `dart:ffi` from the security module.
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

6. Move 16 Rust-covered skipped tests (update_service, recorder,
   recording_reader) to `integration_test/`; investigate the 2
   ad-hoc skips (connection_provider, mobile_shell). One
   consolidated arc, one PR.

### Parallel — refactor backlog (any time, low risk)

7. Split `rust/crates/lfs_core/src/archive.rs` (2 362 LOC) into
   `archive::{encrypt, decrypt, apply, manifest, qr_compose}`.
8. Split the four oversized Dart files (`security_init_controller`,
   `settings_sections_security`, `session_edit_dialog`,
   `session_panel`) — one file per arc, surface unchanged.

### Soon — Phase 6 Tier 2 (3–5 days)

9. Clipboard stack (`secure_clipboard` + `clipboard_secret`) →
   `arboard` crate; Android sensitive-flag stays MethodChannel.
10. `session_lock_listener` → `objc2` / `windows-rs` / zbus.
11. `backup_exclusion` → `objc2` Foundation `xattr`.
12. `linux/fprintd_client` → `zbus`.
13. ~~`core/sftp/file_system.dart` LocalFS → `tokio::fs` in
    `lfs_core::fs::local`.~~ Done — module landed with all
    six fs ops (`list`, `mkdir`, `remove`, `remove_dir`,
    `rename`, `dir_size`) plus `windows_hidden_names`; Dart
    keeps only `initialDir` (Flutter `path_provider` dep).
14. ~~OpenSSH config Include resolution + `ssh_dir_key_scanner` →
    `lfs_core::import::ssh_config`.~~ Done — Include + glob
    walk lives in `lfs_core::ssh_config::parse_openssh_config_with_fs`;
    `~/.ssh` directory scan lives in `lfs_core::ssh_dir_scan::scan`.
    `openssh_config_importer` (orchestration glue → ImportResult)
    deferred — its surface is mostly Dart-domain types
    (`Session`, `SshKeyEntry`, `ImportResult`); migrating it
    requires duplicating those types Rust-side, which adds
    FRB ceremony without a measurable correctness or perf win.
15. SFTP recursive walks (`uploadDir` / `downloadDir` /
    `removeDir`) → `lfs_core::sftp::recursive_walk`. Needs
    FRB Stream + cancellation wiring for progress callbacks
    — pre-req work before the move itself.

### Bundle size — single tweak arc (after Tier 2)

16. Tighten `[profile.release]` in `rust/Cargo.toml`:
    `strip = true` + `lto = "fat"` + `codegen-units = 1` +
    `panic = "abort"`. Measure size before / after; target
    < 14 MiB for `liblfs_frb.so`.

### Strategic gate — Phase 6 Tier 3 (1–2 weeks)

17. **Decision required before starting**: do we drop
    `flutter_secure_storage` + `local_auth` from `pubspec.yaml`?
    Pros: full control of cipher policy, smaller plugin
    attack surface, FIPS-validated suites. Cons: per-platform
    crate audit, CI matrix expansion (macOS / Windows / Android
    runners), ongoing maintenance of native bindings.
18. If yes: `secure_key_storage` + `biometric_key_vault` +
    `biometric_auth` + `wipe_all_service` → `security-framework`
    / `wincred` / `secret-service` / `objc2` / `windows-rs` / JNI.

### Strategic gate — Phase 6 Tier 4 (3–4 weeks, opt-in per item)

19. **Decision required before starting**: do we take on JNI
    maintenance for the Android-only paths? Per-item evaluation.
20. If yes (per item): `hardware_tier_vault` /
    `platform/macos/code_signing` / `macos_installer` /
    `foreground_service` / `qr_scanner` /
    `android_storage_permission`.

### Final — close the migration

21. Delete this file. Backend is fully in Rust; remaining Dart
    is widgets + Riverpod + permanent platform glue.
