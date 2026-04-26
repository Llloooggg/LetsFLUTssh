# Rust migration — next pass

Live, internal-only tracker for the next migration arc. Each
step is one commit. Order picks low-risk + high-test-leverage
wins first so intermediate states stay shippable.

This file is transient — delete once the arc closes.

## Goal

Drop every Dart logic path that has a Rust counterpart already
landed (or trivially portable). After this arc, the Dart layer
contains only:

1. UI (Flutter widgets, Riverpod providers, dialogs, navigation).
2. Platform glue not movable to Rust (`dart:io` shells, system
   `MethodChannel` plugins, `path_provider`, `local_auth` UI,
   Android foreground service binding).
3. Thin model classes the UI binds to (`Session`, `Tag`,
   `Snippet`, `SshKeyEntry`).
4. Riverpod state mirrors driven by bus events.

## Sequencing

### Step 1 — flutter_test FRB bootstrap

**Status:** REJECTED — `RustLib.init`'s `executeRustInitializers`
calls `crateApiInitApp` which spins up `AppState` + opens default
DAO connections. Widget tests with Riverpod `overrideWith`
mocks then fail because the FRB calls succeed against a half-
initialized AppState instead of falling through into the test's
mock store. ~50 widget-test regressions vs the ~10 currently-
skipped suites this would un-skip.

The right fix is `initMock` with a per-suite mock RustLibApi —
that's a separate arc-sized port. Until then the skip-marked
suites stay skipped and the Dart fallbacks in sanitize +
password_strength stay live.

**Why first:** unblocks dropping the sanitize + password_strength
Dart fallbacks (Step 2). Also un-skips 6+ test files marked
`skip:` in the previous arc. Highest test-coverage leverage per
LOC.

**Touches:**
- `test/flutter_test_config.dart` (new) — top-level test config
  that runs `await RustLib.init(externalLibrary: ExternalLibrary.open(<path>))`
  before every suite. Path resolves to the cargokit / cargo build
  output for `liblfs_frb.{so,dylib,dll}` keyed off the platform.
- `Makefile` — new `rust-build-test` target that runs
  `cargo build --release -p lfs_frb` and prints the resulting
  artefact path.
- `test/utils/sanitize_test.dart` (already imports Dart fallback)
  + `test/core/security/password_strength_test.dart` etc — un-skip
  once init lands.

**Risk:** Path resolution per platform. Linux uses
`rust/target/release/liblfs_frb.so`; macOS uses
`liblfs_frb.dylib`; Windows uses `lfs_frb.dll`. The init call
needs to pick the right one off `Platform.isLinux` etc.

### Step 2 — drop sanitize + password_strength Dart fallbacks

**Status:** BLOCKED ON STEP 1 — fallbacks fire today only because
flutter_test does not load the FRB native lib. Until Step 1
lands a working init+mock surface, dropping the fallbacks would
break ~200 widget tests that pipe error strings through
`sanitizeError` or render `PasswordStrengthMeter`.

**Why second:** Step 1 makes them dead weight. Fallbacks were
retained earlier only because flutter_test would crash without
them.

**Touches:**
- `lib/utils/sanitize.dart` — drop `_redactSecretsDart` /
  `_sanitizeErrorMessageDart`.
- `lib/core/security/password_strength.dart` — drop
  `_dartFallback`.

**Risk:** Catches anywhere in the codebase that depend on the
fallback firing. Step 1 wires init globally so
`PasswordStrengthMeter` widget builds and AppLogger sanitiser
pipe both work.

### Step 3 — DeepLinkHandler URI parser → Rust

**Status:** TODO

**Why third:** Pure parser. Zero side effects, no platform
dependency. Small port (~230 LOC Dart → ~150 LOC Rust).

**Touches:**
- `rust/crates/lfs_core/src/deeplink.rs` (new) — `parse_connect_uri`
  + `parse_qr_payload` URL parser.
