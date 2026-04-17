# Adding a Feature — Walkthrough

This is a hands-on tutorial for new contributors. It walks through adding a small feature end-to-end so you learn the project's layout, conventions, and tooling without reading [`ARCHITECTURE.md`](ARCHITECTURE.md) cover-to-cover.

If you're looking for build instructions, see [`CONTRIBUTING.md`](CONTRIBUTING.md). For deep technical reference, see [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## Mental Model

The codebase is split in two layers:

- **`lib/core/<domain>/`** — pure logic, models, stores, services. No widgets. Easy to unit-test
- **`lib/features/<feature>/`** — UI: screens, dialogs, widgets. Consume `core/` via Riverpod providers

State is shared through Riverpod providers in `lib/core/providers/`. Persistence goes through Drift (see [§3.10 Database](ARCHITECTURE.md#310-database--drift)). Strings live in `lib/l10n/app_*.arb` (one file per locale).

A good first scan: open `lib/core/snippets/` and `lib/features/snippets/` side-by-side — it's the smallest complete feature in the codebase and a fair template.

---

## Walkthrough — Add a "Notes" Feature

We'll add a per-session free-form notes field (a real feature you might pick up). Steps map 1:1 to the layers.

### 1. Model — `lib/core/notes/note.dart`

Immutable data class with `copyWith`, `==`, `hashCode`. Match the style of [`lib/core/snippets/snippet.dart`](../lib/core/snippets/snippet.dart):

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

  // == / hashCode / toString — see snippet.dart for the pattern
}
```

**Why no `freezed`?** The existing models in `core/` are hand-written for readability. `freezed` is used only where unions/sealed types pay for themselves (see existing `*.freezed.dart` for examples).

### 2. Store — `lib/core/notes/note_store.dart`

The store owns persistence. For new domains backed by Drift, follow the pattern in [`snippet_store.dart`](../lib/core/snippets/snippet_store.dart) — it loads on init, mutates in memory, writes through Drift on every change.

If the data is sensitive (credentials, tokens) it must go through `AesGcm` — see [§3.6 Security](ARCHITECTURE.md#36-security--encryption-coresecurity). Notes are not sensitive, so plain Drift is fine.

### 3. Provider — `lib/core/providers/notes/notes_providers.dart`

Riverpod is the **only** way state is shared. Never `static` mutable globals.

```dart
final notesProvider = AsyncNotifierProvider<NotesNotifier, List<Note>>(
  NotesNotifier.new,
);
```

Consumers should `.select()` the slice they need — see [§4 State Management](ARCHITECTURE.md#4-state-management--riverpod).

Widget-local state (dialog selection, pane caches, panel focus) does **not** belong in a Riverpod provider. Use `ChangeNotifier` + `AnimatedBuilder` instead — see [§4.3 Widget-local controllers](ARCHITECTURE.md#43-widget-local-controllers-changenotifier) and the canonical `FilePaneController` / `UnifiedExportController` / `SessionPanelController` / `TransferPanelController` implementations.

### 4. UI — `lib/features/notes/notes_panel.dart`

Conventions to respect (the analyzer will catch most, but not all):

- **Buttons:** `AppIconButton`, never bare `IconButton`
- **Hover:** `HoverRegion`, never custom `MouseRegion`
- **Colors:** semantic constants from `AppTheme`, never raw `Colors.red`
- **Font sizes:** `AppFonts.sm`/`md`/`lg`, never hardcoded `fontSize: 14`
- **Border radius:** `AppTheme.radiusSm`/`radiusMd`, never `BorderRadius.circular(8)`
- **Logging:** `AppLogger.instance.log(msg, name: 'Notes')`, never `print`/`debugPrint`

Full list in [CONTRIBUTING.md → Coding Conventions](CONTRIBUTING.md#coding-conventions).

### 5. Localization — `lib/l10n/app_*.arb`

Every user-visible string goes into **all** `app_*.arb` files (en, ru, de, es, fr, it, pt, zh, ja, ko, ar, fa, hi, tr, …). Add the key once in `app_en.arb` with metadata, then mirror to other locales (machine translation is acceptable as a starting point — native speakers refine later).

```json
"notesPanelTitle": "Notes",
"@notesPanelTitle": { "description": "Title of the per-session notes panel" }
```

After editing `.arb`, run `make gen` to regenerate `lib/l10n/app_localizations*.dart`.

### 6. Tests — `test/features/notes/`, `test/core/notes/`

**One test file per source file.** Mirror the source tree:

```
lib/core/notes/note.dart           → test/core/notes/note_test.dart
lib/core/notes/note_store.dart     → test/core/notes/note_store_test.dart
lib/features/notes/notes_panel.dart → test/features/notes/notes_panel_test.dart
```

Patterns, helpers, and DI hooks: [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks). In short:

- Pure logic — straight `test()`
- Anything touching `ref.read()` — `ProviderContainer` with overrides
- Widgets — `pumpWidget` wrapped via `test/helpers/`
- Anything parsing untrusted input (JSON, URIs, file formats) — also add a fuzz target in `test/fuzz/`

Run `make check` (analyzer + tests). Both must be green before commit — the pre-commit hook enforces this.

### 7. Documentation

If your feature adds a new `core/` module or changes a public contract, add a subsection to [`ARCHITECTURE.md`](ARCHITECTURE.md) under §3 (core) or §5 (features). Tiny additions don't need their own section — extend the closest existing one. See the [doc maintenance checklist](CLAUDE_RULES.md#documentation-maintenance-checklist).

### 8. Commit

One logical change per commit. Use the right [conventional prefix](CONTRIBUTING.md#commit-messages) — it drives the auto-changelog and version bump:

```
feat(notes): add per-session notes panel
```

Don't bump `pubspec.yaml` manually — the release pipeline does it from commit prefixes.

---

## Cross-Platform Checklist

LetsFLUTssh ships on Linux, Windows, macOS, Android, iOS. Before marking a feature done:

- [ ] Touched Android code? — also smoke-test iOS (and vice versa)
- [ ] Touched desktop code? — at minimum `make build-linux`; ideally also Windows or macOS
- [ ] New file picker / clipboard / notification? — these have platform-specific quirks; check [§3 Core Modules](ARCHITECTURE.md#3-core-modules) for existing wrappers
- [ ] Mobile UI? — the `features/mobile/` layer is separate from desktop layout (see [§5.6 Mobile](ARCHITECTURE.md#56-mobile-featuresmobile))

---

## Common Pitfalls

| Symptom | Likely cause |
|---|---|
| `make analyze` complains about cognitive complexity | Method > 15 — extract a helper. Don't `// ignore:` |
| Test passes locally, fails in CI | Forgot `make gen` after `.arb` or freezed edits |
| String shows `notesPanelTitle` literally in UI | Missing key in some `app_*.arb`, or missed `make gen` |
| Hover/focus looks off | Using `IconButton`/`InkWell` instead of `AppIconButton`/`HoverRegion` |
| `flutter_secure_storage` errors on Linux | `libsecret-1-dev` is an optional dep — fall back gracefully |

---

## Where to Ask

- Architecture question — check the [navigation table](CLAUDE_RULES.md#quick-navigation-by-task) first
- Found a bug — open an issue with the `bug` label
- Want to discuss a larger change before coding — open an issue with `discussion` first

Welcome aboard.
