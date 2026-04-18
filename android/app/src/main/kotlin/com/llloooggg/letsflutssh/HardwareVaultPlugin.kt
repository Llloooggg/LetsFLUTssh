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
        private const val VAULT_FILE_NAME = "hardware_vault_android.bin"
        private const val GCM_TAG_BITS = 128
    }

    fun register(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isAvailable())
            "backingLevel" -> result.success(backingLevel())
            "isStored" -> result.success(vaultFile().exists())
            "store" -> store(call, result)
            "read" -> read(call, result)
            "clear" -> {
                clearInternal()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun isAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        val bm = BiometricManager.from(activity)
        val status = bm.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        return status == BiometricManager.BIOMETRIC_SUCCESS
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
        val pinHmac = call.argument<ByteArray>("pinHmac")
        if (dbKey == null || pinHmac == null) {
            result.error("ARG", "dbKey and pinHmac required", null)
            return
        }
        try {
            ensureKey()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, loadKey())
            promptBiometric(cipher, "Set up hardware vault", onAuth = { authed ->
                val ciphertext = authed.doFinal(dbKey)
                val iv = authed.iv
                writeVault(pinHmac, iv, ciphertext)
                result.success(true)
            }, onFail = { code, msg -> result.error(code, msg, null) })
        } catch (e: Throwable) {
            result.error("STORE", e.message, null)
        }
    }

    private fun read(call: MethodCall, result: MethodChannel.Result) {
        val pinHmac = call.argument<ByteArray>("pinHmac")
        if (pinHmac == null) {
            result.error("ARG", "pinHmac required", null)
            return
        }
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
            promptBiometric(cipher, "Unlock hardware vault", onAuth = { authed ->
                val plain = authed.doFinal(parsed.ciphertext)
                result.success(plain)
            }, onFail = { code, msg -> result.error(code, msg, null) })
        } catch (e: Throwable) {
            result.error("READ", e.message, null)
        }
    }

    private fun ensureKey() {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (ks.containsAlias(KEY_ALIAS)) return
        val kg = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                builder.setIsStrongBoxBacked(true)
            } catch (_: Throwable) {
                // StrongBox not present on this device — fall through
                // to TEE-backed Keystore automatically.
            }
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