- `rust/crates/lfs_frb/src/api/deeplink.rs` — FRB binding.
- `lib/core/deeplink/deeplink_handler.dart` — replace the parsing
  body with a single FRB call. Keeps the Dart class for the
  app_links subscription + dispatch.
- Tests: `test/core/deeplink/deeplink_handler_test.dart` already
  has fuzz coverage; goes in step 1's fixed bootstrap.

**Risk:** The fuzz test pumps 2k random URI inputs — must round-
trip identically to the Dart pipeline.

### Step 4 — recorder asciinema event composition → Rust

**Status:** TODO

**Why fourth:** Last bit of recorder logic Dart-side. The
`jsonEncode([delta, dir, str])` + UTF-8 sequence runs per frame;
encoding it Rust-side keeps the asciinema interop format
canonical in one place and lets us add a typed `event_type`
discriminator without two parallel codecs.

**Touches:**
- `lfs_core::recorder` — extend with
  `record_terminal_event(id, dir, bytes_at: ts, plaintext_bytes)`
  that composes the JSON line + frame internally. `record_frame`
  stays for the asciinema header (Dart still owns the header
  shape because PTY size + shell label arrive at register time).
- `lib/core/session/session_recorder.dart` — drop `_enqueueEvent`
  + the inline jsonEncode; switch `recordOutput` / `recordInput`
  to call the new endpoint. Header stays Dart-side.

**Risk:** Tests for plaintext recordings asserting on byte-exact
asciinema output stay green only if the JSON serialisation is
byte-identical to Dart's `jsonEncode`.

### Step 5 — KnownHostsManager → Rust

**Status:** TODO

**Why fifth:** TOFU host-key DB. Security-critical. ~573 LOC
moves to Rust. Connect path's host-key callback would resolve
inside the Rust actor without round-tripping fingerprints to
Dart.

**Touches:**
- `rust/crates/lfs_core/src/known_hosts.rs` (new or extend) —
  load / persist / match / add / remove host keys against the
  same on-disk format the Dart side reads.
- `rust/crates/lfs_frb/src/api/known_hosts.rs` — FRB binding.
- `lib/core/ssh/known_hosts.dart` — slim into a Dart wrapper
  around the FRB calls. Stream subscriber for the host-key
  prompt UI stays Dart.
- `core/connection/connection_manager.dart` — host-key prompt
  handler reads off a bus event published by the actor.
- Connect path: bus actor wires the host-key verifier so TOFU
  decisions land Rust-side without crossing FRB.

**Risk:** On-disk format compatibility — current Dart
`KnownHostsManager` uses a custom line-oriented format.
Migration tests must confirm round-trip equality.

### Step 6 — UpdateService → Rust

**Status:** TODO

**Why sixth:** HTTP fetch + SHA-256 + Ed25519 verify all live in
crypto already. ~500 LOC drops Dart-side. Keep the OS-specific
file launcher (`open` / `xdg-open` / `start`) Dart because it
has to hand off to a privileged installer.

**Touches:**
- `rust/crates/lfs_core/src/update.rs` (new) — Reqwest-based
  fetch with redirect cap + trusted-host allowlist + cert
  pinning. Verifies the `.sig` against pinned Ed25519 keys.
  Streams progress through the bus.
- `rust/crates/lfs_frb/src/api/update.rs` — FRB binding.
- `lib/core/update/update_service.dart` — slim into Riverpod
  state mirror that subscribes to the bus + dispatches a
  `BusCommand::UpdateCheck` / `UpdateDownload`. File launcher
  stays.

**Risk:** Cert pinning logic. `cert_pinning.dart` has SPKI hash
extraction that's tightly tied to Dart's HTTP client; Rust does
the equivalent through `rustls` + the pinned-leaf list.

### Step 7 — migration_runner → Rust

**Status:** TODO

