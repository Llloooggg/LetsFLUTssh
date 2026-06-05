//! Android Hardware Keystore / StrongBox SSH signer JNI bridge.
//!
//! Mirrors the [`super::biometric`] shape — every operation rides
//! `tokio::task::spawn_blocking` from the FRB worker, a process-
//! wide pending map matches JVM callbacks to `oneshot::Sender`s by
//! `request_id`, and the actual `BiometricPrompt.authenticate(...)`
//! call hops through the main thread via a Kotlin helper. The
//! Kotlin side is intentionally minimal — `KeystoreSshSigner`
//! issues `KeyPairGenerator` / `Signature` calls and the
//! `LfsKeystoreSignCallback` adapter routes the prompt's
//! `onAuthenticationSucceeded` / `onAuthenticationError` back
//! into Rust through `extern "system"` entry points keyed on the
//! per-sign `requestId` we hand it.
//!
//! ## Why a Kotlin shim instead of pure JNI
//!
//! `BiometricPrompt.AuthenticationCallback` is an abstract class
//! with three abstract methods; subclassing it from Rust via
//! `Env::register_native_methods` is supported by the `jni`
//! crate but extremely fragile across `androidx.biometric` minor
//! versions (the alpha → 1.0 cutover shifted the
//! `AuthenticationResult` constructor signature). A tiny Kotlin
//! adapter avoids the moving target — the JVM-side class binds
//! once at compile time and the JNI surface is three `extern fn`
//! entry points the Kotlin overrides invoke.
//!
//! ## Algorithm surface
//!
//! Three SSH algorithms cross the JNI: ECDSA P-256 / Ed25519
//! (Android 13+ only) / RSA-2048. The wire bytes the Kotlin
//! returns are already in their natural shape — DER for ECDSA,
//! 64 raw bytes for Ed25519, 256 raw bytes for RSA — and the
//! caller (`lfs_core::ssh::keystore_signer`) wraps via
//! `lfs_core::ssh::wire::*`. No SSH-wire knowledge lives here.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

use jni::objects::{JByteArray, JObject, JValue};
use jni::sys::jlong;
use tokio::sync::oneshot;

use super::jni_bootstrap;
use super::jni_helpers as h;

/// SSH algorithm discriminator the JNI bridge speaks. Stays
/// independent from `lfs_core` so the audit perimeter holds —
/// `lfs_os_security` does not pull `lfs_core` in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeystoreAlgo {
    /// ECDSA P-256 over `secp256r1`. StrongBox-eligible on devices
    /// with the `FEATURE_STRONGBOX_KEYSTORE` capability + API 28+.
    EcdsaP256,
    /// Ed25519. Available API 33+ only (KeyMint v2); StrongBox NOT
    /// guaranteed — the device may refuse with
    /// `StrongBoxUnavailableException` even when the feature flag
    /// is set.
    Ed25519,
    /// RSA-2048 PKCS#1 v1.5. Widest TEE compatibility (API 18+);
    /// StrongBox-eligible at 2048 only — 3072 / 4096 keys cannot
    /// land in StrongBox per the AOSP `KeyMint` rejection list.
    Rsa2048,
}

impl KeystoreAlgo {
    /// JCA `KeyPairGenerator` algorithm name.
    pub fn jca_keypair_algo(self) -> &'static str {
        match self {
            Self::EcdsaP256 => "EC",
            Self::Ed25519 => "Ed25519",
            Self::Rsa2048 => "RSA",
        }
    }

    /// JCA `Signature` algorithm name.
    pub fn jca_signature_algo(self) -> &'static str {
        match self {
            Self::EcdsaP256 => "SHA256withECDSA",
            Self::Ed25519 => "Ed25519",
            Self::Rsa2048 => "SHA256withRSA",
        }
    }
}

/// Result the JNI callback delivers back to Rust through the
/// pending map. Captures the structural state the
/// `BiometricPrompt` returned plus the raw signature bytes when
/// the prompt succeeded. Errors are mapped to typed reasons so
/// the caller routes lockout / cancellation / invalidated keys
/// distinctly.
#[derive(Debug, Clone)]
pub enum SignResult {
    /// Signature bytes ready — `Cipher`-equivalent shape: DER for
    /// ECDSA, 64 raw bytes for Ed25519, 256 raw bytes for RSA.
    Signed(Vec<u8>),
    /// `KeyPermanentlyInvalidatedException` fired — a new biometric
    /// got enrolled (or every biometric got removed) after the key
    /// landed in the AndroidKeyStore. The on-device key is gone;
    /// the user must re-generate + re-register the public key.
    Invalidated,
    /// `StrongBoxUnavailableException` from a sign-time fallback
    /// path — shouldn't happen after create-time probing succeeded,
    /// but the device may flip the flag on a firmware update.
    StrongBoxUnavailable,
    /// `UserNotAuthenticatedException` after the BiometricPrompt's
    /// auth window expired (`onAuthenticationError(7)` /
    /// `ERROR_LOCKOUT` typically). The user can retry — the prompt
    /// itself will route them to lockout cooldown if appropriate.
    UserNotAuthenticated,
    /// User dismissed the BiometricPrompt via the negative button
    /// or back press — `ERROR_NEGATIVE_BUTTON` / `ERROR_USER_CANCELED`.
    Cancelled,
    /// Catch-all for unexpected JVM exceptions / state mismatches.
    /// Carries the exception's `getMessage()` verbatim so the Dart
    /// connect dialog renders the underlying cause.
    Other(String),
}

