package com.llloooggg.letsflutssh

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import io.flutter.plugin.common.MethodChannel

/// Clipboard writer that flags every copy as sensitive.
///
/// Android 13+ reads `ClipDescription.EXTRA_IS_SENSITIVE` when
/// deciding whether to show the clipboard toast preview and whether
/// to advertise the content to the launcher "share what you copied"
/// affordances. Setting it hides passwords and tokens from the
/// shoulder-surf surface without refusing to copy.
///
/// Pre-Tiramisu SDKs silently ignore the extra — the copy still
/// works, the OS just cannot honour the flag.
class ClipboardSecurePlugin(private val context: Context) {
    companion object {
        const val CHANNEL = "com.letsflutssh/clipboard_secure"
        private const val SENSITIVE_EXTRA = "android.content.extra.IS_SENSITIVE"
    }

    fun register(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecureText" -> {
                    val text = call.argument<String>("text")
                    if (text == null) {
                        result.error("BAD_ARGS", "setSecureText requires {text: String}", null)
                        return@setMethodCallHandler
                    }
                    setSecureText(text, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setSecureText(text: String, result: MethodChannel.Result) {
        try {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("", text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                clip.description.extras = PersistableBundle().apply {
                    putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                }
            } else {
                // Older SDKs ignore the symbol, but the raw string
                // key is the same — harmless on Tiramisu, honoured
                // by some OEM clipboard surfaces that backported the
                // hint to pre-13 builds.
                clip.description.extras = PersistableBundle().apply {
                    putBoolean(SENSITIVE_EXTRA, true)
                }
            }
            clipboard.setPrimaryClip(clip)
            result.success(true)
        } catch (e: Exception) {
            result.error("CLIPBOARD_FAILED", e.message, null)
        }
    }
}
