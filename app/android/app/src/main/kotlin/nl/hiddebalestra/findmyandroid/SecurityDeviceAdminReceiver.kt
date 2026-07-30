package nl.hiddebalestra.findmyandroid

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import nl.hiddebalestra.device_admin_bridge.DeviceAdminPrefs

/**
 * Notified by the OS when this device's lock-screen credential (PIN/pattern/
 * password) is entered incorrectly — the only way a regular app can observe
 * that at all, and only once the user has explicitly activated this app as
 * a Device Administrator via Android's own system screen (see
 * DeviceAdminBridgePlugin.requestActivation and Settings > Security
 * snapshot). All counting/threshold logic is delegated to [DeviceAdminPrefs]
 * (in the device_admin_bridge plugin) rather than handled here directly,
 * since it needs to work with no Flutter isolate necessarily running at the
 * moment of a failed unlock attempt.
 */
class SecurityDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onPasswordFailed(context: Context, intent: Intent) {
        super.onPasswordFailed(context, intent)
        DeviceAdminPrefs.recordFailedUnlockAttempt(context)
    }
}
