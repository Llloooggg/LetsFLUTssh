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

## Architectural decisions (locked)

Six load-bearing decisions that gate the remaining arcs. Locked
on safety + best-practice priority — no field re-litigation,
arcs land against these as written.

### Decision 1 — Rust↔Dart prompt protocol

**Locked: extend `KnownHostPromptRegistry` per-prompt-type.**

Each prompt that needs Dart UI / Dart-plugin response gets:

- `BusEvent::XxxPromptRequest { req_id, ...typed payload }`
- FRB shim `xxx_prompt_response(req_id, ...typed response)`
- Per-type `PromptRegistry<XxxRequest, XxxResponse>` actor with
  `tokio::oneshot` per request

Why: race-free single-shot resolution; compile-time typed
contract per prompt (drift impossible); plaintext window stays
the same as the existing Dart `flutter_secure_storage.read()`
call; pattern already proven in production for the harder
russh `check_server_key` handshake-blocking case.

Rejected: generic JSON registry (loses compile-time safety) and
FRB callback type (reentrancy / deadlock risk on mutex paths,
already burned us in `connection_manager`).

### Decision 2 — Platform plugin paths (keychain / biometric / hardware vault)

**Locked: callback-up via Decision 1 for C2 / C5 / C6 /
biometric.** Plugins stay Dart; Rust actor publishes
`PluginRequest` event, Dart subscriber executes the
`flutter_secure_storage` / `local_auth` / per-platform
`MethodChannel` call, returns response via FRB.

**C3 (TPM CLI) is the only exception — subprocess via
Decision 3.** `tpm2-tools` is OS-installed binary, not a
Flutter plugin; subprocess driver is a discrete plugin
replacement that doesn't need a mature Rust crate.

Why: plaintext discipline window doesn't grow (credential
already lives in Dart heap during plugin call); audit
perimeter stays put (existing plugins audited a year+);
existing Dart tests for plugin paths keep working;
per-plugin migration to native Rust crate stays open without
blocking on full FFI matrix today.

