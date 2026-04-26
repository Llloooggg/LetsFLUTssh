# Dart legacy cleanup — plan

Live, internal-only tracker for the "вся логика на Rust кроме UI"
final pass. Sequential checklist; each item is a discrete commit.
This file is transient — delete once the cleanup arc closes.

## Goal

Drop every Dart code path that has a Rust counterpart already
landed in `lfs_core` + FRB. After this arc, the Dart layer
contains only:

1. UI (Flutter widgets, Riverpod providers, dialogs, navigation).
2. Platform glue not movable to Rust (`dart:io` shells, system
   `MethodChannel` plugins, `path_provider`, `local_auth` UI,
   Android foreground service binding).
3. Thin model classes the UI binds to (`Session`, `Tag`,
   `Snippet`, `SshKeyEntry`) — these stay Dart because Riverpod
   + widget builders consume them directly.

Everything else either routes through FRB into `lfs_core` or
gets deleted.

## Inventory — what's dead today

### Production code paths the UI no longer touches

- `lib/core/import/import_service.dart` — `applyResult` body
  (~700 LOC). Production flows route through
  `applyResultViaRust`. Constructor + 25 callback fields
  become unused.
- `lib/core/import/import_service_test.dart` — covers the
  legacy callback path. Drop alongside.
- `lib/core/connection/connection_manager.dart` — `_doConnect`
  legacy in-Dart driver. `useRustActor=true` in production
  (`connectionManagerProvider`). The Rust actor path
  (`_doConnectViaActor`) is the only live branch.
- `lib/features/settings/export_import.dart::ExportImport.import_`
  — Dart-side LFSE decrypt + zip parse. Settings flow swaps
  to `dbImportOpen(path, password)`. QR / paste-link flows
  build their own `ImportResult` so they don't hit this.
- `lib/core/session/session_recorder.dart::_rotate` —
  Dart-side 100 MB rotation. Move into Rust recorder driver
  alongside the file IO.

### Dual-impl utility paths (Rust port live, Dart fallback dead)

- `password_strength.dart::_dartFallback` — Rust always loaded
  in production; the FRB-init fallback only ran in unit tests.
- `sanitize.dart::_redactSecretsDart` /
  `_sanitizeErrorMessageDart` — same story.
- `openssh_config_parser.dart::_parseBlocks` /
  `_resolveEntry` etc — Dart fallback after the FRB call
  fails. Only fires when the native lib is missing.

### Already-removed (no further action)

- `dartssh2` package (dropped earlier in the migration).
- drift package (dropped at Phase 4.2 stage 8).

## Sequencing

Each step is one commit. Order picks low-risk wins first so
intermediate states stay shippable.

### Step 1 — drop ImportService legacy callback path

**Status:** DONE

**Why first:** zero production callsites left. Every flow
already routes through `applyResultViaRust`. Confidence
high; risk low.

**Touches:**
- `lib/core/import/import_service.dart` — keep
  `applyResultViaRust`, `_stageFromResult`, `_sessionToJson`
  family, `ImportSummary`, `LfsImportRolledBackException`.
  Drop `class ImportService`, `_Snapshot`, `_SessionsPhase`,
  every `_phase*` / `_import*` helper, `_applyCore` body.
- `test/core/import/import_service_test.dart` — delete
  outright; coverage moves to `lfs_core::archive::tests`
  (already in tree).
- Cross-check: `grep -rn "ImportService(" lib/` should
  return zero results in `lib/`.

**Risk:** any docstring referencing `ImportService.applyResult`
needs scrubbing. The class lives only in test fixtures
otherwise.

### Step 2 — drop Dart-side LFSE decrypt + parse

**Status:** DONE

**Why second:** Step 1 reduces the consumer surface so the
decrypt-side rewire is mechanical.

**Touches:**
- `lib/features/settings/export_import.dart` — drop
  `ExportImport.import_` body and the helpers it pulls
  (`_decodeArchive`, `_decodeList`, `_parseSession`,
  zip walking). Keep only the export half + `probeArchive`
  (used by the settings file picker).
