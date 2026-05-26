package com.llloooggg.letsflutssh

import android.os.Build
import android.util.Base64
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.GetCredentialInterruptedException
import androidx.credentials.exceptions.NoCredentialException
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Kotlin bridge for the Rust `lfs_os_security::fido2_broker::android`
 * module — fires the system Credential Manager dialog for an
 * `sk-*` SSH userauth signature. Mirrors the shape of
 * `KeystoreSshSigner`: a static `object`, JNI callbacks defined as
 * `external` companions, no business logic outside the
 * androidx.credentials plumbing.
 *
 * The Rust caller hands four pieces of input:
 *
 *  * `activity` — host FragmentActivity captured at bootstrap; the
 *    Credential Manager API requires a `Context` that resolves to a
 *    foreground UI surface so the system dialog can attach.
 *  * `rpId` — the bare relying-party id (stripped of any `ssh:`
 *    prefix Rust-side).
 *  * `credentialId` — opaque credential id bytes captured at sk-*
 *    key import.
 *  * `challenge` — the SHA-256 pre-hash of the SSH userauth signature
 *    input. Credential Manager wraps this into the
 *    `clientDataHash`-shaped requestJson.
 *  * `requireUserVerification` — true for credentials registered with
 *    UV; passed verbatim into the requestJson under
 *    `userVerification`.
 *
 * The response carries the CTAP `authenticatorData` blob and the
 * raw signature bytes (Ed25519 64 raw / ECDSA-P256 DER). Both are
 * base64url-decoded here and forwarded as `[B` to Rust.
 *
 * Failures are mapped to a small tag set the Rust side routes to
 * typed `BrokerError` variants:
 *
 *  * `"cancelled"` — user dismissed the dialog
 *    (`GetCredentialCancellationException`).
 *  * `"no-credential"` — no matching credential
 *    (`NoCredentialException`).
 *  * `"transport"` — transport / device-side failure.
 *  * `"timeout"` — dialog timeout (mapped from the generic
 *    `GetCredentialException` when the message names a timeout).
 *  * `"wrong-pin"` — credential gate refused the PIN.
 *  * `"other"` — everything else; detail message rides through.
 */
