# LetsFLUTssh — Feature Backlog & Execution Plan

Concrete per-feature execution plan for the next agent/developer. Each feature section lists **what exists today**, **what needs to be added**, and **every file that has to change with approximate line anchors**, so a contributor can open the listed paths and start typing.

## Progress log

Tracks features that have already shipped end-to-end (data + tests + docs). The table below should be the first thing a new contributor reads — sections marked **DONE** are reference material only; sections without it are still open.

| Status | Section | Commit | What landed |
|---|---|---|---|
| **DONE** | §2.1 Session extras column | `feat(session): add Sessions.extras JSON column` | Drift v1→v2 schema bump + Session model `Map<String, Object?> extras` + typed accessors. Unblocks every later wave-1+ feature without a migration per flag. |
| **DONE** | §2.2 ConnectionExtension hooks | `feat(connection): add ConnectionExtension lifecycle hooks` | Generic `onConnected` / `onDisconnecting` / `onReconnecting` interface + Connection fan-out. Failure-isolated; idempotent on never-connected transports. |
| **DONE (scoped down)** | §2.3 RemoteFs abstraction | `docs(backlog): scope down §2.3 RemoteFs prerequisite` | Existing `FileSystem` interface in `core/sftp/file_system.dart` already covers list/mkdir/remove/rename/dirSize and is implemented by both `LocalFS` and `RemoteFS`; the section above documents the additional surface (`stat` / `getStream`/`putStream` / `close`) to add later when S3 / WebDAV need it. |
| **DONE (full -L/-R/-D)** | §3.1 Port forwarding | 4 commits: backend (-L) + Forwarding-tab UI + `-R` (`forwardRemote`) + hand-rolled SOCKS5 (`-D`). | DB v2→v3 with `PortForwardRules` table, `PortForwardRuntime` implementing `ConnectionExtension`. Local listeners on `ServerSocket`; remote listeners via `client.forwardRemote` with targeted error on server refusal (GatewayPorts hint); dynamic listeners run a hand-rolled SOCKS5 CONNECT-only server (RFC 1928, NO_AUTH only, IPv4 / domain / IPv6 address types) — zero new dep. UI: 4th tab with three-chip kind picker, add/edit/toggle/delete, `0.0.0.0` warning. |
| **DONE (full)** | §3.2 ProxyJump bastion chains | `feat(ssh): add ProxyJump bastion chains` + `feat(session): add via-X badge to session tree row` | DB v3→v4 with `Sessions.via_session_id` (FK SET NULL) + `via_host`/`via_port`/`via_user` override columns. `SSHConnection.connect` accepts a `socketProvider` so reconnect re-runs `bastion.client.forwardLocal`; `_ensureBastion` walks chains bottom-up with `visited`-based cycle guard and depth ≤ 8. Bastion connections are flagged `internal` so the UI hides them; manager `disconnect` cascades. UI: three-chip selector (None / Saved / Custom) in the Connection tab + compact "via X" badge in the session tree row that resolves saved-bastion ids against the live session list. |
| **DONE (full v2+v3, ed25519+rsa)** | §3.3 PuTTY `.ppk` import | 4 commits covering the full {v2, v3} × {ssh-ed25519, ssh-rsa} × {unencrypted, encrypted} matrix. | Pure-Dart `PpkCodec` with `parse(text, passphrase)` top-level dispatcher. v2 uses SHA-1 key schedule + zero IV + HMAC-SHA-1; v3 uses Argon2id (1 GiB memory cap) + KDF-derived IV + HMAC-SHA-256. Algorithm-specific OpenSSH packers (`toOpenSshPemEd25519` / `toOpenSshPemRsa`) handle the openssh-key-v1 envelope construction including the ssh-rsa component reordering (PPK ships `(d, p, q, iqmp)`, OpenSSH wants `(n, e, d, iqmp, p, q)`). MAC verified before decryption so wrong passphrase surfaces as `PpkMacMismatchException`. |
| **DONE** | §3.4 Snippet parameters | `feat(snippets): add {{name}} parameter substitution` | `renderSnippet` template engine + picker integration + fill dialog. Built-in `{{host}}` / `{{user}}` / `{{port}}` / `{{label}}` / `{{now}}`; user tokens prompt at execution. |
| **DONE** | §5.1 Broadcast input | `feat(terminal): add per-tab broadcast input` | Per-tab `BroadcastController` + driver/receiver context-menu actions + yellow border indicator + paste-confirmation dialog. Mobile / quick-connect inert via `supportsBroadcast` guard. |
| **DONE (recorder + playback)** | §6.1 Session recording | `feat(session): add per-shell encrypted recording` + `feat(recordings): add playback browser + xterm replay dialog` | `SessionRecorder` hooks at the shell-helper level, asciinema v2 frames inside per-event AES-256-GCM (HKDF-derived key with `info="letsflutssh-recording-v1"` for cryptographic separation from DB key). Plaintext-tier sessions get raw `.cast` JSON-Lines with `chmod 600`. Per-recording rotation at 100 MB. Opt-in via session edit dialog Options tab. **Tools → Recordings** lists every file under `<appSupport>/recordings/`, resolves session label against the live session list (orphan rows show `<deleted>` + truncated id), tap to play in an embedded xterm at user-chosen speed (1× / 2× / 4× / instant); per-event GCM frames decoded sequentially. **Still open:** global storage cap + LRU eviction, settings storage-used row, scrub bar (would need a per-frame index file for random access). |
| **DONE** | UX polish round | `fix: ProxyJump race + forwarding UX polish`, `feat(snippets): inline token hints in manager dialog`, `fix: chip labels, control sizes, recordings location, fprintd spam` | Race fix on bastion socketProvider (await `waitUntilReady` before reading `client`); via-X badge constrained to 140 px + Flexible(loose); shared `AppPickerChip` widget extracted (used by ProxyJump + Forwarding) with `SelectionContainer.disabled` so chip labels don't behave like body text; chip labels dropped `(-L)` / `(-R)` / `(-D)` / `(user@host:port)` parenthetical hints to fit cramped translations; per-kind explanation text under the kind picker; rule-row toggle + delete unified to AppIconButton; rule-editor "Save" → "OK"; recordings entry moved from Settings → Data into Tools (desktop sidebar + mobile list); BiometricAuth.availability + backingLevel cache one probe per process to stop the fprintd ServiceUnknown spam. |
| **DONE** | Known hosts: OpenSSH `~/.ssh/known_hosts` import | `feat(known-hosts): accept OpenSSH ~/.ssh/known_hosts on import` | Importer accepts both the LetsFLUTssh internal wire format and OpenSSH on the same parser pass — bare hostnames default to port 22, `[host]:port` brackets (incl. IPv6) resolve cleanly, comma-separated multi-host fans out into one entry per host, `@cert-authority` / `@revoked` markers strip cleanly, hashed `\|1\|salt\|hash` rows skip with a counter that surfaces in the log (HMAC-SHA1 hostname hashes are one-way, nothing to TOFU-match against). |
| **DONE** | User-facing documentation | `docs(user-guide): add USER_GUIDE.md + bind agents to keep it current` | `docs/USER_GUIDE.md` (~700 lines, 18 sections) — end-user reference for every shipped feature with worked examples + platform notes. |

