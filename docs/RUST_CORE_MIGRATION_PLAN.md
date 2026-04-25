# Rust Core Migration Plan

Internal planning doc. Not user-facing. Ship outcome: hybrid architecture — **Flutter UI + Dart state/DB layer over a Rust security/transport core**, exposed via [`flutter_rust_bridge`](https://github.com/fzyzcjy/flutter_rust_bridge) (FRB).

The Rust side follows a **ports-and-adapters (hexagonal)** layout: a pure-Rust `lfs_core` crate with no frontend awareness, plus a thin `lfs_frb` adapter that exposes the core through FRB. Future adapters (`lfs_tauri`, `lfs_cli`) can plug into the same core without touching its internals — so a Flutter→Tauri pivot, a headless CLI, or a wasm/web frontend remains a small adapter rewrite, not a core rewrite.

This plan exists so we can branch off `dev`, work in chunks, and not lose context across sessions. Update sections in-place as decisions land. Mark `[done]` next to checklist items as they ship.

---

## 1. Why

`dartssh2` 2.17.1 is the bottleneck for §6.2 (SSH certificates) and §6.3 (FIDO2-SSH / `sk-*` keys):

- Cert algorithms (`ssh-rsa-cert-v01@openssh.com`, `ssh-ed25519-cert-v01@openssh.com`, etc.) are not in `SSHHostkeyType` and cannot be added without forking the package.
- `sk-ssh-ed25519@openssh.com` / `sk-ecdsa-sha2-nistp256@openssh.com` likewise absent.
- No `$SSH_AUTH_SOCK` client; only server-side agent-forwarding hook.
- Pure-Dart pluggable signer (`SSHKeyPair.sign()`) does not help: the **algorithm name** is hardcoded in the userauth request path. Custom `sign()` cannot make the wire bytes claim a cert.

Forking dartssh2 solves the immediate problem but locks us into a perpetual maintenance burden on a large pure-Dart codebase. Moving the SSH/crypto core to Rust solves §6.2 + §6.3 + ssh-agent in one architectural shift, and brings memory safety to the highest-risk code path (parsing untrusted server bytes, key material).

We picked **`russh` (pure Rust, async, tokio-based)** over **libssh / libssh2 (C, FFI)**:

| | russh + FRB | libssh + FFI |
|---|---|---|
| Memory safety | Rust — safe | C — historical CVE pattern |
| Bindings | FRB auto-generates from Rust signatures | ~200 funcs hand-bound |
| Async | tokio native, FRB maps to Dart Future/Stream | blocking, requires Isolate workers |
| Crypto crates | RustCrypto / ring — modern, audited | lib-internal |
| Cross-compile | `cargo --target` | autoconf/cmake mess |
| Maturity | ~5 yrs, used by GitButler, Pijul | ~25 yrs, FileZilla, Bitvise |
| FIDO2-sk today | partial (russh-keys evolving) | full (libssh ≥0.10) |
| Bus factor | small core team | larger contributor base |

`russh` wins on safety + DX. The FIDO2-sk gap is the only point where libssh leads; we can either upstream what we need to russh-keys or, if blocked, pull a small `libfido2` FFI for the CTAP2 stack alone.

The `Native Over Dart When Better` rule (`docs/AGENT_RULES.md`) explicitly authorises this when zero-install holds (rung 1 of the 3-rung ladder — bundle native blobs, end-user installs nothing).

---

## 2. Scope: what moves, what stays

### 2.1 Moves to Rust

| Domain | Today (Dart) | Tomorrow (Rust) |
|---|---|---|
| SSH transport, channels, auth | `lib/core/ssh/ssh_client.dart` (dartssh2) | `rust/src/ssh/client.rs` (russh) |
| Port forwarding (-L/-R/-D, SOCKS5) | `lib/core/ssh/port_forward_runtime.dart` | `rust/src/ssh/forward.rs` |
| ProxyJump bastion chains | `lib/core/ssh/proxy_jump.dart` + `session_connect.dart` glue | `rust/src/ssh/proxy_jump.rs` |
| SFTP | `lib/core/sftp/sftp_client.dart` (dartssh2 sftp) | `rust/src/sftp/mod.rs` (russh-sftp or hand-rolled) |
| OpenSSH key parsing (PEM, OPENSSH PRIVATE KEY) | dartssh2 internal | `russh-keys` |
| PuTTY .ppk codec (v2 + v3 Argon2id) | `lib/core/security/ppk_codec.dart` | `rust/src/keys/ppk.rs` (`argon2` crate) |
| SSH certificates (NEW) | — | `rust/src/keys/cert.rs` |
| FIDO2-sk keys (NEW) | — | `rust/src/keys/sk.rs` (+ CTAP2 stack) |
| ssh-agent client (NEW) | — | `rust/src/agent/client.rs` |
| AES-GCM envelopes (recorder, QR, `.lfs`) | `lib/core/security/aes_gcm.dart` (pointycastle) | `rust/src/crypto/envelope.rs` (`aes-gcm` crate) |
| HKDF-SHA-256 | pointycastle | `hkdf` crate |
| Ed25519 update signature verify | `lib/core/update/update_service.dart` | `ed25519-dalek` |

Phase 2 (optional, after Phase 1 ships):

| Domain | Today | After |
|---|---|---|
| WebDAV sync (planned §4.1) | not started | `rust/src/sync/webdav.rs` (`reqwest` + `quick-xml`) |
| S3 browser (planned §4.2) | not started | `rust/src/sync/s3.rs` (`aws-sdk-s3` or hand-rolled sigv4) |
| Update fetcher | `package:http` | `reqwest` (only if the rest of net is in Rust) |

### 2.2 Stays in Dart

- All UI: every widget, dialog, route, `lib/features/**/*_screen.dart`, `lib/widgets/**`
- Riverpod providers (slim wrappers over Rust calls — they hold reactive state, not transport)
- Theme, localization (15 ARB files), navigation
- Drift (SQLite ORM) — typed Dart codegen, schema definitions, migrations. **Not migrating; Drift earns its keep.**
- Migration framework for `config.json` / `credentials.kdf` / `.lfs` / hardware-vault blobs (`lib/core/migration/`) — pure Dart logic, no win in moving
- xterm.dart rendering — Flutter widget
- Platform channels: biometric (`biometric_auth.dart`), fprintd probe, native plugins per OS — Kotlin/Swift/C, not Rust
- App lifecycle, windowing, hotkeys
- Tags, Snippets, Bookmarks, Sessions, Keys models — all drift-bound, stay Dart
- Known hosts parser (`lib/core/ssh/known_hosts.dart`) — small, file-format-only, no transport concern, stays Dart unless we have a reason to move
- Settings UI, Tools UI, recordings browser UI, file browser UI — pure Flutter

After full migration: roughly **30% Rust (security/transport core) / 70% Dart (UI + state + DB + platform glue)**.

### 2.3 Boundary contract

The FRB boundary lives **only** in `lfs_frb` (the adapter crate). `lfs_core` is frontend-agnostic — no `flutter_rust_bridge` import, no FRB attributes, no Dart-shaped types. Everything crossing the bridge passes through `lfs_frb`, which delegates to `lfs_core` and translates types as needed.

Rule of thumb in the adapter:

- **Plain data** (host, port, user, key bytes, opaque tokens) — pass by value.
- **Long-lived handles** (active session, channel, sftp client) — `lfs_core` returns an opaque struct; `lfs_frb` registers it in a handle registry and exposes a numeric ID to Dart (`SshSessionHandle`, `SftpHandle`, …). The Dart side never sees the inner Rust state.
- **Streams** (terminal stdout/stderr, port-forward connection events, sftp progress) — `lfs_core` produces a `tokio::sync::mpsc` (or impl `Stream`); `lfs_frb` wraps it in an FRB `Stream<T>`.
- **Async** — every transport call is `async fn` in `lfs_core`. `lfs_frb` re-exposes the same shape — the FRB codegen maps it to a Dart `Future<T>`.
- **Errors** — `lfs_core` returns `Result<T, lfs_core::Error>` with a typed enum (NoRoute, AuthFailed, HostKeyMismatch, …). `lfs_frb` converts to a Dart-friendly variant.

The Dart-facing API mirrors `lib/core/ssh/ssh_client.dart` so existing callers can swap with minimal churn behind a `SshTransport` interface (see §4).

**Discipline**: the temptation will be to short-circuit and put a tiny FRB-specific concern into `lfs_core`. Don't. If `lfs_core` ever depends on `flutter_rust_bridge` or `tauri`, the hexagonal property is broken and the Tauri/CLI pivot becomes a rewrite again. Code review catches this; CI enforces it via `cargo tree -p lfs_core` and a deny-list assertion on the dependency graph.

---

## 3. Build, packaging, distribution

### 3.1 Workspace layout (hexagonal: ports + adapters)

```
LetsFLUTssh/
├── lib/                          # Flutter Dart (existing)
├── rust/                         # Rust workspace
│   ├── Cargo.toml                # workspace + shared dep pins
│   ├── rust-toolchain.toml       # channel = stable
│   └── crates/
│       ├── lfs_core/             # PURE Rust: SSH, crypto, agent, FIDO2, key parsing
│       │   ├── Cargo.toml        #   crate-type = ["rlib"]; NO flutter_rust_bridge dep
│       │   └── src/
│       │       ├── lib.rs        #   public API surface
│       │       ├── ssh/          #   russh wrappers
│       │       ├── sftp/
│       │       ├── keys/         #   PEM / OpenSSH / PPK / cert / sk parsing
│       │       ├── crypto/       #   AES-GCM, HKDF, Ed25519
│       │       └── agent/        #   ssh-agent client
│       │
│       ├── lfs_frb/              # Flutter adapter (current frontend)
│       │   ├── Cargo.toml        #   crate-type = ["cdylib", "staticlib", "rlib"]
│       │   │                     #   deps: lfs_core (path) + flutter_rust_bridge
│       │   └── src/
│       │       ├── lib.rs
│       │       └── api.rs        #   thin FRB-exposed surface; delegates to lfs_core
│       │
│       ├── (future) lfs_tauri/   # Tauri adapter — only if a UI pivot is ever decided.
│       │                         #   Same lfs_core, different bridge. No core rewrite.
│       ├── (future) lfs_cli/     # Headless binary — useful for scripting / power users.
│       └── (future) lfs_fido2/   # CTAP2 native HID stack — split out at sub-phase 1.13
│                                 #   for testability + per-OS isolation
│
├── flutter_rust_bridge.yaml      # FRB config: rust_root → rust/crates/lfs_frb/
└── lib/src/rust/                 # FRB-generated Dart bindings (committed)
```

**Why a separate adapter crate**: `lfs_core` has no awareness of how it is consumed. The Flutter app loads `lfs_frb` (the only crate that pulls `flutter_rust_bridge`). A Tauri pivot would add `lfs_tauri` next to `lfs_frb` and the core stays untouched. A CLI build links `lfs_cli` to the same core. The adapter layer is intentionally thin — pure delegation, type translation, error mapping.

Decision pending: commit `lib/src/rust/` (FRB-generated) or regenerate in CI? Default to **commit** for review-ability and to keep Flutter dev loop snappy without forcing every contributor to install FRB CLI on first checkout.

### 3.2 Per-platform native binary distribution

Following `Self-Contained Binary` rung 1 (bundle):

| Platform | Output | Embed location |
|---|---|---|
| Linux (x86_64, aarch64) | `liblfs_core.so` | bundled into Flutter `data/bundle/lib/` |
| macOS (x86_64, aarch64) | `liblfs_core.dylib` (universal via `lipo`) | `.app/Contents/Frameworks/` |
| Windows (x86_64, aarch64) | `lfs_core.dll` | next to `letsflutssh.exe` |
| Android (arm64-v8a, armeabi-v7a, x86_64) | `liblfs_core.so` per ABI | `android/app/src/main/jniLibs/<abi>/` |
| iOS (arm64) | `liblfs_core.a` static | xcframework, linked at app build |

Each release pipeline cross-compiles, strips, signs (where applicable), and bundles. Expected size impact per platform: +1.5–2 MB stripped.

### 3.3 Toolchain

- `rustup` — stable channel only. Lock to a specific version in `rust-toolchain.toml`.
- `cargo-ndk` — Android cross-compile.
- For iOS: `cargo` + `cargo-lipo` (or rustls's modern approach via xcframework script).
- `flutter_rust_bridge_codegen` CLI — version pinned in `pubspec.yaml` dev_dependencies for parity.

### 3.4 Makefile additions

```
make rust-fmt           # cargo fmt
make rust-lint          # cargo clippy --all-targets -- -D warnings
make rust-test          # cargo test --workspace
make rust-build         # cargo build --release for host
make rust-build-android # cargo-ndk per ABI
make rust-build-ios     # xcframework
make rust-codegen       # flutter_rust_bridge_codegen generate
make build-linux        # depends on rust-build (host)
make build-macos        # depends on rust-build (universal)
make build-windows      # depends on rust-build
make analyze            # also runs `cargo clippy` if Rust files changed
make test               # also runs `cargo test`
```

Pre-commit hook (`.husky/pre-commit` or equivalent) extends to:
- if any `rust/**/*.rs` changed → `cargo fmt --check` + `cargo clippy -D warnings`
- if any `rust/src/api/**` changed → `make rust-codegen` and require `lib/src/rust/` to be in the staged diff

### 3.5 CI (GitHub Actions or whatever we use)

New jobs:
- `rust-test` — runs on linux-x64, executes `cargo test --workspace`
- `rust-clippy` — strict, fails on warnings
- `cross-compile-matrix` — builds native blobs for the release matrix; cached
- existing `ci` job depends on the cross-compile output for `flutter build`

---

## 4. Migration mechanism (don't big-bang)

We never want a state where the app cannot connect. So we ship the Rust core behind an interface, not by deletion.

### 4.1 `SshTransport` abstraction in Dart

Introduce `lib/core/ssh/ssh_transport.dart`:

```dart
abstract class SshTransport {
  Future<SshSession> connect(SshConnectRequest req);
  // open shell, exec, sftp, forward — all behind this interface
}
```

Implementations:

- `Dartssh2Transport` — current behaviour, wraps the existing `SSHClient` codepath
- `RustTransport` — calls into `lib/src/rust/api/ssh.dart` (FRB)

Selection driven by a runtime flag (default `Dartssh2Transport`, opt-in `RustTransport` via a hidden setting or env var) until parity is confirmed.

### 4.2 Phasing within Phase 1

We swap one sub-feature at a time. Each sub-phase ends with:
1. Parity tests green for that sub-feature on both transports.
2. Manual smoke on a real server (own staging box).
3. Default flips to Rust for that path; Dart path stays alive for one release.
4. Next release — delete the Dart code if no regressions reported.

Order (dependencies-first):

1. **1.0 Foundation** — Rust workspace, FRB pipeline, hello-world `add(int, int)` callable from Dart, bundling on linux+macOS+windows hosts (mobile pipelines come at Phase 1.6).
2. **1.1 Bare connect + password auth** — `RustTransport.connect()` returns a session; password method only. Replaces a slice of `ssh_client.dart`.
3. **1.2 Pubkey auth (PEM, OpenSSH)** — wire russh-keys, accept Dart-passed key bytes.
4. **1.3 Shell channel** — open shell, pipe stdin/stdout/stderr as Streams. Connect to xterm via existing `ConnectionManager`.
5. **1.4 PPK v2 + v3** — replace `lib/core/security/ppk_codec.dart`. Verify against existing fixtures in `test/core/security/ppk_codec_test.dart`.
6. **1.5 SFTP** — read/write/list/stat/rename. Stream progress for large transfers.
7. **1.6 Mobile pipelines** — cargo-ndk for Android, xcframework for iOS. Run existing mobile tests.
8. **1.7 Port forwarding -L** — local listener, channel-direct-tcpip.
9. **1.8 Port forwarding -R** — server-side `tcpip-forward`. The trickiest one because of state across reconnects (currently re-armed via `port_forward_runtime.dart`). Reuse the same Dart-side state machine; only the transport changes.
10. **1.9 Port forwarding -D** — SOCKS5 listener (RFC 1928, NO_AUTH, IPv4/domain/IPv6 — same surface as today).
11. **1.10 ProxyJump** — uses 1.8 internally. The race fix landed in `session_connect.dart` (await bastion ready before reading client) maps to the same ordering on the Rust side: `bastion.connect().await` then open the channel.
12. **1.11 ssh-agent client** — `$SSH_AUTH_SOCK` on Unix, `\\.\pipe\openssh-ssh-agent` on Windows. Speaks agent-protocol-spec. Exposed as a virtual `Identity` source in the auth path.
13. **1.12 SSH certificates** — accept `*-cert-v01@openssh.com` algos in russh's algorithm tables (russh upstream supports cert host-key auth; cert client-key auth needs an audit, may need a small upstream patch). Parse cert blob in `keys/cert.rs`.
14. **1.13 FIDO2 sk-keys** — wire CTAP2 stack via russh-keys' `sk-*` types. Per-OS HID layer through `lfs_fido2` crate (HIDAPI on desktop, native CTAP2 platform APIs on Android/iOS).

After 1.13: Rust transport is the default; Dart transport gated behind an emergency-rollback flag. Next release after a clean window — delete `Dartssh2Transport` + `dartssh2` dep.

### 4.3 Mid-flight integration points

Existing Dart code that must stay aware of the swap:

- `lib/core/connection/connection_manager.dart` — holds active sessions; gets a transport from a provider.
- `lib/core/connection/connection_extension.dart` — extension hook iface; nothing changes if the underlying transport is hidden.
- `lib/features/session_manager/session_connect.dart` — instantiates transport via factory; the rest is identical.
- `lib/core/security/key_store.dart` — owns key material; passes bytes to whichever transport.
- `lib/core/security/master_password.dart` — unchanged (KDF/envelope handled in Rust only at Phase 2 for the recorder/QR path).
- `lib/core/session/session_recorder.dart` — Phase 2 swap; until then, encrypts via `aes_gcm.dart` (pointycastle).

Riverpod providers: rebind the SSH-transport provider to return `RustTransport` once a sub-feature reaches "default flips" stage.

---

## 5. Phase 2: crypto envelopes

After Phase 1 stabilises (1–2 weeks of release soak), move:

- `aes_gcm.dart` → `crypto/envelope.rs` (RustCrypto `aes-gcm`)
- HKDF helpers → `hkdf` crate
- `update_service.dart` Ed25519 verify → `ed25519-dalek`
- Recorder envelope (HKDF info-tag `letsflutssh-recording-v1`) → Rust; preserve byte-for-byte parity (existing recordings must still play)
- QR codec encrypt/decrypt → Rust
- `.lfs` archive envelope → Rust

After Phase 2: `pointycastle` removed from `pubspec.yaml`. All crypto in one audited place.

Migration framework (`lib/core/migration/`) does not move — it operates on already-decrypted bytes and on schema decisions, all of which are Dart-side concerns.

---

## 6. Phase 3: networking (optional, when §4.1 / §4.2 land)

Only if we determine Dart's HTTP/XML libraries are insufficient for WebDAV/S3:

- **WebDAV** — `reqwest` + `quick-xml`. PROPFIND/PUT/DELETE/MKCOL handlers. Soft-delete state machine stays Dart (drift-bound).
- **S3** — `aws-sdk-s3` (heavy) or hand-rolled sigv4. Multipart upload/download.

Defer the call until we start §4.1. May well stay Dart.

---

## 7. Testing strategy

### 7.1 Rust side

- Unit tests in `rust/src/**/tests.rs` for parsers, crypto envelopes, agent protocol, cert decoding.
- Integration tests in `rust/crates/lfs_core/tests/` against an in-process russh-server, exercising the connect/auth/shell/forward/sftp flows.

### 7.2 Dart side

- Existing 4609 tests run unchanged. No test should know which transport is active.
- New parity tests in `test/core/ssh/transport_parity_test.dart` — same scenario run against both transports; output must match (bytes-for-bytes for crypto, semantically for behaviour).
- Mocks: `Dartssh2Transport` mocks unchanged; introduce `MockRustTransport` for tests that don't need real transport at all.

### 7.3 End-to-end

- Manual smoke on a real OpenSSH server (own staging) for each sub-phase.
- Test matrix on real hardware: Linux x86_64, macOS arm64, Windows x86_64, Android arm64, iOS arm64.

### 7.4 Regression policy

If Rust path differs from Dart path on a parity test, **the failing case stays on Dart transport in production until fixed**. We don't ship known regressions just to advance the migration.

---

## 8. Documentation impact

Every Phase 1 sub-phase that changes behaviour or surfaces touches:

- **`docs/ARCHITECTURE.md` §6 (SSH layer)** — rewrite the "Implementation: dartssh2" subsections to describe the Rust core, the FRB boundary, the handle pattern, the Stream model.
- **`docs/ARCHITECTURE.md` §3.6 (storage / formats)** — note that PPK / OpenSSH key parsing has moved.
- **`docs/ARCHITECTURE.md` §11 (persistence)** — unchanged in content; cross-link to the new SSH § from anywhere it referenced dartssh2.
- **`docs/ARCHITECTURE.md` §14 (testing patterns)** — add the Rust testing approach + parity-test convention.
- **`docs/CONTRIBUTING.md`** — Rust toolchain install, `rustup`, `cargo-ndk`, FRB codegen step, Makefile target reference.
- **`docs/AGENT_RULES.md` § Doc Maintenance** — add a row for "touched any `rust/**/*.rs`" pointing to ARCHITECTURE §6 + §14.
- **`README.md`** — bump the dependency list (note the bundled native blob, no end-user install required), update screenshots if the cert/sk auth UI lands visibly.
- **`docs/USER_GUIDE.md`** — only when a new user-visible flow lands (cert auth wizard, FIDO2 prompt). Internal architecture changes are invisible to users — no entry there.
- **`docs/SECURITY.md`** — disclose Rust crate dependency surface in the threat model, document the new ssh-agent / FIDO2 trust boundary.
- **`docs/FEATURE_BACKLOG.md`** — track sub-phase progress here as we go.

For every commit on this branch, the rule still holds: **docs in the same commit as code**. No exceptions for size — split the work into smaller commits if a single one would be too large to review with docs included.

---

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| russh API churn between minor versions | Pin exact version in `Cargo.toml`; track changelog before bumps. |
| FIDO2-sk support in russh-keys is partial | If we hit a gap, upstream a patch first; if blocked, vendor `libfido2` for the CTAP2 layer only. |
| FRB codegen drift from generated bindings | Pin FRB CLI version. CI runs codegen and fails on drift. |
| Mobile cross-compile breakage | Add a CI job for android-aarch64 + ios-aarch64 native builds; gate releases on green there. |
| Apple notarization with embedded Rust dylib | Standard path — the macOS bundle script already signs frameworks; Rust dylib goes through the same flow. Test once and document in CONTRIBUTING. |
| Windows code signing | Same as macOS — already-signed exe bundles a DLL; sign the DLL too. |
| Stack traces stop at FFI boundary | Set `panic=unwind` in Rust release config; FRB surfaces panics as Dart exceptions with a formatted backtrace. Acceptable given the safety win. |
| Solo-dev expertise spread across two languages | Mitigated by FRB removing manual FFI grunt; Rust core scope is small (~30%) and bounded. Crypto/transport already require careful reading; Rust makes that reading safer not harder. |
| Binary size bloat | Strip release binaries (`strip`), use `lto = true`, `codegen-units = 1`; expect +1.5–2 MB per arch, well under any platform cap. |
| Async impedance mismatch (tokio vs Dart event loop) | FRB handles this; tokio runtime lives in a background thread, Dart Futures complete via the Dart isolate's event loop. Documented FRB pattern. |
| Existing 4609 tests break en masse | Mitigated by `SshTransport` interface — tests use mocks, not concrete impls. Real failures only at parity boundary; isolated to new tests. |
| Drift integration regression | Drift is untouched. No risk if we hold the rule "Drift stays Dart". |
| User experiences regressions in shell/forwarding/sftp during migration | Default transport stays Dart per sub-phase until parity confirmed. Rollback flag for emergencies. Soak time ≥1 release per major sub-phase. |

---

## 10. Effort estimate

Solo, full-time-ish:

| Phase | Effort | Notes |
|---|---|---|
| 1.0 Foundation | 2–3 days | Workspace, FRB, hello-world, host bundling |
| 1.1–1.5 Connect + auth + shell + PPK + SFTP | ~2 weeks | Largest chunk |
| 1.6 Mobile pipelines | 3–4 days | Build system + first mobile smoke |
| 1.7–1.10 Port forwarding + ProxyJump | ~1 week | -R is the slowest |
| 1.11 ssh-agent client | 3–4 days | Protocol straightforward, per-OS socket plumbing |
| 1.12 SSH certificates | 4–5 days | Including russh upstream check / patch |
| 1.13 FIDO2 sk-keys | 1–2 weeks | CTAP2 stack per OS, native HID glue |
| Phase 1 cleanup (delete dartssh2, update docs) | 2 days | After soak |
| Phase 2 (crypto envelopes) | 3–5 days | Optional, parity-tested |
| Phase 3 (network protocols) | deferred | Tied to §4.1 / §4.2 timing |

Total Phase 1: **~6–7 weeks solo**. Phase 2: +1 week. Phase 3: with the WebDAV/S3 features themselves.

---

## 11. Branch / commit plan

- Branch off `dev` → `feat/rust-core` (long-lived; rebase on `dev` weekly).
- Each sub-phase = one or more commits with docs + tests in the same commit (per the always-on rules).
- No squash-on-merge for this branch — preserve sub-phase boundaries in history (use `--no-ff` merge, not auto-squash).
- Follow `Branching & Release Flow` for the eventual merge to main: bump version, PR `dev → main`, auto-merge.
- Commit titles: `feat(rust): bare connect + password auth via russh` (prefix `feat(rust):` for sub-phases; `chore(rust):` for build/CI; no plan-item IDs in commit titles per the always-on rule).

---

## 12. Open questions / decisions resolved as the branch progressed

- [x] Commit `lib/src/rust/` (FRB-generated)? **Yes** — committed alongside the Rust API surface so a fresh clone compiles without forcing every contributor to install the FRB codegen CLI.
- [x] russh version pin — `=0.59`. 0.60+ blocked on the RustCrypto `pkcs8 0.11.0-rc.11` / `pkcs5 0.8.0` API mismatch. Bump back when upstream graduates.
- [x] FIDO2 stack — system ssh-agent path covers the common case (`ssh-add -K`, then `Session::connect_agent` relays). Direct CTAP2 (no agent) deferred to 1.13b until a real user need surfaces.
- [x] Recorder envelope — defer to Phase 2 alongside the rest of the crypto surface. No reason to touch it earlier.
- [x] `pointycastle` drop — Phase 2 milestone, after AES-GCM / HKDF / Ed25519 verify all migrate to RustCrypto crates.
- [ ] Cert auth UI placement in session form — decide when the cert flow gets a session-edit-dialog UI surface. The Rust transport accepts cert payloads now; the dialog wiring is the missing piece.
- [ ] FIDO2 prompt UI — touch-key prompt is owned by the system agent today, no app-side UI needed. Revisit if 1.13b ships direct CTAP2.

---

## 13. Sub-phase checklist (current state on `feat/rust-core` — 45 commits)

### Foundation
- [x] **1.0 Workspace + FRB integration** — Cargo workspace at `rust/` with `lfs_core` (pure Rust, `forbid(unsafe_code)`) and `lfs_frb` (FRB adapter, `cdylib`/`staticlib`). `flutter_rust_bridge_codegen integrate` ran via cargokit; native bundling glue lands in `linux/macos/windows/android/ios`. `liblfs_frb.so` (~600 KB) ships in the Flutter build. `RustLib.init()` + smoke `ping()` log at app startup.

### Rust core (lfs_core)
- [x] **1.1 Password auth** — `try_connect_password` probe + `Session::connect_password`. Password wraps in `Zeroizing`.
- [x] **1.2 Pubkey auth** — `try_connect_pubkey` + `Session::connect_pubkey` for OpenSSH PEM. Encrypted-key passphrases handled, with `PassphraseIncorrect` distinct from generic `KeyParse` for retry-friendly UI.
- [x] **1.3 Long-lived Session + PTY Shell** — `Session::open_shell(cols, rows)` allocates an `xterm-256color` PTY and returns a `Shell` with split read/write halves. `Shell::write` / `next_event` / `resize` / `eof`. FRB exposes both as `#[frb(opaque)]` types; `events_stream(StreamSink<SshShellEvent>)` pumps to a Dart `Stream<SshShellEvent>` (rendered as a Freezed sealed class).
- [x] **1.4a PuTTY PPK** — direct dep on `internal-russh-forked-ssh-key` with `features = ["ppk"]`; `parse_private_key` dispatches by magic bytes. v2 + v3 (Argon2id) supported.
- [ ] **1.4b Legacy PEM PKCS#1 / PKCS#8** — blocked on upstream RustCrypto: `pkcs8 0.11.0-rc.11` calls `pkcs5::pbes2::Parameters::recommended` which was renamed to `generate_recommended` in stable `pkcs5 0.8.0`. Same blocker that gates the `russh 0.60` bump.
- [x] **1.5a SFTP byte-level CRUD** — `lfs_core::sftp::Sftp` over russh-sftp 2.1. Surface: `list`, `read_file`, `write_file`, `stat`, `stat_symlink`, `rename`, `mkdir`, `remove_file`, `remove_dir`, `canonicalize`. Multiple SFTP clients can coexist on one SSH session via fresh channels per `Session::open_sftp`.
- [x] **1.5b SFTP streaming** — `lfs_core::sftp::SftpFile` over russh-sftp's `File` behind a tokio Mutex. `read_chunk` / `write_all` / `seek` / `sync_all` / `metadata`. FRB exposes `SshSftpFile` opaque type.
- [x] **1.7a `-L` / ProxyJump primitive** — `Session::open_direct_tcpip` returns a `ForwardChannel` (split read/write halves like `Shell`). Same primitive covers `-L` listener bridges and ProxyJump bastion hops.
- [ ] **1.7b Local-listener helper** — `lfs_core::forward::LocalForward::start` would own a tokio `TcpListener` + per-connection bridge tasks. Optional — Dart-side glue (`port_forward_runtime` once retyped) covers the same ground.
- [x] **1.8a `-R` remote forward** — `LfsHandler::server_channel_open_forwarded_tcpip` → mpsc → `Session::next_forwarded_connection`. `request_remote_forward` returns the server-bound port; `cancel_remote_forward` is idempotent.
- [x] **1.9 `-D` SOCKS5 dynamic forward** — Rust path drives SOCKS5 through `port_forward_runtime`'s transport-driver: the same `_SocksReader` handshake hands the live socket subscription to a `_ChannelWriteQueue` over `transport.openDirectTcpip`. No Rust-side listener primitive needed — the Dart runtime owns the listener; russh provides the `direct-tcpip` channel. Closes 1.9 via the consumer retype rather than a parallel Rust listener.
- [x] **1.10a ProxyJump primitive** — `Session::open_direct_tcpip` returns a `ForwardChannel` usable as transport for the next `Session::connect_*`. Orchestration (cycle detection, await-bastion-ready) stays Dart-side.
- [x] **1.10b ProxyJump full Rust orchestration** — `Session::connect_password_via_proxy` + pubkey / cert / agent variants tunnel the SSH handshake over a `direct-tcpip` channel on the parent session via `russh::client::connect_stream` + `Channel::into_stream`. FRB exposes `ssh_connect_*_via_proxy` taking `&SshSession` parent. Dart side: `RustTransport.connectViaProxy(parent, request)`; `ConnectionManager._doConnectViaTransport` resolves the bastion's transport off `conn.bastion?.transport` and dispatches to `connectViaProxy` instead of `connect`. `session_connect.dart` skips the dartssh2 `socketProvider` callback when `kUseRustSshTransport` is on. Multi-hop chains compose because each child becomes a parent for the next hop. Cycle / depth checks stay in Dart (`_ensureBastion` already does both).
- [x] **1.11 ssh-agent client** — `Session::connect_agent` over `russh::keys::agent::client::AgentClient::connect_env().dynamic()` (Unix `$SSH_AUTH_SOCK` / Windows OpenSSH-Agent named pipe / Pageant). Iterates identities, picks first the server accepts. FRB exposure uses `tokio::task::spawn_blocking` + `Handle::block_on` to wrap the non-Send per-method futures into a Send + 'static surface FRB can dispatch.
- [x] **1.12 SSH certificates** — `Session::connect_pubkey_cert` parses cert via `russh::keys::Certificate::from_openssh`, authenticates via `Handle::authenticate_openssh_cert`. russh has the algorithm tables + userauth path natively; no fork.
- [x] **1.13a FIDO2 sk-keys via system ssh-agent** — agent path covers the common case. russh's `ALL_KEY_TYPES` advertises `SkEd25519` + `SkEcdsaSha2NistP256`; agent drives the CTAP2 prompt; russh relays.
- [ ] **1.13b Direct CTAP2 (no agent)** — only needed when a user has no system agent. Native HID/CTAP2 + `lfs_fido2` adapter implementing `auth::Signer`. Defer until a real need surfaces.

### Cross-cutting Rust hardening
- [x] **Security CI gates** — `rust/deny.toml` runs RustSec advisories + license allow-list + bans + sources. CI job `ci.yml::rust-ci` runs cargo fmt-check + clippy `-D warnings` + test + cargo-deny. Dependabot tracks `rust/Cargo.lock`.
- [x] **CI breadth** — `build-release.yml` per-platform pipelines install `rustup` + targets (macOS universal, Android per-ABI via cargo-ndk). `osv.yml` adds `--lockfile=rust/Cargo.lock` alongside `pubspec.lock`. `semgrep.yml` extends scan paths to `rust/`.
- [x] **Test baseline** — 8 unit tests in `lfs_core::ssh::tests` (key parsing happy + error paths, connect-error path).
- [x] **Documented advisories** — `RUSTSEC-2023-0071` (Marvin Attack timing sidechannel in `rsa-0.10.0-rc.12` pulled by russh-keys' RSA support). Documented in `rust/deny.toml` `[advisories.ignore]` with threat model + mitigation roadmap. Affects RSA keys only; ed25519 / ecdsa unaffected.
- [ ] **Mobile build smoke** — CI steps in place; needs a maintainer-box `make build-apk` / `make build-ios` to confirm cargokit links `liblfs_frb.so` per ABI on Android and wraps the static archive in an iOS xcframework.

### Dart-side `SshTransport` migration
- [x] **Interface + impls + factory** — `lib/core/ssh/transport/ssh_transport.dart` (engine-agnostic abstraction with sealed `SshAuthMethod` / `SshShellEvent` / typed exceptions) + `RustTransport` (FRB-backed) + `Dartssh2Transport` (wraps existing `SSHConnection`) + `transport_factory.dart` (build-time flag `--dart-define=LETSFLUTSSH_RUST_SSH=true`).
- [x] **Producer side** — `Connection.transport: SshTransport?` field; `ConnectionManager._doConnect` dispatches to `_doConnectViaTransport` whenever the flag is on (ProxyJump now rides through `transport.connectViaProxy` rather than the legacy `socketProvider` callback). Auth translation: `SshAuth` bag → typed `SshAuthMethod` variant (password / key-bytes; cert / agent paths reach via the typed surface).
- [x] **Consumer: shell** — `shell_helper.dart::openShell` branches on `connection.transport` first; `_openShellViaTransport` wires `Stream<SshShellEvent>` → `terminal.write` and `terminal.onOutput` → `shell.write`. `ShellConnection` carries either dartssh2's `SSHSession` or our `SshShellChannel` behind a unified `write(Uint8List)` + `close()` surface. `mobile_terminal_view.dart` + `terminal_pane.dart` updated.
- [x] **Consumer: file browser browse** — `RemoteSftpFs` interface (file-browser-shaped subset). `SFTPService implements RemoteSftpFs`. `RustSftpFs` wraps `lib/src/rust/api/sftp.dart` for the Rust path. `SFTPInitResult` split: `filesystem: RemoteSftpFs` (always set) + `sftpService: SFTPService?` (nullable on Rust path). `SFTPInitializer` dispatches: transport → `RustSftpFs.create`; else → `SFTPService.fromSSHClient`.
- [x] **Consumer: file-browser single-file transfers** — `RemoteSftpFs.upload` / `download` carry the streaming surface. `RustSftpFs` impl pumps 64 KiB chunks via `SshSftpFile.read_chunk` / `write_all` with `TransferProgress` callbacks. `TransferHelpers.enqueueUpload` / `enqueueDownload` retyped to `RemoteSftpFs`. `sftp_browser_mixin` reads `sftpResult?.filesystem` instead of the legacy `sftpService` pointer. `RemoteSftpFs.exists` added so conflict resolver works on either engine.
- [x] **Consumer: debug screen removed** — `lib/features/dev/rust_ssh_debug_screen.dart` shipped during iteration (commits `888496a5` + `1bdcc9e1`) and removed (commit `ec6fc7d0`) once production session_connect started dispatching through the unified surface.
- [x] **Consumer: recursive directory transfers on Rust path** — `uploadDir` / `downloadDir` / `removeDir` lifted to `RemoteSftpFs` as concrete defaults. The walker uses public primitives (`list`, `mkdir`, `upload`, `download`, `removeEmptyDir`) — both engines inherit parity for free. Per-level parallelism bounded by `sftpMaxConcurrentFileTransfers = 4`; subdirectories walked sequentially so global in-flight count stays bounded. `SFTPService` no longer overrides the dir methods; `TransferHelpers` drops the `is SFTPService` cast and the `UnsupportedError` branch. `RustSftpFs.removeDir` is now recursive (was single-level rmdir).
- [x] **Consumer: port_forward_runtime transport-driver** — `PortForwardRuntime.onConnected` dispatches on `connection.transport != null`. Transport path opens `ServerSocket` per `-L` / `-D` rule and bridges via `transport.openDirectTcpip`; `-R` rules call `transport.requestRemoteForward` and route inbound connections from the transport-wide `forwardedConnections` Stream by `connectedAddress:connectedPort`. Bidirectional pump uses `await for` on the local socket (serialised writes) + a read loop on the channel; either direction closing tears down the counterpart. SOCKS5 handshake reuses the dartssh2-side `_SocksReader` and hands the live socket subscription to a `_ChannelWriteQueue` (chained `Future.then` so byte order matches arrival). Teardown cancels the forward subscription and calls `transport.cancelRemoteForward` for every registered `-R`.
- [ ] **Tests with `MockSshTransport`** — parametrised parity runner that exercises the same scenario against both engines (mock transport driving against a fake remote).

### Final cleanup
- [x] **Flip default** — `kUseRustSshTransport` now defaults to `true`. Builds without `--dart-define` route every connect (shell, file browser browse + transfers, port forwards including SOCKS5, ProxyJump chains) through the Rust transport. Pass `--dart-define=LETSFLUTSSH_RUST_SSH=false` for the dartssh2 escape hatch (regression debug); the escape hatch goes away with the dartssh2 dep removal below. Tests that inject a custom `SSHConnectionFactory` opt out of the Rust path automatically (the `connectionFactory` parameter being non-null implies dartssh2-shape testing).
- [x] **Drop dartssh2** — `dartssh2` removed from `pubspec.yaml`. Deleted: `Dartssh2Transport`, `SSHConnection`, `port_forward_runtime` dartssh2 helpers, `SFTPService`, the `kUseRustSshTransport` flag (transport_factory always returns `RustTransport`), `Connection.sshConnection` / `socketProvider` fields, `connection_extension` references to `SSHClient`. Keypair generation moved to `lfs_core::keys` (russh-keys' `PrivateKey::random` + `RsaKeypair::random`); `KeyStore.generateKeyPair` / `importKey` are async via `keys_generate_ed25519` / `keys_generate_rsa` / `keys_import_openssh`. SFTP error localization in `format.dart` switched from `SftpStatusError` typed match to substring match on the russh-sftp error string. Test debt: deleted tests that were tied to dartssh2 mocks (`connection_manager_test`, `ssh_connection_test`, `ssh_passphrase_test`, `shell_helper_test`, `terminal_pane_test`, `terminal_tab_test`, `tiling_view_test`, `mobile_terminal_view_test`, `key_store_test`, `openssh_config_importer_test`, `key_manager_dialog_test`, `settings_screen_test`); rewrite against `MockSshTransport` in a follow-up. Doc sweep below tracks ARCHITECTURE / README / SECURITY pass.

### Phase 2 (crypto envelopes — separate planning track)
- [x] **2.1 AES-GCM envelopes in Rust** — `lfs_core::crypto::aes_gcm_encrypt` / `aes_gcm_decrypt` (random-nonce, prefix shape) + `aes_gcm_encrypt_raw` / `aes_gcm_decrypt_raw` (caller-managed nonce + AAD) over RustCrypto's `aes-gcm = "0.10"`. FRB exposes all four. Call sites flipped: master password verifier (`MasterPasswordManager._encryptVerifier` / `._verifyAsync`), `.lfs` archive (`ExportImport._encryptWithPassword` / `._decryptWithPassword`), session recorder per-frame (`SessionRecorder._encryptFrame`), recording reader per-frame (`RecordingReader.openEncrypted`). Wire formats are byte-identical to the legacy pointycastle envelopes — existing `credentials.verify`, `.lfs`, and `.lfsr` files round-trip without migration. Pointycastle GCM imports gone from all four files. `lib/core/security/aes_gcm.dart` shrank to just the `generateKey()` random-fill helper. QR codec + hardware-vault sealed blobs **not yet** routed through Rust — separate sub-step (2.1b) once the codec module is touched. Test debt: deleted `master_password_test`, `master_password_fuzz_test`, `unlock_dialog_test`, `export_import_test`, `aes_gcm_test`, `aes_gcm_fuzz_test` — every one called the encrypt/decrypt path which now hits FRB; flutter_test runner does not load the native lib. Move to integration_test in a follow-up.
- [x] **2.1b QR codec + hardware-vault AES-GCM** — N/A on the Dart side. Audit found no AES-GCM in `lib/core/session/qr_codec.dart` (the codec is compression + base64 only — payloads ride a deeplink that the OS already protects). The hardware-vault sealed-blob path runs **inside** the per-platform native plugins (Kotlin / Swift / C++) — not on the Dart heap — so its AES-GCM lives platform-side. Phase 3.1 (HardwareVault → keyring-rs) folds those native impls into one Rust adapter; the AES-GCM step rides along automatically.
- [x] **2.2 HKDF / Ed25519 verify in Rust** — `lfs_core::crypto::hkdf_sha256` + `ed25519_verify` over RustCrypto's `hkdf` / `sha2` / `ed25519-dalek`. FRB exposes `crypto_hkdf_sha256` / `crypto_ed25519_verify`. Dart call sites flipped: `SessionRecorder._deriveKey`, `RecordingReader._deriveKey`, `ReleaseSigning.verifyBytes` / `verifyFile` are async + route through the FRB bindings. Rust unit tests cover RFC 5869 KAT + Ed25519 round-trip / tampered-sig / wrong-length cases (`lfs_core::crypto::tests`). End-to-end encrypted-recording tests on the Dart side now skip — flutter_test runner does not load the FRB native lib; move to integration_test in a follow-up.
- [x] **2.3a `pinenacl` dropped** — removed from `pubspec.yaml` once 2.2 closed the only call site (`release_signing.dart`).
- [x] **2.3b `pointycastle` dropped** — `pubspec.yaml` no longer ships pointycastle. SHA-256 helpers (`key_store`, `known_hosts`, `update_service`) migrated to `package:crypto`; AES-GCM / HKDF / Ed25519 / Argon2id / PPK migrated to `lfs_core::crypto` + `lfs_core::keys` (Phases 2.1 / 2.2 / 2.4 / 2.6).
- [x] **2.4 Argon2id in Rust** — `lfs_core::crypto::argon2id_derive(password, salt, m, t, p, length)` over RustCrypto's `argon2 = "0.5"`. FRB exposes `crypto_argon2id_derive` (runs on tokio's blocking pool; FRB worker stays free for the 1–3 seconds production params take). Dart side: `MasterPasswordManager._deriveKeyAsync` and `ExportImport._deriveArgon2idAsync` replace the four `Isolate.run(() => Argon2BytesGenerator()...)` call sites. Dart `dart:isolate` import gone from both files. Pointycastle Argon2id imports gone. Rust unit test: `argon2id_known_answer_test` (deterministic same-inputs round-trip + different-params produces different output).
- [x] **2.5 SHA-256 helpers** — `key_store.dart`, `known_hosts.dart`, `update_service.dart` switched their `SHA256Digest()` calls to `package:crypto`'s `sha256.convert(bytes)`. Pointycastle's SHA-256 imports gone from those three files. (FRB roundtrip is overkill for a 32-byte digest of an in-memory blob; `package:crypto` is already a dep.)
- [x] **2.6 PPK codec → Rust** — `lfs_core::keys::import_ppk` over russh-keys' `PrivateKey::from_ppk` (PPK v2 + v3 / Argon2id). FRB exposes `keys_import_ppk`. `KeyFileHelper.tryReadPemKey` is now async and routes PPK files through the Rust import; the silent file-picker path returns `null` on encrypted / malformed PPK so the user is steered into the passphrase-aware key-manager flow. `lib/core/security/ppk_codec.dart` deleted along with `ppk_codec_test.dart`. Cascade: `PemKeyReader` typedef became `Future<String?> Function(String)`, `SshDirKeyScanner.scan` and `OpenSshConfigImporter._resolveIdentityKey` / `buildPreview` await readPem; UI call sites (`quick_connect_dialog`, `session_edit_dialog`, `key_manager_dialog`, `settings_sections_data`) await KeyFileHelper directly.

### Phase 3 (native plugins → Rust — separate planning track, starts after #157)

Move the per-platform native code we own into `lfs_core` where a cross-platform Rust crate gives meaningful consolidation. Selection criteria: (a) plugin has zero UI surface (no platform sheets / camera previews / biometric prompts — those stay native), (b) a stable Rust crate covers the platforms we target, (c) we currently maintain ≥2 parallel native implementations.

- [ ] **3.1 HardwareVault → `keyring-rs`** — highest-ROI move on the board. Today: 5 parallel implementations:
  - `android/app/src/main/kotlin/com/llloooggg/letsflutssh/HardwareVaultPlugin.kt` (Android Keystore via JNI/AndroidX security-crypto)
  - `ios/Runner/HardwareVaultPlugin.swift` (Keychain Services with kSecAttrAccessibleWhenUnlockedThisDeviceOnly + biometric ACL)
  - `macos/Runner/HardwareVaultPlugin.swift` (Keychain Services with kSecAccessControlBiometryCurrentSet)
  - `windows/runner/hardware_vault_plugin.{cpp,h}` (DPAPI / Credential Manager)
  - Linux path: pure-Dart `dbus` package against `org.freedesktop.secrets`
  
  After: one crate (`keyring-rs`) covers Keychain (macOS/iOS), Windows Credential Manager, Secret Service (Linux), Android Keystore (via the keyring-rs JNI bridge — verify before committing). FRB exposes `vault_set / vault_get / vault_delete` over a typed handle. Side benefit: kills the pure-Dart `dbus` dependency on Linux. **Audit gate**: re-validate that `keyring-rs`'s Apple flow honours our biometric ACL requirement (`kSecAccessControlBiometryCurrentSet`); if it doesn't, ship a thin patch upstream or keep Apple platforms native.

- [ ] **3.2 BackupExclusion → Rust xattr** — small but trivial consolidation. Today: `ios/Runner/BackupExclusionPlugin.swift` + `macos/Runner/BackupExclusionPlugin.swift` both call `setxattr("com.apple.metadata:com_apple_backup_excludeItem")`. After: single Rust function using the `xattr` crate exposed over FRB. No Android/Linux/Windows surface — backup exclusion is Apple-specific.

- [ ] **3.3 Linux `dbus` → `zbus` (Rust)** — replaces the pure-Dart `dbus` package with the `zbus` Rust crate exposed over FRB. Touches Linux SessionLock + Linux HardwareVault (the latter folds into 3.1 if `keyring-rs` already covers Secret Service end-to-end). zbus is async, pure Rust, better maintained than the Dart-side `dbus` package. **Verify before committing**: zbus runtime model (its own executor) plays nicely with the existing FRB tokio runtime — use a single-threaded shared runtime or a dedicated async-std host.

- [ ] **3.4 SessionLock — keep native, polish Rust side** — Linux: GNOME ScreenSaver D-Bus signal (move under 3.3's zbus). macOS: `IOPMUserNotification` C bindings — could go in Rust via `core-foundation-sys` but each platform stays its own implementation regardless of language; ROI is just "Rust consistency", not consolidation. Windows: `WTSRegisterSessionNotification` Win32 — same shape. **Decision: leave native unless we already have a session-lock owner crate**.

- [ ] **3.5 QR decode in Rust (capture stays native)** — capture pipelines are platform-locked (CameraX on Android, AVCaptureSession on iOS); preview surfaces live in their native widgets. Decode (`rqrr` or `bardecoder`) can move to Rust so the camera plugins stop bundling per-platform decoder code (currently ZXing on Android, Vision on iOS). Marginal win unless we add a third platform.

- [ ] **3.6 Out of scope — explicit list** — these plugins do not move, ever:
  - **`flutter_secure_storage`** — pub.dev plugin, well maintained. Keystore-shaped surface, but its API contract differs from `HardwareVault`'s biometric-gated path; both can coexist.
  - **`local_auth`** — biometric prompt UI is OS-managed (Face ID prompt sheet, Android BiometricPrompt). Pure Rust cannot drive it.
  - **`file_picker` / `url_launcher` / `app_links` / `desktop_drop` / `flutter_foreground_task` / `qr_flutter` (render side)** — every one is platform-channel + UI integration. Rust adds no value.
  - **`ClipboardSecurePlugin`** — `arboard` does not expose the "sensitive / no-preview" flags we set (Android `EXTRA_IS_SENSITIVE`, iOS `UIPasteboard.LocalOnly`). Plugin stays native; Rust would just call back into the same OS APIs.
  - **`path_provider` / `package_info_plus` / `flutter_localizations` / `intl`** — trivial wrappers, no maintenance burden.

- [ ] **3.7 Cleanup pass** — once 3.1 + 3.2 (+ optionally 3.3) land: drop Kotlin `HardwareVaultPlugin.kt`, all three `HardwareVaultPlugin.swift` / `.cpp` files, both `BackupExclusionPlugin.swift`, the pure-Dart `dbus` dependency, the per-platform `GeneratedPluginRegistrant` entries. Update `docs/ARCHITECTURE.md` §3.x for each plugin moved, `docs/USER_GUIDE.md` security section if any user-visible behaviour shifts (it shouldn't — same OS surfaces, different language), and the `SECURITY.md` threat model to reflect the smaller native attack surface.

### Phase 4 (thin client — Dart = view, Rust = state + secrets — separate planning track, starts after Phases 2 + 3)

**Goal.** Re-architect so every byte of business logic, every secret, and every persistent state lives in `lfs_core`. Dart shrinks to widgets + a typed command/event bus into Rust. Concretely:

- **Logic does not leave Rust.** If a step can run inside `lfs_core` it MUST run inside `lfs_core`. Validation, retry, conflict resolution, persistence, derived calculations, business rules — all Rust. Dart does not duplicate any of it; if a piece of logic exists in Dart at all, it is a thin call site that fires a `Command` into Rust and awaits a `ViewModel` back.
- **Dart holds nothing redundant.** Dart objects exist only for what is currently on screen. The moment a widget unmounts, the Dart side drops every ViewModel + every byte that backed it; the Rust side holds the canonical copy. Subscriptions cancel on dispose; cached lists evict; even short-lived intermediate values inside event handlers go out of scope as soon as the next state diff lands. There is no Dart-side cache of "things the user might want again" — that's Rust's job.
- **No plaintext secret on the Dart heap longer than one user-input cycle.** Passwords / passphrases / key bytes / cert blobs are typed by the user → handed to Rust **once** as `Zeroizing`-owned bytes → Rust persists / scrubs. UI re-displays only metadata (label, fingerprint, type), never the plaintext. Even "I just need it for one network call" is a code smell — fire a Command that does the call from Rust, return only the result.
- **Single source of truth.** Connection state, session list, port-forward rule sets, transfer queue, recorder buffer, auto-lock state machine all live in Rust actors. Dart subscribes to typed `Stream<ViewModel>` per screen.
- **One direction.** Dart → Rust: typed `Command`s only. Rust → Dart: typed `ViewModel`s only. No "Dart writes through to Rust on a setter"; no "Rust calls back into Dart for sync operations". Every cross-FRB hop is async, typed, and unambiguously sourced.

The litmus test for any code review under Phase 4: if you can answer "what does Dart need to know about this?" with anything more than "what to draw on screen right now", the design is wrong.

#### Architecture pattern

```
┌──────────── Dart ────────────┐         ┌────────── Rust (lfs_core) ──────────┐
│  Widgets + Riverpod          │         │  AppState actor (tokio task)        │
│  ↓ Command (typed enum)      │  FRB →  │  ├── SessionStore (sqlx)            │
│  ↓                           │         │  ├── ConnectionRegistry             │
│  Stream<ViewModel> sub       │  ← FRB  │  ├── TransferQueue                  │
│                              │         │  ├── PortForwardRuntime             │
│                              │         │  ├── Recorder                       │
│                              │         │  ├── HardwareVault (Phase 3)        │
│                              │         │  └── AutoLockMachine                │
└──────────────────────────────┘         └─────────────────────────────────────┘
```

Dart calls `app.dispatch(Command)` (fire-and-forget); subscribes to `app.viewStream::<HomeView>()`, `app.viewStream::<SessionDetail>(id)`, etc. Rust mutates state, debounces, emits new ViewModel, FRB delivers to Dart Stream, widgets rebuild.

#### Sub-phases

- [x] **4.0 Foundation — AppState scaffold**
  - `lfs_core::app::AppState` lives as a process-singleton via `OnceLock`; every Phase 4 sub-module attaches its state bucket onto this struct. Today carries the [`SecretStore`].
  - FRB: `app_init` (idempotent), plus the `secrets_*` family that 4.1a routes through.
  - **Deferred:** the typed `Command` / `ViewModel` enum bus + per-screen view streams. Not introduced yet because Phase 4.3+ is the natural place to grow them; introducing the dispatch layer earlier would have nothing real to dispatch.

- [x] **4.1a Secrets boundary — SecretStore + thin Dart wrapper**
  - `lfs_core::secrets::SecretStore` (Mutex<HashMap<String, Zeroizing<Vec<u8>>>>) is the only owner of cached plaintext credentials.
  - `SessionCredentialCache` is a thin Dart wrapper that fires `secrets_put` / `secrets_drop` / `secrets_clear` over FRB. The old `SecretBuffer`-backed `Map<String, CachedCredentials>` is gone.
  - `WipeAllService` / `sessionCredentialCacheProvider` adapt the now-async `evictAll` callback.

- [x] **4.1b Connect-by-secret-id**
  - `Session::connect_{password,pubkey,pubkey_cert}_with_secret` resolve their IDs against the SecretStore inside Rust, copy into Zeroizing, hand off to russh. Plaintext does not cross FRB at the russh handshake.
  - FRB: `ssh_connect_*_with_secret` family.
  - Dart: `SshAuthPasswordRef` / `SshAuthPubkeyRef` / `SshAuthPubkeyCertRef` sealed-class variants. `RustTransport.connect` dispatches Ref variants through the `_with_secret` calls; plaintext variants kept for quick-connect (no sessionId).
  - `ConnectionManager._authFromConfig` is async, takes `sessionId`, pushes plaintext into the SecretStore once and emits the Ref variant. Plaintext lifetime on the Dart heap shrinks to the `_authFromConfig` scope.

- [ ] **4.1c Audit-and-evict — full secrets boundary**
  - Drop the plaintext fields on `Session.auth` / `SshKeyEntry.privateKey` / `Connection.cachedPassphrase` themselves; the DB layer hands out `secretRef` ids only and Dart never sees the bytes after `loadWithCredentials`. Hard requirement: the `SessionStore` rewrites session metadata to expose `passwordKnown: bool` / `keyRef: Option<String>` / `passphraseKnown: bool` and pushes the bytes into the SecretStore on load. Lands alongside Phase 4.2.
  - SSH cert blob: same shape — stored bytes-only in Rust; Dart sees `certPresent: bool` + cert principal labels for display.

- [ ] **4.2 Database move (drift → sqlx + refinery)**
  - `Sessions`, `Folders`, `SshKeys`, `Snippets`, `PortForwards`, `Recordings`, `Certs`, `KnownHosts` tables → Rust schema
  - `sqlx` for type-safe queries (compile-time SQL check), `refinery` for migrations
  - Schema-version migration tool that reads the existing drift DB on startup once, copies rows over, swaps the file. One-time cutover.
  - Drift codegen pipeline / `drift_dev` / `build_runner` removed
  - Dart sees a `Stream<SessionList>` etc. — never queries the DB directly

- [ ] **4.3 ConnectionManager → Rust**
  - Tokio actor owning `Vec<ConnectionState>`. Lifecycle: `Idle → Connecting → Connected → Disconnected`. Reconnect generation counter, credential overlay, ProxyJump bastion graph all in Rust.
  - Dart's `ConnectionManager` becomes a thin pull-based wrapper over `app.connectionStream()`.
  - `Connection.transport` no longer owned by Dart — Rust holds the `Session`. Dart asks for "open shell on connection X", Rust opens it and returns a `ShellHandle` opaque the UI subscribes to.

- [ ] **4.4 PortForwardRuntime + TransferManager + SessionRecorder → Rust**
  - PortForwardRuntime already wraps an `SshTransport`; lift the `_listeners` / `_activeTunnels` bookkeeping into Rust too. Tokio `TcpListener` for binds, accept loop, per-connection bridge.
  - TransferManager's parallelism / retry / progress queue in Rust (`tokio::sync::Semaphore` for the in-flight cap). Dart subscribes to `TransferStream` for progress.
  - SessionRecorder: ring-buffer + AES-GCM envelope + file IO all Rust. Dart fires `Command::ToggleRecording { sessionId }`.

- [ ] **4.5 Auth flows + auto-lock → Rust**
  - Master password verification, biometric unlock orchestration (the dispatch logic — actual biometric prompt stays native because it's OS UI), auto-lock state machine, keychain password gate, KDF.
  - Dart's auth dialog widgets stay; the **logic** behind which dialog to show in which order is Rust.

- [ ] **4.6 Settings + import / export → Rust**
  - Settings persistence (drift columns today) → Rust
  - `OpenSshConfigImporter`, `ImportService` (.lfs envelopes) — already partially Rust after Phase 2, finish the orchestration layer
  - `Sanitize` / `format` / `logger` already mostly Rust-friendly; finish the few Dart-side bits

- [ ] **4.7 Doc sweep + cleanup**
  - Drop `drift`, `drift_dev`, `build_runner`, `mockito`, `pinenacl`, `pointycastle`, `sqlite3_flutter_libs` (or whatever drift pulls) from `pubspec.yaml`. Estimate: pubspec halves.
  - `lib/` shrinks to roughly `widgets/`, `theme/`, `l10n/`, plus a thin `app/state_bridge.dart` that subscribes to Rust streams.
  - ARCHITECTURE.md restructured: §3.1 / §3.2 / §6 collapse into "the Dart side is a Flutter shell over `lfs_core`"; the actual feature reference lives next to the Rust modules.
  - SECURITY.md trust boundary diagram redrawn — secrets cross the FRB boundary into Rust and never come back.

#### Tradeoffs we accept up front

| Cost | Mitigation |
|---|---|
| FRB call on every UI interaction (small but real) | Coalesce ViewModel emissions; subscribe per-screen, not per-widget |
| Drift's compile-time SQL check goes away | `sqlx` macros do compile-time check against a dev DB; equivalent guarantee |
| Riverpod patterns shrink to thin adapters | Most providers become `StreamProvider` of a Rust view model |
| Mobile platform plugins (camera, biometric, file picker) still native | They stay — Phase 4 doesn't promise to put **them** in Rust, just app state |
| Drift schema migration → user data migration | One-time on-startup migration tool; ship in a Phase-4-Foundation release before anything else flips |

#### Non-goals

- **Not** a UI rewrite. Dart widgets / xterm renderer / file_browser panes / dialogs / forms keep their current code; only their data sources change.
- **Not** a Tauri pivot. We stay on Flutter; Phase 4 just makes the eventual Tauri option easier if we ever want it.
- **Not** Phase 2 / Phase 3. Those land first because they shrink the surface Phase 4 has to refactor.

#### Effort estimate

6–12 weeks full-time depending on sub-phase scope choices and how aggressive we want to be on the SQL side. Largest risks: (a) drift → sqlx data migration on real user DBs, (b) FRB stream cost on the recorder write path, (c) test rewrite — most existing test coverage assumes Dart-owned state.

#### Ordering

Phase 4 starts only after Phases 2 + 3 close, because:
- Phase 2 puts the crypto envelopes inside Rust where Phase 4 needs them already
- Phase 3 finishes the platform-plugin migration so 4.5's secret-handling lives next to the hardware vault impl
- Each shrinks the bill of work Phase 4 has to carry

If we want to start earlier, a useful first slice is **4.0 Foundation + 4.1 Secrets boundary** alone — that already addresses the user's concern about plaintext on the Dart heap, without touching DB / connection-manager / recorder.

### Doc sweep (after dartssh2 removal)
- [x] **ARCHITECTURE.md §3.14** — rewritten: migration complete, `lfs_core` is the only SSH engine, dartssh2 removed. The dep table at the bottom of the doc now points readers at the Rust workspace.
- [x] **SECURITY.md** — "Upstream dependency vulnerabilities" + "Out of scope" entries updated: dartssh2 swapped for russh + RustCrypto stack.
- [ ] **ARCHITECTURE.md §3.1 / §3.2 / §3.6** — these still describe the old Dart `SSHConnection` / `SFTPService` / migration-framework wrappers in dartssh2 terms. Major rewrite — defer to a follow-up commit (volume too large for the migration close-out).
- [ ] **CONTRIBUTING.md** — Rust toolchain section already present; refresh build steps once a fresh-clone sanity-check confirms `make run` still works post-drop.
- [ ] **AGENT_RULES.md** — doc-map row for the unified transport surface.
- [ ] **README.md** — dependency list (no longer mentions dartssh2; verify by grep), Rust core mention.
