# Rust migration — remaining work

Live tracker for the closing arcs. Replaces the open-ended
inventory in [`RUST_MIGRATION_NEXT_PLAN.md`] with a focused punch
list of what's left, sequenced for landing one arc at a time.
Delete both files once every arc closes.

[`RUST_MIGRATION_NEXT_PLAN.md`]: ./RUST_MIGRATION_NEXT_PLAN.md

## Inventory (LOC budget)

| Category                                          | LOC Dart | Action       |
|---------------------------------------------------|---------:|--------------|
| 1. Big orchestrator actors with real logic        |  ~2 400  | arcs A + B   |
| 2. Security tier stack (orchestrators + persist)  |  ~1 500  | arc C        |
| 3. `app_config` schema + persistence              |    ~700  | arc D        |
| 4. UI/controllers with duplicated logic           |    ~700  | arc E        |
| 5. Pure helpers not yet consolidated              |    ~150  | arc F        |
| 6. Stays Dart by design                           |  ~3 500  | leave alone  |

Categories 1 + 2 dropped substantially after the security-tier-stack
arc landed: every per-tier verify, first-launch persist, and unlock
cascade now lives Rust-side. The residual surface in
`SecurityInitController` (1538 LOC) + `ConnectionManager` (660 LOC) +
`SessionStore` (757 LOC) is Dart-side glue (Riverpod / drift /
plugins / navigation / undo-history) that legitimately can't move
without dragging Flutter primitives along.

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

**Locked: subprocess driver lives directly in `lfs_core`,
Linux-target-gated, async exposed via `spawn_blocking` at the
FRB boundary.**

Driver lives in `lfs_core::platform::linux::tpm` (alongside the
existing `fprintd` D-Bus shim — same Linux-only platform
namespace, not in `security/`). Implementation uses
`std::process::Command` + an internal `mpsc` timeout thread
rather than `tokio::process` because (a) the rest of the
`platform/macos/process.rs` file already does the same, (b) the
TPM crypto core is fundamentally serial — once-per-unlock — so
non-blocking I/O buys nothing and a blocking caller is easier
to audit, (c) the FRB shim wraps every call in
`tokio::task::spawn_blocking` (matching the keygen shim
pattern), so the FRB worker thread never stalls.

`tempfile` is NOT used — the driver ships a hand-rolled RAII
`WorkDir` that zero-overwrites every file before unlink, which
the off-the-shelf `tempfile::TempDir` does not do.

Why: `lfs_core` already spawns `std::process::Command` (see
`path.rs:218` for `icacls` on Windows, and
`platform/macos/process.rs` for the macOS auth helper) —
subprocess is an existing pattern, not a new category.
Plaintext auth bytes never cross FRB twice (single hop into the
shim, written to a 0600 file inside the RAII work dir, passed
to `tpm2-tools` as `file:<path>` so they never appear in
`/proc/<pid>/cmdline`).

Rejected: separate `lfs_subprocess` crate (overengineering for
single use case — YAGNI); Dart-side `Process.run` with Rust
business logic over bus (extra plaintext FRB crossings, looser
cleanup discipline); `tokio::process::Command` (no concurrency
win on a serial-by-hardware op, and the spawn_blocking wrapper
is a one-line cost at the boundary).

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
- [x] C9.1 (Dart wiring) — Plaintext path observed by actor.
  `_routePlaintextThroughTierMachine` calls `set_tier` +
  `dispatch unlock_requested` + `try_advance`. Dart still owns
  `_injectDatabase()`; the actor sees the cascade and the
  `BusEvent::TierStateChanged` fans out to the diagnostic
  observer.
- [x] C9.2 — KeychainWithPassword + Keychain paths observed
  by actor via `_emitTierUnlockStart` / `_emitTierUnlockResolved`
  helpers. Failure discriminants map to `plugin_unavailable` /
  `user_cancelled`.
- [x] C9.3 — Hardware path observed. Failure discriminants
  map to `plugin_unavailable` / `corruption` / `user_cancelled`.
- [x] C9.4 — Paranoid path observed. Failure discriminant maps
  to `user_cancelled` (master-password reset).
