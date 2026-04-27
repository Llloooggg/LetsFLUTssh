# Rust migration — full state-machine port

Live tracker. Replaces the earlier 9-step draft, which was framed
under "Dart owns state machines, Rust owns crypto/transport". The
real principle is **Flutter renders, Rust thinks**: every state
machine, every piece of business logic, every persisted derivation
lives in `lfs_core`. Earlier "closed at boundary contract" framing
of Phase 4.3 / 4.4 / 4.5 / 4.6 (see [RUST_CORE_MIGRATION_PLAN.md])
covered the *security* perimeter (no plaintext on the Dart heap,
KDF in Rust, DB in Rust); it left the orchestration in Dart. This
arc finishes the move.

This file is transient — delete once the arc closes.

[RUST_CORE_MIGRATION_PLAN.md]: ./RUST_CORE_MIGRATION_PLAN.md

## Architecture target

Single-direction loop:

- Dart → Rust: typed `Command` enum dispatched over FRB.
- Rust → Dart: typed `Event` enum streamed over bus topics.
- Rust owns every state machine, registry, cache, validator,
  scheduler, debouncer, ring buffer, persisted derivation.
- Dart subscribes per screen; widget unmount → subscription
  cancels → no Dart-side state outlives the rebuild.

Litmus test for any review: if the answer to *"what does Dart need
to know about this?"* is anything beyond *"what to draw on screen
right now"*, the design is wrong.

## Progress log

| Step | Status | Commit |
|---|---|---|
| 1. `migration_runner` → Rust | DONE | `101798a7` |
| 2. `app_config` → Rust | pending — **gated on step 9** (security_tier types couple in) |
| 3. `session_store` → Rust | pending |
| 4. `connection_manager` → Rust | pending |
| 5. `transfer_manager` → Rust driver | pending — Rust queue+state+`SftpTaskExecutor` shipped Phase 5.3; needs FRB `transfer_enqueue` + Dart UI rewire (TransferManager retire + transfer_panel snapshot view) |
| 6. `port_forward_runtime` → Rust driver | DONE — Rust drivers (`-L` / `-D` SOCKS5 / `-R`) shipped earlier; Dart `port_forward_runtime.dart` shrank to a ~150-LOC shim that dispatches per-rule `port_forward_start_*` / `port_forward_stop_*` over FRB |
| 7. `known_hosts` manager → Rust + prompt protocol | pending |
| 8a. `update_service::release_signing` → Rust | DONE | `f4fd49d4` |
| 8b. `update_service::cert_pinning` Dart shim drop | DONE | `4710271e` |
| 8c. `update_service` state machine → Rust | DONE — `lfs_core::update_orchestrator` owns the GitHub-API parse + asset selection + signed-manifest verification; Dart `UpdateService.checkForUpdate` / `downloadAsset` route through FRB by default with a Dart fallback retained only for the test-injection path |
| 9. Security tier stack → Rust | pending — largest port; `KdfParams` + `SecretBuffer` + `SecureRef` retire here |
| 10a. `session_recorder` asciinema composer → Rust | DONE | `5adceb05` |
| 10b. `session_recorder` ring buffer + driver loop | DONE — `lfs_core::recorder::queue` per-id worker + mpsc serialises header/event/rotate/close; Dart shim reduced to fire-and-forget enqueues |
| 13e. `tier_backing.dart` dead code drop | DONE | dead — no production caller |
| 11. `qr_codec` finish + `import_service` close | pending |
| 12. `deeplink_handler` listener through Rust dispatcher | DONE — `lfs_core::deeplink::DeeplinkDispatcher` owns dedup + scheme/file routing + QR staging; Dart `DeepLinkHandler` shrank to a URI pump that switches on `DbDeeplinkOutcome` |
| 13a. `aes_gcm.generateKey` → Rust | DONE | `f1d14183` |
| 13b. `conflict_resolver` | folded into step 7 (prompt protocol) |
| 13c. `secret_buffer` / `secure_ref` | folded into step 9 (security tier) |
| 13d. `clipboard_secret` | DEFERRED — Android sensitive-flag MethodChannel coupling makes a clean Rust port low-leverage |

## Status today

`lfs_core` carries the load-bearing primitives: SSH transport,
SFTP, port-forward driver, transfer queue, recorder driver,
archive, db (rusqlite + SQLCipher), all crypto, all pure parsers
(OpenSSH config, known-hosts, QR decode, deeplink), threat eval,
password strength, log sanitiser, update HTTP, platform clients
(TPM / fprintd / keychain / WinBio).

