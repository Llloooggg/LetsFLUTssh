# Claude Rules — Reference Tables

Reference material for Claude. Read the specific section you need, not the whole file.

## Quick Navigation by Task

| I need to... | Read this section |
|---|---|
| Understand the module layout | [§2 Module Map](ARCHITECTURE.md#2-module-map) |
| Work with SSH connections | [§3.1 SSH](ARCHITECTURE.md#31-ssh-coressh) + [§9.1 SSH Flow](ARCHITECTURE.md#91-ssh-connection-flow) |
| Work with SFTP / file browser | [§3.2 SFTP](ARCHITECTURE.md#32-sftp-coresftp) + [§5.2 File Browser](ARCHITECTURE.md#52-file-browser-featuresfile_browser) |
| Work with transfers | [§3.3 Transfer Queue](ARCHITECTURE.md#33-transfer-queue-coretransfer) + [§9.4 Transfer Flow](ARCHITECTURE.md#94-file-transfer-flow) |
| Work with sessions | [§3.4 Sessions](ARCHITECTURE.md#34-session-management-coresession) + [§9.3 CRUD Flow](ARCHITECTURE.md#93-session-crud-flow) |
| Work with connections | [§3.5 Connection Lifecycle](ARCHITECTURE.md#35-connection-lifecycle-coreconnection) |
| Work with encryption/security | [§3.6 Security](ARCHITECTURE.md#36-security--encryption-coresecurity) + [§13 Security Model](ARCHITECTURE.md#13-security-model) |
| Work with config | [§3.7 Configuration](ARCHITECTURE.md#37-configuration-coreconfig) |
| Add/change keyboard shortcuts | [§3.11 Keyboard Shortcuts](ARCHITECTURE.md#311-keyboard-shortcuts-coreshortcut_registrydart) |
| Work with terminal / tiling | [§5.1 Terminal](ARCHITECTURE.md#51-terminal-with-tiling-featuresterminal) |
| Work with tabs / workspace tiling | [§5.4 Tab & Workspace System](ARCHITECTURE.md#54-tab--workspace-system) |
| Work with mobile features | [§5.6 Mobile](ARCHITECTURE.md#56-mobile-featuresmobile) + [§12 Platform-Specific](ARCHITECTURE.md#12-platform-specific-behavior) |
| Use or create widgets | [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference) |
| Use utilities | [§7 Utilities API](ARCHITECTURE.md#7-utilities--public-api-reference) |
| Work with theme / colors | [§8 Theme System](ARCHITECTURE.md#8-theme-system) |
| Add/change user-facing strings | [§8.1 i18n](ARCHITECTURE.md#81-internationalization-i18n) |
| Understand Riverpod providers | [§4 State Management](ARCHITECTURE.md#4-state-management--riverpod) |
| Understand data persistence / drift DB | [§11 Persistence](ARCHITECTURE.md#11-persistence--storage) |
| Work with database / DAOs | [§2 Module Map](ARCHITECTURE.md#2-module-map) (`core/db/`) + [§11 Persistence](ARCHITECTURE.md#11-persistence--storage) |
| Work with snippets | `core/snippets/` + `features/snippets/` + `providers/snippet_provider.dart` |
| Work with tags | `core/tags/` + `features/tags/` + `providers/tag_provider.dart` |
| Check data models | [§10 Data Models](ARCHITECTURE.md#10-data-models) |
| Understand CI/CD / workflows | [§15 CI/CD Pipeline](ARCHITECTURE.md#15-cicd-pipeline) |
| Check design decisions / gotchas | [§16 Design Decisions](ARCHITECTURE.md#16-design-decisions--rationale) |
| Check dependencies / versions | [§17 Dependencies](ARCHITECTURE.md#17-dependencies) |
| Write tests / understand DI | [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks) |

## Documentation Maintenance Checklist

**Every code change MUST be accompanied by documentation updates.** Violation = incomplete commit.

| What changed | Update |
|---|---|
| New file in `lib/` | Add to [§2 Module Map](ARCHITECTURE.md#2-module-map) + relevant §3/§5 section |
| New/changed class, public API | Update the corresponding §3-§8 section in ARCHITECTURE.md |
| New/changed data model | Update [§10 Data Models](ARCHITECTURE.md#10-data-models) |
| New/changed provider | Update [§4 Provider Catalog](ARCHITECTURE.md#42-provider-catalog) + dependency graph |
| New/changed widget | Update [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference) |
| New/changed utility | Update [§7 Utilities API](ARCHITECTURE.md#7-utilities--public-api-reference) |
| Changed data flow | Update relevant [§9 Data Flow](ARCHITECTURE.md#9-data-flow-diagrams) diagram |
| New dependency added | Update [§17 Dependencies](ARCHITECTURE.md#17-dependencies) |
| Changed persistence format | Update [§11 Persistence](ARCHITECTURE.md#11-persistence--storage) |
| Changed security model | Update [§13 Security Model](ARCHITECTURE.md#13-security-model) + SECURITY.md |
| New design decision | Add to [§16 Design Decisions](ARCHITECTURE.md#16-design-decisions--rationale) with rationale |
| New CI workflow / changed pipeline | Update [§15 CI/CD](ARCHITECTURE.md#15-cicd-pipeline) |
| Platform-specific change | Update [§12 Platform-Specific](ARCHITECTURE.md#12-platform-specific-behavior) |
| New DI hook for testing | Update [§14 Testing Patterns](ARCHITECTURE.md#14-testing-patterns--di-hooks) |
| New/changed user-facing string | Add key to `lib/l10n/app_en.arb` **and translate into every other `app_*.arb` file** (ar, de, es, fa, fr, hi, id, ja, ko, pt, ru, tr, vi, zh — 15 total). Run `flutter gen-l10n`. Use `S.of(context).key`. Missing keys in non-en locales silently fall back to English — ship broken UX |
| New/changed shared component | Before adding a new widget/helper, search `lib/widgets/` and `lib/core/**` for an existing equivalent. Extend the shared component (add a param) instead of duplicating. Update [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference) |
| Architecture changed | Update CLAUDE.md if navigation links affected |
| User-visible change | Update README.md |
| Security scope change | Update SECURITY.md |

## Conventions

### Architecture (non-obvious rules)
- **No SCP** — dartssh2 doesn't support it; SFTP covers all use cases
- SSH keys accepted **both as file and text** (paste PEM)
- `.lfs` export format and import modes — single source of truth: [§3.9 Import](ARCHITECTURE.md#39-import-coreimport)
- Credentials in `CredentialStore` (AES-256-GCM), NOT in plain JSON — [§3.6 Security](ARCHITECTURE.md#36-security--encryption-coresecurity)
- **State placement** — app-wide state → Riverpod `NotifierProvider`; widget-local state (dialog / pane / panel / tab) with constructor-injected args or caches → `ChangeNotifier` + `AnimatedBuilder` (canonical examples: `FilePaneController`, `UnifiedExportController`, `SessionPanelController`, `TransferPanelController`). Side-channel Riverpod overrides for widget-local state = boilerplate with no win — [§4.3 Widget-local controllers](ARCHITECTURE.md#43-widget-local-controllers-changenotifier)

### Theme & UI Constants
OneDark theme: centralized in `app_theme.dart`, semantic color constants, no hardcoded `Colors` — [§8 Theme](ARCHITECTURE.md#8-theme-system)

- **Font sizes** — never hardcode `fontSize`. Use `AppFonts.tiny`/`xxs`/`xs`/`sm`/`md`/`lg`/`xl` (mobile +2 px)
- **Border radius** — never hardcode `BorderRadius.circular(N)`. Use `AppTheme.radiusSm` (4), `radiusMd` (6), `radiusLg` (8). Exception: pill-shaped elements
- **Heights** — never hardcode height literals. Use `AppTheme` constants: `barHeight{Sm,Md,Lg}`, `controlHeight{Xs..Xl}`, `itemHeight{Xs..Xl}`

### UI Components
- **Buttons & hover** — `AppIconButton` for all icon buttons. `HoverRegion` for custom hover containers. Never use bare `IconButton`, `InkWell` for buttons, or manual `MouseRegion`+`GestureDetector`+`setState(_hovered)`. Exception: `context_menu.dart`, mobile touch buttons — [§6 Widgets API](ARCHITECTURE.md#6-widgets--public-api-reference)
- **Dialogs** — `AppDialog` for all modal dialogs. Never use bare `AlertDialog`. Complex dialogs: compose from `AppDialogHeader`/`AppDialogFooter`/`AppDialogAction`. Progress: `AppProgressDialog.show()`. Exception: mobile touch buttons keep `Material`+`InkWell` for ripple
- **Text overflow protection** — localized text in `Row` or fixed-width — wrap with `Flexible`/`Expanded` + `overflow: TextOverflow.ellipsis`. For label columns use `ConstrainedBox(maxWidth:)` instead of fixed `SizedBox(width:)`
- **Accessibility** — wrap interactive list items (session rows, file rows) and panel headers with `Semantics` widget. Use `label` for screen reader text, `button: true` for tappable items, `selected` for selection state, `header: true` for section headings. `StatusIndicator` includes built-in `Semantics`

### Localization (i18n)
All user-facing strings MUST use `S.of(context).xxx`. Never hardcode strings in widgets — treat this as a bug. Add keys to `lib/l10n/app_en.arb`, run `flutter gen-l10n`, use `S.of(context).newKey`. Exceptions: constructor defaults (no context), log messages, `_AlreadyRunningApp`. Tests must include `localizationsDelegates: S.localizationsDelegates, supportedLocales: S.supportedLocales` in every `MaterialApp`. See [§8.1 i18n](ARCHITECTURE.md#81-internationalization-i18n)

## Branching & Release Flow

| Scenario                    | What to do                                                          |
| --------------------------- | ------------------------------------------------------------------- |
| App change (feat/fix/refac) | `bump-version.sh` on dev → PR `dev` → `main` → CI → auto-tag → release |
| Tests/docs/CI only          | Merge to `main` — no bump, no tag, no release                      |
| Dependabot deps             | Auto: PR to main → bump in branch → merge → CI → auto-tag → release |
| Manual build                | `gh workflow run build-release.yml` — fails if CI hasn't passed     |
| Failed build (re-trigger)   | `gh workflow run build-release.yml --ref v{VERSION}`                |
