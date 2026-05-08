//! Common JNI helpers shared across the Android `lfs_os_security`
//! sub-modules. Each helper boxes a single recurring pattern so
//! the keystore / biometric / StrongBox call sites stay focused
//! on the platform-specific call sequence rather than re-deriving
//! `attach_current_thread` boilerplate.

use jni::objects::{GlobalRef, JByteArray, JObject, JString, JValue};
use jni::{AttachGuard, JNIEnv};
use std::path::PathBuf;

use super::jni_bootstrap;

/// Attach the calling thread to the captured JavaVM and run
/// `f` with a live `JNIEnv`. The attach guard auto-detaches on
/// drop, so worker threads spawned inside `tokio::task::spawn_blocking`
/// don't leak JVM thread attachments.
///
/// Returns `Err("jni: …")` strings (rather than `jni::errors::Error`)
/// for caller convenience — the upstream `SecureStorageError`
/// / `BiometricUnavailableReason` enums all have a string-bearing
/// variant so the JNI failure surfaces with context intact.
pub fn with_env<F, R>(f: F) -> Result<R, String>
where
    F: for<'a> FnOnce(&mut AttachGuard<'a>) -> Result<R, String>,
{
    let vm = jni_bootstrap::java_vm().ok_or_else(|| {
        "jni: JavaVM not bootstrapped (LfsJniBootstrap.register not called)".to_string()
    })?;
    let mut guard = vm
        .attach_current_thread()
        .map_err(|e| format!("jni: attach_current_thread: {e}"))?;
    f(&mut guard)
}

/// Convert a Rust byte slice to a Java byte[]. Returned
/// `JByteArray` lives in the local JNI frame; do not promote
/// to `GlobalRef` unless the call site owns the lifetime.
pub fn bytes_to_jbyte_array<'local>(
    env: &mut JNIEnv<'local>,
    bytes: &[u8],
) -> Result<JByteArray<'local>, String> {
    // JNI's `new_byte_array` takes an `i32`; Rust's `usize` is 64-bit
    // on every Android target we ship. A 2 GiB+ buffer would silently
    // truncate to a negative `i32` under `as i32` and the JVM would
    // then throw `NegativeArraySizeException` after we'd already lost
    // size fidelity. `try_from` surfaces the overflow as our typed
    // error so the caller gets a clear bound-violation message.
    let len: i32 = i32::try_from(bytes.len())
        .map_err(|_| format!("jni: byte array length overflow ({} > i32::MAX)", bytes.len()))?;
    let array = env
        .new_byte_array(len)
        .map_err(|e| format!("jni: new_byte_array: {e}"))?;
    if !bytes.is_empty() {
        // `i8` reinterpret of `u8` slice is safe — same memory
        // layout, sign interpretation does not matter for the
        // raw byte array transit.
        let i8_view =
            unsafe { std::slice::from_raw_parts(bytes.as_ptr() as *const i8, bytes.len()) };
        env.set_byte_array_region(&array, 0, i8_view)
            .map_err(|e| format!("jni: set_byte_array_region: {e}"))?;
    }
    Ok(array)
}

/// Convert a Java byte[] (as `JObject`) back to a Rust `Vec<u8>`.
/// Caller asserts the object is a non-null byte[]; if it isn't,
/// the conversion error surfaces as `Err(String)` for the
/// caller to map.
pub fn jbyte_array_to_bytes(env: &mut JNIEnv, array: &JObject) -> Result<Vec<u8>, String> {
    let array = JByteArray::from(unsafe { JObject::from_raw(array.as_raw()) });
    let len = env
        .get_array_length(&array)
        .map_err(|e| format!("jni: get_array_length: {e}"))?;
    // `get_array_length` returns `i32`; reject negative as a malformed
    // JNI handle rather than letting `as usize` reinterpret to a
    // huge value that allocates panics on Vec::with_capacity.
    let buf_len = usize::try_from(len)
        .map_err(|_| format!("jni: get_array_length returned negative ({len})"))?;
    let mut buf = vec![0i8; buf_len];
    env.get_byte_array_region(&array, 0, &mut buf)
        .map_err(|e| format!("jni: get_byte_array_region: {e}"))?;
    Ok(buf.into_iter().map(|b| b as u8).collect())
}

/// Resolve `applicationContext.getFilesDir().getAbsolutePath()`
/// once per call — on the order of microseconds; not worth
/// caching given the LFS storage write rate.
pub fn app_files_dir(env: &mut JNIEnv) -> Result<PathBuf, String> {
    let context: &GlobalRef = jni_bootstrap::app_context()
        .ok_or_else(|| "jni: app context not bootstrapped".to_string())?;
    let files_dir = env
        .call_method(context, "getFilesDir", "()Ljava/io/File;", &[])
        .and_then(|v| v.l())
        .map_err(|e| format!("jni: getFilesDir: {e}"))?;
    let path_jstring: JString = env
        .call_method(&files_dir, "getAbsolutePath", "()Ljava/lang/String;", &[])
        .and_then(|v| v.l())
        .map(JString::from)
        .map_err(|e| format!("jni: getAbsolutePath: {e}"))?;
    let path: String = env
        .get_string(&path_jstring)
        .map(|s| s.into())
        .map_err(|e| format!("jni: get_string: {e}"))?;
    Ok(PathBuf::from(path))
}