- [x] C9.5 — Per-tier unlock + first-launch handlers moved into
  Rust orchestrators (`tier_unlock_orchestrator::{unlock,first_launch}_*`).
  Each orchestrator stages the resolved DB key under
  `TIER_UNLOCK_KEY_ID` + emits the tier_machine cascade; the
  `TierUnlockedListener` Dart provider takes the bytes via
  `secrets_take` on `BusEvent::TierStateChanged.unlocked` and
  runs the post-unlock cascade (caches, drift open,
  securityStateProvider, config persist). Plaintext discipline:
  key bytes cross FRB exactly once per cascade (the
  `secrets_take` round-trip), no longer through orchestrator
  return values. Multi-attempt dialog tiers (L2/L3/Paranoid)
  arm the listener with `onlyUnlocked: true` so per-attempt
  `Locked` events from wrong-secret retries don't resolve the
  wait; the dismiss path resolves explicitly via `cancelPending`.
  Biometric fast-path uses `tier_unlock_biometric_commit` which
  stages bytes + emits cascade in one shot, so the listener
  runs uniformly for typed-secret and biometric paths. L3
  first-launch uses a new `hardware_vault_seal_prompt` registry
  mirroring the unlock-prompt shape. `SecurityInitController`
  shrunk from ~1700 to ~1605 LOC; the residual surface is
  Dart-side glue (lifecycle, migration runner, wizard,
  corruption recovery, DB inject) that legitimately can't move
  into Rust without dragging Drift, Riverpod, navigation, and
  platform plugins along — full delete is unreasonable.

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

**Closed after the decision lock** (decisions 1-6 implemented):

- C9.0 — typed tier_machine scaffold + 18 tests; FRB shim
  + bus event publication on every transition; per-tier
  handler hook (`try_advance` for Plaintext self-advance)
- E1-E4 — qr_compose helper extracted; FRB shim for live
  size estimator; main + per-toggle delta estimators routed
  through Rust composer (every section now contract-tied
  against the production export wire shape)
- D5/D6 — config_store actor (init/get/set/flush/tick + 13
  tests + bus ConfigChanged event); Dart ConfigStore.save
  routes through actor's set_json + flush
- Decision-1 prompt-protocol foundations (purely additive,
  per-prompt-type typed registries):
  - keychain_pepper_prompt — for C2 L2 gate
  - credential_prompt — for A3 connection auth
  - biometric_probe_prompt — for C5 capabilities cache
  Each gets bus event variant + FRB resolve/cancel shims +
  process-singleton instance + 5-6 unit tests.