What still drives logic from Dart (after the Apr-2026 grind —
LOC reflects current tree):

| File | LOC | What it owns (Dart-side) | Plan step |
|---|---|---|---|
| `core/connection/connection_manager.dart` | 768 | registry + generation counter + bastion-await coordination + credential overlay + reconnect cascade + active-count tracking | 4 |
| `core/session/session_store.dart` | 712 | in-memory list + folder-map cache + collapsed-folders set + duplicate-naming + folder rename / move / delete cascade + snapshot restore | 3 |
| `core/transfer/transfer_manager.dart` | 393 | queue scheduler + concurrency cap + history truncation + progress throttle + timeout tracker | 5 |
| `core/update/update_service.dart` | ~1000 | thin façade over `lfs_core::update_orchestrator` (GitHub release parse + signed-manifest verify happen Rust-side); Dart fallback paths stay only for flutter_test contexts that don't load the FRB native lib | DONE |
| ~~`core/ssh/port_forward_runtime.dart`~~ | ~150 | thin FRB shim — armed-rule map + per-rule `port_forward_start_*` / `port_forward_stop_*` dispatch on connect / teardown; everything else is Rust | DONE — step 6 |
| `core/ssh/known_hosts.dart` | 584 | TOFU policy + add / remove / match + cache | 7 |
| `core/security/master_password.dart` | 396 | KDF verify orchestration + tier promotion | 9 |
| `core/security/password_rate_limiter.dart` | 396 | exponential backoff state | 9 |
| `core/security/hardware_tier_vault.dart` | 395 | TPM / Keychain / WinBio composer | 9 |
| `core/security/wipe_all_service.dart` | 374 | catastrophic-reset orchestrator | 9 |
| `core/security/security_bootstrap.dart` | 351 | startup tier resolution | 9 |
| `core/security/keychain_password_gate.dart` | 262 | keychain unlock gate sequence | 9 |
| `core/security/biometric_key_vault.dart` | 255 | biometric unlock sequence | 9 |
| `core/security/security_tier.dart` | 257 | tier model + transitions | 9 |
| `core/config/app_config.dart` | 605 | schema + defaults + validation + migrations | 2 (gated on 9) |
| `core/import/import_service.dart` | 300 | apply driver remnants | 11 |
| ~~`core/session/session_recorder.dart`~~ | ~280 | thin enqueue layer over `lfs_core::recorder::queue`; subscribes to the per-id recorder topic for `RecorderRotateRequested` to allocate fresh paths | DONE |
| `core/session/qr_codec.dart` | 980 | encode payload marshalling (Rust pure encode shipped; Dart still owns the `ExportPayloadInput` build) | 11 |
| ~~`core/deeplink/deeplink_handler.dart`~~ | ~225 | thin URI pump — `app_links` listener + per-URI `deeplinkDispatch` FRB call + outcome switch; static `parseConnectUri` retained for the Dart fuzz / flutter_test surface | DONE — step 12 |
| `core/transfer/conflict_resolver.dart` | 72 | UI-prompt cache state | 7 (folded) |
| `core/security/secret_buffer.dart` | 215 | RAII + zeroing | 9 (folded) |
| `core/security/secure_ref.dart` | 122 | RAII handle | 9 (folded) |
| `core/security/clipboard_secret.dart` | 99 | timed clipboard wipe | 13d (DEFERRED) |
| `core/migration/migration_runner.dart` | 51 | thin shim — DONE | shim only |

Already retired this arc:
- `aes_gcm.dart` (19 LOC, `f1d14183`)
- `release_signing.dart` (135 LOC, `f4fd49d4`)
- `cert_pinning.dart` (177 LOC, `4710271e`)
- `tier_backing.dart` (167 LOC, `6e249d86`) — dead code, no production caller
- Migration framework Dart files (~840 LOC across 9 files, `101798a7`)
| `core/security/clipboard_secret.dart` | 99 | timed clipboard wipe |
| `core/security/aes_gcm.dart` | 19 | random key fill |

Total ≈ **10 000 LOC of Dart-side logic** to move. Hot path is
already Rust; what remains is orchestration and state machinery.

What stays Dart by design (rendering / OS-only surface):