/// Wrap a Rust `&str` as a JNI local-frame Java `String`.
pub fn jstring<'local>(env: &mut JNIEnv<'local>, s: &str) -> Result<JString<'local>, String> {
    env.new_string(s)
        .map_err(|e| format!("jni: new_string: {e}"))
}

/// Look up an `int` static field on `class_name` (e.g. the
/// `KeyProperties.PURPOSE_ENCRYPT` constants). Cached lookups
/// would be marginally faster but the call rate is low enough
/// (once per seal/unseal) that a fresh lookup per call is fine.
pub fn static_int_field(env: &mut JNIEnv, class_name: &str, field: &str) -> Result<i32, String> {
    let class = env
        .find_class(class_name)
        .map_err(|e| format!("jni: find_class {class_name}: {e}"))?;
    env.get_static_field(class, field, "I")
        .and_then(|v| v.i())
        .map_err(|e| format!("jni: static int {class_name}.{field}: {e}"))
}

/// Drain any pending JVM exception left after a failing JNI call.
///
/// JNI's contract: a Java method that throws leaves the exception
/// object posted on the JVM's per-thread "pending" slot. The next
/// JNI call from the same thread will see it AS an exception
/// (most calls then immediately abort + the JVM aborts the
/// process on the second call). We log the exception text via
/// `app_log_warn!` so support traces show what threw, then clear
/// the slot so subsequent JNI calls on the same thread can run.
///
/// Closes the audit's B-OSFFI-4 "JNI exception clear gap":
/// previously every `call_method` failure returned the Rust-side
/// `Err(String)` but left the Java exception parked on the JNI
/// frame, occasionally surfacing as a hard process abort on the
/// next JNI hop.
fn drain_exception(env: &mut JNIEnv, ctx: &str) {
    let occurred = env.exception_check().unwrap_or(false);
    if !occurred {
        return;
    }
    // `exception_describe` writes to logcat directly — informative
    // on Android, harmless on host JVM. Best-effort: a failure
    // describing should not block the clear.
    let _ = env.exception_describe();
    if let Err(clear_err) = env.exception_clear() {
        eprintln!(
            "JniHelpers: drain_exception failed to clear after {ctx}: {clear_err}"
        );
    }
}

/// Convenience wrapper around `env.call_method` that converts
/// the resulting `JValueOwned` into a `JObject` — the most
/// common return type for our chains.
pub fn call_obj<'local>(
    env: &mut JNIEnv<'local>,
    obj: &JObject,
    name: &'static str,
    sig: &'static str,
    args: &[JValue],
) -> Result<JObject<'local>, String> {
    match env.call_method(obj, name, sig, args).and_then(|v| v.l()) {
        Ok(v) => Ok(v),
        Err(e) => {
            drain_exception(env, &format!("call_obj {name}{sig}"));
            Err(format!("jni: {name}{sig}: {e}"))
        }
    }
}

/// Call a static method that returns an Object.
pub fn call_static_obj<'local>(
    env: &mut JNIEnv<'local>,
    class_name: &str,
    name: &'static str,
    sig: &'static str,
    args: &[JValue],
) -> Result<JObject<'local>, String> {
    let class = match env.find_class(class_name) {
        Ok(c) => c,
        Err(e) => {
            drain_exception(env, &format!("find_class {class_name}"));
            return Err(format!("jni: find_class {class_name}: {e}"));
        }
    };
    match env
        .call_static_method(class, name, sig, args)
        .and_then(|v| v.l())
    {
        Ok(v) => Ok(v),
        Err(e) => {
            drain_exception(env, &format!("call_static_obj {name}{sig}"));
            Err(format!("jni: static {name}{sig}: {e}"))
        }
    }
}

/// Call a method that returns a primitive boolean.
pub fn call_bool(
    env: &mut JNIEnv,
    obj: &JObject,
    name: &'static str,
    sig: &'static str,
    args: &[JValue],
) -> Result<bool, String> {
    match env.call_method(obj, name, sig, args).and_then(|v| v.z()) {
        Ok(v) => Ok(v),
        Err(e) => {
            drain_exception(env, &format!("call_bool {name}{sig}"));
            Err(format!("jni: {name}{sig}: {e}"))
        }
    }
}

/// Call a void method.
pub fn call_void(
    env: &mut JNIEnv,
    obj: &JObject,
    name: &'static str,
    sig: &'static str,
    args: &[JValue],
) -> Result<(), String> {
    match env.call_method(obj, name, sig, args) {
        Ok(_) => Ok(()),
        Err(e) => {
            drain_exception(env, &format!("call_void {name}{sig}"));
            Err(format!("jni: {name}{sig}: {e}"))
        }
    }
}
