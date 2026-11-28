package dev.sonixdevs.kodra

import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.view.KeyEvent
import android.view.ViewGroup
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

/**
 * Single-Activity, full-screen WebView. No Electron — it renders the browser workbench
 * served by the local REH-web server on `http://127.0.0.1:<port>/?tkn=<token>`.
 *
 * Origin lock: only the loopback host may load in the WebView; every other navigation
 * is handed to an Android Intent (browser/mail/etc.) and never rendered in-app.
 *
 * Immersive mode defaults to on (see [SETTINGS_PREFS]); the setting is read here so a
 * change in [SettingsActivity] applies on the next launch.
 */
class MainActivity : AppCompatActivity() {
    private var webView: WebView? = null
    private var localBinder: KodraService.LocalBinder? = null
    private var pendingLoad = false

    private lateinit var filePicker: FilePickerBridge
    private lateinit var permissionHandler: PermissionHandler
    private lateinit var workbenchBridge: WorkbenchBridge

    /** True once a load has been started, so the retry loop stops re-issuing loadUrl. */
    private var loadAttempted = false

    private val serviceConn = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            localBinder = binder as? KodraService.LocalBinder
            maybeLoad()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            localBinder = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        filePicker = FilePickerBridge(this)
        permissionHandler = PermissionHandler(this)

        WindowCompat.setDecorFitsSystemWindows(window, false)

        val web = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            // The workbench must reach only its own loopback origin; file:// and
            // content:// access would widen that to the whole device.
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.mediaPlaybackRequiresUserGesture = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                importantForAutofill = android.view.View.IMPORTANT_FOR_AUTOFILL_NO
            }
            if (BuildConfig.ENABLE_WEBVIEW_DEBUGGING) {
                WebView.setWebContentsDebuggingEnabled(true)
            }
            webViewClient = KodraWebClient()
        }
        webView = web
        workbenchBridge = WorkbenchBridge(this, web, filePicker)

        val extraKeys = ExtraKeysView(this).also { it.attach(web) }

        val container = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            addView(
                web,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
            addView(
                extraKeys,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply { gravity = android.view.Gravity.BOTTOM }
            )
        }
        setContentView(container)

        val immersive = getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_IMMERSIVE, true)
        InsetsBridge.apply(this, web, immersive)

        // Web messages are provided by the updatable WebView provider, not by the OS
        // version, so the feature has to be probed rather than SDK-checked.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(
                web,
                KodraBridgeWhiteList.CHANNEL,
                setOf("http://127.0.0.1:*"),
                workbenchBridge.listener()
            )
        }

        permissionHandler.requestNotificationPermission()
        permissionHandler.requestAllFilesAccess()

        KodraService.start(this)
        bindService(Intent(this, KodraService::class.java), serviceConn, Context.BIND_AUTO_CREATE)

        // The server needs a moment to bind; the binder callback normally wins the race.
        web.postDelayed({ maybeLoad() }, LOAD_RETRY_MS)
    }

    override fun onStart() {
        super.onStart()
        if (webView?.url == null) maybeLoad()
    }

    /**
     * Loads the workbench once the service has published a bound port. The token is read
     * from the file the service wrote, so a WebView recreated after process death still
     * targets the running server instead of a fresh one.
     */
    private fun maybeLoad() {
        val view = webView ?: return
        val bound = localBinder?.bound() ?: return
        if (loadAttempted) return
        val token = TokenManager.readToken(this) ?: return
        loadAttempted = true
        view.loadUrl("http://${bound.host}:${bound.port}/?tkn=${Uri.encode(token)}")
    }

    override fun onDestroy() {
        runCatching { unbindService(serviceConn) }
        webView?.destroy()
        webView = null
        super.onDestroy()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && webView?.canGoBack() == true) {
            webView?.goBack()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    inner class KodraWebClient : WebViewClient() {
        @SuppressLint("QueryPermissionsNeeded")
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val url = request.url
            // Loopback is the workbench itself; blob:/data: are generated by it.
            if (url.host == LOOPBACK_HOST) return false
            if (url.scheme == "blob" || url.scheme == "data") return false
            openExternally(url)
            return true
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError
        ) {
            // Only the top-level document matters here; sub-resource failures are the
            // workbench's business and must not replace the page with a toast.
            if (!request.isForMainFrame) return
            Toast.makeText(
                this@MainActivity,
                getString(R.string.err_server_unreachable, error.description),
                Toast.LENGTH_LONG
            ).show()
        }

        private fun openExternally(url: Uri) {
            runCatching {
                startActivity(Intent(Intent.ACTION_VIEW, url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }.onFailure {
                Toast.makeText(
                    this@MainActivity,
                    getString(R.string.err_no_browser, url.toString()),
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
    }

    companion object {
        const val LOOPBACK_HOST = "127.0.0.1"
        const val SETTINGS_PREFS = "kodra_settings"
        const val KEY_IMMERSIVE = "immersive"
        private const val LOAD_RETRY_MS = 1200L
    }
}
