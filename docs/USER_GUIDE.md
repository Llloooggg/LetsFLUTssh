# LetsFLUTssh User Guide

## Quick Start

1. Launch the app
2. Click **+** (or press `Ctrl+N`) to open Quick Connect
3. Enter host, username, and password (or select a key file)
4. Click **Connect** — a terminal tab opens

## Connecting

### Quick Connect

Press `Ctrl+N` or click the **+** button in the toolbar. Fill in:
- **Host** — server hostname or IP
- **Port** — SSH port (default 22)
- **Username** — SSH user
- **Password** — or use **Key File** / paste PEM text

### Saved Sessions

Create saved sessions for servers you connect to regularly:

1. Right-click in the session panel → **New Session**
2. Fill in connection details and authentication
3. Click **Create**

**Connect:** Double-click a session, or right-click → **SSH Connect**
**SFTP only:** Right-click → **SFTP Only** to open a file browser without a terminal

### Authentication Methods

| Method | How to configure |
|--------|-----------------|
| Password | Enter in the Password field |
| Key file | Click browse or drag a `.pem`/`.key` file onto the key field |
| PEM text | Toggle "Paste PEM" and paste your private key |
| Key + passphrase | Provide both key and passphrase |
| Auto-detect | Leave key fields empty — app tries `~/.ssh/id_ed25519`, `id_ecdsa`, `id_rsa`, `id_dsa` |

### Host Key Verification

On first connection to a new server, a dialog shows the server's fingerprint (SHA256). You must **Accept** to continue. If a server's key changes, a MITM warning is shown — only accept if you know the key was legitimately changed.

## Session Manager

### Groups

Organize sessions into nested folders using `/` paths:
- `Production/Web/nginx1`
- `Production/DB/master`
- `Staging`

Right-click empty space → **New Folder** to create groups.

### Search

Type in the search bar to filter sessions by label, group, host, or username.

### Context Menu (right-click)

- **SSH Connect** — open terminal
- **SFTP Only** — open file browser
- **Edit** — modify session details
- **Duplicate** — create a copy
- **Delete** — remove session

## Terminal

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+N` | Quick Connect |
| `Ctrl+W` | Close current tab |
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |
| `Ctrl+Shift+F` | Search terminal |
| `Ctrl+Shift+C` | Copy selection |
| `Ctrl+Shift+V` | Paste |
| `Ctrl+Shift+D` | Split pane right |
| `Ctrl+Shift+E` | Split pane down |
| `Ctrl+Shift+W` | Close pane |

### Tiling Layout

Split the terminal into multiple panes (like tmux):

- Right-click → **Split Right** or **Split Down**
- Or use `Ctrl+Shift+D` / `Ctrl+Shift+E`
- Drag the divider between panes to resize
- Click a pane to focus it (blue border)
- Each pane runs its own shell on the same SSH connection

### Terminal Search

Press `Ctrl+Shift+F` to search the scrollback buffer. Use arrows to navigate matches. Press `Esc` to close.

## SFTP File Browser

### Layout

- **Left pane** — local filesystem
- **Right pane** — remote filesystem (SSH server)

### Navigation

- Click a directory to enter it
- Click the path bar to type a path directly
- Use **Back/Forward/Up** buttons for navigation history

### File Operations

| Action | How |
|--------|-----|
| **Transfer** | Drag files between panes, or right-click → Upload/Download |
| **New folder** | Right-click → New Folder |
| **Rename** | Right-click → Rename |
| **Delete** | Select files → press `Del`, or right-click → Delete |
| **Multi-select** | `Ctrl+click` individual files, or rubber-band select with mouse |

### Transfer Progress

Active transfers appear in the bottom panel. Click to expand/collapse. History shows completed and failed transfers with timing and error details.

## Settings

Open via the gear icon in the toolbar, or on mobile via the Sessions tab.

| Setting | Description |
|---------|-------------|
| Theme | Dark / Light / System |
| Font size | Terminal font size (default 14) |
| Scrollback | Max terminal lines (default 5000) |
| Keep-alive | Interval in seconds (default 30) |
| SSH timeout | Connection timeout (default 10s) |
| Default port | Default SSH port (default 22) |
| Transfer workers | Parallel transfer count (default 2) |
| Max history | Transfer history entries (default 100) |

### Export / Import

**Export:** Settings → Export Data → set master password → saves `.lfs` file
**Import:** Settings → Import Data → select `.lfs` file → enter password → choose Merge or Replace

- **Merge** — adds new sessions, keeps existing
- **Replace** — deletes all existing, imports fresh

You can also drag a `.lfs` file onto the app window to import.

## Mobile

### Navigation

Swipe left/right or tap the bottom bar to switch between:
- **Sessions** — session list, settings access, Quick Connect (+)
- **Terminal** — active terminal sessions
- **Files** — active SFTP browsers

### SSH Virtual Keyboard

Below the terminal, a keyboard bar provides special keys:
- **Esc**, **Tab**, **Ctrl**, **Alt** — tap to send once, double-tap to lock (sticky)
- **Arrow keys** — navigation
- **F1-F12** — function keys
- **|**, **~**, **-**, **/** — common SSH characters

### Terminal

- **Pinch to zoom** — adjust font size (8-24pt)
- **Long press** — copy/paste context menu

### SFTP

- **Tap Local/Remote** to switch filesystem view
- **Long press** files to enter selection mode
- **Bottom sheet** for actions on selected files

## Deep Links

Open connections via URL:

```
letsflutssh://connect?host=myserver.com&port=22&user=admin
```

Parameters: `host` (required), `user` (required), `port`, `password`, `key`

## Security Notes

- Credentials are encrypted with AES-256-GCM in a separate file from session metadata
- The encryption key is stored locally — this protects against casual file access but not a determined attacker with full filesystem access
- Export archives use PBKDF2-SHA256 (600k iterations) key derivation — use a strong master password
- Host key verification requires explicit user acceptance (no auto-trust)
- Session metadata (hosts, usernames, groups) is stored in plaintext JSON
- For maximum security, use key-based authentication instead of passwords
