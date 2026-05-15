package com.llloooggg.letsflutssh

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.biometric.BiometricPrompt

/**
 * Pure callback adapter for `androidx.biometric.BiometricPrompt`
 * specialised for SSH-key signing. Mirrors `LfsBiometricCallback`
 * one file over but routes the prompt's CryptoObject result into a
 * `Signature.update(data) + sign()` round trip before handing the
 * bytes back to Rust through `nativeOnSigned`.
 *
 * No business logic lives here — the adapter holds the
 * to-be-signed bytes plus the per-sign `requestId` we received at
 * construction and forwards every prompt outcome to the matching
 * Rust `extern "system"` entry point in
 * `lfs_os_security::android::keystore_signer`. The Kotlin side is
 * the JVM equivalent of objc2's RcBlock adapter for Apple
 * LAContext — a thin calling-convention bridge between
 * AndroidX's callback model and Rust's tokio oneshot.
 */
class LfsKeystoreSignCallback(
    private val requestId: Long,
    private val data: ByteArray,
) : BiometricPrompt.AuthenticationCallback() {

    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
        val signature = result.cryptoObject?.signature
        if (signature == null) {
            // Diagnostic only — no signature bytes exist yet.
            Log.d(TAG, "onAuthenticationSucceeded requestId=$requestId signature=null")
            nativeOnFailedStatic(requestId, "other", "CryptoObject.signature null")
            return
        }
        try {
            signature.update(data)
            val sig = signature.sign()
            // Log only the byte length, never the signature contents.
            Log.d(TAG, "onSignSucceeded requestId=$requestId sigLen=${sig.size}")
            nativeOnSigned(requestId, sig)
        } catch (e: Throwable) {
            Log.d(TAG, "onSignFailed requestId=$requestId reason=${e.javaClass.simpleName} msg=${e.message}")
            nativeOnFailedStatic(requestId, "other", "sign: ${e.message}")
        }
    }

    override fun onAuthenticationFailed() {
        // `onAuthenticationFailed` fires on a bad biometric reading
        // but the prompt stays up; the final outcome lands in
        // onAuthenticationError or onAuthenticationSucceeded. Don't
        // wake the Rust pending channel here — that would race the
        // success path.
        Log.d(TAG, "onAuthenticationFailed requestId=$requestId (prompt remains)")
    }

    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
        // Error codes per BiometricPrompt:
        //   7 = LOCKOUT, 9 = LOCKOUT_PERMANENT, 10 = USER_CANCELED,
        //  13 = NEGATIVE_BUTTON, 14 = NO_DEVICE_CREDENTIAL.
        val tag = when (errorCode) {
            10, 13 -> "cancelled"
            7, 9 -> "user-not-authenticated"
            else -> "other"
        }
        // `errString` is a localized OS message — safe to log; contains no
        // credential or PII.
        Log.d(TAG, "onAuthenticationError requestId=$requestId code=$errorCode tag=$tag msg=$errString")
        nativeOnFailedStatic(requestId, tag, errString.toString())
    }

    /**
     * Main-thread dispatcher for `BiometricPrompt.authenticate`.
     * Called from the Kotlin static `KeystoreSshSigner.sign` after
     * the prompt + info + CryptoObject objects are constructed.
     * Posts to `Handler(Looper.getMainLooper())` regardless of
     * caller thread so the Rust side can invoke from any worker
     * thread without worrying about
     * `IllegalStateException: Must be called from main thread`.
     */
    fun dispatchAuthenticate(
        prompt: BiometricPrompt,
        info: BiometricPrompt.PromptInfo,
        crypto: BiometricPrompt.CryptoObject,
    ) {
        Log.d(TAG, "dispatchAuthenticate requestId=$requestId dataLen=${data.size}")
        Handler(Looper.getMainLooper()).post {
            prompt.authenticate(info, crypto)
        }
    }

    private external fun nativeOnSigned(requestId: Long, signature: ByteArray)
    private external fun nativeOnFailed(requestId: Long, reasonTag: String, detail: String)

    companion object {
        // Single tag for filtering in `adb logcat -s LfsKeystoreSign:D`
        // during support investigations.
        private const val TAG = "LfsKeystoreSign"

        /**
         * Static-side shortcut for the pre-authenticate failure
         * branches inside `KeystoreSshSigner.sign` (algorithm
         * lookup failed, alias missing, `initSign` threw a
         * non-`UserNotAuthenticatedException`). Invokes the same
         * Rust entry point as the instance method via a throwaway
         * callback instance — the Rust side does not care about
         * Kotlin object identity, only about the requestId pairing.
         */
        @JvmStatic
        fun nativeOnFailedStatic(reqId: Long, reasonTag: String, detail: String) {
            Log.d(TAG, "nativeOnFailedStatic requestId=$reqId reason=$reasonTag detail=$detail")
            LfsKeystoreSignCallback(reqId, ByteArray(0))
                .nativeOnFailed(reqId, reasonTag, detail)
        }
    }
}
