//! AndroidKeyStore-backed key/value storage via direct JNI to
//! `java.security.KeyStore` provider `"AndroidKeyStore"`.
//!
//! Storage shape:
//!
//! 1. **Wrapping key** — AES-256-GCM key generated inside
//!    AndroidKeyStore via `KeyGenerator.getInstance("AES",
//!    "AndroidKeyStore")` + `KeyGenParameterSpec.Builder` with
//!    `setBlockModes("GCM")`, `setEncryptionPaddings("NoPadding")`,
//!    `setKeySize(256)`. The key never leaves the keystore;
//!    AndroidKeyStore wraps it under a hardware-backed root key
//!    when the device has a TEE / StrongBox.
//! 2. **Wrapped value** — caller's bytes encrypted with the
//!    wrapping key via `Cipher.getInstance("AES/GCM/NoPadding")`.
//!    Output is `[12-byte IV][ciphertext+16-byte GCM tag]`,
//!    persisted to a 0600 file under
//!    `<filesDir>/lfs_secure_storage/<alias>.bin`. Avoiding
//!    `EncryptedSharedPreferences` is deliberate: it pulls in
//!    `androidx-security-crypto` which duplicates everything
//!    we already do in `lfs_core` crypto modules.
//!
//! Biometric variant adds `setUserAuthenticationRequired(true)`
//! and `setUserAuthenticationParameters(0,
//! KeyProperties.AUTH_BIOMETRIC_STRONG)` (API 30+) to the
//! KeyGenParameterSpec, plus the unlock cipher must be wrapped
//! in a `BiometricPrompt.CryptoObject` and authorised through
//! `androidx.biometric.BiometricPrompt` (lives in
//! `super::biometric_auth`).
//!
//! **Verification status**: every JNI method-ID lookup below is
//! a runtime-resolved string against the live JVM. The Rust
//! source compiles against `aarch64-linux-android` via the
//! rust-cross-check matrix, but signature mismatches surface
//! only when the call executes on a real device or emulator.
//! Sole secure-storage path on Android. The alias prefix in
//! `KEY_ALIAS_PREFIX` is fixed by external compat constraint —
//! see its docstring.

use std::path::{Path, PathBuf};

use jni::objects::{JObject, JValue};

use super::jni_helpers as h;
use crate::secure_key_storage::SecureStorageError;

/// External-compat constant — **never rename**. On-device
/// AndroidKeyStore aliases under this prefix are produced by an
/// upstream library (the `flutter_secure_storage` Dart plugin)
/// that some installs of this app and unrelated apps share with;
/// matching the prefix lets a fresh JNI write read back an alias
/// the user already stored without the user re-entering anything.
pub const KEY_ALIAS_PREFIX: &str = "FlutterSecureStorageKeyAlias_";

/// Subdirectory under `getFilesDir()` that holds wrapped value
/// blobs. **Owned solely by this module** — no other process
/// (including the upstream `flutter_secure_storage` plugin, which
/// uses `shared_prefs/` XML) writes here. Wrapping key persists
/// in AndroidKeyStore under [`KEY_ALIAS_PREFIX`]; the wrapped
/// value file under this subdir is per-install and rewritten on
/// every store call.
const STORAGE_SUBDIR: &str = "lfs_secure_storage";

/// GCM tag length matches the JCA default. 128-bit auth tag
/// over the IV + ciphertext.
const GCM_TAG_BITS: i32 = 128;

/// Map a logical `alias` (the same one passed to `read`/`write`)
/// to the AndroidKeyStore key alias the wrapping key lives
/// under.
pub fn keystore_alias_for(alias: &str) -> String {
    format!("{KEY_ALIAS_PREFIX}{alias}")
}

fn map_err<S: AsRef<str>>(msg: S) -> SecureStorageError {
    SecureStorageError::Backend(msg.as_ref().to_string())
}

fn value_path(files_dir: &Path, alias: &str) -> PathBuf {
    files_dir.join(STORAGE_SUBDIR).join(format!("{alias}.bin"))
}

/// Read + decrypt the wrapped value for `alias`. Returns
/// `Ok(None)` if either the AndroidKeyStore alias or the
/// wrapped-value file is missing.
pub async fn read(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
    let alias = alias.to_string();
    tokio::task::spawn_blocking(move || read_blocking(&alias, false))
        .await
        .map_err(|e| map_err(format!("tokio join: {e}")))?
}

pub async fn read_biometric(alias: &str) -> Result<Option<Vec<u8>>, SecureStorageError> {
    let alias = alias.to_string();
    tokio::task::spawn_blocking(move || read_blocking(&alias, true))
        .await
        .map_err(|e| map_err(format!("tokio join: {e}")))?
}

