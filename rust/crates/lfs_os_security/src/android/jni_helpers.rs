//! Common JNI helpers shared across the Android `lfs_os_security`
//! sub-modules. Each helper boxes a single recurring pattern so
//! the keystore / biometric / StrongBox call sites stay focused
//! on the platform-specific call sequence rather than re-deriving
//! `attach_current_thread` boilerplate.

use jni::objects::{JByteArray, JObject, JString, JValue};
use jni::refs::Global;
use jni::signature::{RuntimeFieldSignature, RuntimeMethodSignature};
use jni::strings::JNIString;
use jni::Env;
use std::path::PathBuf;

use super::jni_bootstrap;

/// Attach the calling thread to the captured JavaVM and run
/// `f` with a live `Env`. The attach guard auto-detaches on
/// drop, so worker threads spawned inside `tokio::task::spawn_blocking`
/// don't leak JVM thread attachments.
///
/// Returns `Err("jni: …")` strings (rather than `jni::errors::Error`)
/// for caller convenience — the upstream `SecureStorageError`
/// / `BiometricUnavailableReason` enums all have a string-bearing
/// variant so the JNI failure surfaces with context intact.
pub fn with_env<F, R>(f: F) -> Result<R, String>
where
    F: for<'a> FnOnce(&mut Env<'a>) -> Result<R, String>,
{
    let vm = jni_bootstrap::java_vm().ok_or_else(|| {
        "jni: JavaVM not bootstrapped (LfsJniBootstrap.register not called)".to_string()
    })?;
    // `attach_current_thread` requires the closure's error type to be
    // `From<jni::errors::Error>`, which `String` is not. Carry our
    // `Result<R, String>` as the closure's success value and reserve
    // the attach call's own error channel (`jni::errors::Error`) for
    // attach failures alone.
    vm.attach_current_thread(|env| -> Result<Result<R, String>, jni::errors::Error> { Ok(f(env)) })
        .map_err(|e| format!("jni: attach_current_thread: {e}"))?
}

/// Convert a Rust byte slice to a Java byte[]. Returned
/// `JByteArray` lives in the local JNI frame; do not promote
/// to a `Global` reference unless the call site owns the lifetime.
pub fn bytes_to_jbyte_array<'local>(
    env: &mut Env<'local>,
    bytes: &[u8],
) -> Result<JByteArray<'local>, String> {
    // JNI's array index space is `i32`; a 2 GiB+ buffer would later
    // throw `NegativeArraySizeException` inside the JVM. The `try_from`
    // to `i32` surfaces the overflow as our typed error so the caller
    // gets a clear bound-violation message before the JVM ever sees it.
    i32::try_from(bytes.len()).map_err(|_| {
        format!(
            "jni: byte array length overflow ({} > i32::MAX)",
            bytes.len()
        )
    })?;
    let array = env
        .new_byte_array(bytes.len())
        .map_err(|e| format!("jni: new_byte_array: {e}"))?;
    if !bytes.is_empty() {
        // `i8` reinterpret of `u8` slice is safe — same memory
        // layout, sign interpretation does not matter for the
        // raw byte array transit.
        let i8_view =
            // SAFETY: `slice::from_raw_parts` constructs a slice from a pointer + length; the
            // pointer is owned by the calling FFI and valid for the slice length for the borrow's
            // duration.
            unsafe { std::slice::from_raw_parts(bytes.as_ptr() as *const i8, bytes.len()) };
        array
            .set_region(env, 0, i8_view)
            .map_err(|e| format!("jni: set_byte_array_region: {e}"))?;
    }
    Ok(array)
}

/// Convert a Java byte[] (as `JObject`) back to a Rust `Vec<u8>`.
/// Caller asserts the object is a non-null byte[]; if it isn't,
/// the conversion error surfaces as `Err(String)` for the
/// caller to map.
pub fn jbyte_array_to_bytes(env: &mut Env, array: &JObject) -> Result<Vec<u8>, String> {
    // SAFETY: `JByteArray::from_raw` rewraps a jobject reference we received via JNI; the jobject is
    // alive for the JNI frame and we hold a local reference for the rest of the function.
    let array = unsafe { JByteArray::from_raw(env, array.as_raw()) };
    let len = array
        .len(env)
        .map_err(|e| format!("jni: get_array_length: {e}"))?;
    let mut buf = vec![0i8; len];
    array
        .get_region(env, 0, &mut buf)
        .map_err(|e| format!("jni: get_byte_array_region: {e}"))?;
    Ok(buf.into_iter().map(|b| b as u8).collect())
}

/// Resolve `applicationContext.getFilesDir().getAbsolutePath()`
/// once per call — on the order of microseconds; not worth
/// caching given the LFS storage write rate.
pub fn app_files_dir(env: &mut Env) -> Result<PathBuf, String> {
    let context: &Global<JObject<'static>> = jni_bootstrap::app_context()
        .ok_or_else(|| "jni: app context not bootstrapped".to_string())?;
    let files_dir = call_obj(env, context, "getFilesDir", "()Ljava/io/File;", &[])?;
    let path_jobj = call_obj(
        env,
        &files_dir,
        "getAbsolutePath",
        "()Ljava/lang/String;",
        &[],
    )?;
    let path: String = jstring_to_string(env, path_jobj)?;
    Ok(PathBuf::from(path))
}

/// Wrap a Rust `&str` as a JNI local-frame Java `String`.
pub fn jstring<'local>(env: &mut Env<'local>, s: &str) -> Result<JString<'local>, String> {
    env.new_string(s)
        .map_err(|e| format!("jni: new_string: {e}"))
}

