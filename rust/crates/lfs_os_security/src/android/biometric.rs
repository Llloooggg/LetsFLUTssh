//! `androidx.biometric.BiometricPrompt` JNI bridge.
//!
//! Replaces the `local_auth` Dart plugin's Android backend with
//! direct JNI calls into `androidx.biometric.BiometricPrompt` +
//! `androidx.biometric.BiometricManager`. The
//! `BiometricPrompt.AuthenticationCallback` abstract class is
//! implemented at runtime by a tiny Kotlin glue object
//! (`LfsBiometricCallback`) that routes its three callback
//! methods (`onAuthenticationSucceeded`, `onAuthenticationFailed`,
//! `onAuthenticationError`) back into Rust through `extern
//! "system"` entry points. The Kotlin object is pure adapter
//! plumbing — no business logic, equivalent in spirit to
//! `objc2`'s block adapter for Apple `LAContext`.
//!
//! ## Threading
//!
//! `BiometricPrompt.authenticate(...)` MUST be called on the
//! main thread. We achieve this by posting a `Runnable` through
//! the `Handler(Looper.getMainLooper())` from the Rust
//! background thread. The callback methods fire on the main
//! thread too; they hand the result to a tokio `oneshot::Sender`
//! held in a process-wide `Mutex<HashMap<u64, Sender>>` keyed
//! on a `request_id` we generate per call.
//!
//! ## Verification status
//!
//! Same NI-2 gate as the keystore module: source compiles
//! against `aarch64-linux-android` via the rust-cross-check
//! matrix; runtime correctness needs a real device or
//! emulator with enrolled biometrics. The `BiometricPrompt`
//! API has subtle version-gating (the `AUTH_BIOMETRIC_STRONG`
//! constant is API 30+; the callback method signatures
//! shifted between alpha and 1.0 of `androidx.biometric`)
//! that integration tests must validate per
//! `minSdkVersion`.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

use jni::objects::{JObject, JValue};
use jni::sys::{jint, jlong};
use tokio::sync::oneshot;

use super::jni_bootstrap;
use super::jni_helpers as h;

/// Map of in-flight prompt requests, keyed on a per-request
/// `u64` we pass to the Kotlin callback as a `long` so the
/// callback knows which sender to fulfil.
type PendingMap = Mutex<HashMap<u64, oneshot::Sender<BiometricResult>>>;

static PENDING: OnceLock<PendingMap> = OnceLock::new();
static NEXT_REQ_ID: AtomicU64 = AtomicU64::new(1);

fn pending() -> &'static PendingMap {
    PENDING.get_or_init(|| Mutex::new(HashMap::new()))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BiometricResult {
    Succeeded,
    Failed,
    /// `BiometricPrompt.ERROR_*` constant carried straight
    /// through. The relevant ones we map upstream:
    /// `ERROR_USER_CANCELED` (10), `ERROR_LOCKOUT` (7),
    /// `ERROR_LOCKOUT_PERMANENT` (9), `ERROR_NO_BIOMETRICS`
    /// (11). Anything else surfaces as a generic prompt
    /// failure.
    Error(i32),
}

/// `BiometricManager.canAuthenticate(BIOMETRIC_STRONG)` →
/// classified outcome. Returns the constant the JCA enum
/// produces (`BIOMETRIC_SUCCESS = 0`, `BIOMETRIC_ERROR_NO_HARDWARE
/// = 12`, etc.) so the caller can map onto the
/// `BiometricUnavailableReason` enum.
pub async fn can_authenticate() -> Result<i32, String> {
    tokio::task::spawn_blocking(can_authenticate_blocking)
        .await
        .map_err(|e| format!("tokio join: {e}"))?
}

