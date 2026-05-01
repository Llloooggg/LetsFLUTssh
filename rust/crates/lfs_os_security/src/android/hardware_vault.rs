//! L3 hardware-tier vault Android backend — StrongBox-backed
//! AES-GCM wrapping key in AndroidKeyStore + PIN HMAC frame on
//! disk.
//!
//! Mirrors the public surface of
//! `lfs_os_security::hardware_tier_vault::apple` (sync, takes
//! `support_dir` + `db_key` + `pin_hmac` byte slices) so the
//! top-level dispatch can swap backends per `cfg(target_os)`
//! without API surface change.
//!
//! ## Key shape
//!
//! Wrapping key alias: `lfs.hardware_tier_vault.l3` — separate
//! from the `secure_key_storage` aliases so the L3 envelope is
//! distinguishable from per-credential entries.
//!
//! `KeyGenParameterSpec` includes:
//!
//! * `setBlockModes("GCM")`, `setEncryptionPaddings("NoPadding")`,
//!   `setKeySize(256)` — same as the secure-storage wrap.
//! * `setIsStrongBoxBacked(true)` (API 28+) — requests
//!   StrongBox-backed key storage. Falls back to TEE-backed
//!   silently on devices without StrongBox; the
//!   `StrongBoxUnavailableException` from `generateKey()` is
//!   caught and the fallback path retries without StrongBox.
//! * `setUserAuthenticationRequired(true)` is **not** set here
//!   — the L3 vault is unlocked by the PIN HMAC gate in our
//!   own code (constant-time HMAC compare before unwrap),
//!   matching the Apple SE flow that uses
//!   `kSecAccessControlPrivateKeyUsage` without
//!   `kSecAccessControlBiometryAny`.
//!
//! ## On-disk envelope
//!
//! `<support_dir>/hardware_vault_android.bin` holds:
//!
//! ```text
//! [u32 BE pin_hmac_len][pin_hmac][u32 BE iv_len][iv][u32 BE ct_len][ciphertext]
//! ```
//!
//! Three length-prefixed frames so a future-version envelope
//! can grow new fields without breaking the parser. Wrapped DB
//! key uses AES-GCM via the StrongBox-backed wrap key; PIN
//! HMAC is stored verbatim (constant-time compared on read).
//!
//! Biometric overlay (`hardware_vault_android_bio.bin`) holds
//! a separate `[u32 BE iv_len][iv][u32 BE ct_len][ciphertext]`
//! frame wrapped under a biometric-bound variant of the
//! wrapping key (alias `lfs.hardware_tier_vault.l3.bio`).
//!
//! ## Verification status
//!
//! Same NI-2 gate as the rest of the Android JNI surface.
//! StrongBox availability + `StrongBoxUnavailableException`
//! handling is the riskiest piece — needs validation on a
//! Pixel-class device for happy path and a non-StrongBox
//! device (most pre-2019 Android, low-end OEMs) for the
//! fallback path.

use std::path::PathBuf;

use jni::objects::{JObject, JValue};
use subtle::ConstantTimeEq;

use super::jni_helpers as h;
use crate::hardware_tier_vault::HardwareVaultError;

const VAULT_ALIAS: &str = "lfs.hardware_tier_vault.l3";
const VAULT_ALIAS_BIO: &str = "lfs.hardware_tier_vault.l3.bio";
const VAULT_FILE: &str = "hardware_vault_android.bin";
const VAULT_FILE_BIO: &str = "hardware_vault_android_bio.bin";
const GCM_TAG_BITS: i32 = 128;

fn map_err<S: AsRef<str>>(msg: S) -> HardwareVaultError {
    HardwareVaultError::Backend(msg.as_ref().to_string())
}

pub fn is_available() -> bool {
    // Probe by attempting to instantiate KeyStore "AndroidKeyStore".
    // If the JNI call fails (no JavaVM bootstrap, missing
    // BouncyCastle provider, etc.) the L3 tier is genuinely
    // unavailable on this device.
    h::with_env(|env| {
        let provider = h::jstring(env, "AndroidKeyStore")?;
        let _ks = h::call_static_obj(
            env,
            "java/security/KeyStore",
            "getInstance",
            "(Ljava/lang/String;)Ljava/security/KeyStore;",
            &[(&provider).into()],
        )?;
        Ok(())
    })
    .is_ok()
}