Rejected: native Rust plugins per platform (5 platforms × 2-4
weeks of testing matrix the CI doesn't have); pure Dart with
no actor (can't lift orchestration into the tier machine).

### Decision 3 — Subprocess infra in `lfs_core`

**Locked: `tokio::process::Command` directly in `lfs_core`,
target-gated to Linux.**

Add `tempfile` from `dev-dependencies` to `dependencies`;
`tokio::process` is already pulled by `tokio` workspace dep.
Subprocess driver lives in `lfs_core::security::tpm_subprocess`
under `cfg(target_os = "linux")`.

Why: `lfs_core` already spawns `std::process::Command` (see
`path.rs:218` for `icacls` on Windows) — subprocess is an
existing pattern, not a new category. `tempfile` provides
auto-deleting `NamedTempFile` for the auth-value file the
TPM driver writes (cleanup-on-crash discipline). Plaintext
auth bytes never cross FRB.

Rejected: separate `lfs_subprocess` crate (overengineering for
single use case — YAGNI), Dart-side `Process.run` with Rust
business logic over bus (extra plaintext FRB crossings, looser
cleanup discipline).

### Decision 4 — Tier state machine actor scope

**Locked: scaffold-first + per-tier sub-machines under feature
gate.**

Sequence:
- [x] C9.0 — typed scaffold (state enum + event enum + transition
  table + 18 tests). Not wired to Dart — purely additive.
- [x] C9.0.1 — FRB shim exposing the scaffold so per-tier
  wiring commits target a stable Dart API. Process-singleton
  Machine instance behind a Mutex so dispatch is race-free
  across multiple Dart isolates.
- [x] C9.1 (Rust half) — `Machine::try_advance` fires
  `UnlockSucceeded` for Plaintext tier inside `Unlocking`
  (Plaintext is the only synchronous-resolve tier; Keychain /
  Hardware / Paranoid wait for their per-tier handler).
  `tier_machine_try_advance` FRB shim exposes the hook.
- [ ] C9.1 (Dart wiring) — Dart subscribes to
  `BusEvent::TierStateChanged`, dispatches
  `unlock_requested` + `try_advance` on bootstrap for
  Plaintext, runs `_injectDatabase()` on
  `TierStateChanged(unlocked)`. Behind
  `--dart-define=LFS_TIER_MACHINE_PLAINTEXT=true` until
  smoke-tested on every desktop.
- [ ] C9.2 — Keychain path (uses Decision 2 callbacks via
  Decision 1).
- [ ] C9.3 — Hardware path (uses C3 subprocess + Decision 2 for
  per-platform vault plugins).
- [ ] C9.4 — Paranoid path (uses C7 + master_password).
- [ ] C9.5 — Retire Dart `SecurityInitController` after every
  tier feature gate is on by default.

Why: 1167 LOC `SecurityInitController` is the single most
complex Dart orchestrator. Big-bang retire = all-eggs-one-basket
risk on the unlock flow; one regression = users can't open
their DB. Per-tier rolling lets each commit be retain-rollback-
able with feature gate; tests script per tier with FakeAppBus.

Rejected: big-bang full retire (risk profile incompatible with
solo-dev / no-E2E-CI shape), parallel actor permanently
coexisting (drift = anti-pattern).

### Decision 5 — App config Store actor (D4-D6)

**Locked: Rust actor owns debounce + atomic file I/O + bus
event.**

`lfs_core::config::Store` actor:
- In-memory: current `AppConfig` + dirty flag
- API: `get() -> AppConfig`, `update(updater)` (sync, schedules
  300ms debounce), `flush() -> Future<()>`
- Internal: `tokio::time::sleep` debounce, atomic write through
  existing `lfs_core::path::write_bytes_atomic`, publish
  `ConfigChanged` event after save
- Dart `ConfigNotifier`: thin shim — `update` calls FRB,
  subscribes to `ConfigChanged` for state refresh

**D4-D6 ungated from C9.** Per Decision 4, C9 is rolling
(per-tier feature gates), not one big arc. `AppConfig.security`
already routes through Rust mirror (D1-D3 done), so D4-D6 can
ship in parallel.

Why: single source of truth for config + debounce + persistence;
bus pattern uniformity (every other actor publishes
`XxxChanged` after mutation — config should match); atomic
write discipline already centralised; lost-write window on
crash (300ms) is inherent to debounce, equal across all
variants.

Rejected: split debounce/persistence across Dart/Rust (drift
risk on boundary), Dart-owned debounce + Rust per-save (loses
cache, every set = full write).

### Decision 6 — Export controller estimator retire (E)

**Locked: extract `compose_qr_payload` shared helper Rust-side,
estimator routes through it via typed FRB inputs.**

Extract `compose_qr_payload(input: QrPayloadInput) -> Value`
from `lfs_core::archive::qr_export_payload`. Production path
pulls from DB → builds typed input → calls helper. Estimator
path: Dart builds typed input via FRB → calls helper → returns
size only. Same `QrPayloadInput` struct, both producers.

Why: closes the recurring wire-shape drift (already burned us
once on `encodeSessionCompact`, fixed in F-arc, but the
pattern repeats for every section the estimator composes
Dart-side); plaintext exposure window doesn't grow (estimator
already sees password/key_data Dart-side for accurate sizing);
sync FRB call is fast enough (< 10ms for 100 sessions); test
discipline = one property-based test (random input → estimator
size == production size).

Rejected: DB-pull-per-toggle (UX regression — drag through
5 checkboxes = 500ms lag), permanent split (drift risk
indefinitely, F-arc proved this repeats).

## Tractable today vs needs-architectural-decision

**Closed in the current arc** (composite actor commands + helper
consolidations + schema mirrors + dedup-import composite):

- B1 — `db_sessions_duplicate_with_path` actor command
- B2 — `db_folders_rename_path_cascade` actor command (also fixed
  the moveFolder OLD-`parent_id` bug that silently failed cross-
  tree moves)
- B3 — `db_sessions_restore_snapshot` atomic actor command
- F1 — `update_asset_url_for_platform` helper consolidation
- F2 — `rate_limit_backoff_schedule_seconds` const exposure
- A1 — confirmed already done (`SessionCredentialCache` reads
  retired earlier; writes still route via `secretsPut` /
  `secretsDrop` FRB calls)
- D1 / D2 / D3 — `AppConfig` schema mirror (struct + JSON ser/de
  + sanitise + validate) lifted into `lfs_core::config`. Dart
  routes `toJson` / `toJsonForExport` / `fromJson` / `validate`
  through the canonical pipeline.
- C7 — `PersistedRateLimiter` actor (process-singleton with
  cached HMAC-verified state + tokio-spawned disk writes).
  Dart shim retains an in-memory state-machine fallback for
  flutter_test where path_provider is unmocked.
- `db_ssh_keys_import_for_merge` composite — folds `loadAll` +
  `findIdByKeyMaterial` + `uniqueLabel` + `save` into one Rust
  transaction; uses pre-hashed `list_metadata` to dedup by
  fingerprint without pulling PEMs through FRB.

**Closed-enough as thin façades** — full retire would be churn:

- B4 — `SessionStore` retire. The store is already a registry
  mirror (cache hydrates from `sessionsRegistrySnapshot`, bus
  events trigger reload). Touching the ~25 call sites across
  providers / dialogs / tests for marginal gain is not worth it.
- C1 — `MasterPasswordManager` retire. Already a thin façade;
  `_basePath` resolution stays Dart because `getApplicationSupportDirectory`
  is a `path_provider` plugin call.
- F3 — `_compileGlob` regex cache. Lives in the Dart fallback
  only; production already routes through `glob_matches`.

**Needs an architectural decision before the next coding pass:**

- A2/A3/A4 — ConnectionManager full retire. Bastion-readiness
  await + credential overlay + reconnect cascade in Rust requires
  designing how russh callbacks (`check_server_key`, auth
  prompts) hand off to the Dart UI. The `KnownHostPromptRegistry`
  arc shows the pattern, but the credential-prompt surface is
  larger.
- C2 — `KeychainPasswordGate` runtime as actor. Needs flutter_secure_storage
  callbacks Rust→Dart (or moving the keychain reads into a Rust
  platform plugin matrix).
- C3 — `HardwareTierVault` Linux composer. Needs `tpm2-tools`
  subprocess driver in Rust + decision on whether the Apple /
  Android / Windows method-channel plugins similarly migrate.
- C5 — `SecurityBootstrap.probeCapabilities` cache as actor.
  Same callback question — biometric / fprintd / hardware-vault
  probes are platform plugin calls.
- C9 — Tier state-machine actor. Gated on C2 / C3 / C5 / C7.
- D — `app_config` actor. Gated on C9 (security_tier types
  couple in).
- E — `unified_export_controller` full retire. The live size
  estimator already routes the deflate + base64url through Rust;
  retiring the Dart JSON-build orchestration requires Rust
  mirrors of `Tag` / `Snippet` / `AppConfig` / `SshKeyEntry`
  shapes (overlaps with arc D's app_config port).

Each of these arcs is a 5-10 commit multi-day effort and benefits
from explicit user direction on the design tradeoffs (which
plugin paths stay Dart, which migrate to Rust subprocess /
platform-matrix, what callback shape the Rust-Dart prompt
protocol uses).

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

### C7 — `PersistedRateLimiter` (~429 LOC) [DONE]

HMAC-frame + cache + serialised disk-write coordination all
Rust-side. The Dart `PersistedRateLimiter` shrank to a thin
shim with a Dart state-machine fallback for flutter_test
contexts that don't load the FRB native lib (path_provider
unmocked).

- [x] C7.1 — `lfs_core::security::persisted_rate_limit_actor::
  PersistedRateLimiterRegistry` process-singleton actor.
  `init_or_get(id, file_path, hmac_key)` loads + HMAC-verifies
  on-disk; subsequent `status` / `record_failure` /
  `record_success` / `clear` route through the cached entry.
  Disk writes via `tokio::spawn_blocking`. Tampered files clamp
  to max-cooldown slot.

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

## Arc D — `app_config` (~605 LOC) [partial]

**Originally gated on C9** because `SecurityConfig` types couple
in. The schema mirror landed ahead of C9 because the typed
struct + JSON ser/de + sanitise rules are usable independently;
the `Store` actor + bus event remain pending until C9 lands and
the persistence layer routes through Rust.

- [x] D1 — `lfs_core::config::AppConfig` + mirrors of
  `TerminalConfig` / `SshDefaults` / `UiConfig` /
  `BehaviorConfig`. JSON ser/de + sanitise + per-field validate;
  flat top-level wire shape preserved. Dart `AppConfig.toJson` /
  `toJsonForExport` route through the canonical Rust encoders.
- [x] D2 — `AppConfig.fromJson` routes through Rust sanitise
  pipeline (clamp out-of-range + drop unknown tier / locale).
- [x] D3 — `AppConfig.validate` routes through Rust validation
  chain (terminal → ssh → ui → workers → history). English
  error strings stay placeholders that the Settings UI translates
  via `app_*.arb` validation keys.
- [x] D4/D5 — `lfs_core::config_store::Store` actor (init /
  get / set / flush / tick_if_due). Owns 300 ms debounce + atomic
  write through `write_bytes_atomic` + bus event publication.
  FRB sync shims expose the API. 13 Rust unit tests +
  `BusEvent::ConfigChanged { json }` event variant.
- [x] D6 — Dart `ConfigStore.save` routes through Rust actor's
  `set_json + flush` so the explicit save semantic ("save now")
  goes through the canonical pipeline. Inline `writeFileAtomic`
  preserved for flutter_test contexts.
- [ ] D6.2 — Dart `ConfigNotifier` debounce timer ⇒ Rust
  actor's `tick_if_due`. Bus subscription instead of in-Notifier
  state mutation. Pending — current Dart debounce works
  correctly, refactor adds risk without adding safety.

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
| [x] `assetUrlForPlatform`          | `update_service.dart:797`                 | Routed through `lfs_core::update_metadata::asset_url_for_platform`. |
| —    `_compileGlob` regex cache     | `openssh_config_parser.dart:248`          | Cache lives in the Dart fallback only; production already routes through Rust. Removing the cache slows the test-only path with no production benefit — skip. |
| [x] `backoffSchedule` constant     | `password_rate_limiter.dart:35`           | Hydrated from Rust `BACKOFF_SCHEDULE` via FRB const, lazy-cached. |
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
