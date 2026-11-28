package dev.sonixdevs.kodra

import android.net.Uri
import android.webkit.WebView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import org.json.JSONObject

/**
 * WebMessagePort bridge — the only script-visible surface of the app.
 *
 * The workbench calls `window.kodra.postMessage(JSON.stringify({id, method, params}))`
 * and receives `{id, result}` or `{id, error}` back. Every method must be present in
 * [KodraBridgeWhiteList]; anything else is refused without touching a platform API,
 * so a compromised workbench page cannot reach arbitrary device functionality.
 *
 * Listener semantics come from AndroidX WebKit (`WebViewCompat.addWebMessageListener`);
 * the platform `WebView` class has no such API, and the feature is offered by the
 * updatable WebView provider rather than by the OS version.
 */
class WorkbenchBridge(
    private val activity: MainActivity,
    private val webView: WebView,
    private val filePicker: FilePickerBridge
) {
    fun listener(): WebViewCompat.WebMessageListener =
        WebViewCompat.WebMessageListener { _, message: WebMessageCompat, _: Uri?, _: Boolean, reply: JavaScriptReplyProxy ->
            handle(message.data ?: "", reply)
        }

    private fun handle(message: String, reply: JavaScriptReplyProxy) {
        val request = runCatching { JSONObject(message) }.getOrElse {
            send(reply, errorResponse("", "malformed request"))
            return
        }
        val id = request.optString("id", "")
        val method = request.optString("method", "")
        if (method !in KodraBridgeWhiteList.allowedMethods) {
            send(reply, errorResponse(id, "unsupported method"))
            return
        }
        val params = request.optJSONObject("params")
        runCatching {
            when (method) {
                "clipboard.readText" ->
                    send(reply, resultResponse(id, ClipboardBridge.readText(activity) ?: ""))
                "clipboard.writeText" -> {
                    ClipboardBridge.writeText(activity, params?.optString("text", "") ?: "")
                    send(reply, resultResponse(id, true))
                }
                // The picker answers asynchronously, so the reply is posted from its callback.
                "dialog.openFile" -> filePicker.pickFile { res -> replyPicked(id, res, reply) }
                "dialog.openFolder" -> filePicker.pickFolder { res -> replyPicked(id, res, reply) }
                "auth.githubDeviceFlow" -> {
                    val clientId = GithubAuth.getClientId(activity)
                    if (clientId == null) send(reply, errorResponse(id, "no GitHub OAuth client id configured"))
                    else send(reply, resultResponse(id, DeviceAuthFlow.start(activity, clientId)))
                }
                // The token itself never crosses the bridge: the workbench only needs to
                // know whether an account is signed in and must use the credential helper.
                "auth.getToken" -> send(reply, resultResponse(id, GithubAuth.loadToken(activity) != null))
                "auth.clearToken" -> {
                    GithubAuth.clearToken(activity)
                    send(reply, resultResponse(id, true))
                }
                "service.stop" -> {
                    activity.stopService(android.content.Intent(activity, KodraService::class.java))
                    send(reply, resultResponse(id, true))
                }
                "service.reconnect" -> {
                    KodraService.start(activity)
                    send(reply, resultResponse(id, true))
                }
                "insets.setImmersive" -> {
                    val enabled = params?.optBoolean("enabled", true) ?: true
                    activity.runOnUiThread { InsetsBridge.setImmersive(activity, webView, enabled) }
                    send(reply, resultResponse(id, true))
                }
                else -> send(reply, errorResponse(id, "unsupported method"))
            }
        }.onFailure { e ->
            send(reply, errorResponse(id, e.message ?: e::class.java.simpleName))
        }
    }

    private fun replyPicked(id: String, result: Result<String>, reply: JavaScriptReplyProxy) {
        result.fold(
            onSuccess = { send(reply, resultResponse(id, it)) },
            onFailure = { send(reply, errorResponse(id, it.message ?: "picker failed")) }
        )
    }

    private fun resultResponse(id: String, value: Any): String =
        JSONObject().put("id", id).put("result", value).toString()

    private fun errorResponse(id: String, message: String): String =
        JSONObject().put("id", id).put("error", message).toString()

    private fun send(reply: JavaScriptReplyProxy, json: String) {
        // The page can be torn down while a picker is open; posting then throws.
        runCatching { reply.postMessage(json) }
    }
}
