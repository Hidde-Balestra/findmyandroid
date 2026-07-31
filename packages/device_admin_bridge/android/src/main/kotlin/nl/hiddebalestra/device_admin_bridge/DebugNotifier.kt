package nl.hiddebalestra.device_admin_bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * Posts an immediate, plain notification confirming a failed lock-screen
 * unlock attempt was observed -- a debug aid (Settings > Debug), entirely
 * separate from the actual security-snapshot pipeline, which only reacts
 * once the configured threshold is crossed and only after the next
 * background poll picks up the pending flag. Lets the user verify
 * SecurityDeviceAdminReceiver.onPasswordFailed() is actually firing on
 * their device without waiting on any of that.
 */
object DebugNotifier {
    private const val CHANNEL_ID = "device_admin_debug"
    private const val NOTIFICATION_ID = 9001

    fun notifyFailedAttemptDetected(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Security debug", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Confirms a failed lock-screen unlock attempt was detected (debug only)."
                },
            )
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Failed lock-screen attempt detected")
            .setContentText("Debug: onPasswordFailed() just fired on this device.")
            .setAutoCancel(true)
            .build()

        manager.notify(NOTIFICATION_ID, notification)
    }
}
