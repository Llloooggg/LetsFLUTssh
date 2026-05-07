//! macOS-only OS-API surface.
//!
//! Currently hosts the self-sign / re-sign code-signing pipeline
//! that turns a freshly-installed `.app` into one with a stable
//! signing identity in the user's keychain. The pipeline runs once
//! per install (Tier 1 setup) plus once per auto-update (the
//! installer re-signs the staged bundle so the new binary keeps
//! access to the keychain items the previous bundle minted).
//!
//! All work routes through Apple subprocess CLIs (`/usr/bin/openssl`
//! for cert + PKCS#12, `/usr/bin/security` for keychain, and
//! `/usr/bin/codesign` for the signature pass) — same tools the
//! prior Dart implementation in `lib/platform/macos/code_signing/`
//! drove. Moving the orchestration here keeps the Dart layer to a
//! single FRB call and follows the project's "Flutter renders,
//! Rust thinks" invariant.

pub mod code_signing;
pub mod installer;