### Open features

Sections in the rest of this doc still apply as-written for the unfinished work — the same per-file action tables, schema bumps, and l10n key lists are accurate. **Read the `Status` of each above before starting**: a feature already marked DONE is reference, not work.

The remaining backlog (high to low priority, with concrete next-step pointers):

1. **§4.1 WebDAV sync** — biggest feature in the open list. Best-practice path: hand-roll WebDAV over `dart:io` HttpClient (PROPFIND/PUT/GET/DELETE/MKCOL — ~300 lines, zero new dep), Sessions+Keys+Snippets+Tags+Bookmarks soft-delete with `deletedAt DATETIME NULL` (DB v4→v5; **not** known_hosts — TOFU stays per-device), separate sync passphrase from master, manual push/pull buttons in v1 with auto-interval deferred. Plan in §4.1.
2. **§4.2 S3 bucket browser** — depends on the `RemoteFs` widening (`stat` / `getStream` / `putStream` / `close`). Best-practice path: hand-roll Sigv4 against AWS's published test suite (~600 lines including bucket ops + multipart), in-process fake test backend + integration suite under `--tags integration` for MinIO. STS / SSO / IAM out of scope v1.
3. **§4.3 WebDAV file browser** — reuses §4.1's transport. ~1 week of additional surface for `WebDavRemoteFs` + a `webdav` `SessionKind`. Browses Nextcloud / ownCloud / mod_dav / generic NAS WebDAV endpoints in the same file-browser UI as SFTP and (eventually) S3.
3. **§6.2 SSH certificates** — protocol layer landed via russh (`lfs_core::ssh::connect_pubkey_cert`). Open work: cert import / display in the key manager + an optional auto-renewal hook that runs an external command (e.g. `step ssh renew`) before expiry.
4. **§6.3 FIDO2-SSH** — desktop-first (Linux + Windows v1, macOS deferred for entitlements). Best-practice path: native HID platform channels per OS (not `package:hidapi` FFI — would break the zero-install rule on Linux distros without the package). Sequential PIN → touch dialogs.
5. **§6.1 polish** (smaller follow-ups): global storage cap + LRU eviction for recordings, settings tile showing recordings disk-used, scrub bar in playback (would need a per-frame index file written alongside the recording for random access).

