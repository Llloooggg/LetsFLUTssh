package com.llloooggg.letsflutssh

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.biometric.BiometricPrompt

/**
 * Pure callback adapter for `androidx.biometric.BiometricPrompt`.
 *
 * `BiometricPrompt` requires an `AuthenticationCallback`
 * subclass plus a main-thread call to `authenticate(...)`.
 * Both constraints are JVM-side concerns — no business logic
 * lives here. Each callback method routes straight into a
 * Rust `extern "system"` entry point in
 * `lfs_os_security::android::biometric` keyed on a per-prompt
 * `requestId` we receive at construction.
 *
 * The `dispatchAuthenticate` method posts a Runnable to the
 * main looper that invokes `prompt.authenticate(info)` — this
 * is the JVM-required main-thread hop the Rust caller can't
 * do directly.
 *
 * Equivalent in spirit to objc2's `RcBlock` adapter for
 * Apple LAContext: a thin calling-convention bridge between
 * Java's callback model and Rust's tokio oneshot, no key
 * material or crypto state held here.
 */
class LfsBiometricCallback(private val requestId: Long) : BiometricPrompt.AuthenticationCallback() {

    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
        // Log breadcrumb only — no credential / key material is in scope here,
        // BiometricPrompt does not expose the credential bytes via this callback.
        Log.d(TAG, "onAuthenticationSucceeded requestId=$requestId")
        nativeOnSucceeded(requestId)
    }

    override fun onAuthenticationFailed() {
        Log.d(TAG, "onAuthenticationFailed requestId=$requestId")
        nativeOnFailed(requestId)
    }

    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
        // `errString` is a localized OS message ("Too many attempts. Try
        // again later.", etc.) — safe to log; contains no credential or PII.
        Log.d(TAG, "onAuthenticationError requestId=$requestId code=$errorCode msg=$errString")
        nativeOnError(requestId, errorCode)
    }

    /**
     * Main-thread dispatcher for `BiometricPrompt.authenticate`.
     * Called from the Rust JNI side after the prompt + info
     * objects are constructed. Posts to `Handler(Looper.getMainLooper())`
     * regardless of caller thread, so the Rust side can invoke
     * from any worker thread without worrying about
     * `IllegalStateException: Must be called from main thread`.
     */
    fun dispatchAuthenticate(prompt: BiometricPrompt, info: BiometricPrompt.PromptInfo) {
        Log.d(TAG, "dispatchAuthenticate requestId=$requestId")
        Handler(Looper.getMainLooper()).post {
            prompt.authenticate(info)
        }
    }

    private external fun nativeOnSucceeded(requestId: Long)
    private external fun nativeOnFailed(requestId: Long)
    private external fun nativeOnError(requestId: Long, errorCode: Int)

    companion object {
        // Single tag for filtering in `adb logcat -s LfsBiometric:D` during
        // support investigations.
        private const val TAG = "LfsBiometric"
    }
}
