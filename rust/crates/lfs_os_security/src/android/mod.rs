//! Android-only Rust paths — direct JNI to platform Java APIs
//! (`java.security.KeyStore` provider `"AndroidKeyStore"`,
//! `androidx.biometric.BiometricPrompt`,
//! `KeyGenParameterSpec.Builder.setIsStrongBoxBacked`). The `jni`
//! crate keeps the "Rust owns OS-API" invariant on every platform
//! without a hand-maintained Kotlin shim.
//!
//! Runtime verification on a real Android device is pending; Dart
//! `flutter_secure_storage` / `local_auth` paths remain wired in
//! parallel until then.

pub mod biometric;
pub mod hardware_vault;
pub mod jni_bootstrap;
pub mod jni_helpers;
pub mod keystore;
