# LetsFLUTssh — Feature Backlog & Execution Plan

Concrete per-feature execution plan for the next agent/developer. Each feature section lists **what exists today**, **what needs to be added**, and **every file that has to change with approximate line anchors**, so a contributor can open the listed paths and start typing.

## Progress log

Tracks features that have already shipped end-to-end (data + tests + docs). The table below should be the first thing a new contributor reads — sections marked **DONE** are reference material only; sections without it are still open.

| Status | Section | Commit | What landed |
|---|---|---|---|
| **DONE** | §2.1 Session extras column | `feat(session): add Sessions.extras JSON column` | Drift v1→v2 schema bump + Session model `Map<String, Object?> extras` + typed accessors. Unblocks every later wave-1+ feature without a migration per flag. |
| **DONE** | §2.2 ConnectionExtension hooks | `feat(connection): add ConnectionExtension lifecycle hooks` | Generic `onConnected` / `onDisconnecting` / `onReconnecting` interface + Connection fan-out. Failure-isolated; idempotent on never-connected transports. |
| **DONE (scoped down)** | §2.3 RemoteFs abstraction | `docs(backlog): scope down §2.3 RemoteFs prerequisite` | Existing `FileSystem` interface in `core/sftp/file_system.dart` already covers list/mkdir/remove/rename/dirSize and is implemented by both `LocalFS` and `RemoteFS`; the section above documents the additional surface (`stat` / `getStream`/`putStream` / `close`) to add later when S3 / WebDAV need it. |
| **DONE (-L only)** | §3.1 Port forwarding | `feat(ssh): add local SSH port forwarding (-L)` + `feat(session): add Forwarding tab to session edit dialog` | DB v2→v3 with `PortForwardRules` table, `PortForwardRuntime` implementing `ConnectionExtension`, in-place attach in `session_connect`, plus the 4th-tab UI in `session_edit_dialog` with add/edit/toggle/delete and a `0.0.0.0` warning. **Open work:** `-R` via `forwardRemote`, `-D` via `forwardDynamic` + SOCKS5 listener, session-row badge. |
| **DONE** | §3.2 ProxyJump bastion chains | `feat(ssh): add ProxyJump bastion chains` | DB v3→v4 with `Sessions.via_session_id` (FK SET NULL) + `via_host`/`via_port`/`via_user` override columns. `SSHConnection.connect` accepts a `socketProvider` so reconnect re-runs `bastion.client.forwardLocal`; `_ensureBastion` walks chains bottom-up with `visited`-based cycle guard and depth ≤ 8. Bastion connections are flagged `internal` so the UI hides them; manager `disconnect` cascades. UI: three-chip selector (None / Saved / Custom) in the Connection tab. |
| **DONE (v2 ed25519, both)** | §3.3 PuTTY `.ppk` import | `feat(security): import PuTTY .ppk v2 ssh-ed25519 unencrypted` + `feat(security): import encrypted PuTTY .ppk v2 ssh-ed25519` | Pure-Dart `PpkCodec` covering PPK v2 ssh-ed25519 unencrypted **and** encrypted (`aes256-cbc` with PuTTY's SHA-1 key schedule + zero IV). MAC verified before decryption; wrong passphrase surfaces as `PpkMacMismatchException`; missing passphrase throws `PpkPassphraseRequiredException`. `tryReadPemKey` detects PPK and converts to OpenSSH PEM in-place. **Open work:** PPK v3 (Argon2id KDF), `ssh-rsa` (mpint reconstruction). |
| **DONE** | §3.4 Snippet parameters | `feat(snippets): add {{name}} parameter substitution` | `renderSnippet` template engine + picker integration + fill dialog. Built-in `{{host}}` / `{{user}}` / `{{port}}` / `{{label}}` / `{{now}}`; user tokens prompt at execution. |
| **DONE** | §5.1 Broadcast input | `feat(terminal): add per-tab broadcast input` | Per-tab `BroadcastController` + driver/receiver context-menu actions + yellow border indicator + paste-confirmation dialog. Mobile / quick-connect inert via `supportsBroadcast` guard. |
| **DONE (recorder; playback open)** | §6.1 Session recording | `feat(session): add per-shell encrypted recording` | `SessionRecorder` hooks at the shell-helper level, asciinema v2 frames inside per-event AES-256-GCM (HKDF-derived key with `info="letsflutssh-recording-v1"` for cryptographic separation from DB key). Plaintext-tier sessions get raw `.cast` JSON-Lines with `chmod 600`. Per-recording rotation at 100 MB. Opt-in via session edit dialog Options tab. **Open work:** playback browser, global storage cap + LRU eviction, settings storage row. |

### Open features

Sections in the rest of this doc still apply as-written for the unfinished work — the same per-file action tables, schema bumps, and l10n key lists are accurate. **Read the `Status` of each above before starting**: a feature already marked DONE is reference, not work.

The remaining backlog (high to low priority, with concrete next-step pointers):

1. **§3.1 -R / -D port forwarding** — extend `PortForwardRuntime` with `forwardRemote` for `-R` and a hand-rolled SOCKS5 CONNECT-only listener bridged through `forwardDynamic` for `-D`. Persistence + UI already accept the `kind` enum; runtime currently emits "unsupported" status events for both. SOCKS5 hand-roll keeps the zero-install rule intact; ~120 lines.
2. **§3.2 polish** — session-row "via X" badge in the manager UI. Backend / persistence already done.
3. **§3.3 PPK v3 + ssh-rsa** — extend `PpkCodec` with PPK v3 (Argon2id KDF — `pointycastle` already has it; memory cap at 1 GiB) and `ssh-rsa` mpint reconstruction (n / e / d / iqmp / p / q packed into the openssh-key-v1 envelope). Same file, same test fixture pattern.
4. **§4.1 WebDAV sync** — biggest feature in the open list. Best-practice path: hand-roll WebDAV over `dart:io` HttpClient (PROPFIND/PUT/GET/DELETE/MKCOL — ~300 lines, zero new dep), Sessions+Keys+Snippets+Tags+Bookmarks soft-delete with `deletedAt DATETIME NULL` (DB v4→v5; **not** known_hosts — TOFU stays per-device), separate sync passphrase from master, manual push/pull buttons in v1 with auto-interval deferred. Plan in §4.1.
5. **§4.2 S3 bucket browser** — depends on the `RemoteFs` widening (`stat` / `getStream` / `putStream` / `close`). Best-practice path: hand-roll Sigv4 against AWS's published test suite (~600 lines including bucket ops + multipart), in-process fake test backend + integration suite under `--tags integration` for MinIO. STS / SSO / IAM out of scope v1.
6. **§6.1 playback browser** — list view of recordings under `<appSupport>/recordings/<sessionId>/`, decrypt-and-replay widget. Format is asciinema v2 inside the encryption envelope so a future "Export to .cast" is one decrypt away.
7. **§6.2 SSH certificates** — **upstream blocker:** dartssh2 2.17.1 has no client-side cert userauth API. Best-practice path: submit upstream PR adding cert support to `userauth_publickey.dart` + ship via local `pubspec_overrides.yaml` until it merges. Cert parser + display in key manager can ship before the upstream PR lands.
8. **§6.3 FIDO2-SSH** — desktop-first (Linux + Windows v1, macOS deferred for entitlements). Best-practice path: native HID platform channels per OS (not `package:hidapi` FFI — would break the zero-install rule on Linux distros without the package). Sequential PIN → touch dialogs.

---

Style contract — the doc stays useful only if it matches the codebase:

- File paths are live, line numbers are a hint (refresh before acting).
- DB/archive schema bumps name a `SchemaVersions` constant; those bumps are **mandatory together with a registered migration** — see `docs/ARCHITECTURE.md` §3.6 → "Migration framework" + `lib/core/migration/registry.dart` / `archive_registry.dart`.
- Every user-facing string lands in **all 15 ARBs** (`lib/l10n/app_*.arb`). Keys listed per feature are the English source; the implementer translates.
- Every non-UI change ships with unit tests; UI changes ship with widget tests. See `docs/AGENT_RULES.md § Testing Methodology`.
- Cross-platform: Android change → also iOS; Windows → also Linux + macOS.

---

## 1. Release wave ordering

Order is tuned to ship the largest pain-points first, keep crypto/security-sensitive work (sync, hardware tokens) behind more mundane plumbing that the codebase needs anyway, and front-load features that unblock later ones (e.g. ProxyJump lives in the Session model the sync archive also touches, so doing it early reduces later archive-migration churn).

| Wave | Features | Rough calendar (solo) |
|---|---|---|
| 1 — Core SSH pain | Port forwarding → ProxyJump → PuTTY `.ppk` → Snippet placeholders | 4–6 weeks |
| 2 — Sync & storage | WebDAV sync → S3 bucket browser | 6–8 weeks |
| 3 — Killer UX | Terminal broadcast input (splits already exist) | 1–2 weeks |
| 4 — Security-minded | Session recording → SSH certificates → Hardware tokens / FIDO2-SSH | 5–8 weeks |
| 5 — Deferred / drop | X11 / ssh-agent forwarding / Mosh / SCP | — |

---

## 2. Cross-cutting prerequisites

Do these **before** the first wave so every later feature has the scaffolding it needs. Skipping makes later work re-plumb the same spots repeatedly.

### 2.1 Session extensibility

Current `Session` (`lib/core/session/session.dart:78-204`) is flat with explicit fields. Every feature in this backlog adds at least one Session field. Three options:

- **Option A — add fields one-by-one per feature.** Each feature ships its own DB migration. Fine for 2-3 features, ugly for 8.
- **Option B — add a single `extras: Map<String, Object?>` JSON column.** One migration, zero further drift migrations. Loses type safety; tests must guard against `extras` key typos.
- **Option C — hybrid: structured columns for load-bearing fields (forwards, proxy jump), `extras` for the rest.**

Recommendation: **Option C**. Port forwarding + ProxyJump get their own columns because they load at connect time and need indexed lookups; agent forwarding, recording, certificate IDs, layout hints go into `extras`.

Action: add `Sessions.extras TEXT NOT NULL DEFAULT '{}'` column, drift migration + `schemaVersion` bump in `lib/core/db/database.dart:39`. Session model gains `Map<String, Object?> get extras`, helper getters `bool? extrasBool(key)`, `String? extrasStr(key)` etc.

### 2.2 Connection lifecycle hook points

`lib/core/connection/connection.dart:1-133` is the single object that lives across reconnects (`resetForReconnect()` around line 112). Every new "thing" that must survive reconnect registers on it:

- Port forwards
- ProxyJump bastion reference (keepalive)
- Session recording sink
- Agent forwarding state

Add a single `ConnectionExtension` interface the connection holds a list of. Each extension has `onConnected(SSHClient)`, `onDisconnecting()`, `onReconnecting()` hooks. Port forwards, recordings, etc. implement this instead of the manager re-implementing lifecycle per feature. One file, ~60 lines, unblocks all of wave 1–4.

### 2.3 Remote filesystem abstraction

**Status — already present, partial.** The original premise ("SFTP is pinned") was wrong: `lib/core/sftp/file_system.dart` already defines `abstract class FileSystem` with `list/initialDir/mkdir/remove/removeDir/rename/dirSize`, and both `LocalFS` (`file_system.dart`) and `RemoteFS` (`sftp_client.dart:473`) implement it. The file browser already consumes the abstract interface, not `SftpClient` directly.

**What's still missing** (added at S3 implementation time, not speculatively):

| Method | Why it's needed | When to add |
|---|---|---|
| `Future<RemoteStat?> stat(String path)` | S3 `HeadObject` for resumable downloads + last-modified comparisons in sync. SFTP path uses `dartssh2 SftpClient.stat(...)`. | §4.2 S3, §4.1 WebDAV |
| `Stream<List<int>> getStream(String path, {int? offset})` + `Future<void> putStream(String path, Stream<List<int>>)` | Byte-streaming with progress, currently lives in transfer queue keyed on SFTP. S3 multipart needs the same shape. | §4.2 S3 |
| `Future<void> close()` | S3 client + WebDAV client need explicit teardown; LocalFS / SFTP no-op. | §4.2 S3 |
| `Stream<ConnectionHealth> health` | Reflect S3 retry exhaustion / WebDAV server unreachable in the same UI surface as SSH disconnects. Consider deferring to wave 4 unless the file browser already grows a connection-state badge. | Optional — defer |

**Action.** No standalone refactor. Each S3-driven addition lands on its actual feature commit (§4.1 / §4.2). The shared interface is already in place; widening it without a concrete consumer would be premature abstraction.

---

## 3. Wave 1 — Core SSH pain

### 3.1 SSH port forwarding (-L / -R / -D)

**Goal.** Per-session rules that open on connect, close on disconnect, survive reconnect. Three rule types: local (-L), remote (-R), dynamic SOCKS5 (-D).

**What exists.**
- dartssh2 2.17.1 has the primitives:
  - `SSHClient.forwardLocal(host, port)` → `SSHForwardChannel`
  - `SSHClient.forwardRemote(...)` → `SSHRemoteForward`
  - `SSHClient.forwardDynamic(...)` → `SSHDynamicForward`
  - `SSHClient.forwardLocalUnix(path)` (bonus — ship later)
- `SSHForwardChannel implements SSHSocket`, so any channel can be passed around like a native socket.

**What's missing.** Everything above the dartssh2 layer.

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `lib/core/ssh/port_forward_rule.dart` (new) | Immutable `PortForwardRule` model: `id`, `type: PortForwardKind { local, remote, dynamic }`, `bindHost`, `bindPort`, `remoteHost`, `remotePort`, `description`, `enabled`. `toJson`/`fromJson`. ~80 lines. |
| 2 | `lib/core/db/tables.dart:25-57` | Add table `PortForwardRules` — `id TEXT PK`, `sessionId TEXT NOT NULL REFERENCES Sessions(id) ON DELETE CASCADE`, `kind TEXT`, `bindHost TEXT`, `bindPort INT`, `remoteHost TEXT`, `remotePort INT`, `description TEXT`, `enabled BOOL`, `createdAt DATETIME`, `sortOrder INT`. |
| 3 | `lib/core/db/database.dart:39` | Bump `schemaVersion` → 2. Drift `MigrationStrategy.onUpgrade` adds the new table. |
| 4 | `lib/core/db/dao/port_forward_rule_dao.dart` (new) | CRUD: `getBySession(id)`, `upsert(rule)`, `delete(id)`, `deleteBySession(id)`, `reorder(ids)`. |
| 5 | `lib/core/db/mappers.dart` | Domain ↔ DB converters for the rule. |
| 6 | `lib/core/session/session.dart:78-204` | `Session` gains `List<PortForwardRule> forwards`. `copyWith`, `toJson`, `fromJson` updated. |
| 7 | `lib/core/session/session_store.dart` | `load()` / `loadWithCredentials()` join the new DAO. `save()` persists the rule list. |
| 8 | `lib/core/ssh/port_forward_runtime.dart` (new) | `PortForwardRuntime` — implements `ConnectionExtension` (from §2.2). `onConnected` iterates enabled rules, opens channels via dartssh2, tracks `{ruleId: SSHForwardChannel}`. `onDisconnecting` closes all. SOCKS5 over `forwardDynamic` needs a small SOCKS-over-loopback-listener; use `package:socks5_proxy` or ~120 lines of hand-rolled SOCKS5. |
| 9 | `lib/core/connection/connection.dart:1-133` | Holds `PortForwardRuntime` when session has enabled rules. Exposes `Stream<ForwardRuleStatus>` for UI. |
| 10 | `lib/features/session_manager/session_edit_dialog.dart` | Add 4th tab "Port Forwarding" with dynamic rule list (reuse AppDataRow + AppButton patterns from existing tabs). `_buildTabBar()` ~line 298–312 grows one cell. |
| 11 | `lib/features/session_manager/session_panel_widgets.dart` | Session row gains a small `forward_outlined` badge when the session has active forwards, colour-coded to runtime status. |
| 12 | `lib/providers/connection_provider.dart` | Expose `forwardStatusProvider.family(sessionId)` streaming from the runtime. |
| 13 | `lib/features/settings/export_import.dart:314-323` | Export includes forwards (already in `sessions.json` if Session serialises them; verify). Bump `currentSchemaVersion` for the `.lfs` archive (see 3.1 archive migration below). |
| 14 | `lib/core/migration/schema_versions.dart` | Bump `db` 1 → 2, `archive` 1 → 2. |
| 15 | `lib/core/migration/artefacts/archive_v1_to_v2.dart` (new) | Archive migration: open v1 archive, parse `sessions.json`, ensure each session dict has `forwards: []` (missing = empty list), stamp v2 in manifest. Register in `archive_registry.dart`. |
| 16 | `docs/ARCHITECTURE.md` §3.1 / §10 / §11 | Document the new table + runtime + session field. |

**L10n keys.** `portForwarding`, `addForwardRule`, `localForward`, `remoteForward`, `dynamicForward`, `bindAddress`, `bindPort`, `targetHost`, `targetPort`, `forwardDescription`, `forwardRuleActive`, `forwardRuleError`, `forwardRuleDisabled`, `deleteForwardRule`, `socks5ProxyAt`.

**Tests.**
- `test/core/ssh/port_forward_rule_test.dart` — JSON roundtrip, validation.
- `test/core/db/port_forward_rule_dao_test.dart` — CRUD + cascade-delete.
- `test/core/ssh/port_forward_runtime_test.dart` — mocked SSHClient, assert channel lifecycle.
- `test/core/migration/archive_v1_to_v2_test.dart` — on v1 archive adds `forwards: []`.
- `test/features/session_manager/session_edit_dialog_forwards_test.dart` — add rule UX.

**Scope.** 2 weeks including docs + tests.

**Gotchas.**
- Remote forwards allocate a port on the server; handle `SSH_MSG_REQUEST_FAILURE` → show toast "server refused remote forward on port X".
- On mobile we can't reliably hold listening sockets while backgrounded; add a capability gate + note in UI.
- Dynamic (-D) listener must bind to loopback by default, never `0.0.0.0`. Make "bindHost" default `127.0.0.1` and show an explicit warning if the user types `0.0.0.0`.

---

### 3.2 ProxyJump / bastion chains

**Goal.** A session points to another saved session as its "jump host"; the connection opens the bastion first, then `forwardLocal(finalHost, finalPort)` → wrap the resulting `SSHForwardChannel` as the transport `SSHSocket` for the final `SSHClient`.

**What exists.**
- `SSHClient(this.socket, ...)` (dartssh2 `ssh_client.dart:204`) accepts any `SSHSocket`.
- `SSHForwardChannel implements SSHSocket` (`dartssh2/src/ssh_forward.dart:45`).
- No chaining logic in our code today — every session connects directly.

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `lib/core/session/session.dart` | Add `viaSessionId: String?` + `viaOverride: ProxyJumpOverride?` (`ProxyJumpOverride` = `{user, host, port}` free-form override for users who don't want a saved bastion). |
| 2 | `lib/core/db/tables.dart` | Add columns on `Sessions`: `viaSessionId TEXT NULL REFERENCES Sessions(id) ON DELETE SET NULL`, `viaHost TEXT NULL`, `viaPort INT NULL`, `viaUser TEXT NULL`. |
| 3 | `lib/core/db/database.dart:39` | `schemaVersion` already bumped in 3.1; add the columns to the same migration batch (ship 3.1 and 3.2 under db v2 together, not separate bumps). |
| 4 | `lib/core/ssh/ssh_client.dart:1-450` | `SSHClient` wrapper gains an optional `SSHSocket socket` parameter. When passed, skip the `SSHSocket.connect(host, port)` step inside `_connectSocket`. |
| 5 | `lib/core/connection/connection_manager.dart` | Recursive `connectAsync(sessionId)` — if `session.viaSessionId` non-null, first connect the bastion (recursively), wait until authenticated, call `bastion.client.forwardLocal(session.host, session.port)`, pass the resulting `SSHForwardChannel` as `socket:` to the final SSHClient. **Cycle detection** via a `Set<String> visited` argument — throw `ProxyJumpCycleException` if hit. Max depth 4 hop constant. |
| 6 | `lib/core/ssh/errors.dart` | Add `ProxyJumpCycleException`, `ProxyJumpBastionFailed(cause)`, `ProxyJumpDepthExceeded`. |
| 7 | `lib/utils/format.dart` | Localise the three new exception types (see the pattern the `errReleaseManifestUnavailable` work landed on). |
| 8 | `lib/features/session_manager/session_edit_dialog.dart` | In Connection tab, add a **"Connect via"** row: dropdown of other saved sessions + "None" + "Custom (user@host:port)". Custom pops three inline fields. |
| 9 | `lib/features/session_manager/session_panel_widgets.dart` | Session row subtitle: append `" (via <bastion-label>)"` when `viaSessionId` resolves. |
| 10 | `lib/features/settings/export_import.dart` | Export / import of `viaSessionId` — if the bastion is missing in the import, clear the field (don't fail the import). |
| 11 | `lib/core/migration/artefacts/archive_v1_to_v2.dart` | Extend the v1→v2 archive migration (same migration as 3.1) to ensure session dicts have the via-* fields nullable. |
| 12 | `docs/ARCHITECTURE.md` §3.1 / §3.5 / §10 | Add a data-flow diagram for the bastion chain. |

**L10n keys.** `proxyJump`, `connectVia`, `noProxyJump`, `customProxy`, `proxyUser`, `proxyHost`, `proxyPort`, `errProxyJumpCycle`, `errProxyJumpBastionFailed`, `errProxyJumpDepth`, `viaSessionLabel`.

**Tests.**
- `test/core/connection/proxy_jump_test.dart` — two-hop + three-hop, cycle detection, bastion-auth-failure propagation.
- `test/features/session_manager/session_edit_dialog_proxy_test.dart` — dropdown selection flows + custom override.

**Scope.** 1 week.

**Gotchas.**
- Keepalive on the bastion while the final hop is idle: dartssh2 default `keepAliveInterval: 10s` on each SSHClient covers it.
- When the user deletes a session that's referenced by `viaSessionId` in others: `ON DELETE SET NULL` handles the DB, but UI should show a banner "These sessions lost their jump host" after delete.

---

### 3.3 PuTTY `.ppk` import / export

**Goal.** Read + write PuTTY Private Key v2 and v3 files so Windows users migrating from PuTTY / Xshell / WinSCP don't have to convert keys manually.

**What exists.**
- `lib/core/import/key_file_helper.dart` already handles PEM + OpenSSH formats.
- dartssh2's `SSHKeyPair.fromPem(...)` (called from `lib/core/security/key_store.dart:292`) does not parse PPK.
- No PPK library on pub.dev with current null-safety + pure Dart (last check — verify before starting).

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `lib/core/security/ppk_codec.dart` (new) | Parser + writer for PPK v2 and v3. Format spec: <https://the.earth.li/~sgtatham/putty/0.78/htmldoc/AppendixC.html>. Needs `pointycastle` AES-256-CBC + HMAC-SHA-1 (v2) / Argon2id (v3) — `pointycastle` is already a direct dep. ~400–500 lines with tests. |
| 2 | `lib/core/security/ppk_codec_test.dart` (new) | Fixtures: one PPK v2 encrypted, one PPK v3 encrypted (Argon2id), one unencrypted. Decode → re-encode → bit-identical. |
| 3 | `lib/core/import/key_file_helper.dart` | `detectFormat(bytes)` gains a `KeyFormat.putty` case; dispatch to PPK codec. |
| 4 | `lib/core/security/key_store.dart:292-384` | On import, if `KeyFormat.putty` → decode with `PpkCodec`, convert the resulting OpenSSH-format raw bytes to dartssh2 `SSHKeyPair` (dartssh2 accepts OpenSSH serialised private keys). On export, offer "PuTTY v3" and "PuTTY v2" options alongside OpenSSH. |
| 5 | `lib/features/key_manager/key_manager_dialog.dart` | Export dropdown gains "PuTTY (.ppk, v3)" + "PuTTY (.ppk, v2)". Import auto-detects. |
| 6 | `lib/core/import/ssh_dir_key_scanner.dart` | Scanner picks up `*.ppk` alongside `id_*` files. |
| 7 | `lib/core/deeplink/deeplink_handler.dart` | If a deeplink points to a `.ppk` file, dispatch to the same import flow. |
| 8 | `docs/ARCHITECTURE.md` §3.9 | Document PPK support in the import matrix. |
| 9 | `docs/CONTRIBUTING.md` | Add a blurb on how to regenerate PPK test fixtures (puttygen command line). |

**L10n keys.** `importKeyPutty`, `exportAsPuttyV2`, `exportAsPuttyV3`, `errPuttyMacMismatch`, `errPuttyUnsupportedVersion`, `errPuttyBadCipher`.

**Scope.** 3–5 days, dominated by test fixtures + v3 Argon2id wiring.

**Gotchas.**
- PPK v3 uses Argon2id with parameters stored in the file header. We already bundle Argon2id via `pointycastle`; make sure the memory cost cap is sane (reject > 1 GiB).
- PPK v2 MAC uses HMAC-SHA-1 keyed with SHA-1(passphrase). Constant-time compare to avoid trivial leaks.
- The public key blob inside the PPK uses the same SSH wire format as OpenSSH, so the conversion path is one step away from what dartssh2 already consumes.

---

### 3.4 Snippets with parameters

**Goal.** Snippets can reference `{{host}}`, `{{user}}`, `{{port}}`, `{{label}}`, plus user-defined variables that prompt at run time.

**What exists.**
- `lib/core/snippets/snippet.dart:4-50` — flat `Snippet { id, title, command, description }`. No placeholder logic anywhere.
- `lib/features/snippets/snippet_picker.dart` — picker that writes the command directly into the terminal.

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `lib/core/snippets/snippet_template.dart` (new) | Pure function `String renderSnippet(Snippet s, Map<String, String> context)`. Parses `{{name}}` tokens, substitutes known keys (`host`, `user`, `port`, `label`, `folder`, `now`), leaves unknown tokens intact for the picker to prompt. Return `(rendered, List<String> unresolved)`. |
| 2 | `lib/features/snippets/snippet_picker.dart` | Before writing to the terminal: call `renderSnippet`. If `unresolved.isNotEmpty`, show a small modal "Fill in <var>" per token in order. |
| 3 | `lib/features/snippets/snippet_manager_dialog.dart` | Add a live preview pane — shows the rendered command for the currently-selected session. |
| 4 | `lib/l10n/app_en.arb` | New strings (see below). |
| 5 | `docs/ARCHITECTURE.md` §3 snippets section | Document the template grammar and the built-in context keys. |

**L10n keys.** `snippetParameters`, `snippetFillPrompt`, `snippetPreview`, `snippetUnresolved`.

**Tests.**
- `test/core/snippets/snippet_template_test.dart` — coverage for every built-in key, unknown-token passthrough, empty-context behaviour, `{{` literal escape (double-brace `{{{{` → `{{`).

**Scope.** 2–3 days.

**Gotchas.**
- Don't URL-encode or shell-escape the substituted value. Users typing `{{host}}` want exactly the host string. Shell escaping is their problem, same as it is in OpenSSH config.
- No recursion: `{{a}}` where `a=" {{b}} "` must render `{{b}}` literal — snippet substitution is single-pass.

---

## 4. Wave 2 — Sync & storage

### 4.1 WebDAV sync via encrypted `.lfs` archive

**Goal.** Multi-device sync without a central server: app pushes an encrypted `.lfs` to a user-configured WebDAV endpoint, pulls on demand, resolves conflicts via last-writer-wins on a manifest timestamp. **Explicit non-goal:** concurrent live editing across devices — one-writer-at-a-time is the supported model.

**What exists.**
- `.lfs` archive format + encryption already covers the transport payload (`lib/features/settings/export_import.dart:24-210`). We don't re-invent crypto; we re-use this one archive as the sync unit.
- `archiveMigrationRegistry` (`lib/core/migration/archive_registry.dart`) handles cross-version decoding.
- **No WebDAV client in the codebase.** Needs a new dependency (`webdav_client_plus` or hand-rolled — verify pub.dev current state).

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `pubspec.yaml` | Add `webdav_client_plus: ^<latest>` (or chosen alternative). Audit transitive deps for native bindings — we need pure Dart. |
| 2 | `lib/core/sync/webdav_client.dart` (new) | Thin wrapper around the dep: `put(path, bytes, etag?)`, `get(path) → (bytes, etag)`, `propfind(path) → EntryMeta { lastModified, etag, size }`, `delete(path)`. Auth: basic, digest, bearer. |
| 3 | `lib/core/sync/sync_service.dart` (new) | Orchestrator: `push()` — export `.lfs` → upload with If-Match etag. `pull()` — propfind → if remote newer than local `lastSyncedAt`, download, migrate (archive registry), merge. |
| 4 | `lib/core/sync/merge_strategy.dart` (new) | LWW on a per-entity `updated_at`: sessions, keys, known_hosts, tags, snippets, bookmarks. Each side keeps its modified-after-sync rows; remote wins for everything else. Deletes: we need soft-delete to avoid zombie rows; add `deletedAt` column to every syncable table (drift v3 migration). |
| 5 | `lib/core/db/tables.dart` | Add `deletedAt DATETIME NULL` to `Sessions`, `SshKeys`, `KnownHosts`, `Tags`, `Snippets`, `SftpBookmarks`. All user-visible queries filter `deletedAt IS NULL`. |
| 6 | `lib/core/db/database.dart:39` | Bump `schemaVersion` 2 → 3. |
| 7 | `lib/core/config/app_config.dart` | `SyncConfig { enabled, webdavUrl, user, passwordRef, remotePath = "letsflutssh.lfs", passphraseRef, autoIntervalMinutes? }`. PasswordRef + passphraseRef point into `SecureKeyStorage` entries, never plaintext in config. |
| 8 | `lib/features/settings/settings_sections_sync.dart` (new) | Settings section ("Sync") with enable toggle, URL/user/password fields, "Push now" / "Pull now" buttons, last-sync timestamp, last-result banner. |
| 9 | `lib/features/settings/settings_screen.dart:119-165` | Insert new section between "Data" and "Logging". |
| 10 | `lib/providers/sync_provider.dart` (new) | Riverpod notifier: `SyncState { status, lastSuccessAt, lastError }`. |
| 11 | `lib/features/settings/export_import.dart:43-83` | Bump `currentSchemaVersion` → 3 (archive already migrated in wave 1; add a field `syncOrigin` so we can avoid an echo-pull-push loop). |
| 12 | `lib/core/migration/schema_versions.dart` | Bump `archive` 2 → 3, `db` 2 → 3. |
| 13 | `lib/core/migration/artefacts/archive_v2_to_v3.dart` (new) | Stamps `syncOrigin: "unknown"` on unknown-origin archives. |
| 14 | `docs/ARCHITECTURE.md` new §18 | Document sync model + LWW semantics + soft-delete. |
| 15 | `docs/SECURITY.md` | Sync threat model: server is untrusted, only sees ciphertext; stolen passphrase = full compromise of synced data; stolen webdav creds alone = nothing useful. |

**L10n keys.** `syncSection`, `syncEnable`, `webdavUrl`, `webdavUser`, `webdavPassword`, `syncPassphrase`, `syncPushNow`, `syncPullNow`, `syncLastSuccess`, `errSyncConflict`, `errSyncUnauthorized`, `errSyncNetwork`, `syncRemotePath`, `syncAutoInterval`, `syncNeverRun`.

**Tests.**
- `test/core/sync/merge_strategy_test.dart` — every entity, LWW both directions, delete propagation, tombstone reconciliation.
- `test/core/sync/sync_service_test.dart` — with a fake WebDAV implementation in-process.
- `test/core/sync/webdav_client_test.dart` — against a local `webdav-server` test fixture (spawn one via `dart:io` server or use `testcontainers`-style fixture).
- Threat fixture: conflict on two devices modifying the same session → LWW wins as documented.

**Scope.** 1–2 weeks manual push/pull; add 1 week for auto-sync timer + conflict-banner UX.

**Gotchas.**
- **Soft-delete migration** is the riskiest piece — every query in every DAO gets a filter. Grep `from(session` / `from(snippet` etc. in `lib/core/db/dao/*` and update.
- The sync passphrase is **separate** from the master password. User's master password encrypts local DB; the sync passphrase encrypts the `.lfs` archive. Spell this out in the settings UI and in SECURITY.md — reusing master on untrusted endpoint is the classic user footgun.
- Sync should never push when the archive equals the last-pushed archive (compare SHA-256 of the plaintext manifest). Cuts needless traffic + avoids clock-skew LWW ties.
- ETags: use `If-Match` on push, `If-None-Match` on pull, to detect concurrent writes from another device.

---

### 4.2 S3 bucket browser (connection type #2)

**Goal.** Add S3-compatible endpoints as a first-class connection type alongside SSH/SFTP. Browse buckets, prefixes, upload/download with progress, manage credentials, support S3-compat backends (MinIO, Wasabi, R2, B2-S3, Scaleway, DigitalOcean Spaces).

**What exists.**
- `file_browser/*` widgets. Tightly coupled to `SftpClient` today.
- `lib/core/transfer/*` is already event-based, so S3 transfers can plug into the same queue.
- No AWS / S3 client dependency. **Pure-Dart** SDK candidates: `minio` pkg (MinIO's Dart SDK, covers S3 API), `aws_s3_api` (generated from SDK JSON), or hand-rolled Sigv4 — depending on maintenance health, pick one.

**Pre-requisite.** §2.3 `RemoteFs` abstraction. Do **not** start this feature until `RemoteFs` is in place and SFTP migrated under it.

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `pubspec.yaml` | Add chosen S3 pkg; audit for native deps (must be pure Dart). |
| 2 | `lib/core/session/session.dart` | `Session` gains `SessionKind { ssh, s3 }`. Existing sessions default to `ssh`. S3 sessions carry `accessKeyId`, `secretKeyRef` (SecureKeyStorage ref), `region`, `endpoint`, `pathStyle: bool`, `defaultBucket`, `defaultPrefix`. |
| 3 | `lib/core/db/tables.dart` | Add `kind TEXT NOT NULL DEFAULT 'ssh'` + S3 columns; or (cleaner) second table `S3Sessions` joined on session id. Prefer the second — keeps the Sessions table focused. |
| 4 | `lib/core/db/dao/s3_session_dao.dart` (new) | CRUD for S3 session details. |
| 5 | `lib/core/s3/s3_client.dart` (new) | Adapter wrapping the chosen pkg; implements `RemoteFs`. `list` → `ListObjectsV2`, `get`/`put` → `GetObject`/`PutObject` with multipart above threshold, `rename` → `CopyObject + DeleteObject`, `mkdir` → `PutObject(key='prefix/')`, `stat` → `HeadObject`. |
| 6 | `lib/core/s3/s3_multipart.dart` (new) | Multipart upload orchestrator with progress reporting + resumable state persisted to disk. |
| 7 | `lib/features/file_browser/*` | Already consuming `RemoteFs` after §2.3. Add S3-specific affordances: "Generate presigned URL" action, "Copy s3://...". |
| 8 | `lib/features/session_manager/session_edit_dialog.dart` | Kind dropdown at the top (SSH / S3). S3 mode hides SSH-only tabs, shows S3 fields. |
| 9 | `lib/features/session_manager/session_tree_view.dart` | Icon per kind. |
| 10 | `lib/features/settings/export_import.dart` | S3 sessions in `sessions.json` — kind field + bag of S3 fields. |
| 11 | `lib/core/migration/schema_versions.dart` | `archive` and `db` bump together. |
| 12 | `lib/core/migration/artefacts/archive_vN_to_vN+1.dart` | Missing `kind` → default `"ssh"`. |
| 13 | `docs/ARCHITECTURE.md` | New §3.12 "Storage providers" covering `RemoteFs` + SFTP + S3. |

**L10n keys.** `sessionKind`, `sessionKindSsh`, `sessionKindS3`, `accessKeyId`, `secretAccessKey`, `awsRegion`, `s3Endpoint`, `pathStyle`, `defaultBucket`, `defaultPrefix`, `generatePresignedUrl`, `presignedUrlExpiry`, `copyS3Uri`, `errS3AuthFailed`, `errS3NoSuchBucket`, `errS3RegionMismatch`.

**Tests.**
- `test/core/s3/s3_client_test.dart` — MinIO local instance as fixture; covers CRUD, multipart, presign.
- `test/core/s3/sigv4_test.dart` — if hand-rolling; AWS's Sigv4 test suite is public.
- `test/features/file_browser/s3_browser_test.dart` — widget test with fake `RemoteFs`.
- Compatibility matrix doc: AWS, MinIO, Wasabi, R2, B2-S3, Spaces. One test per per-backend quirk (path-vs-vhost, etc.).

**Scope.** 3–4 weeks, front-loaded by `RemoteFs` refactor in §2.3.

**Gotchas.**
- S3 "directories" are illusions. List with `delimiter='/'` and handle `CommonPrefixes`. Don't show apparent-empty "folders" inside a real prefix.
- Large downloads: byte-range GETs for resume, same progress model as SFTP.
- Regions: some backends ignore the region header entirely; R2 uses `auto`; MinIO accepts anything. Default to `auto` when endpoint is overridden.
- STS / SSO / IAM roles: out of scope v1. Static access key + secret only. Ship the hook point for later.
- Presigned URL expiry: default 15 min, user-configurable up to 7 days (Sigv4 max).

---

## 5. Wave 3 — Terminal broadcast input

### 5.1 Broadcast input across split panes

**Goal.** Type in one "driver" pane, keystrokes fan out to a user-chosen set of "receiver" panes in the same tab (or across tabs — decide later). Visual indicator on active participants. Paste guard so clipboard secrets don't unintentionally hit multiple hosts.

**What exists.**
- Split panes are **already implemented** — `lib/features/terminal/tiling_view.dart`, `split_node.dart`, `terminal_pane.dart`, draggable dividers in `tiling_view.dart:130-131`.
- `lib/core/ssh/shell_helper.dart:91-93` shows the single route where `terminal.onOutput` funnels into `shell.write(...)`. That's the fan-out seam.
- **Broadcast does not exist yet** (grep confirms zero references).

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `lib/features/terminal/broadcast_controller.dart` (new) | Per-tab (or per-workspace) controller: holds driver-pane id + `Set<String> receiverIds`. Exposes `void route(Uint8List bytes, String originPaneId)` called from each pane's input intercept; if `origin == driver` and `receivers` non-empty, also write to each receiver pane's shell sink. |
| 2 | `lib/core/ssh/shell_helper.dart:91` | Replace the single `terminal.onOutput = (data) => shell.write(...)` with a wrapper that consults the BroadcastController first. Each `ShellConnection` exposes a `rawWrite(Uint8List)` the controller can call without going back through xterm. |
| 3 | `lib/features/terminal/terminal_pane.dart` | Header gains a toggle "Broadcast target" (for receivers) + "Broadcasting from here" (for driver). Click opens a tiny popover to add/remove receivers from the tab's pane list. |
| 4 | `lib/features/terminal/tiling_view.dart` | Broadcast-active panes get a `AppTheme.yellow` 2 px border. Driver pane gets a slightly thicker border. |
| 5 | `lib/features/terminal/broadcast_paste_guard.dart` (new) | Intercept pastes on the driver pane when broadcast is active. Show a modal: "This will send <N chars> to <M hosts>. Continue?" with a "Don't ask again for this session" checkbox. Special-case: if paste contains shell-meta characters `$`, `(`, `` ` ``, or matches clipboard-secret heuristic from `SecureClipboard`, require explicit confirm regardless of don't-ask. |
| 6 | `lib/core/shortcut_registry.dart` | Add shortcuts: `Cmd+Shift+I` toggle receiver on focused pane, `Cmd+Shift+B` set driver to focused pane, `Cmd+Shift+O` clear all broadcast. |
| 7 | `lib/features/workspace/workspace_view.dart` | Optional: status-bar chip "Broadcasting to N panes" in the tab bar. |
| 8 | `docs/ARCHITECTURE.md` §5.1 | Document broadcast model + paste guard. |

**L10n keys.** `broadcastDriver`, `broadcastReceiver`, `broadcastOff`, `broadcastPasteConfirm`, `broadcastActiveBanner`, `broadcastRecipientCount`, `broadcastNoReceivers`.

**Tests.**
- `test/features/terminal/broadcast_controller_test.dart` — route fan-out, ignore echoes, no self-loop.
- `test/features/terminal/broadcast_paste_guard_test.dart` — secret-detector integration, don't-ask persistence.
- Widget test: driver pane sends a keystroke → every receiver's `MockShellConnection.rawWrite` sees the bytes.

**Scope.** 1–2 weeks (feature isolated, no persistence, no backend changes).

**Gotchas.**
- Mobile: broadcast is a desktop-only feature. Hide the controls on mobile.
- Driver pane's `onOutput` fires on **keystrokes after xterm processing** (arrow keys → escape sequences). That's the right layer for broadcast; we want the same bytes the driver shell sees, not the pre-terminal scan codes.
- If a receiver pane has a broken shell, its `rawWrite` should drop the write without throwing so a single broken receiver doesn't stall the driver.

---

## 6. Wave 4 — Security-minded

### 6.1 Session recording

**Goal.** Per-session encrypted local log of commands + output. Searchable viewer, export to encrypted bundle.

**What exists.**
- `lib/utils/logger.dart` — app-level log, sanitised, opt-in threshold (we just reworked this). Not session-scoped.
- `lib/core/security/*.dart` — AES-256-GCM primitives already here.

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `lib/core/session/session_recorder.dart` (new) | Implements `ConnectionExtension` (§2.2). On connect, opens `<appSupport>/recordings/<sessionId>/<timestamp>.lfsr` encrypted file. Consumes the xterm output stream + the user-input stream, writes framed `{ts, direction: in/out, bytes}` records. |
| 2 | `lib/core/ssh/shell_helper.dart` | Fork output/input streams into the recorder when `session.extras['record'] == true`. |
| 3 | `lib/core/session/session.dart` | Expose `recordEnabled` getter reading `extras['record']`. |
| 4 | `lib/features/session_manager/session_edit_dialog.dart` | Options tab: "Record session" toggle. |
| 5 | `lib/features/recordings/recording_browser.dart` (new) | List / play / scrub recordings. Playback via xterm replay — each frame applies `terminal.write` at the original cadence, with speed controls. |
| 6 | `lib/features/settings/settings_sections_data.dart` | Add "Clear all recordings" + "Recording storage used" row. |
| 7 | `lib/features/settings/export_import.dart` | Exclude recordings from the default `.lfs` archive (too big). Offer separate "Export recordings bundle" action. |
| 8 | `lib/core/migration/schema_versions.dart` | New artefact `recording` schema — v1 in `SchemaVersions`. |
| 9 | `lib/core/migration/artefacts/recording_v1.dart` (new) | Recording format = `VersionedBlob` wrapper + gzipped frames inside. |
| 10 | `docs/ARCHITECTURE.md` new §3.13 / `docs/SECURITY.md` | Recording threat model: plaintext command history on disk is sensitive; the same DB key protects it. |

**L10n keys.** `recordSession`, `recordings`, `recordingDuration`, `recordingSize`, `playRecording`, `deleteRecording`, `exportRecordings`, `clearRecordings`, `recordingsStorage`.

**Tests.**
- `test/core/session/session_recorder_test.dart` — write → read roundtrip, frame ordering, cap on size (e.g. 100 MB default) with rotation.
- Widget test for playback scrubbing.

**Scope.** 1–2 weeks.

**Gotchas.**
- ANSI-coloured output in recordings takes up space; default gzip keeps ratio reasonable.
- Ring-buffer or rotate on per-session size cap; user sets it in Settings.
- Never log passwords: the recorder must consult `SecureClipboard`'s sensitive-paste markers and drop those frames entirely.
- Think about "record by default" vs "opt-in per session". Default is **opt-in** — forensic-by-default is incompatible with the privacy-first positioning.

---

### 6.2 SSH certificates (OpenSSH signed keys)

**Goal.** Support user certs issued by internal CAs — step-ca, HashiCorp Vault SSH, Teleport-style short-lived certs. Auto-renew via external command hook.

**What exists.**
- `SSHKeyPair` in dartssh2 + our `KeyStore` handle plain key pairs.
- No cert support anywhere.

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `lib/core/security/ssh_certificate.dart` (new) | Parser for OpenSSH cert format (`ssh-rsa-cert-v01@openssh.com`, `ssh-ed25519-cert-v01@openssh.com`). Expose principals, validity, critical options. |
| 2 | `lib/core/security/key_store.dart` | `SshKeyEntry` gains `certificate: Uint8List?`. On auth, dartssh2 wants the cert alongside the private key; check dartssh2's API — it may already accept cert-format public keys via its `publicKeyType` field. |
| 3 | `lib/core/ssh/ssh_client.dart` | When building identities (`_buildIdentities` ~line 338), attach cert when present. |
| 4 | `lib/features/key_manager/key_manager_dialog.dart` | Import cert → pair it with an existing key by fingerprint. Show validity + principals. |
| 5 | `lib/core/security/cert_renewal.dart` (new) | Optional: run an external command (configured per key) when the cert is within N minutes of expiry. E.g. `step ssh renew --force` — **user configures the shell command, we exec it**. Security-aware: confirm before first run. |
| 6 | `lib/core/db/tables.dart` | Add `certificate TEXT` column to `SshKeys`. DB schema bump. |
| 7 | `lib/core/migration/schema_versions.dart` | Archive bump + db bump. |
| 8 | `docs/SECURITY.md` | Cert model: we don't sign, we only carry. External renewal command runs under the user's privileges. |

**L10n keys.** `sshCertificate`, `certValidFrom`, `certValidTo`, `certPrincipals`, `certRenewCommand`, `certExpiringBanner`, `errCertParse`, `errCertRenewFailed`.

**Scope.** 1 week if dartssh2 accepts certs natively; 2 weeks if we need to handcraft the SSH_MSG_USERAUTH_REQUEST cert payload.

**Gotchas.**
- Cert expiry often < 1 hour with modern step-ca setups. Auto-renew needs to be reliable; log every renewal attempt through the same `AppLogger`.
- External command execution is a capability expansion — guard behind "Allow renewal commands" setting that defaults off.

---

### 6.3 Hardware tokens / FIDO2-SSH

**Goal.** Support `sk-ecdsa-sha2-nistp256@openssh.com` + `sk-ssh-ed25519@openssh.com` (OpenSSH 8.2+ FIDO2 keys) on YubiKey / SoloKey / OnlyKey.

**Caveat.** This is the **highest-risk** feature in the backlog. Requires CTAP2 bridge per platform (PC/SC on desktop, native plugins on mobile, no Web target). Budget it as v1 = desktop only, v2 = mobile later.

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `pubspec.yaml` | Add `fido2` (if pure Dart and maintained) or hand-roll the CTAP2 client. Likely need a platform channel per OS. |
| 2 | `lib/core/security/fido2/ctap2_client.dart` (new) | CTAP2 HID transport on Linux/Windows/macOS via `hidapi` FFI — already a common pattern in cross-platform Dart. |
| 3 | `lib/core/security/fido2/sk_signer.dart` (new) | Glue: given challenge bytes, calls `ctap2_client.getAssertion(...)` using the credential blob stored in the key file. Returns signature in the format dartssh2 expects. |
| 4 | `lib/core/ssh/ssh_client.dart` | Identity list accepts `SkKeyIdentity` alongside `SSHKeyPair`; dartssh2 userauth flow delegates the signing step to our signer. |
| 5 | `lib/features/key_manager/key_manager_dialog.dart` | Import `*.pub` sk-* key → store the credential handle, no private scalar. Show "requires hardware key" label. |
| 6 | `lib/features/key_manager/hardware_key_prompt.dart` (new) | "Tap your hardware key" modal with timeout + cancel. |
| 7 | `docs/ARCHITECTURE.md` §3.6 Security | Document FIDO2-SSH threat model. |

**L10n keys.** `hardwareKey`, `hardwareKeyTapPrompt`, `hardwareKeyTimeout`, `hardwareKeyNotFound`, `hardwareKeyUnsupported`, `skKeyRequiresDevice`, `errSkWrongPin`.

**Scope.** 2–3 weeks desktop. Mobile adds 2–3 weeks more and platform-specific plugins.

**Gotchas.**
- Touch prompts must be cancelable — otherwise a forgotten prompt hangs auth.
- Some tokens need PIN entry; we surface a PIN field in the prompt modal.
- macOS requires `com.apple.developer.driverkit.communicates-with-hid-devices` entitlement or raw HID access gets blocked under sandbox — audit before shipping.
- Windows Hello sk-* keys exist; defer to v2.

---

## 7. Deferred / drop list

| Feature | Why deferred |
|---|---|
| **X11 forwarding** | Requires a local X server (XQuartz / VcXsrv / native) that violates the zero-install principle. A bundled VcXsrv on Windows is GPL — license conflict unless the whole app goes GPL. Recommend **building a VNC client** instead, covers the same "remote GUI" use case without the X server problem. |
| **ssh-agent client-side forwarding** | dartssh2 has no agent-channel client. Needs a from-scratch agent-protocol implementation + platform-specific bridging (Unix socket on POSIX, Pageant named pipe on Windows, OpenSSH-for-Windows named pipe) + FFI. ~3–4 weeks for meagre end-user ROI (users with a corporate agent setup are rare). Revisit if >3 users ask. |
| **Mosh** | Separate UDP protocol, no Dart client, requires `mosh-server` on remote. Would be a second stack to maintain alongside SSH. Skip. |
| **SCP** | Deprecated by OpenSSH itself; SFTP covers every use case. Skip. |
| **Team session sharing** | Not our product positioning. Skip. |
| **Rich remote shell autocomplete** | Requires a shell-integration shim (FISH-style) or a local model that parses remote history. Shell-integration is fragile; model-based is out of scope. Skip. |

---

## 8. Generic checklist for every feature in this backlog

Use this as a PR template — anything missing is a rejected PR:

- [ ] New table / column → drift migration registered + `schemaVersion` bumped + covered by a `test/core/db/migration/*_test.dart`.
- [ ] Archive artefact format changes → new migration in `lib/core/migration/artefacts/`, registered in `archive_registry.dart`, `SchemaVersions.archive` bumped, cross-version roundtrip test.
- [ ] User-facing strings in **all 15** ARBs (native IT register, see `docs/AGENT_RULES.md § Localization Tone`).
- [ ] ARCHITECTURE.md section updated **in the same commit** (how + why both).
- [ ] Unit tests + widget tests per `docs/AGENT_RULES.md § Testing Methodology`.
- [ ] No hardcoded `fontSize`/`Colors`/`BorderRadius.circular(N)` — use `AppFonts`/`AppTheme`.
- [ ] Cross-platform check: Android ↔ iOS, Windows ↔ Linux ↔ macOS.
- [ ] `make analyze` clean, `make test` green.
- [ ] SonarCloud check on the PR — no new open issues.
- [ ] CLAUDE.md / AGENT_RULES.md updated only if the rule changes; otherwise leave them.

---

## 9. Pointers for the implementer

- **Do not read `ARCHITECTURE.md` cover-to-cover.** Use the TOC; each feature section above links the `§N` that matters. The `/doc` skill (`.claude/skills/doc/SKILL.md`) fetches a §N directly.
- Before any file edit, run the pre-fix discipline from `CLAUDE.md § Always-On Rules → Docs first`.
- Every feature lands on `dev`, never `main` directly. PR workflow in `.claude/skills/pr/SKILL.md`.
- Version bumps are calculated by `scripts/bump-version.sh` from Conventional Commits — don't hand-edit `pubspec.yaml`.
- **Batch feature PRs by wave**, not per file. A wave merges as one PR with a dozen+ commits so the release note reads coherently.
