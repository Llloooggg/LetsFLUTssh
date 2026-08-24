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

use jni::objects::JObject;
use jni::refs::Global;
use jni::sys::{jint, JNI_VERSION_1_6};
use jni::JavaVM;
use std::sync::OnceLock;

/// Captured at first `register()` call by the Kotlin shim;
/// `OnceLock` because the JavaVM handle is process-wide and
/// stable for the lifetime of the JVM. Subsequent calls (if
/// the Kotlin side were to call `register` again, e.g. across
/// MainActivity recreation) are no-ops — the first wins.
static JAVA_VM: OnceLock<JavaVM> = OnceLock::new();

/// `android.content.Context` (specifically the Application
/// context — process-scoped, survives Activity recreation)
/// stashed at bootstrap so JNI calls inside `super::keystore`
/// etc. can resolve `getFilesDir()`, `getMainLooper()`, etc.
/// without re-walking ActivityThread reflection on every call.
/// Held as a `Global` reference to keep the JVM from GC'ing it
/// across the thread-attach boundary.
static APP_CONTEXT: OnceLock<Global<JObject<'static>>> = OnceLock::new();

/// `androidx.fragment.app.FragmentActivity` reference — the
/// host MainActivity, captured at bootstrap so the
/// `BiometricPrompt` JNI path (`super::biometric_auth`) can
/// hand it to `BiometricPrompt.Builder(activity)` without a
/// per-call lookup. Distinct from `APP_CONTEXT`: an Application
/// context is NOT a valid argument for BiometricPrompt because
/// the prompt is Fragment-hosted.
static MAIN_ACTIVITY: OnceLock<Global<JObject<'static>>> = OnceLock::new();

/// The application `ClassLoader`, captured from the MainActivity
/// while `register()` runs on a thread with live Java frames.
/// JNI `FindClass` issued from a worker thread attached without
/// any Java frame resolves through the system classloader, which
/// cannot see app (`com.llloooggg…`) or bundled-library
/// (`androidx.*`) classes — [`super::jni_helpers::load_class`]
/// routes lookups through this handle instead.
static APP_CLASS_LOADER: OnceLock<Global<JObject<'static>>> = OnceLock::new();

/// Retrieve the JavaVM captured at startup. Returns `None` if
/// the Kotlin bootstrap has not run yet (which would be a bug:
/// any call into `super::keystore` etc. requires this to have
/// been initialised).
pub fn java_vm() -> Option<&'static JavaVM> {
    JAVA_VM.get()
}

/// Retrieve the Application context captured at startup.
pub fn app_context() -> Option<&'static Global<JObject<'static>>> {
    APP_CONTEXT.get()
}

/// Retrieve the MainActivity (FragmentActivity) reference
/// captured at startup. Required by the BiometricPrompt path.
pub fn main_activity() -> Option<&'static Global<JObject<'static>>> {
    MAIN_ACTIVITY.get()
}

/// Retrieve the application ClassLoader captured at startup.
/// Required for class resolution from worker threads — see
/// [`super::jni_helpers::load_class`].
pub fn app_class_loader() -> Option<&'static Global<JObject<'static>>> {
    APP_CLASS_LOADER.get()
}

/// Bridge entry point invoked by the Kotlin object
/// `com.llloooggg.letsflutssh.LfsJniBootstrap.register(activity)`
/// once at `MainActivity.onCreate`.
///
/// Captures four process-wide handles:
///
/// * `JavaVM` — lifted from the calling thread's `Env` via
///   `get_java_vm`. Subsequent JNI calls in any thread attach
///   to this VM via `attach_current_thread`.
/// * `MainActivity` (`FragmentActivity`) — the activity argument
///   the Kotlin side passes; `BiometricPrompt` requires a
///   FragmentActivity host, not an Application context.
/// * `Application context` — derived from the activity via
///   `getApplicationContext()`. Process-scoped (survives
///   Activity recreation), used for `getFilesDir()` /
///   `getMainLooper()` resolution.
/// * `Application ClassLoader` — derived from the activity via
///   `getClassLoader()`. Used by [`super::jni_helpers::load_class`]
///   to resolve app and `androidx.*` classes from worker threads
///   where JNI `FindClass` cannot.
///
/// All four are held as `Global` references so the JVM does not
/// reclaim them across the thread-attach boundary in worker
/// threads.
///
/// # Safety
///
/// Called by the JVM via the Kotlin `external fun register()`
/// declaration, so `env` is a valid JNI environment, `_class`
/// is a valid jclass for `LfsJniBootstrap`, and `activity` is
/// a valid jobject reference to a FragmentActivity.
#[no_mangle]
pub unsafe extern "system" fn Java_com_llloooggg_letsflutssh_LfsJniBootstrap_register<'local>(
    mut env: jni::EnvUnowned<'local>,
    _class: jni::objects::JClass<'local>,
    activity: jni::objects::JObject<'local>,
) {
    env.with_env(|env| -> Result<(), jni::errors::Error> {
        if let Ok(vm) = env.get_java_vm() {
            // Set returns Err if already initialised — that is the
            // expected state on a re-register, so the Err branch
            // is silently dropped.
            let _ = JAVA_VM.set(vm);
        }
        if let Ok(global_activity) = env.new_global_ref(&activity) {
            let _ = MAIN_ACTIVITY.set(global_activity);
        }
        // Derive Application context from the activity.
        if let Ok(app_ctx) = env
            .call_method(
                &activity,
                jni::strings::JNIString::new("getApplicationContext"),
                jni::signature::RuntimeMethodSignature::from_str("()Landroid/content/Context;")?
                    .method_signature(),
                &[],
            )
            .and_then(|v| v.l())
        {
            if let Ok(global_ctx) = env.new_global_ref(&app_ctx) {
                let _ = APP_CONTEXT.set(global_ctx);
            }
        }
        // Capture the app ClassLoader — `register()` runs inside
        // MainActivity.onCreate, so this thread has Java frames and
        // `getClassLoader` returns the app (PathClassLoader) loader,
        // not the system one.
        if let Ok(loader) = env
            .call_method(
                &activity,
                jni::strings::JNIString::new("getClassLoader"),
                jni::signature::RuntimeMethodSignature::from_str("()Ljava/lang/ClassLoader;")?
                    .method_signature(),
                &[],
            )
            .and_then(|v| v.l())
        {
            if let Ok(global_loader) = env.new_global_ref(&loader) {
                let _ = APP_CLASS_LOADER.set(global_loader);
            }
        }
        Ok(())
    })
    .resolve::<jni::errors::LogErrorAndDefault>();
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
    let captured = JavaVM::from_raw(vm);
    let _ = JAVA_VM.set(captured);
    JNI_VERSION_1_6
}
