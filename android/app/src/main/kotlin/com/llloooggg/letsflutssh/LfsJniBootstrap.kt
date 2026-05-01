package com.llloooggg.letsflutssh

/**
 * Tiny Kotlin shim that hands a JavaVM handle to the Rust
 * `lfs_os_security` crate's Android JNI subsystem.
 *
 * Cargokit-built `liblfs_frb.so` is loaded by Flutter via
 * `dart:ffi` (not `System.loadLibrary`), so the standard
 * `JNI_OnLoad` callback never fires. Calling `register()`
 * once at MainActivity.onCreate routes into the Rust extern
 * function `Java_com_llloooggg_letsflutssh_LfsJniBootstrap_register`,
 * which lifts `JNIEnv` → `JavaVM` and stashes it in the Rust
 * `OnceLock<JavaVM>` that every subsequent JNI call (keystore,
 * BiometricPrompt, StrongBox, …) attaches against.
 *
 * No business logic lives here — the Rust side owns every
 * call into `java.security.KeyStore` /
 * `androidx.biometric.BiometricPrompt` / etc. directly via
 * the `jni` crate. This object exists solely as the
 * VM-handoff bridge.
 *
 * The `init` block calls `System.loadLibrary("lfs_frb")` to
 * make the native library reachable from the JVM linker
 * (cargokit's `dart:ffi` load doesn't register the library
 * with the JVM's linker chain). Idempotent — `loadLibrary`
 * is a no-op on second call.
 */
object LfsJniBootstrap {
    init {
        System.loadLibrary("lfs_frb")
    }

    external fun register()
}
