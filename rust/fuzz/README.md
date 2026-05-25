# Rust fuzz targets

Coverage-guided libFuzzer harnesses for the untrusted-bytes parsers
in `lfs_core` / `lfs_os_security`:

| Target | Driver                                              | Parser exercised                                     |
|--------|-----------------------------------------------------|------------------------------------------------------|
| `deeplink` | `lfs_core::deeplink::parse_connect_uri`           | `letsflutssh://connect?...` URI grammar              |
| `known_hosts` | `lfs_core::known_hosts_parser::parse_line`     | OpenSSH `known_hosts` line + LFS internal export     |
| `qr_codec` | `lfs_core::qr_codec_decode::decode_payload`       | base64url + deflate + JSON-shape QR / paste payload  |
| `openssh_config` | `lfs_core::ssh_config::parse_openssh_config` | OpenSSH `~/.ssh/config` grammar                      |
| `ssh_target` | `lfs_core::ssh_target` parser                     | `[user@]host[:port]` SSH target string               |
| `pem_certs` | `lfs_core::webdav::client::parse_pem_certs`      | trusted-cert PEM bundle (session-edit paste)         |
| `pkcs11_uri` | `lfs_os_security::pkcs11::uri::Pkcs11Uri::parse` | RFC 7512 `pkcs11:` URI                               |
| `ppk_import` | `lfs_core::keys::import_ppk`                     | PuTTY `.ppk` v2/v3 private key (hex MAC, Argon2 params) |
| `openssh_key_import` | `lfs_core::keys::import_openssh`          | OpenSSH / PKCS#1 / PKCS#8 PEM private key            |
| `sk_key_import` | `lfs_core::keys::parse_sk_private_key`        | FIDO2 `sk-*` private key (credential id + flags)     |

Each target is a pure `fuzz_target!(|data: &[u8]|)` harness that
drives bytes from the fuzzer through the parser and asserts no
panic + (where applicable) parser-output invariants. The three
private-key importers take a fixed passphrase so the encrypted-key
decrypt branch is reachable.

## Running

`cargo fuzz` needs nightly Rust + libfuzzer-sys. Install once:

```sh
cargo install cargo-fuzz
rustup install nightly
```

Then from this directory:

```sh
cd rust/fuzz
cargo +nightly fuzz run deeplink
cargo +nightly fuzz run known_hosts
cargo +nightly fuzz run qr_codec
cargo +nightly fuzz run openssh_config
cargo +nightly fuzz run ppk_import
cargo +nightly fuzz run openssh_key_import
cargo +nightly fuzz run sk_key_import
```

`cargo +nightly fuzz list` prints the full target set.

Each target persists discovered crashes under `artifacts/<target>/`
and the live corpus under `corpus/<target>/`. Both directories are
gitignored — corpora belong in OSS-Fuzz / ClusterFuzzLite, not the
repo.

## Why a separate workspace

`cargo-fuzz` historically struggled with workspace nesting, so
`rust/fuzz/Cargo.toml` re-roots its own empty `[workspace]` so
`cargo build` from the parent `rust/` workspace never picks the
fuzz crate up. This keeps `make rust-build` and `make rust-lint`
fast and stops the libfuzzer-sys nightly-only deps from
leaking into the host build graph.

## Not run in CI today

These targets are meant for offline maintainer runs + a future
ClusterFuzzLite integration. The host build pipeline (`make
rust-test`, `cargo clippy`) ignores them entirely. Each crash
artifact reproduces deterministically; commit a regression test
against `lfs_core` for the fixed behaviour and the fuzz pass
moves on.
