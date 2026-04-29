# Rust migration — remaining work

Live tracker for the closing arcs. Replaces the open-ended
inventory in [`RUST_MIGRATION_NEXT_PLAN.md`] with a focused punch
list of what's left, sequenced for landing one arc at a time.
Delete both files once every arc closes.

[`RUST_MIGRATION_NEXT_PLAN.md`]: ./RUST_MIGRATION_NEXT_PLAN.md

## Inventory (LOC budget)

| Category                                          | LOC Dart | Action       |
|---------------------------------------------------|---------:|--------------|
| 1. Big orchestrator actors with real logic        |  ~3 200  | arcs A + B   |
| 2. Security tier stack (orchestrators + persist)  |  ~2 800  | arc C        |
| 3. `app_config` schema + persistence              |    ~700  | arc D        |
| 4. UI/controllers with duplicated logic           |    ~700  | arc E        |
| 5. Pure helpers not yet consolidated              |    ~150  | arc F        |
| 6. Stays Dart by design                           |  ~3 500  | leave alone  |

Total to move: ~6 850 LOC. Roughly 40–50 commits across all arcs.

## Sequence

```
B  — SessionStore mutating-paths cutover           (4–6 commits, isolated)
A1 — SessionCredentialCache → SecretStore          (1 commit, security fix)
A  — ConnectionManager full retire                 (5–8 commits, after B)
C  — security tier stack
   C1+C2+C5+C6+C7 — shims + bootstrap probes       (8–10 commits)
   C9             — tier state-machine actor       (3–5 commits, after C1–C7)
D  — app_config                                    (4–6 commits, after C9)
E  — unified_export_controller live size estimate  (3–4 commits, anytime)
F  — pure helpers                                  (~6 commits, background)
```

## Arc B — `SessionStore` mutating-paths cutover

**Status:** in progress (read accessors landed; cache write fix landed).

**Owns Dart-side today** (`lib/core/session/session_store.dart`,
884 LOC):

- 17 mutation methods (`add` / `update` / `delete*` / `move*` /
  `duplicateSession` / `restoreSnapshot` / folder ops) already
  call FRB DAOs but composite ops (`duplicate` + dedup,
  `restoreSnapshot` cascade, folder rename cascade) compose the
  steps Dart-side.
- `_loadFuture` / `_doLoad` cache lifecycle (sync hydrate from
  `sessionsRegistrySnapshot`).

**Rust-side ready:** `lfs_core::sessions::Registry` actor,
snapshot / filter / count read paths, `SessionsChanged` bus,
mutating DAOs notify on every successful write.

**Remaining commits:**

- [x] B1 — `session_duplicate` actor command (Rust composes
  unique-label dedup + DAO insert + notify in one transaction).
  Dart `SessionStore.duplicateSession` is now a single FRB call.
- [x] B2 — `folder_rename_cascade` actor command (composite rename
  + cross-tree re-parent inside one transaction; fixes the Dart
  bug where `moveFolder` carried the OLD `parent_id`). Dart
  `renameFolder` / `moveFolder` shrunk to one FRB call.
- [x] B3 — `session_restore_snapshot` actor command (atomic
  delete-all + folder-tree rebuild + per-session insert in one
  transaction). Dart `restoreSnapshot` shrunk to one FRB call.
- [ ] B4 — `SessionStore` retire **deferred**. The store is
  already a registry mirror (cache hydrates from
  `sessionsRegistrySnapshot`, bus events trigger reload). A full
  retire would touch ~25 call sites across providers / dialogs /
  tests; current shape is acceptable as a thin Dart façade. Revisit
  if registry consumers diverge or the Dart cache drifts.

**Risk:** folder-cascade ordering bugs (rename + collapsed-set
sync). Mitigate with property-based tests on the Rust side
before B4.

## Arc A — `ConnectionManager` actor

**Status:** generation counter + active-count tracking already
Rust-side; transient SecretStore IDs evicted on terminal state.

**Owns Dart-side today** (`lib/core/connection/connection_manager.dart`,
832 LOC):

- `_doConnect` orchestration (lines 181–365) — bastion-await +
  ProxyJump cascade + auth resolution + adopt phase.
- `_authFromConfig` (line 464) — credential overlay precedence
  (per-session cache → cached passphrase → typed) + transient
  SecretStore staging.
- `_adoptConnectedSession` — registry mirror + bus subscription
  wiring.
- Reconnect cascade.

**Rust-side ready:** `lfs_core::connection::Registry` with actor
+ state machine + ProxyJump + `connected_user_visible_count` +
`ConnectionActiveCountChanged` bus event.

**Remaining commits:**