- `lib/widgets/**`, `lib/screens/**`, `lib/dialogs/**`
- `lib/providers/**` — pure `StreamProvider` over bus topics
- `core/connection/foreground_service.dart` — Android binding
- `core/security/biometric_auth.dart` — `local_auth` UI prompt
- `core/single_instance/single_instance.dart` — IPC socket
- `app_links` listener (URI → one FRB call)

## Sequence

Order picks dependencies first so each step lands on a stable
base. Each step is one focused arc (1–3 commits depending on
shape). Mark `[done]` next to checklist items as they ship.

### 1 — `migration_runner` → Rust [DONE]

Shipped in commit `101798a7`. `lfs_core::migration` carries the
Runner + Artefact + Migration traits + Registry + ConfigArtefact +
KdfArtefact + SchemaVersions; FRB exposes
`migration_run_on_startup` and `migration_config_version_on_disk`.
Dart `core/migration/` shrinks to a one-line shim over the FRB
call (`runStartupMigrations`). 11 unit tests in
`lfs_core::migration` cover runner + artefact paths; Dart-side
runner / archive / artefact / versioned-blob / registry tests
deleted.

### 2 — `app_config` → Rust

Read by every Rust actor + every Dart screen. Schema +
defaults + validation must live one place.

**Touches.**
- `lfs_core::config::AppConfig` + serde mirrors of every
  sub-struct (theme, terminal, sftp, recording, security, …).
- `lfs_core::config::Store` reads / persists via the
  `app_configs` table (already in `lfs_core.db`).
- FRB: `config_get` / `config_update` + bus `ConfigChanged`
  event so screens auto-refresh.
- Dart: `core/config/app_config.dart` shrinks to FRB-generated
  DTOs + a `StreamProvider<AppConfig>` over the bus topic.

**Risk.** Every config read crosses FRB. Mitigate by emitting
`ConfigChanged` events on writes only; reads return cached
snapshot.

### 3 — `session_store` → Rust

Connection manager + import / export depend on the session
registry. All in-memory orchestration (folder cache, collapsed
set, duplicate-naming, rename / move / delete cascade, snapshot
restore) needs to live one place.

**Touches.**
- `lfs_core::sessions::Registry` actor — owns the in-memory
  session list, folder map, collapsed-folder set; backed by
  the existing `db_sessions_*` DAOs.
- Operations: `add`, `update`, `delete`, `delete_multiple`,
  `move`, `move_multiple`, `duplicate`, `rename_folder`,
  `move_folder`, `delete_folder`, `restore_snapshot`,
  `count_in_folder`, `add_empty_folder`, `remove_empty_folder`,
  `toggle_folder_collapsed`.
- Bus events: `SessionAdded`, `SessionUpdated`, `SessionDeleted`,
  `FolderRenamed`, `FolderMoved`, `FolderDeleted`,
  `FolderEmptyAdded`, `FolderEmptyRemoved`, `FolderCollapsed`,
  `SnapshotRestored`.
- FRB: typed Command enum + `session_registry_view_stream`.
- Dart: `core/session/session_store.dart` retires; Riverpod
  `sessionListProvider` becomes a `StreamProvider<List<Session>>`
  over the bus topic.

**Risk.** Folder-cascade ordering bugs (rename + collapsed-set
sync). Mitigate with property-based tests on the Rust side.

### 4 — `connection_manager` → Rust

Largest hot-path orchestrator after the actor shell. Today the
Rust `ConnectionRegistry` exists but the Dart `ConnectionManager`
still holds: connection map, generation counter, bastion-readiness
await, credential overlay precedence, active-count tracking,
reconnect cascade.

**Touches.**
- Existing `lfs_core::connection::Registry` extended:
  - bastion-readiness await moves into `connect_async`'s
    pre-auth phase (today Dart does
    `await conn.bastion!.waitUntilReady()`).
  - credential overlay (`SessionCredentialCache` + cached
    passphrase) becomes a Rust `CredentialOverlay` that
    composes during `prepare_auth`.
  - generation counter moves into `ConnectionActor`; stale-
    event filtering is a no-op once the bus events themselves
    carry generation tags.
- New events: `ActiveCountChanged(count)` — the Android
  foreground-service binding receives it directly via bus.
- FRB: `connection_connect_async`, `connection_reconnect`,
  `connection_disconnect`, `connection_disconnect_all`.
