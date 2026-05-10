//! `android.content.ClipboardManager` JNI bridge.
//!
//! Single Rust entry point for the Android clipboard write so the
//! cross-platform [`super::super::secure_clipboard::set_secure_text`]
//! dispatcher has one branch per OS instead of the Dart caller
//! short-circuiting to a Kotlin MethodChannel before the call ever
//! reaches Rust.
//!
//! ## Sensitivity flag
//!
//! Android 13 (Tiramisu, API 33) added
//! `ClipDescription.EXTRA_IS_SENSITIVE`. The system reads it when
//! deciding whether to render the clipboard-history toast preview
//! and whether to advertise the content to the launcher
//! "share what you copied" affordances. Setting the flag hides
//! passwords and tokens from the shoulder-surf surface without
//! refusing to copy.
//!
//! ## API gating
//!
//! Pre-Tiramisu SDKs do not expose the typed constant, but the
//! underlying `PersistableBundle` key is the same string —
//! `"android.content.extra.IS_SENSITIVE"`. Some OEM clipboard
//! surfaces backported the hint to API 30-32 builds and honour
//! the raw key. The module reads `android.os.Build.VERSION.SDK_INT`
//! at call time via [`super::jni_helpers::static_int_field`] and
//! picks the typed constant on 33+, the raw key elsewhere. Either
//! way the write succeeds; the OS just may or may not honour the
//! hint depending on its build.

use jni::objects::JValue;

use super::jni_bootstrap;
use super::jni_helpers as h;

/// `android.os.Build.VERSION_CODES.TIRAMISU` constant value (API 33).
const SDK_INT_TIRAMISU: i32 = 33;

/// Write `text` to the primary Android clipboard with the
/// `EXTRA_IS_SENSITIVE` hint set on the `ClipDescription`.
///
/// * **Input** — UTF-8 text, copied verbatim into a
///   `ClipData.newPlainText("", text)` item.
/// * **Return** — `Ok(())` on a successful `setPrimaryClip` call;
///   `Err(String)` when the JNI bootstrap is missing, the
///   `Context.getSystemService(CLIPBOARD_SERVICE)` returns null,
///   or any of the JNI hops surface an exception. The caller maps
///   the error onto a localized "copy failed" toast.
/// * **Failure modes** — `Err` on missing JavaVM bootstrap
///   (LfsJniBootstrap.register not called); on a null clipboard
///   service (ROMs without a system clipboard, very rare); on a
///   pending Java exception drained by the JNI helpers.
pub fn set_secure_text(text: &str) -> Result<(), String> {
    h::with_env(|env| {
        let context = jni_bootstrap::app_context()
            .ok_or_else(|| "clipboard: app context not bootstrapped".to_string())?;

        // ClipboardManager cb = (ClipboardManager)
        //     ctx.getSystemService(Context.CLIPBOARD_SERVICE);
        //
        // `Context.CLIPBOARD_SERVICE` is the string constant
        // `"clipboard"`; passing the literal sidesteps a separate
        // static-field lookup.
        let service_name = h::jstring(env, "clipboard")?;
        let clipboard = h::call_obj(
            env,
            context.as_obj(),
            "getSystemService",
            "(Ljava/lang/String;)Ljava/lang/Object;",
            &[(&service_name).into()],
        )?;
        if clipboard.is_null() {
            return Err("clipboard: getSystemService(CLIPBOARD_SERVICE) returned null".to_string());
        }

        // ClipData clip = ClipData.newPlainText("", text);
        let empty_label = h::jstring(env, "")?;
        let text_jstr = h::jstring(env, text)?;
        let clip = h::call_static_obj(
            env,
            "android/content/ClipData",
            "newPlainText",
            "(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Landroid/content/ClipData;",
            &[(&empty_label).into(), (&text_jstr).into()],
        )?;

        // ClipDescription desc = clip.getDescription();
        let desc = h::call_obj(
            env,
            &clip,
            "getDescription",
            "()Landroid/content/ClipDescription;",
            &[],
        )?;

        // PersistableBundle extras = new PersistableBundle();
        let extras = {
            let class = env
                .find_class("android/os/PersistableBundle")
                .map_err(|e| format!("jni: find_class PersistableBundle: {e}"))?;
            env.new_object(class, "()V", &[])
                .map_err(|e| format!("jni: new PersistableBundle: {e}"))?
        };

        // The typed constant `ClipDescription.EXTRA_IS_SENSITIVE`
        // exists on API 33+; on older SDKs the field lookup fails
        // and we fall through to the raw string key. Both resolve
        // to the same underlying bundle entry.
        let sdk_int = h::static_int_field(env, "android/os/Build$VERSION", "SDK_INT").unwrap_or(0);
        let key_name = if sdk_int >= SDK_INT_TIRAMISU {
            // ClipDescription.EXTRA_IS_SENSITIVE — String constant.
            // Resolve dynamically so we don't bake the string into Rust
            // and drift if Google ever renames it (they have not, and
            // the field is part of the public API contract since
            // Tiramisu).
            read_extra_is_sensitive(env)
                .unwrap_or_else(|| "android.content.extra.IS_SENSITIVE".to_string())
        } else {
            "android.content.extra.IS_SENSITIVE".to_string()
        };
        let key_jstr = h::jstring(env, &key_name)?;
        h::call_void(
            env,
            &extras,
            "putBoolean",
            "(Ljava/lang/String;Z)V",
            &[(&key_jstr).into(), JValue::Bool(1)],
        )?;

        // desc.setExtras(extras);
        h::call_void(
            env,
            &desc,
            "setExtras",
            "(Landroid/os/PersistableBundle;)V",
            &[(&extras).into()],
        )?;

        // cb.setPrimaryClip(clip);
        h::call_void(
            env,
            &clipboard,
            "setPrimaryClip",
            "(Landroid/content/ClipData;)V",
            &[(&clip).into()],
        )?;

        Ok(())
    })
}

/// Read the runtime value of `ClipDescription.EXTRA_IS_SENSITIVE`
/// (a `public static final String` on API 33+). Returns `None` on
/// any JNI failure so the caller can substitute the well-known
/// literal — both resolve to the same persisted bundle key.
fn read_extra_is_sensitive(env: &mut jni::JNIEnv) -> Option<String> {
    let class = env.find_class("android/content/ClipDescription").ok()?;
    let field = env
        .get_static_field(class, "EXTRA_IS_SENSITIVE", "Ljava/lang/String;")
        .ok()?;
    let obj = field.l().ok()?;
    let jstr = jni::objects::JString::from(obj);
    let s: String = env.get_string(&jstr).ok().map(|s| s.into())?;
    Some(s)
}
