package com.llloooggg.letsflutssh

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.security.keystore.UserNotAuthenticatedException
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.util.Log
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.interfaces.RSAPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.RSAKeyGenParameterSpec

/**
 * Static helper bridging the Rust `lfs_os_security::android::keystore_signer`
 * module to `java.security.KeyStore` provider `"AndroidKeyStore"` +
 * `androidx.biometric.BiometricPrompt`. Mirrors the
 * `LfsBiometricCallback` adapter shape one file over — no business
 * logic lives here, only the JCA / BiometricPrompt plumbing that
 * cannot be reached from pure JNI without reflection-heavy hooks
 * for the `BiometricPrompt.AuthenticationCallback` abstract class.
 *
 * Three entry points:
 *
 * * `generate(alias, algo, strongBox)` — creates a fresh
 *   AndroidKeyStore key under `alias`, honouring StrongBox when the
 *   device has it and the algorithm allows it. Returns the
 *   public-key bytes in the per-algorithm shape the Rust caller
 *   wraps via `lfs_core::ssh::wire::*`.
 * * `sign(activity, alias, algo, data, reqId)` — initialises a
 *   `Signature` over the alias's private half, wraps it in a
 *   `BiometricPrompt.CryptoObject`, and fires the prompt; the
 *   `LfsKeystoreSignCallback` adapter feeds the result back to Rust
 *   through `nativeOnSigned` / `nativeOnFailed`.
 * * `delete(alias)` — removes the AndroidKeyStore entry. Swallows
 *   missing-alias errors so the caller can run the DB delete + the
 *   keystore delete in either order.
 */
object KeystoreSshSigner {
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val TAG = "KeystoreSshSigner"

    /**
     * Result envelope returned by `generate()`. Carries the
     * SSH-wire-format public-key body (algorithm-specific shape) +
     * the actual StrongBox-acceptance outcome + capture-time platform
     * metadata. Field names + JNI signatures match the Rust JNI side
     * (`crates/lfs_os_security/src/android/keystore_signer.rs`).
     *
     * `strongBoxUnavailable = true` signals that the device refused
     * `setIsStrongBoxBacked(true)` via `StrongBoxUnavailableException`
     * and NO key was generated; `publicBytes` is empty and
     * `actualStrongBox` is `false`. The Rust caller routes this to
     * a typed `StrongBoxUnavailable` outcome and the Dart wizard
     * prompts the user to explicitly accept a TEE-backed key. The
     * downgrade is never automatic — the user must approve it.
     */
    class GenerateResult(
        @JvmField val publicBytes: ByteArray,
        @JvmField val actualStrongBox: Boolean,
        @JvmField val platform: String?,
        @JvmField val strongBoxUnavailable: Boolean,
    )