type PendingMap = Mutex<HashMap<u64, oneshot::Sender<SignResult>>>;

static PENDING: OnceLock<PendingMap> = OnceLock::new();
static NEXT_REQ_ID: AtomicU64 = AtomicU64::new(1);

fn pending() -> &'static PendingMap {
    PENDING.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Probe whether StrongBox is reachable via
/// `PackageManager.hasSystemFeature(FEATURE_STRONGBOX_KEYSTORE)`.
/// Returns `false` on every non-Android target by virtue of the
/// module being cfg-gated. A `true` here is necessary but not
/// sufficient — the actual generate call may still surface
/// `StrongBoxUnavailableException` for the chosen algorithm /
/// key size (the canonical case: RSA-3072+ on StrongBox).
pub fn probe_strongbox() -> Result<bool, String> {
    h::with_env(|env| {
        let context = jni_bootstrap::app_context()
            .ok_or_else(|| "keystore: app context not bootstrapped".to_string())?;
        // PackageManager pm = context.getPackageManager();
        let pm = h::call_obj(
            env,
            context,
            "getPackageManager",
            "()Landroid/content/pm/PackageManager;",
            &[],
        )?;
        let feature = h::jstring(env, "android.hardware.strongbox_keystore")?;
        h::call_bool(
            env,
            &pm,
            "hasSystemFeature",
            "(Ljava/lang/String;)Z",
            &[(&feature).into()],
        )
    })
}

/// Generate a fresh AndroidKeyStore key under `alias`. Returns the
/// SSH wire-format public-key blob shape per the algorithm:
///
/// * ECDSA P-256 — `0x04 || X(32) || Y(32)` (65 bytes).
/// * Ed25519 — raw 32 bytes.
/// * RSA-2048 — DER `[len(e_be) || e_be || len(n_be) || n_be]`
///   shape the Kotlin side encodes; the caller unpacks back into
///   modulus + exponent and wraps via `encode_public_rsa`.
///
/// `actual_strongbox` reports whether StrongBox actually accepted
/// the request, so the caller can route the row's
/// `keystore_strongbox` column honestly.
///
/// When `request_strongbox = true` but the device refuses
/// `setIsStrongBoxBacked(true)` via `StrongBoxUnavailableException`,
/// the outcome is [`GenerateOutcome::StrongBoxUnavailable`] and NO
/// key was generated. The Dart wizard surfaces a confirmation
/// dialog asking the user to explicitly approve a TEE-backed key
/// instead — there is no silent downgrade.
pub async fn generate(
    alias: String,
    algo: KeystoreAlgo,
    request_strongbox: bool,
) -> Result<GenerateOutcome, String> {
    tokio::task::spawn_blocking(move || generate_blocking(&alias, algo, request_strongbox))
        .await
        .map_err(|e| format!("tokio join: {e}"))?
}

/// Outcome of [`generate`]. The StrongBox-unavailable arm is typed
/// so the Dart wizard can confirm-before-downgrade rather than
/// silently accept a weaker TEE-backed key.
#[derive(Debug, Clone)]
pub enum GenerateOutcome {
    /// Key was generated. Carries the public-key bytes + the actual
    /// StrongBox-acceptance outcome + capture-time platform string.
    Generated(GeneratedKey),
    /// `setIsStrongBoxBacked(true)` was requested and the device
    /// threw `StrongBoxUnavailableException`. No key landed in the
    /// AndroidKeyStore. The caller asks the user whether to retry
    /// with `request_strongbox = false`.
    StrongBoxUnavailable,
}

/// Public-key bytes + the actual StrongBox-acceptance outcome.
#[derive(Debug, Clone)]
pub struct GeneratedKey {
    /// SSH-wire-format public-key body. Caller wraps via
    /// `lfs_core::ssh::wire::{encode_public_ecdsa_p256,
    /// encode_public_ed25519, encode_public_rsa}` after splitting
    /// the RSA `e || n` envelope.
    pub public_bytes: Vec<u8>,
    /// `true` iff StrongBox actually accepted the request. The
    /// caller routes the row's `keystore_strongbox` column off
    /// this value — not the user's wizard toggle — so the badge
    /// label stays honest. When `request_strongbox = false`, this
    /// is always `false`.
    pub actual_strongbox: bool,
    /// Capture-time `Build.MODEL` + `Build.VERSION.RELEASE`,
    /// e.g. `"Pixel 8 (Android 14)"`. `None` when the JNI lookup
    /// failed (best-effort — generate still succeeds without it).
    pub platform: Option<String>,
}