---

Style contract — the doc stays useful only if it matches the codebase:

- File paths are live, line numbers are a hint (refresh before acting).
- DB/archive schema bumps name a `SchemaVersions` constant; those bumps are **mandatory together with a registered migration** — see `docs/ARCHITECTURE.md` §3.6 → "Migration framework" + `lib/core/migration/registry.dart` / `archive_registry.dart`.
- Every user-facing string lands in **all 15 ARBs** (`lib/l10n/app_*.arb`). Keys listed per feature are the English source; the implementer translates.
- Every non-UI change ships with unit tests; UI changes ship with widget tests.
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

## 2. Cross-cutting prerequisites — DONE

| § | Status | What landed |
|---|---|---|
| 2.1 Session extensibility | ✅ | `Sessions.extras TEXT NOT NULL DEFAULT '{}'` column + typed accessors. See [ARCHITECTURE §10 Data Models → Session.extras](ARCHITECTURE.md#10-data-models). |
| 2.2 Connection lifecycle hooks | ✅ | `ConnectionExtension` interface — `onConnected` / `onDisconnecting` / `onReconnecting` with failure-isolated fan-out. See [ARCHITECTURE §3.5 → ConnectionExtension](ARCHITECTURE.md#connectionextension--lifecycle-add-ons). |
| 2.3 Remote filesystem abstraction | ✅ (scoped) | `FileSystem` interface in `lib/core/sftp/file_system.dart` already covers the SFTP path; widening (`stat` / `getStream` / `putStream` / `close`) lands per-feature when §4.2 / §4.1 actually consume it. |

---

## 3. Wave 1 — Core SSH pain — DONE

| § | Status | What landed |
|---|---|---|
| 3.1 Port forwarding (-L / -R / -D) | ✅ | DB column + `PortForwardRules` table + `PortForwardRuntime` (`ConnectionExtension`-based) + 4th tab in session edit dialog + hand-rolled SOCKS5 for `-D`. Server-side `GatewayPorts no` produces a targeted toast on remote-bind refusal. See [ARCHITECTURE §3.1 → Port forwarding](ARCHITECTURE.md#port-forwarding). |
| 3.2 ProxyJump bastion chains | ✅ | `Session.viaSessionId` + `via_host` / `via_port` / `via_user` override columns + `Connection.bastion` cascade + cycle / depth-8 guards + "via X" badge in session tree. See [ARCHITECTURE §3.1 → ProxyJump](ARCHITECTURE.md#proxyjump--bastion-chains). |
| 3.3 PuTTY `.ppk` import | ✅ | Pure-Dart `PpkCodec` — v2 + v3 (Argon2id with 1 GiB memory cap), `ssh-ed25519` + `ssh-rsa`, encrypted + unencrypted, MAC-verified before decrypt. See [ARCHITECTURE §3.9 → PPK codec](ARCHITECTURE.md#ppk-codec--puttys-private-key-format). |
| 3.4 Snippet `{{tokens}}` | ✅ | `renderSnippet()` template engine + `SnippetPicker.show()` + fill-modal for unresolved user tokens. Built-in keys: `host` / `user` / `port` / `label` / `now`. See [ARCHITECTURE §3.12 Snippets](ARCHITECTURE.md#312-snippets-coresnippets). |

---

---

## 4. Wave 2 — Sync & storage

### 4.1 WebDAV sync via encrypted `.lfs` archive

**Goal.** Multi-device sync without a central server: app pushes an encrypted `.lfs` to a user-configured WebDAV endpoint, pulls on demand, resolves conflicts via last-writer-wins on a manifest timestamp. **Explicit non-goal:** concurrent live editing across devices — one-writer-at-a-time is the supported model.

**What exists.**
- `.lfs` archive format + encryption already covers the transport payload (`lib/features/settings/export_import.dart:24-210`). We don't re-invent crypto; we re-use this one archive as the sync unit.
- Archive future-version handling lives in `lfs_core::archive::read_archive_to_pending`, which rejects archives whose `manifest.schema_version` is newer than `SchemaVersions::ARCHIVE` so older builds can't apply newer formats. Within-version decoding routes through the same composer as export.
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

### 4.3 WebDAV file browser (connection type #3)

**Goal.** Reuse the WebDAV transport landed for §4.1 sync to expose a generic WebDAV server as a first-class connection type alongside SSH/SFTP and S3 — browse remote folders, upload/download with progress, manage credentials. Unlocks Nextcloud / ownCloud / Apache mod_dav / generic NAS WebDAV endpoints in the same file-browser UI users already know.

**Why now.** §4.1 hand-rolls the WebDAV verbs (PROPFIND / GET / PUT / DELETE / MKCOL / MOVE) for the encrypted-archive sync use case. Same code, different surface — a `WebDavRemoteFs` adapter implementing §2.3's `RemoteFs` interface costs ~200 LOC on top of the §4.1 transport. Skipping it would mean we ship WebDAV-as-sync but force users to a different app for WebDAV-as-files, even though the protocol is identical.

**Pre-requisites.**
- §4.1 WebDAV sync ships first → reuses transport + auth (basic / digest / bearer) + path utilities.
- §2.3 `RemoteFs` widening (`stat` / `getStream` / `putStream` / `close`) — same widening §4.2 needs.

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `lib/core/session/session.dart` | `SessionKind` gains `webdav`. WebDAV sessions carry `baseUrl`, `username`, `passwordRef` (SecureKeyStorage ref or token), optional `selfSignedFingerprint` for cert pinning, `authMethod: AuthMethod { basic, digest, bearer }`. |
| 2 | `lib/core/db/tables.dart` (or a `WebDavSessions` join table mirroring §4.2 S3Sessions) | New columns / table for WebDAV-specific fields. |
| 3 | `lib/core/webdav/webdav_client.dart` (extracted from §4.1's hand-rolled transport) | `WebDavClient` with verb methods. Used by both sync (§4.1) and the file browser (§4.3). |
| 4 | `lib/core/webdav/webdav_remote_fs.dart` (new) | Implements `RemoteFs` over `WebDavClient`. `list` → PROPFIND depth=1 + parse multistatus, `get`/`put` → GET/PUT with byte-range support for resume, `mkdir` → MKCOL, `rename`/`move` → MOVE, `stat` → PROPFIND depth=0. |
| 5 | `lib/features/file_browser/*` | Already consumes `RemoteFs` post-§2.3. Add WebDAV-specific affordances: "Copy WebDAV URL", "Open in browser" (basic auth in URL stripped). |
| 6 | `lib/features/session_manager/session_edit_dialog.dart` | Kind dropdown gains `webdav`. WebDAV mode shows base URL + auth method + creds, hides SSH/S3 tabs. |
| 7 | `lib/features/settings/export_import.dart` | WebDAV sessions in `sessions.json`. |
| 8 | `lib/core/migration/schema_versions.dart` + `archive_vN_to_vN+1.dart` | `kind` migration covers WebDAV. |
| 9 | `docs/ARCHITECTURE.md` §3.12 "Storage providers" | Add WebDAV. |

**L10n keys.** `sessionKindWebDav`, `webDavBaseUrl`, `webDavAuthMethod`, `webDavBasic`, `webDavDigest`, `webDavBearer`, `webDavSelfSignedFingerprint`, `errWebDavAuthFailed`, `errWebDavNotFound`, `errWebDavConflict`, `errWebDavLockOwnedByOther`.

**Tests.**
- `test/core/webdav/webdav_client_test.dart` — fake HTTP fixture, exercises every verb + error-path mapping.
- `test/core/webdav/webdav_remote_fs_test.dart` — adapter conforms to `RemoteFs` semantics.
- Integration suite under `--tags integration`: spin up a containerised Apache mod_dav and a Nextcloud, run the same matrix.

**Scope.** ~1 week riding on §4.1's transport. Front-loaded by §4.1 + §2.3 — no standalone work until those land.

**Gotchas.**
- PROPFIND depth=infinity is rejected by many servers (Nextcloud, ownCloud); always depth=1 for browsing.
- LOCK / UNLOCK semantics are server-specific. Skip in v1; uploads use `If-None-Match: *` to avoid clobbering only.
- Apache mod_dav reports MIME types from filename; Nextcloud uses its own DB. Don't trust `getcontenttype` for syntax highlighting — sniff like SFTP does.
- Self-signed certs: same trust path as SSH host keys — TOFU on first connect, fingerprint stored per session.
- Large files: PUT supports chunked transfer encoding; resumable upload is server-specific (Nextcloud has a chunked-upload extension, generic WebDAV doesn't). Document the limitation.

---

## 5. Wave 3 — Terminal broadcast input — DONE

| § | Status | What landed |
|---|---|---|
| 5.1 Broadcast input across split panes | ✅ | Per-tab `BroadcastController` (`broadcastControllerProvider.family`) with driver / receiver roles, yellow pane border, paste-confirmation modal, mobile + quick-connect inert via `supportsBroadcast` guard. See [ARCHITECTURE §5.1 → Broadcast input](ARCHITECTURE.md#broadcast-input--per-tab-fan-out). |

---

## 6. Wave 4 — Security-minded

### 6.1 Session recording — DONE (recorder + playback) / open polish

**Status: shipped.** Per-shell `SessionRecorder` (`core/session/session_recorder.dart`) writes asciinema-v2 frames inside per-event AES-256-GCM (HKDF-derived key, info-tag `letsflutssh-recording-v1`) on T1/T2/Paranoid; plaintext `.cast` on T0. Per-recording rotation at 100 MB. Tools → Recordings UI in `features/recordings/` plays via embedded xterm at user-chosen speed (1× / 2× / 4× / instant). See [ARCHITECTURE §3.13 Session Recording](ARCHITECTURE.md#313-session-recording-coresessionsession_recorderdart) + [§5.7 Recordings](ARCHITECTURE.md#57-recordings-featuresrecordings).

**Open polish items:**
- Global storage cap + LRU eviction across all recordings.
- Settings tile showing recordings disk-used + "Clear all recordings" action.
- Scrub bar in the playback dialog — would need a per-frame index file written alongside the recording for random access (per-event GCM frames decode sequentially, no native seek today).

---

### 6.2 SSH certificates (OpenSSH signed keys)

**Status: protocol layer DONE.** Rust core authenticates with OpenSSH certs via `lfs_core::ssh::Session::connect_pubkey_cert`. UI surface (cert import + display + auto-renewal) still pending.

**Goal.** Support user certs issued by internal CAs — step-ca, HashiCorp Vault SSH, Teleport-style short-lived certs. Auto-renew via external command hook.

**What exists.**
- **Rust transport** — `lfs_core::ssh::Session::connect_pubkey_cert(host, port, user, key, passphrase, cert)` parses the cert via russh's forked `ssh-key` (the `internal-russh-forked-ssh-key` workspace dep with the `ppk` feature flipped on; see `rust/Cargo.toml`) and authenticates via russh's `Handle::authenticate_openssh_cert`. FRB binding: `ssh_connect_pubkey_cert(host, port, user, private_key: Vec<u8>, passphrase: Option<String>, cert: Vec<u8>)` already exposed under `lib/src/rust/api/ssh.dart`. russh 0.59 has the cert algorithm tables natively — no fork.
- **Dart-side UI** still does not have a cert import flow. The Auth tab in the session edit dialog only wires the password / key-file / key-from-manager / inline-PEM modes.

**Files to change.**

| # | Path | Action |
|---|---|---|
| 1 | `rust/crates/lfs_core/src/keys.rs` | Add a cert-parser entry point (`parse_openssh_cert(bytes) -> CertSummary`) returning the typed shape Dart needs (principals, valid_after_unix, valid_before_unix, critical options, key fingerprint). The russh fork already does the hard parsing — wrap it. |
| 2 | `rust/crates/lfs_frb/src/api/keys.rs` | Expose the parser through FRB so the manager UI can render the validity / principals without holding cert bytes Dart-side. |
| 3 | `rust/crates/lfs_core/src/db/ssh_keys.rs` + `lfs_core::db::SCHEMA_SQL` | Add `certificate BLOB NULL` column to `SshKeys`; bump `SCHEMA_VERSION`. SCHEMA_SQL bootstrap stamps the `ALTER TABLE` step. |
| 4 | `rust/crates/lfs_frb/src/api/db.rs` (`DbSshKey` row + `db_ssh_keys_*`) | Plumb the `certificate` blob through the existing DAO surface. Keep cert bytes on the Rust side via SecretStore staging when fed into a connect — never round-trip through the Dart heap on the auth path. |
| 5 | `lib/core/security/ssh_key.dart` | `SshKeyEntry` + `SshKeyMetadata` gain `certificate: Uint8List?` (null when not paired). Mapper updates in `lib/src/rust/api/db.dart`. |
| 6 | `lib/features/key_manager/key_manager_dialog.dart` | Import cert → pair with the existing key entry by public-key fingerprint match. Show validity (with expired badge) + principals + critical options in the row's tertiary line. |
| 7 | `lib/core/connection/connections_notifier.dart` | When `SshKey.certificate != null`, route through `SshAuthPubkeyCertRef` (already declared in `transport/ssh_transport.dart`) instead of `SshAuthPubkeyRef`. The transport layer already maps that variant onto `connect_pubkey_cert`. |
| 8 | `rust/crates/lfs_core/src/cert_renewal.rs` (new) | Optional: run an external command (configured per key) when the cert is within N minutes of expiry. E.g. `step ssh renew --force` — **user configures the shell command, we exec it via `tokio::process::Command`**. Security-aware: confirm before first run, log every attempt through `lfs_core::log_sanitize`. |
| 9 | `docs/SECURITY.md` | Cert model: we don't sign, we only carry. External renewal command runs under the user's privileges; document the new "Allow renewal commands" toggle. |

**L10n keys.** `sshCertificate`, `certValidFrom`, `certValidTo`, `certPrincipals`, `certCriticalOptions`, `certRenewCommand`, `certExpiringBanner`, `certExpired`, `errCertParse`, `errCertRenewFailed`.

**Scope.** ~1 week — the russh transport is already done; UI + DAO column + mapper plumbing + the cert-pairing flow in the manager is the outstanding work. Auto-renewal sits on top as a follow-up.

**Gotchas.**
- Cert expiry often < 1 hour with modern step-ca setups. Auto-renew needs to be reliable; log every renewal attempt through the same `AppLogger`.
- External command execution is a capability expansion — guard behind "Allow renewal commands" setting that defaults off.

---

### 6.3 Hardware tokens / FIDO2-SSH

**Status: agent-mediated path DONE.** Direct CTAP2 (no agent) is deferred until an opt-in real-user need surfaces.

**Goal.** Support `sk-ecdsa-sha2-nistp256@openssh.com` + `sk-ssh-ed25519@openssh.com` (OpenSSH 8.2+ FIDO2 keys) on YubiKey / SoloKey / OnlyKey.

**What works today (after rust-core merge).**
- User runs `ssh-add -K /path/to/sk_ed25519` once on their machine to register the FIDO2 key with the system ssh-agent.
- App calls `lfs_core::ssh::Session::connect_agent(host, port, user)` via the existing FRB binding (`ssh_connect_agent` under `lib/src/rust/api/ssh.dart`). russh's agent client (`russh::client::Handle::authenticate_future` driven by an `AgentClient`) enumerates identities including sk-* keys, advertises them to the server during userauth, drives the FIDO2 user-presence prompt itself, returns the signature; russh just relays bytes.
- Covers macOS, mainstream Linux, Windows (OpenSSH-Agent service or Pageant). No CTAP2 stack on our side — the agent owns it.

**What direct CTAP2 (no agent) would add.**
- Windows < 10 with no agent service.
- Locked-down enterprise where ssh-agent is forbidden.
- Mobile (Android USB FIDO; iOS still restricted by Apple).

**Caveat.** Direct CTAP2 is the **highest-risk** part of this backlog. Requires CTAP2 bridge per platform (PC/SC or hidraw on desktop, native plugins on mobile, no Web target). Budget it as v1 = desktop only, v2 = mobile later. Defer until a real user need surfaces — the agent path covers the common case.

**Files to change** (when direct CTAP2 lands — agent path is already shipped).

| # | Path | Action |
|---|---|---|
| 1 | `rust/crates/lfs_core/Cargo.toml` | Add the [`ctap-hid-fido2`](https://crates.io/crates/ctap-hid-fido2) crate (pure-Rust CTAP2 over HID — no `libpcsclite` install required, integrates cleanly with `tokio`). Optional cargo feature so non-FIDO builds skip the dep. |
| 2 | `rust/crates/lfs_core/src/fido2.rs` (new) | CTAP2 wrapper: `get_assertion(rp_id, client_data_hash, credential_id, options)` returning the signature bytes. `tokio::task::spawn_blocking` for the HID I/O so the FRB worker stays free. |
| 3 | `rust/crates/lfs_frb/src/api/fido2.rs` (new) | Expose `fido2_get_assertion(...)` async; the Rust signer reaches russh's signer trait through an `AgentClient`-shaped adapter so the existing `connect_pubkey` paths can swap out the assertion source. |
| 4 | `rust/crates/lfs_core/src/db/ssh_keys.rs` (+ schema bump) | Persist the sk-* key as `(public_blob, credential_id, application_string, has_user_verification)` rather than a private scalar; the credential_id replaces the PEM bytes for these entries. |
| 5 | `lib/core/security/ssh_key.dart` | `SshKeyEntry` gains `credentialId: Uint8List?` + `applicationString: String?` (sk-* sessions). Type variant in `SshKeyType` enum: `skEd25519`, `skEcdsaP256`. |
| 6 | `lib/features/key_manager/key_manager_dialog.dart` | Import `*.pub` sk-* key → parse the credential handle from the OpenSSH binary frame, store it. Render "Hardware-bound (FIDO2)" badge in the row. |
| 7 | `lib/widgets/hardware_key_prompt_dialog.dart` (new) | "Tap your hardware key" modal with timeout + cancel + (when sk-* key requires it) PIN field. |
| 8 | `docs/ARCHITECTURE.md` §3.6 Security + new §3.6.x sub-section | Document the FIDO2-SSH threat model on top of the existing biometric / hardware-vault sections. |

**L10n keys.** `hardwareKey`, `hardwareKeyTapPrompt`, `hardwareKeyTimeout`, `hardwareKeyNotFound`, `hardwareKeyUnsupported`, `skKeyRequiresDevice`, `errSkWrongPin`.

**Scope.** 2–3 weeks desktop. Mobile adds 2–3 weeks more and platform-specific plugins (Android `UsbManager` permission flow + iOS NFC / Lightning entitlement requests).

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
| **ssh-agent forwarding (`-A`)** | Distinct from "agent as auth provider on the local box" (which is **shipped** via russh's `AgentClient` + `ssh_connect_agent`, see §6.3 above). `-A` opens an agent channel on the *remote* host so commands there can talk back to your local agent — useful for `git pull` on a bastion that needs to authenticate forward-hops. russh exposes the channel-open hook but the local-agent server side (Unix socket loop on POSIX, Pageant named pipe on Windows, OpenSSH-for-Windows named pipe) is from-scratch work; ~2 weeks for meagre end-user ROI (users with a corporate agent-forwarding requirement are rare and the security trade-off — remote process can sign anything your agent holds — is famously dangerous). Revisit if >3 users ask. |
| **Mosh** | Separate UDP protocol, no Dart client, requires `mosh-server` on remote. Would be a second stack to maintain alongside SSH. Skip. |
| **SCP** | Deprecated by OpenSSH itself; SFTP covers every use case. Skip. |
| **Team session sharing** | Not our product positioning. Skip. |
| **Rich remote shell autocomplete** | Requires a shell-integration shim (FISH-style) or a local model that parses remote history. Shell-integration is fragile; model-based is out of scope. Skip. |

---

## 8. Generic checklist for every feature in this backlog

Use this as a PR template — anything missing is a rejected PR:

- [ ] New table / column → `lfs_core::db::SCHEMA_SQL` updated with idempotent `CREATE TABLE IF NOT EXISTS` / `CREATE INDEX IF NOT EXISTS`, `SCHEMA_VERSION` bumped, covered by a Rust unit test under `rust/crates/lfs_core/src/db/`. Format-envelope changes (config.json, credentials.kdf, hardware vault blobs) go through the `lfs_core::migration` framework — see ARCHITECTURE §3.6 → Migration framework.
- [ ] Archive artefact format changes → new migration in `lib/core/migration/artefacts/`, registered in `archive_registry.dart`, `SchemaVersions.archive` bumped, cross-version roundtrip test.
- [ ] User-facing strings in **all 15** ARBs.
- [ ] ARCHITECTURE.md section updated **in the same commit** (how + why both).
- [ ] Unit tests + widget tests.
- [ ] No hardcoded `fontSize`/`Colors`/`BorderRadius.circular(N)` — use `AppFonts`/`AppTheme`.
- [ ] Cross-platform check: Android ↔ iOS, Windows ↔ Linux ↔ macOS.
- [ ] `make check` green (covers `make lint` + `make test` for Dart + Rust, plus workflow lint, release hardening, unused-deps).
- [ ] SonarCloud check on the PR — no new open issues.

---

## 9. Pointers for the implementer

- **Do not read `ARCHITECTURE.md` cover-to-cover.** Use the TOC; each feature section above links the `§N` that matters.
- Every feature lands on `dev`, never `main` directly.
- Version bumps are calculated by `scripts/bump-version.sh` from Conventional Commits — don't hand-edit `pubspec.yaml`.
- **Batch feature PRs by wave**, not per file. A wave merges as one PR with a dozen+ commits so the release note reads coherently.