fn can_authenticate_blocking() -> Result<i32, String> {
    h::with_env(|env| {
        let context = jni_bootstrap::app_context()
            .ok_or_else(|| "biometric: app context not bootstrapped".to_string())?;
        // BiometricManager bm = BiometricManager.from(context);
        let bm = h::call_static_obj(
            env,
            "androidx/biometric/BiometricManager",
            "from",
            "(Landroid/content/Context;)Landroidx/biometric/BiometricManager;",
            &[(context).into()],
        )?;
        // int result = bm.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG);
        // BIOMETRIC_STRONG constant value is 0xF (15).
        let strong = h::static_int_field(
            env,
            "androidx/biometric/BiometricManager$Authenticators",
            "BIOMETRIC_STRONG",
        )
        .unwrap_or(0xF);
        env.call_method(&bm, "canAuthenticate", "(I)I", &[JValue::Int(strong)])
            .and_then(|v| v.i())
            .map_err(|e| format!("biometric: canAuthenticate: {e}"))
    })
}

/// Show `BiometricPrompt` and await the user's response.
/// `title` + `subtitle` populate the prompt UI; both are
/// rendered by Android verbatim.
pub async fn authenticate(title: &str, subtitle: &str) -> BiometricResult {
    let (tx, rx) = oneshot::channel();
    let req_id = NEXT_REQ_ID.fetch_add(1, Ordering::Relaxed);
    pending()
        .lock()
        .expect("pending map poisoned")
        .insert(req_id, tx);

    let title = title.to_string();
    let subtitle = subtitle.to_string();
    if tokio::task::spawn_blocking(move || show_prompt_blocking(req_id, &title, &subtitle))
        .await
        .is_err()
    {
        // Tokio join failure — drop the pending entry, surface
        // as a generic error.
        pending()
            .lock()
            .expect("pending map poisoned")
            .remove(&req_id);
        return BiometricResult::Error(-1);
    }
    rx.await.unwrap_or(BiometricResult::Error(-1))
}

fn show_prompt_blocking(req_id: u64, title: &str, subtitle: &str) -> Result<(), String> {
    h::with_env(|env| {
        let activity = jni_bootstrap::main_activity().ok_or_else(|| {
            "biometric: MainActivity not bootstrapped".to_string()
        })?;

        // Build BiometricPrompt.PromptInfo via PromptInfo.Builder.
        let info_builder_class = "androidx/biometric/BiometricPrompt$PromptInfo$Builder";
        let info_builder = {
            let class = env
                .find_class(info_builder_class)
                .map_err(|e| format!("jni: find_class {info_builder_class}: {e}"))?;
            env.new_object(class, "()V", &[])
                .map_err(|e| format!("jni: new PromptInfo.Builder: {e}"))?
        };
        let title_jstr = h::jstring(env, title)?;
        h::call_obj(
            env,
            &info_builder,
            "setTitle",
            "(Ljava/lang/CharSequence;)Landroidx/biometric/BiometricPrompt$PromptInfo$Builder;",
            &[(&title_jstr).into()],
        )?;
        if !subtitle.is_empty() {
            let sub_jstr = h::jstring(env, subtitle)?;
            h::call_obj(
                env,
                &info_builder,
                "setSubtitle",
                "(Ljava/lang/CharSequence;)Landroidx/biometric/BiometricPrompt$PromptInfo$Builder;",
                &[(&sub_jstr).into()],
            )?;
        }
        // Restrict to BIOMETRIC_STRONG so a software-only HAL
        // does not satisfy the prompt.
        let strong = h::static_int_field(
            env,
            "androidx/biometric/BiometricManager$Authenticators",
            "BIOMETRIC_STRONG",
        )
        .unwrap_or(0xF);
        h::call_obj(
            env,
            &info_builder,
            "setAllowedAuthenticators",
            "(I)Landroidx/biometric/BiometricPrompt$PromptInfo$Builder;",
            &[JValue::Int(strong)],
        )?;
        let cancel_jstr = h::jstring(env, "Cancel")?;
        h::call_obj(
            env,
            &info_builder,
            "setNegativeButtonText",
            "(Ljava/lang/CharSequence;)Landroidx/biometric/BiometricPrompt$PromptInfo$Builder;",
            &[(&cancel_jstr).into()],
        )?;
        let prompt_info = h::call_obj(
            env,
            &info_builder,
            "build",
            "()Landroidx/biometric/BiometricPrompt$PromptInfo;",
            &[],
        )?;

        // Instantiate the Kotlin callback adapter:
        //   LfsBiometricCallback callback = new LfsBiometricCallback(reqId);
        let cb_class = "com/llloooggg/letsflutssh/LfsBiometricCallback";
        let callback = {
            let class = env
                .find_class(cb_class)
                .map_err(|e| format!("jni: find_class {cb_class}: {e}"))?;
            env.new_object(class, "(J)V", &[JValue::Long(req_id as jlong)])
                .map_err(|e| format!("jni: new LfsBiometricCallback: {e}"))?
        };

        // Get a main-thread executor: ContextCompat.getMainExecutor(activity).
        let executor = h::call_static_obj(
            env,
            "androidx/core/content/ContextCompat",
            "getMainExecutor",
            "(Landroid/content/Context;)Ljava/util/concurrent/Executor;",
            &[(activity).into()],
        )?;

        // BiometricPrompt prompt = new BiometricPrompt(activity, executor, callback);
        let prompt_class = "androidx/biometric/BiometricPrompt";
        let prompt = {
            let class = env
                .find_class(prompt_class)
                .map_err(|e| format!("jni: find_class {prompt_class}: {e}"))?;
            env.new_object(
                class,
                "(Landroidx/fragment/app/FragmentActivity;Ljava/util/concurrent/Executor;Landroidx/biometric/BiometricPrompt$AuthenticationCallback;)V",
                &[(activity).into(), (&executor).into(), (&callback).into()],
            )
            .map_err(|e| format!("jni: new BiometricPrompt: {e}"))?
        };

        // The actual authenticate() call must run on the main
        // thread. We post a Runnable to the main looper that
        // invokes prompt.authenticate(promptInfo). Easiest
        // way: have the Kotlin callback object expose a
        // helper that runs the call.
        //
        // For brevity here we rely on
        // `LfsBiometricCallback.dispatchAuthenticate(prompt,
        // info)` doing the main-thread post + invoking
        // BiometricPrompt.authenticate(info).
        h::call_void(
            env,
            &callback,
            "dispatchAuthenticate",
            "(Landroidx/biometric/BiometricPrompt;Landroidx/biometric/BiometricPrompt$PromptInfo;)V",
            &[(&prompt).into(), (&prompt_info).into()],
        )?;

        Ok(())
    })
    .map_err(|e| {
        // Drop the pending entry — caller's oneshot will hang
        // forever otherwise.
        if let Ok(mut map) = pending().lock() {
            map.remove(&req_id);
        }
        e
    })
}