fn generate_blocking(
    alias: &str,
    algo: KeystoreAlgo,
    request_strongbox: bool,
) -> Result<GenerateOutcome, String> {
    h::with_env(|env| {
        let alias_j = h::jstring(env, alias)?;
        let algo_tag = match algo {
            KeystoreAlgo::EcdsaP256 => "ecdsa-p256",
            KeystoreAlgo::Ed25519 => "ed25519",
            KeystoreAlgo::Rsa2048 => "rsa-2048",
        };
        let algo_j = h::jstring(env, algo_tag)?;
        // KeystoreSshSigner.generate(alias, algo, strongBox)
        let result_obj = h::call_static_obj(
            env,
            "com/llloooggg/letsflutssh/KeystoreSshSigner",
            "generate",
            "(Ljava/lang/String;Ljava/lang/String;Z)Lcom/llloooggg/letsflutssh/KeystoreSshSigner$GenerateResult;",
            &[
                (&alias_j).into(),
                (&algo_j).into(),
                JValue::Bool(request_strongbox),
            ],
        )?;
        let strongbox_unavailable = env
            .get_field(
                &result_obj,
                h::jni_name("strongBoxUnavailable"),
                h::field_sig("Z")?.field_signature(),
            )
            .and_then(|v| v.z())
            .map_err(|e| format!("jni: GenerateResult.strongBoxUnavailable: {e}"))?;
        if strongbox_unavailable {
            return Ok(GenerateOutcome::StrongBoxUnavailable);
        }
        let public_bytes_obj = env
            .get_field(
                &result_obj,
                h::jni_name("publicBytes"),
                h::field_sig("[B")?.field_signature(),
            )
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: GenerateResult.publicBytes: {e}"))?;
        let public_bytes = h::jbyte_array_to_bytes(env, &public_bytes_obj)?;
        let actual_strongbox = env
            .get_field(
                &result_obj,
                h::jni_name("actualStrongBox"),
                h::field_sig("Z")?.field_signature(),
            )
            .and_then(|v| v.z())
            .map_err(|e| format!("jni: GenerateResult.actualStrongBox: {e}"))?;
        // platform string may be null; tolerate.
        let platform_obj = env
            .get_field(
                &result_obj,
                h::jni_name("platform"),
                h::field_sig("Ljava/lang/String;")?.field_signature(),
            )
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: GenerateResult.platform: {e}"))?;
        let platform = if platform_obj.is_null() {
            None
        } else {
            h::jstring_to_string(env, platform_obj).ok()
        };
        Ok(GenerateOutcome::Generated(GeneratedKey {
            public_bytes,
            actual_strongbox,
            platform,
        }))
    })
}

/// Delete the AndroidKeyStore entry under `alias`. Best-effort —
/// a missing entry returns Ok per `KeyStore.deleteEntry`'s
/// `KeyStoreException` contract (we swallow that case at the
/// Kotlin layer to match the DB delete arm).
pub async fn delete(alias: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || delete_blocking(&alias))
        .await
        .map_err(|e| format!("tokio join: {e}"))?
}

fn delete_blocking(alias: &str) -> Result<(), String> {
    h::with_env(|env| {
        let alias_j = h::jstring(env, alias)?;
        let class = env
            .find_class(h::jni_name("com/llloooggg/letsflutssh/KeystoreSshSigner"))
            .map_err(|e| format!("jni: find_class KeystoreSshSigner: {e}"))?;
        env.call_static_method(
            &class,
            h::jni_name("delete"),
            h::method_sig("(Ljava/lang/String;)V")?.method_signature(),
            &[(&alias_j).into()],
        )
        .map(|_| ())
        .map_err(|e| format!("jni: KeystoreSshSigner.delete: {e}"))
    })
}

/// Sign `data` with the key under `alias` using `algo`. Fires
/// `BiometricPrompt.CryptoObject(Signature)` on the main thread;
/// the result rides back through the pending map.
pub async fn sign(alias: String, algo: KeystoreAlgo, data: Vec<u8>) -> SignResult {
    let (tx, rx) = oneshot::channel();
    let req_id = NEXT_REQ_ID.fetch_add(1, Ordering::Relaxed);
    pending()
        .lock()
        .unwrap_or_else(|p| p.into_inner())
        .insert(req_id, tx);

    let alias_owned = alias.clone();
    let data_owned = data.clone();
    if tokio::task::spawn_blocking(move || sign_blocking(req_id, &alias_owned, algo, &data_owned))
        .await
        .is_err()
    {
        pending()
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .remove(&req_id);
        return SignResult::Other("tokio join failed".into());
    }
    rx.await
        .unwrap_or_else(|_| SignResult::Other("pending channel dropped".into()))
}