- Dart: `core/connection/connection_manager.dart` deletes;
  `Connection` Dart class shrinks to a FRB-DTO mirror with no
  setters; `connectionListProvider` becomes a `StreamProvider`.

**Risk.** Reconnect after auto-lock relies on the in-memory
credential cache. Mitigate by routing `SessionCredentialCache`
through `lfs_core::secrets::SecretStore` (already the canonical
owner of cached plaintext); the Dart-side `_credentialCache`
field disappears.

### 5 — `transfer_manager` → Rust driver

Rust queue exists; the Dart-side scheduler + history truncation +
per-second progress throttle is the only remaining orchestration.

**Touches.**
- `lfs_core::transfer::Driver` extends the existing queue with
  concurrency-bounded worker pool, history ring buffer (capped),
  cancel-token plumbing.
- Bus events: `TransferEnqueued`, `TransferProgress`,
  `TransferCompleted`, `TransferFailed`, `TransferCancelled`,
  `HistoryTruncated`.
- FRB: `transfer_enqueue_*`, `transfer_cancel`,
  `transfer_cancel_all`, `transfer_clear_history`.
- Dart: `core/transfer/transfer_manager.dart` retires;
  `transferProvider` becomes a `StreamProvider`.

**Risk.** Progress throttle UI behaviour — must coalesce events
on the Rust side at ≤1 / 250 ms or Riverpod rebuilds storm.

### 6 — `port_forward_runtime` → Rust driver [DONE]

Rust drivers landed earlier (`-L` listener, `-D` SOCKS5, `-R` +
session-level dispatcher). This rung retires the Dart-side
runtime: `core/ssh/port_forward_runtime.dart` shrank from 691
LOC of accept loops + SOCKS5 handshake + bridge pumps to a
~150-LOC `ConnectionExtension` shim that dispatches per-enabled
rule into `port_forward_start_local` / `port_forward_start_dynamic`
/ `port_forward_start_remote` on `onConnected`, tracks armed rule
ids, and issues the matching `port_forward_stop_*` on
`onDisconnecting` / `onReconnecting`. Status events flow on the
`PortForwardStatus` bus topic; nothing in the UI was ever
subscribed to the old broadcast `statusStream`, so dropping it is
behaviour-preserving.

**Risk.** Hot path on Android (ProxyJump bastion chains lean on
this). Smoke on real Android device after landing.

### 7 — `known_hosts` manager → Rust

Parser already Rust; the manager class + TOFU policy + cache is
the only remaining orchestration.

**Touches.**
- `lfs_core::known_hosts::Manager` actor wraps the existing
  parser + DAO. Owns: in-memory cache, file watch, write
  serialisation.
- TOFU prompt becomes a bus command/response pair:
  `KnownHostPrompt(fingerprint, host)` ← Rust → Dart UI →
  `KnownHostPromptResponse(accept, persist)` → Rust.
- FRB: registry commands + view stream.
- Dart: `core/ssh/known_hosts.dart` retires; the prompt UI
  becomes a `StreamProvider<KnownHostPrompt?>` subscriber that
  pushes the user's choice back as a `KnownHostPromptResponse`
  command.