// ── extern "system" callbacks invoked by LfsBiometricCallback ──

fn deliver(req_id: u64, result: BiometricResult) {
    if let Ok(mut map) = pending().lock() {
        if let Some(tx) = map.remove(&req_id) {
            let _ = tx.send(result);
        }
    }
}

#[no_mangle]
pub unsafe extern "system" fn Java_com_llloooggg_letsflutssh_LfsBiometricCallback_nativeOnSucceeded<
    'local,
>(
    _env: jni::JNIEnv<'local>,
    _class: jni::objects::JClass<'local>,
    req_id: jlong,
) {
    deliver(req_id as u64, BiometricResult::Succeeded);
}

#[no_mangle]
pub unsafe extern "system" fn Java_com_llloooggg_letsflutssh_LfsBiometricCallback_nativeOnFailed<
    'local,
>(
    _env: jni::JNIEnv<'local>,
    _class: jni::objects::JClass<'local>,
    req_id: jlong,
) {
    deliver(req_id as u64, BiometricResult::Failed);
}

#[no_mangle]
pub unsafe extern "system" fn Java_com_llloooggg_letsflutssh_LfsBiometricCallback_nativeOnError<
    'local,
>(
    _env: jni::JNIEnv<'local>,
    _class: jni::objects::JClass<'local>,
    req_id: jlong,
    code: jint,
) {
    deliver(req_id as u64, BiometricResult::Error(code as i32));
}

// Suppress the unused-import warning for `JObject` when the
// module-level helpers don't trigger it on every cfg path.
#[allow(dead_code)]
fn _unused_jobject_imports() {
    let _: Option<JObject> = None;
}