- [x] A1 — `SessionCredentialCache` through
  `lfs_core::secrets::SecretStore` — already done. Read-side
  retired (every `read*` accessor returned null once `SecretStore`
  became canonical, the overlay collapsed to a no-op).
  Write-through still goes via `secretsPut` / `secretsDrop` FRB
  calls. The Dart `SessionCredentialCache` class survives as a
  thin namespace-aware wrapper consumed by ConnectionManager +
  WipeAllService.
- [ ] A2 — Bastion-readiness await moves into Rust
  `connect_async`'s pre-auth phase (today Dart does
  `await conn.bastion!.waitUntilReady()`). (2 commits)
- [ ] A3 — `prepare_auth` Rust-side composer for credential
  overlay. (2 commits)
- [ ] A4 — `connection_connect_async` / `connection_reconnect`
  / `connection_disconnect` / `connection_disconnect_all` FRB
  surface; Dart `ConnectionManager` deletes; `Connection` Dart
  class shrinks to a FRB-DTO mirror with no setters;
  `connectionListProvider` becomes a `StreamProvider`. (3 commits,
  test-risk high)

**Risk:** reconnect cascade through auto-lock relies on the
in-memory credential cache. A1 must land first.

## Arc C — Security tier stack

**Status:** every persisted artefact has its on-disk format
Rust-owned. Tier state-machine actor still pending.

**Sub-arcs by independence:**

### C1 — `MasterPasswordManager` retire (~263 LOC)

Already a thin façade — every op delegates to `master_password_*`
FRB calls. Remaining: rate-limiter wrapper +
`getApplicationSupportDirectory` resolution.

- [ ] C1.1 — Move `support_dir` resolution into a one-shot
  `master_password_init(support_dir)` call instead of passing it
  per-call.
- [ ] C1.2 — `MasterPasswordException` localised messages stay
  Dart; the Dart wrapper retires.

### C2 — `KeychainPasswordGate` runtime (~230 LOC)

Crypto already Rust-side. Remaining: file I/O + flutter_secure_storage I/O orchestration.

- [ ] C2.1 — `keychain_password_gate_set` / `verify` / `clear`
  actor commands that own the disk-blob + pepper-key write
  ordering invariant (disk before keychain, atomic disk write).
  Dart wrapper shrinks to FRB calls + flutter_secure_storage
  delegation as a callback the Rust actor invokes.

### C3 — `HardwareTierVault` Linux composer (~407 LOC)

TPM CLI shell-out (`tpm2-tools`) → Rust subprocess; method-channel
platforms stay Dart.

- [ ] C3.1 — `lfs_core::security::tpm_subprocess` driver wrapping
  `tpm2-tools` invocations.
- [ ] C3.2 — `hardware_tier_vault_linux_*` FRB shims; Dart Linux
  branch shrinks to FRB calls. Method-channel platforms unchanged.

### C5 — `SecurityBootstrap.probeCapabilities` (~404 LOC)

Async probes through D-Bus / platform plugins. State can move
into a Rust actor that caches the snapshot.

- [ ] C5.1 — `lfs_core::security::capabilities_probe::Cache`
  actor; FRB `capabilities_probe_run` + `capabilities_view`.
  Dart `probeCapabilities` retires; provider subscribes.

### C6 — `WipeAllService` (~210 LOC)

File-half already Rust-side. Remaining: `MethodChannel`
invocations + flutter_secure_storage purge.

- [ ] C6.1 — `wipe_keychain_purge` FRB shim that owns the
  flutter_secure_storage key list (versioned alongside the
  vault). Dart wrapper retires.

### C7 — `PersistedRateLimiter` (~429 LOC)

HMAC-frame already Rust-side. Remaining: file I/O + in-memory
cache.

- [ ] C7.1 — `persisted_rate_limit_actor` owns state +
  on-disk frame; FRB `rate_limit_status` /
  `rate_limit_record_failure` / `rate_limit_record_success`.
  Dart `PersistedRateLimiter` shrinks to FRB calls.

### C9 — Tier state-machine actor (final synthesis)

`lfs_core::security::tier::Machine` actor:
`Plaintext | Keychain | Hardware | Paranoid` transitions, unlock
requested/succeeded/failed events.

- [ ] C9.1 — Actor scaffold + state transitions + bus events.
- [ ] C9.2 — Compose master-password / keychain-gate / hardware-
  vault / wipe orchestrators behind the actor.
- [ ] C9.3 — `security_provider.dart` (462 LOC) → `StreamProvider`
  mirror. `security_bootstrap.dart` orchestration retires.

**Risk:** highest of the migration. Land on a focused branch,
smoke on every platform before merge.

## Arc D — `app_config` (~605 LOC)

**Gated on C9** because `SecurityConfig` types couple in.