- `lib/features/settings/settings_sections_data.dart::_showImportDialog`
  — replace `_decryptForPreview` call with
  `dbImportOpen(path, password)`; build the preview dialog
  from `DbImportPreview` counts + labels instead of the full
  `ImportResult` object tree.
- `lib/widgets/lfs_import_preview_dialog.dart` — convert
  `LfsPreview` to carry counts only (drop the
  `List<Session>` field). Existing UI already renders
  counts; the field was passthrough.
- `lib/app/import_flow.dart::showLfsImportDialog` — same
  swap. Calls `dbImportOpen` first, hands the handle to
  `dbImportApply` after the user accepts the preview.
- `pubspec.yaml` — `archive` package likely drops if
  nothing else needs zip Dart-side. Verify with
  `grep -rn "package:archive" lib/`.

**Risk:**
- Mobile filesystem path access (Android SAF) — the FRB
  endpoint takes a string path. SAF URIs need translation
  to plain paths via `file_picker` already; verify in
  practice.
- Preview dialog's "filtered" step that re-builds an
  `ImportResult` with the user's option set goes away.
  Filtering moves into `dbImportApply` options instead;
  the dialog returns the option set directly.

### Step 3 — drop Dart connection manager legacy driver

**Status:** DONE

**Why third:** lighter than archive rewire but exercises a
hot-path code area. Goes after the safer Steps 1+2.

**Touches:**
- `lib/core/connection/connection_manager.dart` — drop
  `_doConnect` body (the legacy in-Dart russh driver),
  `_authFromConfig` legacy plaintext-staging variants,
  `_useRustActor` flag + constructor field. The actor
  path (`_doConnectViaActor`) becomes the unconditional
  body.
- `lib/providers/connection_provider.dart` — drop the
  `useRustActor: true` arg now that there's only one
  path.
- `lib/core/connection/transport/*.dart` — `RustTransport`
  was already the only live transport; the legacy `SshTransport`
  factory chain lives in `transport_factory.dart`. Audit
  whether anything other than tests injects mocks.
- `test/core/connection/*.dart` — every test that
  constructed `ConnectionManager(useRustActor: false)`
  must flip to true (or `connection_get_session` mocks).
  Either fix or skip with `integration_test` migration
  notes (consistent with the recorder skip pattern).

**Risk:**
- Test refactor scope is the largest of any step. ~10
  test files exercise the connection lifecycle.
- Mobile path: Android SSH connect goes through
  `SshTransport` → `RustTransport.adopt`. Verified
  working but worth a smoke test on a device after the
  swap.

### Step 4 — move recorder rotation into Rust

**Status:** DONE

**Why fourth:** isolated change, no consumer rewire. Closes
the last "dual-impl" gap on the recorder.

