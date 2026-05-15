package com.llloooggg.letsflutssh

import android.content.Intent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (instead of FlutterActivity) is required by
// `androidx.biometric.BiometricPrompt` (consumed Rust-side via JNI in
// `lfs_os_security::android::biometric`); the prompt hosts its UI
// inside a Fragment and crashes on a plain FlutterActivity.
class MainActivity : FlutterFragmentActivity() {
    private val qrScannerChannel = "com.letsflutssh/qrscanner"
    private val secureScreenChannel = "com.letsflutssh/secure_screen"

    // Cross-thread access to the pending QR-scan result. `launchQrScanner`
    // runs on the platform-channel thread; `onActivityResult` runs on the
    // main thread. Without `@Volatile` the write from one thread is not
    // guaranteed to be visible to the other, and a stale-null read from
    // `onActivityResult` would silently drop the user's scan response.
    // The `synchronized(scanResultLock)` blocks make the
    // null-check-then-set and read-then-clear atomic against each other
    // so a second `scan` call cannot race past the busy guard while the
    // first result is mid-delivery.
    @Volatile
    private var pendingScanResult: MethodChannel.Result? = null
    private val scanResultLock = Any()

    // Refcount for FLAG_SECURE — a nested SecureScreenScope (e.g. an
    // unlock dialog inside the wizard) should not clear the flag when
    // the inner scope disposes. Set on transition 0→1, clear on
    // N→0, leave alone otherwise.
    private var secureScreenRefcount = 0

    companion object {
        private const val QR_SCAN_REQUEST = 1003
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // JavaVM + activity + Application context bootstrap for
        // the lfs_os_security Android JNI path. Cargokit-loaded
        // `liblfs_frb.so` comes in via `dart:ffi` (not
        // `System.loadLibrary`), so the standard `JNI_OnLoad`
        // callback never fires; calling
        // `LfsJniBootstrap.register(this)` here captures the
        // three handles (JavaVM, FragmentActivity for
        // BiometricPrompt, Application context for getFilesDir
        // etc.) into process-wide OnceLocks that
        // `lfs_os_security::android::*` reads on every JNI call.
        // Idempotent — safe to call again on MainActivity
        // recreation; the OnceLocks ignore second-write attempts.
        LfsJniBootstrap.register(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, qrScannerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scan" -> launchQrScanner(result)
                    else -> result.notImplemented()
                }
            }

        // L3 hardware-backed vault is owned Rust-side now —
        // `lfs_os_security::android::hardware_vault` calls into
        // `java.security.KeyStore` provider `"AndroidKeyStore"`
        // directly via JNI. The Dart `HardwareTierVault` wrapper
        // routes Android through FRB, no MethodChannel involved.

        // Sensitive-clipboard writes (EXTRA_IS_SENSITIVE) are
        // owned Rust-side too —
        // `lfs_os_security::android::clipboard` JNIs directly into
        // `android.content.ClipboardManager`. The Dart
        // `SecureClipboard` wrapper routes Android through FRB.

        // Selective FLAG_SECURE — per-screen opt-in, refcounted so
        // nested SecureScreenScope widgets do not clear the flag
        // when the inner dispose fires. The Dart side wraps every
        // credential-entry / credential-display screen in a
        // SecureScreenScope; here we honour the setSecure calls.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureScreenChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        applySecureFlag(secure)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun applySecureFlag(secure: Boolean) {
        if (secure) {
            val was = secureScreenRefcount
            secureScreenRefcount++
            if (was == 0) {
                runOnUiThread {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE
                    )
                }
            }
        } else {
            if (secureScreenRefcount <= 0) return
            secureScreenRefcount--
            if (secureScreenRefcount == 0) {
                runOnUiThread {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
            }
        }
    }

    private fun launchQrScanner(result: MethodChannel.Result) {
        synchronized(scanResultLock) {
            if (pendingScanResult != null) {
                result.error("BUSY", "A scan is already in progress", null)
                return
            }
            pendingScanResult = result
        }
        val intent = Intent(this, QrScannerActivity::class.java)
        startActivityForResult(intent, QR_SCAN_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == QR_SCAN_REQUEST) {
            val payload = data?.getStringExtra(QrScannerActivity.EXTRA_RESULT)
            val pending = synchronized(scanResultLock) {
                val r = pendingScanResult
                pendingScanResult = null
                r
            }
            pending?.success(if (resultCode == RESULT_OK) payload else null)
        }
    }
}