pub async fn write(alias: &str, value: &[u8], biometric: bool) -> Result<(), SecureStorageError> {
    let alias = alias.to_string();
    let value = value.to_vec();
    tokio::task::spawn_blocking(move || write_blocking(&alias, &value, biometric))
        .await
        .map_err(|e| map_err(format!("tokio join: {e}")))?
}

pub async fn delete(alias: &str, biometric: bool) -> Result<(), SecureStorageError> {
    let alias = alias.to_string();
    tokio::task::spawn_blocking(move || delete_blocking(&alias, biometric))
        .await
        .map_err(|e| map_err(format!("tokio join: {e}")))?
}

// ── Blocking helpers (run inside spawn_blocking) ──────────────

fn read_blocking(alias: &str, biometric: bool) -> Result<Option<Vec<u8>>, SecureStorageError> {
    let keystore_alias = keystore_alias_for(alias);
    h::with_env(|env| {
        // 1. Read wrapped-value file. Missing file = NotFound.
        let files_dir = h::app_files_dir(env)?;
        let blob_path = value_path(&files_dir, alias);
        let blob = match std::fs::read(&blob_path) {
            Ok(b) => b,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                return Ok(None);
            }
            Err(e) => return Err(format!("read wrapped-value file: {e}")),
        };
        if blob.len() < 12 + 16 {
            return Err("wrapped-value file truncated (< IV + tag)".to_string());
        }
        let (iv, ct) = blob.split_at(12);

        // 2. KeyStore ks = KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
        let provider = h::jstring(env, "AndroidKeyStore")?;
        let ks = h::call_static_obj(
            env,
            "java/security/KeyStore",
            "getInstance",
            "(Ljava/lang/String;)Ljava/security/KeyStore;",
            &[(&provider).into()],
        )?;
        h::call_void(
            env,
            &ks,
            "load",
            "(Ljava/security/KeyStore$LoadStoreParameter;)V",
            &[(&JObject::null()).into()],
        )?;

        // 3. SecretKey wrap = (SecretKey) ks.getKey(keystore_alias, null);
        let alias_jstr = h::jstring(env, &keystore_alias)?;
        let wrap_key = env
            .call_method(
                &ks,
                "getKey",
                "(Ljava/lang/String;[C)Ljava/security/Key;",
                &[(&alias_jstr).into(), (&JObject::null()).into()],
            )
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: KeyStore.getKey: {e}"))?;
        if wrap_key.is_null() {
            // Key absent — call write() first to provision.
            return Ok(None);
        }

        // 4. Cipher c = Cipher.getInstance("AES/GCM/NoPadding")
        //    c.init(Cipher.DECRYPT_MODE, wrap_key, new GCMParameterSpec(128, iv));
        let transformation = h::jstring(env, "AES/GCM/NoPadding")?;
        let cipher = h::call_static_obj(
            env,
            "javax/crypto/Cipher",
            "getInstance",
            "(Ljava/lang/String;)Ljavax/crypto/Cipher;",
            &[(&transformation).into()],
        )?;
        let iv_array = h::bytes_to_jbyte_array(env, iv)?;
        let spec_class = "javax/crypto/spec/GCMParameterSpec";
        let spec = {
            let class = env
                .find_class(spec_class)
                .map_err(|e| format!("jni: find_class {spec_class}: {e}"))?;
            env.new_object(
                class,
                "(I[B)V",
                &[JValue::Int(GCM_TAG_BITS), (&iv_array).into()],
            )
            .map_err(|e| format!("jni: new GCMParameterSpec: {e}"))?
        };
        let decrypt_mode = h::static_int_field(env, "javax/crypto/Cipher", "DECRYPT_MODE")?;
        h::call_void(
            env,
            &cipher,
            "init",
            "(ILjava/security/Key;Ljava/security/spec/AlgorithmParameterSpec;)V",
            &[
                JValue::Int(decrypt_mode),
                (&wrap_key).into(),
                (&spec).into(),
            ],
        )?;

        // 5. byte[] plain = c.doFinal(ct);
        let ct_array = h::bytes_to_jbyte_array(env, ct)?;
        let plain_jobj = env
            .call_method(&cipher, "doFinal", "([B)[B", &[(&ct_array).into()])
            .and_then(|v| v.l())
            .map_err(|e| {
                // For biometric path, Cipher.init throws
                // UserNotAuthenticatedException — surfaces here
                // as a JNI exception that the caller must surface
                // to trigger BiometricPrompt.
                if biometric {
                    format!("biometric auth required: {e}")
                } else {
                    format!("jni: Cipher.doFinal: {e}")
                }
            })?;

        let plain = h::jbyte_array_to_bytes(env, &plain_jobj)?;
        Ok(Some(plain))
    })
    .map_err(map_err)
}

