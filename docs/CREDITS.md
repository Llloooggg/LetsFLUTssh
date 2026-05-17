# Credits

LetsFLUTssh is GPL-3.0. The bundled assets below are redistributed
under their own permissive licenses. Replacing or upgrading any of
them must preserve the corresponding license text.

## Fonts

| Asset | Source | License |
|-------|--------|---------|
| `assets/fonts/Inter.ttf` | [Inter](https://github.com/rsms/inter) by Rasmus Andersson | [SIL Open Font License 1.1](https://openfontlicense.org/) |
| `assets/fonts/JetBrainsMono.ttf` | [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) by JetBrains | [SIL Open Font License 1.1](https://openfontlicense.org/) |

The OFL allows bundling the font with the app (modified or not), as
long as the font is not sold on its own and the OFL text accompanies
the binary. Drop `OFL.txt` from each font's source repository into
`assets/fonts/LICENSES/` if/when packaging for stores that audit
shipped license files (Flathub, F-Droid).

## Icons

| Asset | Author | License |
|-------|--------|---------|
| `assets/icons/icon.png` | Llloooggg (project author) | GPL-3.0 (covered by repo LICENSE) |

## Screenshots

| Asset | Author | License |
|-------|--------|---------|
| `docs/screenshots/LetsFLUTssh_terminal.png` | Llloooggg | GPL-3.0 |
| `docs/screenshots/LetsFLUTssh_files.png` | Llloooggg | GPL-3.0 |

## Source Dependencies

### Dart / Flutter

See `pubspec.yaml` and `pubspec.lock` for the complete list of
transitive Dart / Flutter packages. Each is distributed under its
upstream license; the OSV-Scanner workflow tracks vulnerabilities
across the whole tree on every push.

### Rust crates (bundled into the native blob)

The Rust workspace under `rust/` ships into every release as a
statically linked native blob. The full transitive list with
exact versions lives in `rust/Cargo.lock`; high-level
GPL-3.0-compatible licenses are summarised below for audit.

| Crate (root) | Purpose | License |
|---|---|---|
| `russh` + `russh-sftp` + `russh-keys` | SSH / SFTP / key parsing engine | Apache-2.0 |
| `rusqlite` (with `bundled-sqlcipher-vendored-openssl`) | SQLite wrapper + bundled SQLCipher 4.x + OpenSSL (`openssl-src`) | rusqlite MIT; SQLCipher BSD-3-Clause-Modification; OpenSSL Apache-2.0 (3.0+) / dual SSLeay+OpenSSL (1.x history) |
| `aes-gcm` / `argon2` / `hkdf` / `ed25519-dalek` / `sha2` (RustCrypto) | Cryptographic primitives | Apache-2.0 OR MIT |
| `ring` (russh's selected crypto backend) | Crypto suite for the SSH transport | mixed BSD-style + ISC + MIT (see `LICENSE` in the crate) |
| `tokio` + `tokio-util` | Async runtime | MIT |
| `serde` / `serde_json` / `serde_with` | Serialization | Apache-2.0 OR MIT |
| `zbus` (Linux) | D-Bus binding (logind session-lock + secret-service probe) | MIT |
| `secret-service` (Linux) | libsecret/D-Bus keyring access | MIT OR Apache-2.0 |
| `windows` (`microsoft/windows-rs`) | Windows API bindings (Credential Manager, NCrypt, WTSAPI) | Apache-2.0 OR MIT |
| `security-framework` + `objc2` family (Apple) | Keychain Services, Secure Enclave, AVFoundation bridges | MIT OR Apache-2.0 / MIT |
| `jni` (Android) | JNI bindings to AndroidKeyStore + BiometricPrompt | MIT OR Apache-2.0 |
| `tss-esapi` (Linux T2 native backend, opt-in) | TPM2 access via libtss2 | Apache-2.0 |

GPL-3.0 (this project's license) is one-way compatible with all of
the above — no upstream license forbids redistribution inside a
GPL-3.0 binary. Any future dep that is *not* one of these family
licences must be vetted against §7 of the GPL-3.0 text before it
lands in `rust/Cargo.toml`.
