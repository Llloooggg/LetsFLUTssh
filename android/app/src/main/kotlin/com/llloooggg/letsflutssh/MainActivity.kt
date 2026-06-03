package com.llloooggg.letsflutssh

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity (instead of FlutterActivity) is required by
// `androidx.biometric.BiometricPrompt` (consumed Rust-side via JNI in
// `lfs_os_security::android::biometric`); the prompt hosts its UI
// inside a Fragment and crashes on a plain FlutterActivity.
class MainActivity : FlutterFragmentActivity() {
    private val permissionChannel = "com.letsflutssh/permissions"
    private val qrScannerChannel = "com.letsflutssh/qrscanner"
    private val secureScreenChannel = "com.letsflutssh/secure_screen"
    private val apkInstallerChannel = "com.letsflutssh/apk_installer"

    // Pending result for an in-flight storage-permission request — the
    // request runs on the platform-channel thread, the grant verdict
    // arrives on the main thread via onActivityResult /
    // onRequestPermissionsResult. Same @Volatile + lock discipline as
    // the QR-scan result so a second request cannot race past the busy
    // check while the first verdict is mid-delivery.
    @Volatile
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val permissionResultLock = Any()

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
        private const val MANAGE_STORAGE_REQUEST = 1001
        private const val LEGACY_STORAGE_REQUEST = 1002
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestStoragePermission" -> requestStoragePermission(result)
                    "hasStoragePermission" -> result.success(hasStoragePermission())
                    else -> result.notImplemented()
                }
            }

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

        // In-app update installer: hands the downloaded, signature-
        // verified apk to the system package installer. The Dart side
        // (`UpdateService.openFile`) only reaches here on Android after
        // the download + Ed25519 verify pipeline succeeds.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, apkInstallerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("ARG", "missing apk path", null)
                        } else {
                            installApk(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Launch the system package installer for the apk at [path].
    /// Returns (via [result]) "launched" when the install UI opened,
    /// "needsPermission" when API 26+ required the per-app "install
    /// unknown apps" grant and the settings screen was opened instead
    /// (the user grants once, then re-triggers), or an error the Dart
    /// side maps to the release-page fallback.
    private fun installApk(path: String, result: MethodChannel.Result) {
        // API 26+: installing requires a per-app "install unknown apps"
        // grant. When it's missing, open that settings screen for our
        // package rather than failing — the user toggles it once.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val grant = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(grant)
            result.success("needsPermission")
            return
        }
        val uri = try {
            // ACTION_VIEW cannot read a raw file:// path from app-internal
            // storage on API 24+; the FileProvider serves it as a
            // content:// URI the installer can read under the granted
            // permission flag.
            FileProvider.getUriForFile(this, "$packageName.fileprovider", File(path))
        } catch (e: IllegalArgumentException) {
            result.error("URI", "apk path not under a FileProvider root: ${e.message}", null)
            return
        }
        val install = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(install)
            result.success("launched")
        } catch (e: Exception) {
            result.error("LAUNCH", "could not launch installer: ${e.message}", null)
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

    /// True when broad storage access is already held: Android 11+
    /// needs `MANAGE_EXTERNAL_STORAGE` (the "All files access" grant),
    /// older releases the runtime `READ_EXTERNAL_STORAGE`. Side-effect
    /// free — used to decide whether to show the "grant access" banner.
    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.READ_EXTERNAL_STORAGE,
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        }
    }

    /// Request broad storage access. Already-granted short-circuits to
    /// `true`. Android 11+ opens the system "All files access" screen
    /// (`ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`) and reports the
    /// verdict from `onActivityResult`; older releases use the runtime
    /// permission dialog and report from `onRequestPermissionsResult`.
    /// A second call while one is pending is rejected so the verdict
    /// delivery cannot race.
    private fun requestStoragePermission(result: MethodChannel.Result) {
        if (hasStoragePermission()) {
            result.success(true)
            return
        }
        synchronized(permissionResultLock) {
            if (pendingPermissionResult != null) {
                result.error("BUSY", "A storage-permission request is in progress", null)
                return
            }
            pendingPermissionResult = result
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivityForResult(intent, MANAGE_STORAGE_REQUEST)
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    android.Manifest.permission.READ_EXTERNAL_STORAGE,
                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ),
                LEGACY_STORAGE_REQUEST,
            )
        }
    }

    private fun deliverPermissionVerdict(granted: Boolean) {
        val pending = synchronized(permissionResultLock) {
            val r = pendingPermissionResult
            pendingPermissionResult = null
            r
        }
        pending?.success(granted)
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
        if (requestCode == MANAGE_STORAGE_REQUEST) {
            // The system screen does not return a result code we can
            // trust; re-probe the live grant state instead.
            deliverPermissionVerdict(
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                    Environment.isExternalStorageManager(),
            )
        } else if (requestCode == QR_SCAN_REQUEST) {
            val payload = data?.getStringExtra(QrScannerActivity.EXTRA_RESULT)
            val pending = synchronized(scanResultLock) {
                val r = pendingScanResult
                pendingScanResult = null
                r
            }
            pending?.success(if (resultCode == RESULT_OK) payload else null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LEGACY_STORAGE_REQUEST) {
            deliverPermissionVerdict(
                grantResults.isNotEmpty() &&
                    grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED,
            )
        }
    }
}