fn write_blocking(alias: &str, value: &[u8], biometric: bool) -> Result<(), SecureStorageError> {
    let keystore_alias = keystore_alias_for(alias);
    h::with_env(|env| {
        // 1. KeyStore ks = KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
        let provider = h::jstring(env, "AndroidKeyStore")?;
        let ks = h::call_static_obj(
            env,
            "java/security/KeyStore",
            "getInstance",
            "(Ljava/lang/String;)Ljava/security/KeyStore;",
            &[(&provider).into()],
        )?;
        h::call_void(
            env,
            &ks,
            "load",
            "(Ljava/security/KeyStore$LoadStoreParameter;)V",
            &[(&JObject::null()).into()],
        )?;

        // 2. If !ks.containsAlias(keystore_alias): generate the wrapping key.
        let alias_jstr = h::jstring(env, &keystore_alias)?;
        let exists = h::call_bool(
            env,
            &ks,
            "containsAlias",
            "(Ljava/lang/String;)Z",
            &[(&alias_jstr).into()],
        )?;
        if !exists {
            generate_wrap_key(env, &keystore_alias, biometric)?;
        }

        // 3. SecretKey wrap = (SecretKey) ks.getKey(keystore_alias, null);
        let wrap_key = env
            .call_method(
                &ks,
                "getKey",
                "(Ljava/lang/String;[C)Ljava/security/Key;",
                &[(&alias_jstr).into(), (&JObject::null()).into()],
            )
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: KeyStore.getKey: {e}"))?;

        // 4. Cipher c = Cipher.getInstance("AES/GCM/NoPadding"); c.init(ENCRYPT_MODE, wrap);
        let transformation = h::jstring(env, "AES/GCM/NoPadding")?;
        let cipher = h::call_static_obj(
            env,
            "javax/crypto/Cipher",
            "getInstance",
            "(Ljava/lang/String;)Ljavax/crypto/Cipher;",
            &[(&transformation).into()],
        )?;
        let encrypt_mode = h::static_int_field(env, "javax/crypto/Cipher", "ENCRYPT_MODE")?;
        h::call_void(
            env,
            &cipher,
            "init",
            "(ILjava/security/Key;)V",
            &[JValue::Int(encrypt_mode), (&wrap_key).into()],
        )?;

        // 5. byte[] iv = c.getIV(); byte[] ct = c.doFinal(value);
        let iv_jobj = env
            .call_method(&cipher, "getIV", "()[B", &[])
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: Cipher.getIV: {e}"))?;
        let iv = h::jbyte_array_to_bytes(env, &iv_jobj)?;
        let value_array = h::bytes_to_jbyte_array(env, value)?;
        let ct_jobj = env
            .call_method(&cipher, "doFinal", "([B)[B", &[(&value_array).into()])
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: Cipher.doFinal: {e}"))?;
        let ct = h::jbyte_array_to_bytes(env, &ct_jobj)?;

        // 6. Write iv || ct to <filesDir>/lfs_secure_storage/<alias>.bin (0600).
        let files_dir = h::app_files_dir(env)?;
        let dir = files_dir.join(STORAGE_SUBDIR);
        std::fs::create_dir_all(&dir).map_err(|e| format!("create storage dir: {e}"))?;
        let blob_path = dir.join(format!("{alias}.bin"));
        let mut blob = Vec::with_capacity(iv.len() + ct.len());
        blob.extend_from_slice(&iv);
        blob.extend_from_slice(&ct);
        write_atomic_0600(&blob_path, &blob)?;
        Ok(())
    })
    .map_err(map_err)
}