**Risk.** Prompt protocol must serialize across reconnect storms
(multiple connections waiting on the same host's prompt).
Mitigate with per-host coalescing on the Rust side.

### 8 — `update_service` → Rust state machine

HTTP fetch + download already Rust; the state machine + signed
manifest verify orchestration + cert pinning still Dart.

**Touches.**
- `lfs_core::update::StateMachine` actor: `Idle → Checking →
  Available → Downloading → Verifying → Ready → Launching`.
- Signed manifest verify (Ed25519 against pinned key) folds
  into the verify state.
- Cert pinning moves into a custom `rustls::ServerCertVerifier`
  inside `update_http`; SPKI map (currently empty Dart-side)
  becomes a Rust constant.
- Bus events: `UpdateState`, `UpdateProgress`,
  `UpdateError(detail)`.
- FRB: `update_check`, `update_download`, `update_install`.
- Dart: `core/update/update_service.dart` +
  `core/update/release_signing.dart` +
  `core/update/cert_pinning.dart` retire; `updateProvider`
  becomes a `StreamProvider`. File launcher
  (`xdg-open` / `open` / `start`) stays Dart — it hands off to a
  privileged installer that the OS owns.

**Risk.** Pinned SPKI behaviour is opt-in today (empty map). No
regression possible from moving an empty allowlist.

### 9 — Security tier stack → Rust

Largest port. ~1700 LOC across master_password,
password_rate_limiter, hardware_tier_vault, keychain_password_gate,
biometric_key_vault, security_bootstrap, security_tier,
wipe_all_service. Platform clients (TPM, fprintd, keychain,
WinBio) already Rust; this composes them into the tier state
machine.

**Touches.**
- `lfs_core::security::tier::Machine` actor owns:
  - tier state (`Plaintext | Keychain | Hardware | Paranoid`)
  - master-password verify (KDF in Rust already; orchestration
    moves)
  - rate-limiter exponential backoff
  - hardware-tier composer (Linux TPM / macOS Keychain / Windows
    WinBio paths)
  - keychain unlock gate sequence
  - biometric unlock sequence
  - wipe-all reset orchestrator
  - startup tier resolution
- Bus events: `TierState`, `UnlockRequested`, `UnlockSucceeded`,
  `UnlockFailed(detail)`, `LockRequested`, `Wiped`.
- FRB: typed Command enum + view stream.
- Dart: every `core/security/*.dart` orchestrator retires.
  `biometric_auth.dart` (local_auth UI), `secret_buffer.dart`,
  `secure_ref.dart`, `clipboard_secret.dart`, `aes_gcm.dart`
  remain Dart only because they own OS-prompt UI / RAII /
  `Random.secure()` keygen — none are state machines.

**Risk.** Highest of the arc. Land on a focused branch, smoke on
every platform (Linux + macOS + Windows + Android + iOS) before
merge.

### 10 — `session_recorder` → Rust driver [DONE]

Per-frame AES + asciinema composer already shipped in `lfs_core::
recorder` (`record_header` / `record_event` / `rotate_to` /
`close_with_io`). This rung adds the per-id write queue:

- `lfs_core::recorder::queue::RecorderQueue` — process-singleton
  handle map keyed by `RecorderId`. `spawn(id)` creates a
  per-id `mpsc::channel<QueueEntry>` + tokio worker; `enqueue(id,
  entry)` pushes a `Header` / `Event` / `Rotate` / `Close` into
  the worker's mailbox.
- The worker drains entries serially through
  `tokio::task::spawn_blocking` so the asciinema event stream lands
  on disk in arrival order even when concurrent FRB calls overlap
  on the runtime.
- Auto-rotation: after each event write the worker checks the
  registry's running total against `MAX_FILE_BYTES`; when it crosses,
  it latches a flag and emits `RecorderRotateRequested { id,
  bytes_written }` on the bus. Dart subscribes, allocates a fresh
  path under the session directory (uses `getApplicationSupportDirectory`
  + `hardenFilePerms` — platform concerns stay Dart), and enqueues a
  `Rotate { new_path }` plus the next `Header`.
- FRB: `recorder_queue_spawn`, `recorder_queue_enqueue_header`,
  `recorder_queue_enqueue_event`, `recorder_queue_enqueue_rotate`,
  `recorder_queue_enqueue_close`. Bus event `RecorderRotateRequested`
  added to the recorder topic.
- Dart `SessionRecorder` retires its `_writeQueue` /
  `_writeSub` / `_drainOne` / local byte-counter rotation check.
  The new shape is fire-and-forget enqueues + a bus subscription
  that handles rotation. Playback browser stays (read-only file
  consumer, no state).

### 11 — `qr_codec` finish + `import_service` close

Encode `qr_export_payload` already Rust per Phase 4.6; the Dart
side still owns `ExportPayloadInput` build + class hierarchy.
Import apply driver also has a residual Dart layer (~1000 lines
of conflict resolution + snapshot/rollback + FK ordering).

**Touches.**
- `lfs_core::archive::qr_export_input` builds the input from
  `db_sessions_load_for_export(ids)` + filters; Dart only passes
  session ids + options.
- `lfs_core::archive::import_apply_driver` finishes the merge /
  replace machinery.
- FRB: `qr_export_input_only_ids`, `import_archive_apply_driver`.
- Dart: `core/session/qr_codec.dart` shrinks to FRB-DTO mirrors
  only. `core/import/import_service.dart` retires.

### 12 — `deeplink_handler` listener through Rust dispatcher [DONE]

`lfs_core::deeplink::DeeplinkDispatcher` owns dedup state (last URI
+ timestamp, 2-second window) and the routing matrix: scheme
dispatch (`letsflutssh` / `file` / `content`), custom-scheme action
(`connect` / `import`), file-extension classification (`.lfs` /
`.pem` / `.key` / `.pub`), QR-payload staging into
`AppState::imports`. Returns a typed `DeeplinkOutcome` enum.

`lfs_core::qr_codec_decode::try_decode_payload` returns a typed
`QrDecodeResult { Ok / VersionTooNew { found, supported } / Err }`
so the dispatcher can emit a `QrImportRejected` outcome without
parsing error strings.

The FRB adapter (`lfs_frb::api::deeplink::deeplink_dispatch`)
mirrors the outcome as `DbDeeplinkOutcome` and hydrates the
QR-import variant with a full `DbImportPreview` (looked up off the
staged handle in `AppState::imports`) so the Dart caller does not
round-trip back to fetch counts before rendering the import-preview
dialog.

Dart `DeepLinkHandler` shrank from 266 LOC to ~225 LOC (the bulk
of the cut is `_handleImportUri` + `handleCustomScheme` +
`handleFileUri` + the dedup state machine; the static
`parseConnectUri` + Dart fallback stay for the deeplink fuzz
suite + flutter_test surface). The handler is now a URI pump:
each URI from `app_links` (cold-start `getInitialLink` + warm
`uriLinkStream`) flows through `deeplinkDispatch` and switches on
the typed outcome to fire the right callback.

### 13 — Pure helpers cleanup

No dependencies on other steps; lands as small commits when each
gate clears.

- `core/transfer/conflict_resolver.dart` — **deferred to step 7
  prompt protocol.** On second look the file is not pure logic;
  it owns a `ConflictPrompt` callback that drives a UI dialog
  and caches the user's "apply to all" decision. Moving Rust-side
  needs the bus prompt-event protocol that step 7 (`known_hosts`)
  ships first. Fold both prompt-protocol arcs into one rung.
- `core/security/secret_buffer.dart` + `secure_ref.dart` — RAII
  helpers; the Dart wrappers retire once the security tier stack
  moves (step 9). Already routes to
  `lfs_core::secrets::SecretStore`; only the Dart class shells
  survive that step.
- `core/security/clipboard_secret.dart` — timed clipboard wipe;
  fold into `lfs_core::clipboard` (uses `arboard` for the OS
  clipboard surface; Dart MethodChannel for Android sensitive-
  flag stays for that one platform).
- ~~`core/security/aes_gcm.dart`~~ — **DONE**, commit `f1d14183`.
  19-LOC keygen folded into `lfs_core::crypto::aes_gcm_random_key`
  exposed as `frb(sync)`. Seven call sites swapped.

After step 13: every load-bearing path runs in Rust. Dart layer
is widgets + Riverpod subscribers + MethodChannel proxies.
Approximately 10 000 LOC dropped from `lib/core/`.

## Order at a glance

```
1.  migration_runner          — startup; blocks 2, 9
2.  app_config                — every screen reads it
3.  session_store             — connection_manager depends
4.  connection_manager        — registry / generation / overlay
5.  transfer_manager          — scheduler driver
6.  port_forward_runtime      — listener driver
7.  known_hosts               — TOFU policy + prompt protocol
8.  update_service            — full state machine
9.  security tier stack       — largest port
10. session_recorder          — driver loop
11. qr_codec + import_service — finish encode side + apply
12. deeplink_handler          — listener through bus
13. pure helpers              — cleanup
```

## Testing strategy

- Each step lands with Rust unit tests + property-based tests
  where state-machine ordering matters (folder cascade, tier
  transitions, queue scheduler).
- Dart-side: widget tests subscribe to a `FakeAppBus` test
  harness that replays scripted events. No Dart-side state
  mocking — there is no Dart-side state to mock.
- Integration test per arc: real `lfs_frb` lib loaded, real
  bus, real DAOs, scripted command sequence, asserted event
  sequence.

## Out of scope (not migration)

- §149 mobile pipelines (Android / iOS native plugins).
- §121 / §122 / §159 WebDAV / S3 / WebDAV-browser features.
- macOS / Windows hardware verification — needs target hardware
  in CI.
- Tauri / CLI / web frontends — `lfs_core` is already
  frontend-agnostic; adapter additions are not part of this arc.
