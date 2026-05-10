//! Android-only Rust paths — direct JNI to platform Java APIs
//! (`java.security.KeyStore` provider `"AndroidKeyStore"`,
//! `androidx.biometric.BiometricPrompt`,
//! `KeyGenParameterSpec.Builder.setIsStrongBoxBacked`). The `jni`
//! crate keeps the "Rust owns OS-API" invariant on every platform
//! without a hand-maintained Kotlin shim.
//!
//! Runtime verification on a real Android device is pending; CI's
//! `aarch64-linux-android` cross-compile gates the build but not
//! behaviour. These JNI paths are the sole secure-storage +
//! biometric runtime on Android. AndroidKeyStore alias prefix +
//! libsecret schema attributes are pinned by external compat
//! constraint — see `keystore.rs::KEY_ALIAS_PREFIX`.

pub mod biometric;
pub mod hardware_vault;
pub mod jni_bootstrap;
pub mod jni_helpers;
pub mod keystore;
