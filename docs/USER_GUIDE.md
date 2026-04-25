# LetsFLUTssh — User Guide

End-user reference for every feature shipped in the app. Walks through the typical flow + every option per surface, with worked examples.

> Looking for build instructions? See [`CONTRIBUTING.md`](CONTRIBUTING.md). Looking for the security threat model? See [`SECURITY.md`](SECURITY.md).

---

## Table of contents

- [1. First launch](#1-first-launch)
- [2. Sessions](#2-sessions)
- [3. Authentication](#3-authentication)
- [4. Terminal](#4-terminal)
- [5. SFTP file browser](#5-sftp-file-browser)
- [6. Port forwarding (-L / -R / -D)](#6-port-forwarding--l----r----d)
- [7. ProxyJump bastion chains](#7-proxyjump-bastion-chains)
- [8. Snippets with `{{tokens}}`](#8-snippets-with-tokens)
- [9. Broadcast input across split panes](#9-broadcast-input-across-split-panes)
- [10. Session recording + playback](#10-session-recording--playback)
- [11. SSH key manager + PuTTY `.ppk` import](#11-ssh-key-manager--putty-ppk-import)
- [12. Tags](#12-tags)
- [13. Known hosts (TOFU)](#13-known-hosts-tofu)
- [14. Security tiers](#14-security-tiers)
- [15. Import / export](#15-import--export)
- [16. Updates](#16-updates)
- [17. Mobile differences](#17-mobile-differences)
- [18. Troubleshooting](#18-troubleshooting)

---

## 1. First launch

1. Install per [README → Installation](../README.md#installation).
2. App opens to the **Sessions** sidebar (empty) and a **Welcome** placeholder in the main area.
3. **Security tier is set up silently on the first launch** (see [§14 Security tiers](#14-security-tiers)). When the OS keychain is reachable (the common case on every supported platform), the app auto-selects **T1 — Keychain** without prompting, and surfaces a one-shot banner saying so. Only when the keychain is unreachable (e.g. Linux without `gnome-keyring` / KWallet, ad-hoc-signed macOS without an installed signing identity) does a tier-picker wizard appear with T0 / Paranoid as alternatives. T2 hardware-bound and any of the modifiers (master password, biometric shortcut) are opt-in via **Settings → Security** at any time.
4. **Add your first session:** sidebar → "+" or `Ctrl+N`. Fill host / port / username + auth (password or key). Save.
5. **Connect:** double-click the session, or right-click → Terminal / Files.

---

## 2. Sessions

### Creating

- **Sidebar → "+"** or `Ctrl+N` → Session edit dialog.
- **Tabs:** Connection / Auth / Options / Forwarding.
- **Connection tab:** name, host, port, username, plus the [Connect via](#7-proxyjump-bastion-chains) selector at the bottom.
- **Auth tab:** [§3 Authentication](#3-authentication).
- **Options tab:** tags, [Record session toggle](#10-session-recording--playback).
- **Forwarding tab:** [§6 Port forwarding](#6-port-forwarding--l----r----d).
- **Footer buttons:** Cancel / Save / Save & Connect.

### Editing

- Right-click a session → Edit, or press `F2` on a focused row.
- Same dialog as creation. Credential fields are pre-filled from disk on open.

### Folders

- Drag a session onto a folder header to move it.
- Right-click in the sidebar → New Folder (anywhere).
- Folders nest arbitrarily deep. Rename via right-click → Rename Folder. Delete cascades to sessions inside (with a confirm).
- Folders can carry tags (right-click → Edit Tags).

### Search

- Sidebar search field filters by label / host / user. Case-insensitive.

### Drag-and-drop

- Drag a session onto another folder / the root area.
- Drag a folder onto another folder.
- Multi-select (Ctrl-click rows) → Move to → folder picker.

### Quick share

- Right-click a session → Export → QR code (small payloads) or Copy share link.
- The recipient pastes the link via Settings → Data → Import → "From link" (no camera needed) or scans the QR via the in-app scanner.

### Quick connect (without saving)

- Toolbar → Quick Connect → fill host / port / user / auth → Connect.
- Session is not persisted; closing the tab loses the config.

---

## 3. Authentication

The Auth tab in the session edit dialog supports four modes; you fill in the parts that apply.

### Password

- Single field. Stored encrypted at rest (per security tier).
- "Show password" eye icon temporarily reveals.

### Key from file

- "Select Key File" → file picker. Path is stored; the bytes are read on connect.
- `~` / `~/...` paths are supported on desktop (expanded against `$HOME`).

### Key from manager

- Drop-down references a key already imported via Tools → SSH Keys (see [§11](#11-ssh-key-manager--putty-ppk-import)).
- Preferred over file paths for portability — the key travels with the session via export/import.

### PEM key text

- Paste the private-key body (`-----BEGIN OPENSSH PRIVATE KEY-----` … or PKCS#1/PKCS#8 PEM).
- Used for one-off keys you don't want to save to disk.

### Passphrase

- Required for any key type that's encrypted. If left empty and the key is encrypted, you'll be prompted at connect time and can opt to remember for the session.

### Combining password + key

- "Two-factor": both fields filled. Server must accept both. Auth chain order: key first, password as fallback / second factor.

### Encrypted PEM detection

- Settings → Security → … (informational). The auth chain handles `Proc-Type: 4,ENCRYPTED`, PKCS#8 encrypted, and OpenSSH KDF-encrypted keys uniformly.

---

## 4. Terminal

### Opening a tab

- Double-click a session in the sidebar.
- Or right-click → Terminal.
- Or sidebar entry `Quick Connect` → Connect.

### What you see

- Top of the terminal shows connection progress (`[*]` yellow, `[✓]` green, `[✗]` red) until the shell opens.
- After connect, full xterm: 256-color + RGB, mouse modes, scrollback, search.

### Keyboard shortcuts (desktop)

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+C` | Copy selection |
| `Ctrl+Shift+V` | Paste |
| `Ctrl+Shift+F` | Search inside scrollback |
| `Ctrl+\` | Split right (new pane in same tab) |
| `Ctrl+Shift+\` | Split down |
| `Ctrl+W` | Close active pane / tab |
| `Ctrl++` / `Ctrl+-` / `Ctrl+0` | Zoom in / out / reset |
| `Shift` (hold while dragging) | Bypass app's mouse-mode capture for text selection in TUI apps (htop, vim, mc) |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tab |

### Splits (tiling)

- Split a pane → it becomes two, separated by a draggable divider.
- Drag the divider to resize. Min pane width 80 px.
- Each pane runs its own SSH shell channel on the same connection (no new auth handshake).
- Close a pane: hover the pane header → close icon, or `Ctrl+W` in the focused pane.

### Reconnect

- Tab header dot turns red on disconnect. Right-click tab → Reconnect, or click the inline "Reconnect" button.
- Cached passphrase is reused; `Connection.cachedPassphrase` survives the reconnect cycle within the same session.

---

## 5. SFTP file browser

### Opening

- Right-click a session → Files. A new tab opens with the SFTP browser.
- Two-pane: local (left) / remote (right).

### Navigation

- Address bar at top of each pane. `Enter` to jump.
- Breadcrumb path is clickable.
- `..` row navigates up.
- Folder icon → enter; file icon → opens preview / context menu.

### Transfers

- Drag a file from local to remote (or remote to local) → transfer queue picks it up.
- Multi-select with `Ctrl`/`Shift`+click for bulk transfers.
- Right-click → Cut / Copy / Paste between panes (cross-pane = transfer).
- Transfer panel (bottom) shows queue, parallel workers, progress per file, retry on failure.

### Bookmarks

- Pin a remote path: address bar → star icon. Saved as `SftpBookmark` in DB, scoped to the session.
- Quick-jump from the bookmark dropdown.

### Editing remote files (round-trip)

- Right-click a remote file → Open in editor → downloads to a temp dir, opens in OS-default editor, watches for save → re-uploads.
- Closing the editor cleans up the temp file.

---

## 6. Port forwarding (-L / -R / -D)

These are SSH command-line concepts. Every saved session can carry a list of forwarding rules that open automatically on connect and close on disconnect.

### Vocabulary

| Flag | Direction | Listener side | Use case |
|---|---|---|---|
| `-L` Local | client → server target | your machine | reach a remote DB / admin UI as if it were `localhost` |
| `-R` Remote | server → client target | SSH server | expose your local dev server to a remote box |
| `-D` Dynamic | SOCKS5, any target | your machine | route browser traffic through SSH |

### Adding a rule

1. Open the session in the editor.
2. **Forwarding** tab (4th).
3. **Add rule** → modal opens.
4. Pick a kind chip: **Local** / **Remote** / **Dynamic**. The line under the chips explains the kind in plain language.
5. Fill the fields (different per kind — see below).
6. **OK** to commit the rule into the parent dialog's in-memory list.
7. **Save** on the outer session dialog to persist to disk.

### Local (`-L`) — example

You have a Postgres on `db.internal:5432` reachable only from `bastion.example.com`. You want to point `psql` on your laptop at `localhost`.

```
Kind:        Local
Bind addr:   127.0.0.1
Bind port:   5432
Target host: db.internal
Target port: 5432
Description: prod DB tunnel
```

Connect → `psql -h localhost -p 5432 -U dbuser` → reaches the remote Postgres.

### Remote (`-R`) — example

You have `npm run dev` on `localhost:3000` and want a colleague sitting on `dev-server.example.com` to access it.

```
Kind:        Remote
Bind addr:   localhost
Bind port:   9000
Target host: localhost
Target port: 3000
```

Connect → on `dev-server.example.com`: `curl localhost:9000` reaches your laptop's dev server.

**Server-side `GatewayPorts`.** OpenSSH defaults `GatewayPorts no`, which forces remote-forward bind to loopback regardless of the value you type. To bind on `0.0.0.0` (visible to anyone with network access to the server), edit `/etc/ssh/sshd_config` on the **server**: `GatewayPorts yes` + `sudo systemctl reload sshd`. The app surfaces a targeted error if the server refuses.

### Dynamic (`-D`) — example

You want all your browser traffic to leave through `bastion.example.com` (geo-bypass / privacy / corp internal sites without a VPN).

```
Kind:        Dynamic
Bind addr:   127.0.0.1
Bind port:   1080
```

Connect → set browser SOCKS5 proxy to `127.0.0.1:1080`. Every request resolves + connects on the bastion.

**Supported protocol surface:** RFC 1928, CONNECT-only, NO_AUTH, IPv4 / domain / IPv6 address types. No BIND, no UDP ASSOCIATE. Plenty for browsers, `curl --socks5`, `proxychains`, etc.

### Rule list controls

- **Toggle (sliding switch icon):** enable / disable without deleting. Disabled rules don't open on connect.
- **Trash (red):** delete the rule.
- **Tap a row:** edit the rule.

### Common mistakes

- **Bind port already in use** → toast + the rule's row marks error. Pick a different port.
- **Bind on `0.0.0.0` for `-L` or `-D`** → the tunnel is reachable from anyone on your local network. Yellow warning in the editor.
- **Forgot to Save outer dialog** → rules disappear when you close it. The "OK" button on the rule editor only commits to the parent dialog's in-memory list.

---

## 7. ProxyJump bastion chains

A session can route through one or more bastions (`ssh -J`-equivalent). Useful for "you can only reach prod through corp gateway".

### Two modes

- **Saved session as bastion** — references another row in your session list. Bastion has its own credentials. Recommended.
- **Custom override** — type `user@host:port` directly. The override inherits credentials from the current session. Documented limitation: for distinct bastion auth, save the bastion as its own session.

### Setting it up

1. (Optional but recommended) Create / save the bastion as a normal session.
2. Open the **target** session in the editor.
3. **Connection** tab → **Connect via** chip selector.
4. Pick:
   - **None** — direct connection (default).
   - **Saved session** — dropdown shows every other saved session; pick the bastion.
   - **Custom** — three fields (host, port, user).
5. Save.

### Visual cue

- In the session tree, every session that has a bastion shows a compact **"via X"** badge (X = bastion's label, or its host for overrides).

### Chains

- Bastion can itself have a `via X` — chains supported up to 8 hops.
- Cycle detection: if you set A `via` B and B `via` A, the runtime trips with toast "Proxy chain loops back on itself" before any bytes move.

### How it works under the hood

1. App connects to the deepest bastion first (direct TCP).
2. Auth that bastion.
3. Open `forwardLocal(nextHop.host, nextHop.port)` on it — the channel is the transport for the next SSHClient.
4. Repeat until the leaf hop authenticates.
5. Disconnect cascades: closing the leaf closes every bastion in the chain.

### Hidden from UI

- Bastion connections don't appear as user-visible tabs. They're flagged `internal: true` in the connection manager. The Android foreground-service notification still counts them so the OS doesn't kill the chain mid-bounce.

---

## 8. Snippets with `{{tokens}}`

Reusable shell commands with placeholder substitution.

### Creating

1. **Tools → Snippets → Add**.
2. Title (e.g. "Restart nginx").
3. Command — supports `{{tokens}}`:

   ```
   ssh -p {{port}} {{user}}@{{host}} sudo systemctl restart {{service}}
   ```

4. **Token chips under the field** — tap to insert at the current caret position. Built-in chips:

   | Token | Source at execution |
   |---|---|
   | `{{host}}` | `Session.host` |
   | `{{user}}` | `Session.user` |
   | `{{port}}` | `Session.port` |
   | `{{label}}` | `Session.label` |
   | `{{now}}` | ISO-8601 wall-clock at the moment of execution |

5. Anything else (e.g. `{{service}}` above) is a **custom token** — prompts at run time.
6. Description (optional).
7. Save.

### Pinning to a session

- Snippet manager → row → pin icon → choose target session(s). Pinned snippets float to the top of the picker on that session.

### Running

1. In a terminal: right-click → **Snippets**, or the snippets icon in the toolbar.
2. Picker dialog lists pinned (top) + all snippets (below).
3. Tap a snippet:
   - All built-in tokens resolved? Command goes straight to the shell.
   - Custom tokens unresolved? **"Fill in snippet parameters"** dialog opens with one field per token. Submit → command runs.

### Grammar rules (for the curious)

- Single-pass substitution. A substituted value containing `{{x}}` is taken **literally**, not re-scanned.
- `{{{{` is the escape for a literal `{{` in the output.
- Empty `{{}}` is left literal (treated as a typo, not a sentinel).
- Unterminated `{{` is copied verbatim — no data loss on malformed input.
- No shell escaping of substituted values. Same contract as `~/.ssh/config` `%h`/`%p`/`%u`.

---

## 9. Broadcast input across split panes

Type once, send to many panes. Desktop-only.

### Setting it up

1. Split a terminal into multiple panes (`Ctrl+\` / `Ctrl+Shift+\`).
2. **Driver pane** (the source): right-click → **"Broadcast from this pane"**. The pane border turns yellow + thick.
3. **Receiver panes**: right-click → **"Receive broadcast here"** on each. Their borders turn yellow + thin.
4. Type in the driver. Every keystroke (including arrow keys, Ctrl-sequences) replays on every receiver.

### Paste guard

- `Ctrl+Shift+V` in the driver pane while broadcast is active → modal: "Send N characters to M panes?"
- Confirm to send; cancel to abort. Prevents accidentally pasting an SSH key / password into 8 servers.

### Stopping

- Right-click any participating pane → **"Stop all broadcasting"**. Or toggle individual receivers off via the same context menu.

### Mobile

- Mobile has no split panes → no broadcast. The context-menu entries are hidden.

---

## 10. Session recording + playback

Per-session terminal output + input capture, encrypted at rest, playable in-app or exportable.

### Enabling per session

1. Edit the session.
2. **Options** tab → toggle **"Record session"** ON.
3. Save → connect → recording starts automatically.
4. Each shell channel records to its own file (multi-pane connections produce one file per pane).

### File location

| Platform | Path |
|---|---|
| Linux | `~/.local/share/letsflutssh/recordings/<sessionId>/<isoTimestamp>.<lfsr|cast>` |
| macOS | `~/Library/Application Support/letsflutssh/recordings/...` |
| Windows | `%APPDATA%\letsflutssh\recordings\...` |
| Android | App sandbox via `getApplicationSupportDirectory()` |
| iOS | App sandbox via `getApplicationSupportDirectory()` |

### Two formats

- **`.lfsr`** — encrypted (when running on T1/T2/Paranoid tier). Recording key derived from your DB encryption key via HKDF-SHA-256 with info-tag `letsflutssh-recording-v1`. Per-event AES-256-GCM frames so a truncated tail loses one event, not the whole file.
- **`.cast`** — plaintext asciinema v2 (when running on T0 plaintext tier — you opted out of crypto). Directly playable by `asciinema play file.cast`.

### Browsing + replay

1. **Tools → Recordings**.
2. List sorted by date (newest first). Each row shows session label, timestamp, duration, file size, encrypted/plain badge.
3. Tap **Play** → modal opens with embedded xterm replay.
4. **Speed dropdown:** `1×` / `2×` / `4×` / **Instant** (jump to final frame).
5. **Trash** on a row → delete the file.

### Notes

- **Quick-connect sessions don't record** — they have no stable session id, so the recorder skips.
- **Recorder failure is best-effort** — disk full, permissions, etc. log a warning and the connect proceeds without recording.
- **Auto-rotation** at 100 MB per file; the next event opens a fresh file under the same session.
- **No scrub bar yet** — sequential GCM-frame stream means seeking would need an index file. Use the Instant speed for fast-forward.

### External playback (advanced)

- `.cast` files are valid asciinema v2 — `asciinema play <path>` works on any platform.
- `.lfsr` files require the app's HKDF derivation; no out-of-app player today.

---

## 11. SSH key manager + PuTTY `.ppk` import

Centralised key store so a single key can be referenced from many sessions.

### Importing a key

1. **Tools → SSH Keys → Import**.
2. File picker. Supported formats:
   - **OpenSSH** (`-----BEGIN OPENSSH PRIVATE KEY-----`).
   - **PKCS#1** (`-----BEGIN RSA PRIVATE KEY-----`).
   - **PKCS#8** (`-----BEGIN PRIVATE KEY-----` / `-----BEGIN ENCRYPTED PRIVATE KEY-----`).
   - **PuTTY `.ppk`** v2 + v3, ssh-ed25519 + ssh-rsa, encrypted + unencrypted (auto-detected; encrypted prompts for passphrase).
3. Pick a label.
4. Save → key encrypted in the DB (per security tier).

### Using a key from the manager

- Session edit → Auth tab → **Key from manager** dropdown → pick the imported key.

### Generating a key inside the app

- Tools → SSH Keys → "Generate". Pick algorithm (Ed25519 recommended). Optional passphrase.
- Public-key blob is shown for copy-paste into the server's `~/.ssh/authorized_keys`.

### Exporting a key

- Right-click a key → Export → file picker. Saves as OpenSSH PEM.

### `.ppk` quirks

- v3 files use Argon2id KDF — derivation is CPU-bound (deliberately). The first import of a v3 file may take a second or two while pointycastle runs Argon2.
- Memory-cost cap: 1 GiB. Files asking for more (crafted DoS payloads) are rejected with a targeted error.

---

## 12. Tags

Color-coded labels for sessions and folders.

### Creating a tag

- **Tools → Tags → Add**. Name + colour picker.

### Assigning

- Session edit → **Options** tab → Tags row → "Manage tags" → check / uncheck.
- Folders: right-click folder → "Edit Tags".

### Visualisation

- Tag dots appear next to the session label in the tree.
- Multiple tags → multiple dots, ordered by tag's row in the manager.

### Filtering

- Sidebar search supports plain text only today; per-tag filtering is on the backlog.

---

## 13. Known hosts (TOFU)

The app verifies SSH host keys via Trust-On-First-Use, the same model OpenSSH uses with `~/.ssh/known_hosts`.

### First connect to a new host

- Modal: "Unknown host key for `host:port`. Type: `ssh-ed25519`. Fingerprint: `SHA256:…`. Accept this key?"
- **Accept** → key saved to `KnownHosts` table; subsequent connects to the same host:port silently match.
- **Reject** → connect aborts.

### Host key changed

- Modal: "**Host key changed!** This may indicate a server reinstall, or a man-in-the-middle attack."
- Two options: **Update** (overwrite the saved key) or **Cancel** (refuse to connect).
- Don't update unless you are certain the server was rotated by the legitimate operator.

### Browsing / clearing

- **Tools → Known Hosts**.
- Search by host. Per-row delete to forget a single host. Bulk delete via multi-select.

### Importing

- Tools → Known Hosts → Import → pick a known-hosts text file. Both formats are parsed transparently — the importer detects per line:
  - **LetsFLUTssh internal** (`host:port keytype base64key`) — what `exportToString` emits for `.lfs` archive round-trips.
  - **OpenSSH `~/.ssh/known_hosts`** — what your shell has built up over years. Supported variants:
    - bare hostname `example.com keytype base64` → port 22
    - bracketed non-default port `[example.com]:2222 keytype base64`
    - bracketed IPv6 `[::1]:22` / `[fe80::1]:8022`
    - comma-separated multi-host `host1,host2,1.2.3.4 keytype base64` (one entry per host)
    - leading `@cert-authority` / `@revoked` markers are stripped (we don't honour OpenSSH cert chains today; the row imports as a normal entry)
- **Skipped:** hashed entries (`|1|salt|hash` from `HashKnownHosts yes`). HMAC-SHA1 hostname hashes are one-way; nothing to match against on subsequent connects. The importer counts skipped rows and surfaces them in the log.

### Sync caveat

- `KnownHosts` is **not** synced across devices via the export / import path or the (forthcoming) WebDAV sync. TOFU is per-device by design — auto-trusting hosts you've never personally connected to defeats the model.

---

## 14. Security tiers

How the app protects credentials at rest. First launch auto-selects **T1 — Keychain** silently when the OS keychain is reachable (typical on every supported platform). The tier-picker wizard only renders when the keychain is unreachable — it offers T0 / Paranoid plus T2 (hardware) when a TPM 2.0 / Secure Enclave / StrongBox is also detected. T2 and the modifiers (master password, biometric) are opt-in any time via **Settings → Security** even when first-launch auto-applied T1.

### The tiers

| Tier | Where the DB-encryption key lives | Notes |
|---|---|---|
| **T0 — Plaintext** | Nowhere — DB itself is unencrypted | App still uses SQLite3MultipleCiphers in-process; just no key. Use only when you have full-disk encryption + accept the trade-off. |
| **T1 — Keychain** | OS keychain via `flutter_secure_storage` (macOS Keychain, iOS Keychain, Linux libsecret — `gnome-keyring` / KWallet, Windows Credential Manager, Android EncryptedSharedPreferences) | Strongest "no master password to remember" option on most desktops. |
| **T2 — Hardware** | Hardware-bound key in TPM 2.0 (Linux/Windows), Secure Enclave (macOS/iOS), StrongBox (Android) | Needs hardware. App detects + offers when available. |
| **Paranoid** | Argon2id-derived from a master password you type every launch | Nothing on disk except the salt + verifier. Lose the password = lose the data. |

### Modifiers (orthogonal, T1/T2 only)

- **Master password gate** — adds a pre-vault password check (HMAC of input vs stored verifier). The keychain/hardware key is only released after the gate passes. Defends against "attacker has filesystem access but not your password".
- **Biometric shortcut** — FaceID / TouchID / Windows Hello / fingerprint reader / fprintd. Releases the *stored* master password automatically. **Never a replacement for the password — only an OS-mediated way to enter it.** If biometrics fail, you fall back to typing.

### Switching tiers

- Settings → Security → tier card → "Change tier".
- Re-encrypts the DB atomically (`PRAGMA rekey`) before flipping the in-memory key. If anything fails mid-way, the on-disk DB stays at the previous tier — no data loss.

### Auto-lock

- Settings → Security → Auto-lock after N minutes of inactivity. On lock, the in-memory DB key is zeroed and the lock screen appears. Re-unlocking re-derives / re-fetches.

### Threat model + design rationale

In [`SECURITY.md`](SECURITY.md). Read it before deploying in environments where the device is not under your sole physical control.

---

## 15. Import / export

### Export to encrypted `.lfs` archive

1. Settings → Data → **Export → Encrypted archive**.
2. Pick what to include (sessions, keys, tags, snippets, known hosts, config).
3. Set an export passphrase (Argon2id-derived). **This passphrase is independent of your master password** — anyone with the archive needs both.
4. Save the `.lfs` file.

### Export to QR

1. Right-click a session → Export → QR.
2. Modal shows a scannable QR. For larger payloads (full backups), use the encrypted archive instead — QR caps around 2 KB compressed.

### Export to share link

1. Right-click → Export → Copy link.
2. Sends a `letsflutssh://` deep link via the clipboard. Recipient pastes it into Settings → Data → Import → "From link".

### Import from `.lfs`

1. Settings → Data → **Import → Encrypted archive**.
2. Pick file, type passphrase.
3. **Preview dialog** lists what's in the archive (sessions / keys / tags / etc.).
4. Choose **Merge** (additive, ID conflicts mint a fresh UUID) or **Replace** (wipe + insert). Replace is destructive and gated behind a confirm.

### Import from OpenSSH config

- Settings → Data → **Import → SSH config** → file picker. Parses `~/.ssh/config` into sessions.
- Wildcard / glob hosts are skipped.
- IdentityFile paths are imported only when the file exists; otherwise the session is created with blank credentials and noted as "missing key".

### Import from `~/.ssh` directory

- Settings → Data → **Import → ~/.ssh keys**. Scans for `id_*` (and similar) and surfaces them for selection.
- Duplicates (by SHA-256 fingerprint) are silently skipped.

### Import from QR

- Settings → Data → Import → QR scanner (Android via CameraX + ZXing, iOS via AVFoundation — no Google Play Services / MLKit).

### Reset all data

- Settings → Data → **Reset All Data** → confirm.
- Wipes the DB, credential store, keychain entries, hardware-vault sealed blobs, biometric overlay, logs. Returns the app to first-launch state.

---

## 16. Updates

- Settings → Updates → **Check for updates**.
- Optional **Check on startup** toggle (default on).
- Found a new version → modal with release notes + Skip / Open in Browser / Download & Install.
- Download → SHA-256 verify → Ed25519-signature verify → installer launch (Windows MSI / Linux .deb) or "Open release page" fallback.
- Install signature key is bundled with the app; an attacker would need to either (a) compromise the GitHub Releases CDN AND have access to the signing key, or (b) ship a malicious update that's CSP-pinned by the build itself.

---

## 17. Mobile differences

| Feature | Android | iOS | Notes |
|---|---|---|---|
| All session CRUD | ✅ | ✅ | Same DB, same security tiers. |
| Terminal | ✅ | ✅ | Virtual keyboard with Esc / Tab / Ctrl / Alt / arrows / F1-F12. Pinch-to-zoom disabled (caused reflow churn) — use the font slider in Settings. |
| SFTP | ✅ | ✅ | iOS sandbox starts in app's Documents folder (visible in Files.app). Android starts in `/storage/emulated/0` if granted access. |
| Snippets | ✅ | ✅ | Picker reachable from the SSH keyboard bar. |
| Tags | ✅ | ✅ | |
| Tools (SSH Keys / Snippets / Tags / Known Hosts / Recordings) | ✅ list view | ✅ list view | Desktop uses a sidebar layout; mobile uses a tile list inside `ToolsScreen`. |
| ProxyJump | ✅ | ✅ | |
| `-L` Local forward | ✅ | ⚠️ background-limited | iOS kills sockets after ~30 s in background; foreground works fine. |
| `-R` Remote forward | ✅ | ✅ | Server-side listener; client backgrounding doesn't break it. |
| `-D` Dynamic SOCKS5 | ✅ | ⚠️ background-limited | Same as `-L`. |
| Session recording | ✅ | ✅ | App-sandbox storage. |
| Recording playback | ✅ | ✅ | |
| `.ppk` import | ✅ | ✅ | File picker. |
| QR scan | ✅ | ✅ | CameraX (Android) / AVFoundation (iOS). |
| Deep links | ✅ | ✅ | `letsflutssh://` URI scheme. |
| Splits / broadcast | ❌ | ❌ | No tiling on mobile. |
| Drag & drop | partial | partial | Sessions can be reordered; SFTP drag-drop works in-pane only. |
| Foreground service | ✅ | n/a | Android keeps the SSH connection alive in background via a foreground notification while ≥ 1 connection is active. |

### iOS background caveat

Apple disallows long-lived sockets in background for non-VoIP / non-audio apps. SSH connections + their listeners (`-L`/`-D`) are throttled when the app is suspended. Best practice: keep the app foregrounded for the duration of the work, or accept that tunnels reset on resume.

### Android battery-optimisation

The foreground service notification can be muted by aggressive OEM battery managers (Xiaomi, Huawei, OnePlus). If your tunnels die in background despite the notification: Settings → battery → Don't optimise → LetsFLUTssh.

---

## 18. Troubleshooting

### "Bastion failed to connect (caused by: bastion not connected)"

Race we already fixed — make sure you're on the latest build. If it persists with a fresh app, the actual cause is in the toast subtitle (e.g. wrong bastion creds, network unreachable).

### "PPK MAC mismatch — wrong passphrase or corrupt file"

For an encrypted PPK, the MAC verification doubles as a passphrase check. Wrong passphrase + corrupt file are indistinguishable at this layer (PPK v2's encryption is malleable). Re-enter the passphrase carefully; if you're sure it's right, the file may genuinely be corrupt.

### "Server refused remote forward on `host:port`"

The SSH server's `sshd_config` has `GatewayPorts no` (default) and you tried to bind on `0.0.0.0`. Either (a) ask the server admin to enable `GatewayPorts yes`, or (b) bind on `localhost` from the app instead.

### Recording file won't play

`.lfsr` files only decrypt with the same DB key that wrote them. If you switched tiers / reset the app since recording, the key is gone — the file is unrecoverable. Recording browser shows files even when meta can't be decoded so you can delete them.

### Auto-lock keeps tripping

Settings → Security → Auto-lock minutes. Set to 0 to disable.

### Logs

- App writes to `<appSupport>/logs/letsflutssh.log` (off by default).
- Settings → Logging → enable + set threshold (`info` / `warn` / `error`).
- Sanitised: PEM bodies, IPs, `user@host`, paths get redacted before the line hits disk.

### Reporting bugs

- GitHub Issues. Include the build version (Settings → About) + the relevant log slice (sanitised; double-check no remaining secrets before pasting).
- Security issues: see [SECURITY.md → Reporting](SECURITY.md#reporting-a-vulnerability) — don't open a public issue.