**Touches:**
- `rust/crates/lfs_core/src/recorder.rs` — extend
  `RecorderActor` with `max_file_bytes` + `path_template`
  fields. `record_frame` checks the byte counter against
  the cap and triggers rotation: `flush + close current
  file + open new file at template-resolved path + write
  magic + reset counter`. Path template = caller hands a
  closure that returns the next filename (so platform
  app-support resolution stays Dart-side via the initial
  `register_with_io` call's `path` arg).
  - alt: rotation closure runs Dart-side via a callback
    over the bus (publish `RecorderRotateRequested(id)`,
    Dart resolves new path + calls `recorder_register_with_io`
    again under the same id). Cleaner — keeps platform
    fs decisions Dart-side.
- `lib/core/session/session_recorder.dart::_rotate` —
  delete the body. Listen on the bus for the
  `RecorderRotateRequested` event, resolve a new
  timestamped path, call `recorderRegister` with the same
  handle id (or a fresh one + update `_handleId`).

**Risk:**
- Bus event ordering: rotation request must serialise
  with the record-frame queue so a frame doesn't write to
  the new file before its magic landed. Either inline the
  rotation in `record_frame` (Rust drives) or block the
  Dart queue while the rotate command awaits.
- File path generation needs platform-aware `getApplicationSupportDirectory`
  — Dart owns that. So the bus-callback shape is the
  practical path.

### Step 5 — drop Dart utility fallbacks

**Status:** PARTIAL — openssh_config_parser block resolver dropped; sanitize + password_strength fallbacks retained as flutter_test affordances (widget tests render the password-strength meter and AppLogger pipes through sanitizeError, both synchronous build-time calls). Re-evaluate once a flutter_test bootstrap that calls `RustLib.init` lands.

**Why fifth:** tiny diff, last cleanup wave. Drops the
"unit tests work without RustLib.init" affordance — once
production tests are confirmed to bootstrap the FRB
runtime in `flutter_test_driver` setup, the fallback is
dead weight.

**Touches:**
- `password_strength.dart::_dartFallback` — drop. Tests
  that need the meter must `RustLib.init` first.
- `sanitize.dart::_redactSecretsDart` /
  `_sanitizeErrorMessageDart` — drop.
- `openssh_config_parser.dart::_parseBlocks` /
  `_resolveEntry` / `_RawBlock` — drop. The Rust pipeline
  via FRB becomes the only path.
- Test fixtures that hit these paths get an
  `await RustLib.init()` in their `setUpAll` block, OR
  `skip:` markers consistent with the recorder pattern.

**Risk:** flutter_test runner does not load a native lib
by default. Either:
- Add a test bootstrap that loads the native blob (more
  work, more correct).
- Mark affected tests `skip:` with a "moves to integration"
  note (matches recent recorder + ssh dir tests).

### Step 6 — final dead-code sweep

**Status:** TODO

**Why last:** post-cleanup audit. Anything still referenced
only by retired tests or by the dropped paths gets pruned.

**Touches:**
- `pubspec.yaml` — drop deps that no longer have a Dart
  caller (`archive` is the prime suspect). Verify each
  with grep before removal.
- Generated FRB bindings (`lib/src/rust/api/*.dart`) —
  re-codegen after every Rust-side dep change so the Dart
  surface tracks reality.
- `import_flow.dart::_buildImportService` was already
  removed. Check for orphaned `_invalidateImportProviders`
  vs `_refreshStores`; consolidate.
- `lib/features/settings/export_import.dart` — after
  Step 2 the import half is gone; rename / re-scope to
  `export.dart` if the file becomes export-only.

## Test strategy

- Each step ships with `make analyze && make rust-lint &&
  make rust-test && make test` green. Skip-marked tests
  pile under `integration_test/` once they accumulate.
- Integration test bootstrap (load FRB native lib + init
  AppState) lands as a separate concern — a `test_helpers`
  shared utility, plumbed once and reused. Probably arrives
  alongside Step 5.
- Manual smoke pass on a real device after Step 3 (connection
  manager) before merge.

## Out of scope

These do NOT happen in this arc:

- Mobile pipelines (#149) — unrelated feature work.
- WebDAV / S3 file browsers (#121, #122, #159) — feature
  work.
- `lfs_cli` headless binary — useful but separate
  packaging concern; see `RUST_CORE_MIGRATION_PLAN.md`.
- macOS / Windows native verification of the
  already-shipped ports — needs target hardware in CI.

## Order at a glance

```
1. ImportService legacy drop          — low risk, big LOC drop
2. LFSE Dart decrypt drop             — medium risk, archive flow
3. ConnectionManager legacy drop      — high risk, hot path
4. Recorder rotation → Rust           — medium risk, bus wiring
5. Utility fallbacks drop             — low risk, depends on test bootstrap
6. Final sweep + dep prune            — cleanup
```

After Step 6: the Dart layer is UI + platform glue + thin
models. Every load-bearing path runs Rust.