pub fn is_stored(support_dir: &str) -> bool {
    PathBuf::from(support_dir).join(VAULT_FILE).exists()
}

pub fn is_biometric_password_stored(support_dir: &str) -> bool {
    PathBuf::from(support_dir).join(VAULT_FILE_BIO).exists()
}

pub fn store(support_dir: &str, db_key: &[u8], pin_hmac: &[u8]) -> Result<(), HardwareVaultError> {
    let (iv, ct) = wrap(
        VAULT_ALIAS,
        db_key,
        /*biometric=*/ false,
        /*strongbox=*/ true,
    )
    .map_err(map_err)?;
    let blob = encode_pin_envelope(pin_hmac, &iv, &ct);
    let path = PathBuf::from(support_dir).join(VAULT_FILE);
    write_atomic_0600(&path, &blob).map_err(map_err)
}

pub fn read(support_dir: &str, pin_hmac: &[u8]) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    let path = PathBuf::from(support_dir).join(VAULT_FILE);
    let blob = match std::fs::read(&path) {
        Ok(b) => b,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(map_err(format!("read vault file: {e}"))),
    };
    let (stored_hmac, iv, ct) = decode_pin_envelope(&blob).map_err(map_err)?;
    // Constant-time compare on PIN HMAC — wrong PIN returns
    // None without invoking the keystore unwrap (matches the
    // Apple SE flow's gate).
    if stored_hmac.ct_eq(pin_hmac).unwrap_u8() != 1 {
        return Ok(None);
    }
    let plain = unwrap(VAULT_ALIAS, &iv, ct).map_err(map_err)?;
    Ok(Some(plain))
}

pub fn clear(support_dir: &str) -> Result<(), HardwareVaultError> {
    let path = PathBuf::from(support_dir).join(VAULT_FILE);
    let _ = std::fs::remove_file(&path);
    delete_keystore_alias(VAULT_ALIAS).map_err(map_err)?;
    // Also clear the biometric overlay if present — clearing
    // the L3 vault implies the user is fully resetting.
    let bio_path = PathBuf::from(support_dir).join(VAULT_FILE_BIO);
    let _ = std::fs::remove_file(&bio_path);
    delete_keystore_alias(VAULT_ALIAS_BIO).map_err(map_err)?;
    Ok(())
}

pub fn store_biometric_password(
    support_dir: &str,
    password_bytes: &[u8],
) -> Result<(), HardwareVaultError> {
    let (iv, ct) = wrap(
        VAULT_ALIAS_BIO,
        password_bytes,
        /*biometric=*/ true,
        /*strongbox=*/ true,
    )
    .map_err(map_err)?;
    let blob = encode_bio_envelope(&iv, &ct);
    let path = PathBuf::from(support_dir).join(VAULT_FILE_BIO);
    write_atomic_0600(&path, &blob).map_err(map_err)
}

pub fn read_biometric_password(support_dir: &str) -> Result<Option<Vec<u8>>, HardwareVaultError> {
    let path = PathBuf::from(support_dir).join(VAULT_FILE_BIO);
    let blob = match std::fs::read(&path) {
        Ok(b) => b,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(map_err(format!("read bio vault file: {e}"))),
    };
    let (iv, ct) = decode_bio_envelope(&blob).map_err(map_err)?;
    let plain = unwrap(VAULT_ALIAS_BIO, &iv, ct).map_err(map_err)?;
    Ok(Some(plain))
}

pub fn clear_biometric_password(support_dir: &str) -> Result<(), HardwareVaultError> {
    let path = PathBuf::from(support_dir).join(VAULT_FILE_BIO);
    let _ = std::fs::remove_file(&path);
    delete_keystore_alias(VAULT_ALIAS_BIO).map_err(map_err)?;
    Ok(())
}

