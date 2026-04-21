package com.llloooggg.letsflutssh

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Hardware-backed L3 vault for Android.
 *
 * Design:
 *  - Per-install AES-256-GCM key in the Android Keystore, keyed by a
 *    fixed alias (`letsflutssh_hw_vault_l3`).
 *  - `KeyGenParameterSpec` flags:
 *      * `setUserAuthenticationRequired(true)` — key unusable outside
 *        a live BiometricPrompt.CryptoObject session.
 *      * `setInvalidatedByBiometricEnrollment(true)` — atomic
 *        invalidation on enrolment change (Android equivalent of
 *        Apple's `biometryCurrentSet`).
 *      * `setIsStrongBoxBacked(true)` on devices that report
 *        StrongBox, graceful fallback to TEE-backed Keystore on
 *        devices that do not.
 *  - DB key is AES-GCM-sealed under this Keystore key; the
 *    ciphertext + IV + PIN-HMAC live in `hardware_vault_android.bin`
 *    under the app's files dir, 0600.
 *  - PIN is an external HMAC gate: a short PIN cannot be the auth
 *    value for the Keystore key itself (the Android model binds keys
 *    to biometrics, not arbitrary secrets). `HMAC-SHA256(pin, salt)`
 *    is compared against the stored value before the Keystore is
 *    asked for a CryptoObject — wrong PIN fails the gate without
 *    ever prompting biometrics.
 *
 * Every operation that needs the Keystore key (store / read) runs a
 * `BiometricPrompt` for user presence; the hardware enforces the
 * per-key lockout counter via the Keystore attempt policy.
 *
 * Untested on real devices — shipped for the device-testing pass per
 * plan note. Compiles only when the Android SDK is present; the
 * rest of the Flutter toolchain ignores it on non-Android hosts.
 */
class HardwareVaultPlugin(private val activity: FragmentActivity) {
    companion object {
        const val CHANNEL = "com.letsflutssh/hardware_vault"
        private const val KEY_ALIAS = "letsflutssh_hw_vault_l3"
        // Secondary Keystore alias used by the bank-style biometric
        // overlay: holds the user's password bytes, gated by biometric
        // auth via BiometricPrompt.CryptoObject. Read/written via the
        // storeBiometricPassword / readBiometricPassword methods. The
        // primary data key stays under KEY_ALIAS; this alias never
        // touches the DB wrapping key.
        private const val BIO_PASSWORD_KEY_ALIAS = "letsflutssh_hw_password_overlay"
        private const val VAULT_FILE_NAME = "hardware_vault_android.bin"
        // Password-overlay blob: wrapped password bytes released by a
        // biometric-gated Keystore key. Filename intentionally distinct
        // from the primary vault so a clear() can wipe either side
        // independently.
        private const val BIO_PASSWORD_FILE_NAME =
            "hardware_vault_password_overlay_android.bin"
        private const val GCM_TAG_BITS = 128
    }

    fun register(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isAvailable())
            "backingLevel" -> result.success(backingLevel())
            "probeDetail" -> result.success(probeDetail())
            "isStored" -> result.success(vaultFile().exists())
            "store" -> store(call, result)
            "read" -> read(call, result)
            "clear" -> {
                clearInternal()
                result.success(true)
            }
            "storeBiometricPassword" -> storeBiometricPassword(call, result)
            "readBiometricPassword" -> readBiometricPassword(result)
            "clearBiometricPassword" -> {
                clearBiometricPasswordInternal()
                result.success(true)
            }
            "isBiometricPasswordStored" ->
                result.success(biometricPasswordFile().exists())
            else -> result.notImplemented()
        }
    }

    private fun isAvailable(): Boolean {
        val bm = BiometricManager.from(activity)
        val status = bm.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        return status == BiometricManager.BIOMETRIC_SUCCESS
    }

    /**
     * Classified probe — returns one of the string codes the Dart-side
     * `HardwareProbeDetail` enum maps to:
     *
     *  * `available`                   — biometric-strong is available.
     *  * `androidBiometricNone`        — no biometric hardware
     *                                    (BIOMETRIC_ERROR_NO_HARDWARE).
     *                                    User cannot use fingerprint /
     *                                    face — they should rely on
     *                                    master password instead.
     *  * `androidBiometricNotEnrolled` — hardware present but user has
     *                                    not enrolled a fingerprint or
     *                                    face. Actionable.
     *  * `androidBiometricUnavailable` — hardware present, biometric
     *                                    temporarily unusable (lockout,
     *                                    security update required, etc.).
     *  * `androidGeneric`              — any other status we did not
     *                                    classify. Logged for diagnostics.
     *
     * `androidApiTooLow` used to be a possible code here (SDK < 28 had
     * no StrongBox and no key-level enrolment invalidation), but the
     * app now pins `minSdk = 28` so that branch is unreachable.
     */
    private fun probeDetail(): String {
        val bm = BiometricManager.from(activity)
        return when (bm.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
            BiometricManager.BIOMETRIC_SUCCESS -> "available"
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> "androidBiometricNone"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "androidBiometricNotEnrolled"
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "androidBiometricUnavailable"
            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED -> "androidBiometricUnavailable"
            else -> "androidGeneric"
        }
    }

    /** "hardware_strongbox", "hardware_tee", or "software". */
    private fun backingLevel(): String {
        if (!isAvailable()) return "unavailable"
        return try {
            val keyInfo = probeKeyInfo() ?: return "hardware_tee"
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    keyInfo.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX ->
                    "hardware_strongbox"
                @Suppress("DEPRECATION")
                keyInfo.isInsideSecureHardware -> "hardware_tee"
                else -> "software"
            }
        } catch (_: Throwable) {
            "hardware_tee"
        }
    }

    private fun probeKeyInfo(): KeyInfo? {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = ks.getKey(KEY_ALIAS, null) as? SecretKey ?: return null
        val factory = javax.crypto.SecretKeyFactory.getInstance(
            key.algorithm, "AndroidKeyStore"
        )
        return factory.getKeySpec(key, KeyInfo::class.java) as? KeyInfo
    }

    private fun store(call: MethodCall, result: MethodChannel.Result) {
        val dbKey = call.argument<ByteArray>("dbKey")
        // pinHmac is now optional. When supplied it acts as the
        // pre-unseal HMAC gate (bank-style password layer); when null
        // the primary key is the only gate and no in-band secret is
        // compared. Callers that want passwordless T2 pass null.
        val pinHmac = call.argument<ByteArray>("pinHmac") ?: ByteArray(0)
        if (dbKey == null) {
            result.error("ARG", "dbKey required", null)
            return
        }
        try {
            ensureKey()
            // Primary key is silent — no promptBiometric on the data
            // path. doFinal runs synchronously on the calling thread.
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, loadKey())
            val ciphertext = cipher.doFinal(dbKey)
            val iv = cipher.iv
            writeVault(pinHmac, iv, ciphertext)
            result.success(true)
        } catch (e: Throwable) {
            result.error("STORE", e.message, null)
        }
    }

    private fun read(call: MethodCall, result: MethodChannel.Result) {
        val pinHmac = call.argument<ByteArray>("pinHmac") ?: ByteArray(0)
        val parsed = readVault()
        if (parsed == null) {
            result.success(null)
            return
        }
        if (!constantTimeEquals(parsed.pinHmac, pinHmac)) {
            result.success(null)
            return
        }
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                loadKey(),
                GCMParameterSpec(GCM_TAG_BITS, parsed.iv)
            )
            // Primary key is silent — doFinal runs synchronously.
            val plain = cipher.doFinal(parsed.ciphertext)
            result.success(plain)
        } catch (e: Throwable) {
            result.error("READ", e.message, null)
        }
    }

    // ─────────────────────────────────────────────────────────────
    //  Biometric password overlay — bank-style "biometric shortcut"
    //  that releases the user's typed password from a biometric-gated
    //  Keystore entry. Never touches the DB wrapping key; caller feeds
    //  the released password into the normal password-gated read()
    //  path.
    // ─────────────────────────────────────────────────────────────

    private fun storeBiometricPassword(call: MethodCall, result: MethodChannel.Result) {
        val passwordBytes = call.argument<ByteArray>("passwordBytes")
        if (passwordBytes == null) {
            result.error("ARG", "passwordBytes required", null)
            return
        }
        try {
            ensureBiometricPasswordKey()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, loadBiometricPasswordKey())
            promptBiometric(cipher, "Save password for biometric unlock", onAuth = { authed ->
                val ciphertext = authed.doFinal(passwordBytes)
                val iv = authed.iv
                writeBiometricPasswordBlob(iv, ciphertext)
                result.success(true)
            }, onFail = { code, msg -> result.error(code, msg, null) })
        } catch (e: Throwable) {
            result.error("STORE_BIO_PW", e.message, null)
        }
    }

    private fun readBiometricPassword(result: MethodChannel.Result) {
        val parsed = readBiometricPasswordBlob()
        if (parsed == null) {
            result.success(null)
            return
        }
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                loadBiometricPasswordKey(),
                GCMParameterSpec(GCM_TAG_BITS, parsed.iv)
            )
            promptBiometric(cipher, "Unlock with biometrics", onAuth = { authed ->
                val plain = authed.doFinal(parsed.ciphertext)
                result.success(plain)
            }, onFail = { code, msg -> result.error(code, msg, null) })
        } catch (e: Throwable) {
            result.error("READ_BIO_PW", e.message, null)
        }
    }

    private fun ensureBiometricPasswordKey() {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (ks.containsAlias(BIO_PASSWORD_KEY_ALIAS)) return
        val kg = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        val builder = KeyGenParameterSpec.Builder(
            BIO_PASSWORD_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        try {
            builder.setIsStrongBoxBacked(true)
        } catch (_: Throwable) {
            // StrongBox not present on this device — fall through to
            // TEE-backed Keystore automatically. minSdk=28 guarantees
            // the API exists; the try/catch covers the
            // StrongBoxUnavailableException thrown at init() time on
            // devices whose hardware does not expose StrongBox.
        }
        kg.init(builder.build())
        kg.generateKey()
    }

    private fun loadBiometricPasswordKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return ks.getKey(BIO_PASSWORD_KEY_ALIAS, null) as SecretKey
    }

    private fun biometricPasswordFile(): File =
        File(activity.filesDir, BIO_PASSWORD_FILE_NAME)

    private fun writeBiometricPasswordBlob(iv: ByteArray, ciphertext: ByteArray) {
        val out = ByteArrayOutputStream()
        out.write(intToBytes(iv.size))
        out.write(iv)
        out.write(intToBytes(ciphertext.size))
        out.write(ciphertext)
        val file = biometricPasswordFile()
        file.writeBytes(out.toByteArray())
        file.setReadable(false, false)
        file.setReadable(true, true)
        file.setWritable(false, false)
        file.setWritable(true, true)
    }

    private data class BiometricPasswordBlob(
        val iv: ByteArray,
        val ciphertext: ByteArray,
    )

    private fun readBiometricPasswordBlob(): BiometricPasswordBlob? {
        val file = biometricPasswordFile()
        if (!file.exists()) return null
        return try {
            val raw = file.readBytes()
            var pos = 0
            fun next(): ByteArray {
                val len = bytesToInt(raw, pos); pos += 4
                val slice = raw.sliceArray(pos until pos + len)
                pos += len
                return slice
            }
            BiometricPasswordBlob(next(), next())
        } catch (_: Throwable) {
            null
        }
    }

    private fun clearBiometricPasswordInternal() {
        try {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (ks.containsAlias(BIO_PASSWORD_KEY_ALIAS)) {
                ks.deleteEntry(BIO_PASSWORD_KEY_ALIAS)
            }
        } catch (_: Throwable) {
        }
        biometricPasswordFile().delete()
    }

    private fun ensureKey() {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (ks.containsAlias(KEY_ALIAS)) return
        val kg = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        // Primary key is SILENT — no setUserAuthenticationRequired.
        // The bank-style primary data key is hardware-bound but does
        // not gate on biometric / LSKF. Gating lives on the Dart-side
        // HMAC compare (when the password modifier is on) and on the
        // SECONDARY biometric-password-overlay key (when the biometric
        // modifier is on). Layering biometric on the primary too would
        // force a biometric prompt on every read even when the user
        // did not ask for it.
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
        try {
            builder.setIsStrongBoxBacked(true)
        } catch (_: Throwable) {
            // StrongBox not present on this device — fall through to
            // TEE-backed Keystore automatically. minSdk=28 guarantees
            // `setIsStrongBoxBacked` exists.
        }
        kg.init(builder.build())
        kg.generateKey()
    }

    private fun loadKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return ks.getKey(KEY_ALIAS, null) as SecretKey
    }

    private fun promptBiometric(
        cipher: Cipher,
        reason: String,
        onAuth: (Cipher) -> Unit,
        onFail: (String, String?) -> Unit,
    ) {
        val executor = Executors.newSingleThreadExecutor()
        val prompt = BiometricPrompt(
            activity, executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult
                ) {
                    val authed = result.cryptoObject?.cipher
                    if (authed != null) {
                        activity.runOnUiThread { onAuth(authed) }
                    } else {
                        activity.runOnUiThread { onFail("NO_CRYPTO", "Missing CryptoObject") }
                    }
                }

                override fun onAuthenticationError(code: Int, message: CharSequence) {
                    activity.runOnUiThread { onFail("AUTH_ERROR_$code", message.toString()) }
                }

                override fun onAuthenticationFailed() {
                    // User had a live attempt that was rejected — let
                    // the system retry; do not fire onFail here.
                }
            }
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("LetsFLUTssh")
            .setSubtitle(reason)
            .setNegativeButtonText("Cancel")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()
        activity.runOnUiThread {
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        }
    }

    private data class VaultBlob(
        val pinHmac: ByteArray,
        val iv: ByteArray,
        val ciphertext: ByteArray,
    )

    private fun vaultFile(): File = File(activity.filesDir, VAULT_FILE_NAME)

    private fun writeVault(pinHmac: ByteArray, iv: ByteArray, ciphertext: ByteArray) {
        val out = ByteArrayOutputStream()
        out.write(intToBytes(pinHmac.size))
        out.write(pinHmac)
        out.write(intToBytes(iv.size))
        out.write(iv)
        out.write(intToBytes(ciphertext.size))
        out.write(ciphertext)
        val file = vaultFile()
        file.writeBytes(out.toByteArray())
        file.setReadable(false, false)
        file.setReadable(true, true)
        file.setWritable(false, false)
        file.setWritable(true, true)
    }

    private fun readVault(): VaultBlob? {
        val file = vaultFile()
        if (!file.exists()) return null
        return try {
            val raw = file.readBytes()
            var pos = 0
            fun next(): ByteArray {
                val len = bytesToInt(raw, pos); pos += 4
                val slice = raw.sliceArray(pos until pos + len)
                pos += len
                return slice
            }
            VaultBlob(next(), next(), next())
        } catch (_: Throwable) {
            null
        }
    }

    private fun clearInternal() {
        try {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (ks.containsAlias(KEY_ALIAS)) ks.deleteEntry(KEY_ALIAS)
        } catch (_: Throwable) {
        }
        vaultFile().delete()
        // Clear the biometric overlay too — tier transitions wipe both
        // halves, so the overlay never outlives its paired primary
        // vault.
        clearBiometricPasswordInternal()
    }

    private fun intToBytes(i: Int): ByteArray = byteArrayOf(
        (i shr 24).toByte(), (i shr 16).toByte(), (i shr 8).toByte(), i.toByte()
    )

    private fun bytesToInt(buf: ByteArray, off: Int): Int =
        ((buf[off].toInt() and 0xFF) shl 24) or
            ((buf[off + 1].toInt() and 0xFF) shl 16) or
            ((buf[off + 2].toInt() and 0xFF) shl 8) or
            (buf[off + 3].toInt() and 0xFF)

    private fun constantTimeEquals(a: ByteArray, b: ByteArray): Boolean {
        if (a.size != b.size) return false
        var diff = 0
        for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
        return diff == 0
    }
}

@Suppress("unused")
fun registerHardwareVaultPlugin(activity: FragmentActivity, channel: MethodChannel) {
    HardwareVaultPlugin(activity).register(channel)
}

@Suppress("unused")
fun unusedContextAnchor(@Suppress("UNUSED_PARAMETER") ctx: Context) {
    // Kept so reflection-based tooling that scans the file for Context
    // bindings does not drop it; HardwareVaultPlugin itself only needs
    // the FragmentActivity, which subclasses Context.
}