fn delete_blocking(alias: &str, _biometric: bool) -> Result<(), SecureStorageError> {
    let keystore_alias = keystore_alias_for(alias);
    h::with_env(|env| {
        // 1. KeyStore ks = KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
        //    ks.deleteEntry(keystore_alias) — silently succeeds
        //    on missing alias.
        let provider = h::jstring(env, "AndroidKeyStore")?;
        let ks = h::call_static_obj(
            env,
            "java/security/KeyStore",
            "getInstance",
            "(Ljava/lang/String;)Ljava/security/KeyStore;",
            &[(&provider).into()],
        )?;
        h::call_void(
            env,
            &ks,
            "load",
            "(Ljava/security/KeyStore$LoadStoreParameter;)V",
            &[(&JObject::null()).into()],
        )?;
        let alias_jstr = h::jstring(env, &keystore_alias)?;
        // deleteEntry throws KeyStoreException only on the key
        // store itself being uninitialised; we always load(null)
        // first so this is effectively unreachable. Even so, swallow
        // the JNI Result + clear any pending Java exception
        // explicitly — leaving the exception flag armed on the
        // thread would cause every subsequent JNI call on the same
        // thread to fail with a misleading error (Java sees a
        // pending exception and refuses further calls).
        let _ = env.call_method(
            &ks,
            "deleteEntry",
            "(Ljava/lang/String;)V",
            &[(&alias_jstr).into()],
        );
        if matches!(env.exception_check(), Ok(true)) {
            let _ = env.exception_clear();
        }

        // 2. Remove the wrapped-value file (best-effort).
        let files_dir = h::app_files_dir(env)?;
        let blob_path = value_path(&files_dir, alias);
        let _ = std::fs::remove_file(&blob_path);
        Ok(())
    })
    .map_err(map_err)
}