**Why seventh:** config.json + credentials.kdf migration runs
during startup before UI mounts. ~365 LOC. Logic is format-
versioning + transform — canonically Rust now that the formats
themselves live in Rust.

**Touches:**
- `rust/crates/lfs_core/src/migration.rs` (new) — `Migration`
  trait + `MigrationRegistry` + `run_for_artifact(name, blob)`.
- `rust/crates/lfs_frb/src/api/migration.rs` — FRB binding.
- `lib/core/migration/*.dart` — slim into glue that calls the
  Rust runner per artefact at boot.

**Risk:** Migration ordering. The current Dart registry walks
artefacts in a known order; the Rust runner must preserve that
or boot can fail mid-migration on existing installs.

### Step 8 — PortForwardRuntime → Rust actor

**Status:** TODO

**Why eighth:** Largest hot-path drop (~691 LOC). Plan in
`RUST_CORE_MIGRATION_PLAN.md` already had a `forward::driver`
crate with `ChannelFactory` + listener accept loops; the actor
wraps it for connection-scoped lifecycle.

**Touches:**
- `rust/crates/lfs_core/src/portforward/actor.rs` (new) —
  per-connection actor that owns `-L` / `-R` / `-D` listeners,
  publishes `ForwardOpened` / `ForwardBytes` / `ForwardClosed`
  events.
- `rust/crates/lfs_frb/src/api/portforward.rs` — FRB binding for
  the actor commands.
- `lib/core/ssh/port_forward_runtime.dart` — slim into a bus
  subscriber + state mirror.

**Risk:** Hot path; mobile platforms exercise this heavily for
ProxyJump bastion chains. Smoke-test on Android + Linux after
landing.

### Step 9 — Security tier orchestration → Rust

**Status:** TODO (large; defer until 1–8 land)

**Why last:** ~1700 LOC across master_password +
password_rate_limiter + hardware_tier_vault +
keychain_password_gate + security_bootstrap +
biometric_key_vault. Touches every platform's secure storage:
Linux Secret Service / TPM, macOS Keychain, Windows DPAPI /
WinBio. Rust ports of the platform clients already landed
(`platform/linux/tpm.rs`, `platform/macos/keychain.rs`,
`platform/winbio.rs`); this step composes them into the tier
orchestration that today lives Dart-side.

**Touches:**
- `rust/crates/lfs_core/src/security/tier.rs` (new) — tier
  state machine.
- `rust/crates/lfs_core/src/security/master_password.rs` (new)
  — KDF + verify + tier promotion.
- `rust/crates/lfs_core/src/security/rate_limit.rs` (new) —
  exponential backoff against repeated wrong attempts.
- `rust/crates/lfs_frb/src/api/security.rs` — FRB binding.
- `lib/core/security/*.dart` — slim into Riverpod-bound mirror.

**Risk:** Highest of the arc. Startup flow + lock/unlock UX +
TPM / biometric sealing all converge here. Land on a separate
branch, smoke-test on every platform before merge.

## Out of scope (feature work, not migration)

- #149 mobile pipelines (Android / iOS native plugins).
- #121 / #122 / #159 WebDAV / S3 / WebDAV-browser features.
- macOS / Windows hardware verification — needs target hardware
  in CI.

## Order at a glance

```
1. flutter_test FRB bootstrap         — small, unblocks tests
2. drop sanitize + pw fallbacks       — trivial after 1
3. DeepLinkHandler parser → Rust      — small isolated port
4. Recorder asciinema → Rust          — small, last recorder bit
5. KnownHostsManager → Rust           — medium, security-critical
6. UpdateService → Rust               — medium, HTTP + sigs
7. MigrationRunner → Rust             — medium, startup-only
8. PortForwardRuntime → Rust actor    — large hot-path drop
9. Security tier stack → Rust         — largest, defer
```

After Step 9: every load-bearing path runs Rust. Dart layer
is widgets + Riverpod + platform glue + thin models.