fn sign_blocking(req_id: u64, alias: &str, algo: KeystoreAlgo, data: &[u8]) -> Result<(), String> {
    h::with_env(|env| {
        let alias_j = h::jstring(env, alias)?;
        let algo_tag = match algo {
            KeystoreAlgo::EcdsaP256 => "ecdsa-p256",
            KeystoreAlgo::Ed25519 => "ed25519",
            KeystoreAlgo::Rsa2048 => "rsa-2048",
        };
        let algo_j = h::jstring(env, algo_tag)?;
        let data_j: JByteArray<'_> = h::bytes_to_jbyte_array(env, data)?;
        let activity = jni_bootstrap::main_activity()
            .ok_or_else(|| "keystore: MainActivity not bootstrapped".to_string())?;
        let class = env
            .find_class(h::jni_name("com/llloooggg/letsflutssh/KeystoreSshSigner"))
            .map_err(|e| format!("jni: find_class KeystoreSshSigner: {e}"))?;
        let data_obj = JObject::from(data_j);
        env.call_static_method(
            &class,
            h::jni_name("sign"),
            h::method_sig("(Landroidx/fragment/app/FragmentActivity;Ljava/lang/String;Ljava/lang/String;[BJ)V")?.method_signature(),
            &[
                activity.as_obj().into(),
                (&alias_j).into(),
                (&algo_j).into(),
                (&data_obj).into(),
                JValue::Long(req_id as jlong),
            ],
        )
        .map(|_| ())
        .map_err(|e| format!("jni: KeystoreSshSigner.sign: {e}"))
    })
    .inspect_err(|_e| {
        if let Ok(mut map) = pending().lock() {
            map.remove(&req_id);
        }
    })
}

fn deliver(req_id: u64, result: SignResult) {
    if let Ok(mut map) = pending().lock() {
        if let Some(tx) = map.remove(&req_id) {
            let _ = tx.send(result);
        }
    }
}

/// Bridge into Kotlin → Rust on a successful sign. Bytes ride
/// through verbatim — the caller wraps them per the algorithm.
///
/// # Safety
///
/// Invoked by the JVM through JNI when `LfsKeystoreSignCallback`
/// fires `onSigned`. The JVM guarantees argument types match the
/// registered native signature.
#[no_mangle]
pub unsafe extern "system" fn Java_com_llloooggg_letsflutssh_LfsKeystoreSignCallback_nativeOnSigned<
    'local,
>(
    mut env: jni::EnvUnowned<'local>,
    _class: jni::objects::JClass<'local>,
    req_id: jlong,
    signature: jni::objects::JByteArray<'local>,
) {
    env.with_env(|env| -> Result<(), jni::errors::Error> {
        let signature_obj = jni::objects::JObject::from(signature);
        match h::jbyte_array_to_bytes(env, &signature_obj) {
            Ok(bytes) => deliver(req_id as u64, SignResult::Signed(bytes)),
            Err(_) => deliver(
                req_id as u64,
                SignResult::Other("invalid signature array".into()),
            ),
        }
        Ok(())
    })
    .resolve::<jni::errors::LogErrorAndDefault>();
}

/// Bridge into Kotlin → Rust on a failed sign. The Kotlin side
/// maps the thrown JVM exception to a reason tag.
///
/// # Safety
///
/// Invoked by the JVM through JNI when `LfsKeystoreSignCallback`
/// fires `onFailed`.
#[no_mangle]
pub unsafe extern "system" fn Java_com_llloooggg_letsflutssh_LfsKeystoreSignCallback_nativeOnFailed<
    'local,
>(
    mut env: jni::EnvUnowned<'local>,
    _class: jni::objects::JClass<'local>,
    req_id: jlong,
    reason_tag: jni::objects::JString<'local>,
    detail: jni::objects::JString<'local>,
) {
    env.with_env(|env| -> Result<(), jni::errors::Error> {
        let tag = reason_tag
            .try_to_string(env)
            .unwrap_or_else(|_| "other".to_string());
        let detail_str = detail.try_to_string(env).unwrap_or_default();
        let result = match tag.as_str() {
            "invalidated" => SignResult::Invalidated,
            "strongbox-unavailable" => SignResult::StrongBoxUnavailable,
            "user-not-authenticated" => SignResult::UserNotAuthenticated,
            "cancelled" => SignResult::Cancelled,
            _ => SignResult::Other(detail_str),
        };
        deliver(req_id as u64, result);
        Ok(())
    })
    .resolve::<jni::errors::LogErrorAndDefault>();
}
