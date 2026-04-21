#!/usr/bin/env bash
# LetsFLUTssh — macOS self-sign helper
#
# Problem
# -------
# Release .dmg / .tar.gz bundles are ad-hoc signed in CI (`codesign
# --sign -`) because we do not have an Apple Developer ID. macOS 26
# (Tahoe) dyld is fine with ad-hoc at launch, BUT Keychain Services
# bind every stored item to the app's Code Directory hash — ad-hoc
# builds regenerate that hash every release, so the keychain treats
# each new install as a different app and refuses access with
# `errSecMissingEntitlement` (-34018). Effect: the T1 (keychain) tier
# is unusable, and T2 (Secure Enclave) may surface similar symptoms.
#
# Workaround
# ----------
# A *personal* self-signed code-signing certificate gives the bundle
# a stable signing identity across reinstalls (the user creates it
# once, then every re-signed install keeps the same Code Directory
# hash), which is enough for Keychain Services to recognise the app.
# The trade-off: the cert is per-user, only trusted locally, and
# Gatekeeper still surfaces the "unidentified developer" first-launch
# warning. Unlike an Apple Developer ID, this runs offline, costs $0,
# and does not require any Apple account.
#
# Usage
# -----
#   ./macos-resign.sh                           # prompts for sudo
#   ./macos-resign.sh /Applications/letsflutssh.app   # explicit path
#
# The script is idempotent — re-running it with the same cert name
# just re-signs the bundle in place.
#
# Shipped alongside the macOS DMG in the GitHub release assets; the
# README → macOS Installation section points at the same file.

set -euo pipefail

APP_PATH="${1:-/Applications/letsflutssh.app}"
CERT_NAME="LetsFLUTssh Self-Sign"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

log() { printf '\e[36m==>\e[0m %s\n' "$1"; }
warn() { printf '\e[33m!!!\e[0m %s\n' "$1" >&2; }
die() { printf '\e[31mERR\e[0m %s\n' "$1" >&2; exit 1; }

# ── sanity ───────────────────────────────────────────────────────────
[ "$(uname -s)" = "Darwin" ] || die "This script is macOS-only."
[ -d "$APP_PATH" ] || die "App bundle not found: $APP_PATH"
command -v security >/dev/null 2>&1 || die "Missing \`security\` CLI."
command -v codesign >/dev/null 2>&1 || die "Missing \`codesign\` — install Xcode Command Line Tools via \`xcode-select --install\`."
command -v openssl >/dev/null 2>&1 || die "Missing \`openssl\`."

# ── create cert if absent ────────────────────────────────────────────
if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  log "Using existing self-signed cert: $CERT_NAME"
else
  log "Creating self-signed code-signing cert: $CERT_NAME"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  # OpenSSL config for a cert with codeSigning EKU. macOS accepts
  # certs with this extended-key-usage as code-signing identities.
  cat > "$TMP/cert.cnf" <<CFG
[req]
distinguished_name = dn
prompt = no
req_extensions = v3_req
[dn]
CN = ${CERT_NAME}
O  = LetsFLUTssh
[v3_req]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:FALSE
CFG

  openssl req -x509 -nodes -new \
    -newkey rsa:2048 \
    -days 3650 \
    -config "$TMP/cert.cnf" \
    -extensions v3_req \
    -keyout "$TMP/cert.key" \
    -out    "$TMP/cert.crt" \
    >/dev/null 2>&1 \
    || die "openssl cert generation failed"

  # Bundle into a PKCS#12 so the `security import` call below gets
  # both cert + private key in one artefact.
  openssl pkcs12 -export \
    -in "$TMP/cert.crt" \
    -inkey "$TMP/cert.key" \
    -out "$TMP/cert.p12" \
    -name "$CERT_NAME" \
    -passout pass:lfs-transient \
    >/dev/null 2>&1 \
    || die "p12 bundle failed"

  # Import into the user's login keychain — no admin needed.
  security import "$TMP/cert.p12" \
    -k "$KEYCHAIN" \
    -P lfs-transient \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    >/dev/null \
    || die "security import failed"

  # Trust the cert for code signing in the user's login trust
  # settings. This step WILL prompt for your Mac password — it
  # writes to the trust database. Cert stays user-only; no
  # system-wide trust is granted.
  warn "About to run \`security add-trusted-cert\` — macOS will prompt for your password."
  security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN" \
    "$TMP/cert.crt" \
    || die "add-trusted-cert failed — cert was NOT trusted; re-run the script to retry."
  log "Cert created and trusted for code signing (user-only)."
fi

# ── sign the bundle ──────────────────────────────────────────────────
#
# `sudo` is needed because /Applications/letsflutssh.app is owned by
# root after drag-to-Applications. If the user installed to
# ~/Applications we can skip it; detect by write-probing the bundle.
if [ -w "$APP_PATH" ]; then
  SUDO=""
else
  SUDO="sudo"
  log "\`$APP_PATH\` is not writable by you — the codesign step will use sudo."
fi

log "Re-signing $APP_PATH with \"$CERT_NAME\" (deep + force)…"
$SUDO codesign --force --deep --sign "$CERT_NAME" "$APP_PATH" \
  || die "codesign failed."

$SUDO codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null \
  || die "codesign verify failed after re-sign."

# Remove the quarantine attribute that the DMG download attached, so
# Gatekeeper does not also hold the app back.
$SUDO xattr -cr "$APP_PATH" 2>/dev/null || true

log "Done. Launch \"$APP_PATH\" — the T1 (keychain) tier should now work."
log "Future releases can be re-signed by running this script again; the cert is reused."
