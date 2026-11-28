package dev.sonixdevs.kodra

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Foreground service that owns the local Node server and PTY tree.
 * Activity binds to get bound host/port/token for WebView.
 *
 * Stop: notification action → stopSelf() → onDestroy() kills node + releases wakeLock.
 * Reconnect: onBind returns same binder; server is not restarted on config change.
 */
class KodraService : Service() {
    private val job = SupervisorJob()
    private val scope = CoroutineScope(job + Dispatchers.IO)
    private var wakeLock: PowerManager.WakeLock? = null
    private var server: ServerProcess? = null
    private var bound: ServerProcess.Bound? = null

    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        /** Host/port once the server has bound; null while it is still starting. */
        fun bound(): ServerProcess.Bound? = bound.takeIf { server?.isAlive() == true }
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Kodra::server")
            .apply { setReferenceCounted(false) }

        startForeground(NOTIF_ID, buildNotification("Starting…", 0))

        scope.launch {
            try {
                val layout = BootstrapInstaller.installIfNeeded(this@KodraService)
                val token = TokenManager.generate()
                val tf = TokenManager.writeToken(this@KodraService, token)
                val srv = ServerProcess(this@KodraService)
                server = srv
                val b = srv.start(tf, layout)
                bound = b
                // The bootstrap git must know the shared project folder before the
                // built-in Git extension starts asking it questions.
                GitBridge.configure(this@KodraService, layout)
                wakeLock?.acquire(10 * 60 * 60 * 1000L /*10h*/)
                startForeground(NOTIF_ID, buildNotification("Kodra is running", b.port))
                // Broadcast to Activity (if bound, it also polls)
                sendBroadcast(Intent(ACTION_READY).apply {
                    setPackage(packageName)
                    putExtra(EXTRA_PORT, b.port)
                    putExtra(EXTRA_HOST, b.host)
                })
            } catch (e: ServerProcess.BootstrapMissingException) {
                startForeground(NOTIF_ID, buildNotification("Bootstrap missing — see logs", 0))
            } catch (e: Exception) {
                startForeground(NOTIF_ID, buildNotification("Server failed: ${e.message}", 0))
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Ensure foreground even if system kills and recreates (we restart server in onCreate)
        return START_STICKY
    }

    override fun onDestroy() {
        server?.stop()
        server = null
        bound = null
        if (wakeLock?.isHeld == true) wakeLock?.release()
        // Cancelling the parent job also stops an in-flight bootstrap install or a
        // server hand-shake loop; the scope must not outlive the service.
        job.cancel()
        super.onDestroy()
    }

    private fun buildNotification(text: String, port: Int): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, KodraService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, NotificationHelper.CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(if (port != 0) getString(R.string.notification_text, "127.0.0.1:$port") else text)
            .setOngoing(true)
            .setContentIntent(openIntent)
            .addAction(NotificationCompat.Action.Builder(
                android.R.drawable.ic_menu_close_clear_cancel,
                getString(R.string.notification_stop), stopIntent
            ).build())
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    companion object {
        const val NOTIF_ID = 1001
        const val ACTION_READY = "dev.sonixdevs.kodra.READY"
        const val ACTION_STOP = "dev.sonixdevs.kodra.STOP"
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"

        fun start(context: Context) {
            val i = Intent(context, KodraService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i)
            else context.startService(i)
        }
    }
}
