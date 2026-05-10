# Adding a Feature — Walkthrough

Hands-on tutorial for new contributors. Walks through adding a small feature end-to-end so you learn the project's layout, conventions, and tooling without reading [`ARCHITECTURE.md`](ARCHITECTURE.md) cover-to-cover.

Build instructions: [`CONTRIBUTING.md`](CONTRIBUTING.md). Deep technical reference: [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## Mental Model

The codebase splits across three layers:

- **`rust/crates/lfs_core/`** — pure Rust headless library. Owns SSH/SFTP, crypto envelopes, `rusqlite` + SQLCipher 4.x DB, sessions registry, every persisted derivation, every cached secret. No FFI, no UI awareness. See [ARCHITECTURE §3.14](ARCHITECTURE.md#314-rust-securitytransport-core-rust).
- **`lib/core/<domain>/`** — pure Dart logic + thin FRB shims for the Rust core. Models, mappers, DAO wrappers. No widgets.
- **`lib/features/<feature>/`** — UI: screens, dialogs, widgets. Consume `core/` through Riverpod providers in `lib/providers/`.

Persistence runs through the FRB DAO surface in `lib/src/rust/api/db.dart`; the Rust schema lives in `lfs_core::db::SCHEMA_SQL` and is bootstrapped on every DB open. Dart never holds a SQLite handle directly. See [ARCHITECTURE §11 Persistence](ARCHITECTURE.md#11-persistence--storage).

Strings live in `lib/l10n/app_*.arb` (one file per locale, 15 total). The `S.of(context)` getter is generated from `app_en.arb`.

A good first scan: open `lib/core/snippets/` + `lib/features/snippets/` + `lib/providers/snippet_provider.dart` side-by-side — the smallest complete feature in the codebase.

---

## Walkthrough — Add a "Notes" Feature

We'll add a per-session free-form notes field that lives in its own table. Steps map 1:1 to the layers.

### 1. Rust DAO + schema (`rust/crates/lfs_core/src/db/`)

Schema is the authoritative source of truth — every column, FK, and index lives in `lfs_core::db::SCHEMA_SQL`. Add a `Notes` table next to the existing ones (`Sessions`, `SshKeys`, `Snippets`, …).

For the DAO, copy the shape from `rust/crates/lfs_core/src/db/snippets.rs`: each entity gets `list_*`, `upsert_*`, `delete_*` functions taking a `&Connection` and the typed row struct. Idiomatic `rusqlite::Result<T>` returns; errors funnel through `crate::Error`.

When you add or rename a column, bump `SCHEMA_VERSION` and add the matching `ALTER TABLE` step in the bootstrap — see [ARCHITECTURE §11 Schema migrations](ARCHITECTURE.md#11-persistence--storage).

### 2. FRB API surface (`rust/crates/lfs_frb/src/api/db/`)

Expose the DAO through `lfs_frb::api::db::notes` (one file per entity, mirroring `snippets.rs` / `tags.rs`). The adapter:

- Receives Dart-friendly DTOs (`Vec<u8>` / `String` / numeric).
- Delegates to `lfs_core::db::notes::*`.
- Wraps blocking `rusqlite` calls in `tokio::task::spawn_blocking` so the FRB worker thread never stalls.

After editing any file under `lfs_frb::api`, run `make rust-codegen` to regenerate the Dart bindings under `lib/src/rust/`. Stage the regenerated files in the same commit.

### 3. Dart model — `lib/core/notes/note.dart`

Immutable data class with `copyWith`, `==`, `hashCode`, `toJson` / `fromJson`. Match the style of [`lib/core/snippets/snippet.dart`](../lib/core/snippets/snippet.dart):

```dart
import 'package:uuid/uuid.dart';

class Note {
  final String id;
  final String sessionId;
  final String body;
  final DateTime updatedAt;

  Note({
    String? id,
    required this.sessionId,
    required this.body,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       updatedAt = updatedAt ?? DateTime.now();

  Note copyWith({String? body}) => Note(
        id: id,
        sessionId: sessionId,
        body: body ?? this.body,
        updatedAt: DateTime.now(),
      );

  // == / hashCode / toString — see snippet.dart for the pattern.
}
```

### 4. Dart shim + mapper — `lib/core/db/mappers.dart`

Add a one-pair converter between the FRB `DbNoteRow` DTO and the domain `Note` class. Same pattern the existing entries use for `Session` ↔ `DbSessionRow`.

### 5. Provider — `lib/providers/notes_provider.dart`

Riverpod is the **only** way state is shared. Never use `static` mutable globals.

```dart
final notesProvider = AsyncNotifierProvider<NotesNotifier, List<Note>>(
  NotesNotifier.new,
);
```

The notifier reads / writes via the FRB DAO (`dbNotesList` / `dbNotesUpsert` / `dbNotesDelete`) and subscribes to the matching `BusTopic::Notes` event so cross-window mutations refresh the cache without polling. Existing example: [`lib/providers/snippet_provider.dart`](../lib/providers/snippet_provider.dart).

Consumers should `.select()` the slice they need — see [ARCHITECTURE §4 State Management](ARCHITECTURE.md#4-state-management--riverpod).

Widget-local state (dialog selection, pane caches, panel focus) does **not** belong in a Riverpod provider. Use `ChangeNotifier` + `AnimatedBuilder` instead — see [§4.3 Widget-local controllers](ARCHITECTURE.md#43-widget-local-controllers-changenotifier) and the canonical `FilePaneController` / `UnifiedExportController` / `SessionPanelController` / `TransferPanelController` implementations.

### 6. UI — `lib/features/notes/notes_panel.dart`

Conventions (the analyzer catches most, but not all):

- **Buttons:** `AppIconButton`, never bare `IconButton`.
- **Hover:** `HoverRegion`, never custom `MouseRegion`.
- **Colors:** semantic constants from `AppTheme`, never raw `Colors.red`.
- **Font sizes:** `AppFonts.sm` / `md` / `lg`, never hardcoded `fontSize: 14`.
- **Border radius:** `AppTheme.radiusSm` / `radiusMd`, never `BorderRadius.circular(8)`.
- **Logging:** `AppLogger.instance.log(msg, name: 'Notes')`, never `print` / `debugPrint`. Auto-sanitised; see [§ AppLogger](ARCHITECTURE.md#applogger).

Full list in [CONTRIBUTING.md → Coding Conventions](CONTRIBUTING.md#coding-conventions).

### 7. Localization — `lib/l10n/app_*.arb`

Every user-visible string goes into **all 15** `app_*.arb` files (ar, de, en, es, fa, fr, hi, id, ja, ko, pt, ru, tr, vi, zh). Add the key once in `app_en.arb` with metadata, then mirror to other locales (machine translation is acceptable as a starting point — native speakers refine later).

```json
"notesPanelTitle": "Notes",
"@notesPanelTitle": { "description": "Title of the per-session notes panel" }
```

After editing `.arb`, run `make gen` to regenerate `lib/l10n/app_localizations*.dart`.

### 8. Tests — `test/core/notes/`, `test/features/notes/`, `test/providers/`

**One test file per source file.** Mirror the source tree:

```
lib/core/notes/note.dart            → test/core/notes/note_test.dart
lib/providers/notes_provider.dart   → test/providers/notes_provider_test.dart
lib/features/notes/notes_panel.dart → test/features/notes/notes_panel_test.dart
```

Patterns, helpers, and DI hooks: [ARCHITECTURE §14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks). In short:

- Pure logic → straight `test()`.
- Anything touching `ref.read()` → `ProviderContainer` with overrides.
- Anything that needs a real DB / SecretStore → `requireFrbLoaded()` + the in-process Rust fixture (see `test/integration/`).
- Widgets → `pumpWidget` wrapped via `test/helpers/`.
- Anything parsing untrusted input (JSON, URIs, file formats) → also add a fuzz target in `test/fuzz/`.

Test mocks are **hand-rolled** (`test/helpers/fake_*.dart`) — no `mockito` / `mocktail` (see [§14 Mocking discipline](ARCHITECTURE.md#mocking-discipline)).

Run `make check` — single gate covering format-check, lint (Dart analyzer + Rust clippy), workflow lint, release hardening, unused-deps, and tests for both languages. Must be green before commit; the pre-commit hook enforces this.

### 9. Documentation

If your feature adds a new `core/` module or changes a public contract, add a subsection to [`ARCHITECTURE.md`](ARCHITECTURE.md) under §3 (core) or §5 (features). Tiny additions extend the closest existing §.

User-visible feature → also walk through [`USER_GUIDE.md`](USER_GUIDE.md) and add an example.

### 10. Commit

One logical change per commit. Use the right [conventional prefix](CONTRIBUTING.md#commit-messages) — it drives the auto-changelog and version bump:

```
feat(notes): add per-session notes panel
```

Don't bump `pubspec.yaml` manually — the release pipeline does it from commit prefixes.

---

## Cross-Platform Checklist

LetsFLUTssh ships on Linux, Windows, macOS, Android, iOS. Before marking a feature done:

- [ ] Touched Android code? — also smoke-test iOS (and vice versa).
- [ ] Touched desktop code? — at minimum `make build-linux`; ideally also Windows or macOS.
- [ ] New file picker / clipboard / notification? — these have platform-specific quirks; check [§3 Core Modules](ARCHITECTURE.md#3-core-modules) for existing wrappers.
- [ ] Mobile UI? — the `features/mobile/` layer is separate from desktop layout (see [§5.6 Mobile](ARCHITECTURE.md#56-mobile-featuresmobile)).
- [ ] Touched any `cfg(target_os = ...)` Rust code? — `ci.yml::rust-cross-check` validates the Apple / Windows / Android cfg paths every PR (see [§3.14 CI gates](ARCHITECTURE.md#314-rust-securitytransport-core-rust)).

---

## Common Pitfalls

| Symptom | Likely cause |
|---|---|
| `make lint` complains about cognitive complexity | Method > 15 — extract a helper. Don't `// ignore:` |
| Test passes locally, fails in CI | Forgot `make gen` or `make rust-codegen` after editing ARB / FRB API. |
| String shows `notesPanelTitle` literally in UI | Missing key in some `app_*.arb`, or missed `make gen`. |
| Hover/focus looks off | Using `IconButton` / `InkWell` instead of `AppIconButton` / `HoverRegion`. |
| `lfs_os_security::secure_key_storage` errors on Linux | `libsecret-1-0` is an optional OS dep — `KeyringProbeResult` returns `linuxNoSecretService`, UI falls back gracefully. |
| Rust changes don't show up in Dart | Forgot to run `make rust-codegen` after editing `lfs_frb::api::*`. |

---

## Where to Ask

- Architecture question — check the [ARCHITECTURE.md table of contents](ARCHITECTURE.md#table-of-contents) first.
- Found a bug — open an issue with the `bug` label.
- Want to discuss a larger change before coding — open an issue with `discussion` first.

Welcome aboard.