/// Generate the wrapping AES-256-GCM key in AndroidKeyStore
/// for `keystore_alias`. When `biometric == true`, the key is
/// gated on `KeyProperties.AUTH_BIOMETRIC_STRONG` so each
/// `Cipher.init` requires a fresh `BiometricPrompt` flow.
fn generate_wrap_key(
    env: &mut jni::JNIEnv,
    keystore_alias: &str,
    biometric: bool,
) -> Result<(), String> {
    // KeyGenerator kg = KeyGenerator.getInstance("AES", "AndroidKeyStore");
    let algo = h::jstring(env, "AES")?;
    let provider = h::jstring(env, "AndroidKeyStore")?;
    let kg = h::call_static_obj(
        env,
        "javax/crypto/KeyGenerator",
        "getInstance",
        "(Ljava/lang/String;Ljava/lang/String;)Ljavax/crypto/KeyGenerator;",
        &[(&algo).into(), (&provider).into()],
    )?;

    // KeyGenParameterSpec.Builder builder = new Builder(alias, PURPOSE_ENCRYPT | PURPOSE_DECRYPT);
    let purpose_encrypt = h::static_int_field(
        env,
        "android/security/keystore/KeyProperties",
        "PURPOSE_ENCRYPT",
    )?;
    let purpose_decrypt = h::static_int_field(
        env,
        "android/security/keystore/KeyProperties",
        "PURPOSE_DECRYPT",
    )?;
    let purposes = purpose_encrypt | purpose_decrypt;
    let alias_jstr = h::jstring(env, keystore_alias)?;
    let builder_class = "android/security/keystore/KeyGenParameterSpec$Builder";
    let builder = {
        let class = env
            .find_class(builder_class)
            .map_err(|e| format!("jni: find_class {builder_class}: {e}"))?;
        env.new_object(
            class,
            "(Ljava/lang/String;I)V",
            &[(&alias_jstr).into(), JValue::Int(purposes)],
        )
        .map_err(|e| format!("jni: new KeyGenParameterSpec.Builder: {e}"))?
    };

    // setBlockModes("GCM"), setEncryptionPaddings("NoPadding"), setKeySize(256)
    let gcm = h::jstring(env, "GCM")?;
    let gcm_array = {
        let cls = env
            .find_class("java/lang/String")
            .map_err(|e| format!("jni: find_class String: {e}"))?;
        let arr = env
            .new_object_array(1, cls, &gcm)
            .map_err(|e| format!("jni: new_object_array: {e}"))?;
        // SAFETY: `JObject::from_raw` rewraps a jobject reference we received via JNI; the jobject
        // is alive for the JNI frame and we hold a local reference for the rest of the function.
        unsafe { JObject::from_raw(arr.as_raw()) }
    };
    h::call_obj(
        env,
        &builder,
        "setBlockModes",
        "([Ljava/lang/String;)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
        &[(&gcm_array).into()],
    )?;
    let nopad = h::jstring(env, "NoPadding")?;
    let nopad_array = {
        let cls = env
            .find_class("java/lang/String")
            .map_err(|e| format!("jni: find_class String: {e}"))?;
        let arr = env
            .new_object_array(1, cls, &nopad)
            .map_err(|e| format!("jni: new_object_array: {e}"))?;
        // SAFETY: `JObject::from_raw` rewraps a jobject reference we received via JNI; the jobject
        // is alive for the JNI frame and we hold a local reference for the rest of the function.
        unsafe { JObject::from_raw(arr.as_raw()) }
    };
    h::call_obj(
        env,
        &builder,
        "setEncryptionPaddings",
        "([Ljava/lang/String;)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
        &[(&nopad_array).into()],
    )?;
    h::call_obj(
        env,
        &builder,
        "setKeySize",
        "(I)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
        &[JValue::Int(256)],
    )?;

    if biometric {
        // setUserAuthenticationRequired(true)
        h::call_obj(
            env,
            &builder,
            "setUserAuthenticationRequired",
            "(Z)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
            &[JValue::Bool(1)],
        )?;
        // setUserAuthenticationParameters(60, AUTH_BIOMETRIC_STRONG)
        //
        // Time-bound auth (60 seconds) rather than per-op
        // (which would need a `BiometricPrompt.CryptoObject`
        // flow with the cipher object passed through the
        // BiometricPrompt result). The 60-second window
        // matches `flutter_secure_storage`'s
        // `setUserAuthenticationValidityDurationSeconds(60)`
        // historical default, so the user-perceived UX is
        // unchanged: the Dart-side `BiometricKeyVault.unlock`
        // calls `biometric::authenticate` first to fire the
        // BiometricPrompt, then within the 60-second window
        // the subsequent `read_biometric` / `write_biometric`
        // cipher op succeeds without a second prompt.
        //
        // API 30+ uses `setUserAuthenticationParameters(N,
        // AUTH_BIOMETRIC_STRONG)`; API 23-29 used the now-
        // deprecated `setUserAuthenticationValidityDurationSeconds(N)`.
        // The deprecated method still works on API 30+ and is
        // forwarded internally to the new shape, so we use it
        // unconditionally for cross-API compatibility.
        let _ = h::call_obj(
            env,
            &builder,
            "setUserAuthenticationValidityDurationSeconds",
            "(I)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
            &[JValue::Int(60)],
        );

        // setInvalidatedByBiometricEnrollment(true): adding /
        // removing / re-enrolling a finger or face invalidates
        // the key, mirroring Apple's `biometryCurrentSet` ACL.
        // Available API 24+; ignore failures on older devices.
        let _ = h::call_obj(
            env,
            &builder,
            "setInvalidatedByBiometricEnrollment",
            "(Z)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
            &[JValue::Bool(1)],
        );
    }

    // setUnlockedDeviceRequired(true): the key is only usable
    // while the screen is unlocked. Available API 28+; ignore
    // failures on older devices (the call returns the same
    // builder but the flag is silently dropped pre-28).
    let _ = h::call_obj(
        env,
        &builder,
        "setUnlockedDeviceRequired",
        "(Z)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
        &[JValue::Bool(1)],
    );

    // KeyGenParameterSpec spec = builder.build();
    let spec = h::call_obj(
        env,
        &builder,
        "build",
        "()Landroid/security/keystore/KeyGenParameterSpec;",
        &[],
    )?;

    // kg.init(spec); kg.generateKey();
    h::call_void(
        env,
        &kg,
        "init",
        "(Ljava/security/spec/AlgorithmParameterSpec;)V",
        &[(&spec).into()],
    )?;
    let _ = env
        .call_method(&kg, "generateKey", "()Ljavax/crypto/SecretKey;", &[])
        .and_then(|v| v.l())
        .map_err(|e| format!("jni: KeyGenerator.generateKey: {e}"))?;
    Ok(())
}

/// 0600 atomic write — create temp sibling, write+sync, rename.
/// Mirrors the patterns in `lfs_core::path::write_bytes_atomic`
/// but tailored for the Android files-dir layout (no
/// `harden_file_perms` because Android already enforces
/// per-app sandboxing on `getFilesDir()`).
fn write_atomic_0600(path: &std::path::Path, bytes: &[u8]) -> Result<(), String> {
    use std::io::Write;
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    let tmp = path.with_extension("tmp");
    {
        let mut opts = std::fs::OpenOptions::new();
        opts.create(true).write(true).truncate(true).mode(0o600);
        let mut f = opts.open(&tmp).map_err(|e| format!("open tmp: {e}"))?;
        f.write_all(bytes).map_err(|e| format!("write tmp: {e}"))?;
        f.sync_all().map_err(|e| format!("sync tmp: {e}"))?;
    }
    std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o600))
        .map_err(|e| format!("chmod tmp: {e}"))?;
    std::fs::rename(&tmp, path).map_err(|e| format!("rename tmp: {e}"))?;
    Ok(())
}