    @JvmStatic
    fun generate(alias: String, algoTag: String, strongBoxRequested: Boolean): GenerateResult {
        // The Rust side already gated on
        // `PackageManager.hasSystemFeature(FEATURE_STRONGBOX_KEYSTORE)`
        // before sending us `strongBoxRequested = true`; the device
        // may still flip on us between probe + generate (firmware
        // update, GPO change). A refusal is surfaced as a typed
        // `strongBoxUnavailable` signal — we do NOT silently retry
        // without StrongBox. The Dart wizard owns the
        // downgrade-to-TEE decision.
        val wantStrongBox = strongBoxRequested

        val keyAlgo = when (algoTag) {
            "ecdsa-p256" -> KeyProperties.KEY_ALGORITHM_EC
            "ed25519" -> "Ed25519"
            "rsa-2048" -> KeyProperties.KEY_ALGORITHM_RSA
            else -> throw IllegalArgumentException("unknown algo $algoTag")
        }
        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
        )
        when (algoTag) {
            "ecdsa-p256" -> {
                builder.setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                builder.setDigests(KeyProperties.DIGEST_SHA256)
            }
            "ed25519" -> {
                builder.setAlgorithmParameterSpec(ECGenParameterSpec("ed25519"))
                // Ed25519 signs over the raw message; no digest spec.
            }
            "rsa-2048" -> {
                builder.setAlgorithmParameterSpec(RSAKeyGenParameterSpec(2048, RSAKeyGenParameterSpec.F4))
                builder.setDigests(KeyProperties.DIGEST_SHA256)
                builder.setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
            }
        }
        builder.setUserAuthenticationRequired(true)
        // Per-op auth on API 30+; deprecated time-bounded fallback on
        // API 23-29. `setUserAuthenticationParameters(0, …)` requests
        // a fresh prompt on every sign — the load-bearing shape that
        // makes BiometricPrompt.CryptoObject the only way to sign.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(0)
        }
        builder.setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setUnlockedDeviceRequired(true)
        }
        if (wantStrongBox) {
            builder.setIsStrongBoxBacked(true)
        }

        val spec = builder.build()
        val actualStrongBox = wantStrongBox
        val kpg = KeyPairGenerator.getInstance(keyAlgo, ANDROID_KEYSTORE)

        // Trap: re-using an alias across different keystore specs
        // (TEE <-> StrongBox) without an explicit delete leaves the
        // PREVIOUSLY spec'd key on the chip — KeyPairGenerator.initialize
        // is rejected as "alias exists", and any later `KeyStore.getEntry`
        // returns the OLD entry. That silently violates the downgrade
        // consent the user just gave (e.g. cancelled StrongBox -> TEE).
        // Invariant: every `generate(alias=X, ...)` call owns the alias
        // outright; if X already lives in the keystore, purge it before
        // minting the new key so the spec the caller asked for is the
        // spec that lands on disk.
        val purgeKs = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        if (purgeKs.containsAlias(alias)) {
            val tier = if (wantStrongBox) "StrongBox" else "TEE"
            Log.d(TAG, "alias $alias already present; deleting before regenerate (new tier=$tier)")
            try {
                purgeKs.deleteEntry(alias)
            } catch (e: Throwable) {
                throw IllegalStateException(
                    "AndroidKeyStore: failed to purge prior alias $alias before regenerate: ${e.message}",
                    e,
                )
            }
        }

        try {
            kpg.initialize(spec)
            kpg.generateKeyPair()
        } catch (_: StrongBoxUnavailableException) {
            // Caller (Dart wizard via Rust) decides whether to retry
            // with `strongBoxRequested = false`. No automatic downgrade.
            return GenerateResult(ByteArray(0), false, null, true)
        }

        // Re-fetch the public half via the KeyStore so we get the
        // canonical shape (the KeyPair `getPublic()` route works too
        // but going via `KeyStore.getCertificate(alias).publicKey`
        // matches what the sign path will see).
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val cert = ks.getCertificate(alias)
            ?: throw IllegalStateException("AndroidKeyStore: $alias missing after generate")
        val publicKey = cert.publicKey
        val publicBytes = when (algoTag) {
            "ecdsa-p256" -> {
                val ec = publicKey as ECPublicKey
                val w = ec.w
                val x = bigIntToFixedWidth(w.affineX.toByteArray(), 32)
                val y = bigIntToFixedWidth(w.affineY.toByteArray(), 32)
                // 0x04 || X(32) || Y(32) — SSH-wire shape for ECDSA P-256.
                ByteArrayOutputStream(65).apply {
                    write(0x04)
                    write(x)
                    write(y)
                }.toByteArray()
            }
            "ed25519" -> {
                // BC-style Ed25519: `publicKey.encoded` is the X.509
                // SubjectPublicKeyInfo. The 32 raw bytes are the last
                // 32 of the encoded form. AOSP KeyMint v2 follows the
                // same shape.
                val encoded = publicKey.encoded
                encoded.copyOfRange(encoded.size - 32, encoded.size)
            }
            "rsa-2048" -> {
                val rsa = publicKey as RSAPublicKey
                val e = rsa.publicExponent.toByteArray()
                val n = rsa.modulus.toByteArray()
                // `[u32-BE len_e || e_be || u32-BE len_n || n_be]` —
                // the Rust caller unpacks back into mpints.
                val out = ByteArrayOutputStream(8 + e.size + n.size)
                out.write(ByteBuffer.allocate(4).putInt(e.size).array())
                out.write(e)
                out.write(ByteBuffer.allocate(4).putInt(n.size).array())
                out.write(n)
                out.toByteArray()
            }
            else -> throw IllegalArgumentException("unreachable: $algoTag")
        }

        val platform = "${Build.MODEL} (Android ${Build.VERSION.RELEASE})"
        return GenerateResult(publicBytes, actualStrongBox, platform, false)
    }

    /**
     * Strip leading zero pad / left-pad with zeros so the magnitude
     * lands at exactly `targetSize` bytes. Mirrors the SSH wire-format
     * helper one layer above; we duplicate it here so the Rust JNI
     * never needs to re-trim the public point.
     */
    private fun bigIntToFixedWidth(bytes: ByteArray, targetSize: Int): ByteArray {
        if (bytes.size == targetSize) return bytes
        if (bytes.size == targetSize + 1 && bytes[0] == 0.toByte()) {
            return bytes.copyOfRange(1, bytes.size)
        }
        if (bytes.size < targetSize) {
            val out = ByteArray(targetSize)
            System.arraycopy(bytes, 0, out, targetSize - bytes.size, bytes.size)
            return out
        }
        throw IllegalStateException(
            "EC component oversized: got ${bytes.size} bytes, expected $targetSize",
        )
    }

    @JvmStatic
    fun sign(
        activity: FragmentActivity,
        alias: String,
        algoTag: String,
        data: ByteArray,
        reqId: Long,
    ) {
        val sigAlgo = when (algoTag) {
            "ecdsa-p256" -> "SHA256withECDSA"
            "ed25519" -> "Ed25519"
            "rsa-2048" -> "SHA256withRSA"
            else -> {
                LfsKeystoreSignCallback.nativeOnFailedStatic(reqId, "other", "unknown algo $algoTag")
                return
            }
        }
        val ks = try {
            KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        } catch (e: Throwable) {
            LfsKeystoreSignCallback.nativeOnFailedStatic(reqId, "other", "keystore load: ${e.message}")
            return
        }
        val entry = try {
            ks.getEntry(alias, null) as? KeyStore.PrivateKeyEntry
        } catch (e: KeyPermanentlyInvalidatedException) {
            LfsKeystoreSignCallback.nativeOnFailedStatic(reqId, "invalidated", e.message ?: "")
            return
        } catch (e: Throwable) {
            LfsKeystoreSignCallback.nativeOnFailedStatic(reqId, "other", "getEntry: ${e.message}")
            return
        }
        if (entry == null) {
            LfsKeystoreSignCallback.nativeOnFailedStatic(reqId, "other", "alias $alias missing")
            return
        }
        val signature = try {
            Signature.getInstance(sigAlgo)
        } catch (e: Throwable) {
            LfsKeystoreSignCallback.nativeOnFailedStatic(reqId, "other", "Signature.getInstance: ${e.message}")
            return
        }
        try {
            signature.initSign(entry.privateKey)
        } catch (e: UserNotAuthenticatedException) {
            // Expected — the per-op auth contract throws this until
            // the BiometricPrompt rebinds the signature inside its
            // CryptoObject. Fall through to firing the prompt.
        } catch (e: KeyPermanentlyInvalidatedException) {
            LfsKeystoreSignCallback.nativeOnFailedStatic(reqId, "invalidated", e.message ?: "")
            return
        } catch (e: Throwable) {
            LfsKeystoreSignCallback.nativeOnFailedStatic(reqId, "other", "initSign: ${e.message}")
            return
        }

        val callback = LfsKeystoreSignCallback(reqId, data)
        val crypto = BiometricPrompt.CryptoObject(signature)
        val executor = ContextCompat.getMainExecutor(activity)
        val prompt = BiometricPrompt(activity, executor, callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Authenticate to use SSH key")
            .setSubtitle(alias)
            .setAllowedAuthenticators(androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .setNegativeButtonText("Cancel")
            .build()
        callback.dispatchAuthenticate(prompt, info, crypto)
    }

    @JvmStatic
    fun delete(alias: String) {
        try {
            val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            if (ks.containsAlias(alias)) {
                ks.deleteEntry(alias)
            }
        } catch (_: Throwable) {
            // Swallow — the caller pairs delete with a soft-delete on
            // the DB row; missing-on-chip is a tolerable outcome.
        }
    }
}