object Fido2Broker {
    /**
     * True when Credential Manager is reachable on this device.
     * API 28+ for the runtime API class; we additionally verify that
     * a public-key request type is supported via a probe call (lazy —
     * Credential Manager itself throws when the runtime is missing).
     */
    @JvmStatic
    fun isAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        return try {
            // Probe: instantiating CredentialManager.create() throws
            // when the Play Services / GMS Credential Manager runtime
            // is absent (rooted AOSP builds, custom ROMs without GMS,
            // Wear OS pre-API 30). Wrap in a try/catch and report the
            // honest answer.
            Class.forName("androidx.credentials.CredentialManager")
            true
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Trigger the system security-key dialog. Runs the suspending
     * `CredentialManager.getCredential` call on
     * `Dispatchers.Main.immediate` per the API contract.
     *
     * @param activity host FragmentActivity captured at bootstrap.
     * @param rpId the relying-party id; `ssh:` prefix stripped
     *   Rust-side.
     * @param credentialId opaque CTAP credential id.
     * @param challenge SHA-256 pre-hash of the SSH userauth
     *   signature input.
     * @param requireUv true when the credential carries UV.
     * @param reqId opaque tag the Rust side minted; echoed back via
     *   the JNI callbacks so the pending map can resolve the right
     *   Rust future.
     */
    @JvmStatic
    fun getAssertion(
        activity: FragmentActivity,
        rpId: String,
        credentialId: ByteArray,
        challenge: ByteArray,
        requireUv: Boolean,
        reqId: Long,
    ) {
        val requestJson = buildAssertionRequestJson(
            rpId = rpId,
            credentialId = credentialId,
            challenge = challenge,
            requireUv = requireUv,
        )
        val option = GetPublicKeyCredentialOption(requestJson = requestJson)
        val request = GetCredentialRequest(listOf(option))
        val cm = CredentialManager.create(activity)
        // The handler runs on Main so onAssertion / onFailure JNI
        // trampolines fire on a thread the JVM owns; the Rust pending
        // map locks are fine to re-enter from any thread because the
        // OnceLock / Mutex pair is process-wide.
        CoroutineScope(Dispatchers.Main.immediate).launch {
            try {
                val response = cm.getCredential(
                    context = activity,
                    request = request,
                )
                val cred = response.credential
                if (cred !is PublicKeyCredential) {
                    nativeOnFailure(
                        reqId,
                        "other",
                        "non-publickey credential type",
                    )
                    return@launch
                }
                val parsed = parseAssertionResponse(cred.authenticationResponseJson)
                nativeOnAssertion(
                    reqId,
                    parsed.signature,
                    parsed.authenticatorData,
                    parsed.userHandle ?: ByteArray(0),
                )
            } catch (e: GetCredentialCancellationException) {
                nativeOnFailure(reqId, "cancelled", e.message ?: "cancelled")
            } catch (e: NoCredentialException) {
                nativeOnFailure(reqId, "no-credential", e.message ?: "no credential")
            } catch (e: GetCredentialException) {
                val tag = classifyCredentialException(e)
                nativeOnFailure(reqId, tag, e.message ?: e.type)
            } catch (e: Throwable) {
                nativeOnFailure(reqId, "other", e.message ?: e.javaClass.simpleName)
            }
        }
    }

    /**
     * Compose the requestJson Credential Manager wraps for a
     * publicKey assertion. Same shape as the WebAuthn level-2 JSON
     * the W3C standard mandates; Credential Manager parses it back
     * server-side to drive the system dialog.
     *
     * `clientDataHash` carries the bytes verbatim — Credential
     * Manager does NOT recompute it (the platform contract says the
     * client provided the hash). For SSH this is the SHA-256 of the
     * userauth signature input the Rust side already computed.
     */
    private fun buildAssertionRequestJson(
        rpId: String,
        credentialId: ByteArray,
        challenge: ByteArray,
        requireUv: Boolean,
    ): String {
        val root = JSONObject()
        root.put("challenge", base64UrlEncodeNoPad(challenge))
        root.put("rpId", rpId)
        root.put("userVerification", if (requireUv) "required" else "discouraged")
        // `allowCredentials` array with the single id we registered
        // against. Type `public-key` is the only level-2 value.
        val allow = JSONObject()
        allow.put("type", "public-key")
        allow.put("id", base64UrlEncodeNoPad(credentialId))
        root.put("allowCredentials", org.json.JSONArray().put(allow))
        return root.toString()
    }

    /**
     * Parsed shape of the `authenticationResponseJson` Credential
     * Manager returns. The three fields the SSH connect path needs
     * are `signature`, `authenticatorData`, and the optional
     * `userHandle`.
     */
    private data class Parsed(
        val signature: ByteArray,
        val authenticatorData: ByteArray,
        val userHandle: ByteArray?,
    )

    private fun parseAssertionResponse(json: String): Parsed {
        val obj = JSONObject(json)
        val response = obj.getJSONObject("response")
        val sig = base64UrlDecode(response.getString("signature"))
        val authData = base64UrlDecode(response.getString("authenticatorData"))
        val userHandle = if (response.has("userHandle") && !response.isNull("userHandle")) {
            val raw = response.getString("userHandle")
            if (raw.isEmpty()) null else base64UrlDecode(raw)
        } else null
        return Parsed(sig, authData, userHandle)
    }

    private fun base64UrlEncodeNoPad(bytes: ByteArray): String {
        return Base64.encodeToString(
            bytes,
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        )
    }

    private fun base64UrlDecode(s: String): ByteArray {
        return Base64.decode(s, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }

    /**
     * Map a Credential Manager exception to one of the tags the Rust
     * side routes. Three signals are consulted in order: the typed
     * subclass, the stable `e.type` string (androidx.credentials 1.3
     * documents these under `android.credentials.GetCredentialException`
     * and its subclasses), and finally the human-readable `e.message`.
     *
     * Trap the message-keyword pass guards against: Credential Manager
     * docs note that **transport failures** (NFC dropout mid-CTAP,
     * Bluetooth disconnect on a security-key handshake, USB cable
     * unplugged) surface as the base `GetCredentialException` with a
     * descriptive message rather than a dedicated subclass. Tagging
     * those as `"other"` is wrong — the Rust retry heuristics treat
     * `"other"` as terminal and refuse to retry, while `"transport"`
     * is the right tag for "transient — try again". Invariant: any
     * base-class exception whose message names a transport-layer
     * disconnect must emit `"transport"`, never `"other"`.
     */
    private fun classifyCredentialException(e: GetCredentialException): String {
        if (e is GetCredentialInterruptedException) return "transport"
        val type = e.type.lowercase()
        when {
            type.contains("cancel") -> return "cancelled"
            type.contains("timeout") -> return "timeout"
            type.contains("interrupt") -> return "transport"
            type.contains("pin") -> return "wrong-pin"
            type.contains("no_credential") -> return "no-credential"
        }
        val msg = e.message?.lowercase() ?: return "other"
        return when {
            msg.contains("transport") -> "transport"
            msg.contains("connection lost") -> "transport"
            msg.contains("lost connection") -> "transport"
            msg.contains("disconnected") -> "transport"
            msg.contains("interrupted") -> "transport"
            msg.contains("communication") -> "transport"
            msg.contains("timeout") -> "timeout"
            else -> "other"
        }
    }

    @JvmStatic
    private external fun nativeOnAssertion(
        reqId: Long,
        signature: ByteArray,
        authenticatorData: ByteArray,
        userHandle: ByteArray,
    )

    @JvmStatic
    private external fun nativeOnFailure(
        reqId: Long,
        reasonTag: String,
        detail: String,
    )
}