// ── JNI guts (sync — caller already on a background thread) ──

/// Generate (if absent) + use the named wrap key to AES-GCM
/// encrypt `bytes`. Returns `(iv, ciphertext+tag)`.
fn wrap(
    alias: &str,
    bytes: &[u8],
    biometric: bool,
    strongbox: bool,
) -> Result<(Vec<u8>, Vec<u8>), String> {
    h::with_env(|env| {
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
        let alias_jstr = h::jstring(env, alias)?;
        let exists = h::call_bool(
            env,
            &ks,
            "containsAlias",
            "(Ljava/lang/String;)Z",
            &[(&alias_jstr).into()],
        )?;
        if !exists {
            generate_wrap_key(env, alias, biometric, strongbox)?;
        }
        let wrap_key = env
            .call_method(
                &ks,
                "getKey",
                "(Ljava/lang/String;[C)Ljava/security/Key;",
                &[(&alias_jstr).into(), (&JObject::null()).into()],
            )
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: KeyStore.getKey: {e}"))?;
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
        let iv_jobj = env
            .call_method(&cipher, "getIV", "()[B", &[])
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: Cipher.getIV: {e}"))?;
        let iv = h::jbyte_array_to_bytes(env, &iv_jobj)?;
        let value_array = h::bytes_to_jbyte_array(env, bytes)?;
        let ct_jobj = env
            .call_method(&cipher, "doFinal", "([B)[B", &[(&value_array).into()])
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: Cipher.doFinal: {e}"))?;
        let ct = h::jbyte_array_to_bytes(env, &ct_jobj)?;
        Ok((iv, ct))
    })
}

fn unwrap(alias: &str, iv: &[u8], ct: &[u8]) -> Result<Vec<u8>, String> {
    h::with_env(|env| {
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
        let alias_jstr = h::jstring(env, alias)?;
        let wrap_key = env
            .call_method(
                &ks,
                "getKey",
                "(Ljava/lang/String;[C)Ljava/security/Key;",
                &[(&alias_jstr).into(), (&JObject::null()).into()],
            )
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: KeyStore.getKey: {e}"))?;
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
        let ct_array = h::bytes_to_jbyte_array(env, ct)?;
        let plain_jobj = env
            .call_method(&cipher, "doFinal", "([B)[B", &[(&ct_array).into()])
            .and_then(|v| v.l())
            .map_err(|e| format!("jni: Cipher.doFinal: {e}"))?;
        h::jbyte_array_to_bytes(env, &plain_jobj)
    })
}

fn generate_wrap_key(
    env: &mut jni::JNIEnv,
    alias: &str,
    biometric: bool,
    strongbox: bool,
) -> Result<(), String> {
    let algo = h::jstring(env, "AES")?;
    let provider = h::jstring(env, "AndroidKeyStore")?;
    let kg = h::call_static_obj(
        env,
        "javax/crypto/KeyGenerator",
        "getInstance",
        "(Ljava/lang/String;Ljava/lang/String;)Ljavax/crypto/KeyGenerator;",
        &[(&algo).into(), (&provider).into()],
    )?;
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
    let alias_jstr = h::jstring(env, alias)?;
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
    let gcm = h::jstring(env, "GCM")?;
    let gcm_array = {
        let cls = env
            .find_class("java/lang/String")
            .map_err(|e| format!("jni: find_class String: {e}"))?;
        let arr = env
            .new_object_array(1, cls, &gcm)
            .map_err(|e| format!("jni: new_object_array: {e}"))?;
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
        h::call_obj(
            env,
            &builder,
            "setUserAuthenticationRequired",
            "(Z)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
            &[JValue::Bool(1)],
        )?;
        let _ = h::call_obj(
            env,
            &builder,
            "setUserAuthenticationValidityDurationSeconds",
            "(I)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
            &[JValue::Int(60)],
        );
    }
    if strongbox {
        // setIsStrongBoxBacked(true) — API 28+. On devices
        // without StrongBox this throws StrongBoxUnavailableException
        // at generateKey time; the catch path below retries
        // without StrongBox. The exception type is checked by
        // class name (no specific JNI helper) so a subtle
        // version difference in the exception class name would
        // skip the fallback — verify on hardware.
        let _ = h::call_obj(
            env,
            &builder,
            "setIsStrongBoxBacked",
            "(Z)Landroid/security/keystore/KeyGenParameterSpec$Builder;",
            &[JValue::Bool(1)],
        );
    }
    let spec = h::call_obj(
        env,
        &builder,
        "build",
        "()Landroid/security/keystore/KeyGenParameterSpec;",
        &[],
    )?;
    h::call_void(
        env,
        &kg,
        "init",
        "(Ljava/security/spec/AlgorithmParameterSpec;)V",
        &[(&spec).into()],
    )?;
    let gen_result = env
        .call_method(&kg, "generateKey", "()Ljavax/crypto/SecretKey;", &[])
        .and_then(|v| v.l());
    if let Err(e) = gen_result {
        // StrongBox unavailable — clear the JNI exception, drop
        // the StrongBox flag, regenerate via recursion.
        if env.exception_check().unwrap_or(false) {
            let _ = env.exception_clear();
        }
        if strongbox {
            return generate_wrap_key(env, alias, biometric, false);
        }
        return Err(format!("jni: KeyGenerator.generateKey: {e}"));
    }
    Ok(())
}

