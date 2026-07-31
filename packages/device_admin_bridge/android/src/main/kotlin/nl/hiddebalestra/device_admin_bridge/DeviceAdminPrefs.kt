package nl.hiddebalestra.device_admin_bridge

import android.content.Context

/**
 * Native-only bookkeeping for the lock-screen failed-attempt counter and
 * the current security-snapshot threshold, kept in its own SharedPreferences
 * file deliberately separate from Dart's `shared_preferences` storage:
 * `SecurityDeviceAdminReceiver.onPasswordFailed()` can fire with no Flutter
 * engine/isolate alive at all to hand a result off to, so all of the actual
 * counting logic has to live here rather than in Dart. The Dart side only
 * ever reads the resulting "pending trigger" flag, polled from the
 * background check-in (see DeviceAdminBridge.consumePendingLockscreenTrigger
 * and where it's called from for the resulting latency trade-off), and
 * pushes the threshold value down via [setThreshold] whenever it changes.
 */
object DeviceAdminPrefs {
    private const val PREFS_NAME = "security_device_admin_prefs"
    private const val KEY_FAILED_COUNT = "failed_count"
    private const val KEY_THRESHOLD = "threshold"
    private const val KEY_PENDING_TRIGGER = "pending_trigger"
    private const val KEY_DEBUG_NOTIFY_ENABLED = "debug_notify_enabled"

    /** 0 disables the feature entirely, matching the Dart-side default. */
    private const val DEFAULT_THRESHOLD = 1

    /** Returns true if this attempt just crossed the threshold (i.e. the
     * pending-trigger flag was newly set) -- the caller uses that to decide
     * whether to also push an immediate notification, rather than relying
     * solely on the next background poll. */
    fun recordFailedUnlockAttempt(context: Context): Boolean {
        val prefs = prefs(context)
        val threshold = prefs.getInt(KEY_THRESHOLD, DEFAULT_THRESHOLD)
        if (threshold <= 0) return false

        val count = prefs.getInt(KEY_FAILED_COUNT, 0) + 1
        if (count >= threshold) {
            prefs.edit()
                .putInt(KEY_FAILED_COUNT, 0)
                .putBoolean(KEY_PENDING_TRIGGER, true)
                .apply()
            return true
        }
        prefs.edit().putInt(KEY_FAILED_COUNT, count).apply()
        return false
    }

    fun setThreshold(context: Context, threshold: Int) {
        prefs(context).edit().putInt(KEY_THRESHOLD, threshold).apply()
    }

    /** Reads and atomically clears the pending-trigger flag. */
    fun consumePendingTrigger(context: Context): Boolean {
        val prefs = prefs(context)
        val pending = prefs.getBoolean(KEY_PENDING_TRIGGER, false)
        if (pending) prefs.edit().putBoolean(KEY_PENDING_TRIGGER, false).apply()
        return pending
    }

    fun setDebugNotifyEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_DEBUG_NOTIFY_ENABLED, enabled).apply()
    }

    /** Debug aid, see DeviceAdminBridge.setDebugNotifyEnabled -- unrelated to [recordFailedUnlockAttempt]'s threshold logic. */
    fun isDebugNotifyEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_DEBUG_NOTIFY_ENABLED, false)

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
