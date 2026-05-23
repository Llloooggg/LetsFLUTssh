# LetsFLUTssh — Architecture & Technical Reference

## Table of Contents

- [1. High-Level Overview](#1-high-level-overview)
  - [1.1 Cross-language responsibility split](#11-cross-language-responsibility-split)
- [2. Module Map](#2-module-map)
- [3. Core Modules](#3-core-modules)
  - [3.1 SSH (`core/ssh/`)](#31-ssh-coressh)
  - [3.2 SFTP (`core/sftp/`)](#32-sftp-coresftp)
  - [3.3 Transfer Queue (`core/transfer/`)](#33-transfer-queue-coretransfer)
  - [3.4 Session Management (`core/session/`)](#34-session-management-coresession)
  - [3.5 Connection Lifecycle (`core/connection/`)](#35-connection-lifecycle-coreconnection)
  - [3.6 Security & Encryption (`core/security/`)](#36-security--encryption-coresecurity)
  - [3.7 Configuration (`core/config/`)](#37-configuration-coreconfig)
  - [3.8 Deep Links (`core/deeplink/`)](#38-deep-links-coredeeplink)
  - [3.9 Import (`core/import/`)](#39-import-coreimport)
  - [3.10 Update (`core/update/`)](#310-update-coreupdate)
  - [3.11 Keyboard Shortcuts (`widgets/core/shortcut_registry.dart`)](#311-keyboard-shortcuts-widgetscoreshortcut_registrydart)
  - [3.12 Snippets (`core/snippets/`)](#312-snippets-coresnippets)
  - [3.13 Session Recording (`core/session/session_recorder.dart`)](#313-session-recording-coresessionsession_recorderdart)
  - [3.14 Rust Security/Transport Core (`rust/`)](#314-rust-securitytransport-core-rust)
  - [3.15 Sync via WebDAV (`rust/crates/lfs_core/src/sync/`)](#315-sync-via-webdav-rustcrateslfs_coresrcsync)
- [4. State Management — Riverpod](#4-state-management--riverpod)
  - [4.1 Provider Dependency Graph](#41-provider-dependency-graph)
  - [4.2 Provider Catalog](#42-provider-catalog)
  - [4.3 Widget-local controllers (`ChangeNotifier`)](#43-widget-local-controllers-changenotifier)
- [5. Feature Modules](#5-feature-modules)
  - [5.1 Terminal with Tiling (`features/terminal/`)](#51-terminal-with-tiling-featuresterminal)
  - [5.2 File Browser (`features/file_browser/`)](#52-file-browser-featuresfile_browser)
  - [5.3 Session Manager UI (`features/session_manager/`)](#53-session-manager-ui-featuressession_manager)
  - [5.4 Tab & Workspace System](#54-tab--workspace-system)
  - [5.5 Settings (`features/settings/`)](#55-settings-featuressettings)
  - [5.6 Mobile (`features/mobile/`)](#56-mobile-featuresmobile)
  - [5.7 Recordings (`features/recordings/`)](#57-recordings-featuresrecordings)
- [6. Widgets — Public API Reference](#6-widgets--public-api-reference)
  - [6.1 Security & Tier Wizard Widgets](#61-security--tier-wizard-widgets)
- [7. Utilities — Public API Reference](#7-utilities--public-api-reference)
- [8. Theme System](#8-theme-system)
  - [8.1 Internationalization (i18n)](#81-internationalization-i18n)
- [9. Data Flow Diagrams](#9-data-flow-diagrams)
  - [9.1 SSH Connection Flow](#91-ssh-connection-flow)
  - [9.2 SFTP Init Flow](#92-sftp-init-flow)
  - [9.3 Session CRUD Flow](#93-session-crud-flow)
  - [9.4 File Transfer Flow](#94-file-transfer-flow)
- [10. Data Models](#10-data-models)
- [11. Persistence & Storage](#11-persistence--storage)
- [12. Platform-Specific Behavior](#12-platform-specific-behavior)
- [13. Security Model](#13-security-model)
- [14. Testing Patterns & DI Hooks](#14-testing-patterns--di-hooks)
- [15. CI/CD Pipeline](#15-cicd-pipeline)
  - [15.1 Branching Model](#151-branching-model)
  - [15.2 Workflow Graph](#152-workflow-graph)
  - [15.3 Workflow Catalog](#153-workflow-catalog)
  - [15.4 Makefile Targets](#154-makefile-targets)
- [16. Design Decisions & Rationale](#16-design-decisions--rationale)
  - [16.1 Architecture Choices](#161-architecture-choices)
  - [16.2 API Gotchas](#162-api-gotchas)
  - [16.3 Security Decisions](#163-security-decisions)
  - [16.4 Platform Decisions](#164-platform-decisions)
- [17. Dependencies](#17-dependencies)

---

## 1. High-Level Overview

```mermaid
flowchart TD
    main["<b>main.dart</b><br/>Entry point, MaterialApp, theme, routing<br/>isMobilePlatform → MobileShell / else → MainScreen"]
    features["<b>features/</b><br/>(UI + UX)"]
    providers["<b>providers/</b><br/>(Riverpod) global state"]
    widgets["<b>widgets/</b><br/>(reusable)"]
    core["<b>core/</b> (no UI)<br/>SSH, SFTP, sessions, security, config"]
    platform["<b>platform/</b><br/>Flutter-plugin adapters"]
    themeUtils["<b>theme/</b> + <b>utils/</b>"]

    main --> features
    main --> providers
    main --> widgets
    providers --> features
    features --> core
    features --> platform
    providers --> core
    providers --> platform
    providers --> themeUtils
```

**Layering principle:** `core/` holds data + logic + I/O and renders nothing. It imports **zero `package:flutter`** — no UI (`material` / `widgets` / `services` / `foundation`), no plugins (`path_provider`, `app_links`, `flutter_foreground_task`), no Riverpod, no l10n, no xterm. The one permitted framework edge is `flutter_rust_bridge`, the Rust bridge runtime that core wraps; everything else in core is pure Dart (`meta` for annotations, `uuid`, `path`). This is enforced by a fitness test ([`test/core/no_flutter_in_core_test.dart`](../test/core/no_flutter_in_core_test.dart)) that fails CI on a stray import. Consequences for placement: app-wide UI state → `providers/` (Riverpod); Flutter-plugin adapters (foreground service, camera bridge, local-FS sandbox dirs) → `platform/`; observable state core needs → a `dart:async` broadcast `Stream`, not `ChangeNotifier` / `ValueNotifier`; a sandbox/support path → resolved at the boundary and pinned Rust-side (`config_store_init`) so core reads it back from Rust, never `path_provider`. `features/` accesses `core/` through `providers/`. `widgets/` are reusable UI components with no business logic.

<a id="self-contained-binary-principle"></a>
**Self-contained-binary principle:** the released artefact must be **runnable by an end-user with zero manual setup beyond extracting / installing the bundle.** No "first install Python", no "first install JRE", no "first apt install …" as a hard requirement. External OS-level dependencies are allowed **only** when both conditions hold:

1. The app **degrades gracefully** without the dependency, with a clear in-UI message naming what's missing and what's lost (canonical example: Linux without `libsecret-1-0` → OS-keychain mode disabled, plaintext + master-password modes still available).
2. The user-facing `README.md` **Installation** section documents how to install the optional dependency per platform with a copy-pasteable command.

Order of preference when a feature needs OS capability: **bundle it** (e.g. SQLite via `sqlite3` build hooks, QR scanner via system frameworks `AVFoundation` / `AndroidX CameraX`) > **fall back to a built-in alternative** (e.g. master password instead of keychain) > **document an optional install** (last resort, only if the first two are impossible). Never ship a build that hard-requires a manual install step.

<a id="reuse-principle"></a>
**Reuse principle:** the codebase favours **shared modules over local one-offs** at every layer, not just UI. Repeated logic lives in named, parameterised primitives that can be extended; a second caller is the trigger to extract a shared helper, a third caller makes it mandatory. Concrete patterns this principle has produced:

- **UI primitives** in `lib/widgets/` — `AppIconButton`, `AppButton` (`.cancel`/`.primary`/`.secondary`/`.destructive`), `AppDialog` (+ `AppDialogHeader`/`Footer`), `HoverRegion`, `AppDataRow`, `AppDataSearchBar`, `StyledFormField`, `SortableHeaderCell`, `ColumnResizeHandle`, `StatusIndicator`, `MobileSelectionBar`. No widget that has more than one caller is duplicated.
- **Theme primitives** in `lib/theme/` — `AppTheme.radius{Sm,Md,Lg}`, `AppTheme.barHeight*`, `AppTheme.controlHeight*`, `AppTheme.itemHeight*`, `AppTheme.*ColWidth`, `AppFonts.{tiny,xxs,xs,sm,md,lg,xl}`. Hardcoded sizes/radii/heights are treated as bugs.
- **Cross-feature mixins and helpers** in `lib/core/**` — `SftpBrowserMixin` (shared SFTP init/upload/download for desktop + mobile browsers), `key_file_helper.dart` (PEM detection shared by importer / `~/.ssh` scanner / file picker), `breadcrumb_path.dart`, `column_widths.dart`, `progress_writer.dart`, `shell_helper.dart`. New cross-cutting logic gets a `*_helper.dart` or mixin instead of being inlined per call site.
- **DAO + Store layering** — every persisted entity has the same `Store → DAO` shape ([§11](#11-persistence--storage)); a new entity follows the existing template, not its own ad-hoc pattern.

The practical upshot: before adding a widget, helper, style constant, or store, search `lib/widgets/`, `lib/theme/`, and `lib/core/**` for an existing equivalent; if behaviour is close but not identical, extend the shared primitive (add a parameter) rather than fork it. Local one-offs are allowed only when the shared pattern genuinely doesn't fit, and the reason should be obvious from the code.

### 1.1 Cross-language responsibility split

The repo splits across three languages (Dart, Rust, native Kotlin / Swift / C++) by **what each layer is allowed to own**, not by what's convenient. This split is load-bearing for both the security model ([§3.6](#36-security--encryption-coresecurity)) and the architecture invariant from the migration plan ("Flutter renders, Rust thinks").

```mermaid
flowchart TD
    subgraph Dart["<b>Dart / Flutter</b> (lib/)"]
        widgets2["Widgets, dialogs, screens<br/>xterm.dart terminal renderer<br/>Localization (15 ARB files)<br/>Theme, navigation"]
        riverpod2["Riverpod state<br/>(UI-bound only:<br/>selection, loading, errors —<br/>NEVER plaintext secrets)"]
        listeners2["Bus prompt listeners<br/>(subscriptions to Rust Streams)"]
        password2["SecurePasswordField<br/>(zeroize on dispose)"]
        plumbingShim["Thin IPC shims:<br/>QR scanner / Storage permission /<br/>Foreground service hosting"]
    end

    subgraph Rust["<b>Rust</b> (rust/crates/)"]
        core2["<b>lfs_core</b><br/>SSH+SFTP (russh)<br/>Cryptography (RustCrypto family)<br/>SecretStore (sole plaintext owner)<br/>DB (rusqlite + SQLCipher)<br/>State machines (tier / auto-lock / orchestrators)<br/>Persisted state (sessions, config, known_hosts, …)<br/>Update orchestrator + .lfs/QR codec<br/>OpenSSH config parser, log sanitizer"]
        ossec2["<b>lfs_os_security</b><br/>OS-API calls for all 5 platforms:<br/>keystore / biometric / hardware vault /<br/>session lock listener / clipboard /<br/>backup exclusion<br/>Process hardening + anti-debug<br/>macOS code-signing pipeline"]
        frb2["<b>lfs_frb</b><br/>Type-safe Dart↔Rust bridge<br/>(no business logic — adapter only)"]
    end

    subgraph Native["<b>Native plumbing</b> (Kotlin / Swift)<br/>NO business logic — entry-point glue only"]
        kotlin2["Android Kotlin:<br/>LfsJniBootstrap (JavaVM handoff)<br/>LfsBiometricCallback (callback adapter)<br/>MainActivity (Flutter host)<br/>QrScannerActivity (CameraX UI)"]
        swift2["iOS / macOS Swift:<br/>QR scanner (AVCaptureSession UI)<br/>App / Window host shells"]
    end

    Dart -- "FRB calls" --> Rust
    Rust -- "FRB streams" --> Dart
    Rust -- "JNI / objc2 / extern \"C\"" --> Native
    Native -- "callbacks via extern fn" --> Rust
    Native -- "OS components<br/>(Service / FragmentActivity / etc.)" --> OSAPIs[("OS APIs")]
    Rust -- "direct OS-API calls" --> OSAPIs
```

**Decision tree** for "where does this code go?":

| Question | Layer |
|---|---|
| Pixels on screen? | **Dart** widgets |
| "What does the UI show right now?" | **Dart** Riverpod state |
| OS-API call? | **Rust** through a maintained crate (`security-framework` / `windows` / `jni` / `zbus` / `objc2`) |
| Parsing untrusted bytes? | **Rust** (always — memory-safety perimeter) |
| Touches secrets? | **Rust** SecretStore (always — plaintext-discipline boundary, [§3.6](#36-security--encryption-coresecurity)) |
| Persisted to disk? | **Rust** through atomic-write + fsync + chmod 0600 (`lfs_core::path::write_bytes_atomic` — write tmp + `sync_data` + rename + parent-dir `sync_all` on Unix; payload survives a power-loss between rename and the kernel flushing the data pages) |
| OS requires a JVM/UIKit class instance (Service / FragmentActivity / AVCaptureSession host)? | **Native shim** + JNI/objc2 callback into Rust |
| Native UI surface (camera preview, file picker)? | **Native** plugin → Dart wrapper → bytes flow into Rust for parsing |

**What "plumbing only" means in the native layer.** Native shims do *transitions*, not *decisions*:

- `LfsJniBootstrap.register(activity)` — hands a JavaVM handle to Rust, period.
- `LfsBiometricCallback.onAuthenticationSucceeded(reqId)` — forwards the event to a Rust `extern "system"` fn keyed on a per-prompt request id; doesn't decide what success means.
- `QrScannerActivity` — shows the camera, returns the scanned string back to Dart→Rust.
- Android `Service` (via `flutter_foreground_task`) — hosts the persistent-notification component; doesn't know what SSH is.

What native code does **NOT** contain: cryptography, key management, business decisions, persisted state, parsing of untrusted bytes. Anything in those categories belongs in Rust.

**Trace of one secret** (master password → unlock):

1. User types in `SecurePasswordField` (Dart) — controller wipes on dispose, no autocorrect / IME-learning / smart quotes.
2. Submit triggers a single FRB call `unlock_with_password(password)`.
3. Rust receives bytes, immediately wraps in `Zeroizing<Vec<u8>>`, hands to `SecretStore`.
4. `SecretStore::derive_kek()` runs Argon2id KDF; password bytes drop + Zeroize-clear.
5. KEK decrypts DB key from `credentials.kdf`; KEK drops + Zeroize-clear.
6. DB key lives in `mlock`-pinned Rust memory until a lock event.
7. Lock event (idle / OS lock / explicit) → DB key drop + Zeroize, `mlock` release, SQLCipher handle close, `SessionCredentialCache` evict.

Plaintext password exists in Dart heap on the order of milliseconds between steps 1 and 3, then everything is in Rust until the end of life. Per the plaintext-discipline invariant, this is the minimum possible exposure window for the chosen UX (typed master password).

**Rationale for keeping Riverpod in Dart** despite the "Rust owns logic" principle: state management = reactive subscription of UI to changes. Moving Riverpod to Rust would mean every `ref.watch(provider)` is an FRB hop (~50 µs each) — at 60 FPS × hundreds of `watch`es per frame this destroys the Flutter perf model. Riverpod state holds *handles* (session ids, UUIDs) and *flags* (is-loading, last-error), never plaintext credentials, so the security-via-Rust-ownership argument doesn't apply. See [§4 State Management](#4-state-management--riverpod) for the Riverpod patterns; see [§3.6 Security & Encryption](#36-security--encryption-coresecurity) for the plaintext-discipline boundary.

---

## 2. Module Map

```
lib/
├── main.dart                         # Entry point — `runZonedGuarded(_mainBody)`, RustLib init, single-instance, config preload, runApp. `LetsFLUTsshApp` + `_LetsFLUTsshAppState` (security controller wiring, lifecycle / lock-state listeners) live in `main_app.dart`; `MainScreen` + `_MainScreenState` (deep links, prompt listeners, first-launch banner, update dialog flow) live in `main_screen.dart` — both are `part of 'main.dart';`
├── app/                              # App-shell helpers pulled out of main.dart: global error dialog, already-running blocker, toolbar, deep-link wiring, import flow, navigator key, update dialog flow, `SecurityInitController` (migration → unlock → first-launch orchestrator) + `SecurityDialogPrompter` (seam around blocking dialogs — see §14 → Testing the controller), `security_dialogs.dart` (unmounted-fallback wrappers)
├── core/                             # Domain logic + I/O, renders nothing. Zero package:flutter (UI / plugins / Riverpod / l10n / xterm); only flutter_rust_bridge + pure Dart. Enforced by test/core/no_flutter_in_core_test.dart
│   ├── bus/                          # `AppBus` — Dart-side wrapper over the FRB bus subscription. Single global event hub the prompt listeners and notifiers subscribe to.
│   ├── db/                           # Thin Dart shim — schema + DAOs live Rust-side under `lfs_core::db` (rusqlite + bundled SQLCipher 4.x)
│   │   ├── rust_db_init.dart         # `lfsCoreDbExists` (existence probe) / `verifyRustDbReadable` (post-unlock SELECT probe) / `ensureRustDbOpen({key, secretId})` (Rust handle bring-up). `dbClose` is invoked directly through the FRB-bridged `lib/src/rust/api/app.dart` shim from auto-lock + the controller.
│   │   ├── mappers.dart              # Domain ↔ FRB DTO conversion (folder path↔tree, session row↔model)
│   │   └── _folder_path_compat.dart  # Folder-path resolver used by the import path
│   ├── ssh/                          # SSH client, config, TOFU, errors
│   ├── sftp/                         # SFTP operations, file models, FileSystem
│   ├── transfer/                     # File transfer queue
│   ├── session/                      # Session model, persistence, tree, history, recorder, port-forward DAO
│   ├── connection/                   # Connection lifecycle, progress tracking, ConnectionExtension
│   ├── security/                     # Tier ladder + keychain wrappers + biometric auth + master password — every backend lives Rust-side under `lfs_os_security::*` and `lfs_core::security::*`
│   ├── migration/                    # Dart shim over `lfs_core::migration` (FRB DTO re-exports + `runStartupMigrations()`). Runner, registry, artefacts all live Rust-side. Full description: §3.6 → Migration framework
│   ├── config/                       # App configuration (file-based, loaded before DB)
│   ├── snippets/                     # Snippet model + template engine
│   ├── tags/                         # Tag model
│   ├── deeplink/                     # Deep link handling
│   ├── import/                       # Data import/export orchestration (.lfs archive, key files)
│   ├── progress/                     # ProgressReporter — phase/step stream consumed by AppProgressBarDialog and connection-progress widgets
│   └── update/                       # Update checking
├── platform/                         # Flutter-plugin platform adapters kept out of `core/`: `foreground_service.dart` (flutter_foreground_task), `qr_scanner.dart` (camera bridge via `flutter/services`)
├── features/                         # UI modules
│   ├── terminal/                     # Terminal with tiling
│   ├── file_browser/                 # Dual-pane SFTP browser
│   ├── session_manager/              # Session management panel
│   ├── key_manager/                  # SSH key manager (embeddable; standalone dialog on mobile, inside Tools on desktop)
│   ├── snippets/                     # Snippet manager + terminal picker
│   ├── tags/                         # Tag manager + assignment dialog
│   ├── tools/                        # Desktop Tools dialog (SSH Keys, Snippets, Tags, Known Hosts, Recordings)
│   ├── tabs/                         # Tab model (TabEntry, TabKind)
│   ├── workspace/                    # Workspace tiling (panels, tab bars, drop zones)
│   ├── settings/                     # Settings + export/import
│   ├── recordings/                   # Recordings browser + xterm playback dialog (engine in `core/session/session_recorder.dart`)
│   └── mobile/                       # Mobile version (bottom nav)
├── l10n/                             # Internationalization (15 languages: ar, de, en, es, fa, fr, hi, id, ja, ko, pt, ru, tr, vi, zh)
├── providers/                        # Riverpod providers (global state)
├── widgets/                          # Reusable UI components, grouped by role. Widgets import siblings via relative paths; cross-subfolder via `../<sub>/`.
│   ├── core/                         # Generic design-system primitives — no feature knowledge
│   │   ├── app_button.dart           # AppButton + named ctors (.cancel / .primary / .secondary / .destructive)
│   │   ├── app_dialog.dart           # Unified dialog shell, header, footer, action buttons, progress dialog
│   │   ├── sidebar_nav_dialog.dart   # VS-Code-style nav-rail + lazy keep-alive content pane (Tools + Settings dialogs)
│   │   ├── app_data_row.dart         # Shared row for list / table dialogs — icon + title + secondary + tertiary + trailing actions
│   │   ├── app_collection_toolbar.dart # Shared header (search + add + secondary action) for list-style managers
│   │   ├── app_collection_panel.dart  # Generic load→search→list manager shell (CollectionManagerPanel<T>) behind the Keys, Tags + Snippets managers
│   │   ├── app_icon_button.dart      # Rectangular hover button (replaces Material IconButton)
│   │   ├── app_selection_area.dart   # Local-scope text-selection wrapper used inside dialogs / threat lists / help prose
│   │   ├── app_shell.dart            # Desktop layout shell (toolbar, sidebar, body, status bar)
│   │   ├── hover_region.dart         # MouseRegion + GestureDetector replacement
│   │   ├── context_menu.dart         # Custom context menu with keyboard nav
│   │   ├── confirm_dialog.dart / typed_name_confirm_dialog.dart # Destructive-action confirmations
│   │   ├── styled_form_field.dart    # Shared form field (StyledFormField, FieldLabel, StyledInput)
│   │   ├── form_submit_chain.dart    # FocusNode + Enter-to-next/submit wiring for multi-field dialogs
│   │   ├── shortcut_registry.dart    # `AppShortcut` enum + `AppShortcutRegistry`. See §3.11.
│   │   ├── status_indicator.dart, error_state.dart, app_empty_state.dart, toast.dart, app_divider.dart, app_bordered_box.dart
│   │   ├── app_info_button.dart, app_info_dialog.dart, app_picker_chip.dart, app_popup_select.dart, dropdown_select_button.dart, mode_button.dart
│   │   ├── sortable_header_cell.dart, column_resize_handle.dart, clipped_row.dart, marquee_mixin.dart, threshold_draggable.dart, split_view.dart, data_checkboxes.dart
│   │   └── tag_color.dart, tag_dots.dart, session_kind_icon.dart, mobile_selection_bar.dart
│   ├── security/                     # Lock / unlock / tier ladder UI
│   │   ├── lock_screen.dart          # Full-screen lock overlay — biometric → master-password fallback, flips lockStateProvider
│   │   ├── unlock_dialog.dart        # Master password unlock dialog (startup)
│   │   ├── secure_password_field.dart # TextField for secret entry — IME spellcheck/autofill/history disabled
│   │   ├── secure_screen_scope.dart  # Scope opting subtree into OS screen-capture protection (Android FLAG_SECURE)
│   │   ├── auto_lock_detector.dart   # Inactivity wrapper — locks after autoLockMinutesProvider when level is masterPassword
│   │   ├── expandable_tier_card.dart # Settings Security ladder unit (split into _header / _inputs / _logic / _threats parts)
│   │   ├── security_setup_dialog.dart # First-launch wizard — tier + modifier-shape choice (split into _logic / _widgets parts)
│   │   ├── security_comparison_table.dart, security_threat_list.dart # Threat × tier matrix + per-tier inventory
│   │   ├── tier_reset_dialog.dart, tier_secret_unlock_dialog.dart, db_corrupt_dialog.dart
│   │   └── password_strength_meter.dart, first_launch_security_toast.dart
│   ├── ssh_keys/                     # Hardware / SSH-key dialogs + badges (see §3.6 area)
│   │   ├── hardware_key_wizard.dart  # `HardwareKeyWizardMixin` — shared probe→configure→generate→complete scaffold
│   │   ├── hardware_key_badge.dart   # Shared hardware-key row pill (colour + icon + optional tap popover)
│   │   ├── enclave_/hello_/keystore_/tpm_ssh_dialog.dart # Per-backend wizards on the shared mixin
│   │   ├── pkcs11_import_dialog.dart (+ _logic part), hardware_key_prompt_dialog.dart, agent_signature_request_dialog.dart
│   │   └── host_key_dialog.dart      # TOFU dialogs (new host / key changed)
│   ├── import_export/                # .lfs / QR / link import + export surfaces
│   │   ├── unified_export_dialog.dart (+ _tree, _models, controller) # Unified QR + .lfs export
│   │   ├── lfs_import_dialog.dart, lfs_import_preview_dialog.dart, link_import_preview_dialog.dart, import_preview_dialog.dart
│   │   ├── paste_import_link_dialog.dart, ssh_dir_import_dialog.dart, local_directory_picker.dart
│   │   └── file_conflict_dialog.dart # Destination-exists prompt (Skip / Keep both / Replace / Cancel + apply-to-all)
│   └── terminal/                     # Terminal rendering widgets (engine in features/terminal)
│       ├── app_terminal_view.dart, readonly_terminal_view.dart, xterm_shell_terminal.dart
│       ├── anchor_pinning_terminal_controller.dart, terminal_cell_metrics.dart
│       └── connection_progress.dart, progress_writer.dart, update_progress_indicator.dart
├── theme/                            # OneDark / One Light palettes
└── utils/                            # Utilities: logger, format, platform
```

### `dev/` — non-shipping dev tooling

The `dev/` tree holds tooling that never ends up in a release artefact:

- `dev/scripts/` — repo-management shell + Dart scripts (`install-hooks.sh`, `bump-version.sh`, `run-mutants.sh`, `check-arb-parity.sh`, `filter_lcov.dart`, `agent-plan-id-gate.sh`, `setup-xcode-broker.sh`). Wired into the Makefile and the CI workflows. `make hooks` installs the pre-commit gate from here.
- `dev/compose/` — Docker Compose stack for manual QA of the `lfs_core::{s3, webdav, ssh, sftp}` transports against real servers (MinIO, two Apache mod_dav variants for Basic + Digest, Nextcloud for Bearer, `linuxserver/openssh-server`). All services bind to `127.0.0.1` with hard-coded dev credentials. See `dev/compose/README.md`.

Both subtrees are git-tracked but excluded from every build target — Flutter and Cargo neither read nor copy from `dev/`.

---

## 3. Core Modules

### 3.1 SSH (`core/ssh/`)

The SSH engine lives entirely in Rust; the Dart side is a thin transport interface, a typed connect-request / shell-channel surface, plus a few Dart-only concerns (per-session port-forwarding lifecycle, ProxyJump orchestration, the OpenSSH config import path) that wrap russh primitives without speaking the protocol themselves. See [§3.14 Rust core](#314-rust-securitytransport-core-rust) for the workspace structure and the FRB boundary.

#### Files and responsibilities

| File | Class/Function | Purpose |
|------|---------------|---------|
| `transport/ssh_transport.dart` | `SshTransport` interface, `SshAuthMethod` family (`SshAuthPassword`, `SshAuthPubkey`, `SshAuthPubkeyCert`, `SshAuthAgent` + `*Ref` variants), `SshShellChannel`, `SshDirectTcpipChannel`, typed errors (`SshAuthFailed`, `SshConnectError`, `SshHostKeyRejected`) | Engine-agnostic transport surface — `connect` / `openShell` / `openSftp` / `openDirectTcpip` / `requestRemoteForward`. `RustTransport` is the only impl; the interface stays so tests can swap in fakes through the constructor seam on `ConnectionsNotifier`. |
| `transport/rust_transport.dart` | `RustTransport` | Routes channel-ops calls into FRB (`lfs_core::ssh`). The Rust connection actor builds the authenticated session; this wrapper bridges the channel-ops surface and materialises shell + direct-tcpip channels as Dart streams. ProxyJump dialled child sessions adopt the parent's session via `RustTransport.adopt(session)` rather than re-connecting on the bridge. |
| `ssh_config.dart` | `SSHConfig`, `SshAuth`, `ServerAddress` | Config model carried across the connect path. `SshAuth` carries `password`, `keyPath`, `keyData`, `keyId`, `passphrase`, plus the `useAgent` flag (`Session.toSSHConfig` sets it from `authType == AuthType.agent`); the connect path stages stored secrets via `db_sessions_stage_secrets` / `db_ssh_keys_stage_secret` so the bytes never round-trip through the Dart heap (see [§3.6 Security boundary](#36-security--encryption-coresecurity)). When `useAgent` is set, `ConnectionsNotifier._authFromConfig` short-circuits to `SshAuthAgent` before the auth composer runs — the system ssh-agent owns the credential and no SecretStore staging is required. |
| `openssh_config_parser.dart` | `parseOpenSshConfig()` | OpenSSH `~/.ssh/config` parser — Host/HostName/User/Port/IdentityFile. Wildcards and global scope skipped. Used by the one-time SSH-dir import path; never touched at connect time. |
| `providers/known_hosts_provider.dart` | `KnownHostsNotifier` | UI-side notifier that mirrors the `known_hosts` table in `letsflutssh.db`. Subscribes to the `BusTopic::KnownHosts` stream so the cache refreshes whenever any code path mutates the table; the actual TOFU host-key verification flow is owned by `lfs_core::known_hosts` and the FRB-side prompt protocol (see [#§3.1 Auth chain](#auth-chain)) — Dart never gates auth itself. Mutators (`add` / `remove` / `clear`) issue the matching FRB DAO calls + reload. |
| `errors.dart` | `ConnectError`, `AuthError`, `HostKeyError`, `ProxyJumpCycleError`, `ProxyJumpDepthError`, `ProxyJumpBastionError` | UI-facing error hierarchy with structured fields (host, port, user) for localisation. The transport layer raises `SshAuthFailed` / `SshConnectError` / `SshHostKeyRejected`; `ConnectionsNotifier._failureStep` maps those into the typed errors above. |
| `port_forward_rule.dart` | `PortForwardRule`, `PortForwardKind` | Immutable rule model for the per-session forwarding tab. |
| `port_forward_runtime.dart` | `PortForwardRuntime` | Implements [`ConnectionExtension`](#connectionextension--lifecycle-add-ons); thin shim that asks `lfs_core::portforward::driver` to spawn / stop the `-L` / `-D` / `-R` listeners against the live connection actor on connect / disconnect. No accept loop or SOCKS5 handshake on the Dart side. |
| `shell_helper.dart` | `ShellHelper.openShell()` | Shared shell-open path used by the terminal pane + session recorder. Returns a `ShellConnection` wrapping the FRB shell handle. |
| `rust/crates/lfs_core/src/ssh/mod.rs` | `lfs_core::ssh::Session` | russh client wrapper — connect, userauth (password / pubkey / pubkey-cert / sk-key / agent), `openShell`, `openSftp`, `openDirectTcpip`, `requestRemoteForward`. Host-key verification runs entirely Rust-side: the russh `check_server_key` callback consults `lfs_core::known_hosts` directly + raises `BusEvent::KnownHostPromptRequest` for unknown / mismatched fingerprints; the Dart side's `HostKeyPromptListener` (`lib/app/host_key_prompt_listener.dart`) shows the dialog and resolves the prompt via the known-host bus command. |
| `rust/crates/lfs_core/src/ssh/sk.rs` | `lfs_core::ssh::sk` | FIDO2 `sk-*` userauth glue — `FidoCredential` type, `sign_for_userauth`, `algorithm_from_key_type`, `extract_application_from_openssh_pub`. Bridges `lfs_core::fido2::get_assertion` (CTAP2 round trip) to the SSH `sk-*` signature trailer + outer wire string. |
| `rust/crates/lfs_core/src/fido2/brokers.rs` | `lfs_core::fido2::brokers` | Transport dispatcher between the OS-managed FIDO2 broker (`lfs_os_security::fido2_broker`) and the direct HID path (`lfs_core::fido2::client`). Hosts the process-wide `PREFER_DIRECT_HID` atomic + the pure-data `select_transport(Availability) -> Transport` decision; called from `fido2::is_available` / `fido2::get_assertion`. |
| `rust/crates/lfs_os_security/src/fido2_broker.rs` | `lfs_os_security::fido2_broker` | OS-managed FIDO2 broker — Windows `webauthn.dll` direct FFI under `windows = "0.62"` `Win32_Networking_WindowsWebServices`; Apple `ASAuthorizationSecurityKeyPublicKeyCredentialProvider` via the C-ABI Swift glue at `macos/Runner/SecurityKeyBroker.swift` / `ios/Runner/SecurityKeyBroker.swift` (loaded through `libloading` against the running bundle); Android `androidx.credentials.CredentialManager` via the `Fido2Broker.kt` Kotlin shim called through JNI. Surfaces `BrokerAssertion` / `BrokerError` typed shapes the dispatcher maps to `Error::Fido2`. |
| `macos/Runner/SecurityKeyBroker.swift`, `ios/Runner/SecurityKeyBroker.swift` | Swift glue | `@_cdecl` C-ABI exports (`lfs_security_key_broker_is_available`, `lfs_security_key_broker_get_assertion`) the Rust `fido2_broker::apple` module resolves through `libloading`. Drives `ASAuthorizationController` against the `ASAuthorizationSecurityKeyPublicKeyCredentialProvider` request; delegate marshals success / failure back through a C callback the dispatcher's pending map awaits on. |
| `android/app/src/main/kotlin/com/llloooggg/letsflutssh/Fido2Broker.kt` | Kotlin JNI shim | Bridges `lfs_os_security::fido2_broker::android` to `androidx.credentials.CredentialManager.getCredential` + `GetPublicKeyCredentialOption`. Mirrors the `KeystoreSshSigner.kt` shape: static `object`, JNI `external` companions, no business logic. Maps typed Credential Manager exceptions to the dispatcher's reason tags. |
| `rust/crates/lfs_core/src/ssh/sk_signer.rs` | `lfs_core::ssh::sk_signer::FidoSigner` | `russh::Signer` adapter that routes per-message SSH userauth signatures through a FIDO2 hardware authenticator. Used by `Session::connect_pubkey_sk` + the proxy mirror, plus the cert-bearing twins `Session::connect_pubkey_sk_cert` / `_via_proxy` that compose this signer with russh 0.59's `authenticate_certificate_with<S: Signer>`. Private key material never reaches the heap — every signature attempt round-trips through `sk::sign_for_userauth`. |
| `rust/crates/lfs_core/src/ssh/wire.rs` | `lfs_core::ssh::wire` | Shared SSH wire-format primitives (mpint encoding, ECDSA DER → SSH mpint, fixed-width raw `r\|\|s` → SSH mpint, RSA / Ed25519 signature wrappers, public-key blob encoders). Used today by `ssh::sk`; reserved for the PKCS#11 / TPM 2.0 / Secure Enclave / NCrypt / Hardware Keystore signers landing in subsequent commits. |
| `rust/crates/lfs_core/src/ssh_agent/` | `lfs_core::ssh_agent` | In-process ssh-agent endpoint exposing hardware-bound keys to external SSH clients (`git`, `ssh`, IDE plugins) on the same host. `endpoint.rs` carries the `impl Session for Endpoint` + per-platform accept loop and the `run_sign` helper shared between the bare and cert sign paths; `loop_runner.rs` runs our custom u32-framed dispatch loop (cert-aware IDENTITIES_ANSWER routes via `identities`; cert-form SIGN_REQUEST is intercepted and routed through `run_sign` after a `Certificate::from_bytes` decode + bare-key row lookup; every other verb falls back to `Session::handle`); `identities.rs` walks `ssh_keys` + `ssh_key_certificates` and emits bare + cert blobs per identity; `backends.rs` dispatches signs by `BackendKind`; `transport.rs` binds the per-platform listener (UDS on Linux/macOS, named pipe on Windows); `per_key_confirm.rs` parks SIGN_REQUEST prompts and surfaces them via the `EventTopic::SshAgent` bus. Mobile builds resolve to the no-op `stub.rs`. See [In-process ssh-agent endpoint](#in-process-ssh-agent-endpoint) above. |

#### SSH transport surface

`RustTransport` is the only implementation of `SshTransport`. Lifecycle and contract:

```dart
abstract class SshTransport {
  void adopt(rust_ssh.SshSession session);
  Future<SshShellChannel> openShell({required int cols, required int rows});
  Future<dynamic> openSftp();
  Future<SshDirectTcpipChannel> openDirectTcpip({...});
  Future<int>  requestRemoteForward(String address, int port);
  Future<void> cancelRemoteForward(String address, int port);
  Future<void> disconnect();
  bool get isConnected;
}
```

The Rust connection actor owns the connect handshake itself — `connectAsync` in `ConnectionsNotifier` enqueues an `lfs_core::connection::ConnectCommand` over FRB; the actor authenticates via russh, publishes `BusEvent::ConnectionStateChanged(Connected)`, and the Dart `Connection` hands the resulting handle to `RustTransport.adopt(session)` (see `_adoptSession` in [§3.5](#35-connection-lifecycle-coreconnection)).

Auth method selection happens before the FRB hop in `ConnectionsNotifier._authFromConfig`:

- `SshAuthPasswordRef(secretId)` / `SshAuthPubkeyRef(secretId, passphraseSecretId)` / `SshAuthPubkeyCertRef(...)` — the bytes already live in the [`SecretStore`](#36-security--encryption-coresecurity) under the named ids, so the actor passes only the ids; russh fetches the bytes inside Rust.
- `SshAuthPassword(password)` / `SshAuthPubkey(pem, passphrase)` — quick-connect fallback for the no-session-id path; the Dart heap holds the bytes for the duration of the connect attempt and the matching transient SecretStore entry is dropped when the attempt completes.
- `SshAuthAgent` — proxies through the OS ssh-agent socket; no key bytes cross the boundary.

`SshSession` inside Rust is held under `Mutex<Option<Arc<lfs_core::ssh::Session>>>`. Every channel-opening call in `RustTransport` clones the `Arc` under a short-lived lock, drops the lock, then awaits — long-running `openShell` / `openSftp` calls do not block one another and the surface is reentrant per session.

Inbound `-R` connections do not surface on the transport at all: the Rust dispatcher (`lfs_core::ssh::Session::register_remote_forward_route` + `lfs_core::portforward::driver::spawn_remote_forward`) is the **sole** consumer of the per-session `forward_rx`. Each `portForwardStartRemote` registers a route keyed by `(bind_host, bound_port)`; the dispatcher fans out from `forward_rx` to the matching route's bridge task, which opens a TCP connection to the local target and pumps bytes. Funnelling everything through one consumer is intentional — an earlier Dart-side pump that subscribed to the same `forward_rx` raced the Rust dispatcher for every inbound channel, leaving forwards stuck whenever the Dart side won the lock.

#### Auth chain

The transport receives **one** auth method per connect attempt. `ConnectionsNotifier._authFromConfig` picks it before calling `connect`:

0. `SshAuth.useAgent` (set by `Session.toSSHConfig` when the saved session row carries `AuthType.agent`) → short-circuit to `SshAuthAgent` before the auth composer runs. The system ssh-agent owns every signature (`$SSH_AUTH_SOCK` on Unix, OpenSSH named pipe / Pageant on Windows) so SecretStore staging is skipped. Desktop-only — the session-edit dialog hides the toggle on Android / iOS because no system agent endpoint exists there. Mobile instead always renders the password / key fields: an imported `AuthType.agent` session keeps its type while those fields stay blank (so an import → edit → export round-trip back to desktop is lossless), and `_derivedAuthType` converts it to a usable password / key session once the user fills them. `.lfs` import / export itself is Rust-side and never touches this dialog, so the agent type survives a round-trip regardless of whether the session is opened on mobile.
1. `sessionId` set + `db_sessions_stage_secrets` returns `has_key_data` → `SshAuthPubkeyRef("sess.key.<id>", passphraseSecretId: "sess.passphrase.<id>" if staged)`.
2. `sessionId` set + `has_password` → `SshAuthPasswordRef("sess.password.<id>")`.
3. `auth.keyId` set + `db_ssh_keys_stage_secret` returns true → `SshAuthPubkeyRef("key.priv.<keyId>", passphraseSecretId: "key.passphrase.<keyId>" if user typed a passphrase for this attempt)`.
4. Quick-connect: inline `auth.keyData` / `auth.password` → push into a transient SecretStore entry under `conn.<slot>.<uuid>` and emit the same Ref variants.
5. Empty auth → `SshAuthPassword('')` so russh surfaces "no credentials" rather than auto-rejecting.

If the user has an encrypted key and no stored / passed passphrase, `RustTransport.connect` raises `SshAuthFailed` with detail `passphrase required`; `ConnectionsNotifier` catches it, runs the interactive `PassphrasePromptCallback` (up to `maxPassphraseAttempts = 3`), and retries with the new passphrase staged into the SecretStore.

**Auth-failure detail.** Every pubkey/cert/agent auth site funnels its russh `AuthResult` through `check_auth_result()` (`ssh/mod.rs`). On rejection it emits `Error::Auth("server rejected the credential — methods the server still offers: <list>[; partial success]")` instead of a bare `AuthFailed`, so the connection-log step `detail`, the `ConnectionError` event, and the `CoreConnect` warn line all explain *why* the attempt failed. The agent loop reports the identity count when every key is rejected. The SSH protocol exposes nothing more granular — a server never reports *which* key was wrong (anti-enumeration), so per-attempt this is the honest ceiling; transport-level visibility (negotiated algorithms / `server-sig-algs`) needs the verbose connection log.

#### KnownHostsNotifier

```dart
class KnownHostsNotifier extends Notifier<Map<String, String>> {
  // Subscribes to BusTopic::KnownHosts in build(); every mutation
  // anywhere in the workspace fires a BusEvent::KnownHostsChanged
  // and the listener triggers reload().
  Future<void> load();             // hydrates the in-memory cache from DAO (idempotent)
  Future<void> reload();           // force re-fetch
  void invalidateCache();          // dropped on auto-lock unlock so stale rows don't survive a tier switch

  // Read access:
  Map<String, String> get entries;           // {hostPort → "keyType base64Key"}
  int get count;
  static String fingerprint(List<int> keyBytes);

  // CRUD — every mutator goes through the FRB DAO; the resulting
  // bus event refreshes the cache:
  Future<void> add(String host, int port, String keyType, String base64Key);
  Future<void> remove(String hostPort);
  Future<void> removeMultiple(Set<String> hostPorts);
  Future<void> clearAll();
  Future<int> importFromFile(String path);   // merge entries, returns added count
  Future<int> importFromString(String content);
  String exportToString();                   // serialise to the LetsFLUTssh wire format
}
```

The TOFU verification flow is **not** a Dart concern. The russh host-key callback in `lfs_core::ssh::Session` consults `lfs_core::known_hosts` directly; on a mismatch / unknown host it raises `BusEvent::KnownHostPromptRequest { connection_id, host, port, fingerprint, kind }` and awaits the prompt resolution through `lfs_core::security::known_host_prompt`. The Dart-side [`HostKeyPromptListener`](../lib/app/host_key_prompt_listener.dart) subscribes to that bus event, renders [`HostKeyDialog`](#hostkeydialog), and resolves the prompt via the matching bus command. `KnownHostsNotifier` is **only** the UI-side cache mirror; it does not gate auth, does not hold a `verify` method, and never blocks the connect path on user input.

While the host-key prompt is on screen the connect driver's `ssh_timeout_sec` cap is suspended — the wall-clock spent waiting on the user does not count against the network budget. See [§3.5 Connect timeout](#connect-timeout--ssh_timeout_sec-with-prompt-pause) for the pause-aware-timeout machinery.

**Pre-unlock degradation.** Every entry point catches the synchronous `RustLib.instance` throw the FRB layer raises before the native lib is loaded (unit-test runner, first-launch wizard pre-unlock) and returns the in-memory cache only. The connect path doesn't run pre-unlock anyway; the bus subscription installed in `build()` simply fails-soft until the FRB lib is up.

#### Port forwarding

Per-session rules — model + persistence + lifecycle — that open `ssh -L`-style local listeners on connect and tear them down on disconnect. The model lives in `port_forward_rule.dart` (`PortForwardRule { id, kind, bindHost, bindPort, remoteHost, remotePort, description, enabled, sortOrder, createdAt }`), the runtime in `port_forward_runtime.dart`.

**Persistence.** `port_forward_rules` table in `letsflutssh.db` joined to `sessions` with `ON DELETE CASCADE`. `SessionNotifier.loadPortForwards / upsertPortForward / deletePortForward` are the public surface; the FRB DAO never escapes the store.

**Runtime — `PortForwardRuntime` implements `ConnectionExtension`.** Built by `_attachPortForwards` in `features/session_manager/session_connect.dart` only when the session has at least one saved rule (so a session with zero rules pays nothing). The runtime is registered on the [`Connection`](#connectionextension--lifecycle-add-ons) before [`ConnectionsNotifier`](#connectionsnotifier) calls `connectAsync`'s underlying `_doConnect`, so when the transport reaches `state == connected` the standard fan-out fires `onConnected` and the runtime asks `lfs_core::portforward::driver` to spawn the listeners with no race against the new transport assignment.

**Listener model — three kinds, all Rust-driven.** `onConnected` dispatches by `PortForwardKind` onto the FRB driver entry points (`port_forward_start_local` / `port_forward_start_dynamic` / `port_forward_start_remote`). Every variant takes the active connection actor's id; the driver resolves it to the live russh `Session` via `lfs_core::app::instance().connections` and spawns the accept-loop / inbound-bridge task on the tokio runtime. Per-rule kind:

| Kind | Rust driver behaviour |
|---|---|
| `local` (-L) | tokio `TcpListener` on `bind_host:bind_port`. Each accepted socket opens a fresh russh `direct-tcpip` channel to `target_host:target_port` and bridges both directions via `tokio::io::copy_bidirectional`. |
| `remote` (-R) | russh `tcpip-forward` request asks the server to listen on `bind_host:bind_port`. The session-level dispatcher routes inbound `forwarded-tcpip` channels by `(connected_address, connected_port)`; the per-rule task dials out locally to `target_host:target_port` and bridges. Server rejection surfaces immediately as a driver error. |
| `dynamic_` (-D) | tokio `TcpListener` plus a SOCKS5 CONNECT-only handshake (RFC 1928, NO_AUTH, IPv4 / domain / IPv6 address types). After parsing the target the driver opens a fresh `direct-tcpip` channel and bridges. |

Every state transition (`Listening` / `Error`) flows on the `EventBus` as `PortForwardStatus` events keyed by rule id; the FRB-generated `BusEvent_PortForwardStatus` reaches Dart subscribers through `AppBus`. Status events do not depend on a Dart-side stream controller.

**Failure isolation.** Listener bind failures (port already in use, permission denied), `tcpip-forward` rejections, and accepted-socket bridge errors all emit an `Error` status event for the offending rule and abort that rule's task; the rest of the rules are unaffected because each `port_forward_start_*` call spawns its own driver. A `setRules` call replaces the in-memory list but does not reopen on the spot — listeners only refresh on the next reconnect, so the user does not get surprise port-bind ripples while editing rules in a dialog.

**Teardown.** `_teardown` (called from `onDisconnecting` and `onReconnecting`) iterates the runtime's per-rule armed map and issues the matching `port_forward_stop_*` FRB call. Each stop drops the registry entry, which aborts the tokio listener task, closes the local socket (`-L` / `-D`) or withdraws the server-side `tcpip-forward` registration (`-R`). Stop calls are idempotent on a missing rule id, so racing a transport teardown against a rule that already errored is safe.

**UI — Forwarding editor.** `features/session_manager/session_forwards_tab.dart` is the rule list + editor body. After the session-edit dialog redesign to a single-form layout (§5.3), the editor no longer sits in a tab; it is opened from the Advanced section's "Manage…" button via the `SessionForwardsDialog` modal wrapper. The Advanced row + Manage button render **only when the active `SessionKind` is `ssh`** — WebDAV and S3 transports cannot multiplex TCP. The tab owns no state — the parent dialog holds `_forwards: List<PortForwardRule>` and re-renders on `onChanged`. Edits land via the in-line `_ForwardRuleEditor` modal which validates port range / required target host before returning the rule. Persistence is deferred to the parent dialog's Save: `SaveResult.forwards` carries the in-memory list out, and `session_panel._syncForwards` diffs against the store (delete missing ids, upsert the rest) after the session row commits, so the FK constraint sees a real parent. Quick-connect / new-session paths that never touch the tab pass an empty list and skip the diff entirely.

#### ProxyJump — bastion chains

Per-session "bounce through a bastion before reaching the final host" model. Saved-session bastions (`Session.viaSessionId`) take precedence over one-off overrides (`Session.viaOverride`); the loader / mapper enforce the rule by zeroing the override columns whenever `viaSessionId` is non-null, so a stray partial override left over from a prior edit cannot resurrect after the user clears the saved-session reference.

**Persistence.** Four columns on `sessions`:

| Column | Type | Notes |
|---|---|---|
| `via_session_id` | `TEXT NULL` references `sessions(id) ON DELETE SET NULL` | Saved-session bastion. `SET NULL` so deleting a bastion does not cascade-delete every session that referenced it; the UI surfaces the orphan as "lost jump host". |
| `via_host` / `via_port` / `via_user` | nullable text/int/text | One-off override; the loader treats the trio as a unit — if any required field is empty the loader maps to `null`. |

**Runtime — recursive ensureBastion.** `features/session_manager/session_connect.dart::_ensureBastion` walks the chain bottom-up. For every hop:

1. If `current.viaSessionId` is set, look up the cached bastion session (no `loadWithCredentials` round-trip — the staging layer pulls bytes from Rust).
2. Otherwise build an `SSHConfig` from `viaOverride` and inherit auth from the final session's `SshAuth`. Documented limitation: for a bastion with distinct auth, save it as its own session and link via `viaSessionId`.
3. Recurse into the bastion's own bastion (if any) so the chain is materialised root-first.
4. Call `manager.connectAsync(...)` with `internal: true` and `bastion: upstream` so the manager owns the lifecycle.

**Cycle / depth guards.** `_ensureBastion` carries a `Set<String> visited` (session ids already in the chain). A `viaSessionId` already in the set throws `ProxyJumpCycleError` carrying the offending id. Independently, `visited.length >= maxProxyJumpDepth` (8) throws `ProxyJumpDepthError` before the recursion goes deep. The 8 cap leaves room for realistic enterprise chains (corp gateway → region gateway → cluster gateway → service ≈ 4) doubled for safety, while still tripping accidental loops fast. Both errors localise through `errProxyJumpCycle` / `errProxyJumpDepth` so the user sees a concrete message rather than a stack trace.

**Transport injection — `RustTransport.connectViaProxy`.** When `Connection.bastion` is non-null and connected, `ConnectionsNotifier._doConnect` waits for the bastion to reach `connected` (`bastion.waitUntilReady()`), then routes the child handshake through `transport.connectViaProxy(parentTransport, request)`. Inside Rust, `connectViaProxy` opens a russh `direct-tcpip` channel on the parent session targeting the child's `host:port`, wraps it as the upstream socket for the child russh `Session::connect_to_socket`, and runs the standard auth dance over that channel. Reconnect on the parent re-runs the same path, so a bastion mid-handshake when the parent retries simply queues until the upstream's `Connected` state.

**Hidden bastion lifecycle — Connection.internal.** Bastion connections are full `Connection` objects in [`ConnectionsNotifier`](#connectionsnotifier) so the credential overlay, keep-alive timer, and progress-stream machinery all "just work". They are flagged `internal: true`; the user-visible `connections` getter filters them out so the workspace UI never paints a phantom tab for a hop the user did not explicitly open. The `allConnections` getter returns the full set for callers that need the complete actor list (debug overlays, internal teardown sweeps). The Android foreground-service active-count callback gates on the **user-visible** count via `lfs_core::connection::ConnectionRegistry::connected_user_visible_count` (excludes `internal: true` actors) — the user-visible "0 connected sessions" on a parent disconnect collapses the persistent-notification gate cleanly even while the bastion hop is still mid-teardown. The parent connection holds a `bastion: Connection?` reference; `disconnect(parent.id)` cascades into `disconnect(bastion.id)` so the chain is torn down as a unit.

**UI — ProxyJump section in Connection tab.** A three-chip selector (`None` / `Saved session` / `Custom`) sits below the user/host/port row in the Connection tab. The saved-session mode renders a dropdown of every **other** session (the dialog filters out the session being edited so it cannot reference itself — inline guard before the runtime cycle detector kicks in); the custom mode renders host/port/user fields with a note explaining the inherits-credentials limitation. Mode + values persist in dialog state independently so flipping between modes does not destroy partial input.

---

### 3.2 SFTP (`core/sftp/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `sftp_fs.dart` | `RemoteSftpFs` (abstract), `RustSftpFs` (impl over the russh-sftp engine), `RemoteFS` (`FileSystem` adapter) | Public SFTP surface used by [`features/file_browser/`](#52-file-browser-featuresfile_browser) and [`features/transfer/`](#33-transfer-queue-coretransfer). Both leaf primitives (list / mkdir / remove / rename / upload / download) and the recursive composites (`uploadDir` / `downloadDir` / `removeDir`) route through the Rust SFTP engine in one FRB hop each — `lfs_core::sftp` owns the per-entry recursion so the bridge isn't crossed per file. |
| `file_system.dart` | `FileSystem`, `LocalFS` | Engine-agnostic file-system interface used by `FilePaneController` so the same UI code drives local and remote panes. `LocalFS` wraps `dart:io`; `RemoteFS` (in `sftp_fs.dart`) wraps `RustSftpFs`. |
| `sftp_models.dart` | `FileEntry`, `TransferProgress` | File/directory model (name, path, size, mode, modTime, isDir, owner) plus the progress event the transfer queue emits per chunk. |
| `errors.dart` | `SFTPError` family | Typed errors layered over the russh-sftp status codes so the UI can localise "permission denied" / "no such file" / "disk full" without grepping strings. |
| `rust/crates/lfs_core/src/sftp/mod.rs` | `lfs_core::sftp::Sftp` | russh-sftp client wrapper — open/read/write/list/stat/mkdir/remove/rename/chmod, including the streaming readdir loop and the chunked read/write loops the transfer queue feeds. |

#### RemoteSftpFs API

```dart
abstract class RemoteSftpFs {
  // Leaf primitives — every call routes one FRB hop into lfs_core::sftp:
  Future<String> getwd();
  Future<List<FileEntry>> list(String path);
  Future<bool> exists(String path);
  Future<void> mkdir(String path);
  Future<void> remove(String path);                      // files only
  Future<void> removeEmptyDir(String path);              // empty dirs only
  Future<void> rename(String oldPath, String newPath);
  Future<void> upload(String localPath, String remotePath,
                      void Function(TransferProgress)? onProgress);
  Future<void> download(String remotePath, String localPath,
                        void Function(TransferProgress)? onProgress);
  void close();

  // Recursive composites — Rust runs the per-entry walk in lfs_core::sftp,
  // so a 1000-file tree is one FRB hop, not 1000:
  Future<void> removeDir(String path);                   // recursive
  Future<void> uploadDir(String localDir, String remoteDir,
                         void Function(TransferProgress)? onProgress);
  Future<void> downloadDir(String remoteDir, String localDir,
                           void Function(TransferProgress)? onProgress);
}

class RustSftpFs extends RemoteSftpFs {
  static Future<RustSftpFs> create(SshTransport transport);
  // Holds the Rust SFTP client returned by transport.openSftp(); every
  // call routes one FRB hop. Disconnects when the parent transport
  // disconnects.
}
```

**Chunked transfers.** `lfs_core::transfer::driver::{download, upload}` stream in 256 KiB chunks (`TRANSFER_CHUNK_SIZE`). The chunk size matches russh's default 2 MiB SSH channel window divided by ~8 in-flight packets, so a single stream saturates the pipe without back-pressure stalls; the prior 64 KiB cap awaited a full round-trip before the next read went out and capped throughput at ~25% of the link on 100+ Mbps connections. Local file I/O runs through `tokio::fs::File` so the syscalls land on the blocking pool — the SFTP read/write at the top of each loop iteration is async and the runtime worker stays free to drive concurrent transfers. The driver allocates one scratch `Vec<u8>` per call and reuses it across iterations via `SftpFile::read_into`; the older `read_chunk(N)` path stays for the FRB shim where the Dart caller needs an owned `Vec` for SerDe. `try/finally`-equivalent ordering closes the local handle on every error path so a half-written download never leaks an open file descriptor. Progress events fire through `lfs_core::transfer::TransferQueue::set_progress`, **throttled** to one bus event per 256 KiB or 100 ms (whichever fires first; completion edge always publishes), so a 100 MB/s pipe produces ~10 events/s/task instead of the ~3200/s the unthrottled per-chunk emit would (Dart-side `_scheduleRefresh` rebuilt the full transfer-history snapshot per event — UI froze on large downloads). The transfer queue (`features/transfer/`) translates the throttled events into `TransferProgress` rows for the UI.

#### FileSystem interface

```dart
abstract class FileSystem {
  Future<List<FileEntry>> list(String path);
  Future<String> initialDir();
  Future<void> mkdir(String path);
  Future<void> remove(String path);
  Future<void> removeDir(String path);                    // recursive
  Future<void> rename(String oldPath, String newPath);
  Future<bool> exists(String path) async { ... }          // default: parent-listing probe
  Future<int>  dirSize(String path);                      // recursive size in bytes

  /// What this backend can surface. Defaults to "all-false"
  /// (the conservative shape every HTTP-style object store fits).
  FileSystemCapabilities get capabilities =>
      FileSystemCapabilities.objectStore;
}

class FileSystemCapabilities {
  final bool posixMode;   // st_mode bits available in entries
  final bool owner;       // per-resource owner string available
  const FileSystemCapabilities({this.posixMode = false, this.owner = false});

  static const objectStore = FileSystemCapabilities();                          // WebDAV, S3
  static const posix = FileSystemCapabilities(posixMode: true, owner: true);    // LocalFS, RemoteFS
}

class LocalFS implements FileSystem { ... }              // wraps dart:io
class RemoteFS implements FileSystem { ... }             // wraps RustSftpFs; dirSize capped at 64 levels
class WebDavFileSystem implements FileSystem { ... }     // wraps WebDavConnection
class S3FileSystem implements FileSystem { ... }         // wraps S3Connection
```

**Why an interface.** `FilePaneController` works identically across every backend; tests substitute fakes by injecting a different `FileSystem`. Adding a new backend (the WebDAV / S3 path) plugs into the same surface without touching the file-browser UI.

**Why capabilities are a struct, not per-getter overrides.** The file-pane gates per-column visibility on whether the backend actually populates that column (Mode + Owner are hidden for WebDAV / S3 — every row would render `--------` / blank). A single `FileSystemCapabilities` struct field means adding a new capability is one struct field plus a literal update in each production impl; test stubs that don't care keep `objectStore` and never need to touch the new flag. The earlier per-getter shape (`supportsPosixMode`, `supportsOwner` etc.) cascaded every new flag through every `implements FileSystem` site, turning test files into capability-declaration boilerplate.

#### Storage provider abstraction (Rust-side, `lfs_core::storage`)

The Dart-side `FileSystem` keeps the local-vs-remote split inside the file browser; the Rust-side `storage::Provider` trait does the same job one layer down, behind the FRB boundary, for non-SFTP backends that need a Rust-native client (S3 over `aws-sigv4` + `reqwest`, WebDAV over PROPFIND / MKCOL / MOVE). The trait factors out the surface every byte-store offers — list, stat, mkdir, remove, rename, streamed GET, streamed PUT, recursive directory size — so the dispatcher that fans an FRB call out to the right backend can hold an `Arc<dyn Provider>` keyed by `(connection_id, kind)` instead of branching on enum tags at every call site.

| Type | Purpose |
|------|---------|
| `lfs_core::storage::Provider` (trait) | The eight async methods above, each returning `Pin<Box<dyn Future<...> + Send + 'a>>` so the trait stays dyn-compatible (native async-fn-in-traits would not be object-safe under the dispatcher's `Arc<dyn Provider>` shape). |
| `lfs_core::storage::Entry` | One directory entry — `name`, absolute `path`, `kind: EntryKind`, `size_bytes`, `modified_unix_ms`. |
| `lfs_core::storage::EntryKind` | `File` / `Dir` / `Symlink`. Symlink wins over dir in the mapping so the remove walker treats a symlink-to-dir as a link and unlinks it instead of recursing the target. |
| `lfs_core::storage::Metadata` | Same shape as `Entry` minus name + path — returned by `stat`. |
| `lfs_core::storage::ByteStream` | Type alias for `BoxStream<'static, Result<Bytes, Error>>` — `get_stream` returns one, `put_stream` consumes one. Per-chunk `Result` so mid-stream transport drops surface inline. |
| `lfs_core::storage::sftp::SftpProvider` | `Provider` impl that delegates every method to the existing `lfs_core::sftp::Sftp` engine. Holds the engine through `Arc` so streams returned by `get_stream` keep it alive while the caller pumps chunks. |

`SftpProvider` is a thin wrapper: type mapping at the boundary (russh-sftp's `DirEntry` / `FileMetadata` ↔ `Entry` / `Metadata`, including the seconds-to-milliseconds conversion on mtimes), and stat-first dispatch inside `remove` so the uniform trait surface stays uniform without splitting into `remove_file` / `remove_dir`. The streaming GET seeks once when a byte range is supplied (inclusive on both ends, matching HTTP `Range: bytes=start-end`) and yields 64 KiB chunks via `SftpFile::read_into`; the streaming PUT pumps chunks into the open handle and fsyncs at the end. `dir_size` walks the tree depth-first with the same 100-level depth cap as `Sftp::remove_dir_recursive` so a cyclic symlink tree fails fast.

The FRB surface for SFTP stays unchanged with this layer in place — provider polymorphism becomes visible at the FRB / Dart layer when the second backend (S3, WebDAV) lands and the dispatcher routes by id.

---

### 3.3 Transfer Queue (`core/transfer/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `providers/transfer_provider.dart` | `TransfersNotifier` | Task queue, parallel workers, history, cancellation |
| `transfer_task.dart` | `TransferDirection`, `HistoryEntry`, `ActiveEntry` | Direction enum, history-row model (terminal task summary), active-row model (in-flight task UI snapshot). The live task object lives Rust-side in `lfs_core::transfer::WorkerPool`; `ActiveEntry` is the Dart-side snapshot the UI re-renders per `BusEvent::TransferTaskProgress`. |
| `conflict_resolver.dart` | `ConflictAction`, `ConflictDecision`, `BatchConflictResolver` | User decision for destination-exists conflicts, with "apply to all remaining" caching across a batch |
| `unique_name.dart` | `uniqueSiblingName()` | Compute a non-colliding destination path (`file.txt` → `file (1).txt`) for the "Keep both" conflict action |

#### TransfersNotifier — architecture

**`TransfersNotifier`** runtime shape:

- Queue: `[task1, task2, task3, ...]`
- Workers: `2` (configurable)
- Max history: `500` entries
- Timeout: `30 min` per task
- States: `queued → running → completed / failed / cancelled`
- Streams: `onChange → UI updates`, `onHistoryChange → history`

```dart
class TransfersNotifier extends Notifier<TransferState> {
  // Parallelism + maxHistory + taskTimeout live on the Rust side
  // (lfs_core::transfer::WorkerPool + retention policy); the Dart
  // notifier mirrors snapshots only.

  Future<void> enqueue({
    required TransferDirection direction,
    required String sessionId,
    required String remotePath,
    required String localPath,
    int bytesTotal = 0,
  });
  // Routes to lfs_frb::api::transfer::transfer_enqueue; the Rust
  // worker pool owns the live task object and emits per-chunk
  // BusEvent::TransferTaskProgress + lifecycle events that the
  // notifier subscribes to.

  Future<void> cancel(String taskId);
  Future<void> cancelAll();
  Future<void> clearHistory();

  List<ActiveEntry> get activeEntries;        // running + queued tasks with progress
  List<HistoryEntry> get history;             // completed/failed/cancelled
  ({int running, int queued}) get status;
}
```

**Cancellation:** routes through `lfs_frb::api::transfer::transfer_cancel`; the Rust worker checks the cancel flag at every chunk boundary and aborts cooperatively. Timeout shares the same path — the Rust pool's deadline timer enqueues the cancel.

**Queue processing:** owned by `lfs_core::transfer::WorkerPool` (a tokio task pool). Dart's notifier is a passive mirror that re-emits when `BusEvent::TransferTask*` lands.

**Task lifecycle**:

```mermaid
stateDiagram-v2
    [*] --> queued: enqueue()
    queued --> running: worker picks up
    queued --> cancelled: cancel() before start
    running --> completed: run() returns
    running --> failed: run() throws (non-cancel)
    running --> cancelled: _cancelledIds check / 30-min timeout
    completed --> [*]: moves to history
    failed --> [*]: moves to history
    cancelled --> [*]: moves to history
```

#### TransferPanel — UI

The `TransferPanel` (`features/file_browser/transfer_panel.dart`) is a collapsible bottom panel unified with the file browser table pattern:

- **Resizable columns** — Local, Remote, Size, and Time columns have drag handles (shared `ColumnResizeHandle` widget, same as `FilePane`)
- **Column dividers** — Vertical 1px dividers between columns (same `_colDivider` as `FileRow`)
- **Sorting** — Click column headers to sort history entries. Default: Time descending. Enum: `TransferSortColumn` (name, local, remote, size, time)
- **Time column** — Replaces old Duration column. Shows `formatTimestamp` + `(formatDuration)` for completed entries. Tooltip shows created/started/ended/duration breakdown
- **Left-aligned sizes** — Size column uses default left alignment (no `textAlign: TextAlign.right`)

---

### 3.4 Session Management (`core/session/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `session.dart` | `Session`, `SessionAuth`, `AuthType` | Session model with all fields. (`ServerAddress` lives in `lib/core/ssh/ssh_config.dart` and is reused via `Session.server`.) `AuthType` is `password` / `key` / `keyWithPassword` / `agent`; the `agent` variant defers every signature to the system ssh-agent (`$SSH_AUTH_SOCK` on Unix, OpenSSH named pipe / Pageant on Windows) and carries no per-row key / password slot. |
| `providers/session_provider.dart` | `SessionNotifier` | CRUD via FRB DAOs, search, folder tree management |
| `session_tree.dart` | `SessionTree`, `SessionTreeNode` | Hierarchical tree built from flat session list |
| `session_history.dart` | `SessionHistory` | Undo/redo snapshots (stores credentials separately) |
| `session_recorder.dart` | `SessionRecorder` | Per-shell terminal recorder; see [§3.13](#313-session-recording-coresessionsession_recorderdart). |
| `port_forwards_dao.dart` | DAO helpers | Thin Dart shim over the FRB port-forward DAO surface used by `SessionNotifier`. |
| `qr_decoded_source.dart` | `QrDecodedSource` | Sealed type wrapping a Rust-staged QR/.lfs import handle so `LinkImportPreviewDialog` and the apply pipeline speak the same shape. |
| `qr_codec.dart` | Free functions | Thin Dart shim over the Rust QR/`.lfs` codec. Versioned format (`v: 1`), deflate compressed, key map deduplication — all encode/decode/size/wrap/unwrap logic lives in `lfs_core::qr_codec` + `lfs_core::archive::qr_export_payload`; this file only exposes the `ExportOptions` config bag, the `qrMaxPayloadBytes` constant, and `encodeSessionCompact()` (FRB sync wrapper used by export-dialog size estimation). Decode/import always routes through the staged-handle Rust path (`qrImportOpen` → `QrDecodedSource.rust`). |

#### QR payload format (v1)

JSON → deflate → base64url. Top-level keys:

| Key | Type | Description |
|-----|------|-------------|
| `v` | `int` | Schema version (`1` — the floor; there is no version below it, and the format is always deflate-compressed). Both the composer (`lfs_core::archive::qr_compose`) and the decoder (`lfs_core::qr_codec_decode`, which rejects anything above its ceiling as "version too new") read this from `SchemaVersions::QR_PAYLOAD` — neither hardcodes a literal, so the stamped and accepted versions cannot drift. A payload that fails to inflate is rejected, not read raw. |
| `km` | `Map<shortId, PEM>` | Deduplicated key map (embedded + manager private keys) |
| `mk` | `Map<shortId, {l, t, p}>` | Manager key metadata: label, keyType, publicKey |
| `s` | `List<Map>` | Sessions (compact encoding). Manager-key sessions have `mg: 1` flag, `ki` = shortId |
| `eg` | `List<String>` | Empty folder paths |
| `c` | `Map` | App config JSON |
| `kh` | `String` | Known hosts. **Export emits** the LetsFLUTssh internal wire format (`host:port keytype base64key`, one per line). **Import accepts both** the internal format and OpenSSH `~/.ssh/known_hosts` — `_parseLine` detects bare hostnames (port 22 default), `[host]:port` brackets (incl. IPv6), comma-separated multi-host fan-out, and `@cert-authority`/`@revoked` markers (stripped). Hashed (`|1|salt|hash`, `HashKnownHosts yes`) entries are skipped — HMAC-SHA1 hostname hashes are one-way so we have nothing to match against on a later TOFU `verify()`. The importer surfaces a "skipped N hashed entries" warning to the log when it drops them. The `key_base64` body is decode-checked against the standard base64 alphabet at parse time — invalid or empty bodies drop with a `KnownHostsImport` / `ArchiveKnownHosts` warning so a corrupt key body cannot sit in the DB until the next connect attempt surfaces it as a TOFU mismatch. |
| `tg` | `List<{i, n, cl?}>` | Tags (id, name, optional color) |
| `st` | `List<{si, ti}>` | Session→tag links |
| `ft` | `List<{fi, ti}>` | Folder→tag links (folderPath, tagId) |
| `sn` | `List<{i, t, cm, d?}>` | Snippets (id, title, command, optional description) |
| `ss` | `List<{si, ni}>` | Session→snippet links |

`ExportOptions` controls which keys are emitted: `includeSessions`, `includePasswords`, `includeEmbeddedKeys`, `includeManagerKeys` (session-bound only), `includeAllManagerKeys` (entire key store), `includeConfig`, `includeKnownHosts`, `includeTags`, `includeSnippets`, `includeRecordings` (the on-disk `<appSupport>/recordings/` tree — `.lfs` only, QR ignores it).

**Recordings bundling.** `includeRecordings` triggers the `.lfs` composer's `write_recordings_entries` pass, which walks `<recordings_root>/<sessionId>/*.{cast,lfsr}`, decrypts every `.lfsr` with the active DB key (`open_lfsr_iter` re-serialises each event as an asciinema v2 line), and writes a plaintext `recordings/<sessionId>/<base>.cast` entry into the inner ZIP. The receiver does not need the sender's DB key to replay — the LFSE envelope's Argon2id + AES-GCM layer is the only confidentiality boundary in transit. On apply, `apply_recordings_to_filesystem` runs after the DB transaction commits, writing each entry atomically (`*.tmp` → `fsync` → rename) under `<recordings_root>/imported/<sessionId>/<base>.cast`; when the active tier holds a DB key the importer follows up with `convert_all_cast_to_lfsr` so the plaintext sidecars get re-encrypted in place. Path components are vetted with `is_safe_segment` (no `..`, no path separators, no NUL); ill-formed `recordings/...` entries are skipped with an `Archive` warning rather than aborting the archive. The recordings root + DB key are pulled from `lfs_core::app::instance()` inside `build_core_export_input` so the FRB caller cannot forge either.

**Decoder size guard.** Decoding lives Rust-side in `lfs_core::qr_codec_decode` (`decode_to_json_text` → `inflate_capped`); the Dart `core/session/qr_codec.dart` only encodes. The decoder caps the **inflated** JSON size at `MAX_INFLATED_PAYLOAD_BYTES` (4 MiB) and returns `Error::Crypto("payload too large")` on overflow. The cap defuses a zip-bomb-style payload: deflate's theoretical compression ratio lets a ~4 KB QR expand to 4 MB+ of JSON, and the downstream `serde_json` parse would spike heap usage before any schema check could fire. Legitimate full-backup payloads stay far below this ceiling — the QR producer's own 2 KB compressed limit (`qrMaxPayloadBytes`) would never produce that much JSON, and paste-link payloads coming from the same encoder hit a few hundred KB at most.

**Size estimator ↔ emitter parity.** `UnifiedExportController._qrPayloadSize` and `_lfsArchiveSize` route through `qr_estimate_export_size` and `db_lfs_export_size` respectively (FRB sync, id-based). Both functions reach for `lfs_core::archive::qr_export_payload_size` / `export_archive_size` and pull sessions / keys / tags / snippets straight from `letsflutssh.db` by id, so the gauge value matches the bytes the production producer (`db_export_qr_payload` / `db_export_archive`) would emit for the same selection. The dialog hands across only the option flags + the selected ids — manager-key PEM bytes and session passwords stay Rust-side. `UnifiedExportDialogData` carries no `managerKeyEntries` map; the Rust composer looks every payload component up by id, so the Dart heap never materialises private bytes for either the gauge or the actual emit.

#### Session model

```dart
class Session {
  final String id;            // UUID
  final String label;         // display name
  final String folder;        // folder path: "Production/Web" (separator /)
  final SessionKind kind;     // ssh (default) or webdav — picks the transport
  final ServerAddress server; // host, port, user
  final SessionAuth auth;     // authType, password, keyPath, keyData, passphrase
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?> extras; // free-form JSON bag, see "Session.extras" below
  bool get hasCredentials;    // true if password, keyData, keyId, or keyPath is set
  bool get isValid;           // true if host, port, user, and hasCredentials (highlighted orange when false)
  bool get isSsh;             // kind == SessionKind.ssh
  bool get isWebDav;          // kind == SessionKind.webdav

  bool? extrasBool(String key); // typed reads — null when missing or wrong-typed
  String? extrasStr(String key);
  int? extrasInt(String key);
  Session withExtras(Map<String, Object?> delta); // merge; null value removes a key

  SSHConfig toSSHConfig();    // conversion for connection
  Session copyWith({...});    // preserves id, updates updatedAt
  Session duplicate();        // new id, "(copy)" suffix, preserves authType
  Map<String, dynamic> toJson();
  factory Session.fromJson(Map<String, dynamic> json);
}

enum SessionKind { ssh, webdav, s3 }
```

##### Session kind — SSH vs WebDAV vs S3

`SessionKind` picks which transport the runtime opens. The
`Sessions` table only carries the protocol-neutral row (id, label,
folder_id, kind, sort_order, notes, last_connected_at, extras,
timestamps) — every protocol-specific column lives on its own
join table keyed by `session_id`. SSH sessions read host / port /
user / auth_type / password / key_data / key_id / passphrase plus
the `via_*` ProxyJump tuple from `SshSessionDetails` and route
through the russh + `lfs_core::sftp` stack for shell and file
transfer. WebDAV sessions read the transport tuple from
`WebDavSessionDetails` (base URL, username, auth method, optional
self-signed fingerprint) plus the password / bearer token from the
`SecretStore` under `session.webdav.<id>`. S3 sessions read from
`s3_session_details` (access key id, region, endpoint, addressing
style, default bucket, default prefix) plus the secret access key
from `session.s3.<id>` in the `SecretStore`. The `kind` column is
`NOT NULL DEFAULT 'ssh'` so a row inserted without an explicit
kind lands as an SSH session. SSH-specific columns live on
`SshSessionDetails` so non-SSH rows do not carry SSH-shaped
fields. See §11 for the table shape.

**Kind-change cleanup.** `db::sessions::upsert` keeps the live
kind's detail row in sync and drops the rows from the other two
join tables (`ssh_session_details` / `webdav_session_details` /
`s3_session_details`) so re-saving a session under a new kind does
not leak the previous transport's URL / credentials under the same
session id. Idempotent — already-empty deletes are no-ops, so the
common case (kind unchanged) is a single UPSERT plus two trivial
DELETEs. The `db::sessions::duplicate_session` path follows the
same shape but in the INSERT direction: the SSH / WebDAV / S3
detail rows clone column-to-column inside SQLite via
`INSERT INTO ... SELECT FROM ... WHERE session_id = ?` so a non-
matching source set is a clean no-op, and a kind-aware duplicate
always carries its transport tuple (secrets stay under the source's
SecretStore id; the operator re-enters them on first connect of
the copy).

The file browser dispatches on `Connection.kind` (mirrored off
`Session.kind` on connect): the SSH path wraps the live SFTP channel
in `RemoteFS(RustSftpFs)`; the WebDAV path wraps the
`WebDavConnection` opaque FRB handle in `WebDavFileSystem`; the S3
path wraps the `S3Connection` handle in `S3FileSystem`. All three
implement the same `FileSystem` interface, so the pane controllers
and file-browser widgets stay transport-agnostic. See `core/webdav/`
for the WebDAV facade, `core/s3/` for the S3 facade, and
`lfs_frb::api::webdav` / `lfs_frb::api::s3` for the Rust-side connect
probes.

The session edit dialog (`features/session_manager/session_edit_dialog.dart`) uses a **single-form layout** — one vertical scrollable body with three section composers, no tab strip. The kind picker sits at the top of the form as the single lever; flipping it reshapes the Connection and Authentication sections in place rather than swapping hidden tabs:

- **Identity (top of form, no header)** — name + kind picker.
- **Connection section** — the SSH block (host / port / user / ProxyJump editor), the WebDAV block (base URL + username), or the S3 block (access key id + region + endpoint + path-style toggle + default bucket / prefix). The section header reads `CONNECTION`.
- **Authentication section** — protocol-branched (header reads `AUTHENTICATION`):
  - **SSH**: the system-ssh-agent toggle, then the password / key-store / inline-PEM / passphrase block.
  - **WebDAV**: a three-chip method picker (`basic` / `digest` / `bearer`), a single credential field whose label tracks the active method (`PASSWORD *` for basic / digest, `BEARER TOKEN *` for bearer; the underlying `_passwordCtrl` is the same `StyledFormField` widget the SSH path uses), and the optional self-signed-cert fingerprint pin.
  - **S3**: a single `SECRET ACCESS KEY *` field bound to the same `_passwordCtrl` — SigV4 has no other credential dimension.
- **Advanced section (collapsible)** — header reads `ADVANCED`, collapsed by default. Contents: tags (universal — every kind), port-forward rule summary + `Manage…` button (SSH only — opens `SessionForwardsDialog` modal), record-session toggle (SSH only).

Side-bar rows render a per-protocol icon (`Icons.terminal` for SSH, `Icons.cloud_outlined` for WebDAV, `Icons.inventory_2_outlined` for S3) via the `_iconForKind` helper in `session_tree_view_internals.dart`, so the user can tell the kind at a glance without opening the row.

On save the dialog returns the matching transport tuple (`SaveResult.webdavData` / `SaveResult.s3Data`) alongside the session row; the panel action handler upserts the corresponding join row and stages the secret into SecretStore under the canonical id (`dbWebdavSessionDetailsSecretId(sessionId:)` / `dbS3SessionDetailsSecretId(sessionId:)`) — only when the dialog's `passwordDirty` bit fires so a label edit never clobbers a stored token.

##### S3 sessions

The S3 transport (`lfs_core::s3`) speaks the AWS REST surface every
S3-compatible vendor implements: AWS S3 itself, MinIO, Wasabi,
Backblaze B2-S3, Cloudflare R2, DigitalOcean Spaces, Scaleway
Object Storage. The module owns three pieces: the SigV4 signer
(`signer.rs`), the high-level verb surface (`S3Client` in
`client.rs`), and the multipart-upload orchestrator (`multipart.rs`).
The provider adapter (`storage::s3::S3Provider`) lifts the verb
surface into the backend-agnostic `Provider` trait so the file
browser stays transport-agnostic.

**Why an inline SigV4 signer.** The upstream `aws-sigv4` crate
transitively pulls the `aws-smithy-*` runtime tree (~25 crates).
SigV4 itself is a tight four-stage algorithm; the implementation
in `signer.rs` depends only on `hmac` + `sha2` (already in the
tree), fits in one file, and stays under-test through unit tests
that pin the deterministic invariants of every stage.

**Path syntax.** The provider accepts two shapes: `s3://bucket/key`
(explicit bucket) and bare `key` (resolves through the configured
`default_bucket` + `default_prefix`). The bare form rejects when
no default bucket is configured so a misconfigured session
surfaces immediately rather than as a "NoSuchBucket" at the first
list.

**Addressing style.** AWS defaults to virtual-host addressing
(`<bucket>.s3.<region>.amazonaws.com`). MinIO and some private
deployments require path-style (`<endpoint>/<bucket>/<key>`); the
toggle on the Connection tab selects which the signer + URL
composer use. A future region-aware sniffer can flip the toggle
automatically; for now it stays explicit.

**Multipart upload.** Bodies under 8 MiB go through single-shot
`PUT` (`put_object_single`); larger bodies stream through the
multipart orchestrator (Initiate → UploadPart loop → Complete).
Part size is 8 MiB, matching the AWS SDK default; an upload that
errors mid-loop calls Abort to release server-side staged-part
state before surfacing the underlying error. In-process state
only — a crash mid-upload leaves the staged parts orphaned and
the next push restarts from scratch; cross-process resume needs
a typed sidecar that lies outside the v1 cut.

**Presigned URLs.** `S3Connection::generate_presigned_url` builds a
time-limited query-signed `GET` URL via the same SigV4 algorithm
in query-parameter mode. Expiry clamps to AWS's 7-day maximum;
the Dart UI offers 15 min / 1 h / 4 h / 24 h / 7 day presets so
the user picks an expiry without typing seconds.

**Rename is not atomic.** S3 has no native rename — `S3Provider::rename`
emulates via `CopyObject` + `DeleteObject`. A reader between the
two calls observes both source and target; the SFTP / WebDAV
providers do not surface this caveat because their backends honour
native rename.

##### Session.extras — JSON escape hatch

Persisted into the `Sessions.extras TEXT NOT NULL DEFAULT '{}'` column. Holds feature flags that don't justify their own column — recording opt-in, layout hints, agent-forwarding state, future per-session preferences. The map is unmodifiable; mutate through [`Session.withExtras(delta)`] which returns a copy with the delta merged (a `null` value in `delta` removes the key).

**Why a JSON column instead of a column per flag.** Many features add at least one Session field. Doing that one column at a time means a schema bump per feature; doing it via `extras` means one bump covers them all. Load-bearing fields that need indexed lookups or load-time access at connect time (auth, port forwards, proxy jump) keep their own columns; everything else funnels through `extras`.

**Why typed accessors instead of raw map access.** The map is `Map<String, Object?>`; an `extras['record']` read at a feature site forces every call site to handle three failure modes (key missing, value is the wrong type, value is `null`). The `extrasBool` / `extrasStr` / `extrasInt` helpers fold all three into a single `null` result, so the call site reads `if (s.extrasBool('record') ?? false)` instead of branching on `is bool`.

**JSON tolerance.** The full Session JSON codec (encoder + decoder + typed `extras` walker) lives in `lfs_core::session_json` and crosses the FRB boundary via the sync shims `session_canonical_json` / `session_decode_from_json` / `session_extras_decode` / `session_history_encode_snapshot` / `session_history_decode_snapshot`. Malformed payloads fold to the appropriate empty default: a corrupt `extras` blob produces an empty map, an unknown leaf type maps to `Null`, an unparseable top-level decode returns a structural error string the FRB call surfaces to the caller. A corrupt blob never blocks a session from loading.

**Persistence path.** On save the Dart layer hands a `DbSessionJsonInput` to the Rust encoder; the wire shape (key order, conditional-omit rules for `kind` / `key_id` / `extras` / `via_*` / `notes` / `sort_order` / `last_connected_at_ms`) lives in `lfs_core::session_json::encode_canonical_json`. On load the mapper (`mappers.dart::_decodeExtras`) routes the column verbatim through `session_extras_decode`, and `Session.fromJson` routes through `session_decode_from_json`. The Dart `Session` class still owns the domain methods (`displayName`, `effectiveHost`, `withoutCredentials`, typed accessors) but no longer hand-rolls the JSON walk — the single source of truth for the wire shape is Rust.

**Typed `extras` leaves.** The Rust decoder converts each map leaf into a `SessionJsonValue` tagged union (`Null` / `Bool` / `Int` / `Double` / `Text` / `Array(String)` / `Object(String)`); the FRB shim mirrors it as `DbSessionJsonValue`; the Dart `extrasListToMap` helper in `session_json_codec.dart` re-keys the `Vec<DbSessionJsonExtra>` carrier into a `Map<String, Object?>` the typed accessors (`extrasBool` / `extrasStr` / `extrasInt`) consume. Whole-number floats round-trip as `Int` so the `extrasInt` contract matches the Dart `num` shape `jsonDecode` used to produce.

#### SessionNotifier — FRB-backed persistence

All session data (including credentials) is stored in a single SQLite database opened Rust-side via `rusqlite` + bundled SQLCipher 4.x (AES-256-CBC + HMAC-SHA512). Encryption happens at the DB level — stores never manage encryption themselves; the Dart notifier reads / writes through the FRB DAO surface in `lib/src/rust/api/db.dart`.

```dart
class SessionNotifier {
  void setDatabase(AppDatabase db); // injected at startup

  Future<List<Session>> load();     // reads from SessionDao + FolderDao
  Future<void> add(Session session);
  Future<void> update(Session session);
  Future<void> delete(String id);
  List<Session> search(String query);  // by label, folder, host, user

  Set<String> get emptyFolders;
  Future<void> addEmptyFolder(String path);
  Future<void> renameFolder(String oldPath, String newPath);
  Future<void> deleteFolder(String path);
  String? folderIdByPath(String path); // resolve path to DB folder ID
}
```

**Folder tree:** UI uses string paths ("Production/EU"), DB uses a `Folders` table with self-referencing `parentId`. `mappers.dart` handles conversion: `resolveFolderPath()` creates missing folder nodes, `findFolderIdByPath()` resolves path → ID. In-memory `_folderMap` cache rebuilt on `load()`.

**Concurrent load guard:** `load()` uses a `_loadFuture` guard — concurrent callers await the same future instead of starting a second load.

**Atomicity:** Handled by SQLite transactions. No separate save order — all data is in one DB file.

#### SessionTree

```dart
class SessionTree {
  static List<SessionTreeNode> build(List<Session> sessions, {Set<String> emptyFolders = const {}});
  // Builds hierarchy: "Production/Web/nginx" → [Production] → [Web] → [nginx]
  // Empty folders are materialised even without sessions.
}

class SessionTreeNode {
  final String name;
  final String fullPath;       // full path from root
  final Session? session;      // null for folders
  final List<SessionTreeNode> children;
  bool expanded;               // UI-only, mutated by the sidebar
  final int sessionCount;      // recursive count of session leaves under this subtree

  bool get isGroup => session == null;
  bool get isSession => session != null;
}
```

**Where the structural logic lives.** The folder collapsing,
sort order (folders before sessions, case-insensitive within
each kind), and recursive `sessionCount` precomputation are owned
by `lfs_core::session_tree::build` (Rust). The Dart `SessionTree`
class is a thin FRB wrapper: it hands a flat list of
`(id, label, folder, displayName)` records over to Rust, gets
back the immutable forest, and re-binds the live `Session`
handle to each leaf by id (Rust never sees the full session
record — it works in terms of session ids).

**Why Rust-owned.** Rationale follows the same principle as
`session_history` — keeping structural session-domain logic
next to the database row types in `lfs_core::sessions` lets
future `lfs_cli` / `lfs_tauri` consumers reuse the builder
without reimplementing the sort and folder-prefix rules. The
Dart wrapper only carries presentation concerns (the `expanded`
flag the sidebar mutates as the user clicks chevrons).

---

### 3.5 Connection Lifecycle (`core/connection/`)

#### Files and responsibilities

| File | Class | Purpose |
|------|-------|---------|
| `connection.dart` | `Connection` | Connection model (id, label, sshConnection, state, error, ready completer, progress stream) |
| `connection_step.dart` | `ConnectionStep` | Progress step model — phase (`socketConnect` / `hostKeyVerify` / `authenticate` / `openChannel`) × status (`inProgress` / `success` / `failed`) |
| `connection_step_mappers.dart` | Bus → `ConnectionStep` mappers | Translates `BusEvent::ConnectionProgress` payloads into the Dart `ConnectionStep` shape the progress tracker consumes. |
| `progress_tracker.dart` | `ProgressTracker` | Subscribes to `Connection.progressStream`, replays history for late subscribers, notifies listeners |
| `progress_writer.dart` | `ProgressWriter` | Writes ANSI-styled progress steps to an xterm `Terminal` (shared by desktop and mobile terminal views) |
| `connections_notifier.dart` | `ConnectionsNotifier` | Active connection management, creation, disconnection, bus subscription |
| `connection_extension.dart` | `ConnectionExtension` interface | Lifecycle hook contract (`onConnected` / `onDisconnecting` / `onReconnecting`) used by port forwards, recorder, etc. — see [ConnectionExtension](#connectionextension--lifecycle-add-ons) below. |
| `foreground_service.dart` | `ForegroundServiceManager` | Android: foreground service for SSH keep-alive on screen lock |

#### Connection model

```dart
class Connection {
  final String id;           // UUID (tab-specific)
  final String label;
  SSHConfig sshConfig;       // mutable — refreshed from session store on reconnect
  final String? sessionId;   // links back to saved Session (null for quick-connect)
  SshTransport? transport;   // engine-agnostic transport (today: RustTransport); set on successful connect
  SSHConnectionState state;  // disconnected | connecting | connected
  Object? connectionError;
  String? cachedPassphrase;  // interactively entered, reused on reconnect
  final Set<String> transientSecretIds; // SecretStore ids the connect path staged; drained on terminal state
  Connection? bastion;       // pinned bastion hop for ProxyJump (lifecycle cascades)
  bool internal;             // true for manager-created bastion hops; UI hides them

  Stream<ConnectionStep> progressStream;  // broadcasts steps during connect
  List<ConnectionStep> progressHistory;   // buffered for late subscribers

  Future<void> waitUntilReady();   // waits for connect attempt to finish (success or error)
  Future<bool> get transportReady; // resolves once `_adoptSession` has finished
  void completeReady();            // called by ConnectionsNotifier in `_doConnect.finally`
  void addProgressStep(step);      // buffers + broadcasts a progress step
  void resetForReconnect();        // closes old progress controller, then fresh completer + stream, clears history/error
  void dispose();                  // closes bus subscription + progress controller

  // Lifecycle add-ons — see "ConnectionExtension" below.
  void addExtension(ConnectionExtension ext);    // idempotent on the same instance
  void removeExtension(ConnectionExtension ext);
  List<ConnectionExtension> get extensions;
  void notifyExtensionsConnected();      // called by ConnectionsNotifier after handshake
  void notifyExtensionsDisconnecting();  // called before transport tear-down
  void notifyExtensionsReconnecting();   // called between disconnect and re-connect
}
```

##### ConnectionExtension — lifecycle add-ons

Port forwards, ProxyJump bastion keepalives, session recording sinks, agent forwarding all need the same three moments: just after the SSH transport became live, just before it tears down, and again on every reconnect. The interface keeps that contract in one place so [`Connection`](#connection-model) does not grow a fan of feature-specific fields and so each feature does not have to re-implement reconnect-survival logic.

```dart
abstract class ConnectionExtension {
  String get id;  // stable, used in log lines
  void onConnected(Connection connection);     // transport is live; open channels here
  void onDisconnecting(Connection connection); // transport is about to close; idempotent
  void onReconnecting(Connection connection) {} // optional: reset transient state
}
```

**Hook order on a successful connect.** `_doConnect` fires `notifyExtensionsConnected()` only after `conn.transport` has been assigned and `state == connected`, so an extension that reaches into `connection.transport!` cannot race the assignment.

**Hook order on reconnect.** `reconnect()` fires the disconnecting hook *before* it tears down the transport (extensions need the live `SSHClient` to close their channels cleanly), then `notifyExtensionsReconnecting()` after `resetForReconnect()` has reset progress state, then `_doConnect` runs and fires `notifyExtensionsConnected()` again on success. The same disconnecting hook covers the explicit `disconnect()` and `disconnectAll()` paths, so extensions only see one teardown contract regardless of how the transport ended.

**Failure isolation.** `Connection._fanOut` wraps each hook in a `try/catch` and logs through `AppLogger` — one extension throwing never aborts the connection lifecycle or starves later extensions. Extensions are allowed to mutate the registration list during a hook (deregister themselves, register dependent extensions); fan-out iterates over a snapshot so the loop stays safe.

**Idempotence requirement.** `onDisconnecting` is fired even on connections that never reached `onConnected` (a connect that timed out before handshake) so cleanup paths stay symmetric. Extensions must tolerate a teardown that has nothing to clean up.

**Bus subscription ownership.** Each `Connection` opens a permanent FRB bus subscription in its constructor (`_subscribeProgressBus`) and tears it down in `dispose()`. That subscription owns every Dart-side reaction to the per-id event stream the Rust actor publishes — `state` field mutation, transport adoption (`connection_get_session` → `RustTransport.adopt`), transient-secret eviction, progress fan-out into the local stream, connect-attempt success/failure logging, and `connectionError` capture from `BusEvent::ConnectionError`. The earlier design had `ConnectionsNotifier._doConnect` open a second per-attempt subscription that it cancelled in `finally`, but the cancel raced in-flight events from the FRB worker thread and produced "Fail to post message to Dart" stderr noise on every connect; collapsing the two listeners into one persistent subscription is what fixes that.

**Transport-adoption gate.** `state == connected` flips synchronously inside `_subscribeProgressBus` the moment the actor publishes `Connected`, but `_adoptSession` (which calls `connection_get_session` and wraps the russh handle in `RustTransport`) runs as a fire-and-forget `unawaited(_adoptSession())` so the bus listener stays non-blocking. Connect-flow consumers — `terminal_pane`, `mobile_terminal_view`, `sftp_browser_mixin` — therefore await `transportReady` *after* `waitUntilReady()`; otherwise they race the async adoption and see `transport == null` even though the state already says `connected`. `transportReady` resolves to `true` on a successful adopt and `false` if the actor moved straight to `Disconnected` or the `connection_get_session` call failed, so a deadlock-free completion is guaranteed.

**Progress controller lifetime.** `_progressController` is created in the constructor, recreated by `resetForReconnect()`, and only ever closed by `dispose()`. `completeReady()` does **not** close it — closing on `_doConnect.finally` would silently drop every queued post-success step (Rust publishes the success entries for `socketConnect` / `hostKeyVerify` / `authenticate` in the same tick the actor returns, before the Dart microtask queue drains the bus events), so downstream subscribers like `ProgressTracker.writeStep` would never see the green checkmarks even though the connection is live.

**Deferred Init pattern:** Connection is created instantly in state=`connecting`. The actual SSH handshake runs in the background. UI immediately opens a tab and shows a connecting indicator.

**State transitions** (terminal states in bold — a connection can leave `disconnected` only via `reconnect` on the same `Connection` object; a fresh `connectAsync` produces a new one):

```mermaid
stateDiagram-v2
    [*] --> connecting: connectAsync()
    connecting --> connected: handshake ok
    connecting --> disconnected: timeout / failure
    connected --> disconnected: onDisconnect fires
    disconnected --> connecting: reconnect()
    connected --> [*]: disconnect() / disposeAll()
    disconnected --> [*]: disconnect() / disposeAll()
```

#### ConnectionsNotifier

```dart
class ConnectionsNotifier extends Notifier<List<Connection>> {
  // Construction is via NotifierProvider; no required ctor args.
  // sessionCredentialCacheProvider is read inside build().
  // FRB-unreachable contexts (flutter_test) skip the bus subscription.

  PassphrasePromptCallback? onPassphraseRequired;  // set by UI layer (main.dart)

  Connection connectAsync(SSHConfig config, {String? label, String? sessionId});
  // Returns Connection immediately in state=connecting. SSH handshake runs in background.
  // _doConnect resolves saved-session credentials through the FRB
  // SecretStore staging path (db_sessions_stage_secrets +
  // db_ssh_keys_stage_secret); the resulting SecretStore ids land in
  // SshAuth*Ref shape, never the bytes. Quick-connect
  // / typed-passphrase paths use transient ids under conn.<slot>.<uuid>
  // and add them to Connection.transientSecretIds for cleanup on
  // terminal state. cachedPassphrase covers the interactive retry path.
  void disconnect(String connectionId);
  void disconnectAll();  // also completes pending ready futures for in-progress connections

  List<Connection> get connections;

  // Reconnect race prevention: per-connection generation counter routed
  // through lfs_core::connection::ConnectionRegistry (FRB sync). Rapid
  // reconnects bump the counter; _doConnect short-circuits if its
  // generation is no longer current.
}
```

**onDisconnect identity guard.** The per-transport `onDisconnect` callback fires when the underlying `SshTransport` observes a socket close — including the "stale cleanup" path where a superseded generation calls `disconnect()` on its own transport. Because all generations of a single reconnect cycle share one `Connection` object, a naive callback that unconditionally writes `conn.transport = null` + `conn.state = disconnected` can clobber a *newer* generation's already-live transport once the late OS close of the stale one fires. The callback therefore starts with an identity guard (`if (conn.transport != observedTransport) return;`) so only the currently-active transport can flip the shared Connection into disconnected state. The guard is load-bearing together with the generation counter: the counter stops stale *success* paths from writing `conn.transport`, the guard stops stale *disconnect* paths from wiping it. Removing either opens the same UI symptom ("connection flashes disconnected after reconnect while actually live").

**Stale-generation closing edge.** When `run_connect_driver` discovers `actor.generation` was bumped by a newer reconnect while it was inside `run_auth`, the dropped driver does not mutate `actor.state` (the live generation owns the canonical state and will publish its own terminal event) but it does publish two events through [`emit_stale_attempt_closure`](../rust/crates/lfs_core/src/connection/mod.rs) — `BusEvent::ConnectionError { detail: "connect attempt superseded by newer reconnect" }` followed by `BusEvent::ConnectionStateChanged { state: <canonical_state> }`. A per-attempt subscriber that observed the dropped attempt's `Connecting + SocketConnect:InProgress` step would otherwise hang on that progress row: the live generation's later terminal arrives on the same connection id but a strict per-attempt consumer cannot tell that signal apart from the one it was waiting for. The state echo is idempotent against the live driver — when the canonical state moves the live publish wins.

#### Connect timeout — `ssh_timeout_sec` with prompt pause

The connect driver in `lfs_core::connection::run_connect_driver` wraps the entire `run_auth` future — TCP dial + russh KEX + host-key verification + userauth — in a wall-clock cap so an unreachable host does not pin the actor for the OS-level TCP timeout (60–130 s on Linux). The cap is sourced from `AppConfig.ssh_timeout_sec` (Settings → Connection → "Connection timeout (s)"), defaults to 30 s, and is clamped to ≥1 s so a hostile / corrupt config entry cannot disable the bound entirely.

**Prompt pause invariant.** The cap covers **network and handshake time only** — wall-clock spent waiting on a user-facing prompt is *not* counted against it. Today the only such prompt is the TOFU host-key dialog (`BusEvent::KnownHostPromptRequest`, see [§3.1 host-key TOFU flow](#31-ssh-coressh)); future interactive prompts during connect (keyboard-interactive MFA, hardware-vault unlock) plug into the same gate by registering with their own prompt registry on `AppState`.

**Implementation.** `run_with_pause_aware_timeout` polls on a 250 ms tick. Whenever its `is_paused` predicate returns true on a tick boundary — currently `app.known_hosts_prompts.pending_count() > 0` — the slice since the previous tick is added to a paused-time accumulator and excluded from elapsed. Granularity is well below the typical 10–60 s `ssh_timeout_sec` range, so the effective cap is accurate to within a quarter-second of the configured value.

**Why this exists.** The original shape used a flat `tokio::time::timeout(...)` around `run_auth`, so when the TOFU dialog opened during host-key verification the timer kept ticking against the user's read-and-click time. A user who paused to read a fingerprint-change warning past the cap would see the connection fail with `connect timed out (N s)` even though the network was healthy and the dialog was still waiting on their input.

#### ForegroundServiceManager (Android only)

```dart
class ForegroundServiceManager {
  ForegroundServiceManager({
    @visibleForTesting ForegroundServiceBinding? binding,
  });
  // Android → real foreground service via binding
  // Other platforms → no-op internally

  void onConnectionCountChanged(int count);
  // count > 0 → starts foreground service with notification
  // count == 0 → stops service
}
```

**Why foreground service:** Android kills background processes. Without a foreground service, SSH connections drop on screen lock or app switch.

---

### 3.6 Security & Encryption (`core/security/`)

> The code-level reference lives in this section; the user-facing
> threat model (scope, threat boundary, KEK provider hierarchy,
> per-platform trust backing, combined matrix, vulnerability
> reporting) lives in [`SECURITY.md`](SECURITY.md). Keep
> the two in lockstep: code design decisions documented here should
> cross-link out to the SECURITY section that motivates them, never
> duplicate the threat-model prose.

#### Three-Tier + Paranoid Model

All app data lives in one SQLite database (`letsflutssh.db`) opened by `lfs_core::db` over rusqlite with the bundled SQLCipher cipher (AES-256-CBC). The user picks one of three **numbered tiers** plus one **alternative branch** ("Paranoid") shown separately in the wizard for users who do not trust the OS at all. `SecurityTier` enum values are deliberately unordered — no `<` / `>` comparisons anywhere in the codebase; feature-gating goes through predicates on `SecurityConfig` (`usesKeychain`, `usesHardwareVault`, `hasUserSecret`, `isParanoid`, `isPlaintext`).

| Tier | Label | DB key location | Typical user-typed secret (when modifier is on) | Where the secret is stored |
|---|---|---|---|---|
| **T0** | Plaintext | — (bare DB file, 0600 perms) | — | — |
| **T1** | Keychain | OS keychain on Apple/Linux/Windows (Keychain / libsecret / Credential Manager); Android uses an AES-256-GCM frame whose wrap key lives in AndroidKeyStore (TEE / StrongBox-backed when available), with the wrapped value bytes persisted as a 0600 file under `<filesDir>/lfs_secure_storage/<alias>.bin` | Password (optional, via modifier) | Salted HMAC split across disk (`security_pass_hash.bin`) and keychain; biometric variant stores the password in a biometric-gated keychain alias (`letsflutssh_biometric_encryption_key`) |
| **T2** | Hardware-bound | Hardware module (Secure Enclave / StrongBox / TPM 2.0); sealed blob in `hardware_vault_*.bin` | Master password (mandatory; Apple + Android were always password-gated, Linux + Windows now match) | Same HMAC-split pattern as T1; biometric variant stores the password in a secondary hw-gated key (`letsflutssh_hw_password_overlay`) |
| **Paranoid** | Master password | Derived fresh per unlock; never stored in the OS | Mandatory long master password | Argon2id salt + verifier in `credentials.kdf`; key material lives only inside `lfs_core::secrets::SecretStore` (`Zeroizing<Vec<u8>>`) during the unlocked window |

See [`SECURITY.md §KEK provider hierarchy`](SECURITY.md#kek-provider-hierarchy)
for the threat-model rationale behind offering both T1 (convenience,
OS-keychain-backed) and T2 (off-device extraction resistance,
bypasses the OS keychain layer).

#### Orthogonal modifiers

`SecurityTierModifiers` is the bank-style modifier container. Fields:

- `password` — when true, the user typed a secret that acts as the
  primary auth gate for the tier. Stored as HMAC-split on disk +
  keychain; compared in constant time before the KEK provider is
  touched. Paranoid and Hardware always imply `password == true` by
  design — Apple + Android were always password-gated on T2, and the
  Linux + Windows arms now match.
  `SecurityTierModifiers::is_valid_for_tier` rejects
  `(tier=Hardware, password=false)` outright, so a Hardware install
  is always enrolled with a password at setup time and the wrapped
  key on disk is sealed against it.
- `biometric` — when true, the user opted into the biometric
  shortcut. Invariant: `biometric → password`. The flag enables a
  secondary biometric-gated storage slot (biometric-protected
  keychain alias on T1 / per-platform biometric-gated key on T2:
  `letsflutssh_hw_password_overlay` Keystore on Android, SE alias
  on iOS/macOS, `LetsFLUTssh-BioOverlay-v2` CNG key with
  `NCRYPT_UI_PROTECT_KEY` on Windows) that holds the typed password;
  biometric unlock releases the password from that slot and replays
  the HMAC gate without requiring the user to retype.
The JSON decoder silently ignores any key outside the typed
`SecurityTierModifiers` shape (`password` / `biometric`) on
hand-edited configs, so a config that picks up a stray field still
parses.

Stores (`SessionNotifier`, `SshKeysNotifier`, `KnownHostsNotifier`, `SnippetsNotifier`, `TagsNotifier`, `AutoLockMinutesNotifier`) read and write through the FRB DAO layer in `lfs_core::db`; the encrypted handle lives in Rust under `AppState`. The Dart side never holds the SQLCipher key — `SecurityStateNotifier` hands the 32-byte key to `dbInit(key)` over FRB, and `dbClose()` zeroes it from inside Rust on every tier switch / auto-lock. Stores do not handle encryption; the active tier is opaque to them.

#### Tier resolution at startup (`SecurityInitController.bootstrap`)

1. If the `SecurityTierSwitcher` pending marker exists on disk → log
   and clear it. The previous run died mid-switch; the standard
   unlock path below either succeeds under the target credential or
   falls through to the reset dialog.
2. If a `.wipe-pending` marker from an interrupted
   `WipeAllService.wipeAll()` exists → resume the wipe idempotently
   before anything else touches the app-support dir.
3. One FRB call to `recoveryDetectLegacyState` (FRB shim over
   `lfs_core::security::recovery::detect_legacy_state`) bundles the
   on-disk schema-version read + the orphan-artefact existence
   probe + the `< target` decision into a single Rust-side
   transaction. Returns a `DbLegacyStateDetection` with both
   signals plus the auxiliary version fields for diagnostic
   logging. When `shouldPromptReset` is true — either the on-disk
   `config.json` is older than the build's target schema, or
   `AppConfig.security == null` **and** any managed artefact lives
   in the support-dir — show `TierResetDialog`. The dialog routes
   through `WipeAllService.wipeAll()` on user confirm; on cancel
   the app quits. Covers both "resolved tier does not match the
   sealed blob under the expected ACL" and "orphan files from a
   half-broken install". `has_current_security_config` flows from
   the Dart-side `AppConfig.security != null` snapshot so the
   orphan branch short-circuits when the running process already
   has a valid security config.
4. When the config has a tier, dispatch to the matching unlock path
   (`_unlockParanoid`, `_unlockKeychainWithPassword`, `_unlockHardware`,
   `_unlockKeychain`, or the plaintext short-circuit).
5. When no config + no managed state → first-launch
   `SecuritySetupDialog` (the wizard), then persist the chosen
   `SecurityConfig` into `config.json` via
   `_persistSecurityTier(tier, modifiers)`.

First launch is detected by the combination "no `config.security`
**and** no managed artefact **and** no pending-wipe marker." Any
single-signal detector was too fragile against partial installs and
mid-switch crashes.

**Probe parallelism at bootstrap.** `main._bootstrap` fires
`_warmProbeCaches()` at the *start* of the startup graph, before the
migration runner and `SecurityInitController.bootstrap`. `securityCapabilitiesProvider`,
`hardwareProbeDetailProvider`, and `keyringProbeDetailProvider` kick
off in parallel with the DB unlock / session load path. Previously
`_firstLaunchSetup` called `probeCapabilities()` directly, which
serialised the keychain / LAContext / BiometricManager / TPM probe
in front of wizard render — first-launch users saw a frozen empty
screen until every native round-trip completed. The wizard now
awaits the same future through `securityCapabilitiesProvider`, so it
joins whichever state the already-running probe is in. Warm starts
hit the `config.securityProbeCache` branch on the first microtask
and fall through with no work at all.

#### macOS self-sign lifecycle

T1 (keychain) tier on macOS needs a stable signing identity because macOS Keychain Services bind every stored item to the app's Code Directory hash + entitlement blob. CI releases are ad-hoc signed (`codesign --sign -`) because the project has no Apple Developer ID — the ad-hoc signature produces a different Code Directory hash every release, which means the keychain treats each install as a fresh app and the first write fails with `errSecMissingEntitlement` (-34018). The in-app self-sign flow bootstraps a user-owned signing identity so the bundle's designated requirement stays constant across upgrades and the keychain ACL keeps matching.

**Module layout.** The whole pipeline (cert / keychain / codesign + DMG installer) lives Rust-side in [`rust/crates/lfs_os_security/src/macos/`](../rust/crates/lfs_os_security/src/macos/). Dart calls the FRB bindings directly — the cert subject CN is fixed Rust-side ([`code_signing::DEFAULT_COMMON_NAME`](../rust/crates/lfs_os_security/src/macos/code_signing.rs)) so callsites pass no parameters beyond the bundle path on the resign call.

- **Cert generation** (`generate_cert` in `code_signing.rs`) — spawns `/usr/bin/openssl` to produce an RSA-2048 + X.509 v3 codeSigning cert + PKCS#12 bundle. The `-legacy` flag on `pkcs12 -export` is load-bearing: OpenSSL 3's default AES-256 / PBKDF2 MAC produces a p12 that macOS `security import` cannot parse ("MAC verification failed during PKCS12 import"), and only the legacy 3DES / SHA1 MAC is readable by SecKeychainItemImport.
- **Keychain ops** (`run_security_import` + `run_security_add_trusted_cert` + `uninstall_identity` in `code_signing.rs`) — wrap `/usr/bin/security`. Paired `-T /usr/bin/codesign` + `-T /usr/bin/security` ACL on import grants silent subsequent access (no password prompt on every re-sign). `add-trusted-cert` is the one step that surfaces a native macOS password prompt — user-domain trust-DB writes are always auth-gated.
- **Codesign passes** (`resign_inside_out` + `verify` + `extract_entitlements` in `code_signing.rs`) — wrap `/usr/bin/codesign`. Leaf-first ordering (dylibs → frameworks → xpc/appex → outer bundle) because `codesign --deep` visits nested frameworks in arbitrary order and bails with `errSecInternalComponent` on Flutter bundles the moment it re-signs a container that still references its old signature. Outer-bundle pass carries `--options runtime` + `--entitlements` so `keychain-access-groups` survives the re-sign — dropping that entitlement is exactly the -34018 trap the whole flow exists to fix.
- **Orchestrator entry points** (`has_identity` / `ensure_identity` / `resign_bundle` / `uninstall_identity` in `code_signing.rs`) — `ensure_identity()` is idempotent: it checks the keychain via `find-certificate` before generating, so re-running never invalidates existing T1 items by rotating the cert. A user-initiated "Reset secure identity" in Settings is the only path that removes + regenerates; the update flow never touches it.
- **FRB surface** (`rust/crates/lfs_frb/src/api/macos_resign.rs` ↔ `lib/src/rust/api/macos_resign.dart`) — four async entries (`macosResignHasIdentity`, `macosResignEnsureIdentity`, `macosResignBundle`, `macosResignUninstallIdentity`) plus the `MacosResignOutcome` mirror. Dart callsites invoke them directly; there is no Dart-side wrapper class.
- **Silent DMG installer** ([`rust/crates/lfs_os_security/src/macos/installer.rs`](../rust/crates/lfs_os_security/src/macos/installer.rs), exposed to Dart via `rust_macos_installer.macosInstallerInstall`): `hdiutil attach -nobrowse -noautoopen` → `rsync -a --delete` into `<target>.new` → `hdiutil detach` → `code_signing::has_identity` short-circuit → `code_signing::resign_bundle(<target>.new)` (silent under existing cert) → `code_signing::verify_bundle` gate → **entitlement probe** (re-extract entitlements from the staged bundle; if pre-resign had content but post-resign is empty, the re-sign silently stripped `keychain-access-groups` and we roll back). Final atomic swap: `<target>` → `<target>.backup`, then `<target>.new` → `<target>`. `.backup` is retained as a crash-recovery trail and swept by `installer::cleanup_backup` a few seconds after the new bundle has run cleanly.

**Critical invariant: cert stability.** The cert is created exactly once per install and reused across every release. Every `PRAGMA key` bound to keychain access requires the designated requirement derived from this cert to match between write and read — if the cert is regenerated, every stored T1 secret is silently locked out. `ensure_identity` short-circuits on `has_identity` hit; the worst thing this module can do is regenerate a cert it didn't need to, so the short-circuit is the load-bearing guarantee.

**Threat model scope.** The cert is user-only (login keychain), trusted for `codeSign` only (not TLS / email / anchor), and carries no private-key backup outside the keychain. macOS reinstall / user-account wipe destroys the cert → every T1 item becomes permanently unreadable; this is the same property that makes T1 cheap (no master password prompt on every launch). Users who want recovery from OS reinstall enable the password modifier on top of T1 or switch to Paranoid (master-password-derived key, survives keychain wipe). Full threat rows in [`SECURITY.md`](SECURITY.md) — see also [§3.10 Update channel integrity](#310-update-coreupdate) for how the same bundle-swap path interacts with the Ed25519 release-signature verifier.

**User-facing flow.** The wiring above is driven from two surfaces and one callback, never from more than one place simultaneously:

- **First-launch pre-prompt** ([`security_init_controller_first_launch._offerMacosSelfSign`](../lib/app/security_init_controller_first_launch.dart)). Runs inside `_firstLaunchSetup` immediately after the capability probe resolves and *before* the tier wizard is constructed. Fires only when `Platform.isMacOS && !caps.keychainAvailable && caps.hardwareProbeCode == 'macosSigningIdentityMissing'` — a narrow gate that matches exactly the ad-hoc-signing-identity case, not any of the other "hardware unavailable" reasons (pre-T2 Intel Mac, passcode unset, etc). Shows an `AppDialog` with Accept / Decline. Accept runs the identity + re-sign pipeline and re-probes; the refreshed capabilities flow back into the auto-setup-T1 branch unchanged. Decline widens caps into the reduced shape (`keychainAvailable: false && hardwareVaultAvailable: false`), and the wizard renders T0 + Paranoid only — the same branch a Linux host without gnome-keyring lands on. No inline "Enable Keychain" button inside the wizard itself — the pre-prompt is the single opt-in moment, and duplicating it on the T1 row would let the user re-sign twice for no gain.

- **Settings → Security tail row** ([`settings_sections_security._SecuritySectionState`](../lib/features/settings/settings_sections_security.dart)). Probes `macosResignHasIdentity()` once on mount and chooses between two shapes:
  - **No cert on the Mac** → primary "Unlock secure tiers on this Mac" button. Same pipeline as the first-launch accept path; lets the user change their mind after declining at first launch or after the cert was wiped (OS reinstall, manual `security delete-identity` by an adventurous user).
  - **Cert present** → destructive "Remove signing identity" button. Opens a confirmation dialog (T1 / T2 stored secrets are tied to the cert's designated requirement), then the tier-switch wizard with `capabilitiesOverride` forced to the reduced shape so the user can only pick T0 or Paranoid. `_applyTierChange` rekeys the DB under the new tier; only after the tier switch has committed does `macosResignUninstallIdentity()` delete the cert + trust entry. Order matters: removing the cert before the rekey would silently lock the user out of every T1 / T2 secret mid-flow.

- **Silent update-install callback** ([`updateServiceProvider` macOS adapter](../lib/providers/update_provider.dart)). Runs inside the download → install pipeline; `rust_macos_installer.macosInstallerInstall` reaches `code_signing::resign_bundle` silently under the already-present cert (no password prompt, `-T /usr/bin/codesign` ACL is sufficient). When no cert is present (user declined the pre-prompt and never enabled from Settings), `has_identity` returns `false`, the resign step is skipped, and the installed bundle keeps its CI ad-hoc signature, consistent with the user's original decline.

All three surfaces converge on `ensure_identity` + `resign_bundle` Rust-side — the orchestrator guarantees the idempotency invariant across every path, so even a user that cycles Accept → Remove → Accept a dozen times never rotates the cert (the regenerate path is never reachable from these flows; a hypothetical "Reset and re-generate" action would need its own confirmation + explicit tier migration).

**Key-derivation pipeline** (only the master-password branch derives; keychain stores the DB key directly, plaintext has no key):

```mermaid
flowchart LR
    A[User password] --> B["Argon2id (Rust)<br/>m=64 MiB, t=3, p=1<br/>+ 32-byte salt"]
    B --> C["32-byte DB key<br/>(Vec&lt;u8&gt; in Rust)"]
    C --> D["SecretStore + Zeroizing<br/>(process-singleton, locked + zeroed on drop)"]
    D --> E["lfs_core::db<br/>SQLCipher PRAGMA key"]
    D -.-> F["Optional:<br/>BiometricKeyVault<br/>(OS keychain / hw-bound)"]
    F -.-> D
```

Argon2id derivation runs inside `lfs_core::crypto` on a Tokio blocking task; the Dart side calls `dbInit(key)` / `dbRekey(newKey)` over FRB, hands a `Uint8List` of the derived 32 bytes once, and never sees the bytes again. The SecretStore is process-singleton, owns every cached secret as `Zeroizing<Vec<u8>>`, and runs `dbClose()` on auto-lock to zero SQLCipher's C-layer page-cipher state alongside the cached key.

**KDF file format** (`credentials.kdf`, v1):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | Magic `'LFKD'` (0x4C 0x46 0x4B 0x44) |
| 4 | 1 | File version (`0x01`) |
| 5 | 1 | KDF algorithm id (mirror of params[0]) |
| 6 | 10 | Argon2id params: `memoryKiB` (u32 BE), `iterations` (u32 BE), `parallelism` (u8), plus algorithm id byte prefix |
| 16 | 32 | Random salt |

The algorithm id + params block is defined in [`KdfParams`](../lib/core/security/kdf_params.dart) — new algorithms can be added without changing the file-layout header. The canonical production profile lives Rust-side in [`lfs_core::security::master_password::KdfParams::defaults`](../rust/crates/lfs_core/src/security/master_password.rs) (Argon2id m=64 MiB t=3 p=1, one tier above the OWASP 2024 floor of 46 MiB / 2 / 1 — desktop/mobile UX absorbs the extra ~60% derive cost for stronger brute-force resistance). The Dart [`KdfParams.productionDefaults`](../lib/core/security/kdf_params.dart) field is a `late` mirror populated at startup through the sync FRB getter `kdfParamsProductionDefaults`, so Rust is the single source of truth.

**Sanity ceilings on decode.** `KdfParams.decode` validates each Argon2id field against an upper bound (1 GiB memory, 16 iterations, 8 lanes) before constructing the record — decode of a crafted `credentials.kdf` with absurd costs (4 GiB of RAM, a million iterations) throws `FormatException` rather than spinning up the derivation isolate and wedging unlock on an OOM. The ceilings give ~20× headroom over today's production profile, well past any plausible future tuning, while ruling out denial-of-service by file tamper.

#### Cached secrets — Rust SecretStore

Cached plaintext credentials (DB key, session passwords, key passphrases, staged PEM bytes) live exclusively in `lfs_core::secrets::SecretStore` — a `Mutex<HashMap<String, Zeroizing<Vec<u8>>>>` owned by the process-singleton `AppState`. Every value is a `Zeroizing<Vec<u8>>`, so dropping the entry zeroes the bytes before deallocation. The Dart side fires `secrets_put` / `secrets_drop` / `secrets_clear` over FRB; the only cached-credential abstraction left in Dart (`SessionCredentialCache` in `core/security/session_credential_cache.dart`) is a thin namespace wrapper that translates `(sessionId, slot)` → canonical id (`sess.password.<id>` / `sess.key.<id>` / `sess.passphrase.<id>`) and forwards the call.

Two more secret-id namespaces ride on the same store: `key.priv.<keyId>` for staged manager-key PEM bytes (populated by `db_ssh_keys_stage_secret` on the connect path) and `conn.<slot>.<uuid>` for transient quick-connect bytes (lifetime bounded by the in-flight connect attempt). The connect path emits `SshAuthPasswordRef(secretId)` / `SshAuthPubkeyRef(secretId, passphraseSecretId)` so russh fetches the bytes inside Rust without ever crossing the FRB boundary.

`SecurityStateNotifier` no longer owns the DB key as the primary residence. The 32-byte derived key flows: unlock orchestrator stages it under the canonical SecretStore id → Dart's tier-unlocked listener calls `secrets_take(id)` → the bytes briefly cross FRB → Dart wraps them in a `SecretBuffer` (mlock / VirtualLock-pinned page) → hands them to `dbInit(key)` → `SecretBuffer.dispose()` zeroes the page. The Rust-side `SecretStore` entry is gone after the take; the SQLCipher key lives inside Rust until `dbClose()` zeroes the cached page-cipher state on auto-lock or a tier switch. `SecretBuffer` still exists for that narrow Dart-heap residency window plus the `SecurePasswordField` typed-secret mirror, but is no longer the primary holder of the long-lived DB key — that role moved entirely Rust-side.

**Bytes-don't-cross invariant — current state.** Every credential path keeps plaintext bytes on the Rust side of the FRB boundary. Connect / edit / duplicate / bulk listing paths read credentials only via SecretStore staging or pre-hashed metadata. `.lfs` archive composition runs entirely Rust-side via `db_export_archive` / `lfs_core::archive::export_archive`: the orchestrator reads sessions / ssh_keys / tags / snippets / session_tags / folder_tags / session_snippets / known_hosts straight from `letsflutssh.db`, builds the manifest + per-entry JSON inside Rust, ZIPs in Stored mode, applies the Argon2id + AES-GCM envelope, and writes the encrypted bytes atomically to the caller-supplied `output_path` via `lfs_core::path::write_bytes_atomic` (tmp + fsync + rename + parent-dir fsync). The Dart caller no longer holds the encrypted blob on the heap: `db_export_archive` returns just a byte count for logging, the file ends up at `output_path` directly, and a crash mid-write leaves the previous file intact. The QR-export deeplink path is symmetric: `db_export_qr_payload` and the live size estimator (`qr_estimate_export_size`, sync) both read sessions / keys / tags / snippets from the open SQLCipher connection by id, so manager-key PEM bytes never cross the FRB boundary into Dart memory for either the gauge or the actual emit. The `.lfs` size estimator (`db_lfs_export_size`, sync) routes through the same id-based `lfs_core::archive::export_archive_size` for parity with the production producer.

#### SecretStore + SecretRef: the plaintext-discipline rule

The cross-FFI boundary contract referenced from [§3.14 Boundary contract](#314-rust-securitytransport-core-rust). Three rules combine into one invariant — **plaintext does not cross FRB outbound, and crosses inbound only on the user-just-typed-it path**:

1. **Outbound — never plaintext.** Every Rust function that produces secret bytes (derived AES key from `master_password_enable/_change`, the unsealed DB key from `tpm_unseal`, the AES-GCM plaintext from `crypto_aes_gcm_decrypt`, the entry payload from `secrets_take`) stages the bytes in [`SecretStore`](#cached-secrets--rust-secretstore) under a caller-allocated id and returns the id (`String`). The `secrets_take(id)` shim is the only way to materialise the bytes Dart-side; it atomically reads the `Zeroizing<Vec<u8>>`, removes the entry from the store, and hands the `Vec<u8>` to FRB. The Dart caller has the bytes for one logical operation (hand them to `dbInit` / hand them to a connect call) and must drop them as soon as the operation completes. Inside `lfs_core` the bytes never appear as a bare `Vec<u8>` return — every cryptographic helper (`crypto::argon2id_derive`, `crypto::aes_gcm_decrypt*`, `crypto::aes_gcm_random_key`, `crypto::hkdf_sha256`, `master_password::verify_and_derive`) returns `Zeroizing<Vec<u8>>` so the bytes drop cleanly when the caller's binding goes out of scope.
2. **Inbound — only the freshly-typed path.** A new password coming out of an unlock dialog has to cross FRB once on the way to the verifier. After that, every subsequent call (re-verify, change-password, archive export, QR encode, session staging) takes a SecretStore id instead of the bytes. The `*_with_secret_id` variants under `lfs_frb::api::ssh` and `lfs_frb::api::auth_compose` are the canonical inbound shape; the legacy plaintext variants (`ssh_connect_password(password: String)`, `db_sessions_set_secret(value: String)`, etc.) survive only as compatibility shims for the typed-just-now case and should not be the default for any non-dialog caller.
3. **Bus events — no inline secrets.** The tokio broadcast channel buffers events behind every subscriber's read cursor; a slow Dart subscriber holds the buffered event in RAM until it consumes the channel. `Event::HardwareVaultSealPromptRequest { db_key_secret_id: String, pin_secret_id: Option<String> }` carries SecretStore ids, not bytes; the Dart listener calls `secrets_take` to materialise the bytes only when it owns the prompt UI.

The discipline is not academic: a returned `Vec<u8>` lives on the Dart heap with no `Zeroize`, the broadcast channel keeps a clone alive for every subscriber until consumed, and `TextEditingController` for any password field copies the bytes into a `String` (immutable, GC-tracked, not zeroizable). SecretRef is the only shape under which any of those vectors can be eliminated wholesale.

The wipe-completeness regression test (`security::wipe::tests::every_known_artefact_is_in_managed_files`) and the Rust-side rate-limit gate tests (`security::tier_unlock_orchestrator::tests::unlock_*_short_circuits_when_limiter_locked`) are the regression guards on the parts of this invariant that have automatable shapes; the remaining "is this Dart caller still hitting the legacy plaintext arm?" check stays a code-review concern.

#### Unlock-path single KDF

Every master-password unlock verifies the password *and* produces the derived DB key in one Argon2id pass. `MasterPasswordManager.verifyAndDerive(password)` calls into `lfs_core::crypto` over FRB, which runs Argon2id on a Tokio blocking task and returns the derived 32-byte key on success or `null` on wrong password. `UnlockDialog`, `LockScreen`, and the biometric-enable flow all use it; `verify()` stays available as the thin `verifyAndDerive(...) != null` wrapper for call sites that don't need the key (e.g. the remove-master-password confirm). Argon2id is CPU + memory-heavy, so a single-call shape saves real wall-clock on every unlock — and now the heavy work runs off the Dart UI isolate entirely.

#### Switching tiers on the fly — always-rekey invariant

Every tier switch — T0↔T1↔T1+pw↔T2↔Paranoid, **including `password`-modifier flips on the same tier** — generates a fresh random 32-byte DB key and rekeys the whole DB under it. The previous wrapper (keychain entry, hardware-sealed blob, Argon2id verifier) is invalidated by the rekey, so a previously leaked wrapper cannot decrypt post-switch data.

**Exception — biometric-only toggle.** Flipping the `biometric` modifier on an otherwise-identical config (same tier, same `password` state) does **not** trigger a rekey. The DB-key wrapping is unchanged — biometric is purely additive, a secondary copy of the typed password in a biometric-gated slot (see [#biometric-unlock](#biometric-unlock)) — so a rekey would cost the user a re-prompt for the password with zero cryptographic gain. `settings_sections_security._applyBiometricOnlyToggle` handles this path: it calls `_applyPendingBiometric` directly (password prompt on enable, vault clear on disable) and skips `_applyTierChange` entirely. The tier-card Apply button routes here when the only pending diff is the biometric flag.

[`SecurityTierSwitcher.switchTier`](../lib/features/settings/security_tier_switcher.dart) owns the orchestration order:

1. Generate a fresh 32-byte key via `Random.secure()` (CSPRNG-backed — `/dev/urandom` on POSIX, `BCryptGenRandom` on Windows).
2. Write `.tier-transition-pending` marker with the target tier's JSON payload. Marker lives in app-support, hardened to 0600.
3. `rekeyDatabase(db, newKey)` — atomic `PRAGMA rekey` transaction. On failure the DB is still under the source key; the marker points at the unfinished target so startup notices.
4. `applyWrapper(newKey)` — tier-specific: write to `SecureKeyStorage`, `HardwareTierVault.store`, `MasterPasswordManager.enable`, etc.
5. `persistConfig(newKey)` — update `securityStateProvider` + mirror the new tier into `config.json`.
6. `clearPrevious()` — tier-specific cleanup: delete the previous keychain entry, clear the hardware vault, clear the password gate, disable the master-password manager, clear the biometric vault.
7. Delete the marker as the last step; its absence is the "all good" signal the next startup relies on.

A crash between steps 3 and 7 leaves the marker on disk. `SecurityInitController.bootstrap` logs and clears the marker on the next launch; the standard unlock path then succeeds under whichever credential the user can supply (source or target), or falls through to reset. This tolerates the 25-pair tier-transition matrix without needing per-pair recovery logic.

Settings exposes the switcher through a single "Change Security Tier" action that reopens the wizard pre-marked with the current tier and routes the result through `_applyTierChange` (`settings_sections_security.dart`) — every on-disk tier switch goes through the same orchestration path.

#### T1+pw keychain-password gate (`KeychainPasswordGate`)

T1+pw layers a UX-only short password in front of the T1 keychain-stored DB key. The password is **not** a cryptographic layer: an attacker who can read both the disk and the OS keychain already has every ingredient for the DB key, password or not. The gate exists to deny a coworker at the desk, not to resist offline attack.

State layout:

- `security_pass_hash.bin` on disk holds `{salt, HMAC-SHA256(pepper, salt || password)}` as JSON.
- OS keychain holds the pepper under `letsflutssh_l2_pepper`.

`setPassword` rotates both salt and pepper atomically; a stale pepper without a fresh disk write (or vice versa) fails `verify` — the split storage is the tamper surface. `verify` uses constant-time compare. A persistent rate limiter (see below) is keyed by the stored HMAC, so any offline attempt to reset the limiter to zero-failures requires forging a HMAC whose key the attacker already has the pieces of.

**Write order + atomicity.** `setPassword` writes the disk hash through [`writeBytesAtomic`](../lib/utils/file_utils.dart) **before** touching the keychain, and rolls back the disk hash if the keychain write fails. Two invariants hang off that ordering. First, a torn disk write would leave `security_pass_hash.bin` with truncated JSON; on the next launch `verify()` throws inside `jsonDecode`, `isConfigured()` reports false (the `containsKey(pepper)` still returns true, but the torn disk blob routes the unlock path to the plaintext-tier fallback), and the user silently lands on T0 when they thought they were on T2. Second, keychain-first ordering would allow a crash between the two writes to leave the keychain holding the NEW pepper while disk still held the OLD `{salt, HMAC}` — the correct password would stop verifying (HMAC keyed under NEW pepper while disk HMAC was built under OLD pepper), locking the user out until a full reset. Disk-first + atomic-rename keeps the recoverable state either "both old" (crash before keychain write) or "both new" (crash after keychain write); the rollback branch on keychain failure returns to "neither" and routes the next launch through the first-launch wizard cleanly. Regression guards: `test/core/security/keychain_password_gate_test.dart` "setPassword writes atomically" + "setPassword writes disk hash before keychain pepper".

#### T2 hardware vault (`HardwareTierVault`)

T2 seals the DB key inside a hardware module under an auth value derived as `HMAC-SHA256(pin, salt)`. The hardware module enforces rate-limiting and lockout after N failed attempts — that is what makes a 4–6 digit PIN cryptographically meaningful; dictionary attack against such a short secret is infeasible only because the hardware refuses retries.

Per-platform dispatch:

| Platform | Binding | File | PIN channel |
|---|---|---|---|
| **Linux** | TPM2 via `tpm2-tools` Rust subprocess in [`lfs_core::security::hardware_tier_vault::linux`](../rust/crates/lfs_core/src/security/hardware_tier_vault.rs); the spawn + wait runs entirely inside Rust, Dart only invokes via FRB | `hardware_vault.bin` (salt + sealed blob; v3 envelope wraps the TPM-sealed `(public, private)` pair as a TCG ASN.1 DER `id-loadablekey` body — wire-compatible with `openssl-tpm2-engine` / `ssh-tpm-agent`) | PIN HMAC goes to TPM `-p file:<path>` as the unseal auth value — TPM lockout is the rate limiter |
| **iOS / macOS** | P-256 in Secure Enclave (`kSecAttrTokenIDSecureEnclave`) with `.biometryCurrentSet` via Rust `lfs_os_security::hardware_tier_vault::apple` (`security-framework` + `objc2`) | `hardware_vault_apple.bin` (Rust-side envelope) + `hardware_vault_salt.bin` (Dart side) | PIN HMAC is an external gate — SE accepts only biometrics for release |
| **Android** | AES-256-GCM in Keystore with `setUserAuthenticationRequired(true)` + `setInvalidatedByBiometricEnrollment(true)` + StrongBox preferred, via Rust `lfs_os_security::android::hardware_vault` (direct JNI to `java.security.KeyStore` provider `"AndroidKeyStore"`) | `hardware_vault_android.bin` + salt file | PIN HMAC is an external gate — Keystore requires `BiometricPrompt.CryptoObject` for release |
| **Windows** | CNG / `NCrypt` on the Microsoft Platform Crypto Provider (TPM 2.0) via Rust `lfs_os_security::windows::hardware_vault` (`windows` crate FFI). Falls back to Microsoft Software KSP when no TPM. Primary wrap key `letsflutssh_hardware_vault_v1` is silent (no Hello); biometric overlay key `letsflutssh_hardware_vault_bio_v1` carries `NCRYPT_UI_PROTECT_KEY_FLAG \| NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG` so every unwrap fires Hello | `hardware_vault.bin` + `hardware_vault_password_overlay_windows.bin` + salt file | PIN HMAC is an external gate — wrong PIN fails without waking the TPM. `ERROR_INVALID_HANDLE` from any NCrypt entry triggers one retry against a freshly opened provider + key so a sibling `clear_hardware_vault` racing with an unlock cannot brick the primary path |

The PIN is the user-facing secret on every platform, but the binding path diverges: Linux alone is hardware-auth-value-native (TPM accepts arbitrary HMAC bytes as the unseal password). Apple / Android / Windows APIs gate the hardware key release on biometrics / Hello, so the PIN runs as a local HMAC gate that is checked *before* the biometric prompt fires; a wrong PIN fails without waking the user's sensor. Salt lives in Dart-owned `hardware_vault_salt.bin` so two installs with the same PIN produce different gates.

Native plugin code is shipped but has not been validated on real hardware — the plan's "manual device-testing pass" acceptance is still outstanding. CI compiles each plugin on its own runner (macos-latest / windows-latest / ubuntu-latest + Android SDK) but cannot exercise biometric / Hello / StrongBox prompts. iOS is not in the release matrix; the project file carries the entries so `flutter build ios` works when invoked on a developer's Mac.

Per-install salt is generated on `store()` and written alongside the sealed blob in `hardware_vault.bin`. Two devices with the same PIN never end up with the same sealed blob.

**Atomic writes.** Both `hardware_vault.bin` (Linux sealed blob + salt JSON) and `hardware_vault_salt.bin` (method-channel platforms, salt only) are written through [`writeBytesAtomic`](../lib/utils/file_utils.dart) — tmp-file + `hardenFilePerms` + rename. A crash mid-flush therefore leaves either the previous record or the new record on disk, never a torn file. Matters on the Linux path because the sealed blob + salt live in the same file (a torn JSON unseals into nothing); matters on method-channel platforms because the salt is half of the unseal contract (the other half being the wrapped key the native plugin holds), and a half-written salt bricks the vault permanently.

**Linux inner JSON shape.** The body inside the outer `LFHV[magic+version+platform_id]` envelope is `{"v":1,"salt":"<base64>","sealed":"<base64>"}`. The inner `"v"` integer (constant `LINUX_BLOB_INNER_VERSION` in [`lfs_core::security::hardware_tier_vault`](../rust/crates/lfs_core/src/security/hardware_tier_vault.rs)) disambiguates a future shape change (extra IV / AAD frame, swapped encoder) independently of the outer platform tag — without it a tampered or pre-spec file would parse silently against the wrong field set. Decode is strict: a missing `"v"` or any value other than the current constant routes through the corrupt-state cascade. Bumping the inner version is the additive path; reserving a fresh `HW_VAULT_PLATFORM_LINUX_V2` outer tag remains the escape hatch when a shape change has to invalidate every prior install.

**Native-side atomicity — every platform.** The invariant extends into the native plugins that own the wrapped-key half of the vault:

| Platform | File | Mechanism |
|---|---|---|
| **iOS / macOS** | `hardware_vault_apple.bin`, `hardware_vault_password_overlay_apple.bin` | `Data.write(to:options:[.atomic, .completeFileProtection])` — Swift's own tmp-file + rename. |
| **Android** | `hardware_vault_android.bin`, `hardware_vault_password_overlay_android.bin` | Rust `lfs_os_security::path::write_bytes_atomic` (tokio `fs::write` to a tmp sibling, `Permissions::from_mode(0o600)`, `fs::rename` atomic inode swap on ext4 / f2fs). |
| **Windows** | `hardware_vault.bin`, `hardware_vault_password_overlay.bin` | Rust `lfs_os_security::path::write_bytes_atomic` (tokio `fs::write` to a tmp sibling, then `fs::rename` — NTFS atomic-on-same-volume rename invariant, same primitive as Android). |

A torn blob on any platform otherwise yields `readVault` → null → `isStored` → true-but-garbage → next unseal returns nothing → Dart side silently drops biometric / hardware unlock without a "vault corrupted" hint. The invariant matches the Dart-side hardware-vault atomic write and the biometric-vault atomic write already enforced by `writeBytesAtomic`.

**Windows private-key export policy.** Keys created by `lfs_os_security::windows::hardware_vault::open_or_create_key` (both primary data-wrap and biometric overlay) pin `NCRYPT_EXPORT_POLICY_PROPERTY = 0` (`NCRYPT_ALLOW_EXPORT_NONE`) via `NCryptSetProperty` before `NCryptFinalizeKey`. On the Platform Crypto Provider (TPM 2.0) path keys are non-exportable by design; the Microsoft Software KSP fallback, which the provider ladder selects when no TPM is reachable, defaults to `NCRYPT_ALLOW_EXPORT_FLAG | NCRYPT_ALLOW_PLAINTEXT_EXPORT_FLAG` — any local-user process could otherwise call `NCryptExportKey` to lift the DB-wrap RSA private key in plaintext, defeating the separation between the ciphertext file and the wrapping key. Setting the policy to 0 covers both providers uniformly and has to happen *before* `Finalize` because CNG rejects policy changes on finalized keys. Mirror of Android's `setInvalidatedByBiometricEnrollment` invariant: both pin the private key to the hardware-backed storage so the blob on disk is only useful in combination with the live CNG / Keystore handle.

#### Rate limiters — per-tier matrix

[`PasswordRateLimiter`](../lib/core/security/password_rate_limiter.dart) is the abstract base; three concrete variants cover the tier matrix:

| Tier | Limiter | Persistence | Rationale |
|---|---|---|---|
| **T0 / T1** | none | n/a | T0 has no user secret; T1 auto-unlocks via keychain, no retry surface |
| **T1+pw** | `PersistedRateLimiter` | disk, HMAC-authenticated | UX-gate password has no cryptographic strength; a process-restart reset would be free for an attacker |
| **T2** | `HardwareRateLimiter` | in-memory | Thin software counter on top of the platform's hardware lockout — defense-in-depth if the hardware layer is misconfigured |
| **Paranoid** | `InMemoryRateLimiter` | in-memory | Argon2id is the real brake; persisting a forgot-password wait across restarts is user-hostile for no extra safety |

All three share the backoff schedule `[0, 1, 2, 4, 8, 16, 32, 60, 60, 60] s` — capped at 60 s so a legitimate user who genuinely forgot their password never waits more than a minute between retries.

`PersistedRateLimiter` writes `{failureCount, nextRetryAtMillis}` to `rate_limit_state.bin` framed with an HMAC-SHA256 tag. The signing key is **HKDF-derived** from the T1+pw gate's stored HMAC under the `lfs/persisted-rate-limit/v1` info string — the gate HMAC verifies the user-typed password and the rate-limit HMAC signs the cooldown state, with HKDF enforcing key-separation so an attacker who recovers either side has no algebraic shortcut to forge the other. Pre-v1 state files signed the payload with the gate HMAC directly; the decoder retries verification with the raw gate HMAC on first-pass mismatch and the next mutation re-emits under the derived key, migrating the file in-place without a registry hop. Tamper detection: a mismatch on load (against both the derived and the legacy keys) clamps the counter to the schedule cap and sets `nextRetryAt` to `now + 60 s`, so an attacker who overwrites the state file with garbage lands in max cooldown rather than zero-failures. Writes are serialised on a `Future` chain so back-to-back `recordFailure` / `recordSuccess` calls never race at the filesystem.

**Monotonic-floor cooldown (clock-jump hardening).** `record_failure` issues `next_retry_at_millis = max(now + step_ms, prev_next_retry_at_millis)` so a backward clock jump (NTP correction, suspended laptop with battery-drained RTC, hostile system-time write) cannot shrink an already-issued cooldown. Without the floor an attacker with system-clock write access could burn through the geometric backoff: fail → roll clock back → fail → roll back → repeat, issuing each new cooldown against rolled-back time and skipping the schedule entirely. Forward jumps still let the cooldown expire on schedule (legitimate NTP corrections + DST forward roll); only backward jumps are clamped. Regression: `persisted_rate_limit_actor::tests::backward_clock_jump_does_not_shrink_cooldown`.

The unlock dialogs (`UnlockDialog`, `TierSecretUnlockDialog`) consult `rateLimitStatus()` on mount, refuse `verify` while locked, start a 1-Hz `Timer.periodic` to refresh the countdown, and disable the submit button until the cooldown clears. The rendered label uses the `tierCooldownHint(seconds)` l10n key in all 15 locales.

**Rust-side gate — `tier_unlock_orchestrator`.** The Dart-side limiter above is the user-visible brake. Behind it, `lfs_core::security::tier_unlock_orchestrator::unlock_keychain_with_password` and `unlock_paranoid` consult a Rust-side [`InMemoryRateLimiterRegistry`](../rust/crates/lfs_core/src/rate_limit.rs) under fixed ids (`tier_unlock.keychain_with_password` / `tier_unlock.paranoid`) **before** the verifier runs. A direct FRB caller — programmatic test harness, future Tauri client, hostile process with the FFI surface mapped — would bypass the Dart dialog entirely; the Rust-side gate catches that path. Same exponential schedule as the Dart limiter (`[0, 1, 2, 4, 8, 16, 32, 60, 60, 60] s`) so the user-visible countdown matches what the Rust core enforces. `record_failure` increments after a wrong-password verify, `record_success` clears the counter after a correct one, and `status(id).is_locked()` short-circuits to `WrongSecret` while the cooldown holds — without ever touching the verifier (which would otherwise pay the Argon2id cost on Paranoid). Regression: `tests::unlock_keychain_with_password_short_circuits_when_limiter_locked` + `unlock_paranoid_short_circuits_when_limiter_locked`.

#### Biometric unlock

Optional on **T1+password and T2+password only**. Paranoid is intentionally excluded — the tier's "no OS trust" premise rules out a biometric-gated keychain slot (it would pull the DB key back into exactly the OS layer the tier is meant to avoid), and `settings_sections_security._biometricSpecFor` returns `null` for Paranoid so the Settings card never renders the toggle.

**Anti-debug gate — single funnel.** Every biometric attempt (startup `_unlockKeychainWithPassword` / `_unlockHardware`, the inline retry button inside `TierSecretUnlockDialog`, and the mid-session `LockScreen` re-unlock all funnel through `SecurityInitController._tryBiometricCommit`) consults [`ProcessHardening.isBeingDebugged()`](../lib/core/security/process_hardening.dart) before touching the vault. On a positive probe the funnel writes a `logCritical` breadcrumb (`ProcessHardening` tag, `tier=<wireName>`) and returns `false` — the dialog falls through to the typed-secret form, so a debugger watching the process cannot scoop the OS-stored password released by a successful biometric prompt. Probe is fail-safe-false: any FRB error / unreadable `/proc` returns `false` so a hardened-`/proc` host or sandboxed iOS build cannot brick legitimate unlock. Pairs with the static startup pass in [`ProcessHardening.applyOnStartup`](#process-hardening) (which BLOCKS new attaches via `prctl PR_SET_DUMPABLE` / `PT_DENY_ATTACH` / `SetErrorMode`) — the runtime probe READS the post-hardening state so callers can react to a debugger that landed despite the block (debug-signed macOS bundle, Linux host with `cap_sys_ptrace`, Xcode-attached dev build). Threat-model rationale lives in [`SECURITY.md → Anti-debug biometric gate`](SECURITY.md#orthogonal-mitigations); this section is the wiring reference.

 [`BiometricAuth`](../lib/core/security/biometric_auth.dart) routes the availability probe + prompt through `lfs_os_security::biometric_auth` (Apple LAContext via `objc2-local-authentication`, Windows `UserConsentVerifier`, Android JNI to `BiometricManager` + `BiometricPrompt`) plus the direct fprintd D-Bus walk on Linux. [`BiometricKeyVault`](../lib/core/security/biometric_key_vault.dart) stores the already-derived DB key — Apple / Android / Windows all route through `lfs_os_security::secure_key_storage::write_biometric` (Apple `SecAccessControl` + `kSecAccessControlBiometryCurrentSet` via `SecItemAdd`; Android `setUserAuthenticationRequired(true)` on the AndroidKeyStore wrap key via JNI; Windows Credential Manager via `CredWriteW` plus the `BiometricAuth` Hello prompt fired ahead of the read). Linux uses TPM2 seal first, then a libsecret-marker fallback (also via Rust `secure_key_storage`). At startup, `_unlockKeychainWithPassword` and `_unlockHardware` (both in [`security_init_controller_unlock.dart`](../lib/app/security_init_controller_unlock.dart) — extension on `SecurityInitController`) probe `biometricKeyVault.isStored() && biometricAuth.isAvailable()` and call `_tryBiometricCommit()` **first**, skipping the password dialog entirely on success. Only on biometric failure / cancel does [`TierSecretUnlockDialog`](../lib/widgets/security/tier_secret_unlock_dialog.dart) render; it opens with `autoTriggerBiometric: false` to avoid a double-prompt, but the fingerprint retry button inside the dialog stays available so the user can re-invoke the system prompt without relaunching. [`UnlockDialog`](../lib/widgets/security/unlock_dialog.dart) (Paranoid only) has no biometric surface at all — by design.

**Apple platforms — Secure Enclave binding.** On iOS and macOS the vault stores the DB key with a `SecAccessControl` that stacks `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` with `SecAccessControlCreateFlags.biometryCurrentSet`, applied Rust-side via `lfs_os_security::secure_key_storage::write_biometric` (raw `SecItemAdd` against the `security-framework-sys` FFI). Two consequences follow: (a) the key material is held in the Secure Enclave, so even a device-level RAM compromise cannot exfiltrate it; and (b) any change to the biometric enrolment (added or removed fingerprint, re-enrolled Face ID) invalidates the stored key, forcing the user back through the master-password dialog on the next unlock. Android binds the wrap key in AndroidKeyStore via direct JNI (`lfs_os_security::android::keystore::write_biometric`) with `setUserAuthenticationRequired(true)` + `setUserAuthenticationValidityDurationSeconds(60)`; the `BiometricPrompt` invocation is fired by the Dart caller through `lfs_os_security::biometric_auth::authenticate` ahead of the read. When biometric fails (cancel, wrong finger) the fallback is `UnlockDialog` — which itself auto-triggers biometric on first frame as long as `autoTriggerBiometric` is true. The unlock flow passes `false` when it already attempted biometric to prevent a double-cancel loop; the retry button inside the dialog stays available either way, so the user can re-invoke biometrics without relaunching the app. `LockScreen` (mid-session re-lock overlay) follows the same auto-trigger + retry pattern.

`BiometricAuth.availability()` returns a `BiometricUnavailableReason?` (null when biometrics work). The Rust `lfs_os_security::biometric_auth::check_availability` per-platform answer (Apple LAContext, Windows `UserConsentVerifier`, Android `BiometricManager.canAuthenticate`) covers most of the surface, but on Windows it can falsely report ready when only a Hello PIN is configured — `UserConsentVerifier::CheckAvailabilityAsync` says "available" the moment Windows Hello is set up, regardless of whether a physical biometric sensor exists. The Windows arm in [`lfs_os_security::biometric_auth`](../rust/crates/lfs_os_security/src/biometric_auth.rs) chains a second probe inside the same `check_availability` call: when `UserConsentVerifier` returns `Available`, it calls [`lfs_os_security::winbio::count_units`](../rust/crates/lfs_os_security/src/winbio.rs) which runs `WinBioEnumBiometricUnits(Factor = FINGERPRINT | FACIAL | IRIS)` against `winbio.dll`. Zero units → the hardware is not attached; the verdict demotes to `NoSensor` regardless of what `UserConsentVerifier` claims. A `-1` sentinel (the SDK lib could not be loaded — stripped enterprise image, missing `winbio.dll`) leaves the original WinRT answer intact so a user whose hardware we cannot probe is not locked out. The enumeration is zero-prompt and side-effect-free — safe to run on every availability poll. The settings UI uses the multi-state result to show a reason tooltip on a disabled toggle instead of hiding the option. Keeping the gate Rust-side preserves the `lfs_os_security`-is-the-single-FFI-perimeter invariant: Dart never reaches `winbio.dll` directly.

`BiometricUnavailableReason` also carries `systemServiceMissing` — the rung-3 reason for the Linux path: the toggle is disabled with a `fprintd is not installed. See README → Installation.` reason whenever the OS-level fingerprint daemon is absent.

**Linux — `fprintd` D-Bus binding.** On Linux `BiometricAuth.availability()` calls FRB into [`lfs_core::platform::linux::fprintd`](../rust/crates/lfs_core/src/platform/linux/fprintd.rs), a thin async wrapper over the `net.reactivated.Fprint` system bus driven by the `zbus` Rust crate. The ladder is strict: if the daemon is not registered (`GetDefaultDevice` fails or the bus name is unknown) → `systemServiceMissing`; if the default device reports an empty `ListEnrolledFingers("")` → `notEnrolled`; otherwise biometrics are ready. `authenticate()` on Linux issues a `Claim` → subscribes to `VerifyStatus` → calls `VerifyStart("any")` → awaits the terminal signal with a 30 s timeout, and always `Release`s the device on every exit path so a failed verify does not leave the reader stuck. The D-Bus walk lives Rust-side specifically so the unsealed DB key path stays single-language end-to-end (per the "all data through Rust" architectural rule) — Dart sees the boolean / unavailability-reason answer over FRB but never the raw protocol bytes.

**Atomic writes — biometric vault.** [`lfs_core::security::biometric_key_vault::linux::store_from_secret`](../rust/crates/lfs_core/src/security/biometric_key_vault.rs) writes the TPM-sealed `biometric_vault.tpm` through `lfs_core::path::write_bytes_atomic` — matching the same invariant the T2 hardware vault already enforces (`hardware_vault.bin`, `hardware_vault_salt.bin`). A torn write would leave `isStored()` returning true against a truncated blob; next launch the unseal returns garbage, and `_tryBiometricCommit` silently falls back to the password dialog with no "vault broken" hint, forcing the user to type the PIN on every launch even though they enabled biometric specifically to avoid that. Regression guard: `lfs_core::security::biometric_key_vault::tests::*`.

**TPM auth value never crosses argv.** On every `tpm2 create -p …` / `tpm2 unseal -p …` call, the Rust seal/unseal pipeline ([`lfs_core::platform::linux::tpm`](../rust/crates/lfs_core/src/platform/linux/tpm.rs), called directly from FRB) writes the HMAC auth value to a sibling file inside the per-call temp directory and passes `-p file:<path>` to the CLI. The earlier `-p hex:<hex>` form embedded the exact bytes an attacker needs to unseal the blob in the process command line; `/proc/<pid>/cmdline` is readable cross-UID on distros that default to `hidepid=0`, so the leak bypassed every cooldown except the TPM's own lockout. The temp file lives under a per-call workdir that the Rust pipeline zero-overwrites and unlinks on every exit path, so the auth file is self-cleaning. The tpm2-tools dependency is an optional Linux install (the user runs the README per-distro snippet); the threat-model invariant applies regardless of whether the install is bundled.

**Linux — TPM2 seal layer (`tpm2-tools` default; native `tss-esapi` opt-in).** When `/dev/tpmrm0` is present and the optional `tpm2-tools` package is installed, the biometric vault stores the DB key via a TPM-sealed blob instead of libsecret. The seal flow runs entirely Rust-side under [`lfs_core::security::biometric_key_vault::linux`](../rust/crates/lfs_core/src/security/biometric_key_vault.rs): `lfs_core::platform::linux::fprintd::get_enrolment_hash()` returns the SHA-256 of the sorted enrolled-finger list; that digest is handed to `lfs_core::platform::linux::tpm::seal` as the auth value, which dispatches to one of two backends. The default backend (`TpmBackend::Subprocess`, verified-working in the field) shells out to `tpm2 createprimary` + `tpm2 create -p file:<path>`. The opt-in backend (`TpmBackend::Native`, gated on `LFS_TPM_BACKEND=native` env var) talks to `/dev/tpmrm0` directly through the [`tss-esapi`](https://crates.io/crates/tss-esapi) crate — same `Tss2_MU_TPM2B_*` marshalling as `tpm2-tools`, so envelopes round-trip between backends; primary template (RSA 2048, SHA-256, AES-128-CFB, restricted decrypt) mirrors `tpm2 createprimary -C o`'s default field-for-field. The resulting `{pub, priv}` pair rides inside the shared TCG ASN.1 PEM envelope ([`linux::tpm_tcg_pem`](../rust/crates/lfs_os_security/src/linux/tpm_tcg_pem.rs), `id-loadablekey` arm of `draft-bottomley-tpm2-keys-asn1`) under an `LFHV[magic|version|platform_id_linux]` header and is written to `biometric_vault.tpm` under the app-support dir. Unseal runs the mirror sequence (`createprimary` + `load` + `unseal`) against a freshly probed enrolment hash; any change to the biometric enrolment flips the digest, the unseal fails, and the user is back on master password — the Linux equivalent of Apple's `biometryCurrentSet`. **Bytes never cross the FRB boundary** on either path: `store_from_secret(support_dir, secret_id)` reads the DB key out of the SecretStore Rust-internally, and `read_to_secret(support_dir, secret_id)` stages the unsealed bytes back into the SecretStore so the Dart caller sees a boolean only. The native backend stays opt-in until end-to-end verification on real TPM hardware confirms cross-backend envelope compatibility; the subprocess backend retires as soon as that lands. The backing-level label on Linux flips from `software` to `hardware` as soon as the TPM probe succeeds.

**Linux — biometric-overlay for the Hardware tier.** [`lfs_core::security::hardware_tier_vault::linux::store_biometric_password`](../rust/crates/lfs_core/src/security/hardware_tier_vault.rs) seals the user's typed master password under a *second* TPM2 envelope at `hardware_vault_password_overlay_linux.bin`, keyed by the fprintd enrolment hash (same SHA-256-of-sorted-finger-list shape the biometric DB-key vault uses). The overlay is intentionally separate from the primary `hardware_vault.bin` so re-enrolling a fingerprint invalidates only the overlay — the primary unseals fine under the typed password and the user loses the shortcut, not their data. The envelope rides under the common `LFHV[magic+version+platform_id=4]` header; the body is a single length-prefixed sealed frame. Wiring matches Apple / Windows verb-for-verb at the FRB layer (`store_biometric_password` / `read_biometric_password` / `clear_biometric_password` / `is_biometric_password_stored` dispatch through a `cfg(target_os = "linux")` arm in [`lfs_frb::api::hardware_tier_vault`](../rust/crates/lfs_frb/src/api/hardware_tier_vault.rs) to the Linux orchestrator; non-Linux targets stay on `lfs_os_security::hardware_tier_vault`). The orchestrator is async — fprintd's zbus walk runs on the tokio executor, the TPM2 seal/unseal half lives behind `tokio::task::spawn_blocking` so the FRB worker stays free during the subprocess shell-out. Capability-ladder rung 5 (optional OS dep with graceful degradation): a missing `fprintd` service surfaces as `LinuxVaultError::FprintdUnavailable` and the FRB shim maps it to `kind=vault_platform_unsupported` so the Settings toggle disables with the localised `biometricOverlayUnavailable` string and the README install snippet covers the install half (`fprintd` cannot be bundled — it is a system D-Bus service, not a library).

`BiometricAuth.backingLevel()` reports how the active biometric vault is protecting the cached DB key — `hardware` on iOS/macOS (Secure Enclave via `biometryCurrentSet`), `software` on Android/Windows/Linux until the respective hardware-binding path lands (dedicated Keystore + `BiometricPrompt.CryptoObject` on Android; CNG Platform Crypto Provider on Windows; TPM2 seal bound to the fprintd enrolment hash on Linux). The Settings biometric toggle concatenates the localised backing-level label into its subtitle when the toggle is on, so the user can tell hardware binding apart from software fallback without opening the source.

Platform requirements: iOS `Info.plist` carries `NSFaceIDUsageDescription`; Android manifest holds `USE_BIOMETRIC` + `USE_FINGERPRINT` and `MainActivity` extends `FlutterFragmentActivity` (required by `BiometricPrompt`'s Fragment host).

#### Android hardware-backed T2 vault (shipped; device-testing pass pending)

`lfs_os_security::android::hardware_vault` exposes the Keystore-backed T2 path via direct JNI to `java.security.KeyStore` provider `"AndroidKeyStore"` (no Kotlin shim, no MethodChannel). `MainActivity.configureFlutterEngine` calls `LfsJniBootstrap.register(this)` which captures the JavaVM + the FragmentActivity handle into process-wide `OnceLock`s that the JNI helpers read on every call; `build.gradle.kts` pins `androidx.biometric:1.1.0` + `androidx.fragment:1.6.2` so the `BiometricPrompt` + `FragmentActivity` surfaces resolve from JNI cleanly.

1. **Key creation.** `KeyGenParameterSpec.Builder` with `setUserAuthenticationRequired(true)` + `setInvalidatedByBiometricEnrollment(true)` — the key *must* be presented inside a `BiometricPrompt.CryptoObject` session, and any change to the device's enrolled biometrics atomically invalidates the key. This is the Android-native equivalent of `.biometryCurrentSet`.
2. **Storage backing.** `setIsStrongBoxBacked(true)` is attempted on SDK ≥ 28; the Keystore silently falls through to TEE-backed storage on devices that do not expose a StrongBox chip. `KeyInfo.securityLevel` (SDK ≥ 31) + `isInsideSecureHardware` (pre-31) drive the `backingLevel` return value — `hardware_strongbox` / `hardware_tee` / `software`.
3. **Wrapping.** The DB key is AES-GCM-encrypted under the CryptoObject key on `store`; the IV + ciphertext + PIN-HMAC frame lands in `hardware_vault_android.bin` under the app's files dir, 0600. Unlock presents `BiometricPrompt` → receives the authed `Cipher` → decrypts.

**Outstanding device-testing pass:** StrongBox presence varies by OEM (Pixel 3+, recent Samsung flagships), the `setInvalidatedByBiometricEnrollment` contract is subtly different on pre-Android-11 builds, and the `FragmentActivity` host dependency of `BiometricPrompt` interacts with Flutter's `MainActivity` in ways that the emulator matrix does not exercise. The unit-test suite covers the Dart dispatch contract (see `test/core/security/hardware_tier_vault_test.dart`); runtime validation on real hardware is the remaining acceptance item.

#### Windows CNG / NCrypt integration (Rust port; device-testing pass pending)

[`lfs_os_security::windows::hardware_vault`](../rust/crates/lfs_os_security/src/windows/hardware_vault.rs) drives Windows CNG via `NCrypt` on the Microsoft Platform Crypto Provider (TPM 2.0) directly from Rust through the `windows` crate. No MethodChannel — the FRB layer in [`lfs_os_security::hardware_tier_vault`](../rust/crates/lfs_os_security/src/hardware_tier_vault.rs) cfg-dispatches `target_os = "windows"` to this module, mirroring the Apple SE / Android Keystore branches. The Flutter runner CMakeLists.txt no longer links `Ncrypt.lib` / `Bcrypt.lib` / `WindowsApp.lib`; those surfaces are linked by the Rust crate instead.

Two keys live in the CNG key store, each serving a separate role:

1. **Primary DB-wrap key — `letsflutssh_hardware_vault_v1`.** Created once per install via `NCryptCreatePersistedKey` (`BCRYPT_RSA_ALGORITHM`, 2048-bit) on the Platform Crypto Provider — TPM-resident on a host with a TPM, software-resident on the Microsoft Software KSP fallback otherwise. **No `NCRYPT_UI_POLICY_PROPERTY` set**, so `NCryptEncrypt` / `NCryptDecrypt` run silently with zero user prompt. `store(dbKey, pinHmac)` RSA-OAEP (SHA-256) wraps the DB key and persists the len-prefixed `{wrapped, pinHmac}` envelope at `%APPDATA%\LetsFLUTssh\hardware_vault.bin` (matching the Apple wire format via `write_len_prefixed`). `read(pinHmac)` constant-time compares the stored PIN-HMAC first, then `NCryptDecrypt`s — wrong PIN fails without waking the TPM, matching the external-HMAC-gate pattern on Apple / Android.
2. **Biometric password overlay — `letsflutssh_hardware_vault_bio_v1`.** Same 2048-bit RSA-OAEP-SHA-256 shape, but finalised with `NCRYPT_UI_POLICY_PROPERTY + NCRYPT_UI_PROTECT_KEY_FLAG | NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG`. Every `NCryptDecrypt` on this key fires the Windows consent dialog — on a Hello-configured host that is the Hello prompt, which is exactly the biometric gate the overlay is asking for. The overlay seals the user's typed master password (not the DB key — the primary path already owns that) under a single length-prefixed frame at `hardware_vault_password_overlay_windows.bin`; no pin-hmac in the blob, the Hello prompt is the gate. The persistent-key name is **separate** from the primary so a Hello enrolment change (new fingerprint set / PIN reset) invalidates only the overlay; the primary vault keeps working under the typed password.

`backingLevel` returns `hardware_tpm` when the Platform Crypto Provider opens successfully, `software` when the Microsoft Software KSP is the fallback, and `unavailable` when neither is reachable.

**Rewrite history.** The first shipped revision used `KeyCredentialManager::RequestSignAsync` for the primary wrap (C++ MethodChannel plugin). That fired a Hello prompt on every `read` — fine when the user wanted biometric unlock, but a jarring double-prompt for the password-modifier flow, where the user has already typed their password (primary unlock) and Hello firing a second time on top served no threat-model purpose. The current Rust port keeps the silent-NCrypt-primary + Hello-gated-overlay split and dropped the C++ runner plugin entirely; the FRB boundary is now the only path between Dart and the Windows hw-vault.

**Outstanding device-testing pass:** the NCrypt calls are synchronous. Not observed blocking the UI thread in practice — they run inside the FRB worker pool and the Flutter UI isolate remains responsive — but the Hello prompt from the overlay key still takes focus while it is on-screen. A Windows 10 / 11 host *with* Hello + TPM has to exercise `backingLevel == hardware_tpm`, a host *with* TPM but *without* Hello needs to confirm the primary path still unlocks silently, a host without either has to verify the software-KSP fallback stores/reads without error and reports `backingLevel == software`, and a TPM-cleared recovery + a domain-managed-policy host both need to be exercised before the Rust port retires its `device-testing pass pending` flag. Cross-compile is verified clean under `x86_64-pc-windows-gnu`.

#### FIDO2 hardware-bound SSH keys (`sk-*`) — dispatcher + transports

The connect path supports OpenSSH `sk-ssh-ed25519@openssh.com` and `sk-ecdsa-sha2-nistp256@openssh.com` keys produced by `ssh-keygen -t ed25519-sk` / `-t ecdsa-sk`. Private key material lives on the authenticator (YubiKey, SoloKey, Titan, Feitian, Nitrokey, Trezor, system Hello / StrongBox passkey) and never reaches the app; every signature attempt routes through `lfs_core::fido2::get_assertion`, which dispatches to one of two transports:

* **Direct CTAP2 over USB HID** — `lfs_core::fido2::client` wraps the `ctap-hid-fido2` crate. Pure-Rust transport; needs udev rules on Linux and HID class access on Windows. Carries the full CTAP2 surface (hmac-secret, large-blob, credBlob — none of which SSH consumes today per PROTOCOL.u2f's "No extensions are yet defined for SSH use" — but available for forward compatibility).
* **OS-managed broker** — `lfs_os_security::fido2_broker` calls the host's system security-key dialog. The broker handles USB / NFC / BLE / the platform authenticator transparently and runs without admin grants or the Apple Developer Program entitlement. Per-OS implementations: Windows `webauthn.dll` (`WebAuthNAuthenticatorGetAssertion`, Win 10 1903+, `windows = "0.62"` `Win32_Networking_WindowsWebServices` feature surface, direct FFI no DLL-load dance), Apple `ASAuthorizationSecurityKeyPublicKeyCredentialProvider` (macOS 12+ / iOS 15.5+ via the C-ABI Swift glue at `macos/Runner/SecurityKeyBroker.swift` + `ios/Runner/SecurityKeyBroker.swift`, loaded through `libloading` against the running bundle so the audit perimeter "`lfs_os_security` is the single OS-FFI edge" holds), Android `androidx.credentials.CredentialManager` (`Fido2Broker.kt` Kotlin shim called via JNI; mirrors the `KeystoreSshSigner` shape).

`lfs_core::fido2::brokers::select_transport` is the single dispatch decision (cfg-free, pure-data — unit-tested in 9 cases covering each OS x toggle x availability combination):

| OS      | Default        | Fallback              | Settings override                          |
|---------|----------------|-----------------------|--------------------------------------------|
| Linux   | direct HID     | none                  | n/a (toggle has no effect)                 |
| Windows | broker         | direct HID            | "Prefer direct HID" forces direct          |
| macOS   | broker         | direct HID            | "Prefer direct HID" forces direct          |
| iOS     | broker         | none (broker-or-fail) | n/a (no HID stack)                         |
| Android | broker         | none (broker-or-fail) | n/a (no HID stack)                         |

The toggle is `AppConfig.behavior.fido2_prefer_direct_hid` (mirror of Rust `BehaviorConfig.fido2_prefer_direct_hid`), persisted in `config.json`, off by default. The Settings security section's "Hardware security keys" sub-section renders the toggle disabled on Linux / iOS / Android (single-path platforms) and writes through the FRB sync surface `fido2_set_prefer_direct_hid(bool)` which flips a process-wide `AtomicBool` (`brokers::PREFER_DIRECT_HID`). Cold-start orchestrator calls `fido2_apply_prefer_direct_hid_from_config(bool)` after the config has been loaded so the dispatcher's view matches the on-disk value on the first FIDO2 assertion.

**Why broker is the default on Windows / macOS.** No admin permission grant on Windows (the direct HID path needs HID class access), no Apple Developer Program entitlement on macOS (self-signed dev builds drop the `com.apple.developer.web-browser.public-key-credential` capability and the AS routes refuse — the dispatcher gracefully falls through to direct HID for those builds). The OS dialog also covers transports the direct path cannot reach: NFC (broker handles ISO7816 ASE wrapping internally), BLE (broker handles GATT pairing), and the platform authenticator (Hello / StrongBox passkey).

**hmac-secret subsetting.** Brokers expose less of the CTAP2 surface than direct HID — WebAuthn.dll exposes `hmac-secret` only on `MakeCredential` (not `GetAssertion`), ASAuthorization and Credential Manager never expose it. This is irrelevant for SSH `sk-*` userauth per PROTOCOL.u2f, but documented here so future features (e.g. cert-via-FIDO storing per-host secrets in hmac-secret) don't silently regress on broker paths.

```mermaid
sequenceDiagram
  participant Dart as Key manager (Dart)
  participant Frb as lfs_frb
  participant Core as lfs_core::fido2
  participant Dev as HID FIDO2 device
  Dart->>Frb: keys_parse_sk_private_key(pem)
  Frb->>Core: parse_sk_private_key
  Core-->>Dart: credential_id + application + UV flag
  Dart->>Frb: ssh_connect_pubkey_sk(public, credential_id, application, pin?)
  Frb->>Core: Session::connect_pubkey_sk → FidoSigner
  Core->>Dev: CTAP2 get_assertion(rp_id, clientDataHash, credential_ids[], pin)
  Dev-->>Core: assertion (signature || authenticator_data)
  Core-->>Frb: SSH wire signature (sk-* trailer + length-prefixed string)
  Frb-->>Dart: SshSession (live)
```

Persistence: `db::ssh_keys` carries three FIDO2 columns (`credential_id BLOB`, `application_string TEXT`, `has_user_verification INTEGER`). Software keys leave the columns NULL / 0; `sk-*` rows populate all three at import. The row's `key_type` short tag is `sk-ed25519` or `sk-ecdsa-p256`; the connect dispatch maps these back to `ssh_key::Algorithm::SkEd25519` / `SkEcdsaSha2NistP256` through `ssh::sk::algorithm_from_key_type`.

Wire format: the `FidoSigner` impl of russh's `Signer` (publicly re-exported at the crate root in `russh = "0.59"`, see `russh/src/lib_inner.rs`) SHA-256-hashes the SSH userauth signature input, asks the device for an assertion against `(rp_id=application, clientDataHash)`, then composes the OpenSSH `sk-*` signature trailer — `64-byte raw Ed25519 sig || u8 flags || u32 counter` for sk-ed25519, `string mpint r || string mpint s || u8 flags || u32 counter` for sk-ecdsa-p256 — and appends `string(algo_name) || string(sk_signature)` as a single length-prefixed SSH string to the buffer russh handed in. The signer impl lives at `lfs_core::ssh::sk_signer::FidoSigner`; the shared byte-layout helpers (mpint encoding, ECDSA DER → SSH mpint, public-key blob construction) live at `lfs_core::ssh::wire` so subsequent hardware-bound `Signer` impls (PKCS#11, TPM 2.0, Apple Secure Enclave, Windows NCrypt, Android Hardware Keystore) reuse them — see [Hardware-bound SSH signer wire helpers](#hardware-bound-ssh-signer-wire-helpers) below.

Capability ladder. The runtime probe `fido2::is_available()` returns true when at least one transport is reachable on the host — the dispatcher consults `brokers::current_transport()` which probes both the OS broker (`webauthn.dll` / ASAuthorization / Credential Manager) and the direct HID stack. Desktop (Linux + Windows + macOS) keeps the key manager's "Import hardware key (sk-*)" row enabled whenever either path works; the per-OS label in Settings ("Windows Hello / security key" / "System security key dialog" / etc., from `fido2BrokerWindowsLabel` / `fido2BrokerMacosLabel` / `fido2BrokerIosLabel` / `fido2BrokerAndroidLabel`) names which one the dispatcher will pick. iOS / Android route exclusively through the broker — Credential Manager covers USB-host / NFC / BLE / StrongBox passkey transparently, so the direct USB-host JNI bridge originally tracked for Android is dropped. CoreNFC ISO7816 + CoreBluetooth CTAP2 standalone drivers on iOS are likewise unneeded — ASAuthorization handles iOS NFC at the OS layer.

Linux udev. `linux/packaging/70-letsflutssh-fido.rules` carries `uaccess` / `plugdev` rules for the maintained vendor list (Yubico 1050, STMicroelectronics 0483, Feitian 096e, Trezor 1209/53c1, Nitrokey 20a0, Google Titan 18d1, OpenMoko 1d50). Packaging installs it into `/etc/udev/rules.d/`; the bundle ships a copy under `data/udev/` for distro maintainers who want to inspect the source. Without the rules `/dev/hidraw*` defaults to `root:root 0600` and the direct CTAP2 path cannot open the device.

Error envelope. `Error::Fido2(String)` carves the FIDO path out of the generic `Io` / `Platform` buckets; the FRB envelope's `kind::FIDO2` discriminator lets the Dart UI route `wrong pin:` (the matcher in `client::map_upstream_err` prepends this discriminator) to the PIN re-prompt branch versus `timeout:` ("did not respond" toast) versus the catch-all "hardware key error" toast.

**Status:** today's build ships the Linux + Windows direct CTAP2 path end-to-end from the workspace UI down to the device. The connect path is:

1. The user opens a session whose `keyId` resolves to a manager row carrying `credential_id` / `application_string` (set at `sk-*` import by `keys_import_openssh`).
2. `ConnectionsNotifier._authFromConfig` queries `dbSshKeysGet(keyId)` and — when the row has the user-verification bit set — surfaces `HardwareKeyPromptDialog` through the `navigatorKey` global to collect the PIN. Touch-only rows skip the prompt.
3. The Dart caller invokes `connectionPrepareAuth` with the typed PIN in the new `DbPrepareAuthInput.pin` field. `auth_compose::prepare_auth` detects the sk-* row (manager-key path sub-branch (a)), stages the PIN as a transient `key.pin.<id>` SecretStore entry when present, then checks whether a certificate is paired to the row through `ssh_key_certificates::stage_secret_into_store`. With a cert paired it returns `PreparedAuthRef::PubkeySkCert { public_openssh, credential_id, application, has_user_verification, cert_secret_id, pin_secret_id }`; without a cert it returns the bare `PreparedAuthRef::PubkeySk { ... }`. The cert-paired sub-branch (b) and plain-pubkey sub-branch (c) run only when the row is software-only.
4. The Dart `_authFromConfig` switch builds `SshAuthPubkeySkRef` (bare) or `SshAuthPubkeySkCertRef` (cert-paired); the `busAuthRef` mapper emits the matching `BusConnectAuthRef::PubkeySk` / `BusConnectAuthRef::PubkeySkCert`; `connectionConnect` ships it to the Rust actor.
5. The driver dispatcher in `lfs_core::connection::connect_async` routes `ConnectAuthRef::PubkeySk` to `Session::connect_pubkey_sk_owned` and `ConnectAuthRef::PubkeySkCert` to `Session::connect_pubkey_sk_cert_owned`. Both `_owned` twins read the PIN out of the SecretStore inside the future; the cert-bearing variant additionally fetches the cert blob under `key.cert.<key_id>` and drives russh's `Handle::authenticate_certificate_with<S: Signer>` instead of the bare-pubkey twin. The same `FidoSigner` from sk-* userauth signs every assertion round trip — the cert-form algorithm names (`sk-ssh-ed25519-cert-v01@openssh.com` / `sk-ecdsa-sha2-nistp256-cert-v01@openssh.com`) reuse the bare-sk wire-format encoder.
6. `connect_async` rejects `(PubkeySk, Some(parent))` and `(PubkeySkCert, Some(parent))` — and every other hardware-signer variant paired with a bastion — with a typed `Error::Auth` whose human-readable label names the signer that lacks ProxyJump support today. The dispatcher in `lfs_core::connection::run_auth` is a single exhaustive match on `ConnectAuthRef`; every hardware-bound `Some(_)` arm routes through one helper, [`hardware_over_proxyjump_unsupported`](../rust/crates/lfs_core/src/connection/mod.rs), whose `HardwareSigner` enum is itself exhaustively matched against to mint the label. Adding a new hardware variant to `ConnectAuthRef` without a matching `HardwareSigner` arm fails to compile, which is the compile-time gate that catches a new hardware backend added without an explicit ProxyJump decision. The Rust-side proxy variants `Session::connect_pubkey_sk_via_proxy` and `Session::connect_pubkey_sk_cert_via_proxy` are wired but unreachable through FRB until the FIDO2-over-ProxyJump composition lands.

The transient PIN id is added to `transient_secret_ids` so it drops out of the SecretStore the moment the connect attempt settles (Connected or Disconnected), mirroring the typed-passphrase eviction shape on the cert-paired path. The cert blob's `key.cert.<key_id>` entry follows the same lifecycle as the software cert path — staged on `prepare_auth`, evicted on connect-settle.

###### Certificate authentication via sk-*

russh 0.59 ships `Handle::authenticate_certificate_with<U: Into<String>, S: auth::Signer>` — the cert-bearing twin of the bare-pubkey `authenticate_publickey_with`. The composer with [`FidoSigner`](../rust/crates/lfs_core/src/ssh/sk_signer.rs) is a free combination: the signer already produces SSH wire-format signatures over arbitrary userauth payloads, so the cert-form variant only changes the SSH message that wraps the signature — algorithm names switch to `*-cert-v01@openssh.com`, and russh handles the cert encoding internally. No additional CTAP2 round trips beyond what the bare-sk path already pays. See [cert lifecycle in §6.2](#62-ssh-certificates) for how OpenSSH certificates pair to keys + the `ssh_key_certificates` row that backs the join.

Selection precedence in `auth_compose::prepare_auth` matches the software path: cert beats bare-pubkey because the cert is the strictly stronger credential (CA-signed). Without that precedence rule, every short-lived cert rotation on the server would force the user to re-authenticate with the bare key instead of letting the CA carry the validity claim.

Forward-compat note. The CTAP2 `hmac-secret` extension is direct-HID-only on broker platforms (Windows WebAuthn.dll exposes it on `MakeCredential` but not `GetAssertion`; ASAuthorization and Credential Manager never expose it). The SSH cert wire format does not define `hmac-secret` usage, so cert-via-FIDO inherits the same broker-friendly profile as the bare-sk path. A future feature that wanted hmac-secret-derived per-host secrets (e.g. a sealed wrap key tied to the cert) would gate to direct HID — irrelevant for today's cert-via-FIDO but documented so a later arc doesn't silently regress on broker platforms.

##### Hardware-bound SSH signer wire helpers

Every hardware-bound signer (FIDO2 today, PKCS#11 / TPM 2.0 / Apple Secure Enclave / Windows NCrypt / Android Hardware Keystore as they land) speaks the byte layout RFC 4253 §6.6 prescribes for the userauth signature blob and the public-key blob. The shared primitives live in `rust/crates/lfs_core/src/ssh/wire.rs`:

| Function | Purpose | Backends |
|---|---|---|
| `ecdsa_der_to_ssh_mpint(&[u8])` | Parse ASN.1 DER `SEQUENCE { INTEGER r, INTEGER s }` and emit `mpint(r) \|\| mpint(s)` | CTAP2 ECDSA, Apple Secure Enclave, anything calling OpenSSL `ECDSA_sign` |
| `ecdsa_raw_concat_to_ssh_mpint(&[u8])` | Split fixed-width raw `r \|\| s` and emit two mpints | Windows NCrypt `NCryptSignHash`, Android Keystore `NONEwithECDSA` |
| `rsa_pkcs1_v15_to_ssh_blob(&[u8])` | Wrap raw RSA PKCS#1 v1.5 signature into SSH `string(sig)` | PKCS#11, NCrypt RSA |
| `ed25519_to_ssh_blob(&[u8])` | Wrap 64-byte Ed25519 signature into SSH `string(sig)` | Every Ed25519 backend |
| `encode_public_ecdsa_p256(&[u8; 65])` | `0x04 \|\| X \|\| Y` → `ssh-keygen`-shaped ECDSA-P256 public blob | Every ECDSA backend |
| `encode_public_ed25519(&[u8; 32])` | Raw key → `ssh-ed25519` public blob | Every Ed25519 backend |
| `encode_public_rsa(modulus, exponent)` | `(n, e)` → `ssh-rsa` public blob | Every RSA backend |
| `push_ssh_mpint(&mut Vec<u8>, magnitude)` | Append a length-prefixed signed integer with the SSH leading-zero discipline | Composing inner mpints inside the helpers above |
| `push_ssh_string(&mut Vec<u8>, payload)` | Append a length-prefixed SSH string | Composing inner strings inside the helpers above |

The DER parser accepts only the strict shape OpenSSH itself parses (definite length, no trailing bytes, single-component length fields up to four bytes — anything wider would be structurally malformed for an EC signature component); malformed input returns `Error::Auth(...)` rather than panicking. The mpint encoder strips one redundant leading 0x00 byte when dropping it would not flip the sign and re-adds a leading 0x00 when the high bit of the first byte is set, mirroring RFC 4251 §5. Round-trip tests + a fuzz-style sweep covering random byte slices live in `rust/crates/lfs_core/src/ssh/wire.rs::tests`.

#### PKCS#11 hardware tokens — smart cards, USB tokens, network HSMs

The connect path supports smart-card / hardware-token keys via the PKCS#11 (Cryptoki) standard so corporate users on JaCarta, Рутокен, eToken, OpenPGP card, YubiKey PIV applet, Estonian / Finnish / German eID cards, Thales Luna network HSMs, and AWS CloudHSM can authenticate without the private key ever crossing the FRB boundary. Private key material lives on the token; every signature attempt routes through `lfs_os_security::pkcs11::sign::sign_with_pkcs11`, which talks Cryptoki over `dlopen`'d vendor `.so` / `.dylib` / `.dll`.

```mermaid
sequenceDiagram
  participant Dart as Key manager (Dart)
  participant Frb as lfs_frb
  participant Sec as lfs_os_security::pkcs11
  participant Tok as Smart card / HSM
  Dart->>Frb: pkcs11_scan_well_known_paths()
  Frb->>Sec: discovery::scan_well_known_paths
  Sec-->>Dart: vendor candidates (only existing paths)
  Dart->>Frb: pkcs11_list_tokens(path)
  Frb->>Sec: module::load + get_slots_with_token
  Sec->>Tok: C_Initialize + C_GetSlotList
  Tok-->>Sec: token info per slot
  Sec-->>Dart: DbPkcs11TokenInfo[]
  Dart->>Frb: pkcs11_list_keys(slot, pin_id?)
  Frb->>Sec: session::for_slot + login_if_needed + find_objects
  Sec->>Tok: C_Login (PIN) + C_FindObjects (CKO_PUBLIC_KEY)
  Tok-->>Sec: object handles + CKA_LABEL + CKA_EC_POINT / Modulus
  Sec-->>Dart: signable keys + ssh-wire public blobs
  Dart->>Frb: pkcs11_import_key(args)
  Frb-->>Dart: DbSshKeyId
  Note over Dart,Tok: on connect: russh Signer drives C_Sign per challenge
```

Persistence: `db::ssh_keys` carries an explicit `backend` discriminator (one of `software` / `fido2` / `pkcs11` / `tpm` / `enclave` / `hello` / `keystore`), plus the PKCS#11 ingredient block (`pkcs11_uri` for the RFC 7512 URI captured at import, `pkcs11_module_path` for the resolved on-disk library path, `pkcs11_token_serial` to confirm the same physical token, `pkcs11_object_id` for the opaque `CKA_ID` of the private-key object, `pkcs11_object_label` for the human-readable name), the Apple Secure Enclave `enclave_tag` blob (the opaque `kSecAttrApplicationTag` bytes the Keychain matches on; only populated for `backend = 'enclave'` rows), and the Windows Hello `hello_credential_name` string (the CNG persistent-key name the `NCryptOpenKey` lookup re-binds to; only populated for `backend = 'hello'` rows). The agent / connect dispatcher reads `backend` to route to the right `Signer` impl rather than inferring from `credential_id IS NOT NULL`, so a hardware-bound row never falls through to a software arm.

Mechanism → SSH algorithm table:

| PKCS#11 | SSH | Notes |
|---|---|---|
| `CKK_RSA` + `CKM_RSA_PKCS` | `rsa-sha2-256` / `rsa-sha2-512` | Pre-hash + PKCS#1 v1.5 DigestInfo built client-side; raw `CKM_RSA_PKCS` mechanism. Old `ssh-rsa` (SHA-1) is server-deprecated and refused. |
| `CKK_EC` (`prime256v1` / `secp384r1` / `secp521r1`) + `CKM_ECDSA` | `ecdsa-sha2-nistp{256,384,521}` | `C_Sign` returns raw `r ‖ s` left-padded; SSH wants `mpint(r) ‖ mpint(s)` so the sign helper splits + reflows. |
| `CKK_EC_EDWARDS` + `CKM_EDDSA` (Pure scheme) | `ssh-ed25519` | PKCS#11 v3.0+. YubiKey PIV does NOT expose Ed25519 over PKCS#11 today. |
| `CKK_GOSTR3410` | (none — SSH has no GOST suite) | Listed in the picker but disabled with the localized "GOST cannot be used with SSH" reason. |

Well-known module-path discovery (table in `pkcs11::discovery::well_known_table`):

| Vendor | Linux | Windows | macOS |
|---|---|---|---|
| OpenSC (default multi-vendor) | `/usr/lib/{x86_64-linux-gnu,64,}/opensc-pkcs11.so` | `C:\Program Files\OpenSC Project\OpenSC\pkcs11\opensc-pkcs11.dll` | `/Library/OpenSC/lib/opensc-pkcs11.so`, brew prefix |
| YubiKey PIV (`ykcs11`) | `/usr/lib/x86_64-linux-gnu/libykcs11.so`, `/usr/local/lib/libykcs11.so` | `C:\Program Files\Yubico\Yubico PIV Tool\bin\libykcs11.dll` | `/usr/local/lib/libykcs11.dylib`, brew prefix |
| JaCarta | `/usr/lib{,64}/libjcPKCS11-2.so` | `C:\Windows\System32\jcPKCS11-2.dll` | — |
| Рутокен (Rutoken ECP / ECP2 / Lite) | `/usr/lib{,64}/librtpkcs11ecp.so` | `C:\Windows\System32\rtPKCS11ECP.dll` | `/Library/Frameworks/rtPKCS11.framework/rtpkcs11ecp.dylib` |
| eToken / SafeNet | `/usr/lib/libeToken.so`, `/usr/lib64/libeTPkcs11.so` | `C:\Windows\System32\eTPKCS11.dll` | `/usr/local/lib/libeTPkcs11.dylib` |
| Thales Luna network HSM | `/usr/safenet/lunaclient/lib/libCryptoki2_64.so` | `C:\Program Files\SafeNet\LunaClient\cryptoki.dll` | — |
| AWS CloudHSM | `/opt/cloudhsm/lib/libcloudhsm_pkcs11.so` | — | — |

`discovery::scan_well_known_paths` returns only candidates whose file exists on disk; probing the library via `Pkcs11::new + initialize` is deferred to the picker (`module::load`) so the listing pass stays cheap.

Wire format: the `Pkcs11Signer` impl of russh's `Signer` (lives at `lfs_core::ssh::pkcs11_signer`) routes every userauth challenge through `tokio::task::spawn_blocking` into `lfs_os_security::pkcs11::sign::sign_with_pkcs11`. The blocking task resolves the slot by matching `token_serial` against the present-slot list (so a re-plug under a different slot transparently shifts; an unplugged token surfaces as `Error::Pkcs11("unplugged: ...")`), opens the session via the per-`(module, slot)` pool in `pkcs11::session`, runs `C_Login` (or skips it for `CKF_PROTECTED_AUTHENTICATION_PATH` / no-login tokens), reaches for the matching `CKO_PRIVATE_KEY` by `CKA_ID`, fires `C_Sign`, and composes `string(algorithm) || string(sig_blob)` per the SSH userauth contract before handing the buffer back. The PIN crosses FRB as a transient `SecretStore` entry under `pkcs11.pin.<key_id>` (or `key.pin.<key_id>` on the connect path) — never as a plaintext field in the FRB envelope.

Session lifecycle: one session per `(module, slot)` reused across signatures via the global `Mutex<HashMap<...>>` pool in `pkcs11::session`. The 5-minute idle threshold (`IDLE_TIMEOUT`) drops the cryptoki session on the next `with_session` call when the gap exceeds it; the next signature re-opens + re-logs-in. The PIN cache is per-call — the `Zeroizing<String>` inside the Signer drops at the end of the connect attempt, the SecretStore transient evicts when the connect terminal state lands (Connected / Disconnected). PKCS#11 sessions hold an implicit login bound to the logged-in `cryptoki::Session` handle, so re-opening on the next sign attempt forces a fresh prompt — matching the security-first posture even on long-lived workspaces.

PIN counter awareness: the `pkcs11_list_tokens` FRB shim surfaces `user_pin_count_low` and `user_pin_final_try` flags (mapped off `TokenInfo::user_pin_count_low()` / `user_pin_final_try()`); the UI raises the "stop trying" warning loudly before the user fires one more attempt. The token's PIN-attempt counter is hardware-wide — there is no per-app retry budget. `user_pin_locked` reports the terminal state; recovery requires the SO-PIN / PUK and is out of scope (vendor tooling owns the unblock flow).

Import wizard (`lib/widgets/ssh_keys/pkcs11_import_dialog.dart` + `pkcs11_import_dialog_logic.dart`) drives the five-step ladder the key-manager toolbar's "Add smart-card / token key" action surfaces. The wizard composes `AppDialog` + `AppDialogHeader` / `AppDialogFooter` + `AppButton` per the reuse rule and pops a `Pkcs11ImportResult` on success.

```mermaid
stateDiagram-v2
    [*] --> module: open dialog
    module --> token: probe loadModule(path), listTokens(path)
    token --> pin: loginRequired && !protectedAuthPath
    token --> key: protectedAuthPath || !loginRequired
    pin --> key: stagePin → listKeys
    key --> save: select signable row
    save --> [*]: importKey → row id
    save --> key: Back
    pin --> token: Back
    key --> pin: Back (no pin pad)
    key --> token: Back (pin pad)
    token --> module: Back
```

Step semantics:

1. **Module pick** — `pkcs11ScanWellKnownPaths` populates the candidate list with a per-row colored status dot (green = `loadModule + listTokens` succeeded with at least one slot-with-token, amber = module loaded but no token, red = `loadModule` threw). "Custom..." opens the native file picker so users on vendor `.so` paths outside the well-known table can still import. The probe runs lazily on row selection; the initial list-build is on-disk-existence only so the scan stays cheap.
2. **Token pick** — `pkcs11ListTokens` populates the candidate list. Each row carries `tokenLabel`, `serial`, manufacturer, plus the conditional "PIN pad on device" hint (when `CKF_PROTECTED_AUTHENTICATION_PATH` is set) and the orange "1 try left" / red "PIN locked" warnings.
3. **PIN prompt** — reuses `HardwareKeyPromptDialog` (the same surface FIDO2 uses) so the visual contract for hardware-key affordances stays consistent across backends. Skipped entirely for `protectedAuthPath` tokens (the reader's keypad answers) and for `!loginRequired` tokens (public-object enumeration suffices for the listing). The collected PIN crosses FRB as a transient SecretStore entry under `pkcs11.pin.wizard.<timestamp>`; the wizard's `dispose` drops the entry unconditionally so a swallowed-exception path can never leave it pinned.
4. **Key picker** — `pkcs11ListKeys` returns every signable `CKO_PRIVATE_KEY` plus the matching public-key blob. The Dart side disables rows whose `disabledReason` is non-empty (GOST today) and renders the algorithm + curve detail via `pkcs11AlgoDetail`.
5. **Save** — composes the RFC 7512 `pkcs11:` URI Dart-side from the picked token + object metadata (pct-encoding `id` per `pk11-attr-chars`), calls `pkcs11ImportKey`, and pops `Pkcs11ImportResult(keyId, label)`.

The key-manager row badge for `backend = 'pkcs11'` rows is the `Pkcs11Badge` widget at the bottom of the same file. Visual contract mirrors the `_HardwareBadge` pill in `key_manager_dialog.dart` so the row tail reads consistently when PKCS#11 + FIDO2 + certificate badges co-exist. A tap on the badge drops an `AppDialog` info popover with the module path, token serial, and object label captured at import — surfaces the fields the user might need to debug a re-plug failure ("does this row still point at my actual physical token?") without forcing them to inspect the DB.

The wizard backend is abstracted behind a `Pkcs11Backend` interface so widget tests can drive every step without booting FRB; the production `Pkcs11FrbBackend` is the single FRB-call site. The same DI shape will land for the T-4..T-8 sibling backends so each per-backend wizard can be tested in isolation.

Capability ladder rendering:

| Platform | Rung | UI label |
|---|---|---|
| Linux | 3 native impl | "PKCS#11 (smart card)" enabled when at least one candidate validates. Reader access requires `pcscd` + user in the `scard` / `pcscd` group. |
| Windows | 3 native impl | Enabled when at least one vendor DLL present. Vendor installers register the DLL under `C:\Windows\System32\` or a Program Files subdir; reboots not required. |
| macOS | 3 native impl | Enabled. Hardened-runtime / Library Validation may block unsigned vendor `.dylib` — the README documents the Privacy & Security accept step. |
| Android | 4 honestly hide | No `.so` ABI compatible. NFC smart-card stack is a separate driver; out of scope today. |
| iOS | 4 honestly hide | Sandbox forbids `dlopen` of arbitrary `.dylib`. The picker row renders disabled with the `pkcs11HwUnavailableMobile` reason. |

Error envelope: `Error::Pkcs11(String)` carves the PKCS#11 path out of the generic `Io` / `Platform` buckets; the FRB envelope's `kind::PKCS11` discriminator lets the Dart UI route `wrong pin:` to the PIN re-prompt branch, `pin locked:` to the "unblock with PUK" halt, `unplugged:` to the replug toast, and the catch-all to the smart-card error toast. Display strings carry a stable leading discriminator (`wrong pin: <N> tries remaining`, `pin locked: token user PIN is locked`, `unplugged: matching token not present in any reader`) so the Dart matcher can string-match the prefix without re-parsing the full envelope.

#### Apple Secure Enclave SSH keys — on-chip ECDSA P-256

`lfs_os_security::apple_se_ssh` generates / signs / lists / deletes SSH keys whose private half lives on the Secure Enclave coprocessor — same silicon Apple uses to back Touch ID / Face ID for system unlock. The chip refuses to export the private bytes; every signing operation routes through `SecKeyCreateSignature`, and the OS surfaces a biometric / passcode prompt at the FFI boundary per the access-control flags chosen at create time.

**Algorithm exclusivity.** ECDSA P-256 only. The SE silicon implements no other curve and no asymmetric primitive beyond ECDSA + ECIES — `SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave` fails for every other `kSecAttrKeyType`. SSH wire-side this surfaces as `ecdsa-sha2-nistp256` exclusively; `ssh_keys.key_type` always reads back the same value, and the connect dispatcher refuses any other key_type on `backend = 'enclave'` rows.

```mermaid
flowchart LR
    UI[EnclaveSshDialog]
    UI --> FRB[enclave_ssh_generate FRB]
    FRB --> SECREATE[SecKeyCreateRandomKey<br/>kSecAttrTokenIDSecureEnclave]
    SECREATE -- ECDSA P-256 keypair --> CHIP[(Secure Enclave coprocessor)]
    CHIP --> KEYREF[SecKeyRef + applicationTag]
    KEYREF --> PUBEXTRACT[SecKeyCopyExternalRepresentation<br/>65-byte uncompressed point]
    PUBEXTRACT --> WIRE[encode_public_ecdsa_p256<br/>SSH authorized_keys]
    WIRE --> DB[ssh_keys row backend='enclave']
    DB --> SIGN[Connect / agent dispatch]
    SIGN --> SECSIGN[SecKeyCreateSignature<br/>kSecKeyAlgorithmECDSASignatureMessageX962SHA256]
    SECSIGN -- DER r,s --> WIREHELP[ecdsa_der_to_ssh_mpint]
    WIREHELP --> SSH[ssh-agent / userauth signature]
```

**Module layout.** Files live under `rust/crates/lfs_os_security/src/apple_se_ssh.rs` (single shared module, cfg-gated to `target_os = "macos" | "ios"`). The Signer adapter lives at `rust/crates/lfs_core/src/ssh/enclave_signer.rs` (mirrors the PKCS#11 / FIDO2 shape — `russh::Signer` impl wrapping the FFI surface). The FRB shim lives at `rust/crates/lfs_frb/src/api/enclave.rs`.

**Shared Dart wizard scaffold.** The Dart UI of all four hardware-key wizards — Enclave, Windows Hello, TPM, Android Keystore — is one mixin, `lib/widgets/ssh_keys/hardware_key_wizard.dart::HardwareKeyWizardMixin`. It owns the four-step `HardwareKeyStep` ladder (probe → configure → generate → complete), the label field, the probing / generating spinners, the `authorized_keys` completion panel + copy affordance, and the Cancel / Generate / Close action ladder — the half of each wizard that was identical four ways. Each concrete dialog (`EnclaveSshDialog`, `HelloSshDialog`, `TpmSshDialog`, `KeystoreSshDialog`) mixes it in and supplies only the backend-specific hooks: title, probe + its failure fallback, the configure-step body, the `canGenerate` gate, and the generate call. The row-tail pills likewise share one widget — `lib/widgets/ssh_keys/hardware_key_badge.dart::HardwareKeyBadge` (colour + icon + optional tap-to-reveal popover) — with `EnclaveBadge` / `HelloBadge` / `TpmBadge` / `KeystoreBadge` / `Pkcs11Badge` as thin per-backend callers that fill in the colour, icon, and captured-metadata lines. The FIDO2 sk-* row reuses the same pill with no popover.

**Access-control policy.** Two shapes selected per-key at creation, captured implicitly via the on-chip ACL — there is no DB column for the policy because the chip refuses to mutate the ACL after creation:

| `AuthPolicy` | `SecAccessControl` flag | Effect |
|---|---|---|
| `BiometryCurrentSet` | `kSecAccessControlBiometryCurrentSet` | Touch ID / Face ID gates every sign. Re-enrolment invalidates the key (chip biometric template snapshot changes). Strongest binding. |
| `UserPresence` | `kSecAccessControlUserPresence` | Accepts biometry OR the device passcode as fallback. Survives re-enrolment; a stolen passcode unlocks every key in this class. |

Both shapes pin to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so the key never syncs (iCloud Keychain stays out of the loop) and never persists past a passcode unset.

**Application tag.** Each key registers under a unique `kSecAttrApplicationTag` blob — `letsflutssh.ssh.<lowercase-hex-uuid>` — generated at creation time and persisted in `ssh_keys.enclave_tag` (BLOB NULL). The Keychain query at sign time matches on the tag; storing the tag in our own DB rather than letting Keychain enumerate by partial match keeps the mapping unambiguous when multiple keys co-exist on the same device.

**LAContext caching.** Mirrors Secretive's `PersistentAuthenticationHandler` pattern — the caller may cache a single `LAContext` per session and pass it via `kSecUseAuthenticationContext` on subsequent `SecItemCopyMatching` calls. The OS skips the biometric prompt while the context's `evaluatedPolicyDomainState` blob is still valid (a few minutes per Apple's docs; we mirror PKCS#11's 5-minute idle drop). For T-5 the caching surface is wired (`load_private_key` accepts `Option<&Retained<LAContext>>`) but the per-session reuse path lives at the FRB worker boundary (one `LAContext` per connect / agent dispatch); the in-process ssh-agent endpoint reuses it across SIGN_REQUEST bursts from the same external client.

**Public-key extraction.** `SecKeyCopyPublicKey` → `SecKeyCopyExternalRepresentation` returns the 65-byte uncompressed `0x04 || X(32) || Y(32)` point; `lfs_core::ssh::wire::encode_public_ecdsa_p256` wraps it into the SSH authorized_keys body (`string("ecdsa-sha2-nistp256") || string("nistp256") || string(point)`).

**Signing.** `SecKeyCreateSignature(privateKey, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, dataRef, &cferr)` — the OS performs SHA-256 internally, so we pass the raw userauth buffer. The returned bytes are DER `SEQUENCE { INTEGER r, INTEGER s }`; `lfs_core::ssh::wire::ecdsa_der_to_ssh_mpint` produces the two `mpint`s the SSH wire wants.

**Code-signing requirement.** Unsigned / ad-hoc bundles surface `errSecMissingEntitlement` (`-34018`) on the first `SecKeyCreateRandomKey` call. The wizard probe step classifies this separately so the UI can route the user at the documented remediation (`codesign -s - --identifier com.poddeo3.letsflutssh` for self-build users). With `app-sandbox = false` in `macos/Runner/Release.entitlements`, no `keychain-access-groups` entitlement is needed — the unsandboxed process accesses the user-default keychain directly. A future Developer ID + Hardened Runtime build flipping sandbox on will need the team-prefixed access group; the entitlements file carries the documented template.

**Capability ladder rendering.**

| Platform | Probe | Rung | UI |
|---|---|---|---|
| macOS code-signed + SE present | `Ok` | 3 native | "Secure Enclave" enabled |
| macOS unsigned / ad-hoc-unidentified | `Err(CodeSignRequired)` | 4 honestly hide | Wizard disabled with code-signing reason + USER_GUIDE link |
| iOS (always sandboxed + signed) | `Ok` | 3 native | "Secure Enclave" enabled |
| Linux / Windows / Android | n/a | 4 honestly hide | Key-manager toolbar action hidden — `isApplePlatform` gate at the call site |

**`.lfs` export semantics.** SE-bound keys' private half is non-exportable by chip design. Today's `.lfs` archive shape includes the row with `backend = 'enclave'` + the `enclave_tag` blob; the importing device's connect path checks the chip via `apple_se_ssh::list()` and surfaces "Missing on this device — re-generate" when the tag isn't registered. Cross-device portability is impossible; the docs surface the constraint at every UI surface that creates an SE-bound key.

**Error envelope.** `Error::Enclave(String)` carves the SE path out of the generic `Io` / `Platform` buckets; the FRB envelope's `kind::ENCLAVE` discriminator lets the Dart UI route `code-signing required` to the wizard probe-disabled state, `cancelled` to a "touch the sensor again" hint, `key not found` to the recovery dialog, and the catch-all to the generic SE error toast.

**Tests.** Unit tests in `rust/crates/lfs_os_security/src/apple_se_ssh.rs::tests` cover the application-tag mint shape, the unavailable-reason renderer, and the auth-policy flag mapping. Integration tests for the actual `SecKeyCreateRandomKey` round-trip are gated with `#[ignore]` so CI without an Apple machine can compile-check. The Signer adapter has its own tests under `rust/crates/lfs_core/src/ssh/enclave_signer.rs::tests` (algorithm-string contract, error round-trip). The Dart-side wizard tests live in `test/widgets/enclave_ssh_dialog_test.dart` — four cases covering probe-disabled state, code-sign reason rendering, happy-path generate, and the generate-failure recovery.

#### Windows Hello SSH keys — NCrypt / Microsoft Platform Crypto Provider

`lfs_os_security::windows::ncrypt_ssh` generates / signs / lists / deletes SSH keys whose private half lives in the Windows TPM (or, on TPM-less hosts, the Microsoft Platform Crypto Provider's software KSP fallback). The chip refuses to export the private bytes; every signing operation routes through `NCryptSignHash`, and Windows surfaces the Hello prompt — PIN, fingerprint, or face — at the FFI boundary per the `NCRYPT_UI_POLICY_PROPERTY` set at create time.

**Why NOT KeyCredentialManager.** `Windows.Security.Credentials.KeyCredentialManager.RequestSignAsync` produces **RSA-2048 PSS-SHA256**. SSH `rsa-sha2-256` / `rsa-sha2-512` (RFC 8332) requires **PKCS#1 v1.5** — PSS bytes cannot be re-encoded into v1.5; the padding scheme is different at the bit level. KCM is wire-incompatible with SSH userauth, full stop. The only Windows path that emits an SSH-compatible signature is NCrypt + PCP with `BCRYPT_PAD_PKCS1` (RSA) or no padding (ECDSA). The working reference is [`nCryptAgent`](https://github.com/unreality/nCryptAgent). This is the load-bearing reason the SSH-key path takes the opposite default from the T2 hardware vault: the vault deliberately omits UI policy (silent unwrap), the SSH path forces UI policy ON (Hello prompt at every sign — that's the security ceremony).

```mermaid
flowchart LR
    UI[HelloSshDialog]
    UI --> FRB[hello_ssh_generate FRB]
    FRB --> NCCREATE[NCryptCreatePersistedKey<br/>MS_PLATFORM_KEY_STORAGE_PROVIDER]
    NCCREATE --> UIPOL[NCryptSetProperty<br/>UI_PROTECT_KEY + UI_FORCE_HIGH_PROTECTION]
    UIPOL --> FINALIZE[NCryptFinalizeKey<br/>fires Hello configure prompt if needed]
    FINALIZE --> TPM[(TPM 2.0 or PCP software KSP)]
    TPM --> EXPORT[NCryptExportKey<br/>ECCPUBLIC / RSAPUBLIC]
    EXPORT --> WIRE[encode_public_ecdsa_p256/384/rsa]
    WIRE --> DB[ssh_keys row backend='hello'<br/>+ hello_credential_name]
    DB --> SIGN[Connect / agent dispatch]
    SIGN --> NCSIGN[NCryptSignHash<br/>Hello prompt PIN / fingerprint / face]
    NCSIGN -- ECDSA raw r,s --> ECDSAWIRE[ecdsa_raw_concat_to_ssh_mpint]
    NCSIGN -- RSA PKCS#1 v1.5 --> RSAWIRE[rsa_pkcs1_v15_to_ssh_blob]
    ECDSAWIRE --> SSH[ssh-agent / userauth signature]
    RSAWIRE --> SSH
```

**Module layout.** The native driver lives at `rust/crates/lfs_os_security/src/windows/ncrypt_ssh.rs` (cfg-gated to `target_os = "windows"`). The Signer adapter lives at `rust/crates/lfs_core/src/ssh/hello_signer.rs` (mirrors the PKCS#11 / FIDO2 / Enclave shape — `russh::Signer` impl wrapping the FFI surface). The FRB shim lives at `rust/crates/lfs_frb/src/api/hello.rs`. The driver crate stays free of `lfs_core` deps (audit invariant: `lfs_core` depends on `lfs_os_security`, never the reverse), so it returns raw bytes via `HelloSignature` / `HelloPublicKey` and the caller in `lfs_core` wraps them via the shared `lfs_core::ssh::wire` helpers.

**CNG provider + persistent key naming.** Every SSH-bound key is minted under `MS_PLATFORM_KEY_STORAGE_PROVIDER`. The provider prefers TPM 2.0 when present; on hosts without a TPM it transparently falls back to a software KSP. CNG name format: `letsflutssh-ssh-<user-hash>-<uuid>` — the user-hash prefix (first 4 bytes of `SHA-256(USERNAME)`) protects shared-workstation installs from collisions across user profiles. The name persists in `ssh_keys.hello_credential_name` (TEXT NULL); `NCryptOpenKey` re-binds to the same persistent key on every connect / agent dispatch.

**Algorithm matrix.**

| `SshKeyAlgo` | NCrypt algorithm | SSH wire-name | Output shape |
|---|---|---|---|
| `EcdsaP256` | `NCRYPT_ECDSA_P256_ALGORITHM` | `ecdsa-sha2-nistp256` | Fixed-width raw `r \|\| s`, 64 bytes |
| `EcdsaP384` | `NCRYPT_ECDSA_P384_ALGORITHM` | `ecdsa-sha2-nistp384` | Fixed-width raw `r \|\| s`, 96 bytes |
| `Rsa2048` | `NCRYPT_RSA_ALGORITHM` (length 2048) | `rsa-sha2-256` / `rsa-sha2-512` (PKCS#1 v1.5, NOT PSS) | 256-byte raw signature block |

P-384 is TPM-firmware-dependent — the create call surfaces `Error::P384NotSupported` when the host TPM refuses the algorithm (`NTE_NOT_SUPPORTED = 0x80090029`). The wizard exposes all three options; the FRB call routes the user at the localized "TPM firmware does not support P-384" reason when the create attempt fails.

**UI policy contract.** `NCRYPT_UI_POLICY` lands via `NCryptSetProperty` **before** `NCryptFinalizeKey`:

```c
NCRYPT_UI_POLICY {
    dwVersion = 1
    dwFlags   = NCRYPT_UI_PROTECT_KEY_FLAG | NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG
}
```

The flags fire the Hello prompt on every sign — every SSH userauth, every git operation, every `SIGN_REQUEST` from an external client through the in-process ssh-agent endpoint. The strings (`pszCreationTitle` / `pszFriendlyName` / `pszDescription`) stay null today; the OS picks up its default "Authenticate to allow this app to sign data" copy. Localising via Dart would require a round-trip on every sign — out of scope.

**Probe + tier classification.** `probe_availability` cycles a throw-away ECDSA P-256 key under a `letsflutssh-probe-<random>` name with UI policy ON, then deletes it. Inspects `NCRYPT_IMPL_TYPE_PROPERTY` on the probe key to distinguish hardware (TPM 2.0) from the software KSP fallback. Returns:

| `TpmTier` | `NCRYPT_IMPL_TYPE_PROPERTY` bit | UI label |
|---|---|---|
| `Hardware` | `NCRYPT_IMPL_HARDWARE_FLAG (0x1)` set | Plain "Windows Hello" |
| `SoftwareKsp` | flag clear | Plain "Windows Hello" + the localized "Software-gated" suffix |

`NTE_USER_CANCELLED` on the probe finalise step maps to `UnavailableReason::HelloNotConfigured` — the OS surfaces the configure-Hello dialog and the user dismissed it, so the wizard re-routes at the "Configure Windows Hello first" reason.

**Capability ladder rendering.**

| Platform | Probe | Rung | UI |
|---|---|---|---|
| Windows 10 1607+ with TPM + Hello | `Ok(TpmTier::Hardware)` | 3 native | "Windows Hello" enabled |
| Windows 10 1607+ without TPM + Hello | `Ok(TpmTier::SoftwareKsp)` | 6 weaker path with honest label | "Windows Hello (Software-gated)" — NEVER labelled as plain "Windows Hello" |
| Windows + Hello not configured | `Err(HelloNotConfigured)` | 4 honestly hide | Wizard disabled with "Configure Windows Hello first in Settings -> Sign-in options" |
| Windows < 10 1607 | `Err(ProviderUnavailable)` | 4 honestly hide | Wizard disabled with the provider-open HRESULT |
| Linux / macOS / Android / iOS | n/a | 4 honestly hide | Key-manager toolbar action hidden — `isWindowsPlatform` gate at the call site |

**Signing.** ECDSA path passes `padInfo = NULL`, `dwFlags = 0`; the call returns fixed-width raw `r || s` (64 bytes for P-256, 96 for P-384). RSA path passes `BCRYPT_PKCS1_PADDING_INFO { pszAlgId = BCRYPT_SHA256_ALGORITHM / BCRYPT_SHA512_ALGORITHM }` with `dwFlags = BCRYPT_PAD_PKCS1` (NEVER PSS — see "Why NOT KeyCredentialManager" above); returns the 256-byte raw signature block. The driver crate hands those bytes back as `HelloSignature::{EcdsaRaw, RsaPkcs1V15}`; the `lfs_core` caller wraps via `ssh::wire::ecdsa_raw_concat_to_ssh_mpint` / `ssh::wire::rsa_pkcs1_v15_to_ssh_blob` and prefixes the SSH userauth `signature` body (`string(algorithm) || string(sig_blob)`). `NTE_USER_CANCELLED` on the sign maps to `Error::Cancelled` so the UI can route a "cancelled" reason distinct from a hardware failure.

**Lifecycle.** Per-user keys persist under `%APPDATA%\Microsoft\Crypto\PCPKSP\<user-sid>\`. NCrypt manages this — no file path is exposed. `list()` walks `NCryptEnumKeys` with the `letsflutssh-ssh-` prefix filter and returns the matching handles (algorithm recovered from `NCryptKeyName.pszAlgid`). `delete()` is a plain `NCryptDeleteKey`. The Drop impls on `OwnedProvider` / `OwnedKey` release CNG handles on every path; `NCryptEnumKeys` allocates the key-name struct + strings, so each iteration frees via `NCryptFreeBuffer` to avoid leaking.

**Opposite-default from the T2 hardware vault.** The vault path (`windows::hardware_vault`) deliberately omits `NCRYPT_UI_POLICY_PROPERTY` — its primary RSA-OAEP wrap runs silently so the master-password unlock doesn't fire a redundant second Hello prompt. The SSH-key path takes the opposite default — every sign fires Hello. The two paths use distinct persistent-key names (`letsflutssh_hardware_vault_v1` vs `letsflutssh-ssh-<user-hash>-<uuid>`) so they coexist on the same install without confusion. Both pin `NCRYPT_EXPORT_POLICY_PROPERTY` to 0 implicitly: the TPM-backed PCP refuses export by hardware design; the software-KSP fallback defaults to exportable, but UI policy ON gates every operation including `NCryptExportKey` of the private half, so a parallel attacker process gets gated through the same Hello prompt the legitimate sign uses.

**`.lfs` export semantics.** Hello-bound keys' private half is non-exportable by chip / KSP design. Today's `.lfs` archive shape includes the row with `backend = 'hello'` + the `hello_credential_name` string; the importing device's connect path tries `NCryptOpenKey` and surfaces `Error::KeyNotFound` when the CNG name isn't registered. Cross-device portability is impossible; the wizard's "device-bound" warning surfaces the constraint at create time.

**Error envelope.** `Error::Hello(String)` carves the Hello path out of the generic `Io` / `Platform` buckets; the FRB envelope's `kind::HELLO` discriminator lets the Dart UI route `cancelled` to a "authenticate again" hint, `hello not configured` to the configure-first dialog, `TPM firmware does not support P-384` to the algorithm-fallback toast, and the catch-all to the generic Hello error toast.

**Tests.** Unit tests in `rust/crates/lfs_os_security/src/windows/ncrypt_ssh.rs::tests` cover the algorithm round-trip via `from_key_type` / `key_type_tag`, the credential-name mint shape, the `NCryptKeyName.pszAlgid` mapping, the unavailable-reason renderer, and the public-key blob parsers for ECDSA + RSA. The probe round-trip is `#[ignore]`-gated; a self-hosted Windows runner with `--ignored` exercises it. The Signer adapter has its own tests at `rust/crates/lfs_core/src/ssh/hello_signer.rs::tests` (algorithm round-trip, error mapping, russh-algorithm contract). The Dart-side wizard tests live in `test/widgets/hello_ssh_dialog_test.dart` — five cases covering probe-disabled state, hello-not-configured reason rendering, software-KSP honest-label warning, happy-path generate, and the generate-failure recovery.

#### TPM 2.0 SSH keys — Linux ESAPI + Windows PCP silent variant

`lfs_os_security::linux::tpm_ssh` generates / signs / lists / imports / deletes SSH keys whose private half lives inside a TPM 2.0 chip on Linux via direct `tss-esapi` (libtss2-esys) FFI; the Windows side reuses `lfs_os_security::windows::ncrypt_ssh` (the same NCrypt + Microsoft Platform Crypto Provider stack as Hello) but takes the **opposite UI-policy default** — `NCRYPT_UI_POLICY_PROPERTY` is left absent so signs run unattended. The chip refuses to export the private bytes in both paths; on Linux every signing operation routes through `TPM2_Sign` after a fresh `TPM2_Load`, and on Windows `NCryptSignHash` runs against a persisted CNG key without firing any OS-level prompt.

**Why two paths.** Linux has no `KeyCredentialManager`-equivalent — the TPM is reached directly via the TSS2 stack (`tpm2-tools` subprocess or `tss-esapi` library). Windows has a working CNG / PCP path that the Hello-gated wizard already uses; the TPM SSH wizard piggybacks on it but flips the UI-policy bit. Apple platforms route to the Secure Enclave wizard instead (no exposed TPM 2.0 interface on macOS / iOS). Android / iOS hide the toolbar entry.

```mermaid
flowchart LR
    UI[TpmSshDialog]
    UI -- Linux --> FRBL[tpm_ssh_generate FRB]
    UI -- Windows --> FRBW[tpm_ssh_generate FRB]
    FRBL --> ESAPI[tss-esapi::CreatePrimary + Create]
    ESAPI --> BLOB[TPM2B_PUBLIC + TPM2B_PRIVATE<br/>TCG draft-bottomley-tpm2-keys-asn1]
    BLOB --> DBL[ssh_keys row<br/>backend=tpm tpm_provider=tss-esapi<br/>tpm_blob populated]
    FRBW --> NCSILENT[NCryptCreatePersistedKey<br/>MS_PLATFORM_KEY_STORAGE_PROVIDER<br/>no UI_POLICY set]
    NCSILENT --> CNGKEY[(TPM 2.0 via PCP)]
    CNGKEY --> DBW[ssh_keys row<br/>backend=tpm tpm_provider=cng-pcp<br/>cng_key_name populated]
    DBL --> SIGNL[connect_pubkey_tpm_owned + TpmSigner]
    DBW --> SIGNW[connect_pubkey_tpm_owned + TpmSigner]
    SIGNL --> TPM2[TPM2_Sign<br/>raw r||s or PKCS#1 v1.5]
    SIGNW --> NCSIGN[NCryptSignHash<br/>unattended - no prompt]
    TPM2 --> WRAP[ssh::wire::ecdsa_raw_concat / rsa_pkcs1_v15]
    NCSIGN --> WRAP
    WRAP --> SSH[SSH userauth signature]
```

**Module layout.** Linux native driver: `rust/crates/lfs_os_security/src/linux/tpm_ssh.rs` (cfg-gated to `target_os = "linux"`; reuses `tpm_native::build_primary_template` so the parent handle is byte-identical to the T2 hardware-vault seal path). Windows silent path: extends `rust/crates/lfs_os_security/src/windows/ncrypt_ssh.rs` with `create_silent` / `sign_for_ssh_silent` / `list_silent` / `delete_silent` plus the `TpmSilentKeyHandle` type and the `letsflutssh-tpm-<user-hash>-<uuid>` CNG-name prefix that distinguishes silent TPM keys from Hello-gated ones when `NCryptEnumKeys` walks the provider. macOS stub: `rust/crates/lfs_os_security/src/macos/tpm_ssh.rs` (returns `TpmSshError::Unavailable`). Signer adapter: `rust/crates/lfs_core/src/ssh/tpm_signer.rs` (`russh::Signer` impl wrapping the FFI surface; carries the `TpmProvider` discriminator so the single signer routes both backends). FRB shim: `rust/crates/lfs_frb/src/api/tpm_ssh.rs`.

**Algorithm exclusivity.**

| `TpmSshAlgorithm` | Linux TPM template | Windows NCrypt algorithm | SSH wire-name | Output shape |
|---|---|---|---|---|
| `EcdsaP256` | `TPMI_ALG_ECDSA` over `TPMI_ECC_NIST_P256` | `NCRYPT_ECDSA_P256_ALGORITHM` | `ecdsa-sha2-nistp256` | Raw `r \|\| s`, 32+32 bytes |
| `Rsa2048` | `TPMI_ALG_RSASSA`, `RsaKeyBits::Rsa2048` | `NCRYPT_RSA_ALGORITHM` (length 2048) | `rsa-sha2-256` / `rsa-sha2-512` (PKCS#1 v1.5, NOT PSS) | 256-byte raw signature block |
| ~~Ed25519~~ | **REFUSED** — not in TPM 2.0 spec | **REFUSED** — same | n/a | n/a |

Ed25519 is not defined by the TPM 2.0 specification — the wizard refuses with the localized `tpmSshAlgUnsupported` copy rather than silently substituting a different curve.

**Storage model (Linux).** Two modes set at generate time:

1. **On-disk wrapped blob** (default; `TpmSshStorage::Blob`). `TPM2_Create` returns `(public, private)` blobs; we pack them with the `[u32 BE pub_len][pub][u32 BE priv_len][priv]` envelope (same shape the seal-path uses) and store the bytes on `ssh_keys.tpm_blob`. The on-disk file format wrapping that envelope is the TCG draft [`draft-bottomley-tpm2-keys-asn1`](https://datatracker.ietf.org/doc/draft-bottomley-tpm2-keys-asn1/) "TSS2 PRIVATE KEY" PEM — byte-compatible with `ssh-tpm-agent` and `openssl-tpm2-engine` for cross-tool import. Every sign re-issues `TPM2_Load` (~5-20 ms on a typical fTPM) and tears the transient handle down on completion. Portable across reinstalls — the OS reset doesn't touch the user-data dir.
2. **Persistent NV handle** (power-user opt-in; `TpmSshStorage::PersistentHandle(handle)`). After the blob mints, the wizard's "Persist in TPM memory slot" affordance calls `tpm_ssh::make_persistent(handle)` which loads the wrapped pair under a fresh storage primary and fires `TPM2_EvictControl(Owner, loaded, Persistent::Persistent(handle))` against a user-chosen slot in the `0x81010001..0x8101FFFF` range. The chip holds the key in TPM RAM; subsequent signs reach the slot via `tr_from_tpm_public(TpmHandle::Persistent(handle))` and skip the load step (~2-5 ms total) but consume one of the handful of persistent slots (typical fTPM ships ~7 free handles). `tpm2_clear` / BIOS reset wipes them. The inverse `tpm_ssh::evict(key)` fires `TPM2_EvictControl` against the persistent slot to free it. `TPM_RC_NV_DEFINED` on a busy slot surfaces as `Error::Crypto("handle in use: persistent slot 0xNN in use")`; the FRB envelope's `handle in use:` discriminator routes the Dart wizard to the localized `tpmSshHandleInUse` toast. Real-chip exercise lives in the `#[ignore]`-gated `tpm_ssh_swtpm.rs` integration test (promote → sign-from-persistent → evict → re-promote round-trip + slot-collision arm).

**Storage model (Windows).** The silent-TPM variant lives in CNG's PCP keystore at `%LOCALAPPDATA%\Microsoft\Crypto\PCPKSP\<user-sid>\` — NCrypt owns the path and the SSH driver never touches the filesystem directly. The CNG name format `letsflutssh-tpm-<user-hash>-<uuid>` lands in `ssh_keys.cng_key_name`; `NCryptOpenKey` re-binds to it on every sign.

**Authorization model.**

- **PIN-bound (Linux)** — `TPM2B_AUTH` set on the sensitive area at create time. Every `TPM2_Sign` rebinds the auth value via `tr_set_auth`; the TPM's own dictionary-attack lockout fires after 4 wrong PINs (typical Microsoft fTPM policy) and locks the **entire chip** including BitLocker / disk-unlock for a cooldown window. The wizard surfaces `tpmSshPinLockoutWarning` aggressively at every PIN entry surface — TPM lockout is the largest user-facing footgun in this whole path.
- **No-PIN (Linux)** — `TPM2B_AUTH` empty. Convenient for headless service-account keys where no human is present to type a PIN; the key is bound to the OS install (any process that can reach `/dev/tpmrm0` and load the blob can sign).
- **Silent (Windows PCP)** — same security contract as Linux no-PIN: any process running as the logged-in user can sign without a prompt. The wizard surfaces `tpmSshSilentWarning` in red so the user understands the trade-off before opting in. This is the load-bearing contrast with Hello-gated keys, which fire a PIN/fingerprint/face prompt on every sign.
- **PCR-binding** — deferred to v2. The UX cost (key breaks after every BIOS update) outweighs the threat-model win for an SSH key. See [Appendix B](#appendix-b---forward-commitments).

**Probe + capability ladder.**

| Platform | Probe result | Rung | UI |
|---|---|---|---|
| Linux with `/dev/tpmrm0` + user in `tss` group | `Available` | 3 native impl | Wizard enabled |
| Linux no TPM | `DeviceNodeMissing` | 4 honestly hide | "No TPM detected on this device" |
| Linux TPM present but user not in `tss` group | `NoPermission` | 4 honestly hide | "Add user to the `tss` group" + per-distro `usermod -a -G tss $USER` snippet in `USER_GUIDE.md` |
| Linux `tpm2-tools` missing (subprocess fallback) | `BinaryMissing` | 5 optional OS dep | Per-distro install snippet in `USER_GUIDE.md` |
| Windows 10 1607+ with TPM | `Available` (reuses Hello probe) | 3 native impl | Wizard enabled |
| Windows without PCP / Server Core minimal | `ProviderUnavailable` | 4 honestly hide | "No TPM detected on this device" |
| macOS / iOS / Android | `Unsupported` | 4 honestly hide | Toolbar entry hidden — `isApplePlatform` / `isMobilePlatform` gate at the call site routes users to the Secure Enclave wizard on Apple |

**DB schema.** `ssh_keys` carries the TPM 2.0 SSH column block alongside the existing FIDO2 / PKCS#11 / Enclave / Hello block: `tpm_blob BLOB NULL` (TSS2 PRIVATE KEY ASN.1 bytes — Linux blob mode), `tpm_handle INTEGER NULL` (persistent NV handle — Linux), `tpm_provider TEXT NULL` (one of `'tss-esapi'` / `'cng-pcp'` — drives the connect dispatcher's signer selection), `tpm_pin_required INTEGER NOT NULL DEFAULT 0` (gates the per-sign PIN prompt), `cng_key_name TEXT NULL` (Windows PCP silent variant's `NCryptOpenKey` name). The columns stay NULL / 0 for every non-TPM row.

**Signing path.** Linux: the signer reads `ssh_keys.tpm_blob`, calls `tpm_ssh::import_blob` to recover the `TpmSshKey`, then `tpm_ssh::sign(cfg, key, auth_value, data)` — the auth value comes from the SecretStore entry under `tpm.pin.<key_id>` for PIN-bound rows, `None` for empty-auth. The TPM driver returns `TpmSshSignature::{EcdsaP256RawConcat, Rsa2048}` (raw bytes); the `lfs_core` caller wraps via `ssh::wire::ecdsa_raw_concat_to_ssh_mpint` / `ssh::wire::rsa_pkcs1_v15_to_ssh_blob` and prefixes the SSH userauth `signature` body. Windows: the signer reads `ssh_keys.cng_key_name`, builds a `TpmSilentKeyHandle`, calls `ncrypt_ssh::sign_for_ssh_silent` (no `set_ui_policy` call ever fires on this row), and wraps the same way. `TPM_RC_BAD_AUTH` / `TPM_RC_LOCKOUT` on the Linux path map to `Error::Tpm("pin incorrect: ...")` / `Error::Tpm("lockout: ...")` so the Dart connect dialog routes a wrong-PIN retry distinctly from a cooldown banner.

**Cross-tool blob compat.** The TSS2 PRIVATE KEY ASN.1 envelope this module emits is byte-shape-compatible with `ssh-tpm-agent` / `openssl-tpm2-engine`. Imports are best-effort one-way: a `.tpm` file produced by `tpm2_create -i` + the matching `tpm2_marshall` round-trips through `tpm_ssh::import_blob`, but blobs carrying a **PCR policy** reject at import in v1 with a typed `Error::Crypto("policy = pcr-binding-not-supported")` reason — the TPM-side policy session machinery needs more UX than v1 affords. Wired in [Appendix B](#appendix-b---forward-commitments).

**`.lfs` export semantics.** Linux TPM rows in **blob mode** include the wrapped blob in the archive; the importing device's connect path drops the bytes into `ssh_keys.tpm_blob` and can sign as long as the same chip primary key derives identically (which holds because the [`tpm_native::build_primary_template`](https://github.com/parallaxsecond/rust-tss-esapi) template matches the `tpm2 createprimary -C o` default byte-for-byte). Cross-device portability **does not work** for persistent-handle Linux rows (the chip on the new device is different) or for Windows PCP rows (CNG keys are chip + user-SID bound). The wizard's device-bound warning surfaces the constraint at create time.

**`tss-esapi` declaration.** Workspace declaration is caret-major — the envelope format is TCG ASN.1 PEM per `draft-bottomley-tpm2-keys-asn1` ([`linux::tpm_tcg_pem`](../rust/crates/lfs_os_security/src/linux/tpm_tcg_pem.rs)), decoupled from `tss-esapi` builder defaults. A minor bump can no longer brick existing user envelopes by reshuffling how `Tss2_MU_*` marshals fields — the marshalled bytes only ride inside the DER `pubkey` / `privkey` OCTET STRINGs and the chip itself produces them. The major version is the only API-churn guard. Defence-in-depth: `tpm_native::tests::storage_primary_template_marshalls_to_fixture` pins the marshalled storage-primary template against `tests/fixtures/storage_primary_template_v1.bin`; a silent default flip in a minor bump surfaces at CI time so the maintainer mints a new fixture (and ships a `SchemaVersions::HW_VAULT_LINUX` bump) intentionally. The `tpm_ssh_swtpm.rs` integration test (`#[ignore]`-gated; runs against a `swtpm` socket on self-hosted CI) covers the round trip end-to-end.

**Error envelope.** `Error::Tpm(String)` carves the TPM SSH path out of the generic `Io` / `Platform` buckets; the FRB envelope's `kind::TPM` discriminator lets the Dart UI route `pin incorrect:` to the retry dialog, `lockout:` to the cooldown banner, `unavailable:` to the wizard's disabled state with the matching localized reason (no TPM / firmware disabled / `tss` group missing), `handle in use:` to the persistent-slot retry, and the catch-all to the generic TPM error toast.

**Tests.** Unit tests in `rust/crates/lfs_os_security/src/linux/tpm_ssh.rs::tests` cover the algorithm round-trip via `from_key_type` / `key_type_tag`, the envelope `pack_envelope`/`unpack` round trip + truncation rejection, the `pad_left_to_32` padding contract for short / oversized r/s bytes, the `make_persistent` range guard for `0x81010001..0x8101FFFF`, the `make_persistent` already-persistent pre-condition (storage unchanged on rejection), the `evict` not-persistent pre-condition, and the wire-algorithm default selection. The Signer adapter has its own tests at `rust/crates/lfs_core/src/ssh/tpm_signer.rs::tests` (algorithm round-trip from key-type tags, error mapping, russh `Algorithm` contract). The agent dispatcher has a test at `rust/crates/lfs_core/src/ssh_agent/backends.rs::tests` (`BackendKind::Tpm` resolved from a `KeyBackend::Tpm` row). The integration test `rust/crates/lfs_os_security/tests/tpm_ssh_swtpm.rs` is `#[ignore]`-gated and drives end-to-end generate/sign/import against a `swtpm` socket — covers the blob-mode round trip plus the persistent-handle promote/sign/evict/re-promote sequence and the `handle in use:` slot-collision arm. The doc-comment in that file carries the manual `swtpm_setup` / `swtpm socket` invocation. The Dart-side wizard tests live in `test/widgets/tpm_ssh_dialog_test.dart` — probe-disabled state, configure step rendering, Generate-button disabled without a label, badge info popover, silent-variant warning copy.

#### Android Hardware Keystore / StrongBox SSH keys

`lfs_os_security::android::keystore_signer` generates / signs / deletes SSH keys whose private half lives inside the Android Hardware Keystore — StrongBox HSM on devices that ship one (Pixel 3+, Samsung S20+, etc.) and the TEE (KeyMint v2 on API 33+, Keymaster on older) elsewhere. The chip refuses to export the private bytes regardless of tier; every signing operation routes through `Signature.initSign(privateKey) + BiometricPrompt.CryptoObject(signature) + Signature.sign()` per the auth requirement set at create time (`setUserAuthenticationRequired(true)` + `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)`).

**Why a Kotlin shim.** `BiometricPrompt.AuthenticationCallback` is an abstract class with three abstract methods; subclassing it from Rust via `JNIEnv::register_native_methods` is supported by the `jni` crate but fragile across `androidx.biometric` minor versions (the alpha → 1.0 cutover shifted the `AuthenticationResult` constructor signature). A tiny Kotlin adapter (`LfsKeystoreSignCallback`) avoids the moving target — the JVM-side class binds once at compile time and the JNI surface is two `extern "system"` entry points (`nativeOnSigned` / `nativeOnFailed`) the Kotlin overrides invoke.

```mermaid
flowchart LR
    UI[KeystoreSshDialog]
    UI --> FRB[keystore_ssh_generate FRB]
    FRB --> KOTLIN[KeystoreSshSigner.generate]
    KOTLIN --> KSGEN[KeyPairGenerator AndroidKeyStore<br/>setUserAuthenticationRequired<br/>setIsStrongBoxBacked]
    KSGEN --> KSCHIP[(StrongBox HSM or TEE)]
    KSCHIP --> DB[ssh_keys row<br/>backend=keystore<br/>keystore_alias populated]
    DB --> SIGN[connect_pubkey_keystore_owned + KeystoreSigner]
    SIGN --> JNI[JNI: Signature.initSign<br/>BiometricPrompt.CryptoObject]
    JNI --> PROMPT{BiometricPrompt}
    PROMPT -- success --> KSSIGN[Signature.sign]
    PROMPT -- cancel / lockout --> ERR[Error::Keystore]
    KSSIGN --> WRAP[ssh::wire::ecdsa_der_to_ssh_mpint<br/>ed25519_to_ssh_blob<br/>rsa_pkcs1_v15_to_ssh_blob]
    WRAP --> SSH[SSH userauth signature]
```

**Module layout.** Android native bridge: `rust/crates/lfs_os_security/src/android/keystore_signer.rs` (cfg-gated to `target_os = "android"`; mirrors the `biometric.rs` shape with a process-wide pending map keyed on a per-sign `u64`). Kotlin adapter: `android/app/src/main/kotlin/com/llloooggg/letsflutssh/KeystoreSshSigner.kt` (`generate` / `sign` / `delete` static methods called from JNI) + `LfsKeystoreSignCallback.kt` (callback adapter that fires `nativeOnSigned` / `nativeOnFailed`). Signer adapter: `rust/crates/lfs_core/src/ssh/keystore_signer.rs` (`russh::Signer` impl). FRB shim: `rust/crates/lfs_frb/src/api/keystore_ssh.rs`.

**Algorithm matrix.**

| `KeystoreAlgo` | JCA `KeyPairGenerator` | TEE (Android API) | StrongBox (Android API) | SSH wire-name |
|---|---|---|---|---|
| `EcdsaP256` | `EC` over `secp256r1`, `DIGEST_SHA256` | API 23+ | API 28+ | `ecdsa-sha2-nistp256` |
| `Ed25519` | `Ed25519` | API 33+ (KeyMint v2) | **not guaranteed** | `ssh-ed25519` |
| `Rsa2048` | `RSA` 2048 + `DIGEST_SHA256`, PKCS#1 v1.5 | API 18+ | API 28+ | `rsa-sha2-256` |
| ~~RSA-3072 / 4096~~ | — | — | **StrongBoxUnavailableException** | — |
| ~~ECDSA P-384 / P-521~~ | — | API 23+ | **not supported** | — |

EC P-256 is the only uniformly StrongBox-eligible algorithm across the project's min-SDK. RSA-2048 carries the widest TEE compatibility; Ed25519 is TEE-only on Android 13+. The wizard refuses RSA-3072+ and EC P-384+ at the radio level — the StrongBox subset is silent-fail per AOSP `KeyMint`, and offering a weaker-than-TEE fallback would defeat the purpose.

**StrongBox subsetting probe.** `PackageManager.hasSystemFeature(FEATURE_STRONGBOX_KEYSTORE)` reports the device-wide capability. Necessary but not sufficient — the actual `setIsStrongBoxBacked(true)` generate may still throw `StrongBoxUnavailableException` for the chosen algorithm / key size on a firmware update or a vendor-specific subset. The Kotlin layer catches the exception, retries once without the flag, and surfaces `actualStrongBox = false` in the result so the badge label stays honest. The `ssh_keys.keystore_strongbox` column reflects the actual outcome — not the user's toggle.

**Authorisation model — per-op auth via BiometricPrompt CryptoObject.** Every signature must hop through a `BiometricPrompt.CryptoObject(signature)` round trip. The bare `Signature.initSign(privateKey)` call throws `UserNotAuthenticatedException` until the prompt authorises the signature object; on success, `result.cryptoObject.signature.update(data); .sign()` produces the bytes — the signature object inside `result.cryptoObject` is the authorised one. API 30+ uses `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)` for per-op auth (no time window); API 23-29 falls back to the deprecated `setUserAuthenticationValidityDurationSeconds(0)` which still resolves to per-op on every shipped device. The deprecated method is forwarded internally on API 30+ too.

**Enrolment-change invalidation.** `setInvalidatedByBiometricEnrollment(true)` is set at create time: adding / removing / re-enrolling a fingerprint or face destroys the on-chip key. Catch `KeyPermanentlyInvalidatedException` on the next sign and surface `keystoreKeyInvalidatedByEnrollment` so the user re-generates + re-registers the public key on servers. Mirrors Apple's `biometryCurrentSet` ACL — the load-bearing security property that distinguishes hardware-bound keys from a software key sat behind a biometric gate.

**`MainActivity` requirement.** `BiometricPrompt` hosts its UI inside a Fragment; a plain `FlutterActivity` host crashes. `MainActivity extends FlutterFragmentActivity` (`android/app/src/main/kotlin/com/llloooggg/letsflutssh/MainActivity.kt:13`) — already in place for the biometric-unlock vault path; the SSH signer reuses the same capture (`MAIN_ACTIVITY` `OnceLock<GlobalRef>` in `jni_bootstrap`).

**`AndroidManifest.xml::allowBackup` invariant.** `android:allowBackup="false"` (set at line 51 of `android/app/src/main/AndroidManifest.xml`) forces a device transfer / cloud restore to land as a clean install — the AndroidKeyStore alias does not survive the round trip anyway (the chip on the new device is different), but the DB rows must not survive either, otherwise the user lands on a fresh phone with `backend = 'keystore'` rows whose private key is unreachable.

**DB schema.** `ssh_keys` carries the Android Hardware Keystore / StrongBox column block alongside the existing FIDO2 / PKCS#11 / Enclave / Hello / TPM block: `keystore_alias TEXT NULL` (AndroidKeyStore alias the `KeyStore.getEntry(alias, null)` lookup re-binds to on every sign — minted under the `lfs-keystore-` prefix to stay separate from `FlutterSecureStorageKeyAlias_`), `keystore_strongbox INTEGER NOT NULL DEFAULT 0` (`1` when StrongBox actually accepted the request — drives the badge label split), `keystore_user_auth_required INTEGER NOT NULL DEFAULT 0` (`1` for every current Keystore row — the wizard always sets `setUserAuthenticationRequired(true)`; reserved for a future no-auth variant), `keystore_platform TEXT NULL` (capture-time `Build.MODEL` + Android version surfaced in the badge popover). The columns stay NULL / 0 for every non-Keystore row.

**Signing path.** The signer reads `ssh_keys.keystore_alias`, hands it to `lfs_os_security::android::keystore_signer::sign(alias, algo, data)`, and the JNI bridge fires the BiometricPrompt on the main thread. On `onAuthenticationSucceeded`, the Kotlin side runs `result.cryptoObject.signature.update(data); .sign()` and routes the bytes back through `nativeOnSigned`. The Rust caller wraps via `ssh::wire::ecdsa_der_to_ssh_mpint` (ECDSA P-256 — AndroidKeyStore returns DER `SEQUENCE { INTEGER r, INTEGER s }`), `ssh::wire::ed25519_to_ssh_blob` (Ed25519 — raw 64 bytes), or `ssh::wire::rsa_pkcs1_v15_to_ssh_blob` (RSA-2048 — raw 256-byte block). `KeyPermanentlyInvalidatedException` maps to `Error::Keystore("invalidated: ...")`; `UserNotAuthenticatedException` after BiometricPrompt cooldown maps to `Error::Keystore("user not authenticated: ...")`; BiometricPrompt `ERROR_NEGATIVE_BUTTON` / `ERROR_USER_CANCELED` map to `Error::Keystore("cancelled: ...")`; StrongBox flip-on-us maps to `Error::Keystore("strongbox unavailable: ...")` so the Dart connect dialog routes each path to a distinct toast.

**Capability ladder rendering.**

| State | Rung | Label |
|---|---|---|
| StrongBox available + algorithm compatible + biometric enrolled | 3 native impl | "Hardware-backed SSH key (StrongBox HSM)" |
| TEE only / device-side StrongBox refusal | 3 native impl | "Hardware-backed SSH key (TEE)" — different label, never silently downgrade |
| User toggled StrongBox + `StrongBoxUnavailableException` (silent retry) | 3 native impl | Result reports `actualStrongBox = false`; badge label flips to TEE so the user sees the actual binding |
| Biometric not enrolled | 4 honestly hide | Wizard disabled with "Enrol biometric or device PIN first" |
| Non-Android | 4 honestly hide | Toolbar entry hidden — `Platform.isAndroid` gate at the call site |

**`.lfs` export semantics.** Keystore rows are intrinsically per-device — the AndroidKeyStore alias resolves only on the chip that minted the key. The archive-apply path on the receiving device drops the `keystore_*` columns and lands the row as `backend = 'software'` with an empty `private_key`, mirroring the FIDO2 / PKCS#11 / TPM / Enclave / Hello arms; the receiving user re-generates the key on their own device. The `keystoreKeyExportDisabled` copy surfaces inside the badge popover and the wizard's complete step.

**Agent-endpoint reachability.** The in-process ssh-agent endpoint is `#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]` — Android has no surface to host a Unix-socket agent for system clients (`git`, `ssh`, OpenSSH on a desktop). The `BackendKind::Keystore` arm in `lfs_core::ssh_agent::backends::dispatch_sign_by_kind` surfaces `Error::Keystore("Android Hardware Keystore is reachable only on Android in-app sessions")` to keep the dispatcher's match exhaustive on desktop targets; in practice the listing path filters Keystore rows out before the dispatcher sees them.

**Tests.** Unit tests in `rust/crates/lfs_core/src/ssh/keystore_signer.rs::tests` cover the algorithm round-trip via `from_key_type`, the error mapping, the russh `Algorithm` contract, and the wire-algorithm selection. The agent dispatcher has a `from_row_resolves_keystore_when_backend_is_keystore` test in `rust/crates/lfs_core/src/ssh_agent/backends.rs::tests` plus a `dispatch_keystore_on_desktop_surfaces_unsupported` async test that pins the desktop refusal contract. The Dart-side wizard test lives in `test/widgets/keystore_ssh_dialog_test.dart` — probe-disabled state, algorithm radio, StrongBox toggle disabled-with-reason on Ed25519, generate calls the FRB backend. End-to-end Keystore generate / sign + BiometricPrompt is the allow-listed "OS-specific capability" exception (no unit test on the bridge side; requires an emulator with biometric enrolled).

#### In-process ssh-agent endpoint

`lfs_core::ssh_agent` exposes our hardware-bound SSH keys (FIDO2 today; PKCS#11 / TPM 2.0 / Apple Secure Enclave / Windows NCrypt / Android Hardware Keystore as those backends land) to every SSH-protocol-speaking application on the same host — `git` in a terminal, OpenSSH `ssh.exe` / `scp` / `sftp`, VS Code Remote-SSH, JetBrains Gateway, PuTTY 0.78+, IDE plugins, CI runners. Without the endpoint the hardware-bound keys we import are reachable only from our own connect path; corporate workflows expect a key on a host to work everywhere on that host. The endpoint is the symmetric counterpart of `connect_default_agent` — that path consumes external agents, this one IS the agent for external clients.

```mermaid
flowchart LR
    GIT[git push]
    SSH[ssh / scp / sftp]
    IDE[VS Code / JetBrains / PuTTY 0.78+]
    GIT --> SOCK
    SSH --> SOCK
    IDE --> SOCK
    SOCK[UDS / NamedPipe]
    SOCK --> LOOP[loop_runner::handle_socket]
    LOOP -- "msg id 11" --> IDS[identities::build_advertised + encode_identities_answer]
    IDS --> CERTQ[ssh_key_certificates DAO]
    LOOP -- "msg id 13 + cert key_blob" --> CERTSIGN[loop_runner::sign_cert_request &nbsp; Certificate::from_bytes]
    CERTSIGN --> RUN[Endpoint::run_sign]
    LOOP -- "other verbs" --> SESSION[Endpoint &nbsp; Session impl]
    SESSION --> RUN
    RUN --> POLICY[per_key_confirm gate]
    POLICY --> DISP[backends::dispatch_sign]
    DISP --> FIDO[FidoSigner &nbsp; CTAP2 HID]
    DISP --> P11[Pkcs11Signer &nbsp; Cryptoki]
    DISP --> SE[Secure Enclave]
    DISP --> NCRYPT[Windows NCrypt + Hello]
    DISP --> TPM[TPM 2.0 Linux ESAPI + Windows PCP silent]
    DISP -.future.-> KS[Android Keystore]
```

**Module layout.** Files live under `rust/crates/lfs_core/src/ssh_agent/`:

| File | Purpose |
|---|---|
| `mod.rs` | Cfg-gated re-exports + the desktop / mobile split. |
| `endpoint.rs` | `Endpoint` struct + `impl Session`; `start_endpoint` / `stop` / `status` lifecycle; per-process `AgentHandle` parking lot; per-platform accept loop that spawns one `loop_runner::handle_socket` task per accepted client. |
| `loop_runner.rs` | Custom framing loop. Reads u32-prefixed frames, peeks the message-type byte, routes `SSH_AGENTC_REQUEST_IDENTITIES` (msg id 11) through the cert-aware path in `identities`, intercepts `SSH_AGENTC_SIGN_REQUEST` (msg id 13) when the `key_blob` algorithm ends in `-cert-v01@openssh.com` to drive the cert-aware sign path, everything else through `Session::handle` for typed encoding. The reason this exists at all: `ssh-agent-lib 0.5`'s `Session::handle` returns the strongly typed `Response`, which encodes IDENTITIES_ANSWER through `Identity::encode` → `KeyData::encode_prefixed`. `KeyData` has no `Certificate` variant; the `Other(OpaquePublicKey)` catch-all injects an extra `string` length prefix between the algo name and the rest of the encoded bytes, which doesn't match the OpenSSH certificate wire shape (`algo_name || string nonce || inline public-key fields || serial || ... || string signature`). `SignRequest::decode` hits the same mismatch — `reader.read_prefixed(KeyData::decode)` rejects cert-form `key_blob` payloads. Cert blobs cannot route through the typed path at all; bypassing `listen()` is the least-invasive fix that keeps every non-cert verb typed. The cert-form sign path peeks the algorithm string in `key_blob`, parses the cert via `ssh_key::Certificate::from_bytes`, extracts the bare `KeyData` via `cert.public_key()`, looks up the matching `ssh_keys` row via `Endpoint::find_row_by_keydata`, and dispatches through the shared `Endpoint::run_sign` helper. The response signature is bare-key shape (`string ssh-ed25519 \|\| string raw_sig`) regardless of whether the request `key_blob` was a cert — OpenSSH's per-type sign callbacks (`ssh_ed25519_encode_store_sig`, the matching RSA/ECDSA siblings) always write the bare algorithm name without the `-cert-v01@openssh.com` suffix. The `key_blob` field in the request only selects the identity. |
| `identities.rs` | Cert-aware IDENTITIES_ANSWER serialiser. `build_advertised` walks live `ssh_keys` rows (filters Software + Deny), emits the bare-key wire blob, then — when `ssh_key_certificates` holds a paired cert — appends a second entry whose `key_blob` is `Certificate::to_bytes()`. Matches OpenSSH `ssh-agent` semantics: `ssh-add cert.pub` adds both the bare key and the cert form through two separate `SSH_AGENTC_ADD_IDENTITY` calls (OpenSSH's `lookup_identity` compares full key equality, not just the public half, so the two entries don't collide). Cert-aware clients (OpenSSH 8+) pick the cert during userauth; bare-only clients fall back to the public-key form. `encode_identities_answer` writes the byte sequence draft-miller-ssh-agent-14 §3.5 specifies: `u8 msg_id(12) || u32 nkeys || (string key_blob || string comment)*`. |
| `backends.rs` | `BackendKind` discriminator + `dispatch_sign` / `dispatch_sign_by_kind`. One arm per Signer impl; today only `Fido2`. |
| `transport.rs` | `bind_unix` (Linux/macOS) + `bind_windows` (named pipe) + per-platform cleanup helpers. |
| `per_key_confirm.rs` | Parked-prompt registry + `enqueue` / `respond_to_request` / `cancel_request`. Fires bus events on `EventTopic::SshAgent`; the Dart `SshAgentPromptListener` mounts `AgentSignatureRequestDialog`. |
| `stub.rs` | Mobile no-op stub. |

**Crate.** `ssh-agent-lib = "0.5.2"` (wiktor-k/ssh-agent-lib, MIT/Apache-2.0). The trait surface we implement is [`ssh_agent_lib::agent::Session`]; the listener is **NOT** `ssh_agent_lib::agent::listen` — we run our own framing loop in `loop_runner` (see the row above for why) and only delegate the typed verbs (`SignRequest`, `Lock`, `Unlock`, `Extension`, the various refused add/remove arms) back through `Session::handle`. `ssh-key = "0.6"` is a separate crate identity from the russh-forked `internal-russh-forked-ssh-key` — both resolve side by side, the agent surface uses the canonical crates.io shape (including `ssh_key::Certificate::from_openssh` / `to_bytes` for the cert-advertise path).

**Transport.**

| Platform | Path | Permissions |
|---|---|---|
| Linux / macOS | `${XDG_RUNTIME_DIR:-/tmp}/letsflutssh-agent.<pid>/agent.sock` | Parent dir mode `0o700`. Drop guard unlinks the socket and removes the parent dir. |
| Windows | `\\.\pipe\letsflutssh-agent.<pid>` | `ServerOptions::first_pipe_instance(true)` — default DACL grants only the current user SID + SYSTEM. |
| Android / iOS | n/a | Mobile builds compile out the entire module; the FRB shim surfaces `Err(Unsupported)` so the Settings toggle renders disabled-with-reason. |

The `<pid>` suffix keeps parallel instances from colliding on the same path (the single-instance lock runs in a separate layer; per-pid naming is the belt-and-braces).

**Session methods.** The verbs we honour and the ones we refuse mirror the security posture:

| Verb | Behaviour |
|---|---|
| `request_identities` | Lists every `ssh_keys` row with `BackendKind != Software` AND `agent_policy != Deny` AND `!(backend == Fido2 && has_user_verification)`. Software keys never appear — the endpoint MUST NOT expose plaintext PEM material. FIDO2 credentials whose CTAP2 metadata carries the mandatory user-verification bit are filtered too (and the skip is logged via `AppLogger` at `info`) — the agent wire protocol has no surface for collecting a PIN at sign time, so a published row would surface `CTAP2_ERR_PIN_REQUIRED` on every sign. The supported entry point for UV-required keys is the direct connect path's `HardwareKeyPromptDialog`. For rows that carry a paired OpenSSH certificate in `ssh_key_certificates`, the listing emits BOTH the bare public-key blob AND the cert blob (`Certificate::to_bytes()`) as two separate identity entries — matches OpenSSH `ssh-add` semantics so cert-aware clients (OpenSSH 8+) prefer the cert during userauth while bare-only clients still authenticate. The bytes do NOT route through `ssh_agent_lib`'s typed `Identity::encode` for cert rows; see the `loop_runner` row above for why and how. Verifiable end-to-end via `ssh-add -l` against our live endpoint with `SSH_AUTH_SOCK` pointed at our socket: a cert-paired key shows two lines (`(ED25519-SK)` and `(ED25519-CERT-SK)`, or the matching label for ECDSA-SK keys). Bare keys keep their single line. |
| `sign(SignRequest)` | Bare-key form: resolves the row by matching the request's `KeyData` against `PublicKey::from_openssh(row.public_key)`. Cert form: the typed `SignRequest::decode` can't parse cert `key_blob`, so `loop_runner` intercepts msg id 13 frames with a cert-suffix algorithm, parses the cert via `Certificate::from_bytes`, looks up the row by the embedded bare `KeyData`, then drives the shared `Endpoint::run_sign` helper that both paths reach. From the row onward both paths share: `Deny` policy short-circuits to failure; `Ask` policy parks the signer on a oneshot, fires `Event::SshAgentSignaturePrompt`, awaits the Dart-side verdict with a 60-second timeout. Hands the resulting bytes to `backends::dispatch_sign`. The FIDO2 dispatcher short-circuits a UV-required row with the typed `BackendError::FidoUvNotSupportedViaAgent { key_label, fingerprint }` before CTAP2 is reached — the listing filter normally hides such rows but the SIGN arm is a defense-in-depth gate against a cert-form lookup, a race with a concurrent listing, or a manually crafted SIGN_REQUEST. The wire-shape SIGN_RESPONSE always carries the bare-key signature regardless of whether the `key_blob` was bare or cert. |
| `add_identity` / `remove_identity` / `remove_all_identities` / `add_smartcard_key` / `add_smartcard_key_constrained` / `remove_smartcard_key` | Refuse with the catch-all error arm. External clients MUST NOT push key material into our store. |
| `add_identity_constrained` | Refuse. When the payload's constraint list carries a `restrict-destination-v00@openssh.com` / `restrict-destination-v01@openssh.com` extension constraint, surface the specific "agent does not enforce destination constraints — use a per-key signer or omit `-h`" message (still `SSH_AGENT_FAILURE` on the wire, but the log line names the precise reason). Silent acceptance would let `ssh-add -h host` look enforced while signing anywhere. |
| `lock(password)` / `unlock(password)` | Flips the per-connection `Endpoint::locked` flag. While locked, `request_identities` returns empty and `sign` refuses. The password parameter is accepted but not bound to anything — we have no recovery path from "wrong unlock string", so storing a comparable secret would be a footgun. |
| `extension` | Accepts `session-bind@openssh.com` (parsed by ssh-agent-lib upstream; we accept the payload — CTAP2 already signs over the session-bound bytes from the server side). Refuses `restrict-destination-v00@openssh.com` / `restrict-destination-v01@openssh.com` with `ExtensionFailure` for the same reason as the constraint arm above — silent acceptance would imply enforcement we do not perform. Every other extension also surfaces `ExtensionFailure` so external clients fall back to the unextended protocol. |

**Certificate advertising.** Cert-paired rows surface through `request_identities` as two separate entries (bare key blob + cert blob). The connect path's cert-bearing twin `Session::connect_pubkey_sk_cert_owned` and the agent endpoint's cert advertising share the same `ssh_key_certificates` DAO row — the connect side reads `key.cert.<key_id>` out of the SecretStore through `auth_compose::prepare_auth`, the agent side calls `Certificate::from_openssh` then `to_bytes()` on the same DB column. See [Certificate authentication via sk-*](#certificate-authentication-via-sk-) for the userauth-side composition with `FidoSigner` and the wire-format trailer detail. The advertising path is the agent-endpoint mirror: cert-aware external clients (OpenSSH 8+, current PuTTY) pick the cert during userauth automatically; bare-only clients fall back transparently.

**Certificate signing.** Cert-form SIGN_REQUEST (`key_blob` algorithm ending in `-cert-v01@openssh.com`) routes through the same backend signer the bare-key request would use. `ssh-agent-lib 0.5`'s `SignRequest::decode` cannot represent a cert in its `KeyData` field — `reader.read_prefixed(KeyData::decode)` injects a length prefix the cert wire layout doesn't carry — so the cert path is intercepted in `loop_runner` before the typed decoder runs. The interceptor reads the SIGN_REQUEST body manually (`string key_blob || string data || uint32 flags`), parses `key_blob` via `ssh_key::Certificate::from_bytes`, extracts the embedded bare `KeyData` via `cert.public_key()`, resolves the matching `ssh_keys` row through the same `find_row_by_keydata` equality check the bare-key path uses, and drives `Endpoint::run_sign` — the helper shared with `Session::sign` that runs the `agent_policy = 'ask'` confirm gate and dispatches to the backend. The SIGN_RESPONSE carries a bare-key signature (`string ssh-ed25519 || string raw_64_byte_sig` for ed25519; matching shapes for the other algorithms). Verified against OpenSSH `process_sign_request2` / `agent_decode_alg` and the per-type sign callbacks (`ssh_ed25519_encode_store_sig` and siblings): every callback writes the bare algorithm name regardless of whether the lookup key was a cert; the cert algorithm appears only as the request-side discriminator that selects the identity. Bare-key SIGN_REQUEST stays on the typed path.

**Per-key dispatch policy.** `ssh_keys.agent_policy` (TEXT NOT NULL DEFAULT `'ask'`) drives the gate:

- `'always'` — sign silently. The hardware backend's own touch / PIN prompt still fires when the credential carries the user-verification bit.
- `'ask'` — default. Every SIGN_REQUEST surfaces a Flutter `AgentSignatureRequestDialog` (header: requesting process name + key label; buttons: Authorize once / Authorize and remember / Deny). Mirrors `ssh-add -c` semantics. The "remember" button promotes the row to `'always'` in `ssh_keys`.
- `'deny'` — always refuse. The listing path also hides `Deny` rows entirely so the external client cannot enumerate which keys are policy-denied.

**Peer-process resolution.** The dialog body renders the requesting process name when the OS can surface it cheaply: Linux `SO_PEERCRED` → `/proc/<pid>/comm`, Windows `GetNamedPipeClientProcessId` → `QueryFullProcessImageNameW`. macOS does not — BSD `getpeereid` returns uid/gid, never a pid — so the dialog renders the localized "An external SSH client" placeholder there. Today's build surfaces `None` on every platform; per-OS plumbing is a follow-up that drops in above the `ListeningSocket::accept` boundary without touching the Session clones.

**Lifecycle.** `start_endpoint()` binds the listener, spawns a Tokio task running `listen`, parks an `AgentHandle` in a process-singleton `OnceLock<Mutex<Option<AgentHandle>>>`. `stop()` takes the handle out of the slot and drops it — the `Drop` impl aborts the listener task and runs the per-platform cleanup. Idempotent on both sides: a repeat `start_endpoint` returns the existing path, a repeat `stop` is a no-op. The Settings UI is the only authorised driver: the endpoint is off by default (security-first; the user opts in via the "Expose hardware-bound keys to system SSH clients" toggle in `Settings → External SSH client integration`).

**Wire shape per signature.** The Session::sign response carries `Signature { algorithm, data }` — two fields, agent protocol wraps each in a `string(...)` prefix. `data` for `sk-ed25519` is `64-byte signature || u8 flags || u32 counter` (69 bytes total); for `sk-ecdsa-p256` it's `string mpint r || string mpint s || u8 flags || u32 counter`. The userauth-shape outer `string(algorithm) || string(sig_blob)` wrapping the userauth path uses is NOT applied here — the agent codec adds the prefixes itself. `ssh::sk::sign_sk_blob_only` is the lower-level helper that returns just the SK trailer; the userauth path keeps `sign_for_userauth` for its own composition.

**Refusal contract.** Every refusal returns `AgentError::Other(message)` — `ssh_agent_lib` renders this as the wire-level `SSH_AGENT_FAILURE` byte on the server side, which is what the protocol draft specifies for `SSH2_AGENTC_ADD_IDENTITY` / `REMOVE_IDENTITY` / `REMOVE_ALL_IDENTITIES` rejections.

**Tests.** Unit tests in `rust/crates/lfs_core/src/ssh_agent/{endpoint,backends,per_key_confirm,transport,identities,loop_runner}.rs::tests` cover the lock/unlock state machine, extension accept/refuse arms (including the `restrict-destination-v00` / `restrict-destination-v01` rejection contract on both the `extension` verb and the `ADD_IDENTITY_CONSTRAINED` constraint list with a separate assertion that destination-less ADDs still surface the generic refusal), the policy promotion contract, the backend dispatcher's Software refusal, the FIDO2 UV-required short-circuit (typed `BackendError::FidoUvNotSupportedViaAgent`) plus the non-UV branch still routes to CTAP2, the parked-prompt resolve / cancel paths, the cert-aware identity builder (bare-only / bare + cert / cert-text-unparseable / unparseable-pubkey / Deny-policy / Software-row / FIDO2-UV-required filter), the IDENTITIES_ANSWER byte layout, the cert-algorithm key_blob recogniser (cert suffix accepted for both `ssh-*-cert-v01@openssh.com` and `sk-*-cert-v01@openssh.com`; bare blobs, truncated blobs, empty blobs rejected), the cert-form SIGN_REQUEST routing (cert blob → row lookup → backend dispatch; bare blob falls through to the typed path; unknown cert pubkey surfaces SSH_AGENT_FAILURE), and the custom framing loop (unknown msg id, empty payload, locked-session listing, full handshake against a duplex stream serving a primed in-memory DB row + cert pair). Integration tests in `rust/crates/lfs_core/tests/ssh_agent_endpoint_test.rs` spin up a real `UnixListener` under a tempdir and drive the wire via `ssh_agent_lib::client::Client` — wire-level lock, extension session-bind, extension unknown, remove-all refusal. End-to-end cert-form sign over a real FIDO2 device is the allow-listed "OS-specific capability" exception — covered by the cross-client matrix entry (`ssh-add -L` + `git push` against our live endpoint with `SSH_AUTH_SOCK` pointed at it), `#[ignore]`-gated as an operator-runnable manual check.

#### Cipher choice — SQLCipher 4.x (AES-256-CBC + HMAC-SHA512)

The app's at-rest DB encryption runs on **SQLCipher 4.x**, statically linked into `lfs_core` via `rusqlite`'s `bundled-sqlcipher-vendored-openssl` feature (vendors both SQLCipher and the OpenSSL it depends on, so cross-compile targets that lack a system OpenSSL — Android NDK, MSVC Windows, iOS device + sim, ARM64 Linux runners — link cleanly). The cipher contract: AES-256-CBC for confidentiality, HMAC-SHA512 for per-page integrity, 256 000 PBKDF2-SHA512 iterations for the page-cipher key derivation off the `PRAGMA key` value. The page-cipher key Rust hands SQLCipher is the 32-byte master DB key produced by Argon2id (Paranoid), pulled out of the OS keychain (T1), or unsealed from the hardware vault (T2); SQLCipher itself does not see Argon2id, only the final 32 bytes.

**Why SQLCipher and not the previous SQLite3MultipleCiphers / ChaCha20 stack.** The pre-Rust era ran on `drift` + `sqlite3_flutter_libs` + SQLite3MultipleCiphers (MC), with MC's default cipher (ChaCha20-Poly1305 — `CODEC_TYPE_DEFAULT`) used implicitly because no `PRAGMA cipher` was ever set. The rusqlite/SQLCipher port had to pick a single cipher for `lfs_core::db`; the choices were MC (any of its schemes) and SQLCipher. Inputs:

- **Wire compatibility.** MC and SQLCipher are wire-incompatible — a database written under one cannot be opened under the other, regardless of cipher choice. The cutover ships as a documented breaking change: existing installs export their state via `Settings → Export .lfs` on the old build and import it on the new build. The release notes call this out; see also [§11 Encryption engine build path](#encryption-engine-build-path) for the rationale (build complexity, not crypto).
- **Single source of truth.** SQLCipher is the older, more battle-tested implementation; rusqlite's `bundled-sqlcipher-vendored-openssl` feature ships the canonical 4.x build (plus its OpenSSL dependency, vendored from `openssl-src`) with no codec-flag matrix. MC's flexibility (six cipher schemes, three KDFs) is a build-surface cost we pay for nothing: only one cipher is ever selected, the choice is project-wide, and the matrix would only matter if individual users wanted to pick.
- **Auditability.** SQLCipher's wire format is fixed and widely reviewed; the `cipher_test_recovery.sh` style toolchain works against any SQLCipher 4 file. MC's wire format depends on the codec/KDF combination at write time, which makes recovery scripts harder to share.
- **Performance.** AES-256-CBC under bundled SQLCipher is fast enough that DB I/O is never the bottleneck for an SSH-client workload — sessions, snippets, known_hosts, ssh_keys are sub-100-KiB tables with low page-churn. ChaCha20's edge on no-AES-NI Arm chips is real but moot for the project's I/O profile.
- **Operational risk envelope.** SQLCipher's HMAC-SHA512 per-page MAC means a tampered page surfaces a load error rather than silently mis-decoding into UB. The cipher is constant-time on every supported platform.

**If a future decision changes ciphers:**

1. Gate the new cipher behind a schema/version marker in `lfs_core::db`, so `Db::open` picks the right cipher at open time and old DBs keep opening under SQLCipher until they have been migrated.
2. Use the same atomic-tmp flow `Db::rekey` already implements (write the new file, fsync, rename, drop the old).
3. Version-bump the `.lfs` archive format to mirror the new cipher header.
4. Migration UI must be opt-in — never run on app startup by surprise.

#### Password strength meter

Informational-only indicator on the Paranoid branch of `SecuritySetupDialog`. Uses a coarse length + character-class heuristic in [`assessPasswordStrength`](../lib/core/security/password_strength.dart) — five-tier enum, pure function, no `zxcvbn` wordlist (would bloat the binary for a feature that never blocks Save). The [`PasswordStrengthMeter`](../lib/widgets/security/password_strength_meter.dart) widget listens on the password controller and renders a coloured bar + localised label, hiding itself when the field is empty. The meter never blocks submit: a four-character password shows a red bar and still commits on OK, by design — users who want short passwords get a warning, not a wall. Labels are localised across all 15 locales (`passwordStrengthWeak` / `Moderate` / `Strong` / `VeryStrong`). The short-password and PIN forms (T1+pw / T2) do not render the meter — those tiers are governed by the rate limiter + hardware lockout, not entropy.

#### Auto-lock

Opt-in, off by default. `autoLockMinutesProvider` (0 = off; presets 1/5/15/30/60) arms an idle timer in [`AutoLockDetector`](../lib/widgets/security/auto_lock_detector.dart) that wraps the app root. The value lives in the encrypted DB (`AppConfigs.auto_lock_minutes`) — storing it there rather than in plaintext `config.json` was deliberate so an attacker with disk access cannot weaken the security control by editing a config file. On expiry `securityStateProvider.clearEncryption()` zeros the in-memory key and [`lockStateProvider`](../lib/core/security/lock_state.dart) flips to `true`; the root widget overlays [`LockScreen`](../lib/widgets/security/lock_screen.dart) blocking interaction until the user re-authenticates (biometric first, MP form as fallback). The tile is always rendered — muted with a tooltip reason when the user is not on a tier with a user-typed secret — so the option never silently disappears.

**Backgrounding lock**: `AutoLockDetector.didChangeAppLifecycleState` locks on `paused` / `inactive` / `hidden` **only when the idle timer is greater than zero**. Locking unconditionally on every minimize was the #1 user complaint with an "Off" timer still triggering lockouts. Treating backgrounding as idle once the user has opted in matches their intent (protect against leaving the screen visible) without surprising users who have explicitly turned the feature off.

**Always-wipe-on-lock policy.** The idle / lifecycle / session-lock triggers all funnel through `_triggerLock`, which fires `dbClose()` over FRB. `dbClose` zeroes SQLCipher's C-layer page-cipher state inside Rust *and* drops the cached DB key from the SecretStore. Wipe is **unconditional** — **don't add an `activeSessions.isEmpty` guard "to preserve reconnect"**. A guard like that leaves the DB key warm whenever any session is connected, flattening T2+password against RAM-forensics-on-locked-machine and kernel-breach. Live-session reconnect is satisfied by the [Session credential cache](#session-credential-cache) (per-session secrets in `mlock`-pinned native memory outside the encrypted store), so closing the store on lock costs the user nothing.

**Unlock re-opens the DB.** Because `_triggerLock` closes the Rust DB handle, every unlock has to re-open it. [`LockScreen._releaseLock`](../lib/widgets/security/lock_screen.dart) pushes the freshly-derived key back into `securityStateProvider` and flips `lockStateProvider` off; a `ref.listenManual<bool>(lockStateProvider, …)` in [`_LetsFLUTsshAppState._wireLockStateListener`](../lib/main_app.dart) observes the locked → unlocked transition and calls `SecurityInitController.reopenAfterUnlock()`, which routes through the controller to `dbInit(key)` over FRB and invalidates every store's in-memory cache so the next read pulls fresh rows. The per-session credential cache is Riverpod-scoped and is deliberately not touched in this path — its whole purpose is to survive the lock.

**Shortcut gate while locked.** Keyboard shortcuts registered on `MainScreen.CallbackShortcuts` sit in a sibling focus scope to `LockScreen`, so `Ctrl+N` / `Ctrl+,` can otherwise bubble through the overlay and hit `_newSession` / `SettingsDialog.show` against a closed DB. `MainScreen._buildKeyBindings` short-circuits every shortcut callback when `lockStateProvider` is true. Pointer hit-testing is already blocked by the `Positioned.fill(LockScreen)` overlay on the root `Stack`, so the gate is specifically a keyboard-path defense.

#### Session credential cache

[`SessionCredentialCache`](../lib/core/security/session_credential_cache.dart) (provided by [`sessionCredentialCacheProvider`](../lib/providers/session_credential_cache_provider.dart)) is the always-wipe-on-lock policy's reconnect escape hatch. It is a thin namespace adapter over the Rust [`SecretStore`](#cached-secrets--rust-secretstore): every read / write fires `secrets_get` / `secrets_put` / `secrets_drop` over FRB, keyed by `sess.password.<id>` / `sess.key.<id>` / `sess.passphrase.<id>`. The plaintext lives only inside Rust as `Zeroizing<Vec<u8>>`; the Dart side carries an empty stub class plus the namespaced ids. Closing the encrypted store on lock leaves the SecretStore intact, so the cached session envelopes survive; clearing the SecretStore (wipe / shutdown) drops every entry atomically.

Lifetime:

1. **Populate** — `ConnectionsNotifier._cachePostAuthCredentials` writes the envelope into the SecretStore immediately after a successful SSH auth, but only when the `Connection` has a stable `sessionId`. Quick-connect sessions have no key to namespace under and are skipped.
2. **Read on (re)connect** — `ConnectionsNotifier._withCredentialOverlay` overlays the cache onto the outgoing `SSHConfig` before calling `transport.connect`. Today the read accessors return null by design — the connect path resolves saved-session credentials through `db_sessions_stage_secrets` directly, so the overlay is a no-op for stored sessions; the layering point stays for future reconnect paths that need it.
3. **Evict on explicit close** — `ConnectionsNotifier.disconnect(id)` and `disconnectAll` evict the matching ids. Transient drops (network blip, app suspend/resume) flip the Connection's state without calling `disconnect`, so the SecretStore entries are preserved across reconnect.
4. **Evict on wipe / reset** — [`WipeAllService`](../lib/core/security/wipe_all_service.dart) accepts a `credentialCacheEvict: VoidCallback?` constructor param and invokes `secrets_clear` over FRB before any file deletion runs. Every runtime reset path (Settings → Reset All Data, forgot-password, DB-corruption wipe-and-restart, T1 / T2 `onReset`) threads it through. The same path also calls [`TerminalScrubber.scrubAll`](../lib/core/security/terminal_scrubber.dart) ahead of file delete so live terminal panes flush their xterm scrollback (a session that recently echoed a password would otherwise leave the bytes in the per-pane `Terminal.buffer.lines` for the rest of the process). The destructive cascade is then bundled Rust-side by [`lfs_core::security::recovery::run_destructive_reset`](../rust/crates/lfs_core/src/security/recovery.rs): one FRB hop composes `db_close` → `wipe::sweep_files` → `wipe_keychain::run` → per-platform hardware-vault primary clear → per-platform hardware-vault biometric overlay clear. The hw-vault arms dispatch through `lfs_os_security::hardware_tier_vault::clear*` for Apple / Android / Windows and through the in-crate `hardware_tier_vault::linux::clear*` orchestrator for Linux — `lfs_core` already depends on `lfs_os_security`, so the recovery module reaches both without a callback hook. `sweep_files` itself additionally calls `app::instance().secrets.clear()` before deleting the on-disk artefacts so cached SecretStore entries clear in lockstep with the files. Hardware-vault arms are best-effort: a `PlatformUnsupported` outcome (no hardware tier on this build) counts as success, and a backend error logs + continues without aborting the cascade. **Coverage tripwire:** `lfs_core::security::wipe::tests::every_known_artefact_is_in_managed_files` references every canonical filename const (config, KDF, hardware-vault blobs across Apple / Android / pre-port platforms) and fails the build when a new artefact is added without updating `MANAGED_FILES` — directly addresses the Android-port rename gap (`hardware_vault_password_overlay_android.bin` → `hardware_vault_android_bio.bin`) that left an orphan file untouched by an earlier sweep.
5. **App shutdown** — the provider's `ref.onDispose` calls `secrets_clear`, dropping every cached secret as the Riverpod container tears down.

Why the cache survives the lock while the DB key does not: the cache plaintext is per-session and per-install, decrypts nothing at rest, and only helps the user's own reconnect UX when the encrypted store closes on lock. The DB key, by contrast, is the at-rest secret — leaving it warm during lock would flatten the threat matrix between T1+pw and T2+pw. Wiping the DB key but retaining the session envelope is the honest trade.

**OS-level session-lock hook.** Idle-timer auto-lock covers "user stopped typing" and mobile lifecycle-paused covers "app went to background". Neither catches the case where the user locks the OS (`Win+L`, `Ctrl+Cmd+Q`, GNOME lock, power-button lock) *without* being idle-minutes-idle inside the app first. [`SessionLockListener`](../lib/core/security/session_lock_listener.dart) closes that gap by routing an OS workstation-lock signal straight into the auto-lock path. The desktop trio (Linux + macOS + Windows) all run through `lfs_os_security::session_lock_listener` Rust paths and surface as a single FRB Stream `subscribeOsSessionLock`; the matching `com.letsflutssh/session_lock` MethodChannel + native plugins remain wired in parallel until end-to-end verification on real macOS + Windows hardware lets us drop them.

| Platform | Source |
|---|---|
| **Windows** | Rust path: dedicated thread creates a hidden message-only window (`HWND_MESSAGE` parent), registers `WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)`, and pumps `GetMessageW` / `DispatchMessageW`; the `WindowProc` filters `WM_WTSSESSION_CHANGE` for `WTS_SESSION_LOCK` (wparam `0x07`) and forwards on the broadcast channel. |
| **macOS** | Rust path: dedicated thread owns its own `NSRunLoop`, registers an `NSDistributedNotificationCenter` observer for `com.apple.screenIsLocked` via an `objc2`-defined `LFSSessionLockObserver` class (`lfs_os_security::session_lock_listener::macos_impl`); observer callback forwards on the broadcast channel. |
| **Linux** | `lfs_os_security::session_lock_listener` (zbus → `org.freedesktop.login1.Session.Lock` signal stream, scoped to the current process's session via `GetSessionByPID`). Native plugin already retired in this slot. |
| **iOS / Android** | No-op — lifecycle-paused already fires on OS lock, so a second channel would double-lock. |

*Why signal-subscription, not polling:* **don't fall back to** `loginctl show-session` / screensaver-state scraping. Polling burns a D-Bus round-trip on every tick, lags the real lock by up to the poll interval, and fires duplicate events across transitions. The signal-subscription path fires exactly once per transition, costs nothing when idle, and matches what every other desktop app on the system bus uses.

#### Process hardening

[`ProcessHardening.applyOnStartup()`](../lib/core/security/process_hardening.dart) is called from `main.dart` before any secrets touch RAM:

* Linux / Android — `prctl(PR_SET_DUMPABLE, 0)`: kernel skips core-dump generation on SIGSEGV and another process under the same UID can no longer `gdb -p` to read our memory without `CAP_SYS_PTRACE`.
* Linux / Android / macOS — `setrlimit(RLIMIT_CORE, {0, 0})`: belt-and-braces against accidental core dumps. `prctl`/`ptrace` above block the attack-paths they target, but on macOS and on a Linux shell that already ran `ulimit -c unlimited` a SIGSEGV would still write `/cores/<pid>.core` or `./core.<pid>`. Zeroing the soft *and* hard limits from inside the process closes that window without touching the user's shell config.
* macOS — `ptrace(PT_DENY_ATTACH, 0, NULL, 0)`: refuses subsequent debugger attach.
* Windows — `SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX)`: suppresses the "stopped working" dialog and tells Windows Error Reporting (WER) not to capture a crash dump for our process. Without this, WER can write a heap snapshot (and optionally upload it to Microsoft) that contains the live SQLite cipher key and decrypted credentials.
* iOS — no-op; sandboxing already covers the relevant attacks.

All calls are wrapped in try/catch; a failed hardening call never blocks startup.

**Process-hardening audit findings.** A pass against the checklist (core dumps, ptrace attach, `mlock` coverage, stack canaries, isolate cross-talk) confirmed the current surface is sound:

* *Core dumps* — covered on every POSIX target (prctl + setrlimit on Linux/Android, ptrace PT_DENY_ATTACH + setrlimit on macOS). Windows WER is disabled for the process via SetErrorMode. No gap.
* *Ptrace attach* — Linux requires `CAP_SYS_PTRACE` after `PR_SET_DUMPABLE, 0`; macOS blocked via `PT_DENY_ATTACH`; Windows equivalent is covered by the WER disable + the debugger-detection Windows already surfaces. No gap.
* *mlock coverage* — every long-lived DB/crypto secret either stays Rust-side in the page-locked `SecretStore` (the orchestrator-staged DB key handed across FRB by id, the `verifyAndDeriveToSecret` SecretRef variant of master-password derive, every export/import Argon2id-derived key the Rust archive path materialises) or, when the bytes must cross into Dart for legacy callers, lands in a [`SecretBuffer`](../lib/core/security/secret_buffer.dart) that `mlock`s / `VirtualLock`s the page. The unlock dialogs route exclusively through the SecretRef path — `verifyAndDeriveToSecret` stages the derived key inside `SecretStore` and the listener consumes it via `secrets_take`, so the AES bytes never appear on the Dart heap. Short-lived values routed through the Dart heap (password entry `TextEditingController`, `Uint8List` arguments to FRB factories) are unavoidable without a wholesale isolate rewrite; the `SecretBuffer.fromBytes` call at every legacy entry point zeros the source after copy.

* *Password marshalling — `Uint8List` end-to-end.* Every FRB hop that takes a user-typed password (master-password `enable` / `verify_and_derive` / `change`, keychain-gate `set_password` / `verify`, tier orchestrator `unlock_keychain_with_password` / `unlock_paranoid` / `first_launch_*_password`) signs as `Vec<u8>` Rust-side and `Uint8List` Dart-side. The dialog's `TextEditingController.text` lands as a `String` once, gets converted via `Uint8List.fromList(utf8.encode(text))` inside the verify / submit closure, and the `String` becomes GC-eligible the moment that closure returns. Best practical bound given Dart's heap-immutable `String` semantics — the typed value can still appear in a heap dump during the dialog's lifetime, but the post-dialog GC reclaims it cleanly without the previous "password lives on the heap until the next major GC pass" tail.
* *Stack canaries* — the Dart VM + `flutter` engine are compiled with `-fstack-protector-strong` by upstream; the project does not link any native code of its own that would opt out. No action.
* *Isolate cross-talk* — Dart isolates have isolated heaps by design; the project itself spawns no secondary Dart isolate for crypto. Argon2id (master-password verify/derive, export/import key derivation, change-password rotation) runs Rust-side under `tokio::task::spawn_blocking` inside the FRB worker pool, so the wall-clock cost stays off the Dart UI isolate without exposing a second Dart heap to manage. No cross-talk surface.
* *Android manifest debuggable flag* — Flutter release builds set `debuggable=false` by default via Gradle; the project never overrides it. No action.

Any finding that would have been expensive (signing / anti-tamper, runtime integrity checks, syscall filtering) is deliberately out of scope — the threat model is a lost device / hostile same-UID process, not a kernel-level attacker.

#### Backup exclusion (Apple)

[`BackupExclusion.applyOnStartup()`](../lib/core/security/backup_exclusion.dart) fires once per launch and opts the app-support directory out of Apple's backup paths. The hook is a no-op everywhere except iOS and macOS.

* **iOS** — sets `NSURLIsExcludedFromBackupKey` on the directory URL. iCloud Backup and encrypted iTunes/Finder backups both honour the flag for the directory and every file under it.
* **macOS** — the same `URLResourceValues.isExcludedFromBackup = true` call writes the `com.apple.metadata:com_apple_backup_excludeItem` extended attribute. Time Machine skips the directory.
* **Android** — covered by [`data_extraction_rules.xml`](../android/app/src/main/res/xml/data_extraction_rules.xml) at the manifest level; nothing to do at runtime.
* **Linux / Windows** — no OS-level backup default the app needs to opt out of.

*Why:* the app-support directory holds the encrypted SQLite file, `credentials.kdf` (Argon2id salt + verifier), the hardware-vault blob, and the password rate-limiter journal. A restored Apple backup on an attacker-controlled device turns into an offline brute-force target against the master password without the per-device hardware binding the live install would have. The backup exclusion keeps those secrets tied to one device's trusted boot chain.

*Idempotency:* the flag is a property of the directory, so re-running on every launch is cheap and self-healing — if a system action or a restore stripped the xattr, the next launch sets it again. The plugin runs `unawaited`, so startup never blocks on the round-trip.

The native side runs Rust-side under `lfs_os_security::backup_exclusion::exclude_from_backup` (`objc2-foundation` → `NSURL.setResourceValue(_, forKey: NSURLIsExcludedFromBackupKey)`); the Dart wrapper calls it over FRB and resolves the path via `path_provider` so the FRB-passed string always points at the same directory layout under `~/Library/Application Support/` that Apple eventually exposes through the bundle identifier.

#### Clipboard hygiene

Two layers cover every "Copy password" / "Copy token" / "Copy SSH key passphrase" button in the app.

Layer 1 is the write path — [`SecureClipboard.setText`](../lib/core/security/secure_clipboard.dart) — which routes the copy through a single FRB call into `lfs_os_security::secure_clipboard::set_secure_text`. The Rust dispatcher selects the per-platform branch and lands the cloud / history opt-outs in the *same* system call as the text itself. Writing the text first and then adding opt-out flags in a second `OpenClipboard` / `setPrimaryClip` session leaves a one-frame window where a clipboard-history watcher can scoop the payload before the flag arrives, so the Rust write owns the whole session. The matching read primitive — `lfs_os_security::secure_clipboard::current_text` — also lives Rust-side so every clipboard hop (write *and* read for the auto-wipe compare-and-clear) crosses one FRB boundary into the single audit perimeter, never Flutter's stock `Clipboard.getData`.

| Platform | Opt-out applied |
|---|---|
| **Windows 10/11** | `CanIncludeInClipboardHistory` + `CanUploadToCloudClipboard` registered-clipboard-format DWORDs set to 0 alongside `CF_UNICODETEXT`. Win+V history skips the entry; cloud sync does not upload it. |
| **macOS** | `NSPasteboard.general` declares `org.nspasteboard.TransientType` and `org.nspasteboard.ConcealedType` in the same `declareTypes` call as `.string`. Every third-party clipboard manager that follows the nspasteboard.org convention (1Password, Maccy, Paste, Alfred) honours these and skips the entry. Universal Clipboard / Handoff remains a residual gap — Apple exposes no first-party opt-out for the iCloud-mirrored copy path, documented here so it stays visible. |
| **iOS** | `UIPasteboard.setItems(..., options: [.localOnly: true, .expirationDate: now+60s])` — Handoff sync is disabled for that write and the entry clears automatically if the app crashes before the Dart-side wipe fires. |
| **Android 13+** | JNI into `android.content.ClipboardManager` via `lfs_os_security::android::clipboard`. `ClipDescription.EXTRA_IS_SENSITIVE = true` set on the `ClipData`'s `PersistableBundle` extras — the system hides the clipboard-preview toast and launchers skip the "share what you copied" affordance. Pre-13 SDKs use the raw `"android.content.extra.IS_SENSITIVE"` key, which OEM clipboard surfaces that backported the hint also honour. |
| **Linux** | `arboard::Clipboard::set_text`. No cloud clipboard default on X11 or Wayland; on a Rust-side failure the Dart wrapper falls through to Flutter's stock `Clipboard.setData`. |

Layer 2 is the auto-wipe — [`ClipboardSecret.copySecret`](../lib/core/security/clipboard_secret.dart) — which schedules a 30-second timer on top of the write. When the timer fires it hands the SHA-256 hex digest of what we wrote to `lfs_os_security::secure_clipboard::compare_and_clear`; the Rust orchestrator reads the live clipboard, hashes it, and writes an empty string through the same per-platform audit perimeter (Win+V opt-out, NSPasteboard transient/concealed markers, UIPasteboard `localOnly`, Android `EXTRA_IS_SENSITIVE`) only when the digests match. If the user copied something else in the meantime, the digests differ and the new value is left alone. Plaintext never crosses FRB on the wipe path — Dart stages only the one-way digest, so a stale 30-second reference to a freshly-copied PEM is not material an attacker reading the Dart heap could weaponise. This catches terminal emulators, browser extensions, and systemd-journal clipboard watchers that read the pasteboard lazily — the iOS 60-second `.expirationDate` is a belt-and-braces fallback for the case where the Dart timer never runs (app killed, reboot, forced OOM).

*Why two layers:* the opt-out flags are a compliance hint to well-behaved consumers. They do not stop a malicious process on the same user session from reading the clipboard — that is what the 30-second wipe addresses. Together they cover the typical attacker shapes: clipboard history / cloud sync (Layer 1) and live paste-sniffers (Layer 2).

*Fallback:* the failure posture is platform-aware. Linux has no cloud-clipboard default — a Rust-path failure there falls through to Flutter's stock `Clipboard.setData` and the wipe timer still runs. Windows / macOS / iOS / Android **refuse** the write on failure and `setText` returns `false` — landing a secret on a cloud-syncing pasteboard without the per-platform opt-out flags would expose it to history rings the 30-second timer cannot retract. Callers (`ClipboardSecret.copySecret`, `qr_display_screen`) propagate the `false` to the UI so the user sees a "copy failed" toast instead of silently leaking material into Win+V / Universal Clipboard / iCloud-synced clipboard / the Android 13+ history preview.

*Terminal-copy integration.* [`TerminalClipboard.copy`](../lib/utils/terminal_clipboard.dart) runs the sensitivity heuristic on the selected text and routes through `SecureClipboard` when the selection matches (PEM private-key markers or a ≥ 200-char base64-alphabet run); non-sensitive selections take the stock `Clipboard.setData` path so routine copies (filenames, command fragments) still benefit from Win+V / Handoff. Without this branch, a terminal user running `cat ~/.ssh/id_ed25519` or `vault kv get secret/api-token` would land the secret in Windows clipboard-history / iCloud-synced pasteboard / Android 13+ preview toast — the 30-second auto-wipe protects the live slot but cannot retract what the sync layers already ingested. Regression guard: `test/utils/terminal_clipboard_test.dart` "sensitive payload goes through SecureClipboard".

#### Password entry widget

Every secret-entry field in the app (master password, SSH key passphrase, export/import password, rate-limited PIN) goes through [`SecurePasswordField`](../lib/widgets/security/secure_password_field.dart). The widget wraps a stock `TextField` with two behaviours the default does not have:

1. **IME hardening.** `autocorrect`, `enableSuggestions`, `enableIMEPersonalizedLearning`, `smartDashesType`, `smartQuotesType`, and `textCapitalization` are all forced off. Every one of those routes keystrokes through an OS service the app does not want to share a master password with — the autocorrect dictionary learns typed tokens, predictive text builds n-gram histories, `personalisedLearning` trains the IME model, smart-quote substitution hands the raw character stream to the text engine. `keyboardType: TextInputType.visiblePassword` picks the Android "password" IME that already disables dictionary learning at the OS level; `autofillHints: [AutofillHints.password]` keeps the field inside the platform password-autofill surface, which routinely suppresses the dictation / share / lookup context-menu items a plain text field would expose. An obscured field's context menu is stubbed out entirely (only select stays), matching the behaviour of native password fields.
2. **Deterministic wipe point.** `State.dispose` calls [`SecretController.wipeAndClear`](../lib/utils/secret_controller.dart) on the caller's controller before the parent `State` drops its reference. The controller's `text` is overwritten with same-length null bytes, then cleared — the `ValueListenable` emits an opaque intermediate so any listener observing the change no longer sees the secret, and the final listenable state holds nothing. `wipeAndClear` is idempotent, so the caller's own dispose can call it again without surprise.

*Residency trade-off (explicit, not wishful thinking):* Dart `String` is immutable and GC-relocatable. There is no hook in Flutter's stock text-input pipeline to keep typed characters out of a Dart-heap `String` — the IME delivers a full `TextEditingValue` each keystroke, the framework stores `.text` on the controller, and the engine renders it. `wipeAndClear` on dispose overwrites the controller's `text` with same-length null bytes before clearing, but the short-lived interim `String`s the framework created still live on the Dart heap until the GC runs. The long-lived derived key is captured into a page-locked `SecretBuffer` at the KDF output, so it stays mlock-pinned for the entire session — the password *input* buffer is the narrow residency gap, not the derived DB key.

*Platform protection via the Flutter engine (not a separate native widget):* Flutter's engine on Android / iOS bridges `obscureText` and `keyboardType: TextInputType.visiblePassword` to the native `TYPE_TEXT_VARIATION_PASSWORD` / `UITextField(isSecureTextEntry: true)`, which the OS honours for IME learning suppression, clipboard-history opt-out, and screen-recording blackout (iOS only). `macOS` is the notable exception — Flutter `TextField` uses `NSTextView`, not `NSSecureTextField`, so `EnableSecureEventInput()` (HID-level keylogger block) is **not** active. A Mac user concerned about keylogger malware must rely on deny-by-default for Accessibility permission in System Settings → Privacy & Security → Accessibility, which is the standard macOS guard. Windows/Linux have no OS-level equivalent primitive for HID-blocking password fields at the widget layer, so `SecurePasswordField` on all five platforms provides the same set of guarantees (IME hardening + wipe-on-dispose) plus whatever the Flutter engine's native bridging layer adds.

*Why no custom `SecureNativeTextField` PlatformView:* **don't add a per-platform PlatformView-backed secure field**. The hardening it delivers over plain Flutter `TextField + obscureText` is marginal on Android / iOS (the engine already bridges to the same native field) and real only on macOS (`NSSecureTextField` triggers `EnableSecureEventInput`). A macOS-only branch costs separate wiring at every password call site, stylistic mismatch with Material widgets, and a platform-view lifecycle bug surface — all for a keylogger-block a user with untrusted Accessibility-permissioned apps has already lost regardless. The unified `SecurePasswordField` is the single code path; the macOS HID-block gap is documented above and in `SECURITY.md`.

#### AES-GCM

AES-256-GCM lives Rust-side in `lfs_core::crypto` (RustCrypto `aes-gcm`). Wire format `[IV (12 bytes)] [ciphertext + GCM tag]`. Dart never sees AEAD plaintext on the outbound path — see [SecretStore + SecretRef](#secretstore--secretref-the-plaintext-discipline-rule). The previous Dart `AesGcm` class is retired.

#### SecureKeyStorage

Thin Dart wrapper that dispatches OS keychain access by platform:

* **Desktop + Apple (Linux / macOS / iOS / Windows)** — production routes through `lfs_os_security::secure_key_storage` via FRB. Linux uses libsecret over `secret-service` (D-Bus → gnome-keyring / KWallet). Apple goes through `security-framework` plus a raw `SecItemAdd` for the biometric path with `SecAccessControl` + `kSecAccessControlBiometryCurrentSet`. Windows uses extern `CredReadW` / `CredWriteW` / `CredDeleteW`.
* **Android** — direct JNI to `java.security.KeyStore` provider `"AndroidKeyStore"` via `lfs_os_security::android::keystore` (no Kotlin shim, no MethodChannel). The wrap key carries `setUserAuthenticationRequired(true)` + `setUserAuthenticationValidityDurationSeconds(60)`, paired with a preceding `BiometricPrompt` invocation by the caller.
* **Tests** — passing a non-null `FlutterSecureStorage` into the constructor forces the legacy mock path so the unit suite can drive in-memory fakes against the same surface.

All methods catch exceptions and return null/false — graceful fallback to plaintext or master-password mode.

```dart
class SecureKeyStorage {
  Future<bool> isAvailable();      // write+read+delete probe
  Future<Uint8List?> readKey();    // null on failure
  Future<bool> writeKey(Uint8List key); // false on failure
  Future<void> deleteKey();
}
```

OS keychain backends: Keychain (macOS/iOS), Credential Manager (Windows), libsecret (Linux), AndroidKeyStore-wrapped GCM frame in `<filesDir>/lfs_secure_storage/` (Android — direct JNI, no `EncryptedSharedPreferences` round-trip). All are **optional** — the app works without them.

**Linux gating:** libsecret emits a non-recoverable `g_warning` to stderr on any call that tries to unlock a locked keyring, and Dart cannot intercept the warning. To keep the console quiet for users who never opt into keychain storage, a shared [`LinuxKeychainMarker`](../lib/core/security/linux_keychain_marker.dart) tracks opt-in with a marker file (`keychain_enabled`) inside the app-support dir. `SecureKeyStorage.writeKey` creates it on success, `deleteKey` clears it, and `readKey` / the `isAvailable` probe refuse to touch libsecret on Linux until the marker is present. `BiometricKeyVault` uses the same marker for its libsecret fallback path so a fresh install on a no-keyring host (WSL, headless container, minimal desktop) never probes libsecret until the user has successfully written at least one secret through either class. The marker is instance-based (injectable `pathFactory`) so tests can point it at a temp dir without binding the `path_provider` channel; `LinuxKeychainMarker.defaultInstance` is the production singleton both callers default to. First write on opt-in still talks to libsecret so any real failure surfaces through the normal error path.

#### SshKeysNotifier

Central SSH key store. The schema + DAO live Rust-side under
`lfs_core::db::ssh_keys` (rusqlite + bundled SQLCipher); the Dart
notifier is an `AsyncNotifier<List<SshKeyEntry>>` that reads / writes
through the FRB DAO surface in `lib/src/rust/api/db.dart` and never
holds a SQLite handle directly.

```dart
final sshKeysProvider =
    AsyncNotifierProvider<SshKeysNotifier, List<SshKeyEntry>>(
      SshKeysNotifier.new,
    );

class SshKeysNotifier extends AsyncNotifier<List<SshKeyEntry>> {
  // build() returns the metadata-only list (PEM bytes stripped).
  // Every Riverpod watcher of sshKeysProvider sees a credential-
  // stripped projection — no PEM bytes pinned in the Dart heap on
  // every list refresh. The rare paths that genuinely need the PEM
  // (archive export staging) call loadAll() explicitly.
  Future<Map<String, SshKeyMetadata>> loadAllMetadata();
  Future<Map<String, SshKeyEntry>>    loadAll();   // PEM-bearing
  Future<void> save(SshKeyEntry entry);            // upsert one
  Future<void> saveAll(Map<String, SshKeyEntry>);  // single-tx replace-all
  Future<void> delete(String id);
  Future<String> importForMerge(SshKeyEntry entry); // dedup-by-fingerprint
  Future<SshKeyEntry> importKey(String pem, String label); // delegates to
                                                            // top-level
                                                            // importSshKey
  void invalidateCache();   // dropped on unlock so post-DB-open reads pull
                            // fresh rows
}

// Top-level helper — keypair generation lives outside the notifier
// because the call has no Riverpod dependency and is exercised from
// non-ref contexts (Tools → SSH Keys → Generate dialog).
Future<SshKeyEntry> generateSshKeyPair(SshKeyType type, String label);
// Routes to lfs_frb::api::keys::keys_generate_{ed25519,rsa} which
// runs on tokio's blocking pool. Returned entry is unsaved — caller
// decides whether to persist via SshKeysNotifier.save / .importForMerge.

class SshKeyEntry {
  final String id, label, privateKey, publicKey, keyType;
  final DateTime createdAt;
  final bool isGenerated;
}

class SshKeyMetadata {
  // Same shape minus privateKey, plus SHA-256 fingerprints computed
  // Rust-side so dedup / "already in store" UI hints don't pull
  // PEM bytes across FRB.
  final String id, label, publicKey, keyType;
  final DateTime createdAt;
  final bool isGenerated;
  final String privateFingerprint;
  final String publicFingerprint;
}

enum SshKeyType { ed25519, rsa2048, rsa4096 }
```

**Session integration:** `SessionAuth.keyId` references a key by ID. Resolved in `SessionConnect._resolveConfig()` via the staging path (`db_ssh_keys_stage_secret`) so the PEM bytes are pulled out of `SecretStore` Rust-side and never round-trip through the Dart heap on the connect path. The SSH layer reads them off the SecretStore id russh receives.

#### OpenSSH certificates

A stored SSH key may carry an OpenSSH user certificate — a public key signed by a trusted CA the server lists under `TrustedUserCAKeys`. Certificates rotate often (typical lifetimes are hours to days) so the storage shape keeps them on a side table that the row listing joins onto when surfaced:

- **Schema.** `ssh_key_certificates` (PK = `key_id` TEXT, FK → `ssh_keys.id` ON DELETE CASCADE). Columns: `certificate BLOB`, `valid_after INTEGER`, `valid_before INTEGER` (both unix seconds matching the OpenSSH wire format), `principals TEXT` (serialised JSON array — opaque, order preserved by the BTree), `critical_options TEXT` (serialised JSON object — `force-command`, `source-address`, etc.), `fingerprint TEXT` (`SHA256:<base64-no-pad>` over the cert blob). One row per stored key — pairing a new cert to the same key replaces the old row via `ON CONFLICT(key_id) DO UPDATE`.
- **Parser.** `lfs_core::keys::parse_openssh_cert(bytes) -> CertSummary` decodes the armored / raw cert through the russh-fork `Certificate::from_openssh` API and projects the principals / validity window / critical options + a stable fingerprint. The russh `Certificate` itself does not cross the FRB boundary — only the typed summary does. Exposed via `keys_parse_openssh_cert` (sync FRB call; the parse is base64 + ssh-key crate walk, well under a millisecond).
- **DAO.** `lfs_core::db::ssh_key_certificates::{get, upsert, delete, list_all, stage_secret_into_store, certificate_secret_id}`. The DAO does not enforce the cert/key fingerprint pairing — the UI presents the cert to the user and the server validates the pairing at userauth time (a mismatched cert simply fails the connect with an auth error). `certificate_secret_id` returns `"key.cert.<id>"` so the SecretStore audit sees a uniform namespace.
- **Connect path.** `lfs_core::connection::auth_compose::prepare_auth` extends the manager-key branch: when `ssh_keys::stage_secret_into_store` succeeds and `ssh_key_certificates::stage_secret_into_store` also returns `true`, the composer emits `PreparedAuthRef::PubkeyCert { key_secret_id, cert_secret_id, passphrase_secret_id }`. The cert-paired branch runs ahead of the plain pubkey branch because cert auth is strictly stronger (CA-signed). The Dart `_authFromConfig` switch maps the variant to `SshAuthPubkeyCertRef`, which the connection actor routes to `Session::connect_pubkey_cert*` (see `rust/crates/lfs_core/src/ssh/mod.rs`). The same precedence rule applies to FIDO2-paired rows — when a cert is attached to a hardware-bound (`backend = 'fido2'`) key, the composer emits `PreparedAuthRef::PubkeySkCert { ... }` ahead of the bare `PubkeySk`, and the connect dispatcher reaches `Session::connect_pubkey_sk_cert_owned` which composes T-1's [`FidoSigner`](../rust/crates/lfs_core/src/ssh/sk_signer.rs) with russh 0.59's `Handle::authenticate_certificate_with<S: Signer>`. See the FIDO2 [Certificate authentication via sk-*](#certificate-authentication-via-sk-) paragraph for the wire-shape detail.
- **Key-manager UI.** The key manager row carries an "Import certificate" / "Remove certificate" action paired with each stored key. Expired certs (`validity.to < now`) render a red dot + "Expired" pill in the row's trailing slot. The principals chip-style summary clips at three visible entries with a `+N` tail; critical-options surface as `Critical options: N` so a user with `force-command` set sees the constraint without opening a detail dialog.
- **Why a side table rather than inline columns.** Most keys do not have a cert attached; inlining a nullable BLOB + four nullable metadata columns on `ssh_keys` would force every key read to pay the BLOB column cost. The join also keeps the cert lifecycle independent — re-importing a rotated cert is a one-row write and never touches the key.

The current shape ships pairing + display + connect-side routing. Auto-renewal (refresh-before-expiry against a CA / signer endpoint) is out of scope for this iteration; the schema reserves no fields for it.

#### Migration framework

Versioned-artefact migration framework running on startup before
`SecurityInitController.bootstrap`. Every on-disk artefact the app persists registers
an [`Artefact`](../rust/crates/lfs_core/src/migration/mod.rs) trait
impl with a target version, and every breaking format change ships
a [`Migration`](../rust/crates/lfs_core/src/migration/mod.rs) trait
impl that walks one step. The framework owns the *file-format
envelope* around the artefact; intra-DB column / table changes are
owned by `lfs_core::db`'s own bootstrap path
([§11 Persistence](#11-persistence--storage)) and are out of scope
here.

The framework is canonical Rust now — `lfs_core::migration::Runner`
+ `Artefact` + `Migration` + `SchemaVersions` all live there. Dart
side carries only a thin shim (`lib/core/migration/migration_runner.dart`)
that re-exports the FRB-generated DTOs and resolves
`getApplicationSupportDirectory()` before calling
`migrationRunOnStartup`. There is no Dart-side runner, registry,
artefact, or migration class.

##### File layout

```
rust/crates/lfs_core/src/migration/
  mod.rs              — Runner (run_on_startup), Artefact + Migration
                        traits, SchemaVersions consts, Report / Step
                        / UnsupportedFutureVersion structs, topo sort
  registry.rs         — Registry + build_app_registry() (composition
                        root — no service-locator scan)
  artefacts.rs        — ConfigArtefact (parses config_schema_version
                        from config.json), KdfArtefact (validates
                        'LFKD' magic + reads the inner version byte
                        from credentials.kdf — corrupt / missing
                        magic / truncated files surface as fatal
                        Err so the migration runner routes through
                        the reset dialog instead of silently
                        treating a torn-write blob as up-to-date)

rust/crates/lfs_frb/src/api/migration.rs
                      — DbMigrationReport / DbMigrationStep /
                        DbUnsupportedFutureVersion FRB mirrors,
                        migration_run_on_startup(support_dir),
                        migration_config_version_on_disk(support_dir)
                        (legacy-state probe used by SecurityInitController)

lib/core/migration/migration_runner.dart
                      — Dart shim. Re-exports FRB DTOs, defines
                        DbMigrationReportHelpers extension (no_op /
                        has_failures / migrated_count) + the
                        `runStartupMigrations()` async entry that
                        resolves support dir and dispatches the FRB
                        call. `currentConfigSchemaVersion()` reads
                        `SchemaVersions::CONFIG` through FRB so the
                        constant lives one place across the workspace.
```

##### Envelope (future use — not registered today)

Framework-managed binary artefacts use a fixed 6-byte header so the
runner can identify the artefact and its on-disk version without
parsing the payload:

```
offset  size  meaning
0       4     magic = ASCII 'L','F','S',0x01
4       1     artefact id  (stable, never reuse a value)
5       1     payload format version
6       N     payload bytes (artefact-specific)
```

No artefact registers an envelope wrapper today — `config.json`
carries its own `config_schema_version` field in the JSON object,
`credentials.kdf` carries its own `'LFKD'` magic + version byte,
and the SQLCipher DB owns its own `PRAGMA user_version`. The
envelope shape stays documented because the next breaking format
bump on a hardware-vault `.bin` will use it; when that lands, the
writer ships in `lfs_core::migration::artefacts` alongside its
`Artefact` impl.

##### Artefact contract — read_version conventions

`Artefact::read_version(support_dir)` is how the runner discovers
what is on disk. The return value drives the runner's decision tree:

| Return value | Meaning | Runner action |
|---|---|---|
| `Ok(-1)` | Artefact does not exist on disk yet (clean install for this slot) | Skip — nothing to migrate |
| `Ok(>= 1)` | Artefact present, header-versioned at the returned value | Walk the Migration chain up to `target_version` |

v1 is the permanent floor for every artefact. Unrecognised headers,
missing schema fields, malformed payloads must return `Err(message)`
— the runner records the failure as a fatal `Report::fatal_error`
entry so the caller can route the user through the reset dialog.
Never return a made-up version for unrecognised state.

`target_version` must be read straight from a
`SchemaVersions::<X>` constant — never inline a number. The constant
is the single source of truth and a registry unit test greps for
stale literals.

##### Runner lifecycle

`SecurityInitController._runMigrations` calls `runStartupMigrations()`
(Dart shim → FRB → `lfs_core::migration::run_on_startup`)
**before** `SecurityInitController.bootstrap`, so the unlock path always reads the
post-migration shape. The runner is idempotent — calling twice in a
row is a no-op on the second call once every artefact has been
brought to its target.

**Panic-safety.** Each `migrate_artefact` call wraps in
`std::panic::catch_unwind(AssertUnwindSafe(…))` so a panic in one
artefact's `read_version` / `migrate` does not abort the whole
startup pass. A panic-derived fatal lands in `report.fatal_error`
with the artefact id and the unwound message, routed through the
same DB-corruption recovery dialog the typed-error fatals use.

For each artefact (in topologically-sorted order — see Topology
below):

1. Call `read_version`. `Ok(-1)` (absent) or `Ok(target)` (already
   current) → skip. `Err` → fatal.
2. If `on_disk > target` (newer-than-known state, usually the
   result of a downgrade after a forward migration ran), record an
   `UnsupportedFutureVersion` in `report.future_versions` and move
   on. The artefact is left untouched so a re-upgrade recovers
   cleanly — never silently rewrite future-version data.
3. If `on_disk < target`, walk the Migration chain step by step.
   For each step:
   - Look up the `Migration` whose `artefact_id` matches and whose
     `source_version == current`. **No registered migration = fatal
     error**: the runner appends a failed `Step` and aborts the
     whole run with `report.fatal_error` set.
   - Call `apply`. If it returns `Err`, record the failure and
     abort. Otherwise advance `current` to `step.target_version` and
     continue.

The runner returns a `Report` (FRB-mirrored as
`DbMigrationReport`):

| Field | Meaning |
|---|---|
| `steps` | Per-step record (artefactId, fromVersion, toVersion, succeeded, error) |
| `futureVersions` | List of `DbUnsupportedFutureVersion` for artefacts ahead of the build |
| `fatalError` | First fatal error (missing migration, apply error, dependency cycle, corrupt header) |
| `noOp` (helper) | True iff no migrations ran and no failures recorded |
| `hasFailures` (helper) | True iff any step failed, any future version was seen, or fatal is set |
| `migratedCount` (helper) | Successful step count — used in the post-run log line |

`SecurityInitController._runMigrations` inspects `report.hasFailures`
and routes the user through `DbCorruptDialog` on any non-clean run:
*Reset & Setup Fresh* runs `_wipeAndRestartFromScratch` (same
full-wipe + first-launch wizard path that the DB-corruption probe
uses); *Quit* leaves the disk untouched so a newer build can re-read
the same artefacts. An uncaught throw from the runner itself lands
on the same dialog — a broken artefact reader is indistinguishable
from a broken artefact from the user's point of view. The init
controller short-circuits the rest of startup whenever
`_runMigrations` returns `false`, because the failure handler has
already taken over. The registered artefacts are `config.json`,
`credentials.kdf`, `security_pass_hash.bin`, and
`hardware_vault_salt.bin`. Every artefact sits at v1 with no
`Migration` impls registered — the runner only performs the
presence + version probe pass. On a clean install the report is
always `noOp == true`, so the app proceeds into
`SecurityInitController.bootstrap` normally. An on-disk artefact
reporting a version above 1 (downgrade after a forward-version
build wrote the file) routes through `UnsupportedFutureVersion`
and the same `DbCorruptDialog`.

##### Atomicity

`Migration::apply` is responsible for atomicity end-to-end. The
standard pattern is to write the new artefact bytes to a sibling
temp file, fsync, then `rename` over the original. If `apply`
returns `Err` before the rename, the original file is untouched and
the runner records the failure as a fatal `Step`.

There is no post-apply validate hook. A migration that needs to
sanity-check its own output does so inside `apply` and returns
`Err` on mismatch — the runner has no backup to swap to and no
separate validate phase to couple rollback to. Migrations that want
true rollback must hold their own `.bak` sibling inside `apply`.

##### Topology — Registry::dependencies

Some artefacts will need to be migrated only after others (the
canonical example: every per-platform `hardware_vault_*.bin` depends
on `config.json` because the vault layout reads its tier and modifier
shape from the post-migration config). `Registry::dependencies` is a
`HashMap<String, Vec<String>>` — every entry in the value list must
run BEFORE the key artefact runs its own migrations. The runner
sorts via Kahn's algorithm and returns
`fatal_error: Some("cycle in migration dependencies")` on any cycle.
Order between independent artefacts is not specified — do not rely
on it; declare the dependency if order matters.

`build_app_registry` carries no dependency edges today — the four
registered artefacts (`config.json`, `credentials.kdf`,
`security_pass_hash.bin`, `hardware_vault_salt.bin`) all live in
the same support directory and migrate independently of one
another. The runner still tolerates dangling edges (an edge whose
endpoint is not in the registered set is skipped, never deadlocks
the indegree map), so a future commit that introduces a
cross-artefact ordering constraint can wire it into the map without
extra care for fresh installs.

##### Reset migrations are out of scope

When the target state of an "upgrade" is "user runs the setup
wizard again, nothing to salvage", the migration framework is the
wrong place. Those route through `TierResetDialog` /
`DbCorruptDialog` → `WipeAllService.wipeAll()` — user-consented
destructive operations, not silent format bumps. The framework is
for silent automated format bumps only; if there is no automatable
transform, escalate to a reset dialog instead.

##### Archive format migrations

`.lfs` archive format migrations live in `lfs_core::archive` (not
in `lfs_core::migration`) because they run at import time, not
startup. Archives whose `schema_version` does not match the current
`SchemaVersions::ARCHIVE` are rejected by the Rust reader
(`lfs_core::archive::read_archive_to_pending`) with the FRB-mapped
`UnsupportedLfsVersionException`. Future breaking format changes
ship a transform inside the archive read path rather than growing a
read-only back-compat surface (see [§3.9 Import → .lfs
format](#39-import-coreimport)).

##### Developer guide — how to ship a format change

When you change the wire format of a framework-managed artefact,
walk this checklist. There is no CI guard that rejects a partial
bump today; the safety net is `run_on_startup` raising a fatal
`Step` on first post-upgrade boot when a registered migration is
missing. Catch the gap at PR time by adding a unit test under
`rust/crates/lfs_core/src/migration/registry.rs` that builds the
registry and asserts every adjacent
`(SchemaVersions::<X>, source_version → source_version + 1)` pair
has a Migration registered.

###### Adding a brand-new envelope artefact

You are persisting a new binary blob and want it to participate in
the framework from day one.

1. Add a `SchemaVersions::<NAME>` constant in
   `lfs_core::migration::SchemaVersions` set to `1` (the permanent
   floor).
2. Implement `<name>_artefact.rs` under
   `lfs_core::migration::artefacts` with an `Artefact` impl. Set
   `id` to the on-disk filename, `target_version` to
   `SchemaVersions::<NAME>`, and `read_version` to file-missing →
   `Ok(-1)`, present → `Ok(target_version())` (or parse the
   embedded version byte from the envelope).
3. Register the artefact in `build_app_registry`. If your
   artefact's layout depends on another (e.g. it reads tier from
   `config.json`), insert the dependency into
   `registry.dependencies` in the same place.
4. Persist the blob through an atomic writer (tmp + rename + chmod)
   from the producing module. Never write straight to the live
   path.
5. Add a unit test inside the module exercising each
   `read_version` path (missing file, malformed, current version).
   Pass a `tempfile::TempDir` so the test owns its directory.

No `Migration` impl is needed yet — the artefact ships at v1 from
the start and the runner is a no-op on every install.

###### Bumping an existing artefact's format

You are changing the on-disk shape (added a field, renamed a key,
re-arranged a struct) of an artefact already in the registry.

1. Bump the `SchemaVersions::<ARTEFACT>` constant by exactly one.
   Skipping versions is forbidden; the runner walks the chain step
   by step and expects every intermediate migration to exist.
2. Implement a struct under
   `lfs_core::migration::artefacts::migrations` with a `Migration`
   impl covering the single
   `(artefact_id, source_version → target_version)` transition.
   Body: read the v(N-1) bytes, transform in memory, write the
   v(N) bytes atomically. Return `Err` on any failure.
3. Register the migration in `build_app_registry` via
   `registry.migrations.push(Box::new(<Type>))`. Duplicate
   `(artefact_id, source_version)` pairs are rejected by a registry
   unit test — there is exactly one path between adjacent versions.
4. Update the writer in the producing module to stamp the new
   version constant. Update any reader to handle the new payload
   shape. Existing data on disk continues to read correctly
   because the migration upgrades it on next startup.
5. Add a unit test under
   `rust/crates/lfs_core/src/migration/artefacts.rs` (or a sibling
   migrations module) that builds a v(N-1) file in a `tempfile::TempDir`,
   runs the migration, and asserts the resulting file matches the
   v(N) shape. Add a second test confirming the migration is in
   `build_app_registry`'s migrations list.
6. Document the bump under `docs/ARCHITECTURE.md §11 Persistence`
   (if the artefact is a top-level data file) or in the relevant
   `core/security/...` doc reference. Mention what the change is
   and why so the next agent can read intent without grepping
   commits.

The next install that boots will run the new migration once on
startup, log the success step, and never run it again because
`read_version` now returns `target_version`. A user who downgrades
to the prior build after the bump runs lands on the
`UnsupportedFutureVersion` path — the file is left intact so a
re-upgrade recovers.

###### Adding a `.lfs` archive format migration

You are bumping the archive `manifest.schema_version`. Archive
migrations are part of `lfs_core::archive`, not
`lfs_core::migration`. See [§3.9 Import → .lfs
format](#39-import-coreimport) for the import-path transform shape.

###### Deferred v1 improvements

Three improvements were designed but intentionally not shipped at
the v1 floor, because each one needs an archive format bump (or a
new native dependency). With every artefact reset to v1, the next
format bump should be a single coordinated v1 → v2 step, not a
drip of back-compat flags inside v1:

- **Fast wrong-password canary.** An 8-byte sentinel encrypted with
  the Argon2id-derived key, placed at a known offset before the main
  AEAD blob, so a wrong password rejects in microseconds instead of
  processing the whole ciphertext to fail GCM tag verification.
  Requires a format bump (new header field) or a reserved offset
  inside the KdfParams block; both are v1 → v2 changes.
- **Per-entry `schema_version`.** Each JSON entry (sessions, tags,
  snippets, …) carries its own schema version so the framework can
  evolve one entry type without bumping the whole archive. Requires
  wrapping each entry's top-level shape from `[...]` to
  `{"schema_version": 1, "entries": [...]}` — again a v1 → v2 change.
- **Zstd compression.** Would reduce JSON-heavy archives by 30–50 %.
  No stable pure-Dart zstd implementation on pub.dev today; pulling
  in a native-code FFI package would break the self-contained-binary
  invariant or require a per-platform fallback. Pick this up only if a pure
  Dart zstd decoder lands or if the binary-size cost of bundling
  one is judged acceptable.

Streaming archive decode (reading entries from an `InputFileStream`
instead of loading the whole decompressed archive into memory) is a
separate axis and sits in the same deferred bucket — the current
50 MiB cap on encrypted archive size keeps the in-memory cost bounded,
and encrypted archives have to be decrypted fully before the ZIP is
readable at all, so streaming would only benefit the unencrypted path
without touching the hot case. Revisit when a user reports a
real-world archive pushing the cap.

###### What the framework will not do for you

- **Reset migrations** — see "Reset migrations are out of scope"
  above. If the upgrade has no automatable transform, escalate to
  `TierResetDialog` / `DbCorruptDialog` instead.
- **Cross-artefact migrations in a single Migration** — one migration
  covers exactly one `(artefactId, fromVersion → toVersion)`. If a
  format change touches two artefacts, ship two migrations and
  declare the dependency between them via `declareDependency`.
- **Auto-rollback after `validate()` returns false** — see
  "Atomicity and rollback" above. If your migration needs
  post-validate rollback, hold a `.bak` sibling inside `apply`
  yourself.
- **Skipping a version** — every adjacent pair `(N-1, N)` must have
  a registered migration. The runner does not jump versions.

---

### 3.7 Configuration (`core/config/`)

#### AppConfig model

```dart
class AppConfig {
  final TerminalConfig terminal;
  //   fontSize: 6-72 (default 14.0, type double)
  //   theme: 'dark'|'light'|'system'
  //   scrollback: ≥100 (default 5000)

  final SshDefaults ssh;
  //   keepAliveSec: default 30
  //   defaultPort: default 22
  //   sshTimeoutSec: default 10

  final UiConfig ui;
  //   windowWidth/Height
  //   uiScale: 0.5-2.0
  //   showFolderSizes: bool
  //   toastDurationMs: int (default 4000)

  final int transferWorkers;      // 1+ (default 2)
  final int maxHistory;           // ≥0 (default 500)
  final LogLevel? logLevel;       // null = off; info/warn/error = threshold
  final bool checkUpdatesOnStart;
  final String? skippedVersion;
  final String? locale;             // null = OS auto-detect, or any of 15 supported locale codes

  // copyWith uses sentinel pattern for nullable fields:
  // copyWith(skippedVersion: null) clears, omitting preserves
  // copyWith(locale: null) clears, omitting preserves
}
```

#### ConfigNotifier

```dart
class ConfigNotifier extends Notifier<AppConfig> {
  Future<void> update(AppConfig Function(AppConfig) updater); // mutate + persist
  Future<void> load();  // re-read the actor's snapshot into state
  @protected Future<void> persist(AppConfig config); // disk-write seam
}
```

`update()` applies the transform, publishes the new state synchronously (so the UI reflects the change immediately), then arms a 300 ms debounce that coalesces rapid bursts (slider drags, fast toggling) into one trailing write. The eventual write routes through `persist()` → `_saveAppConfigToDisk()`, which pushes the typed value to the `lfs_core::config_store` actor (`config_store_set_typed`, sync FRB) and forces a flush (`config_store_flush`, **async** — the atomic write + fsync runs on a Rust blocking worker, never the UI isolate). Range clamping (`fontSize` ∈ [6, 72], etc.) happens Rust-side in `AppConfig::sanitized` during the typed round-trip.

**Save-path invariant — the store is pinned once, never re-inited per write.** `_saveAppConfigToDisk` does *not* call `path_provider` or `config_store_init` on each save. `config_store_init` is not a no-op: it does a synchronous on-disk read + JSON parse and replaces the in-memory snapshot (clearing any pending write). Running it per settings change — a sync FRB call on the UI isolate — stalled the interface for a beat after every toggle, and the disk reload could also drop an unflushed `sync_*` sub-bag change. The support dir is resolved once at startup (`bootstrapRustConfigStore` → `config_store_init`) and read back from the actor; the save path only reads the live sync sub-bag in memory, sets the typed value, and flushes. Tests that drive a save construct a fresh notifier against a temp dir, so each calls `bootstrapRustConfigStore` in `setUp` to pin the process-global singleton (`Store::init` re-pins on every call).

##### `config_schema_version` cutovers

| Version | Wire-shape | Migration |
|---|---|---|
| **v1** (current) | Bank-style security tier model + every persisted `AppConfig` field the runtime needs. `config_schema_version` is stamped explicitly on every write; a missing field on a parseable JSON object is treated as v1 by `ConfigArtefact::read_version` so a hand-edited file without the stamp does not trigger reset. `security_probe_cache` is always an explicit value (object or `null`). `security_modifiers` carries `{password, biometric}` only — no legacy aliases. Hardware (T2) tier is mandatory-password (`SecurityTierModifiers::is_valid_for_tier` rejects `password=false`). The `sync_*` family persists WebDAV sync endpoint config + last-push state; plaintext credentials live in `SecretStore`, only the ref-ids land on the JSON. `strip_for_export` drops every `sync_*` key before the JSON enters an `.lfs` archive — sync state is per-install, not portable. `recordings_storage_cap_bytes` holds the recorder LRU byte ceiling; sanitiser clamps zero / above 1 TiB to the 500 MiB default. | — |

The next bump follows the framework's [§3.6 → Bumping an existing artefact's format](#bumping-an-existing-artefacts-format) checklist — every step lives in one place so the next bump doesn't have to re-derive the contract.

---

### 3.8 Deep Links (`core/deeplink/`)

`DeepLinkHandler` is a thin URI pump: it owns the `app_links`
subscription (the Flutter plugin that drives the custom-scheme intent —
stays Dart) and routes every URI through the Rust
[`DeeplinkDispatcher`](#deeplinkdispatcher--lfs_coredeeplink) via
`deeplinkDispatch`. Routing, dedup, scheme dispatch, and QR-payload
staging all live in `lfs_core::deeplink`. The app registers **no
file-extension associations** (see §12) — `.lfs` archives import via
drag-drop / the in-app picker, never an OS file hand-off — so a
`file://` / `content://` URI is not ours to open and routes to
`Unknown`.

```dart
class DeepLinkHandler {
  // The only scheme recognised by the Rust dispatcher:
  //   letsflutssh://connect?host=X&user=Y[&port=Z]
  //   letsflutssh://import?d=BASE64URL (deflate + base64url JSON)

  // Each URI from `app_links` (cold-start `getInitialLink` + warm
  // `uriLinkStream`) is dispatched to `lfs_core` via FRB; the
  // returned `DbDeeplinkOutcome` is a sealed Dart enum with one
  // variant per supported action plus `Unknown` / `Duplicate`. The
  // handler switches on the variant and fires the matching callback.

  void Function(SSHConfig)? onConnect;
  void Function(QrDecodedSource)? onQrImport;
  void Function(int found, int supported)? onQrImportVersionTooNew;

  // Static helper for the deeplink fuzz suite + flutter_test
  // surface — routes through `lfs_core::deeplink::parse_connect_uri`
  // in production with an in-file Dart fallback for tests that
  // don't load the FRB native lib.
  static SSHConfig? parseConnectUri(Uri uri);

  void dispose(); // cancels subscription, nulls all callbacks
}
```

#### `DeeplinkDispatcher` — `lfs_core::deeplink`

| Concern | Owner |
|---|---|
| Dedup state (last URI + timestamp) | `DeeplinkDispatcher::inner` (mutex-guarded). Window: 2 s — covers the cold-start `getInitialLink` + `uriLinkStream` double-fire without blocking a deliberate re-tap of the same QR after the user comes back from background. |
| Scheme dispatch (`letsflutssh` only) | `route()` pure function. `file://` / `content://` (and any other scheme) fall to `Unknown` — the app claims no file extensions. |
| Custom-scheme action (`connect` / `import`) | `route_custom_scheme()` matches on the URI authority and delegates to `parse_connect_uri` (connect) or `stage_qr_import` (import). |
| QR payload decode + staging | `stage_qr_import()` calls `qr_codec_decode::try_decode_payload()` → `ImportRegistry::insert(handle_id, pending)`. The `try_decode_payload` enum splits version-too-new from generic decode errors so the dispatcher can emit `QrImportRejected { found, supported }` as a typed outcome. |
| Outcome shape | `DeeplinkOutcome` enum: `Connect{host,port,user}` / `QrImport{handle_id,schema_version}` / `QrImportRejected{found,supported}` / `Unknown` / `Duplicate`. The FRB adapter mirrors this as `DbDeeplinkOutcome` and hydrates the QR variant with a full `DbImportPreview` (looked up off the staged handle) so the Dart caller doesn't round-trip back. |

---

### 3.9 Import (`core/import/`)

| File | Purpose |
|------|---------|
| `import_service.dart` | Thin Dart wrapper over the Rust apply driver: `applyResultViaRust(ImportResult, refreshAfterImport)` serialises the result to the staged-import JSON envelope, calls `dbImportStage` + `dbImportApply` (FRB → `lfs_core::archive::apply_pending_import`), then runs the caller's cache-refresh hook. Hosts `ImportSummary` (per-type counters consumed by the success toast) and `LfsImportRolledBackException` (raised on replace-mode failure so the UI shows "data restored" — the surrounding sqlite transaction guarantees the rollback). All collisions, junction inserts, folder-hierarchy reconstruction, and replace-mode rollback live Rust-side now |
| `key_file_helper.dart` | Shared helpers for SSH key files on disk: `tryReadPemKey`, `isEncryptedPem` (decodes OpenSSH v1 KDF-name field, or sniffs PKCS#1 / PKCS#8 armor), `basename`, `isSuspiciousPath` — centralises the rules used by the OpenSSH-config importer, the `~/.ssh` scanner, and the settings file-picker. PPK files are detected here too via `PpkCodec.looksLikePpk` and converted in-place to OpenSSH PEM (see [PPK codec](#ppk-codec--puttys-private-key-format)) |
| `openssh_config_importer.dart` | Build `ImportResult` from `~/.ssh/config`. Pure — takes a `PemKeyReader` for file isolation. Dedups identity keys within the import by SHA-256 fingerprint; hosts with unreadable IdentityFiles are still imported (blank credentials) and reported via `hostsWithMissingKeys`. Entry point for the SSH-config import UI in Settings → Data — see [§5.5 Settings](#55-settings-featuressettings) |
| `ssh_dir_key_scanner.dart` | Scan a directory (typically `~/.ssh`) for PEM private-key files. Pure — takes a `DirectoryLister` + `PemKeyReader` for full test isolation. Skips obvious non-keys (`*.pub`, `known_hosts*`, `config`, `authorized_keys*`). Used by the "Import SSH keys from ~/.ssh" tile — selected candidates are persisted through `SshKeysNotifier.importForMerge` so fingerprint-duplicate keys are not re-added |

#### .lfs format

```
[salt 32B] [IV 12B] [encrypted payload + GCM tag 16B]

payload = ZIP archive:
  manifest.json              ← schema_version (now v3), app_version, created_at, optional sync_origin (v2+)
  sessions.json              ← session metadata with credentials (toJsonWithCredentials)
  empty_folders.json         ← list of empty folder paths
  keys.json                  ← manager SSH keys + per-backend payload (see table below)
  config.json                ← app configuration
  known_hosts                ← TOFU host key database (LetsFLUTssh wire format, not real OpenSSH)
  tags.json                  ← tag definitions (id, name, color)
  session_tags.json          ← session→tag assignments
  folder_tags.json           ← folder→tag assignments
  snippets.json              ← snippet definitions (id, title, command, description)
  session_snippets.json      ← session→snippet links
  ssh_key_certificates.json  ← v3: paired OpenSSH certs (key_id, blob, validity, principals, options, fingerprint)
  webdav_session_details.json ← v3: per-WebDAV-session config (base_url, username, auth_method, secret-id pointer)
  s3_session_details.json    ← v3: per-S3-session config (access_key_id, region, endpoint, secret-id pointer)
  sftp_bookmarks.json        ← v3: per-session SFTP bookmarks (id, session_id, remote_path, label, created_at)
  port_forward_rules.json    ← v3: per-session port-forward rules (Local / Remote / Dynamic)

Encryption: AES-256-GCM
Key: Argon2id(password, salt, m=64 MiB, t=3, p=1) — canonical in
  [`lfs_core::security::master_password::KdfParams::defaults`](../rust/crates/lfs_core/src/security/master_password.rs),
  mirrored at startup into
  [`KdfParams.productionDefaults`](../lib/core/security/kdf_params.dart)

Wire format for v3 encrypted archives (current writer):
  [ 'LFSE' (4) | version = 0x03 (1) | KdfParams block (≤ 16) |
    salt (32) | iv (12) | ciphertext + GCM tag ]

The KdfParams block carries the algorithm id (1 byte, `0x01` = Argon2id)
followed by the algorithm-specific parameters (for Argon2id: memoryKiB
u32 BE + iterations u32 BE + parallelism u8 = 9 bytes). The reader picks
up the exact cost used to write the archive — a future release can tune
parameters without having to break or re-encrypt existing files.

**Header-bound AAD (v0x03).** The encoder now binds the entire
pre-IV header (magic + version + KDF params + salt — 52 bytes) into
the AES-GCM AAD. An attacker who flips a header byte to coerce
different KDF params (drop memory cap, swap algo id, replace salt)
invalidates the AEAD tag rather than feeding cooked params into the
verifier. The IV is *not* in AAD — its uniqueness is the GCM
contract; binding it would be redundant. v0x02 envelopes (pre-AAD
legacy) still decode through a fallback branch with empty AAD so
existing exports keep importing; new exports always emit v0x03.

Argon2id is the only supported KDF. Archives with a header version byte
other than `0x02` / `0x03`, missing `LFSE` magic, or no manifest are
rejected at import with `UnsupportedLfsVersionException` — users must
re-export from the current app version. Future breaking format changes
ship a transform inside `lfs_core::archive::read_archive_to_pending`
(the import path) — see [§3.6 → Migration framework](#migration-framework)
for the architectural shape; archive migrations live with the archive
reader rather than the on-disk migration framework because they run
at import time, not startup.

| On-disk form | Version byte | KDF | Notes |
|---|---|---|---|
| v1 (LFSE legacy) | `0x02` | Argon2id @ header params | Pre-AAD envelopes. Decoded through a fallback branch with empty AAD; never emitted by current writer. |
| v1 (LFSE current) | `0x03` | Argon2id @ header params | Current writer. Pre-IV header bound into AES-GCM AAD. |

Import caps bound Argon2id params from an untrusted header
(`MAX_IMPORT_MEMORY_KIB = 1 GiB` desktop / 512 MiB mobile,
`MAX_IMPORT_ITERATIONS = 20`, `MAX_IMPORT_PARALLELISM = 4`) so a
hostile archive cannot pin every core for tens of seconds before
the wrong-password check fires. The parallelism cap was tightened
from 16 to 4 (Argon2id production tuning never exceeds 4 lanes
anyway; the higher limit was just DoS surface). Unencrypted ZIP
archives keep their `PK\x03\x04` magic and are handled
separately.

On iOS and Android the effective ceiling drops to 512 MiB
(`mobileImportArgon2idMemoryKiB`) — the Android OOM killer on a 2 GB
baseline device will terminate the process well before the 1 GiB
ceiling is reached, and legitimate exports never need more than the
production default (64 MiB) anyway. **Don't try to derive the cap
from `ProcessInfo.maxRss`** — `maxRss` is the current process peak,
not total physical RAM, so cold-start under-estimates (tiny peak →
spurious "malformed header" rejections of valid archives) and
long-running warm sessions over-estimate. A flat floor matches the
real DoS threat; probing true total RAM would require a new
per-platform method channel purely for this check, which is
disproportionate to the bug. `debugMemoryProbeOverride` stays as
the test injection point.

Unencrypted variant: export dialog accepts an empty master password after
a confirmation step. ExportImport.export() then writes the raw ZIP
bytes (the `PK\x03\x04` local-file-header magic) instead of the
header + salt + IV + ciphertext + tag layout.

Import-side validation: `ExportImport.probeArchive(path)` classifies the
picked file into `{unencryptedLfs, encryptedLfs, notLfs}` before any
password prompt:
  * ZIP magic + at least one marker entry (`manifest.json`,
    `sessions.json`, `config.json`, `keys.json`) → `unencryptedLfs`,
    password prompt skipped.
  * ZIP magic but no marker → `notLfs`, rejected with a localized
    `errLfsNotArchive` toast. This catches e.g. an `.apk` picked by
    mistake on Android SAF, which ignores the `allowedExtensions: ['lfs']`
    filter for unregistered MIME types and lets the user select any file.
  * Non-ZIP header → `encryptedLfs`; password prompt runs and the manifest
    check inside `_decryptAndParseArchive` is the final arbiter.
```

Schema versioning: `ExportImport.currentSchemaVersion` reads
`lfs_core::migration::SchemaVersions::ARCHIVE` (currently **v3**) through
a sync FRB getter so the constant lives one place across the workspace.
The manifest is written on every export and validated on import: when
`read_archive_to_pending` parses a `schema_version` greater than the
build's `SchemaVersions::ARCHIVE` it returns `Error::ArchiveFutureVersion`,
which the Dart `openArchiveWithTypedErrors` wrapper translates into
`UnsupportedLfsVersionException`. GCM's auth tag already protects
archive integrity end-to-end, so no separate content hash is stored
in the manifest.

##### What travels — per backend / per child table

The keys composer always emits a `backend` discriminator on each row;
the payload that travels depends on it. Device-bound backends ship a
public-half-only stub so the receiving device can see "a key with
this label was on the other host" without the private side leaking:

| Backend | Travels | Survives on the receiving device? | Notes |
|---|---|---|---|
| `software` | private_key, public_key, key_type, label | Yes — full round-trip | The classic case; private PEM rides inside the GCM-encrypted envelope. |
| `fido2` (sk-*) | public_key, key_type, label, credential_id, application_string, has_user_verification | Yes — token portable across hosts | Plug the same YubiKey / Solo / Nitrokey into the new device and sign works without re-import. |
| `pkcs11` | public_key, key_type, label, pkcs11_uri, pkcs11_token_serial, pkcs11_object_id, pkcs11_object_label | Yes — token portable | Module path is the per-host install location and is NEVER on the wire; resolved locally on first use via the well-known-paths scan keyed on `pkcs11_token_serial`. Miss surfaces a one-shot "Choose PKCS#11 module" picker. |
| `enclave` | public_key, key_type, label (stub) | No — re-generate on this device | Apple Secure Enclave; private key is bound to one Mac / iPhone. The imported row lands with `imported_as_stub=1`; Key Manager renders desaturated with "Re-generate here" / "Remove" actions. |
| `hello` | public_key, key_type, label (stub) | No — re-generate on this device | Windows Hello / NCrypt; private key is bound to one PC's TPM. Same stub UX as `enclave`. |
| `tpm` | public_key, key_type, label (stub) | No — re-generate on this device | TPM 2.0 (Linux ESAPI or Windows PCP silent); the wrapped blob is per-TPM. |
| `keystore` | public_key, key_type, label (stub) | No — re-generate on this device | Android Hardware Keystore / StrongBox; private key is bound to one phone's TEE. |

Child-table portability — every child row is keyed by its parent's id
(session_id or key_id) and rides with the parent's row:

| Table | Wire fields | Secret discipline |
|---|---|---|
| `ssh_key_certificates` | key_id, certificate, valid_after, valid_before, principals, critical_options, fingerprint | Cert blob is the public half of a CA-signed pair; safe to travel verbatim. Apply drops the row with a warning when the parent key didn't land. |
| `webdav_session_details` | session_id, base_url, username, auth_method, trusted_cert_pem, insecure_skip_verify, credential_secret_id | The password / bearer token lives on the local `password` column (encrypted at rest by SQLCipher), but the archive / sync codec ships only the opaque pointer (`session.webdav.<session_id>`) rather than the bytes. The receiving device finds the SecretStore slot empty and surfaces "re-enter password" on first connect. `trusted_cert_pem` (PEM blob, optional) and `insecure_skip_verify` (boolean) flow through verbatim — the receiver inherits the same TLS posture. |
| `s3_session_details` | session_id, access_key_id, region, endpoint, path_style, default_bucket, default_prefix, trusted_cert_pem, insecure_skip_verify, secret_access_key_secret_id | Access key id is the public half of the AWS credential and rides verbatim; the secret access key bytes persist locally on the `secret_access_key` column (SQLCipher-encrypted at rest) but stay off the wire — the codec ships the opaque pointer. `trusted_cert_pem` / `insecure_skip_verify` mirror the WebDAV columns so both transports share one self-signed-endpoint surface. |
| `sftp_bookmarks` | id, session_id, remote_path, label, created_at | Full round-trip; tombstone-aware. |
| `port_forward_rules` | id, session_id, kind, bind_host, bind_port, remote_host, remote_port, description, enabled, sort_order, created_at_ms | Full round-trip. |

Every archive entry on the wire is independently optional —
each new typed slot on `PendingImport` is `Option<...>`, so an
archive that ships only a subset of entries parses cleanly. The
forward-version gate in `read_archive_to_pending` rejects any
manifest whose `schema_version` is greater than
`SchemaVersions::ARCHIVE`.

#### Import modes

| Mode | Behavior |
|------|----------|
| **Merge** | Adds new sessions; on id collision, inserts a fresh UUID with a `(copy)` suffix (same semantics for tags/snippets). Manager keys deduplicate by private-key fingerprint via `SshKeysNotifier.importForMerge()` — identical keys reuse the existing id. Config apply failure is logged but doesn't abort the merge |
| **Replace** | Full replacement of sessions from archive. Tags / snippets / known_hosts are additionally wiped when the corresponding `includeX` flag from the preview dialog is set — so a user who checks "Tags" with an empty archive ends up with zero tags. Unchecked types are left untouched. A failure at any step triggers a full rollback of the snapshot (sessions + folders + config + tags + snippets + known_hosts) |

#### Apply driver — Rust-routed

`applyResultViaRust(result, refreshAfterImport)` is the only Dart-side
entry point. It stages the `ImportResult` into a `DbStagedImport`
JSON envelope (one `*_json` field per entity table — sessions, keys,
tags, snippets, junction links, empty folders, known_hosts text),
hands it to `dbImportStage` for handle minting, then calls
`dbImportApply` with a `DbApplyOptions{mode, applyX...}` selector
mask. The Rust driver
([`lfs_core::archive::apply_pending_import`](../rust/crates/lfs_core/src/archive/apply.rs))
does the heavy lifting:

- **Manager keys first.** Imported under a fingerprint-dedup so identical keys reuse the existing id; returned id map remaps every `Sessions.keyId` reference. Sessions pointing at a key that wasn't imported get `keyId` cleared so the row still inserts without a `FOREIGN KEY constraint failed` on `Sessions.keyId → SshKeys.id`
- **Folder hierarchy reconstruction.** `apply_folder_tree` splits each session's `folder` path on `/`, mints a UUID per segment, builds a path→id map, and rewrites session `folder_id` references; `empty_folders.json` paths feed the same map so the tree is complete on apply. Folder labels matching Win32 reserved device names (`CON`, `PRN`, `AUX`, `NUL`, `COM1-9`, `LPT1-9`, case-insensitive, extension stripped) emit a soft `Archive` warning at import time — labels are session-tree display strings, not filesystem paths, so the row still lands but the warning hints that the name may render oddly when the user later exports / drags the label into a path context. Folder→tag link import currently ignored — see §3.9 "Folder-tag stub" below
- **Junction inserts.** Session→tag and session→snippet links route through `SessionTags` / `SessionSnippets` once the side tables land; links referencing a non-imported target are silently dropped (would FK-fail otherwise)
- **Replace-mode atomicity.** The whole apply runs inside a single `Connection::transaction()` — replace mode wipes existing sessions / tags / snippets / known_hosts in the same transaction, so a mid-apply failure rolls the DB back to the pre-import state automatically. The Dart wrapper catches the failure and rethrows `LfsImportRolledBackException` so the UI shows the "import failed — data restored" toast
- **Known-hosts text** is appended verbatim to the host-key file via the registered `KnownHostsAdapter`

The Dart `ImportSummary` is rebuilt from the Rust `DbApplyResult` row counts (`sessionsApplied`, `foldersApplied`, `keysApplied`, `tagsApplied`, `snippetsApplied`, `knownHostsApplied`) plus the source `ImportResult.skippedSessions` (decode-time loss, surfaced verbatim). `formatImportSummary()` in `utils/format.dart` renders it as the success toast (`Imported N sessions, K SSH keys, T tags, S snippets, …`) so users see what was actually persisted instead of only the session count. `SqliteException`s that carry a PEM private key in their bound parameters are run through `redactSecrets()` in `utils/sanitize.dart` before reaching the toast or the log file.

**Cache refresh.** Rust writes through the DB directly without going through Dart-side per-store add callbacks, so the in-memory `sessionStore`/`tagStore`/`snippetStore` caches are stale until reloaded. The caller passes a `refreshAfterImport` thunk that calls `sessionStore.load()` + `tagStore.loadAll()` + `snippetStore.loadAll()`; `applyResultViaRust` invokes it once on success. Riverpod `FutureProvider`s (`sshKeysProvider`, `tagsProvider`, `snippetsProvider`) get invalidated by the surrounding flow (`import_flow.dart::_invalidateImportProviders`).

**Config restore stays Dart-side.** The Rust apply ignores the `config_json` field on `DbStagedImport` — `config.json` is a Dart-managed artefact (see [§3.6 → Migration framework](#migration-framework)) and the caller restores it via `ref.read(configProvider.notifier).update((_) => importResult.config!)` after `applyResultViaRust` returns.

**Folder-tag stub.** Folder→tag link import is currently dropped — `ExportFolderTagLink` carries the folder PATH (not the id) but the Rust apply driver keys junctions on `folder_id`. Restoring the link table requires the Dart envelope to resolve paths to freshly-minted folder ids the same way `apply_folder_tree` does for sessions; tracked but not implemented. Folder→tag is the only pre-Rust feature the apply path doesn't yet round-trip — sessions, keys, tags, snippets, session-tags, session-snippets, empty folders, known_hosts, config all survive.

**Session reload after linked-entity delete:** `Sessions.keyId` is declared with `onDelete: KeyAction.setNull`, and `SessionTags` / `SessionSnippets` cascade on FK, so deleting a key / tag / snippet in the DB is correct on its own. The in-memory `sessionProvider` cache doesn't see the cascade, though — the delete UI handlers (`key_manager_dialog`, `tag_manager_dialog`, `snippet_manager_dialog`) each call `sessionProvider.notifier.load()` after the delete so the session tree picks up the nulled `keyId` (the "invalid session" warning icon appears immediately) and the derived tag / snippet lists drop the stale link.

The OpenSSH config parser honours wildcard defaults. `Host *` / `Host *.internal` blocks emit no entries of their own, but their directives cascade onto every concrete host matching the pattern using OpenSSH's first-value-wins rule — so the common idiom "put `Host *` at the end of ~/.ssh/config for defaults that concrete hosts override" works as expected. Negation patterns (`!pattern`) block a wildcard block from applying to a matching host. `IdentityFile` entries accumulate across every matching block in file order (OpenSSH tries them sequentially at connect time).

`Include` directives are expanded against an injectable `IncludeReader`, with relative paths anchored at `~/.ssh` and glob patterns (`config.d/*`) resolved against the real filesystem. Nested includes are honoured up to a depth limit (default 8) and a visited-set guards against self-referencing loops. Missing includes are logged and skipped, not fatal — a deleted helper file does not break the whole import.

`PreferredAuthentications` is parsed into an ordered list of `AuthType` values (publickey ↔ `AuthType.key`, password / keyboard-interactive ↔ `AuthType.password`, gssapi/hostbased ignored). The importer consults this list first — an entry that explicitly prefers password auth keeps `AuthType.password` even when an `IdentityFile` is readable, matching OpenSSH's runtime choice instead of forcing key auth on hosts where it would be rejected.

Encrypted `IdentityFile` keys are detected by `KeyFileHelper.isEncryptedPem` (decoding the OpenSSH v1 binary frame for the KDF-name field, or sniffing PKCS#1 / PKCS#8 armor headers) and surfaced via `hostsWithEncryptedKeys` — a subset of the existing `hostsWithMissingKeys` list, so the old UI warning still fires but callers who care can tell "needs passphrase" from "truly missing" without re-reading the file.

---

#### PPK codec — PuTTY's private key format

`core/security/ppk_codec.dart` parses PuTTY's `.ppk` files and converts the supported variants to OpenSSH PEM in-place so the rest of the import path stays format-agnostic. The codec is stateless / pure-Dart — no FFI, no native deps.

**Scope.** PPK v2 and v3, `ssh-ed25519` and `ssh-rsa`, **unencrypted + encrypted (`aes256-cbc`)**. The top-level `PpkCodec.parse(text, passphrase)` dispatches on the file's first line (`PuTTY-User-Key-File-2` vs `-3`) and the algorithm-specific `toOpenSshPem` packer routes by `algorithm` after parse. Algorithm-only aliases (`parseV2Ed25519`, `parseUnencryptedV2Ed25519`) stay around for callers that explicitly want one path.

**v3 KDF — Argon2id with a 1 GiB memory ceiling.** Encrypted v3 derives 80 bytes via Argon2id over the passphrase + the salt from the `Argon2-Salt` header (the type comes from `Key-Derivation`, supports `Argon2id` / `Argon2i` / `Argon2d`; iterations / memory / lanes from `Argon2-Passes` / `Argon2-Memory` / `Argon2-Parallelism`). The first 32 bytes are the AES-256 key, next 16 the IV (no zero-IV here unlike v2), final 32 the HMAC-SHA-256 key. The parser hard-rejects files asking for more than 1 GiB of working memory (`_argon2MaxMemoryKiB`) — well above puttygen's 8 MiB default but enough below "out of memory" that a crafted file cannot DoS the importer. v3 unencrypted skips the KDF entirely; the MAC key is the empty string (the file is still MAC-verified for tamper detection, just not authenticated against a secret).

**v3 MAC — HMAC-SHA-256 over the same payload as v2.** ssh-string-prefixed `algorithm` + `encryption` + `comment` + `publicBlob` + `privateBlob` (encrypted bytes for encrypted files). Verified before decryption; mismatch surfaces as `PpkMacMismatchException` which doubles as the wrong-passphrase signal — Argon2id over a wrong passphrase produces a different MAC key, so HMAC fails before the AES gibberish ever has to be parsed.

**RSA component reordering.** PPK splits the private RSA tuple as `(d, p, q, iqmp)` whereas OpenSSH's openssh-key-v1 envelope expects `(n, e, d, iqmp, p, q)`. The codec reads `n` and `e` out of the public blob (PPK layout: `ssh-string("ssh-rsa") + mpint e + mpint n`) and reorders into the OpenSSH layout — note `iqmp` lands before `p` and `q` in OpenSSH but after them in PPK. The reordering is the entire content of `toOpenSshPemRsa` over the ed25519 path; the envelope, padding, and PEM armor are identical.

**Encryption — `aes256-cbc`.** PPK v2 derives the AES-256 key by concatenating `SHA-1(0x00000000 || passphrase)` and `SHA-1(0x00000001 || passphrase)` and taking the first 32 bytes. The IV is **all zeros** — the format's choice, not ours; v3 fixes it via KDF-derived IV. Decryption is raw AES-CBC (no PKCS#7 strip — PuTTY pads with arbitrary trailer bytes that the inner ssh-mpint parser ignores).

**MAC verification.** HMAC-SHA-1 keyed with `SHA-1("putty-private-key-file-mac-key")` for unencrypted files, or `SHA-1("putty-private-key-file-mac-key" || passphrase)` for encrypted ones. The payload is the ssh-string-prefixed concatenation of `algorithm`, `encryption`, `comment`, `publicBlob`, **encrypted** `privateBlob` — verification runs **before** decryption so a corrupted file does not waste a CBC pass, and so a wrong passphrase surfaces as the canonical `PpkMacMismatchException` (decrypted gibberish hashes uniformly; the only honest signal is the MAC failing). Compare is constant-time so a forge attempt cannot leak the expected MAC byte-by-byte. Encrypted files passed to `parseV2Ed25519` without a passphrase throw `PpkPassphraseRequiredException` so the importer can prompt and retry.

**OpenSSH conversion.** `toOpenSshPemEd25519` extracts the 32-byte ed25519 public key from the public blob (skipping the algorithm ssh-string) and the 32-byte private scalar from the mpint in the private blob (stripping the optional leading-zero pad), then constructs the `openssh-key-v1\0` envelope with `cipher=none` / `kdf=none`, packs the keys into the standard private-block (matched-check pair, ssh-ed25519 algo, pub, priv-pub-concat, comment, 1..N padding), and base64-armors with `-----BEGIN OPENSSH PRIVATE KEY-----`. The result feeds the Rust core's PEM importer directly.

---

### 3.10 Update (`core/update/`)

```dart
class UpdateService {
  // Checks GitHub Releases API via lfs_core::update::orchestrator
  // (FRB) — version compare, skip-version persistence, signed-
  // manifest verify, atomic download + extract. Dart side is the
  // UI controller; the Rust orchestrator owns the pipeline.
  //
  // DI: HttpFetcher (test-time replacement for the Releases JSON
  // body fetch — production routes through
  // lfs_core::update::http::fetch_text). Download + verify is a
  // single Rust call (lfs_core::update::http::download_with_verification)
  // with a static @visibleForTesting `debugDownloadOverride` seam
  // that scripts a DbDownloadResult for the failure-shape tests.
  // Download: streams every chunk straight to disk while hashing —
  //   bytes never sit in a Dart heap buffer. Follows redirects
  //   (max 10) bounded by the trusted-host allowlist, verifies
  //   every artefact twice before install —
  //   (a) SHA-256 from the Releases JSON, and
  //   (b) Ed25519 signature via lfs_core::update::signing::verify_release_signature.
  //   The Dart wrapper maps DbDownloadErrorKind {untrusted, network,
  //   manifestUnavailable, invalidSignature} into the matching
  //   exception class so the UI can pick the right toast.
  // openFile(): platform launcher, validates Windows paths against shell metacharacters.
  // Progress: bus events (BusEvent::UpdateDownloadProgress +
  //   BusEvent::UpdateVerifyingStarted) drive onProgress / onPhase;
  //   throttled to 1% increments in UpdateNotifier to reduce state churn.
  //
  // Changelog: fetched once during check(), stored in UpdateInfo.changelog,
  // preserved across state transitions (downloading → downloaded) via copyWith.
}
```

Supporting Rust modules:

- **`lfs_core::update::signing`** (`rust/crates/lfs_core/src/update/signing.rs`) — holds the single pinned Ed25519 public key (`PRIMARY_PUBLIC_KEY`) the verifier matches every release-artefact signature against. Single-pin layout by design: rotation is a manual-reinstall ceremony (generate a fresh keypair offline, swap the GitHub `RELEASE_SIGNING_KEY` secret + offline backup, edit the embedded pubkey, ship the new release, announce via README/website), not an in-app hot-swap. A backup `Option<[u8; 32]>` slot was scoped earlier but rejected as scaffolding-without-use — the slot reappears trivially in the same PR that generates the next keypair when a real rotation is planned. See [`SECURITY.md`](SECURITY.md) for the full recovery playbook.
- **`lfs_core::update::http`** (`rust/crates/lfs_core/src/update/http.rs`) — the rusty HTTP client used to fetch the Releases JSON + the artefact / signature pair. Standard rustls TLS via reqwest's `rustls-tls` feature (system trust anchors via webpki-roots). The Ed25519 release signature is the load-bearing integrity check; SPKI pinning was scoped here earlier but rejected because the app ships without analytics or a remote-management channel — a stale pin (GitHub key rotation) would silently break auto-update for everyone on the prior release with no detection or rescue path. The Ed25519 sig already gates the same attacker class.
- **`InvalidReleaseSignatureException`** — thrown from
  `UpdateService.downloadAsset` when the signature check fails. Distinct
  from network errors so the UI can surface a "security-coloured" toast
  instead of a retry prompt.

### 3.11 Keyboard Shortcuts (`widgets/core/shortcut_registry.dart`)

Central registry for all app keyboard shortcuts. Every shortcut is an `AppShortcut` enum value with a default `SingleActivator` binding.

```dart
enum AppShortcut {
  newSession(SingleActivator(LogicalKeyboardKey.keyN, control: true)),
  terminalCopy(SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true)),
  // ... 32 shortcuts total (global, terminal, file browser, session panel, context menu, dialog)
  ;
  const AppShortcut(this.defaultBinding);
  final SingleActivator defaultBinding;
}

class AppShortcutRegistry {
  static final instance = AppShortcutRegistry._();

  SingleActivator binding(AppShortcut shortcut);

  // For CallbackShortcuts widgets:
  Map<ShortcutActivator, VoidCallback> buildCallbackMap(Map<AppShortcut, VoidCallback> actions);

  // For onKeyEvent handlers (e.g. inside xterm where CallbackShortcuts can't intercept):
  bool matches(AppShortcut shortcut, KeyEvent event);

  // Render the current binding for [shortcut] as a display string
  // ("Ctrl+Shift+V", "F2", "Delete") — used by the context-menu
  // factory so shortcut hints always reflect the live bind.
  String shortcutLabel(AppShortcut shortcut);
}

// Pure formatter — turns any SingleActivator into a display string.
// Modifier order: Ctrl, Alt, Shift, Meta (the GTK / Win / mac
// convention). Named keys (Esc, Tab, arrows, …) map to friendly
// glyphs; printable + function keys fall through to `keyLabel`.
String formatShortcut(SingleActivator a);
```

**Usage patterns:**
- `CallbackShortcuts` widgets → `AppShortcutRegistry.instance.buildCallbackMap({...})`
- `onKeyEvent` handlers (xterm, file browser, session panel) → `reg.matches(AppShortcut.x, event)`
- Dialogs → `buildCallbackMap({AppShortcut.dismissDialog: ...})`
- Context-menu hints → `StandardMenuAction.x.item(ctx, shortcut: AppShortcut.y, …)`
  (factory calls `shortcutLabel` internally; see [ContextMenu →
  StandardMenuAction](#standardmenuaction--shared-action-catalogue))

**Note:** `matches()` only checks ctrl/shift modifiers (not alt/meta) to tolerate phantom modifier flags on some platforms (e.g. WSLg).

**Collision invariant — `buildCallbackMap` fails loud on duplicate activators.** Several `AppShortcut` values intentionally share a `SingleActivator`: `sessionCopy` / `fileCopy` both bind `Ctrl+C`, `sessionPaste` / `filePaste` both bind `Ctrl+V`, `sessionDelete` / `fileDelete` both bind `Delete`, `sessionEdit` / `fileRename` both bind `F2`. The context-sensitive dispatch is enforced by *where* each `CallbackShortcuts` is mounted — `SessionPanel` ships the session variants, `FilePane` / terminal subtree ship their own. The enum has no "scope" dimension because Flutter's `CallbackShortcuts` takes a raw `Map<ShortcutActivator, VoidCallback>` with no scope key.

If a caller ever collides two of these shortcuts into one `buildCallbackMap` (unified command palette, shell-level shortcut handler, test harness that wraps both, future refactor), the output used to silently coalesce to the last-written entry — one of the two shortcuts becoming a no-op with no error message at compile or runtime. `buildCallbackMap` now throws `StateError('Duplicate shortcut activator …')` on collision so the regression trips at build time, before any keyboard input reaches the broken state. Regression guard: `test/core/shortcut_registry_test.dart` "buildCallbackMap throws on duplicate activator".

---

### 3.12 Snippets (`core/snippets/`)

Reusable shell command templates with optional placeholder substitution. Persisted in the rusqlite `Snippets` table (schema in `lfs_core::db`); pinned per-session via the `SessionSnippets` junction table. The model is a flat `Snippet { id, title, command, description }`; rendering happens at execution time via `snippet_template.dart`.

#### Template grammar

`renderSnippet(Snippet snippet, Map<String, String> context)` returns a `SnippetRender { rendered, unresolved }`. `{{name}}` is the only placeholder syntax. Whitespace inside the curly braces is trimmed (`{{  host  }}` ≡ `{{host}}`). Tokens that don't resolve against `context` are left in the output as-is and listed in `unresolved` (in first-seen order, deduplicated) so the picker can prompt for them.

| Built-in key | Source at the picker |
|---|---|
| `host` | `Session.host` |
| `user` | `Session.user` |
| `port` | `Session.port` (stringified) |
| `label` | `Session.label` |
| `now` | ISO-8601 timestamp at render time |

User-defined names are anything else; the picker collects them via [`_SnippetFillDialog`](features/snippets/snippet_picker.dart) which renders one `StyledInput` per unresolved token, fills with `fillSnippetUnresolved`, and pops with the final command.

**Why this grammar.** Same shape as `~/.ssh/config` `%h`/`%p`/`%u` and as IDE live-templates — predictable for a power user, no surprises around shell escaping. Tradeoffs frozen explicitly:

- **No recursion.** A substituted value containing `{{x}}` is taken literally; the rendered output is never re-scanned. Prevents user-defined values from accidentally referencing other tokens (and prevents accidental infinite expansion).
- **No shell escaping.** The substituted value is the raw context string. If the user wants quoting, that's their problem at the snippet authoring site — same as OpenSSH config tokens.
- **`{{{{` is a literal `{{`.** The escape is consumed before token detection so `{{{{not-a-token}}}}` renders as `{{not-a-token}}`. Empty `{{}}` is left literal (typo, not a "drop-everything" sentinel).
- **Unterminated `{{` is copied verbatim.** Avoids data loss when a malformed snippet is rendered against a context that would otherwise consume the tail.

#### Picker integration

`SnippetPicker.show(context, sessionId, templateContext)` in `features/snippets/snippet_picker.dart` is the single entry point used from the desktop terminal pane and the mobile terminal view. The caller assembles the built-in context from `widget.connection.sshConfig` (host, user, port, label, now) and hands it to the picker; the picker handles the render → prompt → fill flow internally and returns the final command (or `null` on cancel). The terminal pane never sees the unrendered command — by the time it calls `sendCommand` every placeholder has either resolved against the session or been filled by the user.

---

### 3.13 Session Recording (`core/session/session_recorder.dart`)

Per-shell terminal recorder that captures the user-visible output stream + input keystrokes, framed as [asciinema v2](https://docs.asciinema.org/manual/asciicast/v2/) events, persisted to disk with optional encryption-at-rest.

#### Lifecycle

Two entry points open a recorder, both routed through the same `SessionRecorder.open`:

- **Auto-open at connect** — `TerminalPane._maybeOpenRecorder` consults `Session.extras['record']` and, when true, builds the recorder and hands it to `ShellHelper.openShell` as the `recorder:` parameter.
- **Toolbar toggle mid-session** — the connection bar's record button (`workspace_view._recordButton`) looks the focused pane up in `PaneRecordingRegistry` and calls its `toggle`. The pane's handler builds the recorder through the same `_openRecorder` helper (no extras check) and swaps it onto the live `ShellConnection` via `setRecorder`.

`ShellHelper.openShell` reads `shellConn.recorder` dynamically on every chunk (late-bound capture, not a closure-captured parameter), so a recorder swap mid-stream takes effect on the next byte without restarting the shell. `ShellConnection.setRecorder` closes the previous recorder (sealing its file) before adopting the new one, so a Stop tap finalises the current `.lfsr` / `.cast` in the recordings browser even while the shell stays live.

`ShellConnection.close` calls `recorder.close()` after the shell tears down so any final tail bytes (banner, "logout") still land before the file is sealed.

```
TerminalPane
  ├── auto: reads Session.extras['record']
  │    └── SessionRecorder.open(sessionId, label, w, h)
  │         └── ShellHelper.openShell(... recorder: rec)
  │              ├── stdout/stderr.listen → terminal.write + shellConn.recorder?.recordOutput
  │              └── terminal.onOutput   → shell.write   + shellConn.recorder?.recordInput
  └── on-demand: PaneRecordingRegistry.toggle
       └── SessionRecorder.open(...) + ShellConnection.setRecorder(rec | null)
```

`PaneRecordingRegistry` is a process-wide singleton keyed by paneId. Each `TerminalPaneState` registers its `PaneRecordingHandle` (a `ValueListenable<bool> isRecording` + a `Future<void> toggle()` + a `canRecord` gate) in `initState` and removes it in `dispose`. The connection bar reads the focused pane id from `focusedPaneProvider` (a per-tab Riverpod `NotifierProvider.family<String?, String>` that `TerminalTabState` writes on every `onPaneFocused` callback) so the button always operates on whichever pane the user just clicked in a split tab. Unsaved quick-connect sessions report `canRecord = false` — recordings need a stable session folder to land in — and the button hides for them.

#### Why per-shell, not per-connection

Multi-pane connections run independent shell channels — each pane has its own xterm buffer, scrollback, and dimensions. A connection-level recorder would interleave bytes from N shells into a single timeline that no playback tool could un-mix. Per-shell keeps each recording straight-line.

#### Coalesced worker wake-ups

Each recording's `RecorderQueue` worker writes one asciinema event per mailbox entry. Without coalescing, every shell-output packet from russh (4-16 KiB each, 3-10/s on an interactive prompt and hundreds/s under `cat large_file`) would wake the writer worker individually — a worker wake + AES-GCM frame + disk write per packet.

`lfs_core::recorder::queue::enqueue_event_chunk` absorbs the storm in a per-direction `EventBuffers` slot guarded by a `std::sync::Mutex` (held only across buffer math, never across an `await`). Each chunk extends the matching direction's `Vec<u8>` and either flushes the drained bytes onto the mailbox immediately on the 8 KiB `FLUSH_THRESHOLD_BYTES` overshoot, or schedules a single 10 ms tokio `flush_task` that drains both directions when no further chunk arrived to pre-empt it. Direction split keeps the asciinema timeline straight — a typed key-press never gets attributed to the output stream — and tokio's mpsc preserves FIFO so the on-disk event order matches the wire order regardless of how many chunks land in one frame.

`Header` / `Rotate` / `Close` go through `enqueue_blocking`, which drains pending chunk bytes before sending its own entry: rotation never splits a frame across two files, and close never seals the file before trailing 10-ms-window bytes reach disk on a fast disconnect.

The Dart `SessionRecorder.recordOutput` / `recordInput` is a one-line FRB call per chunk — no Dart-side `BytesBuilder` / `Timer`, no Dart heap retention beyond the FRB call site. Bytes leave Dart heap as soon as they arrive. Dispatches chain off `SessionRecorder._dispatchTail` so each FRB call only fires after the previous one's `enqueue_event_chunk` has returned: the per-id buffer extends in caller order, and `tokio::sync::Mutex` fairness inside the runtime never gets to decide which of two concurrent calls landed first. `close()` awaits the tail before sending `Close`.

#### Why asciinema v2 inside an encryption envelope

asciinema is the de-facto interop format — `asciinema play file.cast` plays it on any platform without our app installed. Keeping the plaintext shape standard means a future "Export to .cast" action is one decrypt away: the bytes inside the envelope are already the asciinema JSON-Lines that any cast viewer accepts. A custom binary format would lock recordings inside the app forever.

#### Encryption envelope

When the running [security tier](#36-security--encryption-coresecurity) carries an in-memory DB encryption key, the recorder mints a **random 32-byte per-file recording key**, wraps it under the DB key in the file header, and uses the recording key for every frame's GCM tag. The recording key is **not** derived from the DB key — random per file, wrapped in place — so tier transitions only rotate the wrap, not the body. Per-recording isolation also means a compromise of one file's frames does not unlock its siblings.

File layout (LFR1 version 0x01):

```
[LFR1 magic (4)] [version (1) = 0x01]
[wrap_nonce (12)] [wrapped_recording_key (32 ct + 16 GCM tag)]    ← 65-byte header
loop:
  [plaintext-len (4 LE)] [nonce (12)] [ciphertext (len)] [GCM tag (16)]
```

Wrap: `AES-256-GCM(key = dbKey, nonce = wrap_nonce, plaintext = recording_key, aad = "letsflutssh-recording-keywrap-v1")`. Each plaintext chunk is one asciinema JSON-Lines record (header on first chunk, then `[t_seconds, "o"|"i", "data"]` events). Per-event GCM frames bind `frame_index_u64_le` as AAD so an attacker who swaps two frames byte-for-byte breaks the tag at both swapped positions. Per-event GCM also means a truncated tail (crashed app, full disk) loses only the trailing event, not the whole timeline.

#### Sidecar index (`<recording>.idx`)

Every event the writer appends to the main file also appends one entry to a fixed-width sidecar `<recording>.idx` so playback can binary-search a target timestamp into a byte offset without scanning the full file. The scrub-bar UI in `RecordingPlaybackDialog` translates a slider release into the matched frame boundary; the main-file decoder restarts pre-positioned at that offset rather than re-decoding from start.

File layout, plaintext `.cast` pairs:

```
[LFI1 magic (4)] [version (1)]
loop:
  [offset (8 LE)] [timestamp_ms (4 LE)]
```

File layout, encrypted `.lfsr` pairs:

```
[LFI1 magic (4)] [version (1)]
loop:
  [plaintext-len (4 LE) = 12] [nonce (12)] [ciphertext (12) + GCM tag (16)]
```

Each encrypted block authenticates one 12-byte plaintext entry under AAD = `entry_seq_u64_le` (0 for the first entry, 1 for the second, …). The reader recomputes the sequence number from block position so a disk-side swap of two blocks invalidates the GCM tag at both swapped positions — same posture as the main-file per-frame AAD chain.

The sidecar key is HKDF-SHA-256 derived off the per-file recording key with a distinct info tag: `letsflutssh-recording-idx-v1`. Chaining off the recording key (not the DB key) keeps register-time self-sufficient — the actor opens its sidecar at construction without a second secrets-store lookup — and the distinct info tag keeps the index key cryptographically separate from both the recording key and the DB key. A leak of one key does not compromise the other.

Because the recording key is stable across tier transitions (only the header wrap rotates, not the key), the sidecar key is also stable across tier transitions. `migrate::rewrap_all_headers` does NOT touch the sidecar — same chain, same key, same on-disk bytes.

`u32` milliseconds tops out at ~49 days per recording — far past any plausible single file. Keeping the timestamp narrow (`u32` vs `u64`) halves the per-entry size on the plaintext path, which directly cuts the binary-search range a typical seek walks.

#### Sidecar crash-safety contract

The main-file frame write happens BEFORE the sidecar entry append. A crash between the two leaves the trailing entry missing — the reader treats that as "no scrub-target past this offset" and falls back to sequential decode for any seek into the dangling range. The pairing is deliberately non-atomic: fsync × 2 per event would dominate the writer hot path, and the worst case (lose one scrub-target on the last 10 ms of a recording before crash) is a minor degradation rather than a correctness break.

Both writes go through `BufWriter` with `flush()` after each event so the durability story for the sidecar matches the main file (the OS still flushes on drop after a clean close; an OS crash loses the most recent unflushed window for both files equally).

#### Sidecar migration: legacy recordings stay playable

Recordings written before this build do NOT have a `<file>.idx` sibling. The reader's seek path returns `None` for any missing / empty sidecar; the playback dialog catches the null and disables the scrub bar with a tooltip explaining why (capability-ladder rung 4: render disabled with a reason rather than ship a weaker path that pretends to scrub). Speed dropdown (`0.5×` / `1×` / `2×` / `4×` / instant) keeps working unchanged — the existing sequential playback path is independent of the sidecar.

The FRB seek entry point is `recorder_seek(recording_path, target_ms, encrypted)`; the playback-start variant `recorder_open_for_playback_at(path, start_offset, start_frame_index, sink)` resumes the iter from a sidecar-supplied frame boundary. Both live under `lfs_core::recorder::index_sidecar` (writer + reader + binary search) and `lfs_frb::api::recorder` (FRB adapter + HKDF chain).

#### Tier-transition migration (`lfs_core::recorder::migrate`)

Every DB-key change (`T0 ↔ T1`, master-password rotation, `T1 ↔ T2` hardware bind / unbind) must keep existing recordings playable — the per-file recording key is wrapped under the DB key in the file header, so a stale wrap leaves the file unreadable even though the body is intact. Three migration operations cover the matrix:

| Transition | Operation | What runs |
|---|---|---|
| `T1 → T1'` (password rotation), `T1 → T2`, `T2 → T1`, `T2 → T2'` | `rewrap_all_headers(root, old_db, new_db)` | Walk `.lfsr`, unwrap each 65-byte header with `old_db`, re-wrap with `new_db`, atomic `tmp + fsync + rename`. Body + sidecar untouched. O(num_files × 64 bytes) regardless of recording length. |
| `T0 → T1` (master-password enable) | `convert_all_cast_to_lfsr(root, new_db)` | Walk `.cast`, mint fresh per-file recording key, write fresh v1 `.lfsr` (header + GCM-framed body), build fresh encrypted sidecar, atomic rename. Source `.cast` removed after `fsync`. |
| `T1 → T0` (master-password disable) | `convert_all_lfsr_to_cast(root, current_db)` | Walk `.lfsr`, decrypt each frame under the wrapped recording key, write plaintext `.cast` (one JSON-Lines record per frame), atomic rename. Encrypted sidecar dropped — `.cast` playback re-discovers offsets sequentially. Must run BEFORE the DB key leaves memory. |

**Hook placement** (`lfs_frb::api`):

- `db_rekey_from_secret(secret_id)` — runs `rewrap_all_headers(active, staged)` BEFORE `PRAGMA rekey`. On migration failure the function aborts before touching SQLite or the secret slots; the caller retries with the same `secret_id` without observing a partially-migrated state.
- `master_password_enable_to_secret(...)` — runs `convert_all_cast_to_lfsr(staged)` AFTER staging the new key in `secret_id` (the slot the next `db_rekey_from_secret` will read from).
- `master_password_disable()` — runs `convert_all_lfsr_to_cast(active)` BEFORE wiping the KDF + verifier files. The DB key still lives in `ACTIVE_DBKEY_SECRET_ID` at this point, which is the invariant the helper needs.
- **Forgotten-password reset** (`master_password_reset`) — does NOT run any migration. The user has already accepted "destroy everything" by reaching that flow; recordings stay encrypted under a key that no longer exists and become unreadable, matching the rest of the reset's posture.

**Atomicity per file.** Each helper writes the new shape to `<file>.tmp.<random>` in the same directory, `fsync`s, then `rename`s over the original. A crash mid-walk leaves either the old or the new file at every step — never a torn header or half-decrypted body. The walker is also idempotent: re-running `rewrap_all_headers(old, new)` after a clean run is a no-op because the post-rewrap files unwrap under `new`, not `old`.

**No global lock.** The migration walks while the recorder registry may still be appending frames to live recordings. Currently-recording files are not in the migration scope (a fresh recording opened post-tier-change picks up the new DB key on its own header build); files already on disk are atomically swapped under the file system's `rename` semantics. The recorder file handle does not cross between the migration's `read` and the production writer's `write` — a stray open handle to the old inode keeps working until close, at which point the new inode (linked at the same path) is what the next reader opens.

#### Plaintext mode

When the security tier is `plaintext`, the recorder writes raw asciinema JSON-Lines (no envelope, no encryption) to a `.cast` file with `chmod 600`. The user already opted out of crypto at the tier level — adding a different surface for one feature would be misleading. The file extension differs (`.cast` vs `.lfsr`) so a future loader can dispatch by suffix without reading magic bytes first.

#### Storage

Recordings live as discrete files at `<appSupport>/recordings/<sessionId>/<isoTimestamp>.<lfsr|cast>`. Each file caps at `maxFileBytes = 100 MB`; on overflow the recorder rotates to a fresh file under the same session (with a fresh asciinema header). 100 MB is large enough for a multi-hour vim-heavy day, small enough that exporting a single file stays trivially shareable.

The aggregate byte ceiling for the tree is configurable through `AppConfig.recordings_storage_cap_bytes` (default 500 MiB, persisted on `config.json`). `lfs_core::recorder::storage_cap` owns the LRU eviction sweep: a two-level walk under `<recordings_root>` collects every regular file, sorts by `metadata.modified()` ascending (entries with unreadable mtime go first — "delete first" rule), and unlinks oldest entries until the running total is at or below the cap. The currently-writing files (every actor registered via `RecorderRegistry::register_with_io`) are skipped by checking the path against `RecorderRegistry::active_paths()`. The sweep fires automatically on every register + close — defence-in-depth pairs with the per-file 100 MB cap so a forgotten "record everything" toggle cannot eat the disk. Per-file `remove_file` failures (perm denied, IO timeout) log a warning and continue rather than aborting the sweep, and the register / close call paths swallow eviction errors so a stuck unlink never blocks the recording lifecycle.

The FRB surface exposes three storage-cap entry points alongside the existing list / delete / play shims: `recorder_storage_used` (bytes currently used; walks the tree fresh, no cache), `recorder_set_storage_cap` (push a new cap → re-parse + sanitise through `AppConfig::from_json_value` → run an immediate eviction sweep), and `recorder_clear_all_recordings` (delete every non-active file). Caps clamp to the default on zero or above 1 TiB inside `AppConfig::sanitized` so a hand-edited `config.json` cannot disable the sweep by stamping `u64::MAX`.

The user-facing surface for the cap lives in the Settings → Data section as the `_RecordingsStorageTile` (`lib/features/settings/settings_sections_data.dart`). The tile reads `recorder_storage_used` on demand (refreshes after cap change + clear-all), exposes the cap as a closed-set dropdown (100 MiB / 250 MiB / 500 MiB / 1 / 2 / 5 GiB) over `recorder_set_storage_cap`, and routes the destructive Clear-all action through `recorder_clear_all_recordings` behind a `ConfirmDialog`. Cap presets stay a closed set rather than a free-form numeric field so a careless `0` cannot slip through the UI and rely on `AppConfig::sanitized` to clamp it back to the default silently.

The recordings tree is owned by `lfs_core::recorder::browser`. Listing (`list_recordings`), per-row delete (`delete_recording`), and playback (`open_for_playback` — dispatches by extension into `open_cast_iter` / `open_lfsr_iter`) all run inside `tokio::task::spawn_blocking` workers behind the FRB shims `recorder_list_recordings`, `recorder_delete_recording`, `recorder_open_for_playback`. Dart resolves `<appSupport>/recordings` once per scan via `path_provider` and hands the root in; `path_provider` is the only piece of the chain that has to live in Dart. The walk uses `symlink_metadata` so a symlink planted under the tree never resolves to a target outside it; `delete_recording` rejects any `session_id` / `file_name` containing `..` or a path separator before issuing any filesystem call.

#### Privacy posture

- **Opt-in per-session, default off.** Privacy-first positioning. Toggle lives on the session edit dialog Options tab.
- **Quick-connect sessions skip recording.** No stable session id = no recording directory, no opt-in surface. Recorder returns null.
- **Recorder failure is best-effort.** A refusal to open the file (permission, disk full) logs a warning and returns null; the connect itself never fails on a recorder error.

---

### 3.14 Rust Security/Transport Core (`rust/`)

The SSH/SFTP/keypair stack and every cryptographic envelope run entirely on a Rust workspace at `rust/` (`russh = "0.59"`, `russh-sftp = "2.1"`, `russh-keys = "0.6.16"` with the PPK feature, `rusqlite` with `bundled-sqlcipher-vendored-openssl`, RustCrypto family for AES-GCM / HKDF / Argon2id / Ed25519). The Dart side carries widgets, Riverpod state, theme, l10n, and thin command/event subscribers — no protocol parsing, no key material, no plaintext secrets ever live there outside the user-typed-just-now window. Memory safety on the highest-risk code path (parsing untrusted server bytes, key material, KDF/AEAD envelopes) plus access to russh's full algorithm table unlock SSH certificates and FIDO2-SSH (sk-* keys) without forking anything.

#### Workspace layout (hexagonal: ports + adapters)

```
rust/
├── Cargo.toml                  workspace root + shared dep pins
├── rust-toolchain.toml         channel = stable
└── crates/
    ├── lfs_core/               PURE Rust headless library
    │                           crate-type = ["rlib"]
    │                           NO flutter_rust_bridge / tauri / dart deps
    │                           [lints.rust] unsafe_code = "forbid"
    │
    ├── lfs_os_security/        OS-bound FFI for the security stack
    │                           crate-type = ["rlib"]
    │                           keychain / biometric / hardware-vault /
    │                           clipboard / session-lock / process-hardening
    │                           Linux + macOS + iOS + Windows + Android JNI
    │                           Owns every `unsafe extern "C"` / objc2 /
    │                           windows-rs / jni call in one auditable place
    │                           Depended on by lfs_core (one-way edge)
    │
    └── lfs_frb/                Flutter adapter — native blob loaded by Flutter
                                crate-type = ["cdylib", "staticlib", "rlib"]
                                deps: lfs_core + flutter_rust_bridge
                                Zero `unsafe` (all FFI lives in lfs_os_security)
```

**Three crates, three roles.** `lfs_core` owns business logic + pure-Rust crypto + persisted state — no FFI, no platform conditionals beyond `cfg(target_os)` for behavioural splits, no UI awareness. `lfs_os_security` is the single audit perimeter for OS-API calls — every `objc2-*`, `windows-*`, `jni`, `secret-service`, `arboard`, `tss-esapi` call routes through here so the unsafe surface lives in one crate instead of being scattered. `lfs_frb` is the only crate that imports `flutter_rust_bridge` and the only one that produces a `cdylib`/`staticlib`. A future Tauri pivot adds `lfs_tauri` next to `lfs_frb` with the same `lfs_core` underneath; a future headless CLI adds `lfs_cli`. The discipline keeps every UI/transport choice replaceable without touching the security-critical core.

#### Boundary contract (FRB)

Defined in [`flutter_rust_bridge.yaml`](../flutter_rust_bridge.yaml) at the project root. Codegen reads `lfs_frb::api`, walks every public item, and emits typed Dart bindings into `lib/src/rust/`. Run via `make rust-codegen` after editing `rust/crates/lfs_frb/src/api.rs`.

Translation rules in the adapter:

| Rust shape (`lfs_core`) | Dart shape (after FRB codegen) |
|---|---|
| `pub fn f(x: T) -> R` | `Future<R> f(T x)` |
| `pub async fn f(...) -> Result<R, Error>` | `Future<R>` that throws a typed Dart exception |
| Long-lived `struct` (session, channel, sftp client) | Numeric handle ID (registered by `lfs_frb`); Dart never sees inner state |
| `tokio::sync::mpsc::Receiver<T>` | FRB `Stream<T>` |
| **Secret material** (passwords, key bytes, passphrases, derived AES keys) | **Opaque `SecretRef` id** (`String`). Plaintext NEVER crosses outbound — the Rust core stages bytes into `lfs_core::secrets::SecretStore` under a caller-allocated id and returns the id; Dart calls `secrets_take(id)` to atomically read-and-remove. Plaintext crosses inbound only on the user-typed-just-now path (the unlock dialog, master-password setup) and the `*_with_secret_id` variants are preferred — see [§3.6 SecretStore + SecretRef pattern](#secretstore--secretref-the-plaintext-discipline-rule). |

Why the SecretRef rule exists: the FRB stream sink buffers events behind the broadcast channel before they reach Dart, and the Dart heap is not auditable for `Zeroize`. Returning a derived AES key as `Vec<u8>` would leave bytes resident in two places we don't control. SecretRef keeps the bytes inside `lfs_core` (where they live in `Zeroizing<Vec<u8>>`) and forces every cross-FFI handoff to go through a single take-and-clear call. Bus events also follow the rule — `Event::HardwareVaultSealPromptRequest` carries a `db_key_secret_id: String` rather than the inline DB key bytes.

#### `lfs_frb` adapter purity

`lfs_frb` is a thin pass-through: marshal Dart-friendly types in, delegate to `lfs_core`, marshal results back. Every public entry point is one of:

- A type-shape adapter (Rust enum / struct → FRB-visible mirror, plus the `From` impls in `bus.rs`).
- A `lfs_core::*::*` call wrapped in `Result::map_err(|e| e.to_string())` for the FRB error shape.
- An opaque-handle returner (`SshSession::from_arc`, `SshForwardChannel`, etc.) for long-lived Rust objects whose internal state never crosses the bridge.

Composition that needs more than that lives in `lfs_core`. Concrete examples:

- Port-forward listeners (`forward.rs::port_forward_start_local/dynamic/remote`) delegate one-line to `lfs_core::portforward::driver::start_*`; the `DirectTcpipFactory` + `AppStatusReporter` + `SocketAddr` plumbing lives inside the driver.
- Connection lookup (`bus.rs::connection_get_session`) is a one-liner over `lfs_core::connection::ConnectionRegistry::connected_session(id)` — the registry walk + state-machine check are encapsulated there.
- DAO writes that need to refresh the sessions cache go through `run_db_writing_sessions` / `run_db_mut_writing_sessions` (and the `_when` predicate variants) in `db.rs` — single `run_db_writing_sessions(...)` call per FRB function. The wrapper resolves the `Db` handle, runs the closure, and fires `lfs_core::sessions::reload_and_notify` on Ok. No DAO callsite in the adapter mixes the run + notify dance by hand.
- OS FFI lives entirely in `lfs_os_security`. `lfs_frb` contains zero `unsafe`.

When in doubt: the adapter contains *delegation* + Dart-shape adapters; orchestration belongs in `lfs_core`.

#### Current scope

`lfs_core` owns: SSH transport (`russh`), SFTP (`russh-sftp`), shell + direct-tcpip channels, port forward driver (`-L` / `-R` / `-D` + SOCKS5), ProxyJump primitive (`open_direct_tcpip`), ssh-agent client, SSH certificates, OpenSSH PEM + PuTTY PPK (v2 + v3 / Argon2id) import, AES-GCM / HKDF / Argon2id / Ed25519 / SHA-256 envelopes, `.lfs` archive encrypt/decrypt/apply, QR codec, rusqlite + SQLCipher 4.x DB, sessions registry, known-hosts + TOFU, log sanitiser, OpenSSH config grammar, update orchestrator, master-password verify, tier state machine, persisted rate-limit, config store actor, recorder ring buffer, auto-lock state machine, file-system local + remote, transfer queue, migration framework.

`lfs_os_security` owns: keychain (Apple `security-framework`, Linux `secret-service`, Windows `CredReadW`/`CredWriteW`, Android `java.security.KeyStore` via JNI), biometric (`LAContext`, `UserConsentVerifier`, Linux `fprintd` D-Bus, Android `BiometricPrompt`), hardware vault (Apple Secure Enclave, Android StrongBox JNI, Windows TPM 2.0 via NCrypt on the Microsoft Platform Crypto Provider), session lock listener (Linux logind, macOS `NSDistributedNotificationCenter`, Windows `WTSRegisterSessionNotification`), secure clipboard (per-OS sensitive-flag markers), backup exclusion (Apple `NSURLIsExcludedFromBackupKey`), process hardening (`prctl` / `ptrace` / `SetErrorMode`), debug-state probe.

`lfs_frb` is the FRB adapter: typed Dart bindings under `lib/src/rust/`, opaque handle registry for long-lived Rust objects, FRB Streams over `tokio::sync::mpsc`. Adapter rule: marshal Dart-friendly types in, delegate to `lfs_core`, marshal results back. No `unsafe`, no business logic.

**`russh` pin — 0.59.** Versions 0.60+ depend on the RustCrypto release-candidate set (`pkcs8-0.11.0-rc.11`, `ed25519-3.0.0-rc.4`, etc.) and `pkcs8-0.11.0-rc.11` fails to build against the latest stable `pkcs5-0.8.0`. Bump back to the latest stable `russh` once that RC set graduates and `pkcs8` 0.11 ships stable.

#### Security baseline

The first lines of defence beyond Rust's safe-by-default ownership / borrow rules:

- **`#[lints.rust] unsafe_code = "forbid"`** on `lfs_core` — no raw FFI / pointer surgery in code we write here. Transitive dependencies (`russh`, `tokio`, `ring`, `aws-lc-rs`) still use `unsafe` internally — that's their audit perimeter.
- **`zeroize::Zeroizing`** wraps secret buffers (passwords today, key material at 1.2/1.4, signing payloads at 1.11/1.12) so the local owned copy clears on drop. Cannot reach copies `russh` or `tokio` hold internally — best-effort hardening on the perimeter we control.
- **`subtle::ConstantTimeEq`** for crypto-material equality (MAC compares, hash compares) — never `==` for anything an attacker could time. `subtle` lives in `[workspace.dependencies]` ahead of need; first concrete use lands at 1.4 alongside the PPK HMAC verify.
- Workspace dep pinning in `[workspace.dependencies]` — every cross-crate version bump touches one place, so a `cargo audit` finding has one knob to twist.

#### CI gates (rust-ci + rust-cross-check jobs)

Two complementary Rust jobs run on every PR and push, alongside the existing Dart `ci` job:

**Canonical host gates** — Rust quality gates run inside the unified `ci` job via `make check`:

| Step (in `make check`) | Gate |
|---|---|
| `make rust-format-check` (`cargo fmt --all -- --check`) | Style drift |
| `make rust-lint` (host + Android + Windows-GNU clippy umbrella; Apple targets added on macOS hosts) | Lint, deny warnings — host + every cross-target whose stdlib ships with `rustup` |
| `make rust-test` (`cargo test --workspace --locked` + `--doc --locked`) | Unit, integration, doc tests; `--locked` enforces Cargo.lock parity |
| `make rust-machete` (`cargo machete --with-metadata`) | Unused dependency detector |

Supply-chain advisories are not gated by the canonical host job — Dependabot tracks `rust/Cargo.lock` against the GitHub Advisory Database on PR, and `osv.yml` cross-checks against the broader OSV DB on push + weekly cron, so a dedicated `cargo-deny` step is no longer wired in.

`make rust-coverage` (`cargo llvm-cov --workspace --all-features --locked --lcov`) runs in the same `ci` job after `make check` to feed Rust coverage to SonarCloud; it is heavier (instrumented rebuild) and not part of the gate.

**`rust-cross-check` (matrix)** — cfg-gated compile + lint validation across every target the workspace ships to. The local `make rust-lint` umbrella now covers Android + Windows-GNU directly (rustup-hosted stdlibs make those checkable from any host), so the CI matrix mainly catches Apple-target regressions on non-macOS contributors' PRs and exercises every target on the native runner end-to-end. Without this matrix, code under `cfg(any(target_os = "macos", target_os = "ios"))` (Apple Secure Enclave, LAContext, NSPasteboard) only compiles at release-tag time through `build-release.yml` — meaning a dependency bump that breaks one of those paths would auto-merge into `main` and surface only when cutting a release. Each matrix entry runs two steps in order:

1. `cargo check --workspace --all-targets --target <T> --locked` — type-checks every crate including dev-deps / test modules. Catches FFI / cfg-gated symbol drift across the whole workspace.
2. `cargo clippy -p lfs_os_security --target <T> --all-targets --locked -- -D warnings` — lints the per-OS FFI surface. Scoped to `lfs_os_security` because that crate is the single OS-FFI perimeter and its cfg-gated modules (`apple_se_ssh`, `fido2_broker::platform_impl`, `winbio`, `windows::*`, `android::*`, `macos::*`) are the only ones whose lints actually diverge per target. The same flags are exposed locally via `make rust-lint-{android,windows-gnu,ios,macos-arm}` (and the umbrella `make rust-lint`) so contributors can reproduce a CI lint failure without pushing first.

| Target | Runner | Why |
|---|---|---|
| `aarch64-apple-darwin` | macos-latest | Apple Silicon Mac path |
| `x86_64-apple-darwin` | macos-latest | Intel Mac path (universal binary other half) |
| `aarch64-apple-ios` | macos-latest | iOS path — same Apple-cfg code, no .ipa shipped today but compile-validates every type drift |
| `x86_64-pc-windows-msvc` | `windows-2025-vs2026` | Windows-cfg paths. Pinned label (not `windows-latest`) silences the GitHub `windows-2025` → `windows-2025-vs2026` redirect notice + locks the VS 2026 / MSVC toolchain. |
| `aarch64-linux-android` + `armv7-linux-androideabi` | ubuntu-latest via `cargo-ndk` | Android JNI paths in `lfs_os_security::android::*`; cargokit also builds these at release time. |

Clippy runs on the native runner per target (not on a single `ubuntu-latest` for all five) because rustup does not ship Linux- or Windows-hosted Apple `std` / `core` — a `cargo clippy --target aarch64-apple-ios` invocation on Linux fails at the `libloading` / `thiserror` build step with `can't find crate for std`, well before any lint runs. The native-runner placement is free here because the `cargo check` matrix already provisions those runners; the second step shares the cargo cache from the first.

Dependabot tracks `rust/Cargo.lock` (`.github/dependabot.yml` `cargo` ecosystem entry) and opens monthly bump PRs alongside the existing pub / github-actions / gitsubmodule schedules.

Rust quality gates are part of the unified `make check` (not a separate `rust-check`), so the same single command runs locally before commit and inside CI. `make check` calls `format-check`, `lint`, `lint-workflows`, `lint-release-hardening`, `rust-machete`, then the umbrella `make test` (which includes `rust-test`). Per-language entry points (`make dart-*` / `make rust-*`) exist for fast iteration when only one side is in scope.

#### Build & distribution

`make rust-build` compiles `lfs_frb` to a host-native blob (`liblfs_frb.so` on Linux, `.dylib` on macOS, `.dll` on Windows; per-ABI `.so` for Android via `cargo-ndk`; static `.a` for iOS via xcframework). The Flutter build picks up the blob via cargokit and bundles it into the platform-specific artefact.

The native blob ships bundled — end-users install nothing beyond the existing app bundle. Bundle size after `[profile.release]` tightening (`lto = "fat"` + `codegen-units = 1` + `strip = "symbols"` + `panic = "abort"`): ~16.6 MiB for `liblfs_frb.so` on Linux x64.

#### Dependency invariant

`lfs_core` MUST NOT depend on `flutter_rust_bridge`, `tauri`, or any frontend-specific crate. `lfs_os_security` is the one-way edge below `lfs_core` — it never depends on `lfs_core`, so `unsafe_code = "forbid"` upstream and `unsafe_code = "allow"` (for FFI) downstream stay separated. CI enforces both via `cargo tree` deny-list. Breaking the invariant turns the next UI pivot into a core rewrite — the whole reason the workspace is split this way.

#### Cross-references

- Build: [CONTRIBUTING.md § Rust core](CONTRIBUTING.md#rust-core-securitytransport) — toolchain install, common targets

---

### 3.15 Sync via WebDAV (`rust/crates/lfs_core/src/sync/`)

WebDAV-backed push / pull orchestrator. Ships the encrypted `.lfs`
archive between devices over the standard WebDAV transport
(`lfs_core::webdav::WebDavClient`). Lives entirely Rust-side; the
Flutter Settings → Sync section calls the three FRB verbs
(`sync_status`, `sync_push`, `sync_pull`) and renders the typed
result envelope.

#### Wire shape

| Layer | What lands on the wire |
|---|---|
| Remote object | One `.lfs` archive at the configured remote path (default `letsflutssh.lfs`) |
| Inner format | Same LFSE envelope manual exports produce (`SchemaVersions::ARCHIVE`) — Argon2id + AES-256-GCM over a stored-mode ZIP |
| Manifest extension | v2 adds optional `sync_origin` field stamping `<install-id>:<unix_ms>` so a peer device's pull can recognise "this is my own push echoing back" |

The remote object is the full DB snapshot every push; the
orchestrator does not ship deltas. Snapshot upload is simpler than
delta merge — the LWW merge in `sync::merge` handles convergence
on pull instead of putting the load on the wire shape.

#### Push flow

```mermaid
flowchart TD
    A[push request] --> B{enabled?}
    B -- no --> Z1[Err Disabled]
    B -- yes --> C[read SyncConfig + secrets]
    C --> D[compose .lfs archive Rust-side]
    D --> E[SHA-256 of archive bytes]
    E --> F{sha matches last_pushed_sha256?}
    F -- yes --> Z2[Ok UpToDate]
    F -- no --> G[PUT with If-Match=last_pushed_etag]
    G -- 412 --> Z3[Err EtagMismatch — UI surfaces &quot;pull first&quot;]
    G -- 401 --> Z4[Err Unauthorized]
    G -- 2xx --> H[stamp last_pushed_at_ms, last_pushed_sha256, last_pushed_etag]
    H --> Z5[Ok Pushed]
```

#### Pull flow

```mermaid
flowchart TD
    A[pull request] --> B[GET with If-None-Match: last_pushed_etag, last_pulled_etag]
    B -- 304 --> Z3[Ok UpToDate, no body]
    B -- 404 --> Z1[Ok Skipped: no remote archive]
    B -- 401 --> Z2[Err Unauthorized]
    B -- 200 --> C[read body + ETag header]
    C --> D[SHA-256 over body bytes]
    D --> E{sha matches last_pushed_sha256 or last_pulled_sha256?}
    E -- yes --> Z6[Ok UpToDate, stamp new last_pulled_etag+sha]
    E -- no --> F[decrypt + parse via parse_archive_bytes]
    F -- future version --> Z4[Err ArchiveFutureVersion]
    F -- ok --> G[parse_sync_origin]
    G --> H{origin starts with our install id?}
    H -- yes --> Z6
    H -- no --> I[merge_pending_into_local single tx]
    I --> J[stamp last_pulled_at_ms + last_pulled_etag + last_pulled_sha256]
    J --> Z5[Ok PullApplied]
```

The pull's hot path is one conditional GET. The `If-None-Match`
header carries a comma-separated list of the most recent push and
pull ETags (quoted per RFC 7232); the server returns 304 with no
body when neither has rotated. PROPFIND is reserved for callers
that genuinely need the multistatus body (file-browser walk); the
sync orchestrator does not call it.

The SHA-256 gate is the second-tier short-circuit: a server that
rotates ETags without changing the body (nginx restart, weak ETags)
still produces 200, but the plaintext hash compares against the
caches and skips the decrypt + merge work when either side already
saw the same bytes. The new ETag is persisted alongside the
unchanged SHA so the next pull's `If-None-Match` hits 304.

#### LWW merge rules

Per-row last-write-wins on the table's effective timestamp. The
merge runs inside a single SQLite transaction so a mid-merge crash
leaves the local DB untouched.

| Table | Field consulted | Notes |
|---|---|---|
| `sessions` | `updated_at` | strict-greater ⇒ peer wins |
| `snippets` | `updated_at` | same |
| `ssh_keys` | `created_at` | DAO has no `updated_at`; mutations re-stamp `created_at` on upsert |
| `tags` | `created_at` | same |
| `sftp_bookmarks` | `created_at` | same; v1 archives do not emit `sftp_bookmarks` yet |

**M2M join tables** (`session_tags`, `folder_tags`,
`session_snippets`) carry no timestamps. The merge unions local +
pending edges via `INSERT OR IGNORE` — every edge either side
knows about survives. **Removal of an edge is not replayed in
v1** because the wire format does not carry a "this edge was
deleted" marker; the user re-unlinks on the second device.

**Tombstone replay caveat — v1 limitation.** The export composer
(`archive::compose::build_sessions_value` and siblings) filters
`deleted_at IS NULL` before serialising, so v1 archives carry
live rows only. A peer device cannot observe a tombstone the
source device stamped through this wire format; cross-device
deletion replay lands when the export pipeline grows a
`deleted_at` field per row.

#### Self-push echo guard

Every push stamps a token `<install-id>:<unix_ms>` into
`manifest.sync_origin`. The `install_id` is a per-process random
12-byte hex string (a stable per-install id would need a
persisted file; per-process suffices because the case we're
guarding is "this process pushes, then pulls within the same
launch and observes its own bytes back"). The pull path strips
the field via `archive::parse_sync_origin` and skips the merge
when the origin matches our own id.

The conditional-GET path is the fast-path equivalent: when the
remote ETag matches either `last_pushed_etag` or `last_pulled_etag`,
the server replies 304 with no body and no decrypt work runs.

#### ETag conflict resolution

A 412 on PUT means the remote drifted since the last push (peer
device pushed between our pull and our push). The orchestrator
surfaces this as `SyncError::EtagMismatch`; the Settings UI
renders the localised "remote changed — pull first, then push"
toast. The user clicks Pull, the merge applies the peer's
changes, then clicks Push and the new ETag round-trips fine.

#### Secrets

Two secrets live in `lfs_core::secrets::SecretStore` under
canonical ids:

- `sync.webdav.password` — WebDAV password / bearer token. Used
  to build the `Credentials` for `WebDavClient`.
- `sync.passphrase` — the AES-GCM key for the archive envelope.
  **MUST differ from the master password** — the Settings UI
  uses `MasterPasswordManager::verifyAndDerive` on the typed
  passphrase to detect collisions without ever exposing the
  master password's plaintext.

Plaintext never lands in `config.json`; only the two SecretStore
id pointers do.

#### Schema versions

Every framework-managed artefact (`config.json`, `.lfs` archive
manifest, QR payload, hardware vault blobs) sits at v1. The Rust
runner reads the on-disk version stamp and routes anything
above 1 through `UnsupportedFutureVersion` → `DbCorruptDialog`
(see §3.6 → Migration framework). Wire-format additions land
on the existing v1 shape (every new field is optional / has a
default); structural bumps wait for the next coordinated v1 → v2
step.

#### Cadence

v1 is manual-only — the user clicks "Push now" / "Pull now". An
auto-interval timer is deferred; no background sync task runs.

## 4. State Management — Riverpod

### 4.1 Provider Dependency Graph

```mermaid
flowchart TD
    UI["UI (features/)"]
    UI -->|watches| sp["sessionProvider<br/>(NotifierProvider&lt;SessionNotifier, List&lt;Session&gt;&gt;)"]
    UI -->|watches| cp["configProvider<br/>(NotifierProvider&lt;ConfigNotifier, AppConfig&gt;)"]
    UI -->|watches| wp["workspaceProvider<br/>(NotifierProvider&lt;WorkspaceNotifier, WorkspaceState&gt;)"]

    sp -.-> fsp["filteredSessionsProvider<br/>(sessionProvider + sessionSearchProvider)"]
    sp -.-> ftp["filteredSessionTreeProvider<br/>(sessionProvider + sessionSearchProvider)"]
    cp -.-> tmp["themeModeProvider"]
    cp -.-> lp["localeProvider"]

    sp --> bus["FRB bus subscription<br/>(BusTopic::Sessions)"]
    cp --> rust["lfs_core::config_store actor<br/>(debounce + atomic write)"]
```

Independent provider clusters:

```mermaid
flowchart LR
    conn["connectionsProvider<br/>(NotifierProvider&lt;ConnectionsNotifier, List&lt;Connection&gt;&gt;)"]
    conn --> cac["connectionActiveCountProvider"]
    conn --> csum["connectionSummaryProvider"]

    txp["transfersProvider<br/>(NotifierProvider&lt;TransfersNotifier, TransfersState&gt;)"]
    txp --> at["activeTransfersProvider"]
    txp --> th["transferHistoryProvider"]
    txp --> ts["transferStatusProvider"]

    sec["securityCapabilitiesProvider<br/>(FutureProvider)"]
    sec --> hpd["hardwareProbeDetailProvider"]
    sec --> kpd["keyringProbeDetailProvider"]
```

### 4.2 Provider Catalog

Generated from `lib/providers/` — each row points at the file that defines the provider. Providers feeding other providers list the dependency in the third column.

#### Session, config, locale, theme

| Provider | Type | Source / depends on |
|---|---|---|
| `sessionProvider` | `NotifierProvider<SessionNotifier, List<Session>>` | `session_provider.dart` — FRB DAO (`db_sessions_*`) + `BusTopic::Sessions` |
| `sessionsByIdProvider` | `Provider<Map<String, Session>>` | derives from `sessionProvider`. Use `ref.watch(sessionsByIdProvider.select((m) => m[id]))` for any per-session row widget that needs to resolve a foreign-key target by id (`SessionViaBadge` resolving `via_session_id` is the load-bearing case). Pre-fix every per-row widget ran an O(N) `firstWhere` on every list mutation → O(N²) per refresh; the derived map + `.select` collapses that to O(1) per badge with no rebuild when the specific bastion's row didn't change |
| `sessionsLoadingProvider` | `NotifierProvider<SessionsLoadingNotifier, bool>` | `session_provider.dart` — `true` while the initial load is in flight |
| `sessionSearchProvider` | `NotifierProvider<SessionSearchNotifier, String>` | `session_provider.dart` |
| `filteredSessionsProvider` | `Provider<List<Session>>` | `sessionProvider` + `sessionSearchProvider` |
| `filteredSessionTreeProvider` | `Provider<List<SessionTreeNode>>` | `sessionProvider` + `sessionSearchProvider` |
| `preloadedAppConfigProvider` | `Provider<AppConfig?>` | `config_provider.dart` — overridden in `main.dart` with the snapshot from the Rust `config_store` actor so `ConfigNotifier.build()` seeds without re-reading the actor |
| `configProvider` | `NotifierProvider<ConfigNotifier, AppConfig>` | `config_provider.dart` — sync via `lfs_core::config_store` (debounce + atomic write + bus event) |
| `themeModeProvider` | `Provider<ThemeMode>` | derived from `configProvider` |
| `localeProvider` | `Provider<Locale?>` | derived from `configProvider` (null = OS auto-detect) |

#### Connections + workspace + transfers

| Provider | Type | Source / depends on |
|---|---|---|
| `connectionsProvider` | `NotifierProvider<ConnectionsNotifier, List<Connection>>` | `connection_provider.dart` — subscribes to `BusTopic::Connection`; `connectionsProvider.notifier` exposes connect / disconnect / reconnect methods |
| `connectionActiveCountProvider` | `StreamProvider<int>` | `connection_provider.dart` — count of `connecting` + `connected` for status indicator |
| `foregroundActiveCountListenerProvider` | `Provider<void>` | `connection_provider.dart` — keeps the Android foreground service alive while ≥ 1 connection is live |
| `connectionSummaryProvider` | `Provider<ConnectionSummary>` | `connection_provider.dart` — derived counts for the sidebar footer |
| `foregroundServiceProvider` | `Provider<ForegroundServiceManager>` | `connection_provider.dart` |
| `workspaceProvider` | `NotifierProvider<WorkspaceNotifier, WorkspaceState>` | `features/workspace/workspace_controller.dart` |
| `transfersProvider` | `NotifierProvider<TransfersNotifier, TransfersState>` | `transfer_provider.dart` — subscribes to `BusTopic::Transfer*` |
| `activeTransfersProvider` | `Provider<List<ActiveEntry>>` | derived from `transfersProvider` |
| `transferHistoryProvider` | `Provider<List<HistoryEntry>>` | derived from `transfersProvider` |
| `transferStatusProvider` | `Provider<ActiveTransferState>` | derived from `transfersProvider` |

#### Security stack

| Provider | Type | Source / depends on |
|---|---|---|
| `masterPasswordProvider` | `Provider<MasterPasswordManager>` | `master_password_provider.dart` |
| `sessionCredentialCacheProvider` | `Provider<SessionCredentialCache>` | `session_credential_cache_provider.dart` |
| `secureKeyStorageProvider` | `Provider<SecureKeyStorage>` | `security_provider.dart` |
| `biometricAuthProvider` | `Provider<BiometricAuth>` | `security_provider.dart` |
| `biometricKeyVaultProvider` | `Provider<BiometricKeyVault>` | `security_provider.dart` |
| `keychainPasswordGateProvider` | `Provider<KeychainPasswordGate>` | `security_provider.dart` |
| `hardwareTierVaultProvider` | `Provider<HardwareTierVault>` | `security_provider.dart` |
| `securityCapabilitiesProvider` | `FutureProvider<SecurityCapabilities>` | `security_provider.dart` — orchestrator-driven capability snapshot |
| `hardwareProbeDetailProvider` | `FutureProvider<HardwareProbeDetail>` | `security_provider.dart` — typed unavailability reason for the hardware-vault Settings card |
| `keyringProbeDetailProvider` | `FutureProvider<KeyringProbeResult>` | `security_provider.dart` — typed unavailability reason for the keychain Settings card |
| `securityStateProvider` | `NotifierProvider<SecurityStateNotifier, SecurityState>` | `security_provider.dart` — current tier + modifiers + DB key holder |
| `lockStateProvider` | `NotifierProvider<LockStateNotifier, bool>` | `core/security/lock_state.dart` |
| `autoLockMinutesProvider` | `NotifierProvider<AutoLockMinutesNotifier, int>` | `auto_lock_provider.dart` |
| `firstLaunchBannerProvider` | `NotifierProvider<FirstLaunchBannerNotifier, FirstLaunchBannerData?>` | `first_launch_banner_provider.dart` |
| `securityReinitProvider` | `NotifierProvider<SecurityReinitNotifier, int>` | `security_reinit_provider.dart` — bumps to force re-evaluation after a tier switch / wipe |

#### Tags, snippets, keys, known hosts

| Provider | Type | Source / depends on |
|---|---|---|
| `tagsProvider` | `AsyncNotifierProvider<TagsNotifier, List<Tag>>` | `tag_provider.dart` |
| `sessionTagsProvider` | `FutureProvider.family<List<Tag>, String>` | `tag_provider.dart` |
| `folderTagsProvider` | `FutureProvider.family<List<Tag>, String>` | `tag_provider.dart` |
| `snippetsProvider` | `AsyncNotifierProvider<SnippetsNotifier, List<Snippet>>` | `snippet_provider.dart` |
| `sessionSnippetsProvider` | `FutureProvider.family<List<Snippet>, String>` | `snippet_provider.dart` |
| `sshKeysProvider` | `AsyncNotifierProvider<SshKeysNotifier, List<SshKeyEntry>>` | `key_provider.dart` |
| `knownHostsProvider` | `NotifierProvider<KnownHostsNotifier, Map<String, String>>` | `known_hosts_provider.dart` |

#### Updates, version, terminal broadcast

| Provider | Type | Source / depends on |
|---|---|---|
| `updateServiceProvider` | `Provider<UpdateService>` | `update_provider.dart` |
| `updateProvider` | `NotifierProvider<UpdateNotifier, UpdateState>` | `update_provider.dart` |
| `appVersionProvider` | `NotifierProvider<AppVersionNotifier, String>` | `version_provider.dart` |
| `broadcastControllerProvider` | `Provider.family<BroadcastController, String>` | `broadcast_provider.dart` — per-tab broadcast input fan-out |

**Data flow pattern:**
```
UI watches provider → Provider reads/watches other providers →
Notifier.state updated → all dependent providers recompute → UI rebuilds
```

### 4.3 Widget-local controllers (`ChangeNotifier`)

App-wide state lives in Riverpod `NotifierProvider`s listed above. Widget-local state — dialog selection, pane navigation, per-tab caches — uses `ChangeNotifier` instead, read through `AnimatedBuilder`. The pattern:

```dart
class FooController extends ChangeNotifier {
  FooController({required this.arg});
  final SomeArg arg;
  // ... state fields + getters

  void mutate() {
    // ... update state
    notifyListeners();
  }
}

class _FooDialogState extends State<FooDialog> {
  late final FooController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = FooController(arg: widget.arg);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => /* renders from _ctrl */,
    );
  }
}
```

**When to pick this over Riverpod:**

| Criterion | `NotifierProvider` | `ChangeNotifier` |
|-----------|--------------------|------------------|
| Shared across widgets | Yes | No |
| Constructor-injected data (lists, maps) | Awkward (side-channel override needed) | Natural |
| Lifecycle bound to a single widget / dialog | Needs `.autoDispose` | Automatic via `dispose()` |
| Tested via `ProviderContainer` overrides | Yes | Direct instantiation, no container |

**Canonical examples:** [`FilePaneController`](#filepanecontroller) (one per file pane, SFTP / local), [`UnifiedExportController`](#53-session-manager-ui-featuressession_manager) (one per open export dialog).

---

## 5. Feature Modules

### 5.1 Terminal with Tiling (`features/terminal/`)

#### Files

| File | Class | Purpose |
|------|-------|---------|
| `terminal_tab.dart` | `TerminalTab` | Container: manages split tree, reconnect, shortcuts |
| `terminal_pane.dart` | `TerminalPane` | Single terminal: xterm widget + SSH shell pipe |
| `cursor_overlay.dart` | `CursorTextOverlay`, `kTerminalLineHeight` | Paints inverted character on block cursor (xterm overlay). Exports the canonical 1.2 line-height multiplier used by every custom painter that sits on top of `TerminalView`. |
| `tiling_view.dart` | `TilingView` | Recursive split-tree renderer. Drives terminal-pane tiling: `BranchNode`s are created by the divider drag handler + the Ctrl+\\ / Ctrl+Shift+\\ duplicate-shortcut path; `LeafNode`s materialise per pane. |
| `split_node.dart` | `SplitNode`, `LeafNode`, `BranchNode` | Sealed class for split tree |
| `broadcast_controller.dart` | `BroadcastController` | Per-tab fan-out for terminal broadcast input — see [§5.1 Broadcast input](#broadcast-input--per-tab-fan-out). Wired to terminal panes via `broadcastControllerProvider.family<BroadcastController, String>(tabId)`; driver + receiver roles set through the pane context menu. |

#### Split tree (tiling)

```dart
sealed class SplitNode {}

class LeafNode extends SplitNode {
  final String id;   // unique pane ID
}

class BranchNode extends SplitNode {
  final SplitDirection direction;  // horizontal | vertical
  final double ratio;              // 0.0-1.0, divider position
  final SplitNode first;
  final SplitNode second;
}
```

**Example:**

```
BranchNode(horizontal, 0.5)
├── LeafNode("pane-1")           ← left half
└── BranchNode(vertical, 0.5)   ← right half
    ├── LeafNode("pane-2")      ← top right
    └── LeafNode("pane-3")      ← bottom right
```

**Operations:**
- `replaceNode(oldId, newNode)` — split a pane (leaf → branch)
- `removeNode(id)` — remove a pane (branch → remaining child)
- `collectLeafIds()` — all pane IDs (for iteration)

#### TerminalPane — internals

```
TerminalPane(connection, paneId)
  ├── ProgressWriter subscribes to connection.progressStream
  │   └── writes ANSI-styled steps to terminal: [*] → [✓] / [✗]
  ├── await connection.waitUntilReady()
  ├── on success: clear terminal → ShellHelper.openShell()
  │   ├── xterm Terminal() ← pipe ← shell.stdout
  │   │                    → pipe → shell.stdin
  │   └── resize → connection.resizeTerminal(cols, rows)
  ├── on error: progress log stays visible with error text
  └── hardwareKeyboardOnly: true (on desktop)
```

**Connection progress:** Instead of a spinner, TerminalPane writes structured progress steps directly into the xterm buffer using ANSI color codes (yellow `[*]` for in-progress, green `[✓]` for success, red `[✗]` for failure). On successful connection the terminal clears and the shell appears; on failure the log stays visible. Cursor is hidden during progress display via `\x1B[?25l` and restored on clear/error.

**Why `hardwareKeyboardOnly: true` on desktop:** xterm TextInputClient is broken on Windows — causes input duplication.

**Focus indicator:** No border is drawn on panes — the 4 px divider in `TilingView` already separates them visually. The focused pane is identifiable by the active cursor and toolbar highlight.

**Context menu:** Right-click is handled by a `Listener(onPointerDown:)` wrapping `TerminalView`, not by xterm's `onSecondaryTapUp`. This ensures the context menu works even when the terminal is in mouse mode (htop, vim, etc.), because `Listener` operates at the raw pointer level before xterm's gesture detector can consume the event.

**Shift-bypass for mouse mode (desktop):** When a TUI app enables mouse mode (htop, vim, mc, etc.), all mouse events are forwarded to the app. Holding **Shift** temporarily suspends pointer-input forwarding via `TerminalController.setSuspendPointerInput(true)`, letting the user drag-select text locally — standard behaviour matching xterm, GNOME Terminal, and other emulators. State is updated via a `HardwareKeyboard` handler registered in `TerminalPaneState`; the handler fires on every key event and recalculates based on current Shift state + `Terminal.mouseMode`.

**Drag-selection anchor pinning (`AnchorPinningTerminalController`):** xterm 4.0.0's `TerminalGestureHandler` stores the drag-start position as a raw widget pixel and recomputes both selection endpoints via `RenderTerminal.getCellOffset(localPx)` on every drag update. `getCellOffset` adds the *current* `_scrollOffset` to the pixel y, so a wheel scroll between drag-start and the next drag update reinterprets the start pixel against a different scroll position and the `base` anchor silently jumps to a new buffer row — visually the selection collapses to the visible viewport and copy returns the wrong range. `AnchorPinningTerminalController` (in `features/terminal/`) is a `TerminalController` subclass that, while a primary-mouse drag is in flight, pins the first observed `(BufferLine, x)` and re-creates a fresh `CellAnchor` on every subsequent `setSelection` call — re-creation is required because xterm's base `setSelection` disposes the prior `_selectionBase`, which would detach a pinned anchor after one reuse. If the pinned line rotates out of the scrollback (`BufferLine.attached == false`), the next call adopts the fresh `base` instead of minting an anchor on a detached line. The pin is armed in the existing right-click `Listener.onPointerDown` (alongside the context-menu branch) and released on `onPointerUp` / `onPointerCancel`. The trigger is narrowed to `PointerDeviceKind.mouse` + `kPrimaryButton` and skipped while `Terminal.isUsingAltBuffer` is true: touch goes through xterm's long-press word-extend (which passes a left-extending `range.begin` the pin would freeze), and the alt-buffer has no scrollback so the bug cannot occur there. `clearSelection` drops the pin so non-drag selection paths (double-tap word, search highlight) stay unaffected.

#### Keyboard Shortcuts

Terminal uses `Ctrl+Shift+` prefix to avoid conflicts with terminal escape sequences (Ctrl+C = SIGINT). Other panels use classic shortcuts since they don't contain a terminal.

**Global** (`main.dart` — `CallbackShortcuts`):

| Shortcut | Action |
|----------|--------|
| Ctrl+N | New session dialog |
| Ctrl+W | Close active tab |
| Ctrl+Tab / Ctrl+Shift+Tab | Next / previous tab |
| Ctrl+B | Toggle sidebar |
| Ctrl+\\ / Ctrl+Shift+\\ | Duplicate tab right / down (any tab type) |
| Ctrl+Shift+M | Toggle panel maximize (zoom) |
| Ctrl+, | Toggle settings |

**Terminal** (`terminal_pane.dart`):

| Shortcut | Action |
|----------|--------|
| Ctrl+Shift+C | Copy selection |
| Ctrl+Shift+V | Paste clipboard |
| Ctrl+Shift+F | Toggle search bar |
| Escape | Close search bar |

**SFTP file browser** (`file_pane.dart` — `Focus.onKeyEvent`):

| Shortcut | Action |
|----------|--------|
| Ctrl+A | Select all files |
| Ctrl+C | Copy selected entries to SFTP clipboard |
| Ctrl+V | Paste — transfer clipboard entries to this pane |
| F2 | Rename (single selection) |
| F5 | Refresh |
| Delete | Delete selected files |

SFTP clipboard is managed by `FileBrowserTab` — stores entries + source pane ID. Ctrl+C in local pane → Ctrl+V in remote pane = upload (and vice versa). Separate from session clipboard.

**Session panel** (`session_panel.dart` — `Focus.onKeyEvent`):

| Shortcut | Action |
|----------|--------|
| Ctrl+C | Copy focused session to session clipboard |
| Ctrl+V | Paste — duplicate copied session |
| Ctrl+Z / Ctrl+Y | Undo / redo session changes |
| F2 | Edit focused session |
| Delete | Delete focused session |

Session clipboard stores a session ID. Ctrl+V duplicates that session via `SessionNotifier.duplicate()`. Independent from SFTP clipboard.

#### Broadcast input — per-tab fan-out

`BroadcastController` (`features/terminal/broadcast_controller.dart`) is a `ChangeNotifier` instantiated per tab via `broadcastControllerProvider.family<BroadcastController, String>(tabId)`. One pane in a tab can be the **driver**; every byte its `Terminal.onOutput` produces is mirrored into every registered **receiver** pane's shell sink. The pane registers itself in `_attachBroadcast` once `_openShell` returns, and unregisters in `dispose` — `_broadcastUnsubscribe` cleans up the listener subscription, `BroadcastController.unregisterSink` clears the role assignment.

**Why per-tab and not workspace-global.** A workspace-wide controller would let a driver in tab A leak keystrokes into tab B's panes after a tab switch — almost never what the user wants. Tying the lifetime of the controller to the tab matches the user's mental "I'm broadcasting in this tab" model and survives split / unsplit operations within the same tab. Trade-off: re-opening a tab from scratch gives a fresh controller; we accept that because the alternative (persisting broadcast state across tab close) is the worse default.

**Driver / receiver wiring.**
- `_attachBroadcast` wraps `Terminal.onOutput` so the original hook installed by `ShellHelper.openShell` still runs; the wrapper additionally calls `controller.broadcastFrom(paneId, bytes)` when `controller.isDriver(paneId)` is true. The driver's own shell still receives the bytes through the original hook — broadcast is a side-channel, never a replacement.
- Receivers register a sink that calls `shell.write(bytes)` directly. The controller iterates the sink list in registration order and wraps each call in `try/catch` — a torn-down receiver shell never stalls the driver loop.
- `isActive` requires both a driver and at least one *other* receiver. A driver alone does not broadcast; toggling the driver's id in the receiver set is filtered out.

**Visual indicator.** The pane build wraps its content in a `Container` whose `Border.all` colour is `AppTheme.yellow` for both driver and receiver, with a slightly thicker stroke (2.5 px) on the driver. Active state is read from the per-tab controller via `ref.watch(broadcastControllerProvider(tabId))` so border updates land on the same `notifyListeners()` cycle that flips the role.

**Paste guard.** When the focused pane is the active driver, `_pasteClipboard` shunts through a confirmation dialog (`broadcastPasteTitle` / `broadcastPasteBody` / `broadcastPasteSend`) before letting the bytes through. The body string carries character count + receiver count so the user gets a concrete picture of the blast radius before sending. Cancel returns to the pane without writing anything; confirm calls `terminal.paste(text)` so the broadcast wrapper fires (sending paste bytes through the bypass would skip every receiver — wrong by construction).

**Single-pane / mobile guard.** `TerminalPane.supportsBroadcast` returns `paneId != null && tabId != null`. The mobile shell and quick-connect surfaces don't plumb either id, so every broadcast path stays inert and the context menu does not grow misleading entries on solo panes. The desktop tiling view passes both ids through `TilingView._buildLeaf`.

---

### 5.2 File Browser (`features/file_browser/`)

#### Files

| File | Class | Purpose |
|------|-------|---------|
| `file_browser_tab.dart` | `FileBrowserTab` | Dual-pane container: local + remote |
| `file_pane.dart` | `FilePane` | Single pane: table + path bar + navigation. State (`_FilePaneState`) keeps build / lifecycle / `MarqueeMixin` overrides; the per-section helpers live in part siblings. |
| `file_pane_layout.dart` | — (`extension _Layout`) | Header / breadcrumb / path editor / nav / column headers / file-list / footer / drop-target builders. Routes setState through the State's `rebuild(VoidCallback)` wrapper. |
| `file_pane_actions.dart` | — (`extension _Actions`) | Context menus + dialog wrapper handlers (delegated to `FilePaneDialogs`). |
| `file_pane_dialogs.dart` | — | Dialogs: New Folder, Rename, Delete |
| `file_row.dart` | `FileRow` | Row in the file table |
| `breadcrumb_path.dart` | `BreadcrumbPath`, `parseBreadcrumbPath()`, `buildPathForSegment()` | Shared breadcrumb path parsing for desktop and mobile file browsers |
| `column_widths.dart` | `FileBrowserColumns` | Shared default widths for Size + Modified/Time columns. `FilePane` and `TransferPanelController` both use these so the SFTP tab and transfer queue stay visually aligned |
| `file_browser_controller.dart` | `FilePaneController` | Pane state: listing, navigation, selection, sort |
| `sftp_browser_mixin.dart` | `SftpBrowserMixin` | Shared mixin: SFTP init, upload, download — used by `FileBrowserTab` and `MobileFileBrowser` |
| `sftp_initializer.dart` | `SFTPInitializer` | SFTP initialization factory (injectable) |
| `transfer_panel.dart` | `TransferPanel` | Bottom panel: progress + history (resizable columns, sorting, column dividers). State (expand, height, column widths, sort column + direction) lives on `TransferPanelController` |
| `transfer_panel_controller.dart` | `TransferPanelController`, `TransferSortColumn` | Headless `ChangeNotifier` — resize clamps, sort-cycle rules, auto-expand edge (fires once per false→true `isRunning` transition), pure `sorted(history)` comparator. Same pattern as [`FilePaneController`](#filepanecontroller) |
| `transfer_helpers.dart` | `TransferHelpers` | Upload/download helpers; `enqueueUpload`/`enqueueDownload` accept `required S loc` for localized status strings |

#### FilePaneController

```dart
class FilePaneController extends ChangeNotifier {
  FilePaneController(FileSystem fs, String initialPath);

  // Navigation
  Future<void> navigateTo(String path);
  void goBack();
  void goForward();
  void goUp();
  String get currentPath;

  // File listing
  List<FileEntry> get entries;        // current contents
  bool get isLoading;

  // Sorting
  SortColumn get sortColumn;          // name, size, mode, modified, owner
  SortOrder get sortOrder;            // asc, desc
  void sort(SortColumn column);

  // Selection
  Set<int> get selectedIndices;
  void select(int index, {bool ctrl, bool shift});
  void selectAll();
  void clearSelection();

  // Folder sizes
  Future<void> calculateFolderSizes(); // async, max 2 concurrent
}
```

**Why `ChangeNotifier` instead of Riverpod:** Lightweight per-pane state. Each pane creates its own controller. Riverpod adds overhead not justified for such local state.

#### Desktop vs Mobile file browser

| Aspect | Desktop | Mobile |
|--------|---------|--------|
| Layout | Dual-pane (local + remote) | Single-pane (toggle local/remote) |
| Selection | Marquee + click + Ctrl/Shift | Long-press → bulk mode |
| Drag & drop | Between panes + from OS | None |
| Navigation | Click + path bar | Tap + swipe |

---

### 5.3 Session Manager UI (`features/session_manager/`)

#### Files

| File | Class | Purpose |
|------|-------|---------|
| `session_panel.dart` | `SessionPanel` | Sidebar: tree view + search + actions + bulk select. Header has "New Folder" and "New Connection" buttons. State (multi-select, focus, marquee, clipboard) lives on `SessionPanelController`; the widget is wired through `AnimatedBuilder`. Build / lifecycle / shortcut bindings / bulk-ops / sidebar layout in this file; per-section helpers in part siblings (`session_panel_widgets`, `session_panel_session_actions`, `session_panel_folder_actions`). |
| `session_panel_widgets.dart` | — | Static helper widgets (`_PanelHeader`, `_SearchBar`, `_EmptyState`, `_SessionDetailsPanel`, `_DetailRow`, `_SidebarFooter`). Pure StatelessWidget extraction. |
| `session_panel_session_actions.dart` | — (`extension _SessionActions`) | Per-session context menu (desktop) / bottom sheet (mobile) + add / edit / move / dialog wrappers + `_confirmDelete`. |
| `session_panel_folder_actions.dart` | — (`extension _FolderActions`) | Per-folder context menu / bottom sheet + create / rename / delete folder + folder-name input dialog. |
| `session_panel_controller.dart` | `SessionPanelController` | Headless `ChangeNotifier` holding the panel's selection set, focused session / folder, marquee progress, and copied-session clipboard. Same pattern as [`FilePaneController`](#filepanecontroller) |
| `session_tree_view.dart` | `SessionTreeView` | Hierarchical list with drag & drop. Uses `FolderDrag` for folder drag data. Session icon color: green (connected), yellow (connecting), grey (disconnected). State + lifecycle + MarqueeMixin overrides + tree helpers in this file; drag & drop, pointer handlers, and the per-row build chain in `session_tree_view_internals.dart`. |
| `session_tree_view_internals.dart` | — (`extension _Internals`) | Drag & drop (`_canAcceptDrop` / `_canAcceptBulkDrop` / `_handleDrop`), pointer handlers (`_onPointerDown` / `_onPointerMove` / `_clampedIndex` / `_onPointerUp`), and the per-row build chain (`_buildDragTarget` / `_buildTreeRow` / `_buildDragFeedback` / `_buildFolderContent` / `_onFolderTap` / `_buildFolderTile` / `_onSessionTap` / `_buildSessionTile`). |
| `session_edit_dialog.dart` | `SessionEditDialog` | Create/edit session form. **Single-form layout, no tabs** — the dialog body is one vertical `SingleChildScrollView` with three section composers (`Identity` block at the top — name + kind picker; `Connection` section with the per-protocol transport block; `Authentication` section with the per-protocol credential block; `More options` collapsible holding tags + ProxyJump + port-forwarding row + record-session toggle). The kind picker is the single lever and is visible from every scroll position — flipping it reshapes the Connection / Authentication sections in place rather than swapping hidden tabs. **The SSH connect surface is one smart-paste field** (`_connectCtrl`, labelled `CONNECT TO`) that accepts `[user@]host[:port]`; on every edit a listener parses the text through `rust_sessions.sessionsParseSshTarget` (Rust `lfs_core::sessions::parse_ssh_target`) and writes the result into `_hostCtrl` / `_portCtrl` / `_userCtrl` so the existing save path and Rust-side validators keep reading the same tuple. Parse failures leave the previous good values in place (mid-typing edge case); the field's validator surfaces `connectStringInvalid` ("Invalid format — expected user@host:port") on Save, plus a separate `required` verdict when the parser tolerates a bare host but no user prefix is present. Per-section composers live in part siblings: `session_edit_dialog_connection.dart` (extension `_ConnectionSection` — `_buildIdentityBlock`, `_buildConnectionBlock`, the kind picker, and the per-protocol SSH / WebDAV / S3 sub-builders; the SSH branch is just the smart-paste field — ProxyJump moved to More options), `session_edit_dialog_auth.dart` (extension `_AuthSection` — `_buildAuthBlock` dispatch + `_buildSshAuthSection` / `_buildWebDavAuthSection` / `_buildS3AuthSection`; SSH = ssh-agent toggle + password / key store / inline-PEM / passphrase; WebDAV = method chips + credential field whose label flips to "BEARER TOKEN *" for bearer + self-signed-cert fingerprint pin; S3 = single `SECRET ACCESS KEY *` field; the "Key from manager" picker renders each row's backend badge via the shared `HardwareKeyBadge` / `Pkcs11Badge` / `EnclaveBadge` / `HelloBadge` / `TpmBadge` / `KeystoreBadge` widgets), `session_edit_dialog_options.dart` (extension `_AdvancedSection` — `_buildAdvancedBlock` rendered inside an `AnimatedSize` expander; tags universally — applicable to every kind; ProxyJump editor + port-forwarding row + Manage button opening `SessionForwardsDialog` + record-session toggle for SSH only because WebDAV / S3 transports never open a shell to record), and `session_edit_dialog_results.dart` (the `SessionDialogResult` sealed hierarchy + `SaveResult` / `WebDavSaveData` / `S3SaveData` payloads the dialog pops). The smart-paste validator collapses the old per-field SSH validators (host required, port range, user required) into one verdict; WebDAV / S3 keep their per-field `*`-suffixed labels because those transport shapes don't compose into a single string. `_save` rejects an invalid form with a `Toast.show(level: warning)` ("Fill the required fields marked *") plus the form-level inline-error path (red border + error text per `StyledFormField`), so a stray empty required field surfaces both globally and locally without needing tab routing. The disabled ssh-agent toggle on mobile binds a no-op `onTap` so a tap on it is absorbed at the HoverRegion layer instead of bubbling through to the dialog's `barrierDismissible` and closing the form. Selecting "Use system ssh-agent" stamps `AuthType.agent` on the session row and clears the per-row key / password slots — the connect path reads `SshAuth.useAgent` (set by `Session.toSSHConfig` from `authType`) and short-circuits to `SshAuthAgent` inside `ConnectionsNotifier._authFromConfig` before the auth composer runs. Mobile builds keep the toggle visible but disabled — the agent endpoint is desktop-only because Android / iOS have no system ssh-agent equivalent to dial. |
| `session_connect.dart` | `SessionConnect` | Connection logic: Session → resolve keyId → SSHConfig → ConnectionsNotifier. Async to support key store lookup |
| `quick_connect_dialog.dart` | `QuickConnectDialog` | Quick connect without saving |
| `qr_display_screen.dart` | `QrDisplayScreen` | QR code display for session sharing (scan or copy link). The bottom badge switches between a neutral "No passwords in QR" info and an orange warning (`qrContainsCredentialsWarning`) depending on the `containsCredentials` flag the caller passes — so the screen doesn't claim there are no passwords when the user enabled `includePasswords` / `includeManagerKeys` in the preceding export dialog |
| `unified_export_dialog.dart` | `UnifiedExportDialog` | Unified export dialog for both QR and `.lfs`. Preset chips ("Full backup" / "Sessions"), session tree with checkboxes, data type selection (passwords, embedded keys, session-bound manager keys, all manager keys, config, known_hosts, tags, snippets), QR size indicator. Widget is a thin `AnimatedBuilder` shell over `UnifiedExportController` — selection / options / cached-size logic lives in the controller so it can be tested without a widget tree |
| `unified_export_controller.dart` | `UnifiedExportController`, `ExportPreset` | Headless `ChangeNotifier` driving the dialog: session selection set, `ExportOptions` with preset helpers, mutually-exclusive key-scope flags, cached payload / credential / empty-folder sizing. Same pattern as [`FilePaneController`](#filepanecontroller) — widget-local state that does not belong in a Riverpod provider |
| `lfs_import_preview_dialog.dart` | `LfsImportPreviewDialog` | Preview .lfs archive contents before import. Filename header, preset chips (Full / Selective), collapsible checkbox grid with per-type counts on the right, merge/replace mode selector. Every checkbox is always clickable so replace mode can express "wipe this type" via a checked row even when the archive carries zero entries |
| `link_import_preview_dialog.dart` | `LinkImportPreviewDialog` | Mirror of `LfsImportPreviewDialog` for `letsflutssh://import?…` deep links and scanned QR payloads. Same preset chips / checkbox grid / merge+replace selector, counts come from the `LfsPreview` projected off the Rust-staged handle (`QrDecodedSource.rust`), so link/QR imports share the archive flow's opt-in/out UX |
| `ssh_dir_import_dialog.dart` | `SshDirImportDialog` | Unified picker for `~/.ssh` contents. Two collapsible sections — "Hosts from config" (from `~/.ssh/config`) and "Keys in ~/.ssh" (scanner output). Each section has a tristate "select all" row, a divider, then the indented per-item list. A "Browse files…" button per section opens a `FilePicker` rooted at `~/.ssh` so the user can pull in an extra config file or key files from elsewhere. Parsed hosts whose `user@host:port` already exists as a session, and keys whose fingerprint matches an entry in the key store, are flagged with an "already in sessions" / "already in store" trailing tag and default to **unchecked** — the same dedup contract the .lfs / QR import flow applies to session IDs and key fingerprints. New picks are deduped by session id (hosts) or private-key fingerprint (keys). Returns one combined `ImportResult` routed through the same `_applyFilteredImport` path as the .lfs archive import |
| (`lib/widgets/core/data_checkboxes.dart`) | `CollapsibleCheckboxesSection`, `DataCheckboxRow` | Shared visual primitives for checkbox grids — lives in `lib/widgets/` (not under `features/session_manager/` despite the export dialog being its main consumer). Used by [`UnifiedExportDialog`](#unifiedexportdialog), `LfsImportPreviewDialog`, and `SshDirImportDialog` so every checkbox list in the app has identical chevron/hover/label/trailing layout |

#### SessionConnect — flow

```dart
class SessionConnect {
  // Terminal:
  static Future<void> connectTerminal(Session session, WidgetRef ref) {
    // 1. Session → SSHConfig (with credentials from CredentialStore)
    // 2. connectionManager.connectAsync(config)
    // 3. workspaceProvider.addTerminalTab(connection)
  }

  // SFTP:
  static Future<void> connectSftp(Session session, WidgetRef ref) {
    // 1-2. Same as above
    // 3. workspaceProvider.addSftpTab(connection)
  }
}
```

#### Session panel input model

The sidebar owns its own keyboard/focus/pointer contract. Four invariants hold across every change in this area:

- **Shortcut dispatch is `CallbackShortcuts`-based**, not a `Focus.onKeyEvent` handler. `SessionPanel.build` wraps the root in `CallbackShortcuts(bindings: _buildShortcutBindings())` so `Ctrl+C` / `Ctrl+X` / `Ctrl+V` / `Ctrl+Z` / `Ctrl+Y` / `Delete` / `F2` fire as long as *any* `FocusNode` descendant of the panel holds focus. An earlier `Focus(onKeyEvent:)` version fired only when the panel root itself was focused — clicking a session row handed focus to an inner `Draggable` / `AppIconButton`, and the shortcut fell back on nothing ("works every other time"). The panel-level `Focus(autofocus: false)` stays for the "panel owns focus → rows render in accent colour" visual state; the shortcut path is independent.
- **Empty-sidebar tap drops the focused pointer, never the `FocusNode`.** `onEmptySpaceTap` calls `_ctrl.clearFocus()` (nulls `focusedSessionId` + `focusedFolderPath` so the row highlight dims to grey) but leaves `_focusNode` focused. Yanking the Flutter focus would drop the panel out of the `CallbackShortcuts` scope — subsequent `Ctrl+V` / `Ctrl+Z` after an empty-space click would silently do nothing.
- **Folder click is two-phase.** First tap on an unfocused folder focuses it (sets the paste target, no toggle); a second tap on the already-focused folder toggles expand. The branch lives in `session_tree_view._onFolderTap`, keyed off `widget.focusedFolderPath == fullPath`. Mirrors macOS Finder's column view and closes the "click folder to paste into it, it collapses instead" regression. Mobile keeps the single-tap toggle — long-press there is the focus-without-toggle alternative.
- **Paste target is resolved at paste time** via `_resolvePasteTargetFolder`: focused folder first, then the folder of the focused session, then root. `pasteCopiedSession` forwards the target to `sessionProvider.duplicate(id, targetFolder:)` so the duplicate lands directly in the destination — no intermediate state the user can observe between "copy made" and "copy moved into place". `duplicateSession` in the store accepts the same `targetFolder` parameter; `FakeSessionNotifier` mirrors the signature. An `explicitTarget:` override on `pasteCopiedSession` lets the session and folder right-click menus force the target to the clicked row / folder regardless of current focus — matches "paste into this folder" without making the user pre-focus it.
- **Drop-zone covers the expanded folder's child rows, not just its header.** Every session row (`_buildSessionTile`) wraps its content in a `DragTarget<SessionDragData>` keyed off `session.folder`, so dropping a drag anywhere inside an expanded folder lands in that folder. Without the per-row wrap the drop fell through to the tree-root `DragTarget` (folder `""`) and the dragged session silently appeared at the root — users read this as "drag-into-folder only works on the folder row". DragTarget nesting resolves innermost-wins, so dropping directly on a sub-folder header still targets that sub-folder (its own `DragTarget` claims the hit first).

#### Session clipboard — pointer model

`SessionPanelController._copiedSessionId` is a 32-char session id, never a session object. Credentials live in the store's `SecretBuffer`s regardless of whether the id is on the clipboard — there is no session data duplicated in RAM.

- `copyFocused()` and `cutFocused()` both set `_copiedSessionId = _focusedSessionId` and flip `_cutPending` accordingly. Cut is one-shot: the next paste consumes the flag and clears the clipboard, so a subsequent Ctrl+V defaults back to duplicate semantics.
- `clearClipboard()` runs on every successful cut paste, on panel `dispose`, and (via the wipe / reset flow) whenever the sidebar is torn down. There is **no wall-clock TTL** — an earlier 30-second auto-wipe caused a "works every other time" UX where the user's paste after a pause silently no-op'd. Since the clipboard is just a pointer, the stale-id window is bounded by panel lifetime, not by a timer.
- Paste of a stale id (session deleted before paste) is a silent no-op — `sessionProvider.duplicate` throws `ArgumentError('Session not found')` and the transactional `_run` wrapper swallows it under the "duplicate session" label in the activity log.
- **The Paste context-menu item is gated on `hasClipboardEntry`** (a copy/cut has stashed a session or folder). With an empty clipboard the entry would no-op, so the session and folder menus omit it entirely rather than show it disabled — context menus are action surfaces, where a control that can do nothing right now is hidden (the disable-with-tooltip treatment is reserved for configuration surfaces). The keyboard `Ctrl+V` path stays bound regardless and no-ops on an empty clipboard.

---

### 5.4 Tab & Workspace System

#### Tab Model (`features/tabs/`)

| File | Class | Purpose |
|------|-------|---------|
| `tab_model.dart` | `TabEntry`, `TabKind` | Tab model (id, label, connection, kind) |
| `welcome_screen.dart` | `WelcomeScreen` | Minimal empty state — icon, heading, subtitle; no buttons or shortcuts |

```dart
class TabEntry {
  final String id;          // UUID
  final String label;
  final Connection connection;
  final TabKind kind;       // terminal | sftp

  TabEntry copyWith({String? label});  // same id
  TabEntry duplicate();                // new UUID, same connection/label/kind
}
```

#### Workspace Tiling (`features/workspace/`)

| File | Class | Purpose |
|------|-------|---------|
| `workspace_node.dart` | `WorkspaceNode`, `PanelLeaf`, `WorkspaceBranch` | Sealed split tree for screen-level tiling |
| `workspace_controller.dart` | `WorkspaceNotifier`, `WorkspaceState` | State management: add/close/move/split/copy/select tabs across panels |
| `workspace_view.dart` | `WorkspaceView`, `WorkspaceViewState` | Recursive renderer: panels with dividers, tab bars, connection bars |
| `panel_tab_bar.dart` | `PanelTabBar`, `TabDragData` | Per-panel tab bar with cross-panel drag-and-drop |
| `drop_zone_overlay.dart` | `PanelDropTarget`, `DropZone`, `buildDropZoneOverlay()` | Snap/dock zones for tab dragging; shared overlay builder used by both panel and workspace edge targets |

#### Two-level tiling architecture

```
WorkspaceNode (screen-level — splits panels on screen)
  ├── WorkspaceBranch (direction + ratio)
  │     ├── PanelLeaf (tab stack A — own tab bar, own IndexedStack)
  │     └── PanelLeaf (tab stack B — own tab bar, own IndexedStack)
  └── ...recursive...

PanelLeaf → TabEntry → TerminalTab → SplitNode (internal pane tiling — unchanged)
```

**Screen-level split:** `WorkspaceNode` tree divides the screen into panels. Each `PanelLeaf` holds its own `List<TabEntry>` with an active index and renders its own `PanelTabBar` + `IndexedStack`.

**Terminal-level split:** `SplitNode` tree inside each `TerminalTab` divides a single terminal tab into panes. These two tiling levels are independent.

**Duplicate Right / Duplicate Down:** Toolbar buttons and Ctrl+\\ / Ctrl+Shift+\\ duplicate the active tab (any type) into a new adjacent panel via `WorkspaceNotifier.copyToNewPanel()`. The duplicate reuses the same `Connection` object (no new SSH connection), getting its own shell/SFTP channel.

**Panel maximize (zoom):** `WorkspaceState.maximizedPanelId` temporarily renders a single panel full-screen while preserving the workspace tree. Toggle via Ctrl+Shift+M, the connection bar button, or the tab context menu. Maximize is cleared automatically when the maximized panel is closed or the tree collapses to a single panel. Edge drop zones are disabled while maximized.

**Drag-and-drop:** Tabs can be dragged between panels. Dropping on a panel's tab bar inserts the tab. Dropping on a panel's content area shows drop zone overlays (center = add to panel, edges = split panel in that direction).

**IndexedStack:** Each panel uses its own `IndexedStack` — all tabs in a panel stay in memory, only the current one is visible. This preserves terminal state when switching tabs.

**Keyboard focus must follow the foreground tab.** Because `IndexedStack` keeps backgrounded tabs mounted, switching tabs does *not* change a pane's in-tab `isFocused` flag (`focusedPaneId == node.id`) — the hidden tab still believes its pane is focused. Without an extra signal the newly-shown terminal never re-asserts keyboard focus, so input keeps routing to the now-hidden pane until an OS-level focus round-trip (clicking outside the window) resets it. `WorkspaceView` therefore threads an `isActiveTab` flag — `panelIsFocused && idx == activeTabIndex` — down through `TerminalTab` → `TilingView` → `TerminalPane`. Keyboard ownership is the combined condition `isActiveTab && isFocused`: `TerminalPane.didUpdateWidget` calls `requestFocus()` when it flips false→true (tab brought forward, or split-pane focus moves) and `unfocus()` when it flips true→false. The `unfocus()` matters when the incoming tab has no terminal to steal focus — e.g. switching from a terminal tab to an SFTP tab — which would otherwise leave the hidden terminal owning the keyboard. Single-pane / mobile callers default `isActiveTab` to true (they have no tab switching).

**GlobalKey for cross-panel moves:** Both `TerminalTab` and `FileBrowserTab` use `GlobalKey` (managed by `WorkspaceViewState._terminalKeys` / `_fileBrowserKeys`). When a tab is dragged to a new panel, `GlobalKey` lets Flutter reparent the widget state instead of destroying and recreating it. Without this, SFTP tabs would re-run `_initSftp()` and show connection progress on every tiling split.

**Tab styling:** Active tab has `AppTheme.bg2` background with a 2 px `AppTheme.accent` top bar. Inactive tabs have `AppTheme.bg1` background. Icons are colored by kind (blue = terminal, yellow = SFTP) when active, `AppTheme.fgFaint` when inactive. Height: `AppTheme.barHeightSm` (34 px).

**Connection lifecycle:** When all tabs referencing a connection are closed across **all** panels, `WorkspaceNotifier` automatically disconnects the orphaned connection via `ConnectionsNotifier.disconnect()`.

**Panel collapse:** When the last tab in a panel is closed (or moved out), the panel is removed from the workspace tree and its sibling is promoted up.

---

### 5.5 Settings (`features/settings/`)

| File | Class | Purpose |
|------|-------|---------|
| `settings_screen.dart` | `SettingsScreen` | Mobile-only route (collapsible sections in a scrollable list) |
| `settings_screen.dart` | `SettingsDialog` | Desktop full-screen modal (VS Code style) — composes [`SidebarNavDialog`](#sidebarnavdialog) with the settings sections, a Reset-button footer, and a per-section `ListView` wrapper |
| `settings_dialogs.dart` | — | Dialog helpers (part of `settings_screen.dart`) |
| `settings_logging.dart` | — | Logging section widgets (part of `settings_screen.dart`) |
| `settings_widgets.dart` | — | Shared settings tiles/controls (part of `settings_screen.dart`) |
| `settings_sections_preferences.dart` | `_AppearanceSection`, terminal / connection / transfers tiles | Appearance + terminal + connection + transfers section widgets (part of `settings_screen.dart`) |
| `settings_sections_security.dart` | `_SecuritySection` | Security-tier card, biometric toggle, known-hosts entry point (part of `settings_screen.dart`) |
| `settings_sections_security_apply.dart` | — | Tier-apply pipeline: validates the wizard result, drives `_applyTierChange`, owns the rekey path (part of `settings_screen.dart`) |
| `settings_sections_security_biometric.dart` | — | Biometric capture step before Apply: routes through `verifyAndDeriveToSecret` so the AES bytes never touch the Dart heap (part of `settings_screen.dart`) |
| `settings_sections_security_macos.dart` | — | macOS-only Keychain enable / remove flow + the resign-required tail row (part of `settings_screen.dart`) |
| `settings_sections_data.dart` | data-section tiles | Data section root — export/import row, QR row, support-dir row (part of `settings_screen.dart`) |
| `settings_sections_data_export_import.dart` | `_ExportImportTile` | Export / import .lfs archives tile (part of `settings_screen.dart`) |
| `settings_sections_updates.dart` | `_UpdateSection` | Auto-update preferences + manual check (part of `settings_screen.dart`) |
| `known_hosts_manager.dart` | `KnownHostsManagerPanel`, `KnownHostsManagerDialog` | Known hosts management surface (search, delete, import, export, clear). Embeddable panel + thin dialog wrapper, same shape as the SSH-keys / snippets / tags managers. |
| `export_import.dart` | — | Export/import .lfs archives (UI + logic) |
| `tools/tools_dialog.dart` | `ToolsDialog` | Desktop full-screen modal — SSH Keys, Snippets, Tags, Known Hosts, Recordings. Composes [`SidebarNavDialog`](#sidebarnavdialog), which owns the lazy keep-alive content pane |
| `tools/tools_screen.dart` | `ToolsScreen` | Mobile Tools route — list of tool tiles (same entries as desktop dialog) |
| `key_manager/key_manager_dialog.dart` | `KeyManagerPanel` / `KeyManagerDialog` | SSH key panel (embeddable, built on `CollectionManagerPanel<SshKeyMetadata>`; keeps its `+ Add ▾` menu + import/generate/hardware flows) + dialog wrapper |
| `snippets/snippet_manager_dialog.dart` | `SnippetManagerPanel` / `SnippetManagerDialog` | Snippet panel (embeddable, built on `CollectionManagerPanel<Snippet>`) + dialog wrapper |
| `tags/tag_manager_dialog.dart` | `TagManagerPanel` / `TagManagerDialog` | Tag panel (embeddable, built on `CollectionManagerPanel<Tag>`) + dialog wrapper |

**Sections:** Appearance (language picker, theme, UI scale, font size), Terminal, Connection, Transfers, Security (known hosts manager), Data (export/import, QR, path), Logging, Updates, About. Language picker uses `PopupMenuButton` with native language names + English secondary labels. Theme selector labels (Dark/Light/System) are localized via `S.of(context)`.

**Desktop:** Toolbar has two buttons — **Tools** (wrench icon, opens `ToolsDialog` with SSH Keys / Snippets / Tags / Known Hosts / Recordings) and **Settings** (gear icon, opens `SettingsDialog`). Both are full-screen modal dialogs that share the [`SidebarNavDialog`](#sidebarnavdialog) shell — sidebar navigation + content pane (VS Code style). Sessions and terminals remain visible behind the dialog overlay.

**Mobile:** Two separate routes — `SettingsScreen` (gear icon) for settings, `ToolsScreen` (wrench icon) for SSH Keys / Snippets / Tags / Known Hosts. Both pushed as routes from the mobile shell top bar.

---

### 5.6 Mobile (`features/mobile/`)

| File | Class | Purpose |
|------|-------|---------|
| `mobile_shell.dart` | `MobileShell` | Bottom navigation: Sessions / Terminal / SFTP |
| `mobile_terminal_view.dart` | `MobileTerminalView` | Full-screen terminal + keyboard bar + copy-mode overlay |
| `terminal_copy_overlay.dart` | `TerminalCopyOverlay` | Trackpad-style virtual cursor + live selection + Copy/Cancel toolbar |
| `mobile_file_browser.dart` | `MobileFileBrowser` | Single-pane SFTP (toggle local/remote) |
| `ssh_keyboard_bar.dart` | `SshKeyboardBar` | Quick access panel: Ctrl, Alt, arrows, Fn, Paste, Copy. Main row is horizontally scrollable (`ListView`); Paste + Copy + Fn buttons are fixed at right edge. `applyModifiers` cascades Ctrl then Alt — Alt wraps the Ctrl result rather than replacing it, so Alt+Ctrl+X produces the standard `ESC + Ctrl-X` two-byte sequence emacs / readline reads as `C-M-x`. An earlier implementation wrote both transforms to the same `result` slot while reading the original `data`, silently collapsing the combo to bare Ctrl+X |
| `ssh_key_sequences.dart` | — | Escape sequences for keys |

**Gesture routing.** `MobileTerminalView` wraps the terminal area in a bare [`Listener`](https://api.flutter.dev/flutter/widgets/Listener-class.html) and tracks every active pointer in a `Map<int, Offset>`. One-finger events are *not* consumed by the Listener — they continue to xterm's internal gesture recognizers for scrolling + tap-to-focus; copy-mode routes single-finger drags through `_copyOverlayKey` to pan the virtual cursor instead. Multi-touch is intentionally unused. **Don't add pinch-to-zoom over `_fontSize`** — every pinch frame propagates through `TerminalView` into `Terminal.buffer.resize` (cell width changes ↔ columns change), which reflows the scrollback dozens of times per gesture and produces visible garbage. Font size is driven **only** by the Settings slider — one commit per release, one reflow, manageable. **Don't add a stock `ScaleGestureRecognizer`** either: it treats a single-pointer drag as a 1× scale and wins the gesture arena, silently killing xterm's own recognizers sharing the same subtree.

**Touch selection is opt-in.** xterm's built-in `TerminalGestureHandler` routes every touch long-press into `renderTerminal.selectWord` and every single-finger drag into `renderTerminal.selectCharacters`. On mobile that free-for-all collided with the dedicated copy-mode overlay — users could stamp a stray word selection by holding a finger anywhere and had no way to disable it. There is no public xterm flag to turn that path off, and winning the gesture arena at a parent level would also steal the scroll gesture. The workaround lives on the **controller** instead: `MobileTerminalView` attaches a listener to its `TerminalController` that calls `clearSelection()` whenever a new selection appears while the copy-mode overlay is *not* active. The guard no-ops when selection is already null, so the follow-up `notifyListeners` call does not recurse. The overlay itself remains the only sanctioned selection surface on mobile; desktop is untouched because long-press-to-word-select is a first-class desktop flow.

**Copy mode — xterm is isolated while active.** xterm's `TerminalGestureHandler` owns a `PanGestureRecognizer` that fires `renderTerminal.selectCharacters` on every single-finger drag; the companion `TerminalScrollGestureHandler` owns the scrollback scroll recognizer. `setSuspendPointerInput(true)` gates only mouse-reporting to the remote shell — it does not mute either of those local recognizers. Left unchecked they used to race `TerminalCopyOverlay.onCursorPan` frame-by-frame, with both paths writing to `TerminalController.setSelection`; the competing calls painted duplicate rows + selection gaps across the scrollback. The fix wraps `TerminalView` in `AbsorbPointer(absorbing: _copyMode, …)`. The outer `Listener` is an ancestor — it still observes the same pointer events via the ancestor hit-test path — so `onCursorPan` keeps flowing while xterm's own recognizers see nothing. Regression gate: the "AbsorbPointer gates the terminal while copy mode is active" widget test in `mobile_terminal_view_test.dart`.

**Copy mode — aim, then extend, with an explicit commit.** The overlay has a two-phase selection model. Entering copy mode shows the virtual cursor at the current shell cursor (or viewport centre if the cursor is off-screen); the selection anchor is **not** stamped. In the aim phase, *every* single-finger gesture moves the cursor freely — lifts and re-grips are free, no pointer event commits the anchor. The user commits the anchor by tapping the "Set anchor" action (`Icons.adjust`) in the copy-mode bar row; `onAnchorDown()` fires then, stamps the anchor at the current cell, and the bar swaps the Set-Anchor button for the Copy action. Subsequent drags extend the selection from the anchor to the new cursor position. **Don't auto-commit the anchor on the first pointer-up** — on a phone viewport the target cell is often under the user's thumb and the aim needs more than one drag, so an auto-commit reads as "I can't lift without losing my aim". Pinned by the "pointer events alone never drop the selection anchor (aim phase)" widget test in `mobile_terminal_view_test.dart`.

**Copy mode layout — reflow on keyboard, stable on copy-mode toggle.** Two events could resize the terminal widget at runtime: soft-keyboard open/close and copy-mode toggle. Each propagates into `Terminal.buffer.resize`, which has visible side effects — `buffer.resize` on a column change runs a full reflow, and even rows-only shrink can lose trailing empty lines. The balance this layout strikes:

1. **Keyboard reflow is allowed — but debounced.** `MobileShell` sets `resizeToAvoidBottomInset: false` on the terminal page so this widget owns the keyboard layout. The SSH bar's `bottom` offset clamps to `navBarHeight` (sits above the mobile-shell nav when no keyboard) and follows the **settled** keyboard inset once the slide animation has finished. The raw `viewInsets.bottom` ticks once per animation frame while the soft keyboard slides in or out; feeding that straight into the layout drove a `Terminal.buffer.resize` per frame, which visibly ripped the scrollback — especially when the user scrolled the terminal during the animation. `MobileTerminalView` now runs the raw value through a 200 ms debounce (`_scheduleKeyboardInsetSettle` in `didChangeDependencies`) so layout freezes at the previous stable inset until the raw value has held still; then we apply one reflow for the whole animation. xterm's rows-only resize path pops empty trailing lines when the cursor is already at bottom, otherwise decrements the cursor — earlier content moves into scrollback where the user reaches it with xterm's own scroll gesture. A prior stable-height / translate-up attempt parked the top rows under the mobile-shell AppBar off-screen with no reachable scroll (scrolling xterm moves the whole render, not the clip), which was strictly worse than a clean reflow.
2. **Copy-mode toggle is stable.** The `SshKeyboardBar` swaps its single row's *contents* between the normal-keys variant and a copy-mode variant (hint text + Set-Anchor / Copy + Cancel) inside the same `Container(height: itemHeightLg)`. No widget in the stack changes height on toggle, so `buffer.resize` never fires when the user enters or leaves copy mode — that was the scrollback-corruption path the old "banner above + toolbar below" rendering hit. The hint and the action button both flip off the overlay's `anchorSet` flag: before commit the button is `Icons.adjust` ("Set anchor"), after commit it becomes `Icons.copy`. Parent rebuilds on `onAnchorDown()` so the bar re-reads the flag on the next frame.
3. **Scrollback rip is an upstream bug.** Users see chunks of text "disappear from the middle" when scrolling back through rapidly-streaming output. Tracked as [xterm.dart issue #222](https://github.com/TerminalStudio/xterm.dart/issues/222) — `Buffer.scrollUp` / `scrollDown` in v4.0.0 rewrite the circular buffer in place, leaving detached `BufferLine` objects at intermediate slots; in release builds the asserts are off and the indices silently mis-point. Triggered by scroll-region escape sequences (vim redraw, tmux status, htop, plus whatever shell output happens to include `\e[S` / `\e[T`), not by raw output rate, which is why bumping `maxLines` does not help. Client-side mitigations (a `CellAnchor`-based eviction watchdog + `ScrollPosition.correctBy` compensation; a `ClampingScrollPhysics` fling-velocity cap) were tried and reverted — they masked a narrow slice of the symptom without fixing the underlying corruption, and xterm's own `_scrollToBottom` bypasses the shared `ScrollController` ([issue #218](https://github.com/TerminalStudio/xterm.dart/issues/218)) so any offset we set gets clobbered on the next input anyway. Waiting on upstream; when the patch ships, re-enable: (a) `scrollOnInput: false` via [PR #219](https://github.com/TerminalStudio/xterm.dart/pull/219) and (b) a `scrollPhysics:` param via [PR #220](https://github.com/TerminalStudio/xterm.dart/pull/220) so we don't need the `ScrollConfiguration` hack.

4. **Overlay is visual-only.** `TerminalCopyOverlay` renders the virtual cursor marker wrapped in `IgnorePointer` (the outer `Listener` still sees cursor-pan deltas via the ancestor hit-test path); on enter it calls `TerminalController.setSuspendPointerInput(true)`. One-finger drags route through `TerminalCopyOverlayState.onCursorPan(delta)`, which accumulates sub-cell pixel deltas against the measured cell size and advances the cursor one cell at a time. The grid is linearised as `y * viewWidth + x` so horizontal overflow rolls onto the next row — a long pasted line that soft-wraps across several buffer rows can be selected in one continuous drag without the user manually crossing the wrap. When the cursor would step past the top / bottom viewport edge, `MobileTerminalView`'s shared `ScrollController` (passed to both `TerminalView(scrollController: ...)` and `TerminalCopyOverlay`) is nudged by the overflow cells' worth of pixels instead — so a single drag can extend the selection through the entire scrollback. The overlay derives the viewport-start line from `scrollController.offset ~/ cellHeight` so selection anchors stay buffer-absolute and accurate while the buffer scrolls.
5. **Copy / Cancel.** The bar's copy-mode row exposes the Copy action (fires `onCopyPressed` → `TerminalClipboard.copy` → `SshKeyboardBarState.exitCopyMode()`) and Cancel (`Icons.close` → `exitCopyMode()` without copying). Paste stays on the normal-row keyboard bar so the user doesn't have to enter copy mode just to paste a password — the two directions are orthogonal.

**Why trackpad-style instead of drag-select.** An earlier mobile build used the Select button to toggle drag-select on the terminal itself: the finger touched the terminal, the selection tracked the finger. Problems: (a) the thumb covered the target cells, so precision required lifting to check alignment, (b) selection started on the first touch with no way to "just cancel" mid-drag, (c) the scale recognizer collision killed long-press-to-word even outside select mode. The trackpad pattern (lifted from Termux) decouples finger position from cursor position — the cursor stays where you left it, the finger drags to advance it relatively — and the explicit Copy/Cancel toolbar gives an escape hatch. Two-finger pan-scroll is deferred until xterm exposes a main-buffer scroll hook.

**Architectural difference:** Mobile is NOT a responsive version of desktop. It's a separate `features/mobile/` module with different interaction patterns (bottom nav instead of sidebar+tabs, long-press instead of right-click, swipe navigation).

**Mobile session panel interactions:**
- **Single tap** on session → connects immediately (no double-tap needed)
- **Long-press** on session → bottom sheet context menu: Terminal, Files, Edit, Duplicate, Move, Delete, **Select**
- **Long-press** on folder → bottom sheet: New Connection, New Folder, Rename, Delete, **Select**
- **Select** action in bottom sheet → enters multi-select mode with that item pre-checked. Further taps toggle items. Bulk actions (Select All, Move, Delete, Cancel) in `_SelectActionBar` (height: 36 px, matching `_PanelHeader`). No checklist icon in header — multi-select is entered exclusively through the bottom sheet.

**Nav guard:** Terminal and Files destinations are disabled (dimmed, tap blocked) when no tabs of that type exist. If the user is on Terminal/Files and the last tab closes, auto-switches to Sessions.

**Shared styling with desktop:** Mobile tab chips match desktop's rectangular tab style (top accent bar, colored icons — blue for terminal, yellow for SFTP, connection status dot). SSH↔SFTP companion buttons (`_MobileCompanionButton`) mirror desktop's `_companionButton` styling (colored background, border, icon + label). Saved-sessions, active-connections, and open-tabs counts use `StatusIndicator` icons in the global header bar (matching desktop's sidebar footer style), not duplicated in the session panel footer. Bottom nav items are plain icons without badges — the total tab count lives in the header bar. The tab chip bar and companion button share a parent `Container` with `AppTheme.bg1` background (no border), ensuring consistent background across both elements.

```dart
// main_screen.dart (part of 'main.dart')
if (isMobilePlatform) {
  return const MobileShell();    // bottom nav, one tab
}
// desktop continues with sidebar + tab bar layout
```

---

### 5.7 Recordings (`features/recordings/`)

User-facing browser + replay surface for the per-session recordings the [`SessionRecorder`](#313-session-recording-coresessionsession_recorderdart) writes. The engine lives in `core/session/session_recorder.dart` (encryption envelope, asciinema framing, rotation); the files below render the on-disk results.

| File | Class | Purpose |
|------|-------|---------|
| `recordings_browser.dart` | `RecordingsPanel`, `RecordingsBrowserDialog` | Embeddable list panel + dialog wrapper. Calls `recorder_list_recordings` (walk + stat) and `recorder_delete_recording` Rust-side; joins the resulting entries to the live session list to resolve labels and exposes per-row delete + Play action. Reachable via Tools → Recordings on desktop and the mobile Tools tile. |
| `recording_playback_dialog.dart` | `RecordingPlaybackDialog` | Embedded xterm playback with speed control (`0.5×` / `1×` / `2×` / `4×`) via the shared no-animation [`AppPopupSelect`] picker. Subscribes to `recorder_open_for_playback`; the Rust side dispatches on extension (`.cast` plaintext / `.lfsr` encrypted) so the Dart consumer hands the path in once and never branches. Truncated tails surface as a clean stop instead of a decode error. Pause / play, the speed dropdown, the scrub slider, and the position read-out share **one controls row** so the freed vertical space goes to the terminal. The recording's full `cols × rows` grid renders at its natural pixel size with **no surrounding scroll view** — `playbackFitFontSize` auto-picks the largest font (preferred = `configProvider.fontSize × 1.25`, larger than the live terminal since recordings are reviewed, not typed into) at which the whole grid fits the dialog and shrinks below it only when an oversized capture (tall htop on a short screen) or odd aspect ratio would overflow, picking the tighter of the width / height axes. xterm's auto-resize then lands exactly on the recorded dimensions, so curses recordings (htop / vim) keep their fixed header + footer rows aligned. The `SizedBox` math measures cells through `measureMonoCell` **with `MediaQuery.textScalerOf`** so the grid matches the OS-text-scaled cell xterm paints — measuring unscaled clips the bottom row when the system text scale is above 1.0. A scroll view would install a drag recogniser that beats xterm's selection pan in the gesture arena, so omitting it also makes drag-to-select match the log terminal. |
| `recording_reader.dart` | `RecordingReader` | Thin Dart wrapper over the FRB playback stream. Holds the `RecordingHeader` / `RecordingMeta` / `RecordingFrame` shapes the UI consumes; the actual decoder (per-frame AES-GCM, `.cast` line-iter, length-cap rejection) lives in `lfs_core::recorder::reader`. |
| `recordings_logic.dart` | Listing + lifecycle helpers | Pure session-id → display-label fallback shared by panel / dialog. Disk walk + delete moved Rust-side; this file only carries `BuildContext`-free label resolution. |

Recordings storage path, per-event GCM frame layout, the `.cast` / `.lfsr` decoder iterators, and the disk walk + delete are owned by [§3.13](#313-session-recording-coresessionsession_recorderdart) (`lfs_core::recorder::browser` for list/delete, `lfs_core::recorder::reader` for playback iteration); this section is the UI surface. Cross-link: [USER_GUIDE § Session recording + playback](USER_GUIDE.md#9-session-recording--playback) for the user-facing flow.

---

## 6. Widgets — Public API Reference

### Widget catalogue at a glance

The full set of files lives under `lib/widgets/` (alphabetical). The detailed entries below describe widgets with non-obvious contracts; the rest of the inventory:

| File | Role |
|------|------|
| `app_button.dart` | `AppButton` + named ctors (`.cancel` / `.primary` / `.secondary` / `.destructive`) — compact dialog/footer button. Re-exported from `app_dialog.dart` so dialog callsites only need one import. |
| `app_collection_toolbar.dart` | `AppCollectionToolbar` — shared "search + add + secondary action" header used by every list-style manager (SSH keys, snippets, tags, known hosts) so they line up visually. |
| `app_collection_panel.dart` | `CollectionManagerPanel<T>` — generic "load a list → search → act on rows" manager shell. Owns the load/loading/filter state and the `AppCollectionToolbar` + separated-list scaffold; callers pass `load` / `filter` / `countLabel` / messages / toolbar actions / `itemBuilder`. Backs the Keys, Tags + Snippets managers. Imperative load-then-`reload` model only — reactive collections (known hosts) watch their stream directly. |
| `app_empty_state.dart` | `AppEmptyState` — centered icon + heading + secondary line + optional action. Replaces ad-hoc `Column` empty placeholders. |
| `app_picker_chip.dart` | `AppPickerChip` — shared pill-shaped selector used by ProxyJump kind picker, port-forward kind picker, snippet token chips. |
| `app_selection_area.dart` | `AppSelectionArea` — local-scope text-selection wrapper used inside dialogs / threat lists / help prose. The desktop shell never wraps the workspace in `SelectionArea` (gesture-arena race with `ThresholdDraggable`). See [Selection scoping](#selection-scoping). |
| `dropdown_select_button.dart` | `DropdownSelectButton<T>` — the canonical shared dropdown trigger (replaces inline `PopupMenuButton` copies in session edit forms and similar). |
| `tag_color.dart` | Colour-palette + `TagColor` helpers used by `TagManagerDialog` / `SessionTagDots` / `FolderTagDots`. |
| `update_progress_indicator.dart` | Determinate + indeterminate progress UI shared by the in-app updater dialogs. |
| `import_preview_dialog.dart` | Shared typedefs (`ImportPreviewCounts`, `ImportPreviewSelection`) consumed by [LfsImportPreviewDialog](#lfsimportpreviewdialog) + [LinkImportPreviewDialog](#linkimportpreviewdialog). |
| `shortcut_registry.dart` | `AppShortcut` enum + `AppShortcutRegistry`. Documented in detail under [§3.11 Keyboard Shortcuts](#311-keyboard-shortcuts-widgetscoreshortcut_registrydart) — file lives under `widgets/` because shortcuts cross UI / non-UI concerns and the registry has no Flutter-free callers. |

Widgets split across `part of` siblings (one entry, multiple files):

- `expandable_tier_card.dart` + `expandable_tier_card_header.dart` / `_inputs.dart` / `_logic.dart` / `_threats.dart`.
- `security_setup_dialog.dart` + `security_setup_dialog_logic.dart` / `_widgets.dart`.

Detailed entries follow.

### AppShell

```dart
AppShell({
  required Widget toolbar,        // content inside the decorated toolbar container
  double toolbarHeight = 34,      // toolbar container height
  Widget? sidebar,                // left panel content (null → no sidebar)
  double initialSidebarWidth = 220,
  double minSidebarWidth = 140,
  double maxSidebarWidth = 400,
  bool sidebarOpen = true,        // inline visibility toggle
  bool useDrawer = false,         // true → sidebar becomes a Drawer (narrow viewports)
  double drawerWidth = 280,
  required Widget body,           // main content between toolbar and status bar
  Widget? statusBar,              // optional bottom bar
})
```
Desktop layout shell shared by the main screen and settings. Provides the consistent visual frame: toolbar (surfaceContainerLow, no border), main body area, and optional status bar. Sidebar resize uses a `Stack` overlay — panels sit flush, a 6 px invisible hit zone with a 1 px `dividerColor` line overlays the boundary. On narrow viewports, set `useDrawer: true` to render the sidebar as a pull-out `Drawer` instead of an inline panel.

**Toolbar layout:** `[sidebar toggle | AppTabBar (embedded) | copy right / copy down | settings]`. Tabs are embedded directly in the toolbar row via `AppTabBar(embedded: true)` to save vertical space. When no tabs are open or in settings mode, the tab area is replaced by a `Spacer`.

State class `AppShellState` exposes `sidebarWidth` getter. Sidebar width is managed internally and persists as long as the widget stays mounted.

### ClippedRow

Drop-in `Row` replacement that clips overflowing children **and** suppresses Flutter's debug overflow indicator (yellow-and-black stripes). Extends `Flex` and uses a custom `RenderFlex` subclass (`_ClippedRenderFlex`) that overrides `paint()` to always clip via `pushClipRect` and skip `paintOverflowIndicator` entirely. The built-in `Flex.clipBehavior: Clip.hardEdge` only clips children painting — the debug indicator is still painted unconditionally by `RenderFlex`. Use in any row whose parent can be resized (sidebar, split panes, column headers, status bars).

### AppIconButton

```dart
AppIconButton({
  required IconData icon,
  VoidCallback? onTap,         // null → disabled (30% opacity)
  String? tooltip,
  double? size,                // null → AppTheme.iconBtnIcon / iconBtnIconDense
  double? boxSize,             // null → AppTheme.iconBtnBox / iconBtnBoxDense
  bool dense = false,          // true → pick the tighter AppTheme defaults
  Color? color,
  Color? hoverColor,
  Color? backgroundColor,      // permanent bg (e.g. mobile buttons)
  bool active = false,         // active state highlight
  BorderRadius? borderRadius,
})
```
Rectangular hover, no splash/ripple. **Replaces Material `IconButton` everywhere.**
When `size`/`boxSize` are left unset the widget resolves them from responsive getters on `AppTheme`: `iconBtnBox`/`iconBtnIcon` return **40/20 on mobile, 26/14 on desktop**, and the dense pair (`iconBtnBoxDense`/`iconBtnIconDense`) drops to **36/18 on mobile, 22/14 on desktop** — use `dense: true` in tight toolbars (dialog header close, toast close, file-browser breadcrumbs, transfer panel).
When `tooltip` is set, `Tooltip` provides semantics. When absent, `Semantics(button: true)` is added for screen readers.

### HoverRegion

```dart
HoverRegion({
  required Widget Function(bool hovered) builder,
  VoidCallback? onTap,
  VoidCallback? onDoubleTap,
  void Function(TapUpDetails)? onSecondaryTapUp,
  void Function(LongPressStartDetails)? onLongPressStart,
  MouseCursor cursor = SystemMouseCursors.basic,
})
```
**Replaces `MouseRegion` + `GestureDetector` + `setState(_hovered)`.** Skips `MouseRegion` on mobile platforms (Android/iOS) — no pointer, saves an unnecessary widget. Exception: `context_menu.dart` (keyboard nav state).

**Selection auto-opt-out.** When any gesture callback is bound (`onTap`, `onCtrlTap`, `onDoubleTap`, `onSecondaryTapUp`, `onLongPressStart`), `HoverRegion` wraps its child in `SelectionContainer.disabled` before installing the `GestureDetector`. That excludes the child's Text from whatever ambient `SelectionArea` is in scope — keeps the I-beam cursor off buttons, stops `Ctrl+C` from hijacking the focused row, and removes the gesture-arena race between `SelectionArea`'s `TapAndDragGestureRecognizer` and the callback's `TapGestureRecognizer` that otherwise surfaces as "drag-select works every other time" on neighbouring Text. Interactive widgets that should not be selectable go inside a `HoverRegion`; informational Text stays outside. Desktop has no global `SelectionArea` (see [Selection scoping](#selection-scoping)), so the wrap is mostly a no-op at the shell level and matters inside dialog / threat-list / help-prose scopes.

Important: the wrap sits *around* the `GestureDetector`'s child, not around the `Listener` / `ThresholdDraggable` subtree that descendants may install. Drag gestures inside a `HoverRegion` still arbitrate in their own arena — `SelectionContainer.disabled` touches the Selectable registry, not pointer routing.

### Selection scoping

Text selection is opt-in on desktop. The shell does not wrap the workspace in a `SelectionArea` — an earlier attempt at "selection everywhere, opted out on buttons" collapsed the moment a `ThresholdDraggable` landed inside a `HoverRegion`, because `SelectionArea`'s `TapAndDragGestureRecognizer` claims pan ahead of `MultiDragGestureRecognizer` in the gesture arena and the opt-out wrap sits above the drag subtree instead of protecting it.

Apply `AppSelectionArea` only to surfaces carrying prose the user may want to copy:

- [`AppDialog`](#appdialog) wraps its body automatically — every dialog's copy (update notes, threat-row captions, help text, release notes) stays selectable.
- [`SecurityThreatList`](#securitythreatlist) wraps its column so individual threat rows can be compared across tier cards.
- Add new local wraps when you introduce a read-only prose surface (e.g. a future help dialog). **Do not** wrap any container that also hosts a `ThresholdDraggable`, an `AppButton`, or an interactive row — the gesture arena race will break drag or make click-throughs feel sluggish.

Mobile keeps a single `AppSelectionArea(child: MobileShell())` because the touch-drag recognisers arbitrate differently and mobile lacks the hover-I-beam path.

Inside a scoped `AppSelectionArea`, a parent may still need to block selection on a specific subtree that is not a `HoverRegion` (e.g. a dialog's sidebar nav list). Wrap that subtree in `SelectionContainer.disabled` explicitly — [`SidebarNavDialog`](#sidebarnavdialog) does this around the nav rail it renders for the Tools + Settings dialogs, so the sidebar labels stop showing the I-beam without yanking selection off the dialog body.

#### Role matrix — when a row is clickable vs prose

| Role | Examples | Cursor | Selection |
|---|---|---|---|
| **Action** | `AppButton`, `AppIconButton`, `_Toggle` knob, `_SegmentControl`, `PopupMenuButton` chip | pointer | **disabled** |
| **Tile** (row dispatches on tap) | `ExpandableTierCard` header, `_ActionTile` (Data section), `AppDataRow` clickable row | pointer | **disabled** — wrap the InkWell's child in `SelectionContainer.disabled` |
| **Form row** (label + interactive control) | `_SettingsRow` used by `_IntTile`, `_Toggle`, `_ThemeTile`, `_LanguageTile` | default | **disabled** — the label + subtitle block is a field name, not content to copy; the row's control handles its own cursor |
| **Prose** (no gesture, user may want to copy) | `SecurityThreatList` rows, dialog bodies, release notes, help text | I-beam | **enabled** |

The rule exists because a clickable ancestor's `MouseRegion(cursor: click)` wins over the Selectable text's inner `MouseRegion(cursor: text)` — leaving text selectable on a clickable tile produces "selectable but cursor still a pointer", which users read as broken. The consistent answer is to disable selection on every clickable subtree, not to try to prefer the inner cursor. `HoverRegion` already handles this for its own callers; controls built on a bare `GestureDetector`, `InkWell`, or `PopupMenuButton` do not, so each wraps its child in `SelectionContainer.disabled` manually — `expandable_tier_card.dart`, `app_data_row.dart`, `tier_threat_block.dart`, the `_SegmentControl` theme picker, the shared `AppPopupSelect` trigger (covers every settings dropdown), and `_AutoLockTile`'s disabled-state trigger.

### ModeButton

```dart
ModeButton({
  required String label,
  required IconData icon,
  required bool selected,
  required VoidCallback onTap,
})
```
Pill-shaped toggle button for import mode selection (merge/replace). Accent-colored when selected, neutral when not. Used in `settings_dialogs.dart` and `lfs_import_dialog.dart`.

### AppDialog

```dart
AppDialog({
  required String title,
  double maxWidth = 460,
  required Widget content,
  List<Widget> actions = const [],
  EdgeInsets contentPadding = const EdgeInsets.all(16),
  bool scrollable = true,
  bool dismissible = true,
})
```
Unified dialog shell matching the app's dark visual language. Background `AppTheme.bg1`, 24 px inset padding, constrained width, header bar with title + close button, optional footer with action buttons. **Replaces Material `AlertDialog` everywhere.** Exception: mobile keyboard buttons (`ssh_keyboard_bar.dart`, `mobile_file_browser.dart`) keep `Material` + `InkWell` for touch ripple feedback.

For complex dialogs (e.g. with tabs between header and content), compose from the building blocks directly:
- `AppDialogHeader({title, onClose})` — header bar
- `AppDialogFooter({actions})` — footer bar (uses `Wrap` layout — actions flow to the next line on narrow mobile screens)
- `AppButton` — compact button (`.cancel()`, `.primary()`, `.secondary()`, `.destructive()`); lives in `lib/widgets/core/app_button.dart` and is re-exported from `app_dialog.dart` so dialog callsites don't need a second import. Used outside dialogs too (settings rows, toasts, wizard steps).
- `AppProgressBarDialog.show(context, reporter)` — non-dismissible labelled progress bar (see [§7 ProgressReporter](#progressreporter)). Replaced the old `AppProgressDialog` spinner — every long operation must report phase/step so users see what is happening and how far it has progressed.

Static helper: `AppDialog.show<T>(context, builder:)` wraps `showDialog` with `AnimationStyle.noAnimation` and consistent barrier settings.

### SidebarNavDialog

```dart
SidebarNavDialog({
  required String title,
  required List<SidebarNavEntry> entries,   // {icon, title, builder}
  Widget? sidebarFooter,                     // pinned below the rail
  Widget Function(Widget panel)? panelBuilder, // wraps each built panel
})
```

Full-screen desktop modal with a fixed 200 px navigation rail on the left and a content pane on the right (VS Code style). Single definition of the chrome shared by the Tools and Settings dialogs: inset (`AppTheme.desktopModalInsetPadding`), the dialog's own `AppSelectionArea`, the `dismissDialog` shortcut, `AppDialogHeader`, and the rail styling. Each dialog supplies only its title + entries; Settings additionally passes a Reset-button `sidebarFooter` and a `panelBuilder` that scrolls each section in a `ListView` under the dense `ListTileTheme`.

The content pane is a **lazy `IndexedStack`**: each entry's panel builds on first selection and then stays mounted, so re-selecting a panel is a cheap index flip rather than a teardown + re-run of its `initState` load (key fetch, filesystem scan, stream subscribe). Without keep-alive the selected-row highlight repaints in the same frame as that rebuild, so rapid nav clicks feel dropped until the load finishes. The rail itself is wrapped in `SelectionContainer.disabled` — see [Selection scoping](#selection-scoping). Tradeoff: a revisited panel keeps its already-loaded state instead of reloading; provider-backed panels still refresh via `ref.watch`, and in-panel mutations update their own state.

### FormSubmitChain

```dart
FormSubmitChain({required int length, required VoidCallback onSubmit});
FocusNode nodeAt(int index);
TextInputAction actionAt(int index);      // .next for non-last, .done for last
ValueChanged<String> handlerAt(int index); // advances focus / submits on last
void dispose();
```

Shared Enter-key wiring for any multi-field input dialog. Owns a fixed-length list of `FocusNode`s and returns the per-field `textInputAction` + `onSubmitted` callback that implement "Enter advances to the next field; Enter on the last field submits". Flutter `TextField`s intercept Enter before parent `CallbackShortcuts` can, so a dialog-level shortcut cannot implement dialog-wide Enter-submit; each field must wire `onSubmitted` individually. Centralising the wiring here keeps dialogs short and prevents per-dialog regressions (e.g. a field that silently fails to submit).

Every password dialog in `features/settings/settings_dialogs.dart` uses it: `_EnableBiometricDialog`, `_ExportPasswordDialog`, `_ImportPasswordDialog`. Any new input dialog must use this helper instead of re-rolling `FocusNode`s and `TextInputAction` defaults by hand. The pre-tier master-password dialogs that also lived in this file were deleted when the tier wizard became the single entry point for every security change (see §3.6).

### AppBorderedBox

```dart
AppBorderedBox({
  required Widget child,
  Color? borderColor,           // default: AppTheme.borderLight
  Color? color,                 // background color
  BorderRadius? borderRadius,   // default: AppTheme.radiusSm
  double borderWidth = 1,
  EdgeInsetsGeometry? padding,
  double? height,
  double? width,
  BoxConstraints? constraints,
  AlignmentGeometry? alignment,
})
```
**Replaces manual `BoxDecoration(border: Border.all(...))` patterns.** Guarantees `borderRadius` is always applied — prevents sharp-corner containers. Use this instead of hand-coded `Container` + `BoxDecoration` with `Border.all`.

### AppDivider

```dart
AppDivider({
  double indent = 0,
  double endIndent = 0,
  Color? color,                  // default: AppTheme.border
})
AppDivider.indented({Color? color})  // indent = 8, endIndent = 8
```
**Replaces bare `Divider(height: 1)` everywhere.** Standardises height (1 px), thickness (1 px), and color. Use `.indented()` for folder separators in menus.

### ColumnResizeHandle

```dart
ColumnResizeHandle({required void Function(double dx) onDrag})
```
Draggable column-resize handle for table headers. Place between a flexible column and a fixed-width column. The `onDrag` callback receives the raw horizontal delta (positive = right). Callers negate the delta when the fixed column is to the right of the handle. Used in `FilePane` and `TransferPanel` column headers.

### AppPopupSelect

```dart
class AppPopupSelectOption<T> {
  const AppPopupSelectOption({
    required this.value,
    required this.label,
    this.secondary,  // dim right-aligned tail (e.g. "Russian" next to "Русский")
  });
}

class AppPopupSelect<T> extends StatelessWidget {
  const AppPopupSelect({
    required this.value,
    required this.options,
    required this.onChanged,
    this.leadingIcon,
    this.menuMinWidth = 200,
  });
}
```

Shared dropdown picker matching the project's canonical dropdown
look: compact `bg3` trigger + down-arrow opening a `bg2`,
`radiusMd`, no-animation `PopupMenuButton` with themed items.
Replaces ad-hoc `DropdownButton` / one-off `PopupMenuButton` copies.
Current callers: `_LanguageTile`, `_LogLevelSelector`. New level /
enum / locale-style pickers should go through this widget rather
than re-rolling a `DropdownButton` — the `PopupMenuButton` owned
animation controller ignores the project-wide animations-off
`MediaQuery`, and the one widget opts out of it once.

**Trigger label flex** — `Flexible` + `TextOverflow.ellipsis`
prevents fractional-pixel overflow on tight settings columns (the
RenderFlex "overflowed by 5.2 px" shape a raw `DropdownButton`
renders on narrow layouts).

### StyledFormField / FieldLabel / StyledInput

```dart
StyledFormField({
  required String label,               // uppercase label above the input
  required TextEditingController controller,
  String? hint,
  bool obscure = false,
  Widget? suffixIcon,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
  bool fixedHeight = false,            // wrap in SizedBox(controlHeightMd)
  bool autofocus = false,
  ValueChanged<String>? onSubmitted,
})
```
Reusable styled form field combining `FieldLabel` + `StyledInput`. Eliminates duplication across `SessionEditDialog`, `QuickConnectDialog`, and `LfsImportDialog`. Uses `AppFonts.mono()` for input text, `AppTheme.bg3` fill, `AppTheme.radiusSm` borders. Set `fixedHeight: true` for compact bottom-sheet layouts (wraps input in `SizedBox(height: controlHeightMd)` with zero vertical padding).

`FieldLabel(text)` — standalone uppercase label widget. `StyledInput(controller, ...)` — standalone text input with full decoration, accepts `labelText` and `contentPadding` overrides for non-standard layouts (e.g. `.lfs` import dialog).

### SplitView

```dart
SplitView({
  required Widget left,
  required Widget right,
  double initialLeftWidth = 220,
  double minLeftWidth = 150,
  double maxLeftWidth = 400,
})
```
Horizontal resizable split. Draggable divider 4px.

### Toast

```dart
Toast.show(context, {
  required String message,
  ToastLevel level,      // info | success | warning | error
  Duration duration,     // default 3s
});
```
Stacked notifications, fade + slide animation, auto-dismiss.

### ContextMenu

```dart
showAppContextMenu({
  required BuildContext context,
  required Offset position,
  required List<ContextMenuItem> items,
});

ContextMenuItem({
  String? label,
  IconData? icon,
  Color? color,
  String? shortcut,
  bool divider = false,
  VoidCallback? onTap,
});
ContextMenuItem.divider()
```
Keyboard nav (arrows, enter, esc), hover highlighting, repositioning.
Re-entrant: right-clicking a new location auto-dismisses the previous menu and opens a new one.
Styled with `AppTheme` colors directly (no Material surface tint).
Each item is wrapped in `Semantics(button: true, label: item.label)` for accessibility.

#### StandardMenuAction — shared action catalogue

```dart
enum StandardMenuAction {
  copy, paste, delete, rename, duplicate, refresh, open, transfer,
  snippets, terminal, files, editConnection, newConnection, newFolder,
  renameFolder, editTags, deleteFolder, close, closeOthers,
  closeTabsToTheLeft, closeTabsToTheRight, closeAll, maximize, restore,
  ;

  ContextMenuItem item(
    BuildContext context, {
    required VoidCallback onTap,
    AppShortcut? shortcut,
    String? labelOverride,
  });
}
```

Every action that appears in more than one right-click menu lives here
as a single enum value, along with its translated label (via `S.of`),
Material icon, and optional accent colour (e.g. `delete` and `closeAll`
carry `AppTheme.red`). Each call site only supplies the side-effect
(`onTap`) and, when applicable, an `AppShortcut` — the shortcut hint is
formatted from the **live** [`AppShortcutRegistry`](#311-keyboard-shortcuts-widgetscoreshortcut_registrydart)
binding (see `formatShortcut` below), never hardcoded.

Why enum, not ad-hoc strings per site: menus had drifted — for example
the terminal right-click advertised a stale `Ctrl+V` next to `Paste`
while the real binding was `Ctrl+Shift+V`. Threading the shortcut
through `AppShortcutRegistry.shortcutLabel(AppShortcut)` makes the hint
always reflect the real bind, and adding a new action is now one enum
value instead of a hand-copied `label` / `icon` / `color` triple in
every caller.

Callers still use `showAppContextMenu` with a `List<ContextMenuItem>` —
the enum just builds items. Site-unique actions (e.g. `closeTabsToTheLeft`
appears only in the workspace tab-strip) also live in the enum because
reuse is likely and the catalogue is cheap; truly one-off actions can
still be constructed as a hand-rolled `ContextMenuItem` without going
through the enum.

Cross-link: shortcut labels are produced by
[`formatShortcut` in §3.11](#311-keyboard-shortcuts-widgetscoreshortcut_registrydart)
— the same helper `AppShortcutRegistry.shortcutLabel` uses.

### HostKeyDialog

```dart
HostKeyDialog.showNewHost(context, {host, port, keyType, fingerprint})    → Future<bool>
HostKeyDialog.showKeyChanged(context, {host, port, keyType, fingerprint}) → Future<bool>
```
TOFU dialogs: new host / key changed.

### ConfirmDialog

```dart
ConfirmDialog.show(context, {
  required String title,
  required Widget content,
  String? confirmLabel,  // null → S.of(context).delete
  bool destructive = true,
}) → Future<bool>
```

### FileConflictDialog

```dart
FileConflictDialog.show(context, {
  required String targetPath,
  required bool isRemoteTarget,
  bool showApplyToAll = true,
}) → Future<ConflictDecision>
```

Prompts the user when a transfer's destination already exists. Actions: `skip`, `keepBoth`, `replace`, `cancel`. When `showApplyToAll` is true, an "apply to all remaining" checkbox lets the resolver cache the decision for the rest of a batch — see `BatchConflictResolver` in `core/transfer/conflict_resolver.dart`. Dismissing via the scrim returns a `cancel` decision. Directory transfers bypass this dialog (silent merge-overwrite).

### ErrorState

```dart
ErrorState({
  required String message,
  VoidCallback? onRetry,
  String retryLabel = 'Retry',
  IconData retryIcon = Icons.refresh,
  VoidCallback? onSecondary,
  String? secondaryLabel,
  IconData? secondaryIcon,
})
```

### ConnectionProgress

```dart
ConnectionProgress({
  required Connection connection,
  String? channelLabel,   // e.g. "Opening SFTP channel"
})
```
Terminal-styled progress display for non-terminal tabs (SFTP file browser). Dark background (`AppTheme.bg2`), monospace font, text markers `[*]`/`[✓]`/`[✗]` — visually identical to the terminal progress output. Subscribes to `connection.progressStream` with history replay. Exposes `ConnectionProgressState.addStep()` for channel-specific steps (e.g. SFTP channel open) not covered by the SSH connection progress.

### LfsImportDialog

```dart
LfsImportDialog.show(context, {required String filePath})
  → Future<({String password, ImportMode mode})?>
```

### PasteImportLinkDialog

```dart
PasteImportLinkDialog.show(context) → Future<QrDecodedSource?>
```

Camera-less QR-import flow: accepts either a full `letsflutssh://import?d=…` deep link or the raw base64url payload, decodes Rust-side via `qrImportOpen` (which transparently strips the `letsflutssh://import?d=` wrapper), and pops the staged `QrDecodedSource.rust` on success — payload bytes never cross the FRB boundary outwards. Paste-from-clipboard button reads `Clipboard.getData('text/plain')`; on mobile an additional "Scan QR code" button launches the native scanner via [`scanQrCode()`](#qr-scanner-coreqr). Rejects invalid input with an inline error instead of closing.

### LocalDirectoryPicker

```dart
LocalDirectoryPicker.show(
  context, {
  required String initialPath,
  required String title,
}) → Future<String?>
```

In-app directory browser that walks the filesystem via `dart:io` (no SAF, no `file_picker`). Used on Android when the app holds `MANAGE_EXTERNAL_STORAGE` — replaces SAF's `ACTION_OPEN_DOCUMENT_TREE`, which would otherwise prompt for per-folder consent on every export. Returns the selected directory's absolute path; callers append the filename.

### MarqueeMixin

```dart
mixin MarqueeMixin<T extends StatefulWidget> on State<T> {
  // Abstract methods (implement in host):
  double get marqueeRowHeight;
  int get marqueeItemCount;
  bool isMarqueeItemSelected(int index);
  void applyMarqueeSelection(int firstIndex, int lastIndex, {required bool ctrlHeld});

  // Ready-made handlers:
  void handleMarqueePointerDown(PointerDownEvent e);
  void handleMarqueePointerMove(PointerMoveEvent e);
  void handleMarqueePointerUp(PointerUpEvent e);
  Widget buildMarqueeOverlay(Color color);
}
```

### StatusIndicator

```dart
StatusIndicator({
  required IconData icon,     // Icon to display
  required int count,         // Numeric count next to the icon
  required String tooltip,    // Tooltip text on hover
  Color? iconColor,           // Override icon color (default: dim)
})
```

Compact icon + number indicator with tooltip. Used in sidebar footer to display session/connection/tab counts. Connection indicator counts both `connecting` and `connected` states; icon is green when any connection is established, yellow when all are still connecting. Reusable for any status bar needing icon + count pairs.

**File:** `lib/widgets/core/status_indicator.dart`

### ReadOnlyTerminalView

```dart
ReadOnlyTerminalView({
  required Terminal terminal,
  double fontSize = 14.0,
})
```
Read-only xterm `TerminalView` wrapper — no keyboard input, cursor hidden. Used by `ConnectionProgress` for SFTP tab progress/error display. Wraps in a `Focus` for the terminal-copy keyboard shortcut and a `Listener` whose `onPointerDown` shows a one-item Copy context menu on right-click. The selection text is captured synchronously in the listener (before xterm's gesture arena resolves) so the menu's Copy action operates on a stable snapshot — competing recognisers that wipe `controller.selection` between right-click and the menu tap can no longer turn a Copy into a no-op.

### ThresholdDraggable

```dart
ThresholdDraggable<T extends Object>({
  // All standard Draggable params +
  double moveThreshold = 8.0,   // min pixels before drag begins
})
```
`Draggable` variant that requires `moveThreshold` pixels of pointer movement before initiating a drag. Prevents accidental drags when clicking close buttons or double-clicking items. Uses a custom `MultiDragGestureRecognizer`.

### MobileSelectionBar

```dart
MobileSelectionBar({
  required int selectedCount,
  required int totalCount,
  required VoidCallback onCancel,
  required VoidCallback onSelectAll,
  required VoidCallback onDeselectAll,
  required VoidCallback? onDelete,
  List<Widget> actions = const [],
})
```
Shared selection-mode action bar for mobile screens. Used by both the file browser and session panel. Shows: close button, count, select/deselect all toggle, custom action buttons, and delete.

### SortableHeaderCell

```dart
SortableHeaderCell({
  required String label,
  required bool isActive,
  required bool sortAscending,
  required VoidCallback onTap,
  required TextStyle style,
  double? width,
  TextAlign? textAlign,
})
```
Reusable sortable column-header cell for table views. Shows a label with optional sort-direction arrow (↑/↓). Highlights on hover and when active. Used in `FilePane` and `TransferPanel`.

Also provides `columnDivider()` — thin vertical divider between table columns (for data rows, not headers).

### AppDataRow

```dart
AppDataRow({
  required Widget icon,           // leading icon or avatar
  required String title,
  String? secondary,              // dim line under title
  String? tertiary,               // dim line under secondary
  List<Widget> trailing = const [],
  VoidCallback? onTap,
  VoidCallback? onSecondaryTap,
  bool selected = false,
  EdgeInsets? padding,
})
```
Shared row primitive for list / table dialogs (known hosts, snippets, tags, SSH keys). Min-height-padded so rows align across dialogs. Uses `AppTheme.itemHeightMd` and `AppFonts` for the typography ladder. Pair with [AppDataSearchBar](#appdatasearchbar) for the matching search input.

### AppDataSearchBar

```dart
AppDataSearchBar({
  required TextEditingController controller,
  required ValueChanged<String> onChanged,
  String? hint,
  bool autofocus = false,
})
```
Shared search input for list / table dialogs. Visually paired with [AppDataRow](#appdatarow); both surface the same dark-language conventions so dialogs stay consistent.

### TagDots — SessionTagDots & FolderTagDots

```dart
SessionTagDots({required String sessionId, double diameter = 8})
FolderTagDots({required String folderPath, double diameter = 8})
```
Coloured dot row showing the tags assigned to a session (or aggregated across a folder subtree). `Consumer*` widgets — both watch `tagProvider` so dots stay in sync with tag CRUD without manual rebuilds. See [§3 Tags](#3-core-modules) for the underlying `TagsNotifier`.

### DataCheckboxes — CollapsibleCheckboxesSection & DataCheckboxRow

```dart
CollapsibleCheckboxesSection({
  required String title,
  required bool expanded,
  required ValueChanged<bool> onExpandedChanged,
  required List<Widget> children,
  Widget? trailing,
})

DataCheckboxRow({
  required bool? value,           // null = indeterminate (mixed selection)
  required String label,
  String? secondary,
  required ValueChanged<bool?> onChanged,
  bool dim = false,
})
```
Shared collapsible checkbox grid + tri-state row used by the unified export dialog and the import-preview dialogs. Tri-state semantics: `null` renders the indeterminate marker so a parent group can show "some children selected".

### LfsImportPreviewDialog

```dart
typedef LfsImportPreviewResult = ({ImportMode mode, ImportPreviewSelection selection});

LfsImportPreviewDialog.show(context, {
  required ImportPreviewCounts counts,
  required ImportMode initialMode,
}) → Future<LfsImportPreviewResult?>
```
Pre-import preview of a `.lfs` archive — shows per-type counts ([§3.9 Import](#39-import-coreimport)) and lets the user trim the import + pick merge/replace before commit. The shared `ImportPreviewCounts` / `ImportPreviewSelection` typedefs in `widgets/import_export/import_preview_dialog.dart` are reused by [LinkImportPreviewDialog](#linkimportpreviewdialog) so both sources speak the same shape.

### LinkImportPreviewDialog

```dart
typedef LinkImportPreviewResult = ({ImportMode mode, ExportOptions options});

LinkImportPreviewDialog.show(context, {
  required QrDecodedSource source,
}) → Future<LinkImportPreviewResult?>
```
Same preview surface as [LfsImportPreviewDialog](#lfsimportpreviewdialog) but for `letsflutssh://` deep-link / QR payloads. Reads counts off the unified `LfsPreview` shape projected from the Rust-staged handle, so both sources render identically.

### UnifiedExportController

```dart
class UnifiedExportController extends ChangeNotifier {
  ExportPreset preset;            // fullBackup | sessions | custom
  ImportPreviewSelection selection;
  ExportOptions options;          // include credentials? compress? …
  // Pure presentation logic — no Riverpod, no persistence.
}
```
Headless controller for the unified QR + `.lfs` export dialog. Holds selection + options, exposes derived counts for the size indicator. Lives in `widgets/` because export is widget-local state (not app-wide) — see [§4.3 Widget-local controllers](#43-widget-local-controllers-changenotifier).

### UnifiedExportDialog

```dart
UnifiedExportDialog.show(context, {
  required UnifiedExportDialogData data,
}) → Future<UnifiedExportResult?>
```
Single dialog covering both QR and `.lfs` export. Top of the dialog flips between QR (small payloads) and archive (everything else) modes; the controller above owns the selection state. Tree rendering is split into `unified_export_dialog_tree.dart` (a `part of` file) to keep the state class small — presentation only.

---

## 6.1 Security & Tier Wizard Widgets

Cluster of widgets that implement the first-launch security wizard, the Settings → Security ladder, the lock screen, and the reset prompts for mismatched on-disk state. They consume / mutate state owned by `core/security/` ([§3.6](#36-security--encryption-coresecurity)) and the security providers ([§4.2 Provider Catalog](#42-provider-catalog) — `securityProvider`, `lockStateProvider`, `autoLockMinutesProvider`, `firstLaunchBannerProvider`, `masterPasswordProvider`).

### AppInfoButton

```dart
AppInfoButton({
  required String dialogTitle,
  required Widget dialogContent,
  double size = 14,
})
```
Inline `(i)` icon that opens [AppInfoDialog](#appinfodialog) with caller-supplied threat-model copy. Sits next to any tier row or setting where the user might want to know what they're turning on before they tap it.

### AppInfoDialog

```dart
AppInfoDialog({required String title, required Widget content})
AppInfoDialog.show(context, {required String title, required Widget content}) → Future<void>
```
Reusable threat-model explainer. Two columns of "protects against" / "does not protect against". Shown from [AppInfoButton](#appinfobutton) next to security-tier rows in the first-launch wizard and Settings → Security.

### AutoLockDetector

```dart
AutoLockDetector({required Widget child})
```
Wraps the app body and locks the app after `autoLockMinutesProvider` minutes of user inactivity when the active security tier is `masterPassword`. "Lock" means: clear in-memory keys, push [LockScreen](#lockscreen) on top of the navigator. No-op for tiers below masterPassword (keychain / no-secret) — those have nothing to lock.

### LockScreen

```dart
LockScreen({Key? key})
```
Full-screen lock overlay shown while `lockStateProvider` is true. Tries biometric unlock first (if the user enabled it) and falls back to a master-password form. On success it re-derives the DB key, pushes it back into [`KeyHolder`](#36-security--encryption-coresecurity) and flips `lockStateProvider` off. Cross-links: [§3.6 Security](#36-security--encryption-coresecurity) for the key derivation path.

### SecurePasswordField

```dart
SecurePasswordField({
  required TextEditingController controller,
  String? label,
  String? hint,
  bool autofocus = false,
  ValueChanged<String>? onSubmitted,
  FocusNode? focusNode,
})
```
A `TextField` pre-configured for secret entry — master password, SSH key passphrase, API token. Drops every IME convenience that would otherwise leak the typed secret into a system service: `autocorrect: false`, `enableSuggestions: false`, `enableInteractiveSelection: false`, `obscureText: true`, no spell-check, no autofill. Single Dart implementation across all five platforms — Flutter's engine bridges `obscureText` + `keyboardType: visiblePassword` to the native secure-input field (`TYPE_TEXT_VARIATION_PASSWORD` / `UITextField.isSecureTextEntry`), which covers IME-learning suppression on every platform and screen-recording blackout on iOS. macOS is a known gap (`NSTextView`, not `NSSecureTextField`, so `EnableSecureEventInput` does not fire); see [§3.6 Security](#36-security--encryption-coresecurity).

### SecureScreenScope

```dart
SecureScreenScope({required Widget child, bool enabled = true})
```
Scope opting its subtree into OS-level screen-capture protection for as long as it is mounted. On Android sets `WindowManager.LayoutParams.FLAG_SECURE` via the embedding `Activity`; no-op on platforms without an equivalent (iOS / desktop). Wrap any subtree that may render secrets (lock screen, master-password unlock, key import dialogs).

### PasswordStrengthMeter

```dart
PasswordStrengthMeter({
  required TextEditingController controller,
  EdgeInsetsGeometry? padding,
})
```
Live coloured strength bar + label under a password input. Subscribes to `controller.text` so it rebuilds on every keystroke. Informational only — never blocks Save. Strength estimate is computed in pure Dart (no zxcvbn) so it can run without network or a native plugin.

### SecurityComparisonTable

```dart
SecurityComparisonTable({Key? key})
```
Full threat × tier-config matrix. Threats as rows, tier columns along the top. Horizontally scrollable on narrow desktop; rendered in transposed "one section per tier" shape on mobile so each tier fits in viewport width. Pulls labels from `core/security/threat_vocabulary.dart` so the table never drifts from the canonical threat list.

### SecurityThreatList

```dart
SecurityThreatList({
  required SecurityTier tier,
  required SecurityModifiers modifiers,
})
```
Single-tier threat-status list used by the per-tier info popup. Renders the full `SecurityThreat` vocabulary — every threat row visible inline with a ✓ / ✗ / — / ! glyph derived from the tier + modifiers it was constructed with.

### ExpandableTierCard

```dart
typedef TierSelectCallback =
    Future<void> Function({
      required SecurityTier tier,
      required SecurityTierModifiers modifiers,
      String? shortPassword,
      String? pin,
      String? masterPassword,
    });

ExpandableTierCard({
  required SecurityTier tier,
  required SecurityTier currentTier,
  required SecurityTierModifiers currentModifiers,
  required bool tierAvailable,
  required TierSelectCallback onSelect,
  String? unavailableReason,
  bool initiallyExpanded = false,
  Widget? activeTierExtras,
})
```
Settings → Security ladder unit. Collapsed state shows the tier header (badge + title + subtitle + a trailing "Current" pill on the active row). Expanded state surfaces:

1. A fixed-order threat list — the same 8 rows in the same sequence on every tier card, each with a ✓/✗ icon computed by `evaluate()` in `threat_vocabulary.dart`. Rows that would flip to ✓ if the password modifier were enabled carry an "(only with password)" hint in muted italics so the user can tell at a glance which threats the toggle unlocks. Earlier iterations split the list into "protects" / "doesn't protect" halves; dropped because cross-tier comparison requires positional alignment that halves-split destroyed.
2. Password and biometric modifier toggles where applicable — T1 and T2 both carry the password toggle; the underlying auth value (long password vs PIN) is semantically different but rendered as the same `SecurePasswordField + confirm` pair under a unified "password" label. The brute-force-resistance distinction (length on T1, hardware lockout on T2) lives in the threat-row copy, not in a second field name.
3. Secret input fields — shown only when the corresponding modifier is on (password+confirm for T1/T2, master password+confirm for Paranoid).
4. An Apply / "✓ Current" button — Apply routes through `onSelect` into the same atomic always-rekey pipeline the old wizard invoked.
5. `activeTierExtras` — an optional widget slot rendered under the Apply button with a divider separating it. Used by the Settings section to inline the biometric-unlock toggle and the auto-lock tile into the current tier's expandable, because both are orthogonal "settings of the currently applied tier" rather than pending changes queued for Apply. Non-current cards pass null; the slot stays hidden there.

Unavailable tiers (T2 without TPM, T1 with gdbus probe reporting no secret-service) keep the card expandable so the user can still read the threat split. The Select button is disabled and the `unavailableReason` line renders under the threat list as a yellow pill.

### SecuritySetupDialog

```dart
class SecuritySetupResult { … }

SecuritySetupDialog({Key? key})
SecuritySetupDialog.show(context) → Future<SecuritySetupResult?>
```
Reduced-wizard fallback: shown on first launch **only when both T1 (keychain) and T2 (hardware) are unavailable** — a rare environment where the user genuinely has to pick between T0 (plaintext) and Paranoid (master password) because no OS-backed secret store is reachable. On the common path (keychain reachable) `_firstLaunchSetup` auto-selects T1 silently and surfaces a `FirstLaunchSecurityToast` instead of this modal — the toast is non-blocking because the auto-setup already made a safe choice for the user. `SecuritySetupResult` carries both the plain `(tier + typed-secret-field)` shape and the bank-style `(tier + modifiers)` shape so downstream call sites can consume either form.

### FirstLaunchSecurityToast

```dart
FirstLaunchSecurityToast.show(context, {
  required FirstLaunchBannerData data,
  required VoidCallback onOpenSettings,
  required VoidCallback onDismiss,
}) → void
```
Top-right `Overlay`-based toast shown once after the first-launch auto-setup lands on a tier. Replaces the earlier blocking `FirstLaunchSecurityDialog` — the auto-selected T1 is a safe default the app already landed on, so a dismiss-to-continue modal is out of scale for what the user has to do (nothing). Carries the same copy (what we picked + whether a hardware upgrade is within reach), offers the Settings action when `data.hardwareUpgradeAvailable`, and auto-dismisses after 8 seconds. Drives `firstLaunchBannerProvider` the same way the dialog did — `onDismiss` clears the provider so the toast never re-opens. The reduced-wizard path (both keychain + hardware unreachable) still shows `SecuritySetupDialog` as a blocking modal because that branch is a real decision the user has to make.

### TierSecretUnlockDialog

```dart
TierSecretUnlockDialog.show(context, {
  required TierSecretUnlockLabels labels,
  required Future<TierUnlockAttempt> Function(String secret) verify,
  VoidCallback? onReset,
  PasswordRateLimiter? rateLimiter,
  BiometricSpec? biometric,
}) → Future<TierUnlockAttempt>
```
Shared T1+pw (short password) / T2 (PIN) unlock shell. Owns the retry loop: the host supplies a `verify` callback that returns a typed `TierUnlockAttempt` outcome — `staged` (the unlock orchestrator put the resolved key in SecretStore), `wrongSecret` (kept open + decrements the limiter), `error` (closes with failure for plaintext / corruption fallback), or `cancelled` (inner sub-prompt dismissed, dialog stays open). The dialog never sees raw key bytes; Rust's `run_post_unlock_cascade` opens the rusqlite handle, persists the tier, publishes the store-changed events, and finally emits `BusEvent::UnlockCascadeReady { tier_wire, has_key }`. The [`TierUnlockedListener`](../lib/app/tier_unlocked_listener.dart) reads `has_key` off that payload and runs the Riverpod half (`securityStateProvider.setActive`, resolve the pending `awaitNextUnlock`). [`LockStateNotifier`](../lib/core/security/lock_state.dart) subscribes to the same event and drops the lock overlay on its own — no Dart-side rendezvous between the listener and the lock screen. Cooldown back-off is wired through the `rateLimiter` parameter.

### TierResetDialog

```dart
enum TierResetChoice { resetAndContinue, exit }

TierResetDialog.show(context) → Future<TierResetChoice>
```
Non-dismissible prompt shown when the resolved security tier no longer matches the on-disk artefact shape. Outcomes: wipe every security file + DB and run the setup wizard, or exit.

### DbCorruptDialog

```dart
enum DbCorruptChoice { reset, tryOtherTier, exit }

DbCorruptDialog.show(context) → Future<DbCorruptChoice>
```
Outcome dialog for DB-corruption / wrong-key startup. Three choices: reset the DB and run setup again, retry with a different security tier (config.security gets re-prompted), or exit.

### FatalErrorApp

```dart
class FatalErrorApp extends StatefulWidget {
  final String summary;
  final String detail;
  ...
}
```
Bare `MaterialApp` shown when the bootstrap chain stops before the regular dialog stack can run — the Rust `config_store` actor reports a parse failure for `config.json` (surfaced by `bootstrapRustConfigStore` as `AppConfigParseException`, rethrown out of `_initRustCoreOrFatal` so the caller can route to the corrupt-config screen rather than the native-blob screen), or `_initRustCoreOrFatal` fails to load the bundled native blob itself. Carries two recovery affordances:

* **Quit** (`OutlinedButton`) — exits without touching anything on disk.
* **Wipe all data** (`FilledButton`, red) — last-resort self-recovery for a corrupt-on-disk artefact the user wants to drop. The handler tries the canonical path first: lazily loads `RustLib.init()` + `appInit()` and routes through `WipeAllService.wipeAll()` (files + keychain + hardware vault + crash-safety marker). Only when `RustLib.init` itself fails — the native blob is the broken artefact — does the handler fall through to [`earlyWipeAppSupportFiles`](../lib/app/early_wipe.dart), which enumerates the immediate children of `<app_support>` and deletes each. The sweep is by enumeration, not against a hardcoded catalogue, so new artefacts the Rust side later writes are covered without a Dart-side edit. Keychain / hardware-vault orphans left by the Dart-only fallback resurface on the next launch and route through `_handleLegacyStateIfPresent` → `TierResetDialog` for the proper Rust-backed cleanup.

Rust core init runs on click, not on dialog open: a broken FRB load must not block the recovery dialog from rendering.

### SshDirImportDialog

```dart
class SshDirImportSource { … }
class PickedConfigResult { … }
typedef PickConfigCallback = Future<PickedConfigResult?> Function();
typedef PickKeysCallback = Future<List<ScannedKey>?> Function();

SshDirImportDialog.show(context, {
  required SshDirImportSource source,
  required PickConfigCallback pickConfig,
  required PickKeysCallback pickKeys,
}) → Future<ImportResult?>
```
Unified `~/.ssh` picker. Renders hosts (parsed from `~/.ssh/config` via [`parseOpenSshConfig()`](#31-ssh-coressh)) and keys (filesystem scan) in a single pick-list, returns one merged `ImportResult`.

### UnlockDialog

```dart
UnlockDialog({Key? key})
UnlockDialog.show(context) → Future<bool>
```
Master-password unlock dialog used at startup before any DB read. Returns true on success (key derived and pushed to [`KeyHolder`](#36-security--encryption-coresecurity)), false on cancel. Distinct from [LockScreen](#lockscreen) — this one runs once at app launch, the lock screen runs after auto-lock fires.

---

## 7. Utilities — Public API Reference

### AppLogger

```dart
enum LogLevel { info, warn, error }

class AppLogger {
  static AppLogger get instance;

  static const maxLogSizeBytes = 5 * 1024 * 1024;  // 5 MB
  static const _maxRotatedFiles = 3;

  String? get logPath;
  bool get enabled;        // threshold != null
  LogLevel? get threshold;

  Future<void> setThreshold(LogLevel? value);  // null = off
  Future<void> init();
  void log(
    String message, {
    String? name,
    Object? error,
    StackTrace? stackTrace,
    LogLevel? level,  // defaults to info; auto-promotes to error when `error` non-null
  });
  Future<void> logCritical(String message, {String? name, Object? error, StackTrace? stackTrace});  // always error level, bypasses threshold
  Future<String> readLog();
  Future<void> dispose();   // sets threshold=null, closes sink
  Future<void> clearLogs(); // deletes all log files, reopens if threshold non-null
}
```
File: `<appSupportDir>/logs/letsflutssh.log`. Rotation: 5 MB, 3 files.
`dispose()` sets `_threshold = null` so no writes occur after disposal.

Line format: `HH:MM:SS X [Tag] message` where X is `I` / `W` / `E`. Continuation lines for error / stack traces are indented two spaces so the viewer can fold them under the parent row without reparsing the tag. Header lines (`--- Log started <ISO> ---`, `Platform: ...`, `Dart: ...`) are written verbatim on sink open and render as a dim divider in the viewer.

**File ownership lives Rust-side.** Every `dart:io File` / `Directory` operation against the log path — create, append, rotate, read, clear, chmod — lives in `lfs_core::logger::file_sink`. The module owns a process-wide `Mutex<FileSinkState>` holding the resolved log path + an `Option<BufWriter<File>>` for the routine-write sink. `lfs_frb::api::logger` exposes eight entry points (`logger_open_sink`, `logger_append_line`, `logger_append_critical`, `logger_flush`, `logger_read_all`, `logger_rotate_if_needed`, `logger_clear_all`, `logger_close_sink`) — sync for the hot path, async + `spawn_blocking` for directory creates / multi-file deletes. Dart's `AppLogger` formats + sanitises lines, broadcasts entries on `liveEntries`, holds an in-memory ring buffer for pre-FRB `logCritical` writes, and routes every file op through the FRB seam. The split keeps the chmod / recursive-mkdir / rename grammar in one language and stops the cold-start path from owning a `dart:io` file handle the FRB-loaded code cannot inspect.

**Routine logs are opt-in — off by default.** `init()` resolves the log path string from `path_provider` without touching the filesystem; the Rust-side `logger_open_sink` creates `<app_support>/logs/` and opens the file in append mode the first time `setThreshold(...)` is called with a non-null `LogLevel`, wired up via `ConfigProvider.load` reading `config.behavior.logLevel`. Entries already on disk stay until the user hits "Clear" in the Settings → Logging section. All writes pass through [sanitize](#sanitize) before crossing the FRB boundary, and the file is chmod-0600 on POSIX via `lfs_core::path::harden_file_perms` (called inside `logger_open_sink` so the tighten is atomic with the create).

**No OS-logging mirror.** Routine `log()` calls do NOT forward to `dart:developer` — Android Logcat, macOS Console.app and desktop stderr never receive our lines. This is a deliberate privacy decision: a user with `adb logcat` access (or anyone reading the device's system logs) should not be able to read our log stream just because the user opened the app. The only surface our logs can be read from is the opt-in file under app-support. `logCritical` is the only exception — it mirrors to stderr on desktop, scoped to crash entries, because the file sink can fail (disk full, perm error, missing path) and the whole point of the critical path is forensic visibility on a crashing app.

**Critical paths bypass the threshold.** [`AppLogger.logCritical`](../lib/utils/logger.dart) routes through `logger_append_critical` which opens a fresh `OpenOptions::append` handle Rust-side rather than going through the held routine sink, so the write lands even when the user has logging off. The three global crash boundaries in `main.dart` (`FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded` handler), the `MigrationRunner` fatal path (uncaught throws + `report.hasFailures`) and the post-init `verifyDatabaseReadable` failure all leave a forensic breadcrumb without waiting for the user to pick a level. Rationale: the window where a crash trace matters most is exactly the first-launch window, before any user has opened Settings at all.

**Pre-FRB critical buffer.** The zone error handler can fire during the few-ms `RustLib.init()` window inside `_mainBody`. Calling FRB before init completes would throw `StateError("flutter_rust_bridge has not been initialized")` and swallow the original error — the exact failure mode the [cold-start ordering](#cold-start-ordering--pre-init--post-init-invariant) invariant exists to prevent. So `AppLogger.logCritical` checks `_frbReady` and, when false, pushes the rendered entry into an in-memory `_preFrbCriticalBuffer` (cap 64, FIFO eviction) and mirrors to stderr on desktop. `_mainBody` flips the gate via `AppLogger.onFrbReady()` immediately after `_initRustCoreOrFatal` returns — the method registers the log path Rust-side and replays every buffered entry through `logger_append_critical` so the breadcrumb still lands on disk after boot. Subsequent crashes route straight to Rust without buffering.

**Rule:** `AppLogger.instance.log(message, name: 'Tag')` for routine events; `AppLogger.instance.logCritical(...)` only for crash / fatal / integrity-probe-failure paths. Never `print()` / `debugPrint()` / `dart:developer.log()`. Never log sensitive data. Use `stackTrace` parameter for full stack traces.

**Severity levels + threshold.** The `level` parameter drives the Settings → Logging viewer's per-row tint + filter chips, and also gates whether the line lands on disk at all — a `log(..., level: LogLevel.warn)` call writes only when the user picked `Warn` (or `Info`) as their threshold, an `error` line writes at any non-null threshold, and so on. Auto-promote: `log(..., error: e)` without an explicit `level:` becomes `LogLevel.error`. `logCritical` is always `E` and bypasses the threshold.

### Sanitize

```dart
String sanitizeErrorMessage(String message);
// Redacts: IPv6 → <ip>, IPv4 → <ip>, user@host → <user>@host,
// `as <user>` / `user=<user>` / `login=<user>` shapes, host:port → :<port>,
// `C:\Users\<user>\…` → `<path>\…`, `/home/<user>/…` / `/Users/<user>/…` → `/<user>/…`

String redactSecrets(String input);
// Strips PEM private-key blocks and ≥ 200-char base64 runs
// (catches the common rusqlite / sqlite leak where a failed INSERT
// dumps its bound parameters into the exception message).

bool looksSensitive(String text);
// Heuristic: PEM marker + "PRIVATE KEY", or a ≥ 200-char base64 run.
// Used by terminal_clipboard auto-wipe to decide whether a copy
// should route through SecureClipboard + arm the 30-s wipe timer.
```

Pure Dart — no FRB. The pipeline used to route through
`lfs_core::log_sanitize`, but the cold-start error handlers fire
before `RustLib.init` completes (any throw between
`runZonedGuarded`-wrap and `_initRustCoreOrFatal` lands in the
zone handler), and a FRB-bound sanitiser would crash-loop the
handler in that window. The Dart regex pipeline is byte-for-byte
the same as the Rust port — the 10k-input fuzz suites
(`test/fuzz/sanitize_fuzz_test.dart`) cover idempotence,
stability, and per-shape redaction invariants. See [Cold-start
ordering](#cold-start-ordering--pre-init--post-init-invariant)
for the broader pre-init / post-init invariant this is part of.

Use `sanitizeErrorMessage()` before logging any error message that may contain connection details, usernames, IPs, or file paths. The global error handler in `main.dart` applies this automatically.

**Rule:** Always sanitize error messages that may contain user data, server addresses, or file paths.

### FileUtils

```dart
Future<void> writeFileAtomic(String path, String content);
Future<void> writeBytesAtomic(String path, List<int> bytes);
Future<void> restrictFilePermissions(String path);  // async chmod 600
```

### Platform

```dart
String get homeDirectory;
  // Desktop: HOME or USERPROFILE
  // Android: EXTERNAL_STORAGE or /storage/emulated/0

bool get isMobilePlatform;     // Android || iOS
bool get isDesktopPlatform;    // Linux || macOS || Windows
bool get isMacosPlatform;      // macOS only — gates self-sign UI

// Testing:
@visibleForTesting bool? debugMobilePlatformOverride;
@visibleForTesting bool? debugDesktopPlatformOverride;
@visibleForTesting bool? debugIsMacosOverride;
@visibleForTesting void debugResetPlatformCache();
```

**Routing.** All four queries delegate to
`lfs_core::host_info::*` over a sync FRB hop. `home_directory`
performs the env-var lookup Rust-side
(`EXTERNAL_STORAGE` on Android; `HOME` then `USERPROFILE`
elsewhere). `is_mobile` / `is_desktop` / `is_macos` resolve
to `cfg!(target_os = ...)` constants. Each result is cached
on the Dart side after the first read — env vars don't move
during a process lifetime, and the cfg booleans are
compile-time constants.

**Test-context fallback.** The three boolean predicates fall
back to `dart:io` `Platform.isXyz` when FRB is not
bootstrapped, so widget tests that don't call `RustLib.init`
still resolve. The fallback can never disagree with the Rust
answer (both forms are compile-time constants tied to the
same binary target). `homeDirectory` has no such fallback —
the env-var resolution is the part that earns its keep
through Rust, so tests that exercise tilde expansion bootstrap
FRB. The `debugResetPlatformCache()` seam exists so tests
that toggle FRB load state mid-suite can drop the cached
results.

### TerminalClipboard

```dart
static void copy(Terminal terminal, TerminalController controller);
static void copyText(String text);
static Future<void> paste(Terminal terminal);
```

`copy()` reads the controller's current selection, runs the
sensitive-content heuristic on the resulting text, writes it through
either `SecureClipboard` (PEM private key / ≥ 200-char base64 run) or
`Clipboard.setData`, then clears the selection as a side-effect.
`copyText()` is the same routing without the controller dependency —
used by [ReadOnlyTerminalView](#readonlyterminalview)'s right-click
menu, which captures the selected text snapshot synchronously at
`onPointerDown` so the menu's Copy action stays correct even if a
competing gesture recogniser clears `controller.selection` between
the right-click and the user's choice.

### Format

```dart
String formatSize(int bytes);         // "1.5 MB"
String formatTimestamp(DateTime dt);   // "2024-01-15 14:30"
String formatDuration(Duration d);    // "2m 15s"
String sanitizeError(Object error);   // strips OS-locale text, handles SSHError chain, 43 errno codes (POSIX + Winsock) — for logging only
String localizeError(S l10n, Object error); // maps errno/SSHError to localized strings via S — for UI display
```

<a id="progressreporter"></a>
### ProgressReporter (`core/progress/`)

```dart
final reporter = ProgressReporter(l10n.progressReadingArchive);
AppProgressBarDialog.show(context, reporter);
try {
  reporter.phase(l10n.progressDecrypting);      // indeterminate phase
  reporter.step(l10n.progressImportingSessions, 3, 12);  // 3 of 12, 25 %
} finally {
  if (context.mounted) Navigator.of(context).pop();
  reporter.dispose();
}
```

Long-running operations own a `ProgressReporter` and push updates as they work; `AppProgressBarDialog` subscribes via `ValueListenableBuilder` and rebuilds only the progress panel. Two update shapes:

- `phase(label)` — **indeterminate** bar with a caption. Use when the current step is an atomic call (PBKDF2 inside an isolate, ZIP decode) where no percent is observable.
- `step(label, current, total)` — **determinate** bar with `N / M` counter and percent. Use for per-row loops (importing sessions, tags, snippets).

All long operations surface progress through this type — `ExportImport.export/import_` takes optional `ProgressReporter? progress, S? l10n` parameters; the apply path (`applyResultViaRust`) reports through the FRB stream from the Rust apply driver. **Never** put a bare `CircularProgressIndicator` inside a modal dialog for long work; use `AppProgressBarDialog` so the user always sees a labelled phase and a percentage when it is available. Small in-list spinners (≤ 100 ms loads) are fine.

`LfsDecryptionFailedException` (from `ExportImport`) wraps GCM auth-tag failures and ZIP decoder failures so the UI can render a single localized "wrong master password or corrupted archive" message without leaking `InvalidCipherTextException` stack traces.

`LfsArchiveTooLargeException` is raised *before* any decryption when the encrypted file on disk exceeds 50 MiB (`lfs_core::archive::probe::MAX_ARCHIVE_BYTES`). Real archives are single-digit-MB; the cap catches zip-bomb-scale files before Argon2id + AES-GCM are forced to hold the full plaintext in memory. Per-entry declared-uncompressed size is also capped at 200 MiB (`MAX_DECOMPRESSED_BYTES`) to refuse a zip-bomb that claims petabytes of inflation before any decompression runs. Both checks live in [`lfs_core::archive::probe`](../rust/crates/lfs_core/src/archive/probe.rs) — the Dart caller (`ExportImport.probeArchive`) is a thin async wrapper. Legitimate UI paths surface both exceptions through `localizeError`.

`UnsupportedLfsVersionException` fires when an archive is not at the current `SchemaVersions.archive`: missing `manifest.json`, malformed `schema_version`, a `schema_version` that does not match `ExportImport.currentSchemaVersion`, missing `LFSE` magic, or a header version byte other than the current Argon2id one. v1 is the permanent floor — users re-export from the current app version to recover.

`.lfs` writes use a tmp-then-rename pattern (`<path>.tmp` → `<path>`) so an I/O failure mid-export can't leave a partially-written file that would fail decryption on next import.

`OpenSshConfigImporter.isSuspiciousPath` rejects `IdentityFile` entries that contain `..` segments before the path is dereferenced — a maliciously crafted `~/.ssh/config` cannot coerce the importer into reading files outside the user's intended key directory.

### QR Scanner (`core/qr/`)

```dart
const qrScannerChannel = MethodChannel('com.letsflutssh/qrscanner');

Future<String?> scanQrCode();
```

Dart-side entry point for the native QR scanner used by the import flow. Backed by a single `MethodChannel`:

- **Android** — `QrScannerActivity` launches CameraX + ZXing-core; decoded payloads return via `Activity.onActivityResult`.
- **iOS** — `QrScannerController` presents a modal AVFoundation scanner.
- **Desktop** — no native implementation; the channel call resolves to `MissingPluginException` and `scanQrCode()` returns `null`. Callers must treat null as "no scanner" and fall back to [PasteImportLinkDialog](#pasteimportlinkdialog).

Returns the decoded QR text, or `null` on user-cancel, permission-denied, or unsupported platform. Errors are logged through `AppLogger` (channel name `QrScanner`) — never thrown to the caller, so callers always see the same nullable contract.

The scanner is exposed as a top-level function (not a class) because there is no per-instance state: every call opens a fresh native scanner, returns one payload, tears down. The constant `qrScannerChannel` is exported so unit tests can install a mock handler without the production code branching on `Platform.isAndroid` / `Platform.isIOS`.

---

## 8. Theme System

### AppTheme

Dark theme: **OneDark Pro** (binaryify/OneDark-Pro) exact hex values.
Light theme: **Atom One Light** (official) exact hex values.

Brightness-aware: all getters return the appropriate color based on current `_brightness`.
Every color in the UI MUST come from this class — no hardcoded hex or `Colors.*` outside `app_theme.dart`.

```dart
abstract final class AppTheme {
  static void setBrightness(Brightness brightness);
  static bool get isDark;

  // Backgrounds (dark / light)
  static Color get bg0;     // deepest surface           (#1B1D23 / #DBDBDC)
  static Color get bg1;     // sidebar, status bar       (#21252B / #EAEBEB)
  static Color get bg2;     // main content              (#282C34 / #FAFAFA)
  static Color get bg3;     // inputs, selection         (#2C313A / #E5E5E6)
  static Color get bg4;     // hover, inactive selection (#323842 / #DBDBDC)

  // Foreground
  static Color get fg;       // main text                (#ABB2BF / #383A42)
  static Color get fgDim;    // secondary text           (#7F848E / #696C77)
  static Color get fgFaint;  // disabled text            (#5C6370 / #A0A1A7)
  static Color get fgBright; // emphasized text          (#D7DAE0 / #232424)

  // Accent & syntax hues
  static Color get accent, blue, green, red, yellow, orange, cyan, purple;
  static Color get border;      // hard dividers         (#181A1F / #DBDBDC)
  static Color get borderLight; // panel borders         (#3E4452 / #DBDBDC)
  static Color get selection, hover, active;
  static Color get onAccent;    // text on accent bg     (#F8FAFD / #FFFFFF)

  // Terminal ANSI colors (OneDark Pro terminal palette / One Light syntax)
  static Color get termBlack, termRed, termGreen, termYellow;
  static Color get termBlue, termMagenta, termCyan, termWhite;
  static Color get termBrightBlack, termBrightRed, termBrightGreen, termBrightYellow;
  static Color get termBrightBlue, termBrightMagenta, termBrightCyan, termBrightWhite;
  static Color get termCursor;     // block cursor color (#528BFF / #526FFF)
  static Color get termSelection;  // mouse selection    (#677696 @ 38% / #4078F2 @ 38%)

  // Semantic colors (brightness-aware getters)
  static Color get connected;      // green  (#98C379 / #50A14F)
  static Color get connecting;     // yellow (#E5C07B / #C18401)
  static Color get disconnected;   // red    (#E06C75 / #E45649)
  static Color get info;           // cyan   (#56B6C2 / #0184BC)
  static Color get folderIcon;     // yellow (#E5C07B / #C18401)
  static Color get searchHighlight;// terminal search bg (#FFFF2B / #FFD700)
  static Color get searchHitFg;    // search hit text

  // Section border helpers (brightness-aware)
  static BorderSide get borderSide;  // BorderSide(color: border)
  static Border get borderTop;       // Border(top: borderSide)
  static Border get borderBottom;    // Border(bottom: borderSide)

  // Bar height scale
  static const double barHeightSm;  // 34 px — toolbars, headers, footers, status bars
  static const double barHeightMd;  // 40 px — dialog title bars, mobile breadcrumbs
  static const double barHeightLg;  // 44 px — mobile app bars, selection toolbars

  // Control height scale
  static const double controlHeightXs; // 26 px — compact buttons, file rows, settings items
  static const double controlHeightSm; // 28 px — context menu items, search inputs
  static const double controlHeightMd; // 30 px — input fields, auth-type selectors
  static const double controlHeightLg; // 32 px — tab selectors, mode selectors
  static const double controlHeightXl; // 38 px — dialog action buttons

  // Item height scale
  static const double itemHeightXs;  // 22 px — compact rows (path editors, transfer details)
  static const double itemHeightSm;  // 24 px — small items (resize handles, transfer entries)
  static const double itemHeightLg;  // 48 px — icon containers, mobile list items, drag targets
  static const double itemHeightXl;  // 56 px — mobile bottom navigation bar

  // Border radius scale
  static const radiusSm;  // 4 px — inputs, buttons, small elements
  static const radiusMd;  // 6 px — cards, containers, default rounding
  static const radiusLg;  // 8 px — toasts, mobile elements, larger containers

  // Shared builders — eliminate duplication across dialogs and terminal views
  static InputDecoration inputDecoration({
    String? labelText, String? hintText, TextStyle? hintStyle,
    EdgeInsetsGeometry contentPadding,
  });
  static TerminalTheme get terminalTheme; // xterm color theme from current brightness

  // Theme factory — both delegate to shared _buildTheme()
  static ThemeData dark();
  static ThemeData light();
}
```

### AppFonts

```dart
abstract final class AppFonts {
  // Platform-aware size scale (desktop / mobile)
  static double get tiny;  // 10 / 10 — transfer errors, smallest fine print
  static double get xxs;   // 11 / 11 — keyboard shortcuts, status badges
  static double get xs;    // 12 / 13 — captions, subtitles, metadata
  static double get sm;    // 13 / 14 — body text, inputs, default UI text
  static double get md;    // 14 / 14 — section headers, form labels
  static double get lg;    // 16 / 15 — dialog titles, sub-headings, toasts
  static double get xl;    // 19 / 18 — page headings

  static TextStyle inter({fontSize, fontWeight, color, height});  // UI text
  static TextStyle mono({fontSize, fontWeight, color});            // Code/data
}
```

Fonts: **Inter** (UI), **JetBrains Mono** (terminal, data). Assets: `assets/fonts/`.

**Monospace fallback chain** (`AppFonts.monoFallback`). JetBrains Mono's cmap covers Latin, extended-Latin, and box-drawing, but *not* emoji, CJK, or most symbol blocks. `TerminalStyle` on every terminal surface (desktop `TerminalPane`, mobile `MobileTerminalView`, and the custom `CursorTextOverlay` painter) is instantiated with `fontFamily: AppFonts.monoFamily` **plus** `fontFamilyFallback: AppFonts.monoFallback` — `Noto Color Emoji` / `Apple Color Emoji` / `Segoe UI Emoji` / `Segoe UI Symbol` / `Noto Sans Symbols 2` / `sans-serif`. Every target OS ships one of those under the exact name in its system font registry, so Flutter/Skia resolves the missing glyph chain without us bundling a ~10 MB color-emoji font. Without the fallback, the terminal rendered emoji and CJK as tofu on Android; the `CursorTextOverlay` custom painter was the worst-affected site because it built a bare `ui.TextStyle(fontFamily: ...)` with no fallback parameter at all.

**Cell metrics lockstep (`kTerminalLineHeight`).** xterm's internal `TerminalStyle` defaults `height: 1.2` and forwards the multiplier into `ui.ParagraphStyle(height: …)` when it measures cell size. Every painter we stack on top of `TerminalView` — `CursorTextOverlay` (desktop + mobile), the mobile `TerminalCopyOverlay` virtual cursor + selection anchors — has to measure cells with the same multiplier. Drop the multiplier on our side and the paragraph height collapses from `fontSize × 1.2` to `fontSize × ~1.17`; cell rows drift up ~20 % per row, so the block-cursor glyph lands above its real cell and the mobile copy-mode selection rectangle renders a couple of lines below the virtual cursor. The invariant lives as `kTerminalLineHeight` in `cursor_overlay.dart`; the mobile overlay imports the same symbol so one edit covers both surfaces.

**Row snap: no dead strip at the bottom.** xterm's `TerminalView` paints whole cells only — it rounds `constraints.maxHeight` down to `floor(h / cellHeight)` rows and leaves the subpixel remainder as a background-coloured strip, which reads as dead terminal space (user report: *"он выглядит как терминал, но туда ничего не выписывается"*). Both `TerminalPane` (desktop) and `MobileTerminalView` (mobile) wrap `TerminalView` in a `LayoutBuilder` that snaps the widget's own height to `rows * fontSize * kTerminalLineHeight + padding` via a `SizedBox`. The remainder pixels become a `ColoredBox` painted in the terminal background, so the boundary between the last row and the next widget (split divider / SSH keyboard bar / status line) reads as a clean edge instead of an unwriteable gap. The pre-layout estimate uses the shared `kTerminalLineHeight` multiplier; xterm's live measurement agrees to within a subpixel so the snap holds.

**CJK & non-Latin in language picker:** Native language names (中文, 日本語, 한국어, العربية, فارسی, हिन्दी) rely on system fonts. Each entry has an English secondary label (Chinese, Japanese, Korean, Arabic, Persian, Hindi) as fallback for systems without those fonts. No bundled CJK/Arabic/Devanagari fonts — keeps the binary small.

**Rule:** Never use hardcoded `fontSize` numeric literals — always use `AppFonts.xs`, `AppFonts.sm`, etc. The constants are platform-aware: mobile gets +2 px automatically for touch readability.

**Rule:** Never use hardcoded `BorderRadius.circular(N)` or `BorderRadius.zero` — always use `AppTheme.radiusSm`, `radiusMd`, or `radiusLg`. Exception: pill-shaped elements (e.g. toggle tracks) that need full rounding.

**Rule:** Never hardcode height numeric literals for UI elements — always use `AppTheme` height constants. Three scales are available: `barHeight{Sm,Md,Lg}` for toolbars/headers/bars, `controlHeight{Xs..Xl}` for buttons/inputs/selectors, `itemHeight{Xs..Xl}` for rows/containers/list items. Panels sit flush without borders; resizable dividers use `Stack` overlays (6 px invisible hit zone, 1 px visible line where needed).

---

## 8.1 Internationalization (i18n)

All user-facing strings are externalized via Flutter's built-in `gen_l10n` system.

### Supported languages

| Code | Language | File |
|------|----------|------|
| `en` | English (template) | `app_en.arb` |
| `ru` | Russian | `app_ru.arb` |
| `zh` | Chinese (Simplified) | `app_zh.arb` |
| `de` | German | `app_de.arb` |
| `ja` | Japanese | `app_ja.arb` |
| `pt` | Portuguese | `app_pt.arb` |
| `es` | Spanish | `app_es.arb` |
| `fr` | French | `app_fr.arb` |
| `ko` | Korean | `app_ko.arb` |
| `ar` | Arabic (العربية) | `app_ar.arb` |
| `fa` | Persian (فارسی) | `app_fa.arb` |
| `tr` | Turkish | `app_tr.arb` |
| `vi` | Vietnamese | `app_vi.arb` |
| `id` | Indonesian | `app_id.arb` |
| `hi` | Hindi (हिन्दी) | `app_hi.arb` |

### Language selection

The user selects a language in **Settings → Appearance → Language**. Options: "System Default" (auto-detect from OS) or any of the 15 supported languages. Stored as `AppConfig.locale` (`null` = system default, `'ru'` = Russian, etc.). Wired via `localeProvider` → `MaterialApp.locale`.

iOS requires `CFBundleLocalizations` in `Info.plist` listing all supported locale codes for proper OS locale detection.

### Setup

| File | Purpose |
|------|---------|
| `l10n.yaml` | Config: ARB dir, template, output class `S`, non-nullable getter |
| `lib/l10n/app_en.arb` | English strings (template) — add new keys here |
| `lib/l10n/app_XX.arb` | Translations — one file per language |
| `lib/l10n/app_localizations.dart` | Generated — `S` class with all getters |
| `lib/l10n/app_localizations_XX.dart` | Generated — per-language implementations |

### Usage

```dart
import '../l10n/app_localizations.dart';

// In any widget with BuildContext:
Text(S.of(context).settings)
Text(S.of(context).nSessions(count))  // parameterized
```

`S.of(context)` is non-nullable — no `!` needed. `MaterialApp` in `main.dart` has `locale: ref.watch(localeProvider)`, `localizationsDelegates: S.localizationsDelegates` and `supportedLocales: S.supportedLocales`.

### Adding a new language

1. Copy `lib/l10n/app_en.arb` → `lib/l10n/app_XX.arb` (e.g., `app_it.arb`)
2. Set `"@@locale": "XX"` and translate all values (keep keys and placeholders intact)
3. Do NOT copy `@key` metadata entries — only the template needs them
4. Run `flutter gen-l10n` — generates `app_localizations_xx.dart` automatically
5. Add the locale code to `AppConfig.supportedLocales` list
6. Add the locale entry to `_LanguageTile._localeLabels` in `settings_screen.dart`
7. Add the locale code to `CFBundleLocalizations` in `ios/Runner/Info.plist`

### Adding a new string

1. Add the key + value to `lib/l10n/app_en.arb` (with `@key` metadata for placeholders)
2. Add the translated key to **ALL** `app_XX.arb` files — no locale may rely on English fallback
3. Run `flutter gen-l10n`
4. Use `S.of(context).newKey` in the widget

### Rules

- **Never hardcode user-facing strings** — always use `S.of(context).xxx`
- Constructor default parameters (e.g., `confirmLabel = 'Delete'`) stay hardcoded — no `context` available
- Strings only used in logs (`AppLogger`) stay hardcoded — not user-facing
- Tests must include `localizationsDelegates: S.localizationsDelegates` and `supportedLocales: S.supportedLocales` in every `MaterialApp`
- Generated files (`app_localizations*.dart`) are committed to the repo

---

## 9. Data Flow Diagrams

### 9.1 SSH Connection Flow

```mermaid
flowchart TD
    u[User clicks session]
    u --> sc["SessionConnect.connectTerminal(session)<br/>Session → SSHConfig (credentials from CredentialStore)"]
    sc --> cm["connectionManager.connectAsync(config)<br/>Creates Connection (state: connecting)<br/>Launches async _doConnect()<br/>Returns Connection → UI"]
    cm --> tab["UI: tabProvider.addTerminalTab(connection)<br/>TerminalPane subscribes to progressStream"]
    cm --> dc["_doConnect() async:<br/>SSHConnection.connect(onProgress)<br/>emits steps: socketConnect → hostKeyVerify → authenticate"]
    dc --> r{outcome}
    r -->|success| ok["state = connected + completeReady()"]
    r -->|failure| err["connectionError, state = disconnected<br/>+ completeReady()"]
    ok --> okui["TerminalPane: clear terminal → openShell() → xterm pipe"]
    err --> errui["TerminalPane: progress log stays visible with error"]
    tab -.->|via progressStream| okui
    tab -.->|via progressStream| errui
```

**Progress pipeline:** `SSHConnection.connect()` accepts an `onProgress` callback that emits `ConnectionStep` events at each phase boundary. `ConnectionsNotifier._doConnect()` forwards these to `Connection.addProgressStep()`, which buffers them in `progressHistory` and broadcasts via `progressStream`. The UI subscribes to the stream (replaying history for late subscribers) and renders steps in real time.

**Reconnect flow:** When a terminal tab reconnects (user clicks "Reconnect" after disconnect), `TerminalTab._refreshConfig()` re-reads the `Session` from `sessionProvider` using `Connection.sessionId` and updates `Connection.sshConfig` before creating a new `SSHConnection`. This ensures reconnect picks up any session edits (e.g. added keys, changed password). Quick-connect tabs (`sessionId == null`) use the original config.

### 9.2 SFTP Init Flow

```mermaid
flowchart TD
    fb["FileBrowserTab.initState()<br/>Shows ConnectionProgress widget<br/>await connection.waitUntilReady()"]
    fb --> init["SFTPInitializer.init(connection)"]
    init -->|Android only| perm["_requestStoragePermission()<br/>Quick-check /storage/emulated/0<br/>MethodChannel → MainActivity.kt"]
    perm --> api["API 30+: MANAGE_APP_ALL_FILES_ACCESS_PERMISSION<br/>API &lt;30: READ/WRITE_EXTERNAL_STORAGE dialog"]
    init --> cli["connection.sshConnection.client.sftp() → SftpClient"]
    cli --> local["LocalFS(homeDirectory) → FilePaneController (local)"]
    cli --> remote["RemoteFS(SFTPService) → FilePaneController (remote)"]
    local --> pane["FilePane(controller) × 2"]
    remote --> pane
```

### 9.3 Session CRUD Flow

```mermaid
flowchart TD
    ui["UI → sessionsProvider.notifier.add(session)"]
    ui --> add["SessionNotifier.add(session)<br/>Calls db_sessions_upsert via FRB"]
    add --> rust["lfs_core::db::sessions::upsert<br/>WriteAheadLog row → SQLCipher commit"]
    rust --> evt["BusEvent::SessionsChanged"]
    evt --> reload["SessionNotifier reload from db_sessions_list"]
    reload --> rc["sessionTreeProvider recomputes<br/>filteredSessionsProvider recomputes<br/>UI rebuilds"]
    ui -.-> hist["SessionHistory.push(snapshot)<br/>undo support — Dart-only"]
```

### 9.4 File Transfer Flow

```mermaid
flowchart TD
    drag["User drags file between panes"]
    drag --> fa["FileActions.transfer(source, target, direction)"]
    fa --> enq["TransfersNotifier.enqueue() →<br/>lfs_frb::api::transfer::transfer_enqueue"]
    enq --> pool["lfs_core::transfer::WorkerPool<br/>tokio task per active worker"]
    pool --> exec["SftpTaskExecutor:<br/>spawn russh-sftp upload/download<br/>cooperative cancel-flag check per chunk"]
    exec --> evt["BusEvent::TransferTaskProgress<br/>(per chunk; coalesced inside actor)"]
    evt --> activedart["TransfersNotifier rebuilds ActiveEntry"]
    activedart --> ui["TransferPanel rebuilds"]
    exec --> r{outcome}
    r -->|success| done["BusEvent::TransferTaskCompleted → HistoryEntry"]
    r -->|cancelled| canc["BusEvent::TransferTaskCancelled → HistoryEntry"]
    r -->|failure| err["BusEvent::TransferTaskFailed → HistoryEntry(error)"]
    done --> ui
    canc --> ui
    err --> ui
```

---

## 10. Data Models

### Session

```dart
Session {
  id: String              // UUID v4
  label: String           // display name
  folder: String          // folder path: "Production/Web" (/ separator)
  server: ServerAddress {
    host: String
    port: int             // default 22
    user: String
  }
  auth: SessionAuth {
    authType: AuthType    // password | key | keyWithPassword (Both)
    password: String      // empty if not used
    keyPath: String       // key file path (or ~)
    keyId: String         // SSH-keys-table id (when using a saved key)
    keyData: String       // PEM text (paste)
    passphrase: String    // for the key
  }
  createdAt: DateTime
  updatedAt: DateTime
  extras: Map<String, Object?>  // Sessions.extras JSON bag
  viaSessionId: String?         // ProxyJump bastion (saved session id)
  viaOverride: ProxyJumpOverride?  // ProxyJump override (one-off)
  notes: String                 // Sessions.notes — free-form, round-tripped on every save
  sortOrder: int                // Sessions.sort_order — manual position within folder (0 = unspecified)
  lastConnectedAtMs: int?       // Sessions.last_connected_at — wall-clock ms since epoch
}
```

The plaintext credential fields (`password`, `keyData`, `passphrase`) on the in-memory model are populated only on the dialog-edit path; persistence routes through SecretRef ids (see [§3.6 SecretStore + SecretRef pattern](#secretstore--secretref-the-plaintext-discipline-rule)) so the on-disk form holds opaque ids, not plaintext.

### Connection

```dart
Connection {
  id: String              // UUID (bound to tab)
  label: String
  sshConfig: SSHConfig    // mutable — refreshed from session store on reconnect
  sessionId: String?      // links back to saved Session (null for quick-connect)
  transport: SshTransport?  // engine-agnostic transport set on successful connect (today: RustTransport)
  state: SSHConnectionState  // disconnected | connecting | connected
  connectionError: Object?
  cachedPassphrase: String?  // for the lifetime of one tab; cleared on disconnect
  transientSecretIds: Set<String>  // SecretStore ids the connect path staged; drained on terminal state
  bastion: Connection?    // pinned bastion hop for ProxyJump (lifecycle cascades)
  internal: bool          // true for manager-created bastion connections (UI hides them)
  _readyCompleter: Completer<void>  // resolves after connect attempt
}
```

`Connection` does not own a `KnownHostsNotifier` reference; the host-key verification flow runs entirely Rust-side (`lfs_core::known_hosts` + the FRB-side `BusEvent::KnownHostPromptRequest` round-trip), and the Dart `KnownHostsNotifier` is a UI-side notifier on the same backing table without any per-connection link.

### TabEntry

```dart
TabEntry {
  id: String              // UUID
  label: String
  connection: Connection
  kind: TabKind           // terminal | sftp

  copyWith({label})       // same id, updated label
  duplicate()             // new UUID, same connection/label/kind
}
```

### FileEntry

```dart
FileEntry {
  name: String
  path: String            // full POSIX path
  size: int               // bytes
  mode: int               // Unix permissions (octal)
  modTime: DateTime
  isDir: bool
  owner: String           // parsed from ls -l longname
}
```

### Transfer rows

```dart
enum TransferDirection { upload, download }

// Live task — surfaced by TransfersNotifier.activeEntries; the
// authoritative task object lives Rust-side in
// lfs_core::transfer::WorkerPool. ActiveEntry is the Dart-side
// snapshot that the bus subscription rebuilds per progress event.
class ActiveEntry {
  final String id;
  final TransferDirection direction;
  final String name;
  final String sourcePath;
  final String targetPath;
  final int    bytesTotal;     // 0 if unknown
  final int    bytesDone;
  final TransferState state;   // queued | running | cancelling
}

// Terminal-state task — populated when a task completes / fails /
// gets cancelled. Replaced the earlier TransferTask Dart class
// that mixed live + history state.
class HistoryEntry {
  final String id;
  final TransferDirection direction;
  final String name;
  final String sourcePath;
  final String targetPath;
  final int    bytesTotal;
  final int    bytesDone;
  final DateTime startedAt;
  final DateTime? endedAt;
  final TransferOutcome outcome;  // completed | cancelled | failed
  final String? errorMessage;
}
```

### AppConfig

```dart
AppConfig {
  terminal: TerminalConfig {
    fontSize: double      // 6-72, default 14.0
    theme: String         // 'dark'|'light'|'system'
    scrollback: int       // 100..200_000 (TerminalConfig.maxScrollback),
                          // default 5000. Upper cap is the OOM brake —
                          // xterm allocates per-line buffers eagerly,
                          // and an unclamped `cat /dev/urandom` would
                          // pin the renderer's heap.
  }
  ssh: SshDefaults {
    keepAliveSec: int     // default 30
    defaultPort: int      // default 22
    sshTimeoutSec: int    // default 10
  }
  ui: UiConfig {
    windowWidth: double
    windowHeight: double
    uiScale: double       // 0.5-2.0
    showFolderSizes: bool
    toastDurationMs: int  // default 4000
  }
  transferWorkers: int    // 1+, default 2
  maxHistory: int         // ≥0, default 500
  logLevel: LogLevel?     // null = off (default); info / warn / error = threshold
  checkUpdatesOnStart: bool
  skippedVersion: String?
  locale: String?           // null = OS auto-detect, or supported locale code
}
```

---

## 11. Persistence & Storage

### SQLite database — Rust-owned schema

All application data is stored in a single SQLite database, opened Rust-side via `rusqlite` + bundled SQLCipher 4.x. Schema lives in `lfs_core::db::SCHEMA_SQL`; Dart reads / writes through the FRB DAO surface in `lib/src/rust/api/db.dart`:

| Table | Purpose | Key relationships | Soft-delete |
|-------|---------|-------------------|-------------|
| `Sessions` | Saved sessions — protocol-neutral row only (id, label, folder_id, `kind`, sort_order, notes, last_connected_at, `extras` JSON bag, timestamps). Every protocol-specific column lives on its matching join table. | FK → Folders | yes |
| `SshSessionDetails` | Per-session SSH transport config + credentials (host, port, user, auth_type, password, key_path, key_data, key_id, passphrase, via_session_id, via_host, via_port, via_user). Kept off `Sessions` so non-SSH rows do not carry SSH-shaped columns. | FK → Sessions, cascade on delete; PK = `session_id`; FK → SshKeys (key_id) | yes |
| `WebDavSessionDetails` | Per-session WebDAV transport config (base URL, username, auth method, optional self-signed fingerprint) | FK → Sessions, cascade on delete; PK = `session_id` | no (1-to-1 with `Sessions` kind=webdav) |
| `Folders` | Folder tree (self-referencing `parentId`) | self-ref FK | no |
| `SshKeys` | SSH key pairs | — | yes |
| `SshKeyCertificates` | OpenSSH user certificates paired to stored keys | FK → SshKeys, cascade on delete; PK = `key_id` | no (1-to-1 with `SshKeys`) |
| `KnownHosts` | TOFU host key database | unique(host, port) | no (per-device) |
| `AppConfigs` | Single-row config JSON blob | — | no |
| `Tags` | User-defined color tags | unique(name) | yes |
| `SessionTags` | M2M: sessions ↔ tags | cascade on delete | no (M2M edge) |
| `FolderTags` | M2M: folders ↔ tags | cascade on delete | no (M2M edge) |
| `Snippets` | Reusable command snippets | — | yes |
| `SessionSnippets` | M2M: sessions ↔ snippets | cascade on delete | no (M2M edge) |
| `SftpBookmarks` | Saved remote paths per session | FK → Sessions, cascade | yes |
| `PortForwardRules` | Per-session SSH port-forward rules (local / remote / dynamic) | FK → Sessions, cascade | no |

### Files on disk

All files live in the platform's app-support directory (see **Location** below). Inside that directory:

| Path | Encryption | Format | Purpose | Created when |
|------|-----------|--------|---------|--------------|
| `letsflutssh.db` | SQLCipher 4.x — AES-256-CBC + HMAC-SHA512 (`PRAGMA key`) | SQLite | All app data — sessions, folders, SSH keys, known hosts, tags, snippets, bookmarks, app config row | First write (after security setup) |
| `letsflutssh.db-wal` / `letsflutssh.db-shm` | inherits DB encryption | SQLite WAL | SQLite write-ahead log + shared memory; auto-managed by sqlite3 | Whenever DB is open |
| `config.json` | No | JSON | App config — theme, locale, font size, scrollback, transfer workers, update prefs, `recordings_storage_cap_bytes`, `config_schema_version`. Loaded **before** the DB opens (needed for splash screen). Auto-lock timeout lives in the encrypted DB, not here | First config save |
| `credentials.kdf` | No | `'LFKD'` magic + version + KdfParams + 32-byte salt | Argon2id salt + params for master-password key derivation. Presence = master password is enabled | Master password setup |
| `credentials.verify` | No | AES-256-GCM | Encrypted known-plaintext blob — used to verify the entered master password matches | Master password setup |
| `credentials.key` | AES-256-GCM (under master-password-derived KEK) | Length-prefixed envelope | The 32-byte DB encryption key, wrapped under the master-password-derived KEK. Lets the verify path reuse the same Argon2id pass for both verify + key resolution rather than running it twice | Master password setup; rewritten on every tier switch |
| `keychain_enabled` | No | Marker file (presence) | Sentinel for the T1 keychain-backed tier — written when the T1 setup wizard finishes, removed on tier downgrade or wipe | T1 enable |
| `rate_limit_state.bin` | HMAC-SHA256-authenticated framing | `{failureCount, nextRetryAtMillis}` blob | Persisted T1+pw password-gate rate-limit counters. Survives process restart so a relaunch can't reset the cooldown | First T1+pw failure |
| `security_pass_hash.bin` | No | JSON `{salt, HMAC-SHA256(pepper, salt ‖ password)}` | T1+pw keychain-password gate hash. Pepper lives in the OS keychain under `letsflutssh_l2_pepper` (split-storage tamper surface). Verifies the short-password the keychain unlock prompt collects. Not Argon2id — gate is UX-only by design (see [§3.6 → KeychainPasswordGate](#t1pw-keychain-password-gate-keychainpasswordgate)); cryptographic key derivation lives on Paranoid only | T1+pw+password setup |
| `hardware_vault_*.bin` | Hardware-backed wrap | Per-platform envelope | Hardware-vault sealed DB-key blob (one per platform — Apple / Android / Windows / Linux + per-platform overlay variants). See [§3.6 T2 hardware vault](#t2-hardware-vault-hardwaretiervault) for the per-platform shape | T2 enable |
| `.tier-transition-pending` | No | JSON | Crash-recovery marker written before a tier-switch rekey. Absence = previous tier switch completed cleanly; presence on startup signals an interrupted switch and routes through the recovery path | Every tier switch (cleared on success) |
| `.wipe-pending` | No | Empty file | Crash-recovery marker written before a wipe sweep starts. Presence on startup re-runs the sweep idempotently | Wipe start (cleared on success) |
| `migration_history.json` | No | JSON | Legacy artefact, kept in [`MANAGED_FILES`](../rust/crates/lfs_core/src/security/wipe.rs) for cleanup on installs that still carry it. No code path writes or reads it. | Legacy installs only |
| `logs/letsflutssh.log` | No | Text | App debug log (rotates at 5 MB, keeps 3 rotated copies). Disabled by default | First log write after user enables logging |
| `logs/letsflutssh.log.1`…`.3` | No | Text | Rotated log files | After log rotation |

### Database initialization

The DB lives Rust-side under `lfs_core::db`. The Dart layer
calls `dbInit(path, key)` over FRB once on unlock; the Rust
side opens an encrypted SQLite file via `rusqlite` with
`bundled-sqlcipher-vendored-openssl` (SQLCipher 4.x +
vendored OpenSSL — AES-256-CBC + HMAC-SHA512, 256 000
PBKDF2-SHA512 iterations off the `PRAGMA key` value).
The page-cipher key the Dart caller hands in is the 32-byte
master DB key produced by Argon2id (Paranoid) / pulled out of
the OS keychain (T1) / unsealed from the hardware vault (T2).
Plaintext mode (T0) opens the same file with no `PRAGMA key`.

`bootstrap_schema()` writes every table idempotently
(`CREATE TABLE IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS`)
and stamps `PRAGMA user_version = SCHEMA_VERSION` on every open
whenever the on-disk value lags. Foreign keys are enabled via
`PRAGMA foreign_keys = ON` in the same bootstrap pass. No per-step
`ALTER` arms are registered today — every shipping install lands on
the same column shape directly from `SCHEMA_SQL`.

**POSIX permissions.** Rust pre-creates the DB file before
SQLite touches it so the very first encrypted page lands on a
0600 inode (Unix `set_permissions(0o600)` / Windows ACL via the
`windows` crate). Idempotent; a permission-system quirk that
makes the call fail logs and continues so startup is never
blocked.

**Config split.** `config.json` is loaded before the database
opens because it carries pre-unlock UI state (theme, locale,
window size) — anything that has to render before the user
types the master password. The auto-lock timeout, by contrast,
is a security control: it lives in the encrypted DB
(`app_configs.auto_lock_minutes`) so an attacker with disk
access cannot weaken it.

**Location.** `path_provider` → `getApplicationSupportDirectory()`:
- Linux: `~/.local/share/letsflutssh/`
- macOS: `~/Library/Application Support/letsflutssh/`
- Windows: `%APPDATA%\letsflutssh\`
- Android: app internal storage
- iOS: app sandbox

**Atomicity.** Handled by SQLite transactions —
`lfs_core::archive::apply_pending_import` wraps its entire body
in a `Connection::transaction()`, so a bulk import either fully
lands or leaves the DB unchanged (a mid-import exception
triggers SQLite rollback; the Dart wrapper rethrows
`LfsImportRolledBackException` so the UI shows "data restored"
in replace mode).

**Schema migrations.** `bootstrap_schema()` is currently the
v1 floor — every shipping install runs it and ends at the
same column shape. Future bumps:

1. Add the migration step inside `bootstrap_schema` before the
   `pragma_update("user_version", SCHEMA_VERSION)` line, gated
   by `read_schema_version(conn)?` (test-only helper today; if
   the production path needs to branch on it, drop the
   `#[cfg(test)]` and surface it through `Db`).
2. Bump `SCHEMA_VERSION`.
3. Add a Rust unit test that sets up a v(N-1) DB by hand,
   runs `bootstrap_schema`, asserts the new column / table /
   constraint behaviour.

**Version log.**
- **v1** — the column-and-table shape declared in `SCHEMA_SQL`
  (see the table at the top of §11). Single floor for every
  shipping install. No `ALTER` arms register in
  `bootstrap_schema` today — additive bumps (`ADD COLUMN`,
  `CREATE TABLE IF NOT EXISTS` follow-ups) land alongside their
  matching match arm + rewind+replay test when the next
  format change ships. Structural rewrites that SQLite cannot
  express additively (drop column, rename, change PK) follow the
  SQLite 12-step rebuild recipe. Reference snapshots predating v1
  live verbatim under
  [`drift_schemas/drift_schema_v1.json` … `_v4.json`](../drift_schemas/);
  they are not consumed by any runtime path and exist only as
  documentation when proving a column existed in a given
  pre-floor era for archive-import back-compat.

### Export portability per table

The `.lfs` archive + WebDAV sync ship a per-table subset. Every
table below either round-trips in full, ships an opaque secret-id
pointer in place of secret bytes, or stays per-device. The full
"what travels" table per backend lives in §3.9; the column below
is a quick reference.

| Table | Export portability | Notes |
|---|---|---|
| `folders` | Full | Path-keyed reconstruction on apply. |
| `sessions` | Full | Slim protocol-neutral row — `id`, `label`, `folder_id`, `kind`, `sort_order`, `notes`, `last_connected_at`, `extras`, timestamps. LWW on `updated_at` for sync. |
| `ssh_session_details` | Full (passwords inside GCM envelope) | SSH-specific config + credentials; LWW on `updated_at`. The composer flattens this back into the `Session` archive entry so the wire format does not leak the join split. |
| `ssh_keys` | Backend-dependent | `software` + `fido2` + `pkcs11` round-trip; `enclave` / `hello` / `tpm` / `keystore` ship as stubs. See §3.9. |
| `ssh_key_certificates` | Full | Cert blob is the public half; safe verbatim. |
| `webdav_session_details` | Opaque-pointer | Endpoint config + secret-id pointer travels; password bytes stay on the source device's `webdav_session_details.password` column (SQLCipher-encrypted at rest) and never cross the wire. |
| `s3_session_details` | Opaque-pointer | Access key id travels; secret access key bytes stay on the source device's `s3_session_details.secret_access_key` column (SQLCipher-encrypted at rest). |
| `known_hosts` | Full | Per-device TOFU; archive import unions rows. Sync explicitly does NOT replicate host trust between devices. |
| `tags` / `session_tags` / `folder_tags` | Full | M2M edges union via `INSERT OR IGNORE`. |
| `snippets` / `session_snippets` | Full | LWW on `updated_at` for sync. |
| `sftp_bookmarks` | Full | Tombstone-aware; LWW on `created_at`. |
| `port_forward_rules` | Full | No tombstone column; replace-mode clears. |
| `app_configs` | Per-device | Not exported via `.lfs` / sync (UI theme, locale, log threshold etc. stay local). |

### Soft-delete contract

The five tombstoned tables (`sessions`, `ssh_keys`, `tags`,
`snippets`, `sftp_bookmarks`) carry an `INTEGER NULL deleted_at`
column. Every DAO read filters `WHERE deleted_at IS NULL` so a
soft-deleted row is invisible to the rest of the app. The DAO
`delete*` family flips the column to the current unix-millis
instead of issuing a `DELETE FROM`; the row survives so a
sync-merge teardown (`§8b`, planned) can replay the tombstone
across devices. Physical removal goes through a single
`purge_tombstones(before_ms)` helper per DAO — reserved for the
sync-merge cleanup and the user-initiated "Reset All Data" path.
Re-`upsert` of a tombstoned row clears `deleted_at` (`ON
CONFLICT(id) DO UPDATE SET … deleted_at = NULL`), so a recreate-
with-same-id flow revives the row instead of failing on the PK.

**Why these five.** They carry user-authored configuration that
WebDAV sync (`§8b`) replicates between devices; physical deletes
in one device would otherwise re-appear on the next pull because
the peer DB still has the row. `folders` and `port_forward_rules`
are excluded today: folders cascade-clean via session FKs and
port forwards are owned 1-to-1 by their session row. `known_hosts`
stays per-device.

**`tags.name` uniqueness is partial.** A `CREATE UNIQUE INDEX
idx_tags_name_live ON tags(name) WHERE deleted_at IS NULL` keeps
the live-row constraint without reserving the name across
tombstones, so the "delete `prod`, recreate `prod`" loop works
immediately. No inline `UNIQUE(name)` column constraint on the
table itself — that would block recreating a same-named tag while
the tombstoned row sits in the purge queue.

**Performance indexes are baked into the schema.**
`bootstrap_schema` issues `CREATE INDEX IF NOT EXISTS` for every
foreign-key column queried as a "join from the child side" —
SQLite indexes the declared `PRIMARY KEY` automatically but does
NOT index FK columns by default, so without these every reverse
lookup (`SELECT … FROM sessions WHERE folder_id = ?`,
`DELETE FROM sftp_bookmarks WHERE session_id = ?`,
`tag → sessions / folders / snippets`) was a full table scan.
Current set: `idx_sessions_folder_id`, `idx_sessions_via_session_id`,
`idx_sessions_key_id`, `idx_folders_parent_id`,
`idx_port_forward_rules_session_id`,
`idx_sftp_bookmarks_session_id`,
`idx_session_tags_tag_id`, `idx_folder_tags_tag_id`,
`idx_session_snippets_snippet_id`. Composite-PK junction tables
already have the leading column covered by the PK; the trailing
column gets its own index for the reverse join.
Existing databases pick the indexes up on next open via
`IF NOT EXISTS` — no migration bump needed. Adding a new index
for an existing table is a one-line edit to the `SCHEMA_SQL`
block — `IF NOT EXISTS` makes it idempotent without a version
bump. Functional schema changes (columns, tables, constraints)
still require a version bump and a migration step per the rule
above.

**Prepared-statement cache.** Every query in `lfs_core::db::*`
goes through `conn.prepare_cached(sql)` rather than
`conn.prepare(sql)` — rusqlite memoises the compiled
`sqlite3_stmt` keyed by SQL text so the parser + planner runs
once per process per query string instead of once per call.
`Connection::prepare_cached` takes `&self` (interior mutability
via `RefCell`) so it drops in to the existing `&Connection`-shaped
DAO functions without flipping signatures. Hot paths
(`sessions::list_all`, `folders::list_all`, the per-id `get`
forms) benefit most; one-shot startup queries are unchanged.

The `bootstrap_schema` SCHEMA_VERSION + `PRAGMA user_version` machinery covers **only** intra-DB column / table changes; it does **not** cover the on-disk envelope around the DB file or any other persisted artefact (`config.json`, `credentials.kdf`, `.lfs` archives). Those go through the typed [Migration framework](#migration-framework) (`lfs_core::migration`), which runs on startup before `SecurityInitController.bootstrap` for filesystem artefacts and at import time for `.lfs` archives. The two are intentionally separate: `lfs_core::db::bootstrap_schema` owns the schema inside the DB, the migration framework owns the file-format envelope around it. `letsflutssh.db` itself is **not** registered with the framework — the framework only walks artefacts whose version is queryable without invoking a platform OS-API, and the DB cipher key arrives via the unlocked tier far later in startup. A schema mismatch instead surfaces as a SQLCipher decrypt failure on `ensureRustDbOpen` (the first read after unlock) and is routed via `DbCorruptDialog`.

### Uninstall behavior

User data lives **outside** the install directory in `getApplicationSupportDirectory()`, so removing the app binary leaves the data behind by design — protects against accidental data loss on reinstall/upgrade. Users who want a clean uninstall:

| Platform | How user data is removed |
|----------|--------------------------|
| Windows (Inno Setup) | Uninstaller offers a "Also delete user data" checkbox. Unchecked by default. If checked, `%APPDATA%\letsflutssh\` is recursively deleted post-uninstall |
| Linux (.deb) | `apt-get remove` keeps user data; `apt-get purge` also removes config, but user data in `~/.local/share/letsflutssh/` must be deleted manually |
| Linux (AppImage) | No installer — delete `~/.local/share/letsflutssh/` manually |
| macOS (.dmg) | Drag-to-Trash leaves user data in `~/Library/Application Support/letsflutssh/` — delete manually |
| Android | OS uninstall removes the entire app sandbox including user data |
| iOS | OS uninstall removes the entire app sandbox including user data |

### Store → FRB DAO pattern

Each Dart store wraps an FRB-generated DAO under
`lib/src/rust/api/db.dart`. The Riverpod notifier reads / writes
through `dbInit(...)` once on unlock; subsequent reads /
writes hop into Rust via `tokio::task::spawn_blocking` so the
FRB worker thread is never blocked on disk I/O. Mappers
(`lib/core/db/mappers.dart`) translate between domain objects
and the FRB DTOs.

### Encryption engine build path

The encryption half of the storage stack — SQLCipher 4.x —
is bundled in-tree via the `rusqlite` crate's
`bundled-sqlcipher-vendored-openssl` Cargo feature. **Both
SQLCipher AND the OpenSSL it depends on are statically
vendored** (via `openssl-src`) — no separate native binary,
no `third_party/` submodule, no Flutter build hook, no
system OpenSSL prereq on any cross-compile target. A fresh
clone is enough; `cargo build` compiles SQLCipher + OpenSSL
in-process along with the rest of the Rust workspace,
picking up sources from `rusqlite`'s vendored copies. First
build pays ~40s extra for the OpenSSL source compile; the
cargo `target/` cache reuses it on subsequent builds.

The vendored variant replaced the plain `bundled-sqlcipher`
feature once the release matrix expanded to Android NDK +
MSVC Windows + iOS + ARM64 Linux runners — none of which
have system OpenSSL provisioned, all of which fail
`bundled-sqlcipher`'s linker step with `'openssl/crypto.h'
file not found`. Vendoring is the difference between
"download Flutter, run make, ship" and "configure OpenSSL
per platform, hope vcpkg / NDK headers are aligned".

**Why SQLCipher and not the previous SQLite3MultipleCiphers /
ChaCha20 stack** is covered in detail in §3.6 → "Cipher choice
— SQLCipher 4.x". Short version: one Cargo feature flag, vs.
vendoring the MC submodule plus custom `pubspec.yaml` build
hooks plus a per-cipher `HAVE_CIPHER_*` defines block. Build
complexity dropped to zero; AES-256-CBC + HMAC-SHA512 vs.
ChaCha20-Poly1305 is a neutral cipher swap on every
actively-shipped target (every ARMv8 / x86-64 device with
hardware AES).

**Reproducibility.** `rust/Cargo.lock` pins the exact
`rusqlite` version + the bundled SQLCipher revision shipped
with it, so the compiled blob is byte-stable across machines.
Dependabot tracks the workspace `Cargo.lock` under
`package-ecosystem: cargo` (see `.github/dependabot.yml`,
monthly cadence) and opens PRs for the inevitable rusqlite /
SQLCipher minor bumps; the existing `make rust-test` +
`make test` matrix on the PR catches a breaking cipher or
schema change before merge.

---

## 12. Platform-Specific Behavior

| Aspect | Desktop (Linux/macOS/Windows) | Mobile (Android/iOS) |
|--------|-------------------------------|---------------------|
| Entry point | `MainScreen` (sidebar + tabs) | `MobileShell` (bottom nav) |
| Navigation | Sidebar + tab bar | Bottom nav: Sessions / Terminal / SFTP |
| Terminal | Tiling (split panes) | Full screen, single pane |
| File browser | Dual-pane (local + remote) | Single-pane (toggle) |
| Selection | Click + Ctrl/Shift + marquee | Long-press → bulk mode |
| Context menu | Right-click | Long-press |
| Keyboard | Hardware only (`hardwareKeyboardOnly: true`) | SSH keyboard bar + system |
| SSH keep-alive | OS keeps process alive | Foreground service (Android) |
| Home directory | `HOME` / `USERPROFILE` | Android: `EXTERNAL_STORAGE` / `/storage/emulated/0`; iOS: app Documents dir + folder picker |
| Drag & drop | desktop_drop + inter-pane | None |
| Deep links | `app_links` (URL scheme) | `app_links` (URL scheme + file intents) |
| Single instance | Native shell primitive (Linux GtkApplication D-Bus uniqueness; Windows `CreateMutexW` named mutex; macOS `LSMultipleInstancesProhibited`) — see [§ Single-instance protection](#single-instance-protection-desktop-only) | OS-managed natively |
| Font scaling | UI scale in settings | Terminal font slider in settings |

### Android specifics

- **Storage permission** — `MANAGE_EXTERNAL_STORAGE` for full file access. Requested via the `com.letsflutssh/permissions` MethodChannel in `MainActivity.kt` — shared helper `utils/android_storage_permission.dart`. Android 11+ opens the system "All files access" settings page (`ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`); older versions use the standard `READ_EXTERNAL_STORAGE`/`WRITE_EXTERNAL_STORAGE` runtime dialog. No external plugin (avoids `permission_handler` GPS side-effects)
- **Export folder picker** — once `MANAGE_EXTERNAL_STORAGE` is granted, `.lfs` exports use the in-app [`LocalDirectoryPicker`](#6-widgets--public-api-reference) (a `dart:io` directory browser) instead of SAF's `ACTION_OPEN_DOCUMENT_TREE`. SAF asks for per-folder consent on every export even when all-files access is already granted — that's the UX bug the picker sidesteps. Without `MANAGE_EXTERNAL_STORAGE` the flow still falls back to the SAF picker via `file_picker.getDirectoryPath`
- **QR scanner** — native `QrScannerActivity.kt` using CameraX (AndroidX) for the preview pipeline and ZXing-core (Apache 2.0 jar) for decoding. Exposed through the `com.letsflutssh/qrscanner` MethodChannel, `method: scan`. **No Google Play Services / MLKit** — works offline on AOSP builds and degoogled devices
- `flutter_foreground_task` for keep-alive on screen lock
- APK split per ABI: arm64-v8a, armeabi-v7a, x86_64

### iOS specifics

- `NSLocalNetworkUsageDescription` required for local TCP
- `NSCameraUsageDescription` required for the QR scanner (scan-only)
- No foreground service (iOS background modes)
- **Local file browser** — starts in app's Documents directory (`getApplicationDocumentsDirectory()`), which is accessible via Files.app. Users can browse outside the sandbox via a "Pick Folder" button (iOS only, uses `file_picker` → `UIDocumentPickerViewController` in folder mode). Security-scoped access is granted for the session after the user picks a folder
- **QR scanner** — `QrScannerController.swift` built on `AVCaptureSession` with `AVMetadataMachineReadableCodeObject` restricted to `.qr`. System framework only, zero external dependencies. Registered on the shared `com.letsflutssh/qrscanner` channel from `AppDelegate`

### Desktop window constraints

All desktop platforms enforce a minimum window size of **480 × 360** logical pixels to prevent layout overflow:

| Platform | File | Mechanism |
|----------|------|-----------|
| Windows | `windows/runner/win32_window.cpp` | `WM_GETMINMAXINFO` with DPI scaling |
| Linux | `linux/runner/my_application.cc` | `gtk_window_set_geometry_hints` (`GDK_HINT_MIN_SIZE`) |
| macOS | `macos/Runner/MainFlutterWindow.swift` | `NSWindow.contentMinSize` |

Additionally, internal resizable elements (sidebar, file browser columns, split panes) use overflow-safe patterns:
- **`ClippedRow`** (`widgets/core/clipped_row.dart`): drop-in `Row` replacement with custom `_ClippedRenderFlex` that clips overflow and suppresses the debug overflow indicator entirely. Used in file browser rows, column headers, breadcrumb paths, connection bar, and transfer panel
- **Sidebar text** (`_SidebarFooter`, `_PanelHeader`, session tree rows): `Flexible` / `Expanded` with `TextOverflow.ellipsis`
- **Welcome screen**: `SingleChildScrollView` prevents vertical overflow on small windows

### Cold-start ordering — pre-init / post-init invariant

The boot path splits into two halves with the `runApp` call as the
boundary. FRB readiness is established **inside** the pre-`runApp`
slice — every step after `_initRustCoreOrFatal` (including
`loadAppConfigFromDisk` and `runApp` itself) executes with a live
Rust core. The narrow pre-FRB window collapses to the few ms spent
inside `RustLib.init()`; `logCritical` writes during that window
still buffer through the ring at `AppLogger._preFrbCriticalBuffer`
and drain via `AppLogger.onFrbReady()` immediately after init
returns.

```
_mainBody (synchronous, pre-runApp):
  WidgetsFlutterBinding.ensureInitialized
  SecureKeyStorage.enableRuntimeSubprocessProbes()      // bool flag
  AppLogger.init()                                      // path resolution
                                                         // (path_provider only;
                                                         // no dart:io File ops)
  error handlers (FlutterError + PlatformDispatcher + zone)
                                                         // logCritical buffers
                                                         // pre-FRB; stderr
                                                         // mirrors on desktop
  _initRustCoreOrFatal:
      RustLib.init()                                    // load .so/.dll
      rust_app.appInit()                                // AppState singleton
      bootstrapRustConfigStore()                        // config_store actor
                                                         // loads config.json
                                                         // through symlink-safe
                                                         // Rust read; throws
                                                         // AppConfigParseException
                                                         // on a corrupt file →
                                                         // config-corrupt
                                                         // FatalErrorApp
      AppLogger.attachCoreLogPipe()                     // bus → file sink
      ProcessHardening.applyOnStartup()
  AppLogger.onFrbReady()                                // drains the pre-FRB
                                                         // critical-write
                                                         // buffer; registers
                                                         // the log path
                                                         // Rust-side; opens
                                                         // sink if threshold
                                                         // already non-null
  loadAppConfigFromDisk                                 // snapshots the Rust
                                                         // config_store actor
                                                         // (config_store_get_json
                                                         // + was_loaded_from_disk);
                                                         // no dart:io File on
                                                         // config path
  setThreshold(config.logLevel)                         // sink open lands here
                                                         // since FRB is up
  runApp(LetsFLUTsshApp)                                // first frame paints
                                                         // user's theme +
                                                         // locale; splash visible
──── post-frame _bootstrap:
  activateDeepLinks(ref.read(deepLinkHandlerProvider))  // FRB-driven
                                                         // initial-URI
                                                         // pump
  _wireFrbDependentBootstrapListeners                   // every AppBus.subscribe
      HostKeyPromptListener.start()
      KeychainProbePromptListener.start()
      HardwareVault*PromptListener.start() × 3
      TierStateObserver.start()
      ref.read(foregroundActiveCountListenerProvider)   // triggers StreamProvider
  BackupExclusion.applyOnStartup()                      // unawaited, FRB
  appVersionProvider.load
  warmProbeCaches                                       // capabilities + hardware + keyring
  securityController.bootstrap                          // migrations + tier unlock + DB open
  → readyNotifier.value = true                          // splash hides
```

**Invariant — STRICT.** The pre-FRB window narrows to the few ms during `RustLib.init()` itself. Nothing reachable from the synchronous slice of `_mainBody` *before* the `await _initRustCoreOrFatal()` call may import `package:letsflutssh/src/rust/...` or otherwise reach FRB; everything after that call runs against a live Rust core. The zone / framework / platform error handlers installed in that slice fire from arbitrary later points in the process lifetime, so their handler bodies still defer FRB-touching work — `logCritical` is the canonical example: it buffers into `_preFrbCriticalBuffer` until `_frbReady` flips and drains.

**Why the pre-FRB slice is narrow, not zero.** Three reasons keep the slice non-empty rather than collapsing it further:

* **`WidgetsFlutterBinding.ensureInitialized` must run inside the zone that owns the eventual `runApp` call** — Flutter warns + tests crash on a zone mismatch when they diverge. The binding init itself does not touch FRB.
* **Error handlers must be installed before any code that might crash** — including `RustLib.init()`. If the native blob crashes loading, the zone handler is the only forensic surface; if its body called FRB it would crash-loop the handler. The handlers therefore install pre-init and gate on `_frbReady`.
* **`AppLogger.init()` resolves `<appSupport>/logs/letsflutssh.log` as a string via the Flutter `path_provider` plugin** — needed before `setThreshold` can record where the eventual sink open will land. Pure path composition; no file ops.

**Why the invariant exists.** Pre-FRB FRB calls throw `StateError("flutter_rust_bridge has not been initialized")`. Past failure modes that motivated the boundary: the zone error handler calling FRB-backed log-timestamp helpers crash-looped on FRB-not-init; `MainScreen.initState` wiring `*PromptListener.start()` → `AppBus.subscribe` left dead `_SharedTopic` entries that never recovered to live FRB subscriptions; `AppConfig.fromJson` → `rust_config.configAppConfigSanitizeJson` raced the native lib load and on the losing race silently overwrote the on-disk config with defaults; the unlock cascade hung for minutes when one of its FRB-backed steps fired pre-init and the retry loop kept re-entering the same throw. Every one of these shipped at some point as a real bug. The fix is structural — move `RustLib.init()` to the top of `_mainBody` so the rest of the pre-`runApp` slice (config snapshot, threshold, logger sink) sees a live core, and keep the handlers that can still fire pre-FRB (zone + FlutterError + PlatformDispatcher + the in-`RustLib.init` window itself) on a deferred path that drains after `onFrbReady`.

**Dart-side I/O carve-out — narrow, named, justified.** Rust owns persistent state and platform I/O everywhere except this fixed list, where a Flutter-only primitive forces a Dart-side touch. New Dart-side filesystem / OS-API call sites outside this list are regressions. Every entry runs without holding secret material:

* **`config.json` load — Rust-routed.** [`loadAppConfigFromDisk`](../lib/providers/config_provider.dart) snapshots the Rust `config_store` actor (`config_store_get_json` + `config_store_was_loaded_from_disk`); `bootstrapRustConfigStore` (called from `_initRustCoreOrFatal`) is the single reader of the on-disk `config.json` via the Rust-side symlink-safe `read_bytes_secure`. No `dart:io File` / `Directory` operation touches the config path Dart-side. Corrupt JSON throws `AppConfigParseException` (rethrown from inside `_initRustCoreOrFatal`) → fatal-error screen, never silent-rewrites.
* **Pre-FRB fatal wipe** — [`earlyWipeAppSupportFiles`](../lib/app/early_wipe.dart) is the bottom of the recovery ladder when `RustLib.init()` itself fails (the native blob is the broken artefact). Enumerates the immediate children of `<app_support>` (a per-bundle subdir resolved by `path_provider`) and deletes each. No hardcoded filename list — the sweep is drift-proof because any future artefact the Rust side writes under `<app_support>` is covered automatically. The canonical `WipeAllService.wipeAll()` runs Rust-side once FRB is healthy and also clears keychain / hardware-vault entries; this path is reached only when the Rust-side path is unreachable. OS-secure-storage orphans left behind resurface on the next launch and route through `_handleLegacyStateIfPresent` → `TierResetDialog` for proper cleanup.
* **Cold-start logger path resolution** — [`AppLogger.init()`](../lib/utils/logger.dart) calls `getApplicationSupportDirectory()` (a Flutter plugin, not FRB) to compose `<appSupport>/logs/letsflutssh.log` as a string; no `dart:io` File / Directory ops touch the path. The file create / append / chmod / rotate / read / clear surface lives Rust-side under `lfs_core::logger::file_sink` and routes through eight FRB entry points (`logger_open_sink`, …, `logger_close_sink`). `_mainBody` runs `_initRustCoreOrFatal` first, then calls `AppLogger.onFrbReady()` (registers the log path Rust-side, opens the sink if a threshold is already non-null, drains the pre-FRB `_preFrbCriticalBuffer` cap-64 ring through `logger_append_critical`), then `setThreshold(effectiveLevel)` against the live runtime. During the few-ms `RustLib.init()` window routine `log()` calls are no-ops (the sink has not opened yet); critical writes hit the buffer + stderr mirror on desktop so a crash inside that window still leaves a breadcrumb after boot.
* **Single-instance lock** — `flock` (Linux/macOS) / `CreateMutexW` (Windows) live in the native shell, **not** Dart. The Dart side does not race for the lock at all; this entry is included so the mental map of "what touches OS state on cold-start" stays complete.
* **`path_provider` resolution** — `getApplicationSupportDirectory()` is the only platform-channel call the Dart side keeps, because `lfs_core` is OS-FFI-free by design. Resolved paths cross FRB to Rust shims (`recorder_list_recordings`, `update::orchestrator::cleanup_stale_downloads`, archive read paths) so disk walks themselves stay Rust-side.

**How to add a new pre-`_initRustCoreOrFatal` step.** That slice is the few statements between `WidgetsFlutterBinding.ensureInitialized` and the `await _initRustCoreOrFatal()` call. Use only `dart:io`, `dart:convert`, `path_provider`, `package:flutter/foundation`. Importing anything under `lib/src/rust/` from code reachable here is a regression — fail loud at review.

**How to add a new post-init listener / FRB-touching boot step.** Two valid hosts:
* One-shot setup that must finish before `runApp` (and the post-frame `_bootstrap` chain) — extend `_mainBody` between `_initRustCoreOrFatal` and `runApp`.
* Listeners + bus subscribers that should run after the first frame — wire inside `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners` (for AppBus subscribers) or directly in `_bootstrap` (for one-shot setup that does not need to block the first paint).

Don't add it to `_MainScreenState.initState` — that fires during the first runApp frame, which now sits *after* FRB init but predates the post-frame `_bootstrap` chain that wires every prompt subscriber.

**Pre-FRB handler bodies that defer FRB work.** The error handlers installed before `_initRustCoreOrFatal` can fire while `RustLib.init` is still pending — their bodies stay FRB-safe by buffering or short-circuiting until `_frbReady` flips:

* **`AppLogger.logCritical` writing pre-FRB.** The zone error handler in `main.dart` calls `logCritical` from inside `runZonedGuarded`, plus the `FlutterError.onError` / `PlatformDispatcher.onError` shims; these can fire while `RustLib.init` is still in flight. The file write target is `logger_append_critical` (FRB), so a pre-FRB call would throw `StateError` and crash-loop the handler. The Dart side gates on `_frbReady`: pre-FRB the rendered entry lands in `AppLogger._preFrbCriticalBuffer` (cap 64, FIFO eviction) plus a stderr mirror on desktop; `_mainBody` drains the buffer via `AppLogger.onFrbReady()` immediately after `_initRustCoreOrFatal` returns. Without the buffer + drain a fresh-install crash inside the native-lib load would land nowhere — neither on disk nor in a recoverable surface.
* **Deep-link wireup.** `DeepLinkHandler.init()` runs `getInitialLink()` then `handleUri` → `rust_deeplink.deeplinkDispatch` (FRB). The handler lives in `deepLinkHandlerProvider` (process-wide). `_MainScreenState.initState` registers callbacks via `wireDeepLinks(...)` (pure-Dart wiring); `_bootstrap` calls `activateDeepLinks(...)` post-frame to fire `init()`. A cold-launch via `letsflutssh://` URL or a double-clicked `.lfs` file therefore lands after FRB init.

**`AppBus.subscribe` keeps its retry path.** A single Riverpod provider — `connectionActiveCountProvider` (`lib/providers/connection_provider.dart`) — has a `build` that may run during the first runApp pass (a top-bar badge watches the count) and calls `AppBus.subscribe` from inside that build. FRB is up by the time `runApp` fires, so the subscribe lands on a live runtime in normal cold-start. The retry path stays wired for two structural reasons: the test harness mounts widget trees without going through `_mainBody` (so FRB may not be initialised in unit tests), and `AppBus.subscribe` from inside a `Notifier.build` is structurally fragile against future refactors that move call sites earlier in the chain. `_SharedTopic.ensureFrbSub` checks `RustLib.instance.initialized` and returns early when the core has not loaded, handing back the Dart-side `StreamController.broadcast` stream regardless; `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners` calls `AppBus.retryFrbSubscriptions()` so any deferred topic promotes to a live FRB subscription, and listeners that already attached to the broadcast stream start receiving events without re-listening.

**FRB-ready / pre-DB-init window for Riverpod stream providers.** FRB is up by the time `runApp` fires, but `db_init` lands inside `securityController.bootstrap` — i.e. *after* the first frame. Stream providers that hydrate from DB-backed FRB DAOs (`sessionsWorkspaceStreamProvider`, `knownHostsStreamProvider`, `sshKeysStreamProvider` via `SshKeysMutator.loadAllMetadata`) mount on that first frame and fire their initial load against `app.db() == None` Rust-side, which returns `Err("db not initialized")`. Each loader catches the error by substring (`e.toString().contains('db not initialized')`), yields the empty snapshot, and waits for the matching post-unlock `*Changed` event the `tier_unlock_orchestrator::run_post_unlock_cascade` publishes once `db_init` lands. The substring gate is the canonical pattern — copy it verbatim when adding another DB-backed stream provider. Unexpected errors (locked-tier reads against a wrong key, corrupted DB) log at `LogLevel.warn` (recoverable, the stream stays at empty) rather than `error`.

### Single-instance protection (desktop only)

Prevents multiple app instances from running simultaneously, which would corrupt the shared database, and follows the OS-standard "focus the existing window on duplicate launch" UX every desktop file manager + Start menu / Dock expects.

**Enforced in the native shell, BEFORE the Flutter engine boots.** Each platform uses its canonical primitive:

| Platform | Primitive | Where |
|---|---|---|
| **Linux** | GtkApplication's D-Bus uniqueness (no `G_APPLICATION_NON_UNIQUE` flag) | `linux/runner/my_application.cc` `my_application_new()` |
| **Windows** | `Local\LetsFLUTssh-SingleInstance` named mutex via `CreateMutexW` | `windows/runner/main.cpp` `wWinMain()` |
| **macOS** | `LSMultipleInstancesProhibited = true` in `Info.plist` (NSApplication enforces) | `macos/Runner/Info.plist` |

**Behaviour on duplicate launch:**

1. Linux: in `my_application_local_command_line`, after `g_application_register`, `g_application_get_is_remote() == TRUE` indicates a primary instance already owns the D-Bus name. The duplicate calls `gtk_init` + `gtk_message_dialog_new` + `gtk_dialog_run` to surface a native GTK info dialog (`"An instance of LetsFLUTssh is already running."`, OK button), then exits without invoking `g_application_activate` and without spinning up the Flutter engine.
2. Windows: `wWinMain` calls `CreateMutexW` immediately. `GetLastError() == ERROR_ALREADY_EXISTS` → `MessageBoxW("An instance of LetsFLUTssh is already running.", "LetsFLUTssh", MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND)` for a native Win32 info dialog, then `CloseHandle` + `return EXIT_SUCCESS`. Mutex auto-releases on process exit.
3. macOS: NSApplication detects the duplicate launch via Launch Services and forwards activation to the existing process (window comes to front). The duplicate process never starts; no dialog. macOS users expect this silent focus-existing behaviour as the platform convention — every Cocoa app does this and surfacing an "already running" alert would feel out of place against the rest of the system.

**Why English-only text in the dialogs.** Pulling the strings from `lib/l10n/app_*.arb` would require running enough of the Flutter engine to reach the localisation runtime, which defeats the speed benefit of rejecting the duplicate launch before the engine boots. The brief modal is acceptable in EN-only — the `OK` button itself renders in the OS's system locale via `MessageBoxW` / `GtkMessageDialog`'s native chrome.

**Mobile:** Android + iOS manage single instance through their activity / scene lifecycle — no app code involved.

**Why native, not Dart.** The previous implementation was `lib/core/single_instance/single_instance.dart` using `RandomAccessFile.lock` (and before that an `lfs_os_security::single_instance` Rust module via FRB). Both ran AFTER the Flutter engine had already booted — the duplicate process paid the entire engine boot before reaching the duplicate-check, then showed an `AlreadyRunningApp` blocker the user had to dismiss. Three concrete benefits of moving the gate into the native shell:

* **Faster reject** — duplicate launches return in milliseconds instead of seconds.
* **Standard UX** — focus the existing window instead of showing a custom error dialog.
* **No Dart-side ordering concerns** — earlier the FRB-bound version of `acquire` had to coordinate with `RustLib.init` (it threw "RustLib not initialised" when called too early); the native gate side-steps the cold-start `pre-init / post-init` invariant entirely, since there's no Dart code in that path at all.

**Files:** `linux/runner/my_application.cc`, `windows/runner/main.cpp`, `macos/Runner/Info.plist`. No Dart-side code.

### Windows specifics

- `hardwareKeyboardOnly: true` — xterm TextInputClient bug
- Inno Setup for EXE installer
- `USERPROFILE` for home directory

---

## 13. Security Model

### Tier matrix

The full per-tier model lives in [§3.6 Three-Tier + Paranoid Model](#three-tier--paranoid-model). The summary at this scope:

| Tier | Key source | Database encryption | On-disk artefacts |
|---|---|---|---|
| **Plaintext (T0)** | None | `letsflutssh.db` — opened via rusqlite/SQLCipher with no `PRAGMA key` | `letsflutssh.db` |
| **Keychain (T1)** | OS keychain via `lfs_os_security::secure_key_storage` (Apple SecItem / Linux libsecret / Windows CredMan / Android Keystore JNI) | `letsflutssh.db` — SQLCipher 4.x (`PRAGMA key`) | `letsflutssh.db`, `keychain_enabled` |
| **Keychain + password (T1+pw)** | OS keychain + T1+pw password gate (HMAC-SHA256 verifier with split-storage pepper, paired with an HKDF-derived HMAC-bound rate-limiter) | SQLCipher 4.x (`PRAGMA key`) | `letsflutssh.db`, `security_pass_hash.bin`, `rate_limit_state.bin`, `keychain_enabled` |
| **Hardware (T2)** | Hardware-sealed wrap (TPM 2.0 / Secure Enclave / AndroidKeyStore strongbox / CNG TPM) | SQLCipher 4.x (`PRAGMA key`) | `letsflutssh.db`, `hardware_vault_*.bin`, optional overlay (.password_overlay) |
| **Paranoid** | Argon2id-derived from master password — never stored in the OS | SQLCipher 4.x (`PRAGMA key`) + `credentials.kdf` + `credentials.verify` + `credentials.key` | `letsflutssh.db`, three `credentials.*` files |

Encryption is applied at the database level via SQLCipher 4.x (AES-256-CBC + HMAC-SHA512) — a single encrypted DB file replaces the old per-store AES-256-GCM files.

### First-launch auto-select

`_firstLaunchSetup` in `main.dart` probes capabilities via [`probeCapabilities`](../lib/core/security/security_bootstrap.dart) and picks the tier itself. The multi-option wizard is a fallback that only fires when the choice matters on this device — 99% of installs never see it.

`probeCapabilities` is a thin async wrapper around `lfs_core::security::capabilities_orchestrator::run` (FRB) — the orchestrator fans the four probes (keychain / hardware vault / biometric / fprintd) out concurrently via `tokio::join!` with a 5 s per-probe timeout, composes the snapshot, pushes it through the `capabilities_cache` actor, and returns it. Two of the four probes need a Dart-side helper because they wrap UI-bearing platform plugins; those run through `KeychainProbePromptListener` and `HardwareVaultProbePromptListener` (each subscribes to the matching `BusEvent::*ProbePromptRequest` and resolves with `*_probe_prompt_resolve`). The biometric + fprintd probes execute entirely Rust-side via `lfs_os_security::biometric_auth::check_availability` and the Linux `fprintd` D-Bus path inside `lfs_core::platform::linux::fprintd` — no Dart prompt listener is needed for them. A Rust-side failure propagates directly to the caller. **Don't add a Dart-mirror fallback pipeline** — a shadow probe with even slightly different semantics silently masks Rust-side failures and hides the orchestrator's actual failure mode.

1. Probe keychain + hardware vault classified results in parallel via the Rust orchestrator.
2. **Keychain reachable (common path)** → silently land on T1: generate a random DB key, write it to the OS keychain, inject the database, log the auto-select. No dialogs, no prompts. The `FirstLaunchBannerData` is queued on [`firstLaunchBannerProvider`](../lib/providers/first_launch_banner_provider.dart) so the main screen pops a one-shot confirmation dialog telling the user which tier we picked and whether a hardware upgrade is reachable.
3. **Keychain unreachable (Linux without libsecret / kwallet, or an explicit `FlutterSecureStorage` probe failure)** → fall through to `SecuritySetupDialog` in its **reduced** layout. When both `caps.keychainAvailable` and `caps.hardwareVaultAvailable` come back false, the wizard hides the T1 + T2 rows entirely and renders a banner at the top naming the missing dependency (`wizardReducedBanner`: "OS keychain not reachable — install gnome-keyring / kwallet / libsecret provider"). The remaining choice collapses to T0 (plaintext) vs Paranoid (master password). Showing the two disabled rows with tooltip grumbles was the first iteration and read as "we're hiding options from you"; collapsing to the rows the user can actually pick matches what the decision is about, and the banner keeps the honesty.

*Why auto-select on top of the existing wizard:* the wizard was jarring as a first-run experience. Five tiers × two modifiers = ten combinations staring at a user who just wanted an SSH client. T1 is a solid default — protects against cold-disk theft, unlocks silently, zero friction — and the upgrade path to T2 / Paranoid is one tap away in Settings. The banner is the honest middle ground: we picked for you, here is what we picked, here is the upgrade path or the reason it is not available.

*Post-setup banner:* [`FirstLaunchSecurityToast`](../lib/widgets/security/first_launch_security_toast.dart) — top-right `Overlay`-based toast shown by `_MainScreenState` when the provider fires. Replaces an earlier blocking `FirstLaunchSecurityDialog`: the auto-selected T1 is a safe default the app already landed on, so a modal that pins the user to click Dismiss before touching anything else is heavier than the choice warrants. The toast carries the same copy (what we picked + whether a hardware upgrade is within reach), offers an **Open Settings** action when `caps.hardwareVaultAvailable == true && current tier != hardware`, auto-dismisses after 8 seconds, and never blocks input. `onDismiss` clears the provider so the toast never re-opens; same no-persistence property as the dialog it replaced.

*Settings discoverability cards:* the Security section consumes the same capabilities snapshot via [`securityCapabilitiesProvider`](../lib/providers/security_provider.dart) (a session-scoped `FutureProvider` — TPM / Secure Enclave / libsecret don't appear or disappear mid-session, so one probe per container is correct). When the current tier is below `SecurityTier.hardware`, Settings renders one of two cards right under the active-tier info tile:

- **`_HardwareUpgradeBanner`** — green-bordered action card pointing at the existing "Change security tier" wizard, shown when `caps.hardwareVaultAvailable == true`.
- **`_HardwareUnavailableNotice`** — neutral info card with the per-platform reason from `defaultHardwareUnavailableReason()` + `hardwareUnavailableReasonText()` (shared with the first-launch dialog so both surfaces speak in lockstep), shown when the probe came back false.

Paranoid is treated as "already opted out of OS trust" and never shows the upgrade card — offering a user who picked Paranoid an "upgrade to TPM" tile would be wrong-direction advice.

*Classified unavailability reasons.* A tier that reports `isAvailable: false` still needs to tell the user *why*, or the Settings card reads as a dead end. Two providers resolve a typed reason code into a localised hint line rendered under the disabled card:

- [`hardwareProbeDetailProvider`](../lib/providers/security_provider.dart) — maps a [`HardwareProbeDetail`](../lib/providers/security_provider.dart) case to the `hwProbe*` ARB keys. Linux routes through FRB into [`lfs_core::platform::linux::tpm::probe`](../rust/crates/lfs_core/src/platform/linux/tpm.rs) which distinguishes `deviceNodeMissing` (no `/dev/tpmrm0`), `binaryMissing` (no `tpm2-tools`), and `probeFailed` (CLI returned non-zero). macOS / iOS / Android / Windows route through Rust `lfs_os_security::hardware_tier_vault::probe_detail` — Windows lives under `lfs_os_security::windows::hardware_vault` since the C++ MethodChannel plugin retired. All paths emit one of the platform-specific codes:
  - **Windows** — `windowsSoftwareOnly` (TPM 2.0 absent, only Software KSP reachable), `windowsProvidersMissing` (both CNG providers fail — corrupted crypto subsystem or blocking GPO).
  - **macOS** — `macosNoSecureEnclave` (pre-T2 Intel Mac), `macosPasscodeNotSet` (SE present, login password absent), `macosGeneric` (any other `LAError`).
  - **iOS** — `iosPasscodeNotSet`, `iosSimulator` (Simulator has no SEP), `iosGeneric`.
  - **Android** — `androidBiometricNone` (no fingerprint / face hardware), `androidBiometricNotEnrolled`, `androidBiometricUnavailable` (lockout or pending security update), `androidGeneric`. `androidApiTooLow` is still exposed by the Dart enum as a defensive fallback but the native plugin no longer emits it — `minSdk = 28` (see [`android/app/build.gradle.kts`](../android/app/build.gradle.kts)) guarantees StrongBox and BiometricPrompt are available.

  *Why the native side classifies rather than the Dart side:* the backing-level inference Linux does via file + process probes is not portable. On Apple the classifier needs the typed `LAError` code from `canEvaluatePolicy`, on Android it needs the `BiometricManager.canAuthenticate` status constant, on Windows it needs the `NCryptOpenStorageProvider` result. All three live on the native side already; the plugin returning a structured code is simpler than routing the raw error object through the method channel and re-classifying in Dart.

- [`keyringProbeDetailProvider`](../lib/providers/security_provider.dart) — maps a [`KeyringProbeResult`](../lib/core/security/secure_key_storage.dart) case to the `keyringProbe*` ARB keys. On Linux the probe routes through FRB into `lfs_os_security::secure_key_storage::secret_service_reachable` — a `zbus`-driven `SecretService::connect` against `org.freedesktop.secrets`. `Ok(connection)` = service registered and responds → `available`; transport failure / `ServiceUnknown` / no daemon → `linuxNoSecretService`. The same signal `libsecret` itself runs before every API call; probing up front lets us classify without spamming stderr on failure. **Don't pattern-match `WSL_DISTRO_NAME` or check `DBUS_SESSION_BUS_ADDRESS`** — both are proxies: WSL2 + WSLg ships a session bus but no keyring daemon, so env-var branches give the wrong answer. **Don't shell out to `gdbus`** — keeping the keyring data-path single-language (zbus inside Rust) avoids the "Dart subprocess for one introspection call" maintenance liability. Non-Linux platforms (Windows / macOS / iOS / Android) fall through to a live write-read-delete round-trip against `lfs_os_security::secure_key_storage`; failure = `probeFailed`.

The Linux subprocess path is guarded by `SecureKeyStorage.enableRuntimeSubprocessProbes`, called from `main.dart` at app startup. Widget tests running under FakeAsync do not reach that entry point, so the flag stays false and the probe short-circuits to an optimistic `available` — necessary because `Process.run` inside FakeAsync-managed code leaks a Timer onto the pending-timer list and fails unrelated widget tests.

Both providers are session-scoped (keyring failure modes on Linux don't change mid-session, hardware probe results are fixed by the boot-time state of the chip). Tier cards read the classified probe's `AsyncValue` as the authoritative availability signal too, not just for the reason-line copy — the fast-path `SecureKeyStorage.isAvailable()` uses only env + marker-file checks and would falsely mark WSL as "keychain available", leaving the Select button enabled on a broken system; the classified `probe()` is the actual truth. `caps.keychainAvailable` from the startup capabilities snapshot is kept as a fallback while the classified probe's future is still resolving, so the card renders optimistically on the first frame and snaps to the correct state milliseconds later.

### Startup security flow

`SecurityInitController.bootstrap()` in `main.dart` — database file is the sole source of truth for detecting existing installs:
1. DB file exists + master-password enabled → biometric first, else `UnlockDialog` → derive key
2. DB file exists + keychain has key → read from keychain
3. DB file exists but no encryption → plaintext mode
4. No DB file → first launch → probe capabilities, auto-select T1 when the keychain is reachable (queue the post-setup banner on `firstLaunchBannerProvider`), or show `SecuritySetupDialog` in its T0-vs-Paranoid form when the keychain is not reachable (see [First-launch auto-select](#first-launch-auto-select))
5. Open database via `_injectDatabase(key, level)` → `openDatabase(encryptionKey)` → `setDatabase()` on all stores + update `securityStateProvider`

### Master password

```mermaid
flowchart LR
    pw["User password"]
    pw --> kdf["Argon2id<br/>m=64 MiB, t=3, p=1<br/>32-byte salt"]
    kdf --> k["256-bit key"]
    k --> db["letsflutssh.db<br/>PRAGMA key = x'hex'"]
```

- **Detection:** `credentials.kdf` exists
- **Verification:** `credentials.verify` = AES-256-GCM(known plaintext "LetsFLUTssh-verify")
- **Enable flow:** derive key → re-open database with new key → delete keychain key if present
- **Disable flow:** try keychain → generate random key → re-open database → delete `credentials.kdf` + verifier. No keychain → plaintext fallback
- **Change flow:** verify old → derive new → re-open database with new key
- **Forgot password:** deletes encrypted database + kdf/salt/verifier files

### Update channel integrity

Each release ships **two** files alongside the binaries — one
`.sha256sums` manifest listing every artefact's sha256 digest, and
one detached Ed25519 signature `letsflutssh-<version>.sha256sums.sig`
covering that manifest. CI produces the pair via
`openssl pkeyutl -sign` against the `RELEASE_SIGNING_KEY` secret in
`.github/workflows/build-release.yml`. Per-artefact `.sig` files are
intentionally **not** produced — that older shape (one signature per
binary) doubled the surface for a forged-anchor swap and made the
auto-updater fetch N signatures per release; collapsing to one
signature over the manifest gives the same authentication with one
file to verify.

On the client, `UpdateService.downloadAsset` hands the full
pipeline to `lfs_core::update::http::download_with_verification`
through a single FRB call. The Rust orchestrator:

1. Streams the binary from the GitHub release URL into `<targetDir>/`,
   hashing each chunk into a SHA-256 accumulator as it goes — bytes
   never sit in a Dart heap buffer. Per-chunk progress is published
   on `BusTopic::Update` (`BusEvent::UpdateDownloadProgress`) so the
   Dart side can drive a determinate progress bar; the verifying
   phase emits `BusEvent::UpdateVerifyingStarted`.
2. Compares the per-asset SHA-256 from the Releases JSON against
   the streaming accumulator when the caller passed `expectedDigest`
   (belt-and-suspenders against an attacker who swapped only the
   binary; the empty-string default skips this step).
3. Downloads the manifest pair (`letsflutssh-<version>.sha256sums`
   + `.sha256sums.sig`) alongside the binary.
4. Verifies the manifest signature via
   `lfs_core::update::signing::verify_release_signature` — Ed25519
   verify against the single embedded `PRIMARY_PUBLIC_KEY`. On
   failure all three files are deleted and a
   `DbDownloadResult` with `errorKind = invalidSignature` returns;
   the Dart wrapper maps that into
   `InvalidReleaseSignatureException` so the UI surfaces a
   security-coloured toast.
5. Looks the artefact name up in the verified manifest and compares
   the streamed hash to the manifest line — mismatch deletes the
   binary and surfaces as `invalidSignature` too.
6. Hands the verified path back to the Dart caller, which forwards
   it to the platform installer (Windows Inno Setup `.exe` / Linux
   `.deb` / macOS silent `macosInstallerInstall` / Android via
   launcher). Other formats (AppImage, tar.gz, .dmg) fall through
   to `openFile()` which surfaces them in the OS file manager —
   auto-install is opt-in per format, the verify gate is universal.

Failure shapes the Dart wrapper distinguishes:

| `DbDownloadErrorKind`  | Dart exception                          | UI treatment            |
|---|---|---|
| `untrusted`            | `StateError("Untrusted update download URL: …")` | refuse, no retry |
| `network`              | `StateError("Update download failed: …")` | offer retry |
| `manifestUnavailable`  | `ReleaseManifestUnavailableException`    | offer retry (transient) |
| `invalidSignature`     | `InvalidReleaseSignatureException`       | security-coloured toast |

**Why this is independent of SHA-256 / TLS:** SHA-256 and the asset
URL come from the same `api.github.com` response, so a MITM who can
rewrite that response supplies both. TLS protects the channel only if
DNS, every trusted CA, and the network path are intact — attackers
have compromised all three historically. The Ed25519 signature comes
from a private key held offline by the maintainer and verified by a
public key compiled into the binary; the updater does not consult any
online service at verify time.

**Rotation:** single-pin layout — `lfs_core::update::signing::PRIMARY_PUBLIC_KEY` is the only trusted Ed25519 public key. Rotation is a manual-reinstall ceremony rather than an in-app hot-swap: generate a fresh keypair offline (`openssl genpkey -algorithm Ed25519 -out release-key-new.pem`), update the GitHub `RELEASE_SIGNING_KEY` secret + offline copy, edit the embedded pubkey bytes, ship the new release, announce via README + website. Existing installs whose auto-update breaks (because their embedded pubkey doesn't match the new signature) follow the manual-reinstall flow in [`SECURITY.md`](SECURITY.md). Why no hot-swap backup slot: an `Option<[u8; 32]>` placeholder pinned at `None` until a real rotation populates it costs API surface for zero today-value — the slot reappears trivially in the same PR that generates the next keypair when a rotation is actually planned.

**SPKI pinning (rejected, not implemented):** an SPKI gate over `api.github.com` / `objects.githubusercontent.com` was scoped during the audit pass and rejected. The app ships without analytics, telemetry, or a remote-management channel — a stale pin (GitHub keypair rotation) would silently break auto-update for everyone on the prior release with no detection path and no rescue mechanism. The Ed25519 release-manifest signature is what gates the same attacker class (CA / DNS compromise alone yields no payload an installer will trust), so the second wall costs operational autonomy without adding meaningful security headroom. Standard rustls + system trust anchors only on the update HTTP path.

### .lfs export

```
v1 header:
  ['LFSE' 4] [0x03 version 1] [KdfParams block ≤16] [salt 32B] [IV 12B]
  [AES-256-GCM(ZIP(sessions + keys + config + known_hosts + tags + snippets))]

Key = Argon2id(password, salt, m=64 MiB, t=3, p=1)
AAD = pre-IV header bytes (magic + version + KDF params + salt)
Legacy 0x02 envelopes (pre-AAD) decode through a fallback branch.
```

v1 is the permanent floor — archives with any other header version,
missing magic, or no manifest are rejected with
`UnsupportedLfsVersionException`. See the .lfs format table in §3.9 for
the full layout.

Export decrypts known_hosts via `KnownHostsNotifier.exportToString()`. Import returns content for caller to import via `KnownHostsNotifier.importFromString()`.

Sessions are serialized with credentials via `toJsonWithCredentials()`. Empty folders are stored as a JSON array of folder paths. Manager keys, tags (with session/folder assignments), and snippets (with session links) are each stored in separate JSON files inside the ZIP archive (see [§3.9](#39-import-coreimport) for full file list).

The archive also carries a `manifest.json` with `schema_version` (current: `ExportImport.currentSchemaVersion`, a sync FRB getter that reads `lfs_core::migration::SchemaVersions::ARCHIVE`), optional `app_version`, and `created_at`. Archives whose `schema_version` is missing, malformed, or higher than the current build are rejected with `UnsupportedLfsVersionException` by `lfs_core::archive::read_archive_to_pending` — the user re-exports from the current app version. Archive format bumps ship a transform inside the Rust archive read path rather than a registered migration: archives are user-supplied import payloads, not on-disk persisted state, so the framework registry deliberately leaves the `ARCHIVE` slot unregistered (see [§3.6 → Migration framework](#migration-framework) → `build_app_registry` non-registration rationale).

### TOFU (Trust On First Use)

- New host → dialog with SHA256 fingerprint → user accepts/rejects
- Changed key → warning dialog → user accepts/rejects
- Without callback → reject (fail-safe)
- Known hosts stored in DB `KnownHosts` table (encrypted with rest of DB)

### Deep link validation

- URL scheme whitelist
- Path traversal rejection (`../`)
- Host/port sanitization

### Error sanitization & localization

- `sanitizeError()` translates OS-locale error text to English using errno codes — **for logging only**
- `localizeError(S l10n, Object error)` maps errno codes, `SSHError` subtypes, and `TimeoutException` to localized strings via `S` — **for UI display**
- Handles `SSHError` chain: preserves structured data (`host`, `port`, `user`), sanitizes `cause` recursively
- 43 errno codes mapped (30 POSIX/Linux + 13 Windows Winsock)
- `SSHError` subtypes carry structured fields: `AuthError(user, host)`, `ConnectError(host, port)`, `HostKeyError(host, port)`
- `SFTPError` (`core/sftp/errors.dart`) — typed SFTP error with `message`, `cause`, `path`, `statusCode`, `userMessage`. Factory `SFTPError.wrap(error, op, path)` for wrapping raw exceptions with operation context
- `Connection.connectionError` stores raw `Object?` — localized at display time with `localizeError`
- Unknown errno → original OS text preserved as-is
- Applied in: `ConnectionsNotifier`, `TerminalTab.reconnect()`, `TransfersNotifier` (+ path stripping, inline error in transfer panel)

### Error Handling Architecture

#### Global Error Boundary (`main.dart`)

Three-layer error handling catches all errors at appropriate levels:

```mermaid
flowchart TD
    rzg["<b>runZonedGuarded</b><br/>Catches: async errors from onPressed, Future, Stream<br/>Action: Log (sanitized) + show user dialog"]
    feo["<b>FlutterError.onError</b><br/>Catches: build, layout, render errors<br/>Action: Log only (not user-facing)"]
    pdo["<b>PlatformDispatcher.onError</b><br/>Catches: errors that escape Flutter zone entirely<br/>Action: Log (sanitized) + show user dialog"]
    rzg --> feo
    feo --> pdo
```

**Error dialog behavior:**
- Shows via `WidgetsBinding.instance.addPostFrameCallback` — ensures Navigator is available
- Uses `useRootNavigator: true` — works even if current Navigator is broken
- Wrapped in `try/catch` — if dialog fails to show, error is logged
- User sees brief message; full details saved to log file (if logging enabled)

#### Sensitive Data Sanitization (`utils/sanitize.dart`)

All error messages are sanitized before logging to prevent accidental exposure of:

| Pattern | Redacted to | Example |
|---------|-------------|---------|
| `user@host` | `<user>@host` | `admin@example.com` → `<user>@example.com` |
| IPv4 | `<ip>` | `192.168.1.100` → `<ip>` |
| `host:port` | `host:<port>` | `example.com:2222` → `example.com:<port>` |
| Windows paths | `<path>` | `C:\Users\john\Documents\file.pem` → `<path>\Documents\file.pem`; bare `C:\Users\john` → `<path>` |
| Unix paths | `/<user>` | `/Users/john/.ssh/id_rsa` → `/<user>/.ssh/id_rsa`; bare `/home/john` → `/<user>` |

Usage: `sanitizeErrorMessage(message)` before logging any error that may contain connection details or file paths.

#### Live log viewer (`features/settings/settings_logging.dart` + `settings_logging_parser.dart` + `core/logs/log_store.dart` + `providers/log_store_provider.dart`)

Settings → Logging section renders the live log inline with per-row severity tint. Data flows through a process-singleton [`LogStore` (`core/logs/log_store.dart`)] — a `ChangeNotifier` that subscribes once to `AppLogger.liveEntries`, retains every emitted entry in an in-memory buffer (soft cap 50 k entries), and publishes the filtered subset the `ListView.builder` iterates over. Boot priming via `_LetsFLUTsshAppState._wireFrbDependentBootstrapListeners` calls `ensureSeeded()` after FRB init — that path async-reads the on-disk log file and folds its history into the buffer so opening the Logs tab is instant (no on-mount file read, no list rebuild).

`ensureSeeded` merges the disk seed with whatever live entries already arrived during construction: builds a `(timestamp, tag, message)` signature set from the parsed seed, drops any pre-seed live entries whose signature matches the seed (those duplicates appear because `AppLogger.log` writes to disk + emits on `liveEntries` in lock-step — the seed read picks the same bytes off disk), and keeps any truly-late live entries that arrived after the seed read started. Final order: seed (chronological from disk) at the top, leftover live entries at the bottom. Without this merge, boot logs ended up doubled and out of order — live appended at the start, the disk dump trailed behind starting with the `--- Log started ---` banner.

`Off` honours the user's choice on cold-start: the `--dart-define=LETSFLUTSSH_LOG_LEVEL` override seeds the threshold ONLY when `loaded.loadedFromFile == false` (no `config.json` on disk yet — fresh install). After the user has saved any setting at all, the on-disk config wins, including an explicit `Off`. Without this gate, `make run`'s dart-define silently resurrected `info` on every restart, so `Off` looked broken: writes kept happening regardless of the user's pick. Release builds ship with the override null, so this branch is a no-op there.

The Settings viewer shows when logging is on OR when the on-disk file is non-empty (archived from a previous session): `_LogViewerHost` checks `enabled || _logFileHasContent()` and falls through to the viewer with `active = enabled` so the toolbar reads "Live Log" / green dot vs "Archived log" / dim dot. Archived mode keeps export + clear reachable; no live writes happen because `setThreshold(null)` closed the sink.

Parsing is shared between the boot seed and the legacy export-to-clipboard path. `parseLogEntries` (pure, testable — `settings_logging_parser.dart`) is what folds the on-disk text into `LogEntry`s:

- splits primary `HH:MM:SS X [Tag] message` lines via regex `^(\d{2}:\d{2}:\d{2}) ([IWE]) \[([^\]]+)\] (.*)$`
- folds indented continuation lines (`  Error: ...`, `  Stack trace:`, raw stack frames) into the parent `LogEntry.continuations`
- tags header lines (`--- Log started <ISO> ---`, `Platform: ...`, `Dart: ...`) + any regex-miss line as `isHeader: true` so the viewer dims them

**Uniform row shape — single `Selectable` per entry, regardless of type.** Every entry flows through the same `_LogRow` widget which renders ONE `Container + Text.rich` with no nested selectable widgets. Only the `Container.decoration` border and the inline span sequence change per type:

| Variant | Border | Spans |
|---|---|---|
| Routine | 2 px left, level-tinted | `[timestamp dim] [TAG colour] [message] [\n + continuation lines, dim]` |
| Session-start banner (`--- Log started ... ---`) | 2 px left, `AppTheme.green` | message dim mono, verbatim — the green stripe is the only thing that distinguishes the run boundary from a routine row, keeping the row a uniform Container + Text.rich without bespoke geometry |
| Plain header (legacy `Platform:` / `Dart:` rows from rotated pre-banner files) | none | message dim mono, verbatim |

The tag is rendered inline as `[TAG]` in the level colour — NOT a `WidgetSpan` chip with its own `Text` child. A `WidgetSpan` would register the inner `Text` as a satellite `Selectable` and break the "single canvas" feel of drag-select: the tag would either skip selection or coalesce as a separate fragment, depending on which `Selectable` the drag rect intersected first. The flat `[TAG]` span keeps the entire row a single `Selectable`. Same reason the session-start line is rendered as a plain header rather than a bespoke banner widget — earlier iterations gave it hairlines + segment splitting + bright bold spans, and every variant introduced non-uniform geometry that broke the SelectionArea run. The `---` framing is enough visual signal on its own.

Rows are physically contiguous (no vertical margins on the `Container`, `height: 1.55` on the base `TextStyle` so the `Text.rich` paint area fills the row vertically). No `Padding` widgets between rows, no per-type wrapper widgets — the `SelectionArea` walks a uniform run of single-`Selectable` rows in paint order, so drag-select doesn't drop on inter-row gaps or in-row padding zones.

**Per-row `SelectionContainer` injects `\n` into copy output without touching layout.** Each row's `Container + Text.rich` sits inside a `SelectionContainer` whose delegate (`_RowNewlineSuffixDelegate`) extends `MultiSelectableSelectionContainerDelegate` and overrides `getSelectedContent` to append `\n` to whatever the inner `Text.rich` reports as selected. `SelectableRegion._copy` concatenates each child Selectable's `getSelectedContent()` without inserting a separator (`StringBuffer.write` only), so without the suffix a drag-select across N rows lands on the clipboard as one run-on line. The `\n` lives in the copy pipeline only — never as an `InlineSpan` — so on-screen row geometry stays unchanged. The first attempt at the same goal added a trailing `TextSpan(text: '\n', style: TextStyle(fontSize: 1, height: 0.001))` to every row; `Text.rich` still allocates baseline line metrics for the trailing newline regardless of the tiny font/height, so each row grew by one visible blank line. The `SelectionContainer` route sidesteps the rendering pipeline entirely. `ensureChildUpdated` is a no-op: each row's lifetime mounts with exactly one child `Text.rich` (one `Selectable`), so the base class's synthesised-edge-event bookkeeping (for mid-selection inserts) never has a Selectable to catch up. The toolbar `Copy log` button stays independent — it serialises `LogStore.allEntries` via `StringBuffer.writeln` directly.

The on-disk shape of the session-start line is one row: `--- Log started <YYYY-MM-DD HH:MM:SS> | <os name os version> | LetsFLUTssh <appVersion> ---`. `AppLogger._bannerWritten` suppresses duplicate banners on subsequent reopens within the same process (toggle Off → On in Settings, rotation cycling the file in place); `clearLogs` resets it because a clear is a deliberate new-session boundary. The `LetsFLUTssh <appVersion>` segment is populated from `PackageInfo.fromPlatform()` via `AppLogger.setAppVersion(...)` called from `_mainBody` pre-`runApp`. One row replaces the previous three-row block (`Log started`, `Platform: ...`, `Dart: ...`) — same forensic signal, no duplicate-meaning rows. Older rotated files still carry the legacy three-row shape; those rows fall through to the same header path (no italic, no special weight).

**Cross-process banner dedup at the read side.** `AppLogger._bannerWritten` is per-process — every fresh launch writes its own banner. When two processes start in quick succession without writing anything between them, the file accumulates back-to-back `--- Log started ---` markers (the user-reported "опять два раза лейбл о начале логов"). Writing through this on the disk side would require sync tail-of-file inspection in `_openSink`, which the `path_provider` mock plumbing doesn't make easy in tests. Instead, `LogStore._collapseAdjacentBanners` (run on every seed) and `LogStore._onEntry` (live-stream path) drop the older of two adjacent banners when no content sits between them — the later banner wins because it represents the session that's actually about to log. Other header rows (`Platform: ...`, `Dart: ...` from rotated legacy files) carry distinct content and don't coalesce.

The `SelectionArea`'s right-click / long-press toolbar uses a custom `contextMenuBuilder` only to fix one Flutter default-behaviour gap: a right-click without a prior selection surfaces a `Select all`-only menu, which gives the user nowhere to land a "copy this thing I clicked on" intent. The custom builder appends a `ContextMenuButtonType.copy` item (system-localised "Copy" label, no custom string) that copies the entire buffer when no selection is active; with a live selection the default Copy item already appears and our fallback is suppressed, so the menu reads as the standard system one in both states.

Filter toolbar above the list: three toggle chips (`I W E`, all on by default) + a live-substring search input that AND-combines with the level filter against message + tag + continuation text. Toggling either calls `LogStore.applyFilter` which recomputes the filtered subset against the full buffer and notifies the `ListenableBuilder` wrapping the `ListView.builder`.

`SelectionArea` wraps the `ListView.builder` so drag-select crosses row boundaries natively, and the right-click / long-press context menu is Flutter's default `AdaptiveTextSelectionToolbar` (Copy + Select All) — no custom builder. Toolbar buttons (`Copy log` / `Save log` / `Clear logs`) sit above the box; `Copy log` serialises the buffer's `allEntries` list (filter-independent — the action means "everything captured", not "what is shown after my level filter").

Sticky-tail scroll is structural, not scripted. The `ListView.builder` runs with `reverse: true` and an index transform (`entries[entries.length - 1 - i]`) so paint order is bottom-up: scroll offset 0 sits at the visual bottom (newest entry), and new entries land at index 0 so they naturally appear at the bottom on the next rebuild. A user scrolled up keeps their pixel offset across rebuilds — reading older entries while new ones arrive does not yank the view. No `_follow` flag, no `onStoreChanged` listener firing `jumpTo(maxScrollExtent)`. An earlier post-frame `jumpTo` shape produced a visible jump on tab open: `ListView.builder`'s first `maxScrollExtent` is an estimate (`itemCount × average item height`), the jump targeted that estimate, then the lazy sliver materialised the real rows and `maxScrollExtent` recomputed — clamping the position backward by a few rows. `reverse: true` removes the failure mode by starting at the tail without needing to move.

#### AppLogger (`utils/logger.dart`)

```dart
void log(String message, {String? name, Object? error, StackTrace? stackTrace});
Future<void> logCritical(String message, {String? name, Object? error, StackTrace? stackTrace});
```

- File logging is **disabled by default** — user enables via Settings → Enable Logging. The default-off stance is load-bearing: it protects users who never touch Settings from carrying a forensic trail around.
- Auto-rotation at 5 MB, keeps 3 rotated files, file chmod-0600 on POSIX.
- **Every message is auto-sanitized** before it leaves the process — both the `dart:developer` forward and the disk append run through `AppLogger.sanitize` which chains `redactSecrets` → `sanitizeErrorMessage` (the table [above](#sensitive-data-sanitization-utilssanitizedart)). Callers do not pre-sanitize by hand; `'Connect failed: $e'` is fine, the sanitizer picks the user@host / IP / PEM out of `$e`'s string form.
- `logCritical` is the crash-path variant — writes straight to disk even when `enabled` is false so the three global error boundaries in `main.dart` (`FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded`), the `MigrationRunner` fatal branch and `verifyDatabaseReadable` always leave a forensic breadcrumb. Routine lines stay on the opt-out gate.
- `stackTrace` parameter writes full stack trace to the log file for debugging; the trace also passes through `sanitize` so paths and IPs in frames are redacted.

##### Logging conventions (when to log, what to write)

The default-off sink means **there is no "log spam" cost** — only users who opted in pay the write, and they opted in because they want the detail. The rule is **err on more not fewer**, not the other way around.

*Required log points — add a line at every one:*

- Entry / exit of any operation that touches disk, the DB, the network, a subprocess, or a native plugin (success or failure).
- Every branch of a user-consequential `try/catch`, including the "caught and continued" path. A silent fallback with no log line is invisible in a support trace.
- Every decision on ambiguous input: archive kind detected, migration applied, TOFU branch chosen, tier transition fired, fallback path taken.
- Every guard a past bugfix added — if the guard fires in the future, the log line is what points the investigator at the original bug.

*Tag naming — module-scoped, not file-scoped.* `'KnownHosts'`, `'FilePane'`, `'KdfParams'`, `'MigrationRunner'`, `'Session'`, `'SecureClipboard'`. Grep existing `name: '...'` usage before inventing a new tag so one module stays under one tag.

*Free-form user-chosen strings are the sanitizer's blind spot.* Session labels, key labels, tag names, snippet titles, folder names have no regex shape — a sanitizer pattern strict enough to catch them would false-positive everywhere. For those, log the marker `<label>` or `<name>` instead of the value, e.g.:

```dart
// session_connect.dart — keyId IS safe (opaque UUID), label is NOT.
AppLogger.instance.log(
  'Resolved keyId ${session.keyId} → <label>',
  name: 'Session',
);
```

*Never compose a message that embeds a raw secret.* The sanitizer catches PEM blocks and long base64 runs, but a short passphrase / master password falls through. Keep the secret in the code path, not the string:

```dart
// OK — the sanitizer redacts user@host and host:port from russh error text.
AppLogger.instance.log('SSH auth failed: $e', name: 'Connect', error: e);

// NOT OK — `$typedPassword` falls through every sanitizer rule.
AppLogger.instance.log('Login failed with $typedPassword', name: 'Connect');
```

*Never call `print` or `dart:developer` log directly.* `print` survives into release builds and bypasses both the sanitizer and the file sink; `dev.log` bypasses the sanitizer. Both leak the raw message into whatever host is capturing stdout (`adb logcat`, Xcode Console, `flutter run` terminal, CI runner logs).

#### Local Error Handling

Global handler is a safety net. Expected errors should be caught locally with `try/catch`:

```dart
try {
  await FilePicker.pickFiles(...);
} catch (e, stack) {
  AppLogger.instance.log('Failed to pick file: $e', name: 'Tag', error: e, stackTrace: stack);
  // Show user-friendly message or fallback
}
```

This provides:
- Immediate, context-aware error handling
- Graceful fallback (e.g., show "file picker unavailable" instead of crash)
- Clearer log messages with operation context

---

## 14. Testing Patterns & DI Hooks

### Injectable factories

| Class | DI parameter | Purpose |
|-------|------------|---------|
| `SSHConnection` | `socketFactory`, `clientFactory` | Mock TCP/SSH |
| `ConnectionsNotifier` | `connectionFactory` | Mock connection creation |
| `TerminalTab` | `reconnectFactory` | Mock reconnect logic |
| `FileBrowserTab` | `sftpInitFactory` | Mock SFTP initialization |
| `MobileFileBrowser` | `sftpInitFactory` | Mock SFTP initialization (mobile) |
| `ForegroundServiceManager` | `create()` factory | Platform-specific impl |
| `SecurityInitController` | `dbFileExists`, `verifyReadable`, `dialogPrompter`, `migrationRunner` | Bootstrap / unlock / first-launch / corruption / migration paths driven end-to-end in tests without touching real SQLite cipher or blocking on user-driven dialogs — see [Testing the controller](#testing-the-controller) below |
| `app/import_flow.dart` (top-level fns) | `ImportFlowSeams` ‒ `probeArchive` / `openArchive` / `dropHandle` / `applyHandle` / `showLfsDialog` / `showLinkPreviewDialog` | Drives `showLfsImportDialog` / `handleQrImport` / `handleQrImportSource` end-to-end without booting FRB or rendering a real password / preview dialog. Tests swap the bag via `debugSetImportFlowSeams(...)` (clear with `null` in `tearDown`) so they can assert on probe→open→apply→drop ordering and the handle-drop-on-failure invariant |
| `BiometricAuth` (Linux) | `fprintdReachable`, `fprintdHasEnrolled`, `fprintdVerify`, `tpmAvailable` | Function-pointer seams override the four FRB calls into `lfs_core::platform::linux::{fprintd, tpm}` so unit tests drive the availability ladder + verify path + backing-level branch with deterministic answers, no real fprintd daemon and no `/dev/tpmrm0` |

All seams are optional ctor params defaulting to the production function (`lfsCoreDbExists`, `verifyRustDbReadable`, `ProductionSecurityDialogPrompter()`, and `runStartupMigrations` — the FRB-bridged Rust migration runner in `lib/core/migration/migration_runner.dart` driving `lfs_core::migration::registry::build_app_registry`). Prod call sites construct `SecurityInitController` without passing any of them — no behavioural drift from production. The top-level dispatchers in `app/import_flow.dart` follow the same pattern with a process-wide `_seams = ImportFlowSeams.production()` that tests rebind via `debugSetImportFlowSeams`.

### Platform overrides

```dart
debugMobilePlatformOverride = true;    // force mobile layout in tests
debugDesktopPlatformOverride = true;   // force desktop layout in tests
```

### Shared test helpers (`test/helpers/`)

| File | Contents |
|------|----------|
| `test_notifiers.dart` | `TestConfigNotifier`, `PrePopulatedConfigNotifier`, `PrePopulatedSessionNotifier`, `PrePopulatedWorkspaceNotifier`, `PrePopulatedUpdateNotifier`, `FixedVersionNotifier` |
| `fake_session_notifier.dart` | `FakeSessionNotifier` (in-memory), `StaticSessionNotifier`, `ThrowingSessionNotifier` |
| `fake_transfers_notifier.dart` | `FakeTransfersNotifier` — production `TransfersNotifier` subclass that records `clearHistoryCalls`; bypasses the FRB queue |
| `fake_security.dart` | `FakeMasterPasswordManager`, `FakeSecureKeyStorage` (`writeKeySucceeds` flag), `FakeHardwareTierVault` (`storeSucceeds` flag), `FakeKeychainPasswordGate`, `FakeBiometricAuth` (`skipFirstNAvailableCalls` counter), `FakeBiometricKeyVault` (`isStoredThrows` + `throwAfterNCalls`), `FakeAutoLockNotifier` — all subclasses with no-op async defaults; flags let tests drive write-failure / throw / availability-change branches without swapping fakes mid-test |
| `fake_dialog_prompter.dart` | `FakeSecurityDialogPrompter` — scripted answers for `showFirstLaunchWizard`, `showDbCorrupt`, `showTierReset`, `showMasterPasswordUnlock`, `showTierSecretUnlock`; `tierSecretSimulatedInput` delegates to the real `verify` closure so the DB-inject side effect fires; `fireOnReset` + `fireBiometricUnlock` trigger the dialog's reset / biometric callbacks for coverage |
| `fake_path_provider.dart` | `installFakePathProvider()` + `uninstallFakePathProvider(tmp)` — redirects the `path_provider` channel to a per-test tmp dir; returns the `Directory` so tests can pre-seed / inspect state files |
| `fake_security.dart` | `FakeSecureKeyStorage` / `FakeBiometricAuth` / `FakeHardwareTierVault` / `FakeMasterPasswordManager` — subclasses overriding the async surface with deterministic, filesystem-free defaults so unit tests can inject any tier-state shape without bootstrapping FRB or the OS keychain |
| `fake_native_plugins.dart` | `installFakeNativePlugins({config})` / `uninstallFakeNativePlugins()` — one-call mock for every app MethodChannel (session_lock, backup_exclusion, permissions, secure_screen, qrscanner) + file_picker; returns a `NativeCallLog` so tests assert on the exact invocation shape. The hardware-vault and clipboard-secure channels are intentionally absent: every supported OS routes those through FRB into `lfs_os_security`, so there is no Dart-side MethodChannel left to mock |
| `test_providers.dart` | `makeTestProviderContainer({...})` and `securityProviderOverrides({...})` — shared baseline of Riverpod overrides (session / master-password / keychain / hardware-vault / keychain-gate / biometric-auth / biometric-vault / auto-lock stores). Widget tests that need their own `ProviderScope` spread the override list; unit tests call the factory |

### Test file mapping

Rule: **one test file per source file** (`lib/core/ssh/ssh_client.dart` → `test/core/ssh/ssh_client_test.dart`). No `_extra_test.dart` files.

### Mocking discipline

No `mockito` / `mocktail` in the suite. Test doubles are hand-rolled subclasses (see `test/helpers/fake_*.dart`) so the public production API is the only contract under test — a `mockWhen(...).thenReturn(...)` graph would lock tests to private call shapes and silently rot when the production code changes signature. Pure logic ships as ordinary subclass overrides; side-effect surfaces (Rust archive boundary, native plugins, file_picker) ship as wrapper classes / function-pointer bags swapped through a Riverpod override or a `@visibleForTesting` setter.

### Testing the controller

`SecurityInitController` orchestrates migrations → security init → DB open → readability probe across every tier (plaintext / keychain / keychain+password / hardware / paranoid). Unit tests drive the full chain under `tester.runAsync` through the four DI seams above:

- `dbFileExists` — script "existing install" vs "first launch" without touching the fake tmp dir; defaults to `lfsCoreDbExists`.
- `verifyReadable` — flip integrity-probe results per call, letting tests drive corruption → retry → wipe paths deterministically; defaults to `verifyRustDbReadable`.
- `dialogPrompter` — return canned `SecuritySetupResult` / `DbCorruptChoice` / `TierResetChoice` / tier-secret keys without rendering real dialogs, which would block on user interaction; defaults to `ProductionSecurityDialogPrompter()`.
- `migrationRunner` — throw, return a `MigrationReport` with fatal errors, or return one with `migratedCount > 0` — covers every branch of `_runMigrations` + `_handleMigrationFailure`; defaults to `runStartupMigrations` over the Rust registry.

DB open + close go through `ensureRustDbOpen` / `dbClose` directly — these calls run inside the security flow rather than as injectable seams. Tests reach the unlock branches by pre-seeding `letsflutssh.db` in the fake tmp dir and asserting on the controller's flag transitions, not by swapping the open routine.

Two paths remain out of reach at this layer and are deferred to higher-level harnesses:

- `exit(0)` branches inside `DbCorruptChoice.exitApp` / `TierResetChoice.exitApp` — would terminate the test isolate. A spawned-process integration test could cover them.
- macOS self-sign (`_offerMacosSelfSign`) — gated on `Platform.isMacOS`. Runs on a macOS CI lane only.

`tester.runAsync` is required around `bootstrap()` / `reinitFromReset()` / `reopenAfterUnlock()` — `configProvider.update` awaits a 300 ms debounce `Timer` that FakeAsync (the default under `testWidgets`) never advances.

### End-to-end SSH/SFTP/port-forward integration tests (`test/integration/`)

`flutter test test/integration/` drives the **real Rust connect actor → russh client → russh server → Rust dispatcher → bridge** stack against an **in-process russh-server fixture** at `lfs_core::connection::test_server`. The fixture binds 127.0.0.1:0, generates a fresh Ed25519 host key per `start()`, accepts a hard-coded test password, and implements the SSH subsystem surface the tests exercise: `auth_password` / `auth_publickey`, `channel_open_session` + `subsystem_request("sftp")` (russh-sftp filesystem-backed handler rooted at a tempdir), `channel_open_direct_tcpip` (loopback only — for `-L` / ProxyJump / `-D`), `tcpip_forward` + `cancel_tcpip_forward` (for `-R`), `pty_request` + `shell_request` (idle channels for openShell consumers).

The fixture exists because the four race-window bugs that landed on `feat/rust-core` (post-handshake event drop, per-attempt sub cancellation, transport-vs-state ordering, "Fail to post message to Dart" stderr noise) live at the **bus delivery boundary** between the Rust connect actor and the Dart-side observation pipeline. Static audits missed every one of them; only a real handshake against a real listener exercises that window deterministically. Fake event emitters reproduce the *shape* of bus traffic but not the *timing*.

| File | Coverage |
|---|---|
| `connection_lifecycle_test.dart` | progressHistory phases, transport-vs-state ordering, exactly-once `connected` transition, auth-fail, reconnect generation guard |
| `sftp_lifecycle_test.dart` | list / mkdir / upload / download / rename / remove / removeDir / error-path / `..`-traversal |
| `known_hosts_prompt_test.dart` | TOFU prompt fires on Unknown / accept proceeds / reject fails HostKeyVerify / KeyChanged dialog |
| `bastion_proxyjump_test.dart` | bastion-routed connect, both reach Connected + target.bastion is wired, cascade-disconnect tears bastion down |
| `transfer_queue_test.dart` | single upload/download, batch-of-three uploads, **cancel mid-flight settles in `cancelled`** (uses `test_ssh_server_set_sftp_write_delay_ms` to widen the cancel race window) |
| `port_forward_test.dart` | `-L` round-trip + teardown, `-R` round-trip + teardown, `-D` SOCKS5 CONNECT round-trip |

`make test` builds `rust/target/release/liblfs_frb.so` first via the `rust-build` Make target — the integration tests load FRB through `requireFrbLoaded()` and throw if the .so is missing.

### Mutation testing (`cargo-mutants`)

`make rust-mutants SCOPE=<dir>` (e.g. `SCOPE=archive`) drives [`cargo-mutants`](https://mutants.rs) over a curated module under `rust/crates/lfs_core/src/<dir>/`. The wrapper at `dev/scripts/run-mutants.sh` enumerates every `*.rs` basename in the chosen scope, feeds each as a `--file` flag, and prints the per-file caught/missed roll-up after the run.

| Outcome | Meaning |
|---|---|
| **CaughtMutant** | The mutated code failed at least one test. Test suite catches the regression. |
| **MissedMutant** | The mutated code passed every test. The test suite **does not** verify the behaviour at that span. |
| **Unviable** | The mutation does not compile (skipped). |
| **Timeout** | The mutated code hangs the test (counted as caught). |
| **Mutation score** | `caught / (caught + missed)` — fraction of behaviour-touching mutations the suite would catch. |

A mutation score of 100% means every algebraic / boolean / return-value mutation produces a test failure. Real-world good is ≈ 80–90%; below 50% means the tests verify "the function ran" rather than "the function returned the right thing".

**WSL caveat.** cargo-mutants creates per-job scratch copies of `target/` (3-4 GiB each) under `$TMPDIR`. WSL2 mounts `/tmp` as **tmpfs (RAM)** capped at ~16 GiB by default, so 4 jobs OOM the box; the wrapper pins `TMPDIR=$REPO/.cache/cargo-mutants/scratch` (disk-backed) and defaults to 2 jobs. Override with `MUTANTS_JOBS=N`, `MUTANTS_TMPDIR=...`, `MUTANTS_TIMEOUT_MUL=...`.

**Scopes.** Pass `SCOPE=<directory under lfs_core/src/>`. Examples: `archive`, `security`, `ssh`, `crypto`, `db`. cargo-mutants matches files by basename, so this works as long as `lfs_core` carries one file per name across these dirs (today it does).

**Outputs.** `.cache/cargo-mutants/<scope>/mutants.out/` — already in `.gitignore`. Inspect `missed.txt` for the actionable list (each line is `path:line:col: <kind>: <replacement> in <fn>`); use it to write tests that would fail under that exact mutation.

**When to run.** Not every commit. Mutation runs are minutes-long; trigger them when raising the testing bar on a sub-module, when reviewing a `0%` test file, or when a refactor reshapes a critical path (archive composer / crypto envelope / authn handshake).

**Synthetic-Connection helper.** `Connection.debugMarkTransportAdopted()` (gated by `@visibleForTesting`) completes the underlying `_transportAdopted` Completer the same way the bus listener would after `_adoptSession`. Widget tests that build `Connection(state: SSHConnectionState.connected)` directly (no actor, no bus events) call it once at construction so `await conn.transportReady` resolves immediately — without it the SFTP-mixin / file-browser tests' `pumpAndSettle` hangs on the never-completed completer.

### Fuzz testing

Two layers of fuzz testing — **property-based** (random inputs on every PR, no coverage feedback) and **coverage-guided** (libFuzzer mutation on a seed corpus, nightly-style runs).

**Dart property-based tests** (`test/fuzz/`): run as part of `make test` on every PR. Each test generates N random / adversarial inputs (N ≈ 1000, seeded from `Random.secure()`) and asserts the decoder returns a typed failure or a valid value — never an unhandled exception. Pure-Dart tests with full Flutter / pub access.

| Test file | Fuzzed function | Input type |
|-----------|----------------|------------|
| `fuzz_session_json_test.dart` | `Session.fromJson()` | Random JSON maps |
| `fuzz_app_config_test.dart` | `AppConfig.fromJson()` + sub-configs | Random JSON maps |
| `fuzz_deeplink_test.dart` | `DeepLinkHandler.parseConnectUri()` | Random URIs |
| `fuzz_format_test.dart` | `sanitizeError()`, `formatSize()`, `formatDuration()` | Random strings, errno patterns, objects |
| `fuzz_openssh_config_parser_test.dart` | `parseOpenSshConfig()` | Random `~/.ssh/config` snippets (wildcards, `Include`, malformed directives) |
| `parsers_fuzz_test.dart` | Shared `basic` / integer / bool parsers | Random strings + typed overflows |
| `sanitize_fuzz_test.dart` | `sanitizeErrorMessage()` | Random strings (path redaction, IP redaction) |

**Standalone Dart harnesses** (`fuzz/`): compiled to native via `dart compile exe` (`make fuzz-build`). Read **raw bytes** from stdin (binary targets use `stdin.readByteSync` — `readLineSync` would UTF-8-decode and die on any non-ASCII byte), exercise parsing logic, and are wrapped by a thin C libFuzzer harness from `.clusterfuzzlite/build.sh` that pipes libFuzzer input to the Dart binary's stdin. Coverage-guided mutation via libFuzzer, but the parsing logic runs in Dart.

| Harness | Fuzzed logic | Notes |
|---------|-------------|-------|
| `fuzz_json_parser` | `Session.fromJson()` / `AppConfig.fromJson()` / QR payload decoder | Text input, seeded with valid JSONs per target |
| `fuzz_known_hosts` | `~/.ssh/known_hosts` parser | Text lines, seeded with one RSA + one Ed25519 entry + a comment |
| `fuzz_uri_parser` | `letsflutssh://` deep-link URIs (`connect` + `import`) | Text, seeded with valid connect + import payload |
| `fuzz_kdf_params` | `KdfParams.decode` — 10-byte algorithm / memory / iterations / parallelism blob | Binary, seeded with production defaults (Argon2id, 64 MiB, 3 iter, 1 lane) |
| `fuzz_lfs_archive_header` | LFS archive header — magic + version + KDF blob + salt + IV — parsed up to but NOT including the Argon2id run (user-supplied `memoryKiB` would OOM the fuzz worker) | Binary, seeded with one well-formed Argon2id header + 32-byte salt + 12-byte IV |

Standalone harnesses mirror production logic inline (no Flutter / pub imports) so the compiled binary stays small and libFuzzer coverage attribution is clean. Drift between the mirror and production is caught by test-table tests that exercise both paths against the same vectors.

**Rust libFuzzer harnesses** (`rust/fuzz/`): coverage-guided harnesses for the four untrusted-bytes parsers that landed Rust-side in the migration (post-port the Dart harnesses can't reach them — `lfs_core` is consumed via FRB, not import). Member of the parent `rust/` workspace but excluded from `default-members` so `cargo build --workspace` ignores them; activated by `cargo +nightly fuzz run <target>` from `rust/fuzz/`. Targets:

| Target | Driver |
|---|---|
| `deeplink` | `lfs_core::deeplink::parse_connect_uri` — `letsflutssh://connect?...` URI grammar |
| `known_hosts` | `lfs_core::known_hosts_parser::parse_line` — OpenSSH wire format + LFS internal export |
| `qr_codec` | `lfs_core::qr_codec_decode::decode_payload` — base64url + deflate + JSON-shape payload |
| `openssh_config` | `lfs_core::ssh_config::parse_openssh_config` — OpenSSH `~/.ssh/config` grammar |

Each `fuzz_target!(|data: &[u8]|)` shim drives bytes from libFuzzer through the parser and asserts no panic + parser-output invariants where applicable (idempotency, contract-bound field shapes). Crashes persist under `rust/fuzz/artifacts/<target>/` (gitignored — corpora live in OSS-Fuzz / ClusterFuzzLite, not the repo). Not run in CI today; the host pipeline (`make rust-test`, `cargo clippy`) ignores these targets entirely.

**CI integration**: `.github/workflows/cfl-fuzz.yml` runs ClusterFuzzLite on push to main and PRs to main, 300 seconds per target. Detected by OpenSSF Scorecard's Fuzzing check. Nightly extended runs are not configured — PR-run coverage over time accumulates broadly enough that a separate nightly workflow would duplicate CFL without meaningfully widening coverage. Any new untrusted-input path in `lib/` adds a matching fuzz target in the same commit (see [§14 Fuzz testing](#fuzz-testing)).

---

## 15. CI/CD Pipeline

### 15.1 Branching Model

Two branches: **`dev`** (daily work) and **`main`** (releases only).

- All app development happens on `dev`. Push freely — CI and security scans run on PRs (not on every push). No tags, no builds, no releases.
- To release: merge `dev` → `main`. Everything is automatic: CI → auto-tag → build → release.
- Never push app changes directly to `main`. Dependabot PRs and CI/docs-only fixes are exceptions.
- **Contributors** work via forks → PR into `dev`. CI runs on PRs automatically. Maintainer reviews and merges.

**Branch Protection (GitHub Rulesets):**

| Ruleset | Branch | Rules | Bypass |
|---------|--------|-------|--------|
| `main` | `main` | No deletion, no force-push, PR required, all CI checks required | None |
| `dev-protect` | `dev` | No deletion, no force-push | None |
| `dev-checks` | `dev` | All CI checks required (`ci`, `osv-scan`, `semgrep-scan`, `codeql-scan`) | Admin — allows direct push |

### 15.2 Workflow Graph

```mermaid
flowchart TD
    p["push to dev/main or PR"]
    p --> ci["ci.yml<br/>always runs — no path filters<br/>analyze + test + coverage"]
    ci --> sonar["ci-sonarcloud.yml<br/>workflow_run[CI], non-fork only<br/>quality + coverage scan"]
    ci --> tag["ci-auto-tag.yml<br/>workflow_run[CI], main only<br/>reads version from pubspec.yaml<br/>tag exists → skip / new version → create tag"]
    tag --> rel["build-release.yml (tags: v*)<br/>build all platforms<br/>GitHub Release + SLSA attestation"]
    p --> fuzz["cfl-fuzz.yml<br/>push main / PR to main"]
    p --> sec["osv.yml / codeql.yml / semgrep.yml<br/>main push + PR + weekly"]
    p --> sco["scorecard.yml<br/>main push + weekly"]

    dep["Dependabot PR (into main)"]
    dep --> da["dependabot-auto.yml<br/>bump version in PR branch → auto-merge<br/>→ ci.yml → ci-auto-tag.yml → build-release.yml → Release"]

    bump["Version bump (on dev, before PR)"]
    bump --> bs["dev/scripts/bump-version.sh<br/>parse commits → bump pubspec.yaml → commit"]

    man["Manual build"]
    man --> mb["gh workflow run build-release.yml<br/>CI not passed? → fail immediately (no polling)"]
```

### 15.3 Workflow Catalog

| Workflow | Trigger | Branches | Purpose | Blocks release? |
|----------|---------|----------|---------|-----------------|
| `ci.yml` | push main / PR (main, dev) | main, dev | Single `ci` job runs `make check` (format-check + lint + workflow lint + release hardening + unused-deps + tests for Dart + Rust) and `make rust-coverage` (lcov for SonarCloud); plus `rust-cross-check` matrix (Apple, Windows, Android cfg compile) | Yes (required) |
| `ci-auto-tag.yml` | workflow_run[CI] success | main only | Reads version, creates tag if new | — |
| `build-release.yml` | push tag v* / manual | — | Build all platforms + release + SBOM + cosign keyless signature | — |
| `ci-sonarcloud.yml` | workflow_run[CI] / manual | main, dev | Quality + coverage scan | No (warn-only) |
| `dependabot-auto.yml` | PR (any branch) — gates on `dependabot[bot]` actor | main | Bump version in PR branch + auto-merge patch/minor | — |
| `osv.yml` | push main / PR (all) / weekly | main | CVE scan (pubspec.lock) | Yes on PR |
| `codeql.yml` | push main / PR (all) / weekly | main | GitHub Actions analysis | Yes on PR |
| `semgrep.yml` | push main / PR (all) / weekly | main | SAST scan (Dart code) | Yes on PR |
| `cfl-fuzz.yml` | push main / PR to main | main | ClusterFuzzLite | No |
| `scorecard.yml` | push main / weekly | main | OpenSSF supply chain assessment | No |
| `reproducibility-check.yml` | nightly cron | main | Builds Linux artefacts twice on the same SHA + diffs sha256 to verify the `SOURCE_DATE_EPOCH`-pinned reproducibility claim | No |
| `pages.yml` | push main / manual | main | Publishes the project landing site to GitHub Pages | No |

**External Integrations:**

| Service | Config | Purpose |
|---------|--------|---------|
| GitGuardian | `.gitguardian.yml` | Secret detection on PRs. Test files (`test/**`) and localization files (`lib/l10n/**`) are excluded — they contain fake credentials and translated "password" labels that trigger false positives |

### Composite actions (`.github/actions/`)

| Action | Purpose |
|--------|---------|
| `setup-rust` | Activates the toolchain pinned in `rust/rust-toolchain.toml` (`cargo --version` from inside `rust/` triggers rustup auto-install of the pinned channel — currently `1.95.0`), installs any cross-compile targets passed via the `targets:` input, then primes `Swatinem/rust-cache@v2.7.8` (SHA-pinned) keyed on Cargo.lock hash + active rustc version + workspace root. Used by all 7 Rust-building jobs in `build-release.yml`; bumping the cache action SHA, the rustup invocation, or the cache scope is one edit, not seven. The composite's `save-if: 'true'` override sends cache writes from feature branches too — without it, `Swatinem/rust-cache`'s default `save-if` only writes from the repo's default branch and feature-branch pushes would have nothing to restore from. |

### Release matrix shape

The release matrix builds across 7 platform-arch tuples. The Flutter SDK install path differs by tuple:

| Tuple | Flutter SDK install | Rationale |
|---|---|---|
| linux-x64, windows-x64, macos-universal, android, ios-unsigned | `subosito/flutter-action@v2` with `flutter-version: 3.41.9` | Flutter Foundation publishes precompiled tarballs for these (host) platforms; the action's resolver finds them in `releases_<os>.json`. |
| linux-arm64, windows-arm64 | `git clone --depth 1 + git checkout <pinned-SHA>` of `flutter/flutter` followed by `flutter precache` | Flutter Foundation publishes **zero** ARM64 desktop tarballs (verified against `releases_linux.json` / `releases_windows.json` across stable / beta / dev). The git-clone path is the official documented install on ARM64 hardware (https://docs.flutter.dev/get-started/install/linux). The `FLUTTER_SHA` is pinned by full commit hash inside the workflow — tags are mutable, commit SHAs are not. Cached separately keyed `flutter-arm64-${runner.os}-${SHA}`. |

The `lfs_frb` Rust core uses **`ring`** as russh's crypto backend (overriding russh's default `aws-lc-rs`) — `aws-lc-sys` ships ~200k LOC of vendored AWS-LC C that fails MSVC's `stdalign_check.c` probe on Windows ARM64 *and* added 8-15 minutes of compile wall-clock per release matrix job. `ring` has prebuilt assembly for ARM/ARM64 and produces functionally equivalent SSH crypto.

The iOS unsigned-build job runs a **pre-flight `cargo build --target aarch64-apple-ios`** step before `flutter build ios --no-codesign`. xcodebuild swallows rustc diagnostics — collapses any iOS-cfg compile regression to a single `Error (Xcode): could not compile X (lib) due to N previous errors` line without the `error[Exxxx]` body — so we run cargo directly first to surface the full diagnostic in plain GHA log. The pre-flight runs with `working-directory: rust` so rustup picks up `rust-toolchain.toml` (without it, cargo from repo root resolves to the runner's default-stable toolchain which lacks the iOS targets the composite installed) and `IPHONEOS_DEPLOYMENT_TARGET: '13.0'` so vendored OpenSSL's references to `__chkstk_darwin` (added in iOS 13) resolve at link time.

### 15.4 Makefile Targets

Top-level umbrellas (`test`, `lint`, `format`, `format-check`) run both languages in sequence. Per-language entry points (`dart-*`, `rust-*`) exist for fast iteration when only one side is in scope.

#### Umbrella + per-language

| Action | Umbrella | Dart-only | Rust-only |
|---|---|---|---|
| Run tests | `make test` | `make dart-test` | `make rust-test` |
| Static analysis | `make lint` | `make dart-lint` | `make rust-lint` |
| Auto-format | `make format` | `make dart-format` | `make rust-format` |
| Format verification | `make format-check` | `make dart-format-check` | `make rust-format-check` |

#### Development

| Target | Command | Purpose |
|--------|---------|---------|
| `make run` | `flutter run` | Run (debug) |
| `make run-release` | `flutter run --release` | Run (release) |
| `make check` | `format-check + lint + lint-workflows + lint-release-hardening + rust-machete; @make test` | Full pre-commit gate (Dart + Rust). Same command CI runs |
| `make gen` | `build_runner build` | Code generation (FRB freezed siblings + l10n) |
| `make deps` | `flutter pub get` | Install Flutter / Dart dependencies |
| `make setup` | `deps + hooks + setup-rust-tools` | One-shot post-clone bootstrap |
| `make setup-rust-tools` | Install `cargo-machete`, `cargo-llvm-cov` (pinned versions) | Cargo plugins used by `make check` and `make rust-coverage` |
| `make fuzz-build` | `dart compile exe fuzz/*.dart` | Compile native fuzz targets |

#### Rust core (`rust/`)

| Target | Command | Purpose |
|--------|---------|---------|
| `make rust-build` | `cargo build --release --workspace --locked` | Build the FRB native blob + workspace |
| `make rust-test` | `cargo test --workspace --locked` + `--doc --locked` | Unit + integration + doc tests; `--locked` enforces Cargo.lock parity |
| `make rust-format` | `cargo fmt --all` | Format Rust sources |
| `make rust-format-check` | `cargo fmt --all -- --check` | Format verification (used by `make check`) |
| `make rust-lint` | Umbrella: `rust-lint-host` + `rust-lint-android` + `rust-lint-windows-gnu` (+ `rust-lint-ios` + `rust-lint-macos-arm` on macOS hosts) | Host + every cross-target whose stdlib ships with rustup; catches cfg-gated regressions before push |
| `make rust-lint-host` | `cargo clippy --workspace --all-targets --locked -- -D warnings` | Host-target-only clippy for fast iteration when only host-target code changed |
| `make rust-lint-android` | `cargo clippy -p lfs_os_security --target aarch64-linux-android --all-targets --locked -- -D warnings` | Cross-target clippy for Android (every host) |
| `make rust-lint-windows-gnu` | `cargo clippy -p lfs_os_security --target x86_64-pc-windows-gnu --all-targets --locked -- -D warnings` | Cross-target clippy for Windows (every host; rustup mingw stdlib) |
| `make rust-lint-ios` | `cargo clippy -p lfs_os_security --target aarch64-apple-ios --all-targets --locked -- -D warnings` | Cross-target clippy for iOS; requires a macOS host (no Linux-hosted Apple stdlib) |
| `make rust-lint-macos-arm` | `cargo clippy -p lfs_os_security --target aarch64-apple-darwin --all-targets --locked -- -D warnings` | Cross-target clippy for Apple Silicon Mac; requires a macOS host |
| `make rust-machete` | `cargo machete --with-metadata` | Detect unused dependencies (used by `make check`) |
| `make rust-coverage` | `cargo llvm-cov --workspace --all-features --locked --lcov` | Generate `rust-lcov.info` for SonarCloud |
| `make rust-codegen` | `flutter_rust_bridge_codegen generate` | Regenerate Dart bindings under `lib/src/rust/` (run after editing `rust/crates/lfs_frb/src/api/*.rs`) |
| `make rust-clean` | `cargo clean` | Remove `rust/target/` |

#### Build

| Target | Platform |
|--------|----------|
| `make build-linux` | Linux x64 (or host arch on ARM64 Linux) |
| `make build-macos` | macOS universal (x86_64 + arm64 lipo'd) |
| `make build-apk` | Android per-ABI (`arm64`, `arm32`, `x64`) |
| `make build-aab` | Android App Bundle |
| `make build-ios` | iOS (unsigned `.ipa` shipped via CI; locally `--no-codesign`) |

#### Packaging

| Target | Format |
|--------|--------|
| `make package-linux` | tar.gz |
| `make package-appimage` | AppImage |
| `make package-deb` | .deb |
| `make package-windows` | .zip |
| `make package-exe` | Inno Setup EXE |

---

## 16. Design Decisions & Rationale

### 16.1 Architecture Choices

| Decision | Why |
|----------|-----|
| **Self-contained binary, zero manual setup** for end-user | App must run from a single extracted bundle. External OS deps allowed only if (1) graceful degradation with in-UI message and (2) install documented in README per platform. Preference order: bundle > built-in fallback > documented optional install. See [§1 Self-contained-binary principle](#self-contained-binary-principle) |
| **Shared modules over local one-offs** at every layer | Single source of truth for visual, behavioural, and persistence patterns; second caller triggers extraction, third makes it mandatory. Produced `AppDialog`/`AppIconButton`/`AppDataRow`/`StyledFormField` (UI), `AppTheme.radius*`/`AppFonts.*`/`*ColWidth` (theme), `SftpBrowserMixin`/`key_file_helper.dart`/`breadcrumb_path.dart` (logic), `Store → DAO` template (persistence). See [§1 Reuse principle](#reuse-principle) |
| Single SQLite DB instead of JSON files | Referential integrity, folder tree with FK, M2M tags/snippets, single encrypted DB file. Schema + DAOs live Rust-side under `lfs_core::db`; Dart reads / writes through FRB. |
| SQLCipher 4.x via `rusqlite` `bundled-sqlcipher-vendored-openssl` | DB-level encryption replaces per-store AES-GCM. Single Cargo feature flag, both SQLCipher and OpenSSL vendored — no submodule, no native build hook, no system OpenSSL prereq on cross-compile targets. AES-256-CBC + HMAC-SHA512 per-page MAC. See [§3.6 Cipher choice](#cipher-choice--sqlcipher-4x-aes-256-cbc--hmac-sha512) for the picked-over-MC rationale and [§11 Encryption engine build path](#encryption-engine-build-path) for the build model + the `vendored-openssl` decision. |
| Config stays file-based | Theme/locale needed before DB opens (chicken-and-egg with encryption key) |
| Three-level security (plaintext/keychain/master password) | Honest security: DB-level encryption via PRAGMA key. OS keychain optional with graceful fallback |
| Accept per-platform asymmetry, don't escalate working baselines | Cross-platform packages with documented per-platform limits are the chosen budget across all domains (storage, file pickers, notifications, biometrics, IPC, hardware probes). Per-platform native rewrites are out of scope unless explicitly requested — N× code paths rarely worth a marginal upgrade. |
| OS keychain via `lfs_os_security::secure_key_storage` (libsecret / SecItem / CredMan / AndroidKeyStore JNI) instead of a Flutter plugin | Single Rust dispatch layer per platform — no `flutter_secure_storage` plugin in the call chain; one audit perimeter instead of one per platform. Linux libsecret is still an OS dep (graceful "keyring unavailable" fallback). |
| `app_links` instead of `uni_links` | Desktop support |
| Widget-local controllers (`FilePaneController`, `UnifiedExportController`, `SessionPanelController`, `TransferPanelController`) use `ChangeNotifier` | Match tool to scope: app-state lives in Riverpod `NotifierProvider`, dialog / pane / panel state that takes constructor args or owns caches uses `ChangeNotifier + AnimatedBuilder` — side-channel Riverpod overrides would be pure ceremony |
| Sealed class `SplitNode` | Recursive split tree with type safety |
| Each terminal pane → own SSH shell | Shared `SSHConnection`, independent shells |
| `Listener` for marquee | Raw pointer events don't conflict with `Draggable` |
| `IndexedStack` for tabs | Preserves terminal state when switching tabs |
| `GlobalKey` for tab widgets | Preserves widget state when tab is dragged to a new panel |
| Separate `features/mobile/` | Different interaction patterns, not a responsive adaptation |
| Global `navigatorKey` for host key dialog | SSH callback arrives without BuildContext |
| `AnimationStyle.noAnimation` | Animations disabled (Flutter 3.41+), design decision |
| `AppShortcutRegistry` singleton | Centralized shortcut definitions; all key combos in one place, ready for future user-override settings page |
| `matches()` checks only ctrl/shift | Original handlers didn't check alt/meta; WSLg can report phantom meta, causing false negatives |

### 16.2 API Gotchas

| Problem | Solution |
|---------|----------|
| `ConnectionState` conflict with Flutter async.dart | Use `SSHConnectionState` |
| russh-sftp file mode lookup | `metadata.permissions` (`russh-sftp` shape), not POSIX `mode_t` |
| russh `check_server_key` callback runs on the IO thread | Bus-event prompt protocol with a `tokio::oneshot` resolution; never block the callback on Dart |
| FRB `#[frb(sync)]` reserved for sub-microsecond reads | Anything touching the filesystem or cipher stays async + `spawn_blocking` |
| xterm TextInputClient broken on Windows | `hardwareKeyboardOnly: true` on desktop |

### 16.3 Security Decisions

| Decision | Rationale |
|----------|-----------|
| Argon2id m=64 MiB t=3 p=1 | Deliberately one tier above the OWASP 2024 floor (46 MiB / 2 / 1) — desktop/mobile UX absorbs the extra ~60% derive cost for stronger brute-force resistance. Canonical in `lfs_core::security::master_password::KdfParams::defaults`; mirrored Dart-side via the sync FRB getter `kdfParamsProductionDefaults` so Rust is the single source of truth |
| v1 floor across every persisted artefact | Anything below the current schema is treated as corrupt and routed through `DbCorruptDialog` + `WipeAllService`. Keeps the attack surface to a single KDF and a single wire format at runtime |
| chmod 600 | Minimal permissions on sensitive files |
| TOFU reject without callback | Fail-safe: if no UI → reject |
| `CredentialStoreException` with two types | Distinguish "no credentials" from "corrupt key" |
| SessionNotifier abort on credential load failure | Prevents overwriting encrypted store |
| SessionNotifier concurrent load guard | Prevents race condition when multiple lifecycle events fire simultaneously |
| `RandomAccessFile` + try/finally for upload | Guarantees file handle cleanup |
| Error sanitization | Don't expose file paths to user |
| Deep link path traversal rejection | URL handling security |

### 16.4 Platform Decisions

| Decision | Platform | Rationale |
|----------|----------|-----------|
| `EXTERNAL_STORAGE` env + fallback | Android | Not all devices set the env var |
| `MANAGE_EXTERNAL_STORAGE` permission | Android | Access files outside sandbox |
| `NSLocalNetworkUsageDescription` | iOS | Required for local TCP (SSH connections) |
| Foreground service | Android | Prevents SSH kill on screen lock |
| Per-ABI APK split | Android | Reduces APK size |
| Universal binary | macOS | Intel + Apple Silicon in one binary |

---

## 17. Dependencies

> **Versions are NOT listed here** — `pubspec.yaml` is the single source of truth.
> Run `flutter pub deps` to see the resolved dependency tree.

### Runtime

| Package | Purpose |
|---------|---------|
| `flutter_localizations` | Flutter i18n delegates (SDK package) |
| `intl` | ICU message formatting for l10n |
| `lfs_frb` (path dep on `rust_builder/`) | Loads the Rust core native blob; see [§3.14](#314-rust-securitytransport-core-rust) for the workspace it's built from. |
| `flutter_rust_bridge` | FFI bridge to the Rust core. Pin must match the codegen CLI version exactly (`cargo install flutter_rust_bridge_codegen --version 2.12.0`) — drift produces incompatible bindings. |
| `freezed_annotation` | Annotations the generated `*.freezed.dart` files (FRB-side enums) import; runtime dep because the generated code ships in release. |
| `xterm` | Terminal emulator widget |
| `flutter_riverpod` | State management |
| `crypto` | SHA-256 only (keychain fingerprints, known_hosts, update-feed checksum). AES-GCM / HKDF / Ed25519 / Argon2id all live Rust-side under `lfs_core::crypto`. |
| `path_provider` | App data directories |
| `archive` | ZIP for .lfs export/import |
| `desktop_drop` | OS drag & drop |
| `flutter_foreground_task` | Android foreground service |
| `app_links` | Deep links + file intents |
| `qr_flutter` | QR code generation |
| `file_picker` | File selection |
| `package_info_plus` | App version at runtime |
| `url_launcher` | Open URLs |
| `uuid` | UUID generation |
| `path` | Cross-platform path utils |
| `ffi` | `calloc` / `free` for `mlock`-pinned secret buffers (`lib/core/security/secret_buffer.dart`). |
| `meta` | `@visibleForTesting` / `@protected` annotations without dragging in `package:flutter/foundation` (would break `core/`-no-Flutter layering). |

### Dev

| Package | Purpose |
|---------|---------|
| `flutter_test` | Flutter test framework (SDK package) |
| `integration_test` | Flutter integration test runner (SDK package) |
| `flutter_lints` | Lint rules |
| `build_runner` | Drives `freezed` codegen for FRB-generated sealed classes. |
| `freezed` | Sealed-class codegen for FRB enum bindings (run via `make rust-codegen` followed by `make gen`). |
| `plugin_platform_interface` | Platform interface for plugin packages |
| `flutter_launcher_icons` | App icon gen |

**Test mocks are hand-rolled** (`test/helpers/fake_*.dart`) — no `mockito` / `mocktail` (see [§14 Mocking discipline](#mocking-discipline)).

### Bundled Fonts

| Font | Purpose | Location |
|------|---------|----------|
| Inter | UI text | `assets/fonts/` |
| JetBrains Mono | Terminal, monospaced data | `assets/fonts/` |

### SDK Constraints

- **Flutter** ≥ 3.41.0 (stable channel)
- **Dart** ≥ 3.11.3 (ships with Flutter ≥ 3.41.0)

See `pubspec.yaml` → `environment` section for the canonical constraint. Run `flutter --version` to check.

### Lint Rules

Base: `flutter_lints/flutter.yaml` + custom:
- `prefer_const_constructors`, `prefer_const_declarations`
- `prefer_final_locals`, `prefer_single_quotes`
- `sort_child_properties_last`, `use_key_in_widget_constructors`
- `avoid_print`, `prefer_relative_imports`
- Excludes: `*.g.dart`, `*.freezed.dart`
