package com.llloooggg.letsflutssh

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (instead of FlutterActivity) is required by
// local_auth's BiometricPrompt, which hosts its UI inside a Fragment.
class MainActivity : FlutterFragmentActivity() {
    private val permissionChannel = "com.letsflutssh/permissions"
    private val qrScannerChannel = "com.letsflutssh/qrscanner"
    private var pendingResult: MethodChannel.Result? = null
    private var pendingScanResult: MethodChannel.Result? = null

    companion object {
        private const val MANAGE_STORAGE_REQUEST = 1001
        private const val LEGACY_STORAGE_REQUEST = 1002
        private const val QR_SCAN_REQUEST = 1003
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestStoragePermission" -> requestStoragePermission(result)
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
    }

    private fun launchQrScanner(result: MethodChannel.Result) {
        if (pendingScanResult != null) {
            result.error("BUSY", "A scan is already in progress", null)
            return
        }
        pendingScanResult = result
        val intent = Intent(this, QrScannerActivity::class.java)
        startActivityForResult(intent, QR_SCAN_REQUEST)
    }

    private fun requestStoragePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ — need MANAGE_EXTERNAL_STORAGE
            if (Environment.isExternalStorageManager()) {
                result.success(true)
            } else {
                pendingResult = result
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivityForResult(intent, MANAGE_STORAGE_REQUEST)
            }
        } else {
            // Android 10 and below — runtime permission
            val permission = android.Manifest.permission.READ_EXTERNAL_STORAGE
            if (ContextCompat.checkSelfPermission(this, permission)
                == android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                result.success(true)
            } else {
                pendingResult = result
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        android.Manifest.permission.READ_EXTERNAL_STORAGE,
                        android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                    ),
                    LEGACY_STORAGE_REQUEST
                )
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == MANAGE_STORAGE_REQUEST) {
            val granted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                Environment.isExternalStorageManager()
            pendingResult?.success(granted)
            pendingResult = null
        } else if (requestCode == QR_SCAN_REQUEST) {
            val payload = data?.getStringExtra(QrScannerActivity.EXTRA_RESULT)
            pendingScanResult?.success(if (resultCode == RESULT_OK) payload else null)
            pendingScanResult = null
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LEGACY_STORAGE_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            pendingResult?.success(granted)
            pendingResult = null
        }
    }
}
