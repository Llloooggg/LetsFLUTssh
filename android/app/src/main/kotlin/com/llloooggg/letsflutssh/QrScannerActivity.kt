package com.llloooggg.letsflutssh

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.Result
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Full-screen QR scanner using CameraX for the preview pipeline and
 * ZXing-core for decoding.  Entirely offline — no Google Play Services
 * or MLKit involved.
 *
 * Contract:
 *   - Started by `QrScannerActivity.INTENT_ACTION` from [MainActivity].
 *   - Finishes with [Activity.RESULT_OK] and `EXTRA_RESULT` when a QR
 *     code is decoded, [Activity.RESULT_CANCELED] otherwise.
 */
class QrScannerActivity : ComponentActivity() {
    companion object {
        private const val TAG = "QrScanner"
        const val EXTRA_RESULT = "qr_result"
    }

    private lateinit var previewView: PreviewView
    private lateinit var cameraExecutor: ExecutorService
    private val decoded = AtomicBoolean(false)

    private val requestCamera = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            startCamera()
        } else {
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(buildLayout())
        cameraExecutor = Executors.newSingleThreadExecutor()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) {
            startCamera()
        } else {
            requestCamera.launch(Manifest.permission.CAMERA)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cameraExecutor.shutdown()
    }

    private fun buildLayout(): FrameLayout {
        val root = FrameLayout(this)
        root.setBackgroundColor(0xFF000000.toInt())
        root.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )

        previewView = PreviewView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        root.addView(previewView)

        // Minimal on-screen hint — the Flutter side already shows its own
        // page around this activity, but a short caption avoids a blank
        // camera view on the very first frames.
        val hint = TextView(this).apply {
            text = "Point at a LetsFLUTssh QR"
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 14f
            setPadding(16, 12, 16, 12)
            setBackgroundColor(0x80000000.toInt())
            val lp = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            lp.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            lp.bottomMargin = 48
            layoutParams = lp
        }
        root.addView(hint)
        return root
    }

    private fun startCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            val provider = providerFuture.get()

            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }

            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
            analysis.setAnalyzer(cameraExecutor, ::analyseFrame)

            try {
                provider.unbindAll()
                provider.bindToLifecycle(
                    this,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    preview,
                    analysis,
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to bind camera: $e")
                finish()
            }
        }, ContextCompat.getMainExecutor(this))
    }

    @OptIn(ExperimentalGetImage::class)
    private fun analyseFrame(imageProxy: ImageProxy) {
        if (decoded.get()) {
            imageProxy.close()
            return
        }
        try {
            val yPlane = imageProxy.planes[0]
            val yBuffer = yPlane.buffer
            val data = ByteArray(yBuffer.remaining())
            yBuffer.get(data)

            val source = PlanarYUVLuminanceSource(
                data,
                yPlane.rowStride,
                imageProxy.height,
                0, 0,
                imageProxy.width,
                imageProxy.height,
                false,
            )
            val bitmap = BinaryBitmap(HybridBinarizer(source))
            val reader = MultiFormatReader().apply {
                setHints(
                    mapOf(
                        DecodeHintType.POSSIBLE_FORMATS to listOf(
                            com.google.zxing.BarcodeFormat.QR_CODE,
                        ),
                    ),
                )
            }
            val result: Result = reader.decode(bitmap)
            val text = result.text ?: return
            if (decoded.compareAndSet(false, true)) {
                runOnUiThread { finishWithResult(text) }
            }
        } catch (_: NotFoundException) {
            // No code in this frame — normal, keep scanning.
        } catch (e: Exception) {
            Log.w(TAG, "Frame decode failed: $e")
        } finally {
            imageProxy.close()
        }
    }

    private fun finishWithResult(text: String) {
        val data = Intent().putExtra(EXTRA_RESULT, text)
        setResult(Activity.RESULT_OK, data)
        finish()
    }
}