**Closed in the prior arc** (composite actor commands + helper
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

**Thin Dart façades that still need a final retire pass:**

- B4 — `SessionStore` retire. The store is already a registry
  mirror (cache hydrates from `sessionsRegistrySnapshot`, bus
  events trigger reload). ~25 call sites across providers /
  dialogs / tests need a final retire pass.
- C1 — `MasterPasswordManager` retire. Already a thin façade;
  `_basePath` resolution stays Dart because
  `getApplicationSupportDirectory` is a `path_provider` plugin
  call.
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
- [ ] B4 — `SessionStore` retire. The store is already a
  registry mirror (cache hydrates from
  `sessionsRegistrySnapshot`, bus events trigger reload).
  Touches ~25 call sites across providers / dialogs / tests.

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
- [x] A2 — `lfs_core::connection::wait_for_parent_ready(parent_id)`
  subscribes to the bus, snapshots the parent actor's state,
  awaits the next `ConnectionStateChanged` for the parent
  until it settles into `Connected` (proceed) or `Disconnected`
  (fail with a typed "ProxyJump parent failed" error). 30 s
  timeout matches the SSH banner ceiling so a wedged parent
  doesn't burn the unlock spinner forever. Race-free:
  subscribe-then-snapshot avoids the lost-update window. The
  Dart `_doConnect` keeps `bastion.waitUntilReady()` as a
  best-effort no-op for flutter_test contexts that don't load
  the FRB native lib (the in-memory completer keeps the test
  bastion graph drainable without a fake event bus); the
  failure-branch logic moves Rust-side and surfaces via the
  same `connectionConnect` error path the rest of the connect
  cascade uses.
- [x] A3 — `lfs_core::connection::auth_compose::prepare_auth`
  composes the saved-session-staged → manager-key-staged →
  quick-connect-fallback walk in one place. Reads sqlite
  columns + stages every byte into the `SecretStore` inside
  Rust; returns the typed `PreparedAuthRef` (`Password` /
  `Pubkey`) plus the list of transient store ids the caller
  drops after the connect attempt settles. FRB shim
  `connection_prepare_auth(input)` returns the wire DTO.
  Dart `_authFromConfig` routes through the FRB composer by
  default; the inline pipeline stays in place as the
  flutter_test fallback (no FRB native lib loaded). 8 unit
  tests cover the precedence walk + transient-id bookkeeping.
- [~] A4 — partial. The four FRB endpoints already exist
  (`connection_connect`, `connection_reconnect`, etc., served
  by the bus dispatcher). The Dart-side retire is incremental:
  - [x] A4.1 — `Connection` class self-subscribes to the
    per-id connection bus topic and feeds its own
    `progressStream` from `BusEvent::ConnectionProgress`
    events via the shared `connection_step_mappers`. The
    manager's `_applyConnectionEvent` no longer fans out
    progress steps; only the failed-step log line remains
    (kept for support traces). Connection now exposes a
    `dispose()` that cancels the bus subscription + closes
    the controller; the manager calls it from `disconnect` /
    `disconnectAll` so a removed connection stops consuming
    events.
  - [x] A4.2 — Transport adoption + per-attempt transient-secret
    eviction live inside `Connection` itself. The bus listener
    now also handles `BusEvent::ConnectionStateChanged`:
    `Connected` → spawn `connection_get_session(id)` async,
    wrap in `RustTransport.adopt`, fire `notifyExtensionsConnected`,
    evict transients via the batched `secretsDropMany` shim;
    `Disconnected` → clear transport + evict. The manager's
    `_adoptConnectedSession` and `_evictTransientSecrets`
    helpers retire entirely. `Connection.dispose()` now also
    runs the eviction as a belt-and-braces against the
    explicit-disconnect race where the bus subscription is
    cancelled before the terminal-state event lands.
  - [ ] A4.3 — `ConnectionManager` deletes;
    `connectionListProvider` becomes a pure `StreamProvider`
    sourcing from `connection_snapshot_all` + bus events.
    Workspace UI provider graph rebuilds against the new
    shape.

## Arc C — Security tier stack

**Status:** every persisted artefact has its on-disk format
Rust-owned. Tier state-machine actor still pending.

**Sub-arcs by independence:**

### C1 — `MasterPasswordManager` retire (~263 LOC)

Already a thin façade — every op delegates to `master_password_*`
FRB calls. Remaining: rate-limiter wrapper +
`getApplicationSupportDirectory` resolution.

- [x] C1.1 — `master_password_init(support_dir)` FRB shim pins
  the path inside an `OnceLock<PathBuf>` Rust-side; subsequent
  ops (`is_enabled`, `enable`, `change`, `disable`, `reset`,
  `derive_key`, `verify_and_derive`) read from the singleton
  instead of taking the path per call. Dart
  `MasterPasswordManager._getBasePath` resolves once via
  `getApplicationSupportDirectory()` and forwards to the init
  shim; consumers stay unchanged.
- [ ] C1.2 — `MasterPasswordException` localised messages stay
  Dart; the Dart wrapper retires.

### C2 — `KeychainPasswordGate` runtime (~230 LOC)

Crypto already Rust-side. Remaining: file I/O + flutter_secure_storage I/O orchestration.

- [x] C2.1 — Verify path: `keychain_password_gate_actor::verify_password`
  composes disk-blob read + Decision-1 pepper-prompt round-trip
  + HMAC compare; FRB async shim + Dart `verify()` route
  through Rust with the existing inline pipeline as fallback.
- [x] C2.2 — `is_configured` / `set_password` / `clear` actor
  commands. Disk side (atomic write, rollback on keychain
  failure, rate-limit-state wipe, file deletes) lives in
  `keychain_password_gate_actor`; the Dart side is reduced to
  a generic `keychain_op_prompt` registry that handles the
  `containsKey` / `write` / `delete` `flutter_secure_storage`
  calls via bus prompts. Disk-before-keychain ordering +
  rollback-on-keychain-write-failure preserved. Dart
  `KeychainPasswordGate.{isConfigured,setPassword,clear}`
  routes through Rust with the inline Dart pipeline as the
  flutter_test fallback. The same `keychain_op_prompt`
  registry will host C6's wipe enumeration too.

### C3 — `HardwareTierVault` Linux composer (~407 LOC)

TPM CLI shell-out (`tpm2-tools`) → Rust subprocess; method-channel
platforms stay Dart.

- [x] C3.1 — `lfs_core::platform::linux::tpm` driver wrapping
  `tpm2-tools` invocations: classified `probe()`, `seal()`,
  `unseal()`, RAII `WorkDir` with zero-overwrite-on-drop,
  `file:<path>` auth-value handoff so the HMAC never crosses
  argv. Sync core + async FRB boundary via `spawn_blocking`
  (see Decision 3 update).
- [x] C3.2 — `lfs_frb::api::tpm` async shim (`tpm_probe` /
  `tpm_seal` / `tpm_unseal`); Dart `TpmClient` routes through
  the FRB shim by default, retains the inline `Process.run`
  pipeline as a fallback for flutter_test contexts that don't
  bootstrap `RustLib`. `_FakeTpm` test substitutes still
  satisfy the `TpmClient` interface — no test changes needed.

### C5 — `SecurityBootstrap.probeCapabilities` (~404 LOC)

Async probes through D-Bus / platform plugins. State moves into
a Rust actor that caches the snapshot; the Rust-orchestrated
re-probe (which fans out prompt-registry round-trips per probe)
lands incrementally per Decision 4 scaffold-first discipline.

- [x] C5.1 — `lfs_core::security::capabilities_cache::Cache`
  process-singleton actor. FRB shims:
  `security_capabilities_view` (sync), `security_capabilities_set`
  (sync), `security_capabilities_clear` (sync).
  `BusEvent::SecurityCapabilitiesChanged { json }` published on
  every set-that-differs + on explicit clear (with empty JSON).
  Dart `probeCapabilities` pushes the snapshot into the cache
  after running the existing platform plugin probes — provider
  / Settings cards can subscribe today; the Rust-orchestrated
  re-probe slots in via C5.2 without changing the FRB surface.
- [x] C5.2 — `lfs_core::security::capabilities_orchestrator::run`
  fans out four probes concurrently via `tokio::join!`:
  biometric (existing prompt registry), keychain
  (`keychain_probe_prompt`, new), hardware-vault
  (`hardware_vault_probe_prompt`, new — non-Linux only), and
  Linux fprintd (in-process via
  `lfs_core::platform::linux::fprintd::has_enrolled_fingers`).
  Per-probe 5 s timeout collapses stuck D-Bus calls /
  unresponsive plugins to the matching "unavailable" answer.
  Snapshot is pushed through `capabilities_cache::Cache::set`
  on every successful run; the cache fires
  `BusEvent::SecurityCapabilitiesChanged` on a delta.
  FRB shim `capabilities_probe_run(is_linux_host)` returns the
  snapshot DTO so the Dart caller doesn't need a follow-up
  view call. Dart `probeCapabilities` routes through the FRB
  orchestrator by default; the inline platform-plugin pipeline
  stays in place as the flutter_test fallback (no FRB native
  lib loaded). New Dart subscribers
  `KeychainProbePromptListener` +
  `HardwareVaultProbePromptListener` delegate to the existing
  `SecureKeyStorage.probe()` / `HardwareTierVault.probeDetail()`
  helpers — the orchestrator just routes the call through Rust
  for the cache discipline + bus fan-out.

### C6 — `WipeAllService` (~210 LOC)

File-half already Rust-side. Remaining: `MethodChannel`
invocations + flutter_secure_storage purge.

- [x] C6.1 — `lfs_core::security::wipe_keychain` actor owns the
  canonical `MANAGED_KEYS` list (5 slots: encryption_key,
  biometric_encryption_key, keychain_probe, l2_pepper,
  bio_db_key). `wipe_keychain_run` walks the list sequentially
  and dispatches a `KeychainOpKind::Delete` prompt per key via
  the `keychain_op_prompt` registry; the existing
  `KeychainOpPromptListener` Dart subscriber handles the
  `flutter_secure_storage.delete` call. Per-key outcome report
  surfaces partial failure to the Settings UI. Dart
  `WipeAllService._purgeKeychainStore` routes through Rust
  with `keychain.deleteAll()` retained as the flutter_test
  fallback. The list-vs-`deleteAll` design is deliberate:
  enumeration makes the wipe surface auditable (a new key
  caught at code review when its consumer doesn't add to the
  list) and avoids prefix-matching surprises on shared
  platform keychain backends. `MethodChannel` (hardware vault)
  invocations stay Dart-side — single-arc pattern, the
  channel is a Flutter primitive without a Rust analogue.

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

**Superseded by Decision 4 rolling — see C9.0 / C9.1 / C9.2 /
C9.3 / C9.4 / C9.5 above** (under the Decision 4 block). The
original monolithic C9.1-C9.3 plan below is kept as a
historical anchor; the actual work tracks per-tier rolling so
each commit ships an isolated rollback-able feature gate
rather than one big-bang flip.

- [~] C9.1 — Actor scaffold + state transitions + bus events.
  Done as C9.0 (per Decision 4).
- [x] C9.2 — Per-tier orchestrators in Rust:
  `tier_unlock_orchestrator::{unlock,first_launch}_*` for all
  five tiers (Plaintext / Keychain / KeychainWithPassword /
  Hardware / Paranoid). Each owns the per-tier verify (gate /
  Argon2id / keychain Read/Write / hardware unseal/seal) +
  cascade emission + SecretStore staging; the Dart side
  consumes the cascade via `TierUnlockedListener`.
- [~] C9.3 — `security_provider.dart` (462 LOC) → `StreamProvider`
  mirror. `security_bootstrap.dart` orchestration retires.
  Pending — capabilities cache + orchestrator (C5.1 + C5.2)
  already cover the Settings-card subscription side; the
  remaining work is the Riverpod-graph wiring against the
  cascade events the per-tier orchestrators now publish.

**Risk:** highest of the migration. The Decision 4 rolling
keeps every step rollback-able; the residual C9.5 retire is
the last gate.

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
- [~] D6.2 — Rust-side singleton background ticker drives
  `tick_if_due` automatically after `config_store_init` runs;
  the actor's debounce flush no longer needs a Dart-side caller
  to poke it. Dart `ConfigNotifier` retains its own 300 ms
  Timer for now because the existing test suite's
  `_SaveCountingStore` asserts coalescing behaviour through the
  Dart debouncer; collapsing the Dart timer into the Rust
  ticker requires reworking the test contract (the assertion
  switches from `saveCount == 1 across 20 update bursts` to
  observing the `BusEvent::ConfigChanged` arrival rate, which
  flutter_test can't drive without bootstrapping `RustLib`).

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

- [x] E1 — `lfs_core::archive::qr_export_payload_size(conn,
  input)` mirrors `qr_export_payload` step-for-step (same DB
  reads + dedup + opts filter + folder-path resolve + JSON
  build) but skips the base64url encode and returns the
  deflated byte count via `qr_codec_encode::compress_to_payload_size`.
  Both producers now route through a shared
  `build_qr_export_json` helper so the wire shape stays one
  place. FRB shim `db_export_qr_payload_size(input)` exposes
  the API. The Dart `unified_export_controller` per-toggle
  estimators (`_qrEstimateSize`) currently route through
  `qr_compose::compose_and_size` (Decision 6 / E3-E4 work in
  earlier session); flipping the controller to call
  `db_export_qr_payload_size` for the full-DB-driven sizing
  path lands as E2.
- [x] E2 — `unified_export_controller` no longer references
  `_deduplicateKeys` / `_addAllManagerKeys` / `_encode*Payload`
  Dart-side composers; the per-toggle estimator routes through
  `qr_compose::compose_and_size` (Decision 6 / E3-E4 in earlier
  session) for the in-memory `data` carrier path. The full-DB
  `db_export_qr_payload_size` shim from E1 stays available for
  callers that want a DB-driven estimate (none today — would
  cost a query per checkbox toggle, slower than the in-memory
  composer for the live gauge UX). The Dart fallback composers
  in `qr_codec.dart` survive solely for flutter_test contexts
  that don't load the FRB native lib; production controllers
  never reach them.

## Arc F — Pure helper consolidations

| Helper                             | Current location                          | Notes                                                            |
|------------------------------------|-------------------------------------------|------------------------------------------------------------------|
| [x] `assetUrlForPlatform`          | `update_service.dart:797`                 | Routed through `lfs_core::update_metadata::asset_url_for_platform`. |
| —    `_compileGlob` regex cache     | `openssh_config_parser.dart:248`          | Cache lives in the Dart fallback only; production already routes through Rust. Removing the cache slows the test-only path with no production benefit — skip. |
| [x] `backoffSchedule` constant     | `password_rate_limiter.dart:35`           | Hydrated from Rust `BACKOFF_SCHEDULE` via FRB const, lazy-cached. |
| [x] `_unquote` (OpenSSH config)    | `openssh_config_parser.dart:337`          | Routed through `lfs_core::ssh_config::unquote` via `sshConfigUnquote` FRB sync; pure-Dart inline kept as flutter_test fallback. |
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
