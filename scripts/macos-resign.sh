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
#   ./macos-resign.sh                                   # = sign
#   ./macos-resign.sh sign                              # explicit
#   ./macos-resign.sh sign /Applications/letsflutssh.app
#   ./macos-resign.sh uninstall                         # remove cert
#   ./macos-resign.sh help
#
# The `sign` action is idempotent — re-running with the same cert
# name just re-signs the bundle in place. `uninstall` removes the
# personal cert from the login keychain and the user-trust database;
# the app itself stays installed but the keychain items written under
# the cert become unreadable (that is the point — opting back out).
#
# Shipped alongside the macOS DMG in the GitHub release assets; the
# README → macOS Installation section points at the same file.

set -euo pipefail

CERT_NAME="LetsFLUTssh Self-Sign"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
DEFAULT_APP_PATH="/Applications/letsflutssh.app"

log() { printf '\e[36m==>\e[0m %s\n' "$1"; }
warn() { printf '\e[33m!!!\e[0m %s\n' "$1" >&2; }
die() { printf '\e[31mERR\e[0m %s\n' "$1" >&2; exit 1; }

# ── platform sanity — runs for every sub-command ─────────────────────
[ "$(uname -s)" = "Darwin" ] || die "This script is macOS-only."
command -v security >/dev/null 2>&1 || die "Missing \`security\` CLI."

print_usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [sign]   [APP_PATH]   Create (if absent) a personal
                                         code-signing cert and re-sign
                                         the installed .app with it.
                                         APP_PATH defaults to
                                         $DEFAULT_APP_PATH.
  $(basename "$0") uninstall             Delete the personal cert from
                                         the login keychain and the
                                         user-trust DB. The .app stays
                                         installed.
  $(basename "$0") help                  Print this help.
USAGE
}

# ─────────────────────────────────────────────────────────────────────
#  sign — create cert (if absent), re-sign app, drop quarantine
# ─────────────────────────────────────────────────────────────────────
sign_action() {
  local app_path="${1:-$DEFAULT_APP_PATH}"
  [ -d "$app_path" ] || die "App bundle not found: $app_path"
  command -v codesign >/dev/null 2>&1 \
    || die "Missing \`codesign\` — install Xcode Command Line Tools via \`xcode-select --install\`."
  command -v openssl >/dev/null 2>&1 || die "Missing \`openssl\`."

  # ── create cert if absent ─────────────────────────────────────────
  if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    log "Using existing self-signed cert: $CERT_NAME"
  else
    log "Creating self-signed code-signing cert: $CERT_NAME"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064  # deliberate single-expansion
    trap "rm -rf '$tmp'" RETURN

    # OpenSSL config for a cert with codeSigning EKU. macOS accepts
    # certs with this extended-key-usage as code-signing identities.
    cat > "$tmp/cert.cnf" <<CFG
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
      -config "$tmp/cert.cnf" \
      -extensions v3_req \
      -keyout "$tmp/cert.key" \
      -out    "$tmp/cert.crt" \
      >/dev/null 2>&1 \
      || die "openssl cert generation failed"

    # Bundle into a PKCS#12 so the `security import` call below gets
    # both cert + private key in one artefact.
    openssl pkcs12 -export \
      -in "$tmp/cert.crt" \
      -inkey "$tmp/cert.key" \
      -out "$tmp/cert.p12" \
      -name "$CERT_NAME" \
      -passout pass:lfs-transient \
      >/dev/null 2>&1 \
      || die "p12 bundle failed"

    # Import into the user's login keychain — no admin needed.
    security import "$tmp/cert.p12" \
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
      "$tmp/cert.crt" \
      || die "add-trusted-cert failed — cert was NOT trusted; re-run the script to retry."
    log "Cert created and trusted for code signing (user-only)."
  fi

  # ── sign the bundle ───────────────────────────────────────────────
  #
  # `sudo` is needed because /Applications/letsflutssh.app is owned
  # by root after drag-to-Applications. If the user installed to
  # ~/Applications we can skip it; detect by write-probing the
  # bundle.
  local sudo_cmd=""
  if [ ! -w "$app_path" ]; then
    sudo_cmd="sudo"
    log "\`$app_path\` is not writable by you — the codesign step will use sudo."
  fi

  log "Re-signing $app_path with \"$CERT_NAME\" (deep + force)…"
  $sudo_cmd codesign --force --deep --sign "$CERT_NAME" "$app_path" \
    || die "codesign failed."

  $sudo_cmd codesign --verify --deep --strict --verbose=2 "$app_path" >/dev/null \
    || die "codesign verify failed after re-sign."

  # Remove the quarantine attribute that the DMG download attached,
  # so Gatekeeper does not also hold the app back.
  $sudo_cmd xattr -cr "$app_path" 2>/dev/null || true

  log "Done. Launch \"$app_path\" — the T1 (keychain) tier should now work."
  log "Future releases can be re-signed by running this script again; the cert is reused."
}

# ─────────────────────────────────────────────────────────────────────
#  uninstall — remove cert + trust entry; leave the .app alone
# ─────────────────────────────────────────────────────────────────────
uninstall_action() {
  log "Removing self-signed cert: $CERT_NAME"

  if ! security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    log "No \"$CERT_NAME\" cert found in $KEYCHAIN — nothing to remove."
    log "If an earlier \`sign\` run created a cert under a different keychain,"
    log "open Keychain Access and delete it manually."
    return 0
  fi

  # Drop the trust entry first so the `delete-certificate` call below
  # does not leave a dangling trust-DB pointer.
  warn "About to run \`security remove-trusted-cert\` — macOS may prompt for your password."
  security remove-trusted-cert -d "$KEYCHAIN" >/dev/null 2>&1 || {
    # `-d` is the user-domain equivalent; different macOS versions
    # differ on which domain the earlier `add-trusted-cert` wrote to.
    # Best-effort: fall through to direct deletion and let the
    # dangling entry (if any) get cleaned up by the cert removal.
    warn "remove-trusted-cert reported an error (harmless if no trust entry existed)."
  }

  # Delete the cert + its private key. `-t` narrows to cert objects;
  # `-c` matches by common-name. The private key sitting under the
  # same label is swept by `delete-identity`.
  security delete-identity -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1 \
    || warn "delete-identity: nothing matched (cert may have been partial)."
  security delete-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1 \
    || warn "delete-certificate: nothing matched (cert may already be gone)."

  log "Cert removed. The .app stays installed but any keychain items"
  log "written under the cert are now unreadable — first launch under"
  log "the original ad-hoc signature will surface the wizard again,"
  log "giving you a chance to pick a re-sign-free tier (Paranoid / T0)."
}

# ─────────────────────────────────────────────────────────────────────
#  dispatch
# ─────────────────────────────────────────────────────────────────────
case "${1:-sign}" in
  sign)      shift || true; sign_action "$@" ;;
  uninstall) shift || true; uninstall_action "$@" ;;
  help|-h|--help) print_usage ;;
  /*|./*)    # raw path — back-compat with the single-action v1 script
             sign_action "$1" ;;
  *) die "Unknown action: $1 (try \`$(basename "$0") help\`)" ;;
esac
