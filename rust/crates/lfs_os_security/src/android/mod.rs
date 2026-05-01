//! Android-only Rust paths — direct JNI to platform Java APIs
//! (`java.security.KeyStore` provider `"AndroidKeyStore"`,
//! `androidx.biometric.BiometricPrompt`,
//! `KeyGenParameterSpec.Builder.setIsStrongBoxBacked`).
//!
//! See [Tier 3 Android JNI bridge ledger](
//! ../../../../../docs/RUST_CORE_MIGRATION_PLAN.md#tier-3--android-jni-bridge-ledger-planned-approach)
//! for the planned-approach rationale. Short version: the JVM is
//! a calling-convention concern (identical to `extern "system"`
//! on Windows or `objc2` on Apple), not an architectural one;
//! the `jni` crate gives us direct access to platform Java
//! classes without a hand-maintained Kotlin shim — same
//! "Rust owns the OS-API call" invariant the other four
//! platforms already maintain.
//!
//! **Verification status**: every JNI call below is a string-
//! identified Java method ID lookup at runtime. Mismatches
//! between the Rust-side type signatures and the actual Android
//! API contract surface only when the call executes on a real
//! device or emulator (`cargo check --target aarch64-linux-android`
//! validates that the Rust source compiles, not that the JNI
//! signatures resolve). This module's runtime correctness is
//! the [NI-2 verification gate](
//! ../../../../../docs/RUST_CORE_MIGRATION_PLAN.md#ni-2--apple--windows-rust-ports-verification-pending);
//! the Dart `flutter_secure_storage` / `local_auth` plugin paths
//! remain wired in parallel until that gate flips.

pub mod jni_bootstrap;
pub mod keystore;
