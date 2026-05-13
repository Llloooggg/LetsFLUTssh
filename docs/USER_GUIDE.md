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
- [5b. WebDAV file browser](#5b-webdav-file-browser)
- [5c. S3 bucket browser](#5c-s3-bucket-browser)
- [6. Port forwarding](#6-port-forwarding)
- [7. ProxyJump bastion chains](#7-proxyjump-bastion-chains)
- [8. Snippets with `{{tokens}}`](#8-snippets-with-tokens)
- [9. Session recording + playback](#9-session-recording--playback)
- [10. SSH key manager + PuTTY `.ppk` import](#10-ssh-key-manager--putty-ppk-import)
- [11. Tags](#11-tags)
- [12. Known hosts (TOFU)](#12-known-hosts-tofu)
- [13. Security tiers](#13-security-tiers)
- [14. Import / export](#14-import--export)
- [14b. Sync via WebDAV](#14b-sync-via-webdav)
- [15. Updates](#15-updates)
- [16. Mobile differences](#16-mobile-differences)
- [17. Troubleshooting](#17-troubleshooting)

---

## 1. First launch

1. Install per [README → Installation](../README.md#installation).
2. App opens to the **Sessions** sidebar (empty) and a **Welcome** placeholder in the main area.
3. **Security tier is set up silently on the first launch** (see [§13 Security tiers](#13-security-tiers)). When the OS keychain is reachable (the common case on every supported platform), the app auto-selects **T1 — Keychain** without prompting, and surfaces a one-shot banner saying so. Only when the keychain is unreachable (e.g. Linux without `gnome-keyring` / KWallet, ad-hoc-signed macOS without an installed signing identity) does a tier-picker wizard appear with T0 / Paranoid as alternatives. T2 hardware-bound and any of the modifiers (master password, biometric shortcut) are opt-in via **Settings → Security** at any time.
4. **Add your first session:** sidebar → "+" or `Ctrl+N`. Fill host / port / username + auth (password or key). Save.
5. **Connect:** double-click the session, or right-click → Terminal / Files.

---

## 2. Sessions

### Creating

- **Sidebar → "+"** or `Ctrl+N` → Session edit dialog.
- **Tabs:** Connection / Auth / Options / Forwarding.
- **Connection tab:** name, host, port, username, plus the [Connect via](#7-proxyjump-bastion-chains) selector at the bottom.
- **Auth tab:** [§3 Authentication](#3-authentication).
- **Options tab:** tags, [Record session toggle](#9-session-recording--playback).
- **Forwarding tab:** [§6 Port forwarding](#6-port-forwarding).
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

---

## 3. Authentication

The Auth tab in the session edit dialog supports five modes; you fill in the parts that apply.

### Password

- Single field. Stored encrypted at rest (per security tier).
- "Show password" eye icon temporarily reveals.

### Key from file

- "Select Key File" → file picker. Path is stored; the bytes are read on connect.
- `~` / `~/...` paths are supported on desktop (expanded against `$HOME`).

### Key from manager

- Drop-down references a key already imported via Tools → SSH Keys (see [§10](#10-ssh-key-manager--putty-ppk-import)).
- Preferred over file paths for portability — the key travels with the session via export/import.
- Each row carries a backend badge — "Hardware-bound (FIDO2)" for sk-* keys, "Smart card / token" for PKCS#11, "Secure Enclave" / "Windows Hello" / "TPM 2.0" / "Android Keystore" for the platform-bound variants. Software keys carry no badge. The visual matches the standalone key manager so switching between the two surfaces does not require re-learning which row is which.

### PEM key text

- Paste the private-key body (`-----BEGIN OPENSSH PRIVATE KEY-----` … or PKCS#1/PKCS#8 PEM).
- Used for one-off keys you don't want to save to disk.

### System ssh-agent

- "Use system ssh-agent" toggle at the top of the Auth tab. Defers every signature to a running ssh-agent on this machine — `$SSH_AUTH_SOCK` on Linux / macOS, the OpenSSH named pipe `\\.\pipe\openssh-ssh-agent` (or Pageant) on Windows.
- No key / passphrase / password slot has to be filled — the agent owns the credential. Selecting the toggle collapses the rest of the Auth tab.
- Useful if you already keep your keys in `gpg-agent`, Pageant, KeePassXC's SSH-agent integration, or a system ssh-agent, and you don't want a second copy living inside the app.
- Desktop-only — Android / iOS have no system ssh-agent equivalent to dial, so the toggle renders disabled with a tooltip explaining why. This is distinct from the **outgoing** agent endpoint the app exposes for other tools (see [§10b](#10b-using-hardware-bound-keys-outside-the-app)) — this toggle makes the app a **client** of the existing agent, not a server.

### Passphrase

- Required for any key type that's encrypted. If left empty and the key is encrypted, you'll be prompted at connect time and can opt to remember for the session.

### Combining password + key

- Both fields filled — the auth chain takes the **key** branch and uses the typed passphrase to decrypt it. The typed password is **not** sent as a separate fallback; SSH "key + password" two-factor flows are not currently implemented.

### Encrypted PEM detection

- Detection is automatic at import time. The auth chain handles legacy PKCS#1 (`Proc-Type: 4,ENCRYPTED` + `DEK-Info` headers), PKCS#8 encrypted (`-----BEGIN ENCRYPTED PRIVATE KEY-----`), and modern OpenSSH KDF-encrypted (`-----BEGIN OPENSSH PRIVATE KEY-----` with a non-`none` KDF in the binary frame) uniformly.
- If the key is encrypted and you didn't supply a passphrase up front, Tools → SSH Keys / Session edit → Auth tab prompts for one before saving. On connect the same prompt fires for any key whose passphrase is not stored.

### Hardware key (FIDO2 `sk-*`)

OpenSSH supports `sk-ssh-ed25519@openssh.com` and `sk-ecdsa-sha2-nistp256@openssh.com` keys whose private half lives on a hardware authenticator (YubiKey, SoloKey, Titan, Feitian, Nitrokey, Trezor, or the platform Hello / StrongBox passkey). The app speaks to the device through one of two transports depending on the platform:

- **OS security-key dialog** — the system's built-in flow. Windows shows the Windows Hello / security-key prompt; macOS shows the system security-key dialog; iOS shows the system NFC + USB dialog; Android shows the Credential Manager picker. Handles USB / NFC / BLE transparently and works without admin permission grants.
- **Direct USB HID** — the in-process CTAP2 transport. Linux uses it exclusively (no broker exists); Windows / macOS keep it as a fallback when the OS dialog is not available, and as an opt-in path for advanced users via Settings.

1. Generate the key with `ssh-keygen` on the host where you want to install the `authorized_keys` entry:
   - `ssh-keygen -t ed25519-sk -O resident -O application=ssh: -f ~/.ssh/id_ed25519_sk`
   - For PIN-required (user verification): add `-O verify-required`.
2. Copy the matching `~/.ssh/id_ed25519_sk.pub` to the server's `~/.ssh/authorized_keys`.
3. In the app: **Tools → SSH Keys → Import hardware key (sk-*)**. Pick the private file (`id_ed25519_sk`, not `.pub`). The row shows the "Hardware-bound (FIDO2)" badge once imported.
4. Reference the key from a session's **Auth → Key from manager** drop-down.
5. On connect:
   - **Windows** — the standard Windows Hello / security-key prompt opens. Tap the metal contact when the device asks; type the PIN when prompted; the OS handles everything.
   - **macOS** — the system security-key dialog opens. Same flow: tap, PIN if required.
   - **iOS** — the system dialog asks to "Use security key" and surfaces a USB + NFC chooser; hold the key flat against the back of the device for NFC, or plug it in for USB.
   - **Android** — the Credential Manager picker fires; pick the key, tap, enter the PIN if required. Works for USB-host, NFC, BLE, and the on-device StrongBox passkey.
   - **Linux** (and Windows / macOS when the toggle below is on) — the app shows its own "Tap your hardware key" dialog if the credential was generated with `verify-required` (collects the PIN first); touch-only credentials skip the dialog. Then the device LED starts blinking — tap the metal contact.

The signing path is in-process even when the OS dialog drives the UX: every userauth challenge SHA-256-hashes the SSH packet, asks the device for an assertion against the credential id captured at import, and assembles the `sk-*` signature trailer. Private key material never leaves the authenticator; `ssh-agent` is not involved.

**Paired OpenSSH certificate.** If you've imported an OpenSSH user certificate (`-cert.pub`) and paired it with this hardware key through **Tools → SSH Keys → Import certificate**, the cert is presented automatically when the session connects — the app sends the cert-form algorithm (`sk-ssh-ed25519-cert-v01@openssh.com` / `sk-ecdsa-sha2-nistp256-cert-v01@openssh.com`) instead of the bare public key, and the server validates the CA signature via its `TrustedUserCAKeys`. Same touch / PIN UX as the bare-key path; the device signs the cert-form userauth payload through the same CTAP2 round trip.

**Settings → Hardware security keys → "Prefer direct USB HID over system dialog"** lets advanced users bypass the OS dialog on Windows and macOS, falling through to the in-app CTAP2 path. Off by default. On Linux the toggle is disabled (no broker exists); on iOS and Android it is disabled (no HID fallback exists). Direct HID exposes more authenticator features (hmac-secret, large-blob, credBlob — none of which SSH consumes today) but requires per-app permission grants (`udev` rules on Linux, HID class access on Windows).

**Platform availability**

| Platform | Default transport | Notes |
|---|---|---|
| Linux | Direct USB HID via `hidraw` | Install `70-letsflutssh-fido.rules` (see below) |
| Windows 10 1903+ | OS security-key dialog (WebAuthn) | Direct HID fallback available; opt-in via Settings |
| macOS 12+ | OS security-key dialog (ASAuthorization) | Direct HID fallback available; opt-in via Settings. Self-signed dev builds without the Apple Developer Program entitlement skip the dialog and use direct HID |
| iOS 15.5+ | OS security-key dialog (USB + NFC) | Broker only; no HID fallback exists |
| Android | Credential Manager (USB / NFC / BLE / StrongBox passkey) | Broker only; no HID fallback exists |

**Linux: install the udev rules**

`/dev/hidraw*` defaults to `root:root 0600`. Install the bundled rules to grant the seat-owning user passthrough:

```bash
sudo cp /usr/share/letsflutssh/udev/70-letsflutssh-fido.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

The rules cover Yubico (1050), STMicroelectronics (0483, SoloKey), Feitian (096e), Trezor (1209/53c1), Nitrokey (20a0), Google Titan (18d1), and OpenMoko (1d50, OnlyKey + assorted FIDO2 firmware).

### Hardware key (PKCS#11 smart cards and tokens)

LetsFLUTssh supports smart cards and hardware tokens that speak the PKCS#11 (Cryptoki) standard. Coverage includes:

- **JaCarta** (Aladdin / Aladdin R.D.) — corp-segment Russia / CIS.
- **Рутокен** (Rutoken ECP / ECP2 / Lite series) — corp-segment Russia / CIS.
- **eToken / SafeNet** — global enterprise.
- **YubiKey PIV applet** (alternative to the FIDO2 path; uses the on-card PIV slots).
- **OpenPGP card** (Nitrokey Pro / Storage, ZeitControl OpenPGP card, Yubikey OpenPGP applet).
- **Estonian ID / Finnish HST / German eIDAS smartcards** via OpenSC.
- **Thales Luna network HSM** — enterprise HSMs.
- **AWS CloudHSM** — Cloud HSM client.

The private key never leaves the token; every connect-time signature routes through the vendor's `dlopen`'d library into `C_Sign`. Imported PKCS#11 keys also surface through the in-process ssh-agent (see [§10b](#10b-using-hardware-bound-keys-outside-the-app)) so `git`, `ssh`, IDE plugins can use them.

1. Install the vendor driver:
   - **Linux** — `apt-get install opensc` (OpenPGP card, PIV applets, eID), `apt-get install pcscd` + add yourself to the `scard` or `pcscd` group for reader access. JaCarta / Рутокен / eToken: install the vendor's `.deb` / `.rpm` (Aladdin JaCarta drivers, Rutoken SDK, SafeNet Authentication Client). Restart the session after group changes.
   - **Windows** — vendor installer (JaCarta Unified Client, Rutoken Driver, SafeNet Authentication Client, YubiKey Manager + PIV Tool, OpenSC for OpenPGP card / eID).
   - **macOS** — `brew install opensc` or vendor `.pkg`. The macOS hardened-runtime may block unsigned vendor `.dylib`s; if the picker reports "module did not initialise" right after install, open **System Settings → Privacy & Security**, scroll down, click **Allow** next to the blocked library, then re-try.
2. Plug the token / insert the smart card.
3. In the app: **Tools → SSH Keys → Add smart-card / token key**. The wizard's first step shows every well-known vendor library it found on disk; pick one (or use **Custom...** to browse for a vendor library at a non-standard path). Each row carries a status dot — **green** = the module loaded and a token is present, **amber** = module loaded but no token in any reader, **red** = the library failed to initialise (vendor driver missing / blocked).
4. Step two lists tokens present in the chosen module. The row shows the manufacturer, model, serial number, and any warnings (PIN-final-try, PIN-locked). Tokens with a built-in PIN pad show "(PIN pad on device)" instead of asking for a PIN here.
5. Step three asks for the PIN (skipped for PIN-pad tokens and for tokens that do not require login). Wrong PINs surface the remaining-tries counter the token reports; **don't keep trying** when "1 try left" appears — the next failure locks the card and recovery requires the SO-PIN / PUK from your administrator.
6. Step four lists every SSH-usable key on the token (RSA, ECDSA P-256 / P-384 / P-521, Ed25519). GOST-only keys show disabled with the "GOST cannot be used with SSH" reason. Pick the row you want and confirm.
7. Step five — confirm the label (defaults to the on-token object label) and tap **Import key**. The imported key appears in the SSH Keys list with the **Smart card / token** badge; tap the badge to see the captured module path, token serial, and object label.
8. Reference the key from a session's **Auth → Key from manager** drop-down. On connect the app asks for the PIN once per connect attempt (or fires the PIN-pad prompt on protected-authentication-path tokens).

**Platform availability**

| Platform | Status |
|---|---|
| Linux | Supported. Install `pcscd` + the vendor driver. |
| Windows | Supported. Vendor DLLs install with vendor drivers. |
| macOS | Supported. Hardened-runtime / Library Validation may block unsigned vendor `.dylib`; allow once in System Settings → Privacy & Security. |
| Android | Disabled — no compatible vendor `.so` ABI on Android. |
| iOS | Disabled — the sandbox forbids `dlopen` of arbitrary `.dylib`. |

**Network HSM caveats.** Thales Luna and AWS CloudHSM both require their respective clients to be pre-configured (`/etc/Chrystoki.conf` for Luna, `/etc/cloudhsm/cloudhsm.cfg` for CloudHSM). LetsFLUTssh's UI does not ship a configuration surface for those clients — set them up per the vendor's documentation first, then point the picker at the resulting `.so` (`libCryptoki2_64.so` or `libcloudhsm_pkcs11.so`).

**GOST keys.** PKCS#11 supports `CKK_GOSTR3410` for state-sector cryptography. SSH has no GOST wire suite, so the picker shows GOST keys but disables them with the "GOST cannot be used with SSH" reason. JaCarta / Рутокен tokens that hold both an RSA / ECDSA key (for SSH) and a GOST key (for state-portal auth) work fine — the import picks the SSH-usable one and ignores the GOST sibling.

### Hardware key (Apple Secure Enclave)

On macOS (Apple Silicon or T2 Intel) and iOS, LetsFLUTssh can generate SSH keys whose private half lives on the Secure Enclave coprocessor — the same silicon that backs Touch ID / Face ID. The chip refuses to export the private bytes; every connect-time signature routes through `SecKeyCreateSignature`, and the OS fires a biometric / passcode prompt at the call boundary.

- **Algorithm.** ECDSA P-256 only (`ecdsa-sha2-nistp256`). The chip implements no other curve.
- **Device-bound.** SE keys cannot be exported or copied to another device — the key works only on the Mac / iPhone that generated it.
- **Re-enrolment caveat.** When you choose **Touch ID / Face ID required** the chip ties the key to the *current* biometric template. Adding a finger or re-enrolling Face ID invalidates the key; you must re-generate. Choose **Allow device passcode as fallback** if you need biometric re-enrolment to survive.

#### Generating a key

1. **Tools → SSH Keys → Add hardware-bound key** (the row is visible only on macOS and iOS — Linux / Windows / Android hide it).
2. The wizard probes the chip. On unsigned / ad-hoc-signed dev builds the probe surfaces "App must be code-signed to use the Secure Enclave" — see the "Self-build users" note below.
3. Pick a label and an auth policy:
   - **Require Touch ID / Face ID** — strongest binding; re-enrolment invalidates the key.
   - **Allow device passcode as fallback** — survives re-enrolment; a stolen passcode unlocks every key in this class.
4. Tap **Generate**. The OS fires the biometric / passcode prompt; on success the wizard shows the `authorized_keys`-shaped public-key line with a Copy affordance.
5. Add that line to `~/.ssh/authorized_keys` on the server.
6. Reference the new row from a session's **Auth → Key from manager** drop-down. Every connect attempt fires the OS biometric / passcode prompt the first time the key is used inside the LAContext cache window (a few minutes); subsequent reconnects within that window skip the prompt.

#### Self-build users — code-signing requirement

Apple's Keychain Services refuses to bind keys to the Secure Enclave when the running binary isn't code-signed. Distributed builds (the GitHub Release artifacts) are signed and work out of the box. Self-build users running `make build-macos` against the source tree see `errSecMissingEntitlement (-34018)` on the first key-generate call.

Fix with an ad-hoc signature against the bundle:

```bash
codesign -s - --identifier com.poddeo3.letsflutssh \
    --entitlements macos/Runner/Release.entitlements \
    --deep --force \
    build/macos/Build/Products/Release/letsflutssh.app
```

Re-launch the app and re-run the wizard. The `-s -` signature is ad-hoc (no Apple identity required) but provides the stable Code Directory hash Keychain needs to bind keys.

#### Platform availability

| Platform | Status |
|---|---|
| macOS (Apple Silicon, T2 Intel) | Supported. Code-signed bundles work directly; ad-hoc-signed dev builds need the `codesign -s -` snippet above. |
| iOS | Supported. The app must be signed with a development / distribution profile (Xcode handles this automatically). |
| Intel Macs without a T2 chip | Hidden — no Secure Enclave silicon. |
| Linux / Windows / Android | Hidden — chip doesn't exist on these platforms. |

### Hardware key (Windows Hello)

On Windows 10 1607+ with Windows Hello configured, LetsFLUTssh can generate SSH keys whose private half lives in the TPM (or, on hosts without a TPM, in the Microsoft Platform Crypto Provider's software KSP fallback). The chip refuses to export the private bytes; every connect-time signature routes through `NCryptSignHash`, and Windows fires the Hello prompt — PIN, fingerprint, or face — at the call boundary.

- **Algorithms.** ECDSA P-256 (`ecdsa-sha2-nistp256`, preferred default), ECDSA P-384 (`ecdsa-sha2-nistp384`, TPM-firmware-dependent), and RSA-2048 PKCS#1 v1.5 (`rsa-sha2-256` / `rsa-sha2-512`, for older OpenSSH servers).
- **Device-bound.** Hello-bound keys cannot be exported or copied to another PC — the key works only on the Windows install that generated it.
- **Not `KeyCredentialManager`.** The wizard uses NCrypt + the Microsoft Platform Crypto Provider directly. The higher-level `KeyCredentialManager.RequestSignAsync` API produces RSA-PSS signatures that are not compatible with the SSH wire protocol — the SSH ecosystem requires PKCS#1 v1.5, which only the NCrypt path emits.

#### Generating a key

1. **Tools → SSH Keys → Windows Hello SSH key** (the row is visible only on Windows — macOS / Linux / Android hide it).
2. The wizard probes the Microsoft Platform Crypto Provider. On hosts without Windows Hello configured the probe surfaces "Configure Windows Hello first in Settings -> Sign-in options" — open the Settings app, set up a PIN as the minimum baseline, and re-run the wizard.
3. Pick a label and an algorithm:
   - **ECDSA P-256** — preferred default; smallest signature, widest TPM support.
   - **ECDSA P-384** — optional; older Infineon TPM firmware may refuse this algorithm. The wizard surfaces "TPM firmware does not support P-384" when create fails on this branch — pick P-256 or RSA-2048 instead.
   - **RSA-2048** — fallback for older OpenSSH servers that don't speak ECDSA.
4. Tap **Generate**. Windows fires the Hello prompt (PIN / fingerprint / face); on success the wizard shows the `authorized_keys`-shaped public-key line with a Copy affordance.
5. Add that line to `~/.ssh/authorized_keys` on the server.
6. Reference the new row from a session's **Auth → Key from manager** drop-down. Every connect attempt fires the Hello prompt — there is no caching layer like the Apple Secure Enclave's LAContext window. Hello is the ceremony.

#### TPM vs Software-gated

The wizard surfaces a "Software-gated" warning when the host has no TPM. The key still lands in the Microsoft Platform Crypto Provider, but the private bytes live in user-mode software rather than on-chip silicon. The Hello prompt still gates every signature, but the cryptographic strength reduces from "TPM-bound key" to "Hello-gated software key". The badge in the key manager carries the localized "Software-gated" suffix so you can tell at a glance which tier the key landed at.

#### Recovery from device loss

There is none. The private key never leaves the TPM (or PCP software KSP); the `.lfs` archive carries only the CNG persistent-key name, which only matches on the original PC. If the device is lost or wiped, re-generate the key on the replacement PC and update `authorized_keys` on the server. Hello-bound keys are deliberately device-bound — that's the security property that makes them stronger than software-only SSH keys.

#### Platform availability

| Platform | Status |
|---|---|
| Windows 10 1607+ with TPM 2.0 + Hello | Supported. Wizard surfaces "Windows Hello" enabled. |
| Windows 10 1607+ without TPM + Hello | Supported with the "Software-gated" honest-label warning — keys live in user-mode storage, Hello still gates every signature. |
| Windows + Hello not configured | Hidden in the wizard with the "Configure Windows Hello first" reason. |
| Windows < 10 1607 | Hidden — Microsoft Platform Crypto Provider is unreachable. |
| macOS / Linux / Android / iOS | Hidden — provider doesn't exist on these platforms. |

### Hardware key (TPM 2.0)

On Linux and Windows, LetsFLUTssh can generate SSH keys whose private half lives inside a TPM 2.0 chip. The chip refuses to export the private bytes; every connect-time signature routes through the TPM driver — `TPM2_Sign` on Linux via the `tss-esapi` library, `NCryptSignHash` on Windows via the Microsoft Platform Crypto Provider. The TPM SSH wizard is **not** the same as the Windows Hello wizard above — the two paths use the **opposite** UI-policy default:

- **Hello SSH keys** (above) fire a PIN / fingerprint / face prompt on **every** signature.
- **TPM SSH keys** (this section) sign **unattended** on Windows (silent variant — no prompt) and rely on a per-key PIN on Linux. Intended for headless service-account contexts where a Hello prompt is impossible (cron jobs, CI runners, deploy scripts).

Pick the wizard that matches your security ceremony:
- Need a prompt on every sign? Use the Windows Hello wizard.
- Need unattended signing under a TPM-bound key the chip will never export? Use the TPM 2.0 wizard.

#### Algorithms

| Algorithm | When to pick it |
|---|---|
| ECDSA P-256 (`ecdsa-sha2-nistp256`) | Default. Widest TPM support, smallest signature. |
| RSA-2048 (`rsa-sha2-256` / `rsa-sha2-512`) | Older OpenSSH servers that don't speak ECDSA. Generation takes 2-10 s on a typical fTPM. |
| Ed25519 | **Refused** — Ed25519 is not in the TPM 2.0 specification. The wizard surfaces the localized "Algorithm not supported by this TPM firmware" reason. |

#### Setup — Linux

1. Verify your hardware has a TPM 2.0 chip. Most consumer laptops since 2016 ship one (Microsoft Pluton, Intel PTT, AMD fTPM, or a discrete Infineon / Nuvoton chip).
2. Install the TSS2 stack:
   - **Ubuntu / Debian**: `sudo apt install tpm2-tools libtss2-dev`
   - **Fedora / RHEL**: `sudo dnf install tpm2-tools tpm2-tss-devel`
   - **Arch / Manjaro**: `sudo pacman -S tpm2-tools tpm2-tss`
3. Add your user to the `tss` group so the app can reach `/dev/tpmrm0`:
   ```
   sudo usermod -a -G tss $USER
   newgrp tss
   ```
   The `newgrp` step picks up the new group membership in the current shell without a logout/login cycle.
4. Verify the chip responds: `tpm2_getrandom 8` should print 8 random bytes.
5. Open **Tools → SSH Keys → Generate TPM-backed SSH key**.

#### Setup — Windows

1. The TPM 2.0 path uses the same Microsoft Platform Crypto Provider as the Windows Hello wizard. No extra install — the provider ships with Windows 10 1607+.
2. Verify TPM is enabled in firmware: open **tpm.msc**; the "TPM Manufacturer Information" pane should show a vendor + version (2.0). If it's missing, enable "TPM" / "fTPM" / "PTT" in your firmware setup (BIOS/UEFI).
3. Open **Tools → SSH Keys → Generate TPM-backed SSH key**.

#### Generating a key

1. **Tools → SSH Keys → Generate TPM-backed SSH key** (the row is visible on Linux + Windows; macOS hides it because the Apple Secure Enclave path covers the same security niche, and mobile platforms have no compatible TPM surface).
2. The wizard probes the chip. Disabled-with-reason routes:
   - **Linux** "No TPM detected on this device" — chip is missing or fTPM is disabled in firmware.
   - **Linux** "App cannot access the TPM. Add user to the `tss` group" — the device node exists but the app cannot open it.
   - **Windows** "No TPM detected on this device" — the Microsoft Platform Crypto Provider is unreachable (Server Core minimal, GPO-blocked PCP, or pre-1607).
3. Pick a label and an algorithm (P-256 default; RSA-2048 fallback).
4. **Linux only** — choose a PIN policy:
   - **No PIN** (default for headless service accounts) — the key is bound to the OS install; any process that can reach `/dev/tpmrm0` and load the blob can sign.
   - **Protect with PIN** — the wizard adds two PIN fields. Every sign asks for the PIN. **TPM lockout is hardware-wide** — wrong PIN 4 times locks the entire chip including BitLocker / disk-unlock for a cooldown window (typically 10 minutes on the first lockout, scaling up). The wizard surfaces this warning aggressively.
5. **Linux only** — choose a storage policy:
   - **Store wrapped key in app data** (default) — `TPM2_Create` output is wrapped per TCG draft `draft-bottomley-tpm2-keys-asn1` and stored in the app's data dir. Portable across reinstalls.
   - **Persist in TPM memory slot** — the key sits in TPM RAM. Faster signing but consumes one of the chip's persistent slots (typical fTPM ships ~7 free handles).
6. **Windows only** — there is no PIN or storage radio. The silent variant signs unattended and the CNG keystore is the only storage. The wizard surfaces the silent-warning copy in orange — anyone with desktop access while you're logged in can use the key.
7. Tap **Generate**. On success the wizard shows the `authorized_keys`-shaped public-key line with a Copy affordance.
8. Add that line to `~/.ssh/authorized_keys` on the server.
9. Reference the new row from a session's **Auth → Key from manager** drop-down.

#### Cross-tool blob compat (Linux)

The Linux blob storage mode uses the TCG draft `draft-bottomley-tpm2-keys-asn1` "TSS2 PRIVATE KEY" PEM format. It's the same shape `ssh-tpm-agent` and `openssl-tpm2-engine` write. You can:
- **Import** an existing `.tpm` file via **Tools → SSH Keys → Import TPM-protected SSH key**.
- **Export** an existing LetsFLUTssh-minted blob to another TSS2 PRIVATE KEY consumer by copying the underlying `<appSupportDir>/ssh_tpm_keys/<key_id>.tpm` file (advanced users only — the file is part of LetsFLUTssh's internal layout).

Blobs carrying a **PCR policy** (key bound to specific firmware / boot-loader / kernel measurements) reject at import in v1 with a "PCR-binding not supported" reason — the policy session machinery is on the roadmap for v2.

#### Recovery from device loss

The TPM bonds keys to the chip. If the device is lost, wiped, or the TPM is cleared (BIOS reset / `tpm2_clear`), every TPM-bound SSH key on it is gone — regenerate on the replacement and update `authorized_keys`.

#### Platform availability

| Platform | Status |
|---|---|
| Linux with TPM 2.0 + `tss` group | Supported. Wizard enabled. |
| Linux without TPM | Hidden with "No TPM detected on this device". |
| Linux with TPM but no `tss` group membership | Disabled with `usermod -a -G tss $USER` snippet. |
| Windows 10 1607+ with TPM 2.0 | Supported — silent variant (no Hello prompt). |
| Windows without PCP / Server Core minimal | Hidden with "No TPM detected on this device". |
| macOS / iOS | Hidden — use the Secure Enclave wizard instead. |
| Android | Hidden — use the Android Hardware Keystore wizard below. |

### Hardware key (Android Hardware Keystore / StrongBox)

On Android, LetsFLUTssh can generate SSH keys whose private half lives in the Hardware Keystore — StrongBox HSM on phones that ship one (Pixel 3+, Samsung S20+, etc.) and the TEE elsewhere. The chip refuses to export the private bytes; every connect-time signature routes through `BiometricPrompt.CryptoObject(Signature)` and fires the system biometric prompt (fingerprint / face) inside the call.

- **Algorithms.** ECDSA P-256 (`ecdsa-sha2-nistp256`, the only uniformly StrongBox-eligible choice — preferred default), Ed25519 (`ssh-ed25519`, Android 13+ only, TEE-only — StrongBox is not guaranteed even on capable devices), and RSA-2048 PKCS#1 v1.5 (`rsa-sha2-256`, widest compatibility with older servers).
- **Device-bound.** Keystore-bound keys cannot leave the chip — the key works only on the Android device that generated it. A factory reset or app uninstall destroys the key.
- **Per-signature prompt.** Every connect attempt fires the BiometricPrompt. There is no caching layer; Android's per-op auth contract is the security property.

#### Setup

1. Enrol a biometric (fingerprint / face) or a device PIN in **Settings → Security**. The wizard refuses to proceed without one — Android's KeyStore requires `setUserAuthenticationRequired(true)` and the only way to satisfy it is a configured authenticator.
2. **Tools → SSH Keys → Add Android hardware-bound key** (the row is visible only on Android — other platforms hide it).
3. The wizard probes the device. If biometric is missing, the dialog renders disabled with "Enrol biometric or device PIN first" — open Settings and re-run.
4. Type a label (the row's display name in the key manager).
5. Pick an algorithm:
   - **ECDSA P-256** — preferred default; eligible for StrongBox HSM on capable devices.
   - **Ed25519** — modern, smaller signatures; Android 13+ only; never lands in StrongBox.
   - **RSA-2048** — widest server compatibility; eligible for StrongBox.
6. The **StrongBox HSM** toggle is enabled when the device has the `FEATURE_STRONGBOX_KEYSTORE` capability AND the chosen algorithm supports it (ECDSA P-256 / RSA-2048). Ed25519 disables the toggle with the matching reason. The toggle defaults to on.
7. Tap **Generate**. Android creates the key inside the AndroidKeyStore (no biometric prompt at generate time — only at sign time). The wizard shows the `authorized_keys`-shaped public-key line with a Copy affordance, and the badge label tells you which tier the key actually landed at — "StrongBox HSM" or "TEE". The device may silently drop StrongBox if the algorithm subset doesn't fit (rare but possible after a firmware update); the label is always honest.
8. Paste the public-key line into `~/.ssh/authorized_keys` on every server you want to reach.
9. Reference the new row from a session's **Auth → Key from manager** drop-down. Every connect attempt fires the BiometricPrompt — that's the ceremony.

#### Enrolment-change destruction

The key is bound to the biometric enrolment in place at create time. Adding or removing a fingerprint / face — or enrolling a new one — permanently invalidates the on-chip key. The next connect attempt surfaces "Key destroyed: a new biometric was enrolled. Re-register the public key on your servers." The DB row is preserved so you can copy the public key off it (paste a fresh one to the server), but the row's hardware binding is gone — delete it and run the wizard again. This is the load-bearing security property that distinguishes hardware-bound keys from a software key sat behind a biometric gate: the on-chip private half cannot survive an enrolment change.

#### Backup / sync

There is none. The private key never leaves the AndroidKeyStore; the `.lfs` archive carries only the alias, which only matches on the original device. If the device is lost or wiped, re-generate the key on the replacement Android device and update `authorized_keys` on the server. The `android:allowBackup="false"` manifest entry blocks Android's auto-backup from copying anything across — by design.

#### Platform support

| Platform | Support |
|---|---|
| Android 13+ (Pixel 8 / Galaxy S24 / etc. with StrongBox) | Supported. StrongBox HSM available for ECDSA P-256 / RSA-2048; TEE for Ed25519. |
| Android 9-12 with StrongBox | Supported. StrongBox available; Ed25519 not exposed (KeyMint v2 only). |
| Android 6-8 (no StrongBox) | Supported. Wizard renders TEE-only — toggle disabled with "StrongBox HSM not available on this device". |
| iOS / macOS / Windows / Linux | Hidden — use the Apple Secure Enclave / Windows Hello / TPM 2.0 wizard for that platform. |

---

## 4. Terminal

### Opening a tab

- Double-click a session in the sidebar.
- Or right-click → Terminal.

### What you see

- Top of the terminal shows connection progress (`[*]` yellow, `[✓]` green, `[✗]` red) until the shell opens.
- After connect, full xterm: 256-color + RGB, mouse modes, scrollback, search.

### Keyboard shortcuts (desktop)

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+C` | Copy selection |
| `Ctrl+Shift+V` | Paste |
| `Ctrl+Shift+F` | Search inside scrollback |
| `Ctrl+W` | Close active tab |
| `Ctrl++` / `Ctrl+-` / `Ctrl+0` | Zoom in / out / reset |
| `Shift` (hold while dragging) | Bypass app's mouse-mode capture for text selection in TUI apps (htop, vim, mc) |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tab |

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

---

## 5b. WebDAV file browser

LetsFLUTssh can also browse a WebDAV server (Nextcloud, ownCloud, Apache mod_dav, Synology DSM, IIS) with the same two-pane file browser.

### Creating a WebDAV session

- Session manager → New session → set **Session kind** to `WebDAV` at the top of the dialog.
- Fill **Base URL** with the WebDAV root collection, including the trailing slash. Examples:
  - Nextcloud: `https://cloud.example.com/remote.php/dav/files/alice/`
  - ownCloud: `https://files.example.com/remote.php/webdav/`
  - Apache mod_dav: `https://example.com/webdav/`
- Pick **Auth method**:
  - `Basic` — username + password, always sent (only safe over TLS).
  - `Digest` — challenge / response, MD5. Use when the server insists; password never crosses the wire in clear.
  - `Bearer token` — OAuth-style. Paste the access token into the password field; the username is ignored.
- Switch to the **Auth tab** and type the password or bearer token into the Password field. Leave it blank on a follow-up edit to keep the previously saved secret (the `[Saved]` badge shows up when the entry is already in SecretStore).
- Optional: paste a **Self-signed cert fingerprint** (SHA-256, `aa:bb:cc:…` or `SHA256:…`) when the server uses a self-signed certificate that the system trust store rejects. Leave empty for the default system trust.

### Connecting and browsing

- Save the session and click Connect (or double-click the row). The connect probe does a PROPFIND against the base URL; an invalid URL or wrong credential fails fast with the localized error toast.
- The remote pane opens at the base URL. Navigation, drag-and-drop, multi-select, mkdir, rename, and delete work the same way as the SFTP browser.
- File-row context menu adds two WebDAV-only actions: **Copy WebDAV URL** copies the full URL of the entry; **Open in browser** launches it in the system web browser (the password is stripped from the URL before launch).

### Limitations

- Streaming uploads / downloads for very large files are buffered in memory for the WebDAV transport; SFTP keeps the chunked streaming path. Plan around this when moving multi-GB objects over WebDAV.
- Server-side recursive delete is the server's behaviour, not the client's. Nextcloud, ownCloud, Apache mod_dav, and IIS cascade by default; if your server rejects DELETE on a non-empty collection, drain the folder manually first.

---

## 5c. S3 bucket browser

LetsFLUTssh can also browse any S3-compatible object store (AWS S3, MinIO, Wasabi, Backblaze B2-S3, Cloudflare R2, DigitalOcean Spaces, Scaleway Object Storage) with the same two-pane file browser.

### Creating an S3 session

- Session manager → New session → set **Session kind** to `S3` at the top of the dialog.
- Fill **Access key ID** with the public-side key (AWS `AKIA…`, MinIO console-generated key, R2 access key id, etc.).
- Fill **Region** with the bucket's region wire value:
  - AWS: `us-east-1`, `eu-west-2`, etc.
  - Cloudflare R2: `auto`.
  - MinIO / private deployments: any string; the value still feeds the SigV4 credential scope, so pick one and stay consistent.
- Fill **Endpoint** only for non-AWS deployments:
  - AWS: leave empty (defaults to `https://s3.<region>.amazonaws.com`).
  - MinIO: `https://minio.local:9000` (or your host).
  - Cloudflare R2: `https://<account-id>.r2.cloudflarestorage.com`.
  - DigitalOcean Spaces: `https://<region>.digitaloceanspaces.com`.
  - Wasabi: `https://s3.<region>.wasabisys.com`.
  - Backblaze B2-S3: `https://s3.<region>.backblazeb2.com`.
  - Scaleway: `https://s3.<region>.scw.cloud`.
- Toggle **Path-style addressing** when the server requires it. MinIO needs it; AWS, R2, Spaces, Wasabi all default to virtual-host and the toggle stays off.
- Fill **Default bucket** with the bucket the browser should open at. Leave empty to require the `s3://bucket/key` shorthand on every navigation.
- Optional: fill **Default prefix** with the prefix the browser should open under (`logs/`, `2024/`). The browser still walks above the prefix when the user types an `s3://` path that points elsewhere.
- Switch to the **Auth tab** and type the **Secret access key** into the Password field. Leave it blank on a follow-up edit to keep the previously saved secret (the `[Saved]` badge shows up when the entry is already in SecretStore).

### Connecting and browsing

- Save the session and click Connect (or double-click the row). The connect probe runs a one-page `ListObjectsV2` against the default bucket; a wrong credential or missing bucket fails fast with the localized error toast.
- The remote pane opens at `s3://<default-bucket>/<default-prefix>`. Common prefixes (the `<prefix>/` markers S3 surfaces as virtual directories) render as folders so navigation matches the SFTP / WebDAV browser.
- File-row context menu adds two S3-only actions:
  - **Generate presigned URL** — produces a time-limited download URL for the object. Pick the expiry from the dropdown (15 minutes, 1 hour, 4 hours, 24 hours, 7 days — AWS's maximum). The URL is copied to the clipboard.
  - **Copy s3://bucket/key URI** — copies the `s3://<bucket>/<key>` form for pasting into AWS CLI, other S3 tools, or a teammate's chat.

### Limitations

- Rename is not atomic on S3 — the browser emulates it via `CopyObject` + `DeleteObject`. A reader between the two calls observes both source and target objects briefly. The SFTP and WebDAV transports honour native rename and don't carry this caveat.
- Streaming uploads route through the multipart orchestrator above 8 MiB (AWS SDK default). A crash mid-upload leaves the staged parts orphaned server-side; the next push restarts from scratch and the next session lifecycle reclaims the orphaned state through your bucket's lifecycle policy (most providers run a default cleanup on incomplete multipart uploads — check your provider's docs).
- Downloads / uploads are buffered in memory for the v1 cut; multi-GB objects need disk-backed streaming, which is a follow-up.

---

## 6. Port forwarding

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

## 9. Session recording + playback

Per-session terminal output + input capture, encrypted at rest, playable in-app or exportable.

### Enabling per session

1. Edit the session.
2. **Options** tab → toggle **"Record session"** ON.
3. Save → connect → recording starts automatically.
4. Each shell channel records to its own file.

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
5. **Scrub bar:** drag to jump to any point in the recording. Recordings made before this build are sequential-only — the scrub bar is disabled for them with a tooltip explaining why; they still play back at `1×` / `2×` / `4×` / Instant.
6. **Trash** on a row → delete the file.

### Storage management

Settings → Data → **Recordings** shows the current `<appSupport>/recordings/` usage and lets you change the hard cap or wipe everything.

- **Cap presets:** 100 MiB / 250 MiB / 500 MiB / 1 GiB / 2 GiB / 5 GiB. Default 500 MiB.
- **LRU eviction** runs automatically whenever a recording starts or finishes — once the tree exceeds the cap, oldest files (by mtime) are deleted until the total drops back under the cap. The recording currently in progress is never deleted.
- **Clear all recordings** wipes every file under the recordings root in one go. The recording currently in progress (if any) is preserved.
- Changing the cap to a smaller value triggers an immediate eviction sweep; the toast shows how much was reclaimed.

### Notes

- **Quick-connect sessions don't record** — they have no stable session id, so the recorder skips.
- **Recorder failure is best-effort** — disk full, permissions, etc. log a warning and the connect proceeds without recording.
- **Auto-rotation** at 100 MB per file; the next event opens a fresh file under the same session.
- **No scrub bar yet** — sequential GCM-frame stream means seeking would need an index file. Use the Instant speed for fast-forward.

### External playback (advanced)

- `.cast` files are valid asciinema v2 — `asciinema play <path>` works on any platform.
- `.lfsr` files require the app's HKDF derivation; no out-of-app player today.

---

## 10. SSH key manager + PuTTY `.ppk` import

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

- v3 files use Argon2id KDF — derivation is CPU-bound (deliberately). The first import of a v3 file is usually under a second; the worker runs natively in the Rust core (`russh-keys::PrivateKey::from_ppk` over RustCrypto Argon2id), not via a Dart-side KDF library.
- Memory-cost cap: 1 GiB. Files asking for more (crafted DoS payloads) are rejected with a targeted error before any derivation runs.

### Pairing a certificate to a key

- Open **Tools → SSH Keys**, find the row for the key the certificate was issued for, tap the certificate icon → **Import certificate**, then select the `*-cert.pub` file the CA produced via `ssh-keygen -s ca_key id_ed25519.pub`.
- The row picks up a tertiary line showing the principals (clipped at three visible, `+N` tail), the validity end date, and a `Critical options: N` summary when the cert carries any. An expired certificate (`valid_before < now`) renders a red dot + **Expired** pill in the row's trailing slot.
- To detach the cert later, tap the same icon again → confirm. After removal the next connect attempt falls back to plain public-key auth.
- The cert pairing is opportunistic — the connect path prefers cert auth whenever a paired certificate exists for the key the session references, otherwise it uses the plain key.

### System ssh-agent

The Rust core can authenticate a session against the user's running ssh-agent over the platform's default channels — keys stay inside the agent, every signature round-trips back through it. No session-edit knob in the current build picks this path; once it ships, the platform mechanics below already apply.

On Linux and macOS the app reads `$SSH_AUTH_SOCK` (the same variable OpenSSH `ssh` honours). Run `ssh-add -l` in the same shell that launches the app to confirm the keys you expect are listed.

On Windows the app first tries the OpenSSH-on-Windows named pipe `\\.\pipe\openssh-ssh-agent` — what Microsoft's `OpenSSH Authentication Agent` service registers when you enable the *OpenSSH Client* optional feature and `Start-Service ssh-agent`. If that pipe doesn't exist it falls back to **Pageant** automatically; both the legacy `WM_COPYDATA` mailbox and modern named-pipe Pageant builds are picked up. PuTTY 0.78+ ships the named-pipe variant by default. We do not stand up our own Pageant-compatible endpoint for other tools to consume — the `WM_COPYDATA` channel has known injection vectors (see WithSecure Labs' Pageant analysis). For PuTTY-side consumption of keys you imported into the app, point PuTTY at the OpenSSH named pipe exposed by Settings → External SSH client integration (see [§10b](#10b-using-hardware-bound-keys-outside-the-app)).

**gpg-agent.** `gpg-agent --enable-ssh-support` exposes a Unix domain socket that speaks the standard OpenSSH agent protocol, so the app picks up its keys exactly like any other ssh-agent. To use OpenPGP-card-resident keys or GPG-managed key files for SSH:

```bash
export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
```

Then list the keygrips you want exposed in `~/.gnupg/sshcontrol` (one per line). Launch the app from the same shell — or wire the export into your shell's startup file — and `ssh-add -l` should show the gpg-agent identities.

On Windows, gpg4win ships a Pageant-compatible bridge (`gpg-agent --enable-putty-support`), not the OpenSSH named-pipe bridge — so the app can't reach gpg-agent directly through the OpenSSH pipe. The workaround is a shim that re-publishes gpg-agent's identities at `\\.\pipe\openssh-ssh-agent`; `wsl-ssh-pageant` is the most common choice. Once the shim is running the app picks the keys up automatically on its next connect.

---

## 10b. Using hardware-bound keys outside the app

LetsFLUTssh can act as an ssh-agent on the same host so `git`, OpenSSH `ssh` / `scp` / `sftp`, VS Code Remote-SSH, JetBrains Gateway, PuTTY 0.78+ and other SSH-protocol-speaking tools can use the FIDO2 and PKCS#11 (and future TPM / Secure Enclave / Hello / Keystore) keys you import here.

The endpoint is off by default for safety — flip it on under **Settings → External SSH client integration** when you want to reach your hardware keys from outside the app. Every signature request still routes through a confirmation dialog ("Authorize once" / "Authorize and remember" / "Deny") unless you explicitly promote the key's policy.

### Linux / macOS — Unix domain socket

Enable the toggle, copy the path the section shows (`/run/user/<uid>/letsflutssh-agent.<pid>/agent.sock`), and point your shell at it:

```bash
# bash / zsh
export SSH_AUTH_SOCK="$(/path/that/Settings/copied)"

# fish
set -x SSH_AUTH_SOCK /path/that/Settings/copied
```

`ssh-add -l` should now list your imported hardware-bound keys. `git push`, `scp`, IDE SSH plugins all pick up the same `SSH_AUTH_SOCK` automatically.

The endpoint stops when the app exits — restart picks a fresh `<pid>` suffix, so update `SSH_AUTH_SOCK` after every restart (or wrap it in a shell function that re-reads the running app's path on every shell login).

### Windows — OpenSSH named pipe

Enable the toggle and copy the pipe name (`\\.\pipe\letsflutssh-agent.<pid>`). Then in `%USERPROFILE%\.ssh\config`:

```
Host *
    IdentityAgent \\.\pipe\letsflutssh-agent.<pid>
```

PowerShell session-wide alternative:

```powershell
$env:SSH_AUTH_SOCK = "\\.\pipe\letsflutssh-agent.<pid>"
```

PuTTY 0.78+ reads `IdentityAgent` straight from the pipe name. Older PuTTY versions speak Pageant — see the [Pageant interop](#pageant-interop) note below.

### Mobile (Android / iOS)

Not available — neither platform exposes an SSH client that reads a host-local agent socket. The Settings row is disabled with a "Not supported on this platform" label.

### Per-key dispatch policy

Every imported hardware key starts at policy `Ask` — every signature request from an external client surfaces a confirmation dialog naming the requesting process (best-effort; macOS displays "An external SSH client" because the BSD socket layer does not surface peer pids) and the key label. From the dialog:

- **Authorize once** — sign this one request only. The next request prompts again.
- **Authorize and remember** — sign this request AND flip the key's policy to `Always` so future requests skip the dialog. The hardware backend's own touch / PIN prompt still fires when the credential carries the user-verification bit.
- **Deny** — refuse this request. Policy stays at `Ask`.

To pre-set or change a policy without waiting for a prompt: Tools → SSH Keys → pick a key → policy dropdown (`Always` / `Ask` / `Deny`). `Deny` also hides the key from `request_identities`, so external clients can't even see that the key exists.

### Certificates

If you've paired an OpenSSH certificate to a key (Tools → SSH Keys → key → Import certificate), the certificate is advertised alongside the bare public key — `ssh-add -l` against our endpoint shows two lines per cert-paired key, ending `(...-SK)` for the bare entry and `(...-CERT-SK)` for the cert entry. OpenSSH 8+ clients automatically pick the cert form during userauth, so a `git push` over SSH against a server that trusts your CA will authenticate via the certificate without any extra knob. Bare-only clients fall back to the public-key entry transparently. Mirror of what `ssh-add cert.pub` against the OpenSSH `ssh-agent` would advertise.

### Refused operations

The endpoint never accepts key material from external clients — `ssh-add <file>` / `ssh-add -d` / `ssh-add -D` all fail with `SSH_AGENT_FAILURE`. Keys flow only one way: through the in-app import flow (Tools → SSH Keys → Import).

### Pageant interop

PuTTY 0.78+ supports OpenSSH named pipes natively (see the Windows section above). For older PuTTY versions that only speak Pageant's `WM_COPYDATA` protocol, our app does NOT stand up a Pageant-compatible endpoint — the protocol's window-message channel has known injection vectors (see WithSecure Labs' Pageant analysis). Upgrade PuTTY to 0.78 or later, or use `wsl-ssh-pageant` to bridge our named pipe into a Pageant shim.

---

## 11. Tags

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

## 12. Known hosts (TOFU)

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

## 13. Security tiers

How the app protects credentials at rest. First launch auto-selects **T1 — Keychain** silently when the OS keychain is reachable (typical on every supported platform). The tier-picker wizard only renders when the keychain is unreachable — it offers T0 / Paranoid plus T2 (hardware) when a TPM 2.0 / Secure Enclave / StrongBox is also detected. T2 and the modifiers (master password, biometric) are opt-in any time via **Settings → Security** even when first-launch auto-applied T1.

### The tiers

| Tier | Where the DB-encryption key lives | Notes |
|---|---|---|
| **T0 — Plaintext** | Nowhere — DB itself is unencrypted | App still opens via rusqlite/SQLCipher in-process; just no `PRAGMA key` set. Use only when you have full-disk encryption + accept the trade-off. |
| **T1 — Keychain** | OS keychain via direct Rust calls (macOS / iOS Keychain via `security-framework`, Linux libsecret via `secret-service` D-Bus, Windows Credential Manager via `CredReadW` / `CredWriteW`, Android `java.security.KeyStore` via direct JNI). No third-party plugin in the call chain. | Strongest "no master password to remember" option on most desktops. |
| **T2 — Hardware** (requires password) | Hardware-bound key in TPM 2.0 (Linux/Windows), Secure Enclave (macOS/iOS), StrongBox (Android) — **always password-gated.** | Needs hardware. App detects + offers when available. The typed password is the primary unlock gate; biometric is the optional shortcut. |
| **Paranoid** | Argon2id-derived from a master password you type every launch | Nothing on disk except the salt + verifier. Lose the password = lose the data. |

### Modifiers (orthogonal, Keychain optional / Hardware mandatory)

- **Master password gate** — adds a pre-vault password check (HMAC-SHA256 of input against the stored verifier, with the pepper in the OS keychain so disk access alone can't forge a hit). The keychain/hardware key is only released after the gate passes. Defends against "attacker has filesystem access but not your password". Optional on T1; **mandatory on T2** (the typed password is the primary unlock gate for the Hardware tier — the modifier toggle is locked-on for that row).
- **Biometric shortcut** — FaceID / TouchID / Windows Hello / fingerprint reader / fprintd. Releases the *stored* password automatically.
  - **Invariant: biometric requires password.** The shortcut is one specific UX path for entering the password, never a replacement. The password is still the auth value the keychain / hardware vault expects; the biometric prompt only releases the password from a biometric-gated OS slot. Re-enrolling your biometrics (adding a new fingerprint / re-running Face ID setup) invalidates the slot and forces a password re-entry — the OS-level invariant we ride on, not something we choose.
  - **Anti-debug gate.** When a debugger is attached to the running app the biometric path is silently refused on every unlock attempt — the app falls through to the typed-secret form (master password) so an OS-stored password can never be released into a process whose RAM the debugger can read. Logged via the Settings → Logging viewer (`ProcessHardening` tag) at critical severity. Affects developer builds running under Xcode / `gdb -p` / `lldb -p`; legitimate end-user installs never see this path.
  - **Failure fallback.** If the biometric prompt fails or is cancelled, you type the password as usual. No data loss; the keychain entry remains intact.

### Biometric overlay (Hardware tier shortcut)

The biometric overlay is the OS-managed slot that holds the Hardware-tier password under a biometric ACL. When you enable biometric on T2 the app caches your typed password in this slot; every subsequent unlock fires the system biometric prompt and reads the password back without asking you to retype it. Per platform:

- **Apple (macOS / iOS)** — Secure Enclave overlay key with `kSecAccessControlBiometryCurrentSet`.
- **Android** — AndroidKeyStore alias `lfs.hardware_tier_vault.l3.bio` with `setUserAuthenticationRequired(true)` + `setInvalidatedByBiometricEnrollment(true)`.
- **Windows** — NCrypt persistent key `letsflutssh_hardware_vault_bio_v1` on the Microsoft Platform Crypto Provider with `NCRYPT_UI_PROTECT_KEY_FLAG | NCRYPT_UI_FORCE_HIGH_PROTECTION_FLAG`; every unwrap fires the Windows Hello prompt. Re-enrolling Hello (new fingerprint / face / PIN reset) invalidates only the overlay — the primary password vault keeps working.
- **Linux** — TPM2-sealed `hardware_vault_password_overlay_linux.bin` keyed by your fprintd enrolment hash (SHA-256 of your sorted enrolled-finger names). Requires `fprintd` running with at least one enrolled finger; the README install snippet covers per-distro install + first enrol. Re-enrolling (adding / dropping a finger) flips the hash so the TPM unseal fails, and you fall back to typing the password. The primary `hardware_vault.bin` is unaffected — only the shortcut goes away.

### Migrating from earlier versions (Hardware tier password set)

Older builds let the Hardware tier run without a password — biometrics on top of an empty PIN-HMAC. New builds make the password mandatory; biometric is the optional shortcut on top. When you launch the new version with an existing Hardware-tier install that had no password, a one-shot wizard appears before the regular unlock dialog:

- **Set a password.** Type a fresh master password (twice for confirmation). The DB key already sealed in your TPM / Secure Enclave / StrongBox / Windows TPM stays the same — only the auth value changes; sessions, keys and known-hosts survive intact.
- **Wipe and start over.** A destructive escape hatch sits on every screen of the wizard. Picks this if you have no usable password to type — the install resets to a fresh first-launch wizard.

The wizard is non-dismissible. Once the re-seal succeeds the regular Hardware-tier unlock dialog asks for the password you just typed and the boot continues as usual. If the re-seal fails (wrong-shape vault on disk, hardware suddenly unavailable), the wizard surfaces the failure inline and lets you pick a different password or wipe — the previous vault stays untouched on disk so a retry is always available.

### Switching tiers

- Settings → Security → tier card → "Change tier".
- Re-encrypts the DB atomically (`PRAGMA rekey`) before flipping the in-memory key. If anything fails mid-way, the on-disk DB stays at the previous tier — no data loss.

### Auto-lock

- Settings → Security → Auto-lock after N minutes of inactivity. On lock, the in-memory DB key is zeroed and the lock screen appears. Re-unlocking re-derives / re-fetches.

### Threat model + design rationale

In [`SECURITY.md`](SECURITY.md). Read it before deploying in environments where the device is not under your sole physical control.

---

## 14. Import / export

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

## 14b. Sync via WebDAV

Settings → **Sync** lets you push the encrypted session library
to a WebDAV server (Nextcloud, ownCloud, Apache `mod_dav`, IIS,
Synology DSM, Yandex.Disk) and pull it on another device. The
archive shipped over the wire is the same encrypted `.lfs` format
the Data → Export flow produces — same `LFSE` envelope, same
Argon2id + AES-256-GCM crypto, same wire-version contract.

### Setting it up

1. Open Settings → **Sync**.
2. Toggle **Enable WebDAV sync** on.
3. Fill in:
   - **WebDAV URL** — the collection root, ending in `/`. Example: `https://cloud.example.com/remote.php/dav/files/alice/`.
   - **Username** — usually the same one you log into the web UI with.
   - **Auth** — pick **basic** for username + password, **digest** for HTTP digest auth, **bearer** for an OAuth-style token.
   - **Password** — types into the field, then leaves the form on submit. Stored in the OS keychain through the same SecretStore the rest of the app uses; never written to `config.json`.
   - **Sync passphrase** — the secret that encrypts the archive itself. **Must differ from your master password** — if you type the master password by mistake, the form refuses to save. Pick a fresh phrase you can remember; losing it makes existing remote archives unrecoverable.
   - **Remote path** — the file name under the WebDAV root. Default `letsflutssh.lfs`; change only if you have multiple identities sharing one bucket.

### Push and Pull

- **Push now** — packs your current session library into an encrypted `.lfs` and uploads it. The button is disabled while a sync is in flight; tapping it twice does not enqueue two uploads.
- **Pull now** — fetches the remote archive, decrypts it with the sync passphrase, and merges the peer's rows into your local library. Per-row last-write-wins: a session whose `updated_at` on the remote is newer than yours overwrites yours; older rows leave yours untouched. **Re-pulling unchanged state is free** — the request stamps an `If-None-Match` for the ETag you last pushed or pulled, the server replies 304 with no body, and no decrypt work runs. A second tier compares the SHA-256 of the downloaded body against the last push / pull when the server rotates the ETag without changing the content (nginx restart, weak ETags), so the merge step still short-circuits.
- **Last push** / **Last pull** rows show when each verb last succeeded, or **Never** if the action has not run.

### ETag conflict — pull first, then push

If another device pushed between your last pull and your push, the server rejects your upload with a 412 ETag mismatch. The app shows **"Remote changed — pull first, then push"**. Click **Pull now** — your library merges the peer's changes — then click **Push now** again and the new ETag round-trips fine.

### Limitations (v1)

- Manual only — no background sync timer. Click Push / Pull when you want to sync.
- **Tombstones do not propagate across devices**. If you delete a session on device A and pull on device B, the deletion is not replayed. The next push from device B re-introduces the deleted row. Workaround: delete the session on every device until the sync wire format grows tombstone fields.
- M2M edges (session → tag, session → snippet, folder → tag) are union-merged; unlinking on one device does not unlink on the other.
- v1 ships the full archive on every push, not deltas. Push time scales with library size; a typical 100-session library lands in under 100 KiB.

### Where the secrets live

- **WebDAV password** — OS keychain via the SecretStore. Cleared when you wipe app data; not in `config.json`.
- **Sync passphrase** — same. The Settings UI verifies it differs from the master password before saving by running the typed passphrase through `MasterPasswordManager.verifyAndDerive`; the master password's plaintext never lands in Dart memory during the check.
- **Local mirror of sync state** — `config.json` holds the URL, the username, the SecretStore id pointers, and the `last_pushed_*` / `last_pulled_at_ms` timestamps. An `.lfs` exported through Data → Export drops every `sync_*` field on its way out, so a peer importing the archive on a third machine does not adopt your endpoint.

---

## 14c. Moving between devices

When you reinstall the app on a fresh device — new laptop, new
phone, restored backup — you can carry your library across with
`.lfs` import or WebDAV sync. Most data round-trips automatically;
a few items need a one-time action on the new device.

### What comes back automatically

- Every session — host, port, user, auth shape, ProxyJump / via,
  notes, extras, port-forward rules, SFTP bookmarks.
- Folder hierarchy + every tag / snippet assignment.
- Software SSH keys — the private PEM rides inside the GCM
  envelope and lands directly.
- FIDO2 (`sk-*`) hardware keys — the credential id, application
  string, and user-verification bit travel; plug the same
  YubiKey / Solo / Nitrokey into the new device and sign works.
- PKCS#11 smart cards / tokens — the token serial, object id,
  object label, and PKCS#11 URI travel. The library path on disk
  is per-host and is re-discovered automatically from the
  well-known-paths table on first connect.
- Paired OpenSSH certificates — the cert blob is the public half
  of a CA-signed pair and rides verbatim.
- Known-hosts (TOFU) database.
- All preferences except theme / locale / log threshold (those
  are per-device on purpose).

### What you re-enter on the new device

- **WebDAV password** for any WebDAV-kind session you carried.
  The secret stayed on the source device; the imported row
  surfaces "missing credential — re-enter password" on first
  connect.
- **S3 secret access key** for any S3-kind session. Same
  discipline — the access key id (the public half) travels, the
  secret bytes don't.
- The **sync passphrase** when you pull from WebDAV on the new
  device — the new install has no passphrase staged yet, so the
  Settings → Sync card prompts for it the first time.

### What you re-insert

- FIDO2 / PKCS#11 hardware tokens — physically plug them into the
  new device. SSH-key rows already point at them by
  `application_string` / `pkcs11_token_serial` / `pkcs11_object_id`.
- PKCS#11 module path on a vendor / OS combination where the
  well-known-paths scan does not find the library. The connect
  flow surfaces a one-shot "Locate the PKCS#11 module for token
  `<token>`" dialog; pick the library once and the row remembers
  it.

### What you re-generate

Device-bound keys — Apple Secure Enclave / Windows Hello / TPM /
Android Keystore — cannot leave the original device's hardware.
The imported row lands in Key Manager as a desaturated **stub**
with an **Imported stub** badge and a "Re-generate here" action.
Pick it to mint a fresh hardware-backed key with the same label;
the wizard runs through the per-backend confirmation flow.
"Remove stub" is also available when you want to clear the row
without regenerating (e.g. you no longer use that identity on
this device).

The session-edit "Key from manager" picker disables stub rows
with the tooltip **"Re-generate this key on this device before
using"** so you cannot accidentally bind a session to a key whose
private half lives on another machine.

---

## 15. Updates

- Settings → Updates → **Check for updates**.
- Optional **Check on startup** toggle (default on).
- Found a new version → modal with release notes + Skip / Open in Browser / Download & Install.

### What "Download & Install" does

1. Fetches the release's `letsflutssh-<version>.sha256sums` manifest **and** the matching `.sha256sums.sig` (one Ed25519 signature over the whole manifest).
2. Verifies the manifest signature against the public key compiled into the app. **Verify failure** = both files deleted, security-styled error tile shown with an "Open Releases page" action; auto-install never runs on an unverified manifest.
3. Downloads the binary, computes its sha256, looks the artefact name up in the verified manifest, compares.
4. Hands off to the platform installer:

   | Platform | Auto-install path | Notes |
   |---|---|---|
   | **Windows (Inno Setup `.exe`)** | Launches the installer; user clicks through the wizard. | Portable `.zip` falls through to step "open in file manager" — no auto-install. |
   | **Linux (`.deb`)** | Launches `xdg-open` on the `.deb` so the system package manager (Discover / GNOME Software / `apt`) takes over. | `.AppImage` and `.tar.gz` open the file manager — re-launching the new bundle is a manual one-time step. |
   | **macOS (`.tar.gz` / `.dmg`)** | Silent install via `macosInstallerInstall` — mounts the `.dmg`, rsyncs the new bundle alongside the running one, re-signs under the user's existing self-sign cert (when present), atomic-swaps the old bundle. No user prompt. | Falls back to "Open release page" when the silent path fails (no cert configured / verification mismatch). |
   | **Android (`.apk`)** | Launches the system package installer for confirmation. | Per-ABI APK already matched by the manifest entry. |
   | **iOS** | Sideloading flow — app opens the GitHub release page; user re-signs through their chosen sideloader. | No in-app auto-install — Apple sandbox forbids it. |

5. **Verify failure on the binary** = same outcome as step 2, with the binary deleted before the install path runs.

### Trust anchor

Install signature key is **baked into the app at build time** — `lfs_core::update_signing::PRIMARY_PUBLIC_KEY`, single-pin layout. An attacker would need to either (a) compromise BOTH the GitHub Releases CDN AND the offline signing key, or (b) ship you a hostile build whose embedded pubkey already matches their own private key (i.e. a fresh-install supply-chain attack — outside the auto-update threat model). Rotation is a manual-reinstall ceremony described in [SECURITY.md → Release signing](SECURITY.md#release-signing); existing installs whose embedded pubkey doesn't match the new signature refuse to auto-update by design.

---

## 16. Mobile differences

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
| Drag & drop | partial | partial | Sessions can be reordered; SFTP drag-drop works inside one browser pane only. |
| Foreground service | ✅ | n/a | Android keeps the SSH connection alive in background via a foreground notification while ≥ 1 connection is active. |

### iOS background caveat

Apple disallows long-lived sockets in background for non-VoIP / non-audio apps. SSH connections + their listeners (`-L`/`-D`) are throttled when the app is suspended. Best practice: keep the app foregrounded for the duration of the work, or accept that tunnels reset on resume.

### Android battery-optimisation

The foreground service notification can be muted by aggressive OEM battery managers (Xiaomi, Huawei, OnePlus). If your tunnels die in background despite the notification: Settings → battery → Don't optimise → LetsFLUTssh.

### iOS sideloading (no App Store)

LetsFLUTssh is not on the App Store — Apple Developer Program is paid ($99/year) and the per-release review process is hostile to fast iteration. The release pipeline ships an unsigned `.ipa` you self-sign onto your own device. Free Apple ID works for personal use; the cert it issues is good for 7 days, so the install needs refreshing weekly. A paid Apple Developer cert lifts that to 1 year.

**One-time setup**

1. Grab `letsflutssh-ios-unsigned-<version>.ipa` from the [Releases page](https://github.com/Llloooggg/LetsFLUTssh/releases).
2. Pick a sideloader for the OS you'll re-sign from (you do NOT need a Mac):

   | Tool | Host OS | Apple ID | Cert lifetime | Notes |
   |---|---|---|---|---|
   | [AltStore](https://altstore.io) | macOS / Win / Linux | Free / Paid | 7 d / 1 yr | AltServer on the host machine refreshes the cert in the background as long as the iPhone is on the same Wi-Fi. Easiest free path. |
   | [Sideloadly](https://sideloadly.io) | macOS / Win | Free / Paid | 7 d / 1 yr | Manual re-sideload; no background refresh. |
   | Xcode | macOS | Free / Paid | 7 d / 1 yr | Drag the `.ipa` onto a connected device, sign with your team. |
   | [TrollStore](https://github.com/opa334/TrollStore) | none (on-device) | none | permanent | Only works on iOS versions vulnerable to the CoreTrust bypass — currently iOS ≤ 16.7 and select 17.x sub-builds. Check the TrollStore compat matrix before trying. |

3. On the iPhone after install: **Settings → General → VPN & Device Management → Apple Development: <your-apple-id> → Trust**.

**Free Apple ID limits**

- 3 sideloaded apps active per device at any time.
- 10 unique app IDs every 7 days.
- 7-day cert expiry — re-sideload when the LetsFLUTssh icon greys out + iOS shows "Untrusted Developer". AltStore automates this if AltServer is reachable.

**Paid Apple Developer ($99/year)**

- Up to 100 devices per cert.
- 1-year cert.
- Worth it only if you also publish your own apps; for purely sideloading LetsFLUTssh the AltStore + free Apple ID flow is enough.

**Updating the app**

Each new release ships a fresh `.ipa` on the GitHub release page. Re-sideload over the existing install — settings, sessions, key material, recordings persist (data lives in the app sandbox, the resign only swaps the binary + bundle ID's signing chain).

**What's NOT available on iOS**

- App Store delivery (we don't go through the review).
- Push notifications (no APNs cert in the unsigned build).
- Universal Clipboard / Handoff between Apple devices (would need an entitlement signed by the App Store team).
- Background socket lifetime — see [iOS background caveat](#ios-background-caveat) above.

If sideloading isn't an option for you, the desktop builds (Linux / macOS / Windows) cover the same workflow and don't have the sandbox limits.

---

## 17. Troubleshooting

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

### "An instance of LetsFLUTssh is already running."

Desktop only — the OS-native single-instance gate fired (Linux GtkApplication D-Bus uniqueness, Windows `Local\LetsFLUTssh-SingleInstance` named mutex, macOS `LSMultipleInstancesProhibited`). Switching to the existing window is the intended UX; closing it lets the next launch start fresh. macOS Dock click brings the existing instance forward without a dialog. The mutex / D-Bus name auto-releases when the process exits, including via crash, so you can never deadlock yourself out by force-killing.

### App refuses to launch — "Failed to load configuration"

`config.json` was either truncated by a power loss, modified by hand into invalid JSON, or written by a future build whose schema this build doesn't understand. The fatal-error screen offers two buttons: **Quit** (preserves the file for manual recovery — open it in a text editor and fix the malformed JSON) and **Wipe all data** (deletes every managed file under app-support, including the encrypted DB and security artefacts). Wipe is destructive and gated behind the screen explicitly so the choice is conscious.

### App refuses to launch — DB-corruption dialog

The database is on disk but won't decrypt under the resolved tier. Three options offered:

- **Reset & Setup Fresh** — wipes every managed file (DB + security artefacts + logs), runs the first-launch wizard. Destructive; export your data first via Settings → Export if anything is recoverable.
- **Try other tier** — re-runs the security tier picker. Useful when you remember choosing T2 originally but the hardware blob got corrupted and you want to fall back to Paranoid.
- **Quit** — leaves the disk untouched. Try a newer / older build; the on-disk shape may match a different release.

### Restoring data after Reset All Data

You don't — Reset is destructive on purpose. The recovery path is **before** you reset: export an `.lfs` archive while the app still works (Settings → Data → Export → Encrypted archive), then re-import on the new install (Settings → Data → Import → Encrypted archive). The archive carries sessions, keys, snippets, tags, known hosts, and your config — it does **not** carry the security tier itself, so the new install runs the first-launch wizard and you re-pick T1 / T2 / Paranoid on top of fresh hardware.

### Logs

- App writes to `<appSupport>/logs/letsflutssh.log` (off by default).
- Settings → Logging → enable + set threshold (`info` / `warn` / `error`).
- Sanitised: PEM bodies, IPs, `user@host`, paths get redacted before the line hits disk.

### Reporting bugs

- GitHub Issues. Include the build version (Settings → About) + the relevant log slice (sanitised; double-check no remaining secrets before pasting).
- Security issues: see [SECURITY.md → Reporting](SECURITY.md#reporting-a-vulnerability) — don't open a public issue.
