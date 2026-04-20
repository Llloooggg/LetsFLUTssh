package com.llloooggg.letsflutssh

import android.content.Context
import android.graphics.Color
import android.text.InputType
import android.util.TypedValue
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import androidx.core.widget.addTextChangedListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.nio.charset.StandardCharsets

/// Native-memory-backed secure text input for password / passphrase
/// fields. Bytes live in an Android [EditText]'s [android.text.Editable]
/// (Java heap, char[] — mutable) instead of a Dart [String] (Dart
/// heap, immutable, GC-relocatable). On submit the bytes are encoded
/// to UTF-8, sent across the method channel as a [Uint8List], and
/// the EditText content is wiped in place before the call returns.
/// The Dart side copies the bytes into a page-locked [SecretBuffer]
/// and zeroes the Uint8List in the same frame — residency on the
/// Dart heap collapses to a single copy, one frame long.
///
/// Caveat: the bytes still sit in the Java heap for the duration of
/// typing. Java heap is also GC'd, but Android keyboards (Samsung,
/// Gboard, SwiftKey, Chinese IMEs) already handle passwords through
/// this same EditText path — the threat model is narrower than
/// "every process can read it". The win over Flutter TextField is
/// eliminating the interim Dart [String] allocations that land per
/// keystroke in the TextEditingValue history.
class SecureTextFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return SecureTextView(context, messenger, viewId)
    }
}

class SecureTextView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
) : PlatformView {
    companion object {
        const val VIEW_TYPE = "com.letsflutssh/secure_text"
    }

    private val channel = MethodChannel(
        messenger,
        "com.letsflutssh/secure_text_$viewId",
    )

    private val editText = EditText(context).apply {
        inputType = InputType.TYPE_CLASS_TEXT or
            InputType.TYPE_TEXT_VARIATION_PASSWORD
        imeOptions = EditorInfo.IME_ACTION_DONE or
            EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING or
            EditorInfo.IME_FLAG_NO_EXTRACT_UI
        isSingleLine = true
        isLongClickable = false
        setTextIsSelectable(false)
        setTextColor(Color.BLACK)
        setHintTextColor(Color.GRAY)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
    }

    private val container = FrameLayout(context).apply {
        addView(
            editText,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
    }

    init {
        editText.addTextChangedListener(
            afterTextChanged = { _ ->
                // Notify Dart when there's any text vs. empty — the
                // Dart side uses this to light up the Apply button.
                channel.invokeMethod(
                    "onChanged",
                    mapOf("hasText" to (editText.text?.isNotEmpty() == true)),
                )
            },
        )
        editText.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                emitAndWipe()
                true
            } else {
                false
            }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "submit" -> {
                    val bytes = emitAndWipe()
                    result.success(bytes)
                }
                "focus" -> {
                    editText.requestFocus()
                    result.success(true)
                }
                "clear" -> {
                    wipeEditable()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Encode current content to UTF-8 and wipe the Editable in
    /// place. Returns the bytes by value so the native→Dart channel
    /// can deliver them even after the view is gone.
    private fun emitAndWipe(): ByteArray {
        val editable = editText.text ?: return ByteArray(0)
        val bytes = editable.toString().toByteArray(StandardCharsets.UTF_8)
        // Also push the bytes through the one-shot onSubmit stream so
        // a long-press context-menu "Done" path surfaces the same
        // event shape as the IME Done key.
        channel.invokeMethod("onSubmit", bytes)
        wipeEditable()
        return bytes
    }

    /// Overwrite the backing char[] with NUL before clearing. The
    /// default `setText("")` replaces the underlying array without
    /// zeroing the old one — ART may hold onto the deallocated
    /// char[] in the young generation until the next GC cycle.
    /// Overwriting forces the same bytes to be NUL regardless of
    /// GC timing.
    private fun wipeEditable() {
        val editable = editText.text ?: return
        val len = editable.length
        if (len > 0) {
            val nulls = CharArray(len)
            editable.replace(0, len, String(nulls))
        }
        editable.clear()
    }

    override fun getView(): View = container

    override fun dispose() {
        wipeEditable()
        channel.setMethodCallHandler(null)
    }
}

/// Thin registrar — call from MainActivity.configureFlutterEngine.
class SecureTextPlugin {
    fun register(
        messenger: BinaryMessenger,
        registry: io.flutter.plugin.platform.PlatformViewRegistry,
    ) {
        registry.registerViewFactory(
            SecureTextView.VIEW_TYPE,
            SecureTextFactory(messenger),
        )
    }
}