fn delete_keystore_alias(alias: &str) -> Result<(), String> {
    h::with_env(|env| {
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
        let alias_jstr = h::jstring(env, alias)?;
        let _ = env.call_method(
            &ks,
            "deleteEntry",
            "(Ljava/lang/String;)V",
            &[(&alias_jstr).into()],
        );
        Ok(())
    })
}

// ── On-disk envelope encode / decode ──────────────────────────

fn encode_pin_envelope(pin_hmac: &[u8], iv: &[u8], ct: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(12 + pin_hmac.len() + iv.len() + ct.len());
    out.extend_from_slice(&(pin_hmac.len() as u32).to_be_bytes());
    out.extend_from_slice(pin_hmac);
    out.extend_from_slice(&(iv.len() as u32).to_be_bytes());
    out.extend_from_slice(iv);
    out.extend_from_slice(&(ct.len() as u32).to_be_bytes());
    out.extend_from_slice(ct);
    out
}

fn decode_pin_envelope(buf: &[u8]) -> Result<(&[u8], Vec<u8>, &[u8]), String> {
    let (pin_hmac, rest) = read_frame(buf, "pin_hmac")?;
    let (iv, rest) = read_frame(rest, "iv")?;
    let (ct, _) = read_frame(rest, "ct")?;
    Ok((pin_hmac, iv.to_vec(), ct))
}

fn encode_bio_envelope(iv: &[u8], ct: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(8 + iv.len() + ct.len());
    out.extend_from_slice(&(iv.len() as u32).to_be_bytes());
    out.extend_from_slice(iv);
    out.extend_from_slice(&(ct.len() as u32).to_be_bytes());
    out.extend_from_slice(ct);
    out
}

fn decode_bio_envelope(buf: &[u8]) -> Result<(Vec<u8>, &[u8]), String> {
    let (iv, rest) = read_frame(buf, "iv")?;
    let (ct, _) = read_frame(rest, "ct")?;
    Ok((iv.to_vec(), ct))
}

fn read_frame<'a>(buf: &'a [u8], label: &'static str) -> Result<(&'a [u8], &'a [u8]), String> {
    if buf.len() < 4 {
        return Err(format!("envelope: missing {label} length prefix"));
    }
    let len = u32::from_be_bytes(buf[..4].try_into().unwrap()) as usize;
    let end = 4_usize
        .checked_add(len)
        .ok_or_else(|| format!("envelope: {label} length overflow"))?;
    if end > buf.len() {
        return Err(format!("envelope: {label} truncated"));
    }
    Ok((&buf[4..end], &buf[end..]))
}

fn write_atomic_0600(path: &std::path::Path, bytes: &[u8]) -> Result<(), String> {
    use std::io::Write;
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("mkdir parent: {e}"))?;
    }
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
