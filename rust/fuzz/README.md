# Rust fuzz targets

Coverage-guided libFuzzer harnesses for the four untrusted-bytes
parsers the audit (P12) called out:

| Target | Driver                                              | Parser exercised                                     |
|--------|-----------------------------------------------------|------------------------------------------------------|
| `deeplink` | `lfs_core::deeplink::parse_connect_uri`           | `letsflutssh://connect?...` URI grammar              |
| `known_hosts` | `lfs_core::known_hosts_parser::parse_line`     | OpenSSH `known_hosts` line + LFS internal export     |
| `qr_codec` | `lfs_core::qr_codec_decode::decode_payload`       | base64url + deflate + JSON-shape QR / paste payload  |
| `openssh_config` | `lfs_core::ssh_config::parse_openssh_config` | OpenSSH `~/.ssh/config` grammar                      |

Each target is a pure `fuzz_target!(|data: &[u8]|)` harness that
drives bytes from the fuzzer through the parser and asserts no
panic + (where applicable) parser-output invariants.

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
```

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