/// Decode a Java `String` object (handed to us as a `JObject`) into a
/// Rust `String`. Caller asserts the object is a non-null
/// `java.lang.String`.
pub fn jstring_to_string(env: &mut Env, obj: JObject) -> Result<String, String> {
    // SAFETY: `JString::from_raw` rewraps a `java.lang.String` reference we received via JNI; the
    // jobject is alive for the JNI frame and we hold a local reference for the decode.
    let jstr = unsafe { JString::from_raw(env, obj.into_raw()) };
    jstr.try_to_string(env)
        .map_err(|e| format!("jni: get_string: {e}"))
}

/// Encode a method / field / class name as a JNI MUTF-8 string for
/// the `AsRef<JNIStr>`-typed `name` arguments the 0.22 JNI calls
/// expect. Used by call sites that issue raw `env.call_method` /
/// `env.new_object` / `env.find_class` calls with their own error
/// mapping rather than routing through the helpers below.
pub fn jni_name(s: &str) -> JNIString {
    JNIString::new(s)
}

/// Parse a runtime JNI method signature, mapping the parse error
/// to our string envelope. Exposed so raw call sites can build a
/// `MethodSignature` for `env.call_method` / `env.new_object` via
/// `h::method_sig(sig)?.method_signature()`.
pub fn method_sig(sig: &str) -> Result<RuntimeMethodSignature, String> {
    RuntimeMethodSignature::from_str(sig)
        .map_err(|e| format!("jni: bad method signature {sig}: {e}"))
}

/// Parse a runtime JNI field signature for raw `env.get_field` /
/// `env.get_static_field` call sites: `h::field_sig(sig)?.field_signature()`.
pub fn field_sig(sig: &str) -> Result<RuntimeFieldSignature, String> {
    RuntimeFieldSignature::from_str(sig).map_err(|e| format!("jni: bad field signature {sig}: {e}"))
}

/// Look up an `int` static field on `class_name` (e.g. the
/// `KeyProperties.PURPOSE_ENCRYPT` constants). Cached lookups
/// would be marginally faster but the call rate is low enough
/// (once per seal/unseal) that a fresh lookup per call is fine.
pub fn static_int_field(env: &mut Env, class_name: &str, field: &str) -> Result<i32, String> {
    let class = env
        .find_class(JNIString::new(class_name))
        .map_err(|e| format!("jni: find_class {class_name}: {e}"))?;
    env.get_static_field(
        &class,
        JNIString::new(field),
        field_sig("I")?.field_signature(),
    )
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
/// Without this drain, every `call_method` failure returns the
/// Rust-side `Err(String)` but leaves the Java exception parked
/// on the JNI frame, occasionally surfacing as a hard process
/// abort on the next JNI hop.
fn drain_exception(env: &mut Env, _ctx: &str) {
    if !env.exception_check() {
        return;
    }
    // `exception_describe` writes to logcat directly — informative
    // on Android, harmless on host JVM. Best-effort: a failure
    // describing should not block the clear.
    env.exception_describe();
    env.exception_clear();
}

/// Convenience wrapper around `env.call_method` that converts
/// the resulting `JValueOwned` into a `JObject` — the most
/// common return type for our chains.
pub fn call_obj<'local>(
    env: &mut Env<'local>,
    obj: &JObject,
    name: &'static str,
    sig: &'static str,
    args: &[JValue],
) -> Result<JObject<'local>, String> {
    let parsed = method_sig(sig)?;
    match env
        .call_method(obj, JNIString::new(name), parsed.method_signature(), args)
        .and_then(|v| v.l())
    {
        Ok(v) => Ok(v),
        Err(e) => {
            drain_exception(env, &format!("call_obj {name}{sig}"));
            Err(format!("jni: {name}{sig}: {e}"))
        }
    }
}

/// Call a static method that returns an Object.
pub fn call_static_obj<'local>(
    env: &mut Env<'local>,
    class_name: &str,
    name: &'static str,
    sig: &'static str,
    args: &[JValue],
) -> Result<JObject<'local>, String> {
    let parsed = method_sig(sig)?;
    let class = match env.find_class(JNIString::new(class_name)) {
        Ok(c) => c,
        Err(e) => {
            drain_exception(env, &format!("find_class {class_name}"));
            return Err(format!("jni: find_class {class_name}: {e}"));
        }
    };
    match env
        .call_static_method(
            &class,
            JNIString::new(name),
            parsed.method_signature(),
            args,
        )
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
    env: &mut Env,
    obj: &JObject,
    name: &'static str,
    sig: &'static str,
    args: &[JValue],
) -> Result<bool, String> {
    let parsed = method_sig(sig)?;
    match env
        .call_method(obj, JNIString::new(name), parsed.method_signature(), args)
        .and_then(|v| v.z())
    {
        Ok(v) => Ok(v),
        Err(e) => {
            drain_exception(env, &format!("call_bool {name}{sig}"));
            Err(format!("jni: {name}{sig}: {e}"))
        }
    }
}

/// Call a void method.
pub fn call_void(
    env: &mut Env,
    obj: &JObject,
    name: &'static str,
    sig: &'static str,
    args: &[JValue],
) -> Result<(), String> {
    let parsed = method_sig(sig)?;
    match env.call_method(obj, JNIString::new(name), parsed.method_signature(), args) {
        Ok(_) => Ok(()),
        Err(e) => {
            drain_exception(env, &format!("call_void {name}{sig}"));
            Err(format!("jni: {name}{sig}: {e}"))
        }
    }
}