- [ ] D1 — `lfs_core::config::AppConfig` + serde mirrors of every
  sub-struct (`TerminalConfig` / `SshDefaults` / `UiConfig` /
  `BehaviorConfig`).
- [ ] D2 — `lfs_core::config::Store` reads / persists via the
  `app_configs` table (already in `lfs_core.db`).
- [ ] D3 — FRB `config_get` / `config_update` + bus
  `ConfigChanged` event.
- [ ] D4 — Dart `core/config/app_config.dart` shrinks to FRB DTOs
  + a `StreamProvider<AppConfig>` over the bus topic.

**Risk:** every config read crosses FRB. Mitigate by emitting
`ConfigChanged` on writes only; reads return cached snapshot.

## Arc E — `UnifiedExportController` live size estimation

**Owns Dart-side today** (`lib/widgets/unified_export_controller.dart`,
708 LOC):

- `_deduplicateKeys` / `_addAllManagerKeys` /
  `_encode*Payload` orchestration for live "fits in QR" gauge.
- Pre-toggle dummy-session + key-only delta + per-option size
  estimate.

**Rust-side ready:** `qr_codec_compress_to_payload_size` (sync
sizing endpoint). Production export already through
`dbExportQrPayload`.

- [ ] E1 — `qr_export_estimate_size(opts, session_ids,
  manager_keys)` Rust-side that mirrors `dbExportQrPayload` but
  returns only the byte count (no archive build).
- [ ] E2 — Dart controller drops `_deduplicateKeys` /
  `_addAllManagerKeys` / `_encode*Payload`; keeps only UI state +
  the FRB sizing call.

## Arc F — Pure helper consolidations

| Helper                             | Current location                          | Notes                                                            |
|------------------------------------|-------------------------------------------|------------------------------------------------------------------|
| [ ] `assetUrlForPlatform`          | `update_service.dart:797`                 | Move to `lfs_core::update_metadata` (already has `asset_suffix`) |
| [ ] `_compileGlob` regex cache     | `openssh_config_parser.dart:248`          | Already routed through `glob_matches`; drop the Dart cache.      |
| [ ] `backoffSchedule` constant     | `password_rate_limiter.dart:35`           | Expose `BACKOFF_SCHEDULE` via FRB const.                          |
| [ ] `_unquote` (OpenSSH config)    | `openssh_config_parser.dart:337`          | Trivial, low priority.                                           |
| —    `OpenSshConfigImporter.expandHome` | `openssh_config_importer.dart:72`    | Skip — Android `EXTERNAL_STORAGE` divergence vs Rust `home_dir`. |
| —    `_tierToString` / `_tierFromString` | `security_tier.dart:247,262`         | Skip — 5-line switches; routing through Rust adds no value.      |

## Stays Dart by design (~3 500 LOC)

- `lib/widgets/**`, `lib/screens/**`, `lib/dialogs/**` —
  rendering only.
- `lib/providers/**` — `StreamProvider` over bus topics after
  arcs A / B / C land.
- `core/connection/foreground_service.dart` (191) — Android
  binding.
- `core/security/biometric_auth.dart` (314) — `local_auth` UI
  prompt.
- `core/security/biometric_key_vault.dart` (255) —
  flutter_secure_storage + per-platform plugin.
- `core/security/secure_key_storage.dart` (376) —
  flutter_secure_storage wrapper.
- `core/security/secure_clipboard.dart` (81) — MethodChannel.
- `core/security/clipboard_secret.dart` (99) — Android
  sensitive-flag MethodChannel.
- `core/security/process_hardening.dart` (172) — `dart:ffi`
  (Rust port would require disabling the crate's
  `unsafe_code = "forbid"` rule).
- `core/security/terminal_scrubber.dart` (88) — xterm-bound.
- `core/security/session_lock_listener.dart` (88) — platform
  listener.
- `core/security/wipe_all_service.dart` (210) — MethodChannel
  + flutter_secure_storage purge (the file-half already Rust).
- `core/single_instance/single_instance.dart` (85) — IPC
  socket.
- `core/qr/qr_scanner.dart` (36) — `mobile_scanner` plugin.
- `core/sftp/file_system.dart` (220) — file picker /
  share_plus.
- `core/db/rust_db_init.dart` (88) — `path_provider`.
- `core/security/libc_loader.dart` (30) — `dart:ffi` loader.

## Testing strategy per arc

- Each arc lands with Rust unit tests + property-based tests
  where state-machine ordering matters (folder cascade, tier
  transitions, queue scheduler).
- Dart-side: widget tests subscribe to a `FakeAppBus` test
  harness that replays scripted events. No Dart-side state
  mocking — there is no Dart-side state to mock.
- Integration test per arc: real `lfs_frb` lib loaded, real
  bus, real DAOs, scripted command sequence, asserted event
  sequence.
