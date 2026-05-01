package com.llloooggg.letsflutssh

import androidx.fragment.app.FragmentActivity

/**
 * Tiny Kotlin shim that hands a JavaVM handle + the host
 * FragmentActivity to the Rust `lfs_os_security` crate's
 * Android JNI subsystem.
 *
 * Cargokit-built `liblfs_frb.so` is loaded by Flutter via
 * `dart:ffi` (not `System.loadLibrary`), so the standard
 * `JNI_OnLoad` callback never fires. Calling
 * `register(activity)` once at MainActivity.onCreate routes
 * into the Rust extern function
 * `Java_com_llloooggg_letsflutssh_LfsJniBootstrap_register`,
 * which:
 *
 * * lifts `JNIEnv` → `JavaVM` and stashes it in a
 *   `OnceLock<JavaVM>`,
 * * holds a `GlobalRef` to the activity (needed by
 *   `BiometricPrompt`, which requires a FragmentActivity host),
 * * derives + holds `getApplicationContext()` for filesystem
 *   + main-looper access on subsequent JNI calls.
 *
 * No business logic lives here — every Java API call below
 * this layer (`java.security.KeyStore`,
 * `androidx.biometric.BiometricPrompt`, etc.) goes through
 * the `jni` crate from Rust. The activity argument is the
 * single piece of state the Kotlin side hands over because
 * it cannot be discovered from Rust without a Java-side
 * starting point.
 *
 * The `init` block calls `System.loadLibrary("lfs_frb")` to
 * register the native library with the JVM linker (cargokit's
 * `dart:ffi` load path doesn't). Idempotent — `loadLibrary`
 * is a no-op on second call, and the Rust-side OnceLock
 * guards against double-register.
 */
object LfsJniBootstrap {
    init {
        System.loadLibrary("lfs_frb")
    }

    external fun register(activity: FragmentActivity)
}
