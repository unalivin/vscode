package dev.sonixdevs.kodra

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * GitHub OAuth Device Flow (RFC 8628), used because an installed APK cannot keep a
 * client secret. The client ID comes from `local.properties` at build time and is
 * never a secret on its own; the resulting token is encrypted with the Android
 * Keystore by [GithubAuth] and never crosses the WebView bridge.
 *
 * The flow is asynchronous: [start] returns immediately so the workbench message
 * handler is not blocked on the network, and progress is surfaced through
 * notifications (the user code must stay visible while the user types it in a
 * browser, which a workbench toast cannot guarantee).
 */
object DeviceAuthFlow {
    private const val TAG = "KodraAuth"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val inFlight = AtomicBoolean(false)

    data class DeviceCode(
        val deviceCode: String,
        val userCode: String,
        val verificationUri: String,
        val verificationUriComplete: String?,
        val interval: Long,
        val expiresIn: Long
    )
    data class TokenResponse(val accessToken: String, val tokenType: String, val scope: String)

    fun requestDeviceCode(clientId: String): DeviceCode {
        val body = "client_id=${enc(clientId)}&scope=${enc("repo read:user")}"
        val json = post("https://github.com/login/device/code", body, "application/json")
        val o = JSONObject(json)
        return DeviceCode(
            o.getString("device_code"), o.getString("user_code"),
            o.getString("verification_uri"), o.optString("verification_uri_complete", null),
            o.optLong("interval", 5), o.optLong("expires_in", 900)
        )
    }

    suspend fun pollForToken(clientId: String, deviceCode: String, intervalSec: Long, expiresInSec: Long): TokenResponse {
        val deadline = System.currentTimeMillis() + expiresInSec * 1000
        val bodyBase = "client_id=${enc(clientId)}&device_code=${enc(deviceCode)}&grant_type=${enc("urn:ietf:params:oauth:grant-type:device_code")}"
        while (System.currentTimeMillis() < deadline) {
            delay(intervalSec * 1000)
            val json = post("https://github.com/login/oauth/access_token", bodyBase, "application/json")
            val o = JSONObject(json)
            if (o.has("access_token")) {
                return TokenResponse(o.getString("access_token"), o.optString("token_type","bearer"), o.optString("scope",""))
            }
            val err = o.optString("error","")
            if (err == "authorization_pending") continue
            if (err == "slow_down") { delay(5000); continue }
            if (err == "expired_token" || err == "unsupported_grant_type") throw IllegalStateException("Device flow $err")
            if (err.isNotEmpty()) throw IllegalStateException("Device flow error: $err - $json")
        }
        throw IllegalStateException("Device flow timed out")
    }

    /**
     * Starts the flow and returns at once.
     *
     * @return `{"status":"started"}` so the caller can tell "sign-in begun" from
     *   "already running" or "no client id".
     */
    fun start(context: Context, clientId: String): JSONObject {
        val app = context.applicationContext
        if (!inFlight.compareAndSet(false, true)) {
            return JSONObject().put("status", "in_progress")
        }
        val title = app.getString(R.string.auth_notification_title)
        scope.launch {
            try {
                val code = requestDeviceCode(clientId)
                NotificationHelper.showAuth(
                    app,
                    title,
                    app.getString(R.string.auth_notification_code, code.userCode)
                )
                openVerification(app, code)
                val token = pollForToken(clientId, code.deviceCode, code.interval, code.expiresIn)
                GithubAuth.storeToken(app, token.accessToken)
                GitBridge.configure(app)
                NotificationHelper.showAuth(
                    app,
                    title,
                    app.getString(R.string.auth_notification_success)
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // The message can carry the OAuth error code, never the token: the token
                // response is only parsed into [TokenResponse] on the success path.
                Log.w(TAG, "Device flow failed: ${e.message}")
                NotificationHelper.showAuth(
                    app,
                    title,
                    app.getString(R.string.auth_notification_failure, e.message ?: "")
                )
            } finally {
                inFlight.set(false)
            }
        }
        return JSONObject().put("status", "started")
    }

    fun openVerification(context: Context, deviceCode: DeviceCode) {
        val uri = deviceCode.verificationUriComplete?.let { Uri.parse(it) } ?: Uri.parse(deviceCode.verificationUri)
        context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
    private fun post(url: String, body: String, accept: String): String {
        val c = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            setRequestProperty("Accept", accept)
            setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        }
        c.outputStream.use { it.write(body.toByteArray()) }
        val code = c.responseCode
        val stream = if (code in 200..299) c.inputStream else c.errorStream
        return stream.bufferedReader().readText()
    }
}
