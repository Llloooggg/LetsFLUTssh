//! JavaVM capture for the Android JNI subsystem.
//!
//! Cargokit produces `liblfs_frb.so` for every Android ABI and
//! Flutter loads it via `dart:ffi`. That load path bypasses the
//! JVM, so the standard `JNI_OnLoad` callback is never invoked
//! (it fires only when the library is loaded via
//! `System.loadLibrary` from Java/Kotlin). To get a `JavaVM`
//! handle we expose an `extern "system"` entry point that a
//! tiny Kotlin object in `MainActivity` calls once at
//! application startup; thereafter every JNI call attaches the
//! current thread to the captured VM via
//! `JavaVM::attach_current_thread`.
//!
//! The Kotlin side is intentionally minimal — `LfsJniBootstrap`
//! is a single Kotlin object whose `register()` method routes
//! into [`Java_com_llloooggg_letsflutssh_LfsJniBootstrap_register`].
//! We do not maintain a Kotlin business-logic shim; the Java
//! method calls below all go through `java.security.KeyStore`
//! / `androidx.biometric.BiometricPrompt` / etc. directly via
//! the `jni` crate.
//!
//! **Verification status**: this bootstrap module compiles
//! against `aarch64-linux-android` via the rust-cross-check
//! matrix. The `register()` method's actual call from
//! `MainActivity.onCreate` + the resulting JavaVM capture is
//! the runtime-validation half — covered by the NI-2 gate, see
//! the `super::keystore` module's status block for details.

use jni::sys::{jint, JNI_VERSION_1_6};
use jni::JavaVM;
use std::sync::OnceLock;

/// Captured at first `register()` call by the Kotlin shim;
/// `OnceLock` because the JavaVM handle is process-wide and
/// stable for the lifetime of the JVM. Subsequent calls (if
/// the Kotlin side were to call `register` again, e.g. across
/// MainActivity recreation) are no-ops — the first wins.
static JAVA_VM: OnceLock<JavaVM> = OnceLock::new();

/// Retrieve the JavaVM captured at startup. Returns `None` if
/// the Kotlin bootstrap has not run yet (which would be a bug:
/// any call into `super::keystore` etc. requires this to have
/// been initialised).
pub fn java_vm() -> Option<&'static JavaVM> {
    JAVA_VM.get()
}

/// Bridge entry point invoked by the Kotlin object
/// `com.llloooggg.letsflutssh.LfsJniBootstrap.register()` once
/// at `MainActivity.onCreate`.
///
/// The `JNIEnv` argument hands us the active JNI environment
/// for the calling thread; we lift it into a process-wide
/// `JavaVM` reference via `JNIEnv::get_java_vm` and stash it
/// in [`JAVA_VM`]. From this point onward every JNI call
/// inside `super::keystore` etc. attaches the current thread
/// to the captured VM and operates against it.
///
/// # Safety
///
/// Called by the JVM via the Kotlin `external fun register()`
/// declaration, so `env` is a valid JNI environment and
/// `_class` is a valid jclass for `LfsJniBootstrap`.
#[no_mangle]
pub unsafe extern "system" fn Java_com_llloooggg_letsflutssh_LfsJniBootstrap_register<'local>(
    env: jni::JNIEnv<'local>,
    _class: jni::objects::JClass<'local>,
) {
    if let Ok(vm) = env.get_java_vm() {
        // Set returns Err if already initialised — that is the
        // expected state on a re-register, so the Err branch
        // is silently dropped.
        let _ = JAVA_VM.set(vm);
    }
}

/// JNI version negotiation entry point. Cargokit's Flutter
/// integration loads `liblfs_frb.so` via `dlopen` rather than
/// `System.loadLibrary`, so the JVM never invokes `JNI_OnLoad`
/// in practice. The entry point exists for symmetry: if a
/// future build path does load us through the JVM, it should
/// still get a valid version response so the load succeeds.
///
/// # Safety
///
/// Standard JNI contract: invoked by the JVM during
/// `System.loadLibrary`. `_vm` is the JavaVM that loaded us;
/// `_reserved` is unused per the JNI spec.
#[no_mangle]
pub unsafe extern "system" fn JNI_OnLoad(
    vm: *mut jni::sys::JavaVM,
    _reserved: *mut std::ffi::c_void,
) -> jint {
    // Capture the VM here too — when the library IS loaded via
    // System.loadLibrary, the explicit register() call from
    // MainActivity is redundant but the OnceLock guard makes
    // either order safe.
    if let Ok(vm) = JavaVM::from_raw(vm) {
        let _ = JAVA_VM.set(vm);
    }
    JNI_VERSION_1_6
}
