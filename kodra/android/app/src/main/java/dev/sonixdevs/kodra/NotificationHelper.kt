package dev.sonixdevs.kodra

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

object NotificationHelper {
    /** Low importance: the server runs continuously and must not buzz on every start. */
    const val CHANNEL_ID = "kodra_server"

    /** Default importance: the sign-in user code has to stay visible and copyable. */
    const val AUTH_CHANNEL_ID = "kodra_auth"

    const val AUTH_NOTIFICATION_ID = 1002

    fun createChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    ctx.getString(R.string.notification_channel_name),
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = ctx.getString(R.string.notification_channel_desc)
                    setShowBadge(false)
                }
            )
            nm.createNotificationChannel(
                NotificationChannel(
                    AUTH_CHANNEL_ID,
                    ctx.getString(R.string.auth_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = ctx.getString(R.string.auth_channel_desc)
                    setShowBadge(false)
                }
            )
        }
    }

    /**
     * Sign-in progress. Not ongoing: once the flow ends the user can dismiss it, and
     * the notification with the device code disappears instead of lingering as a
     * misleading "in progress" indicator.
     */
    fun showAuth(ctx: Context, title: String, text: String) {
        val open = PendingIntent.getActivity(
            ctx,
            2,
            Intent(ctx, SettingsActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(ctx, AUTH_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .build()
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        nm.notify(AUTH_NOTIFICATION_ID, notification)
    }
}
