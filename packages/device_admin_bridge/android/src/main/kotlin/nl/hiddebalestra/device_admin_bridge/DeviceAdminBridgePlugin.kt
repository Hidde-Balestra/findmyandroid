package nl.hiddebalestra.device_admin_bridge

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Not a general-purpose plugin: it's tightly coupled to this one app's own
 * `SecurityDeviceAdminReceiver` (declared in the app's own AndroidManifest,
 * not here — a DeviceAdminReceiver has to be part of the app itself).
 * Implements ActivityAware only so [requestActivation] can launch Android's
 * "Activate device administrator?" screen from a real Activity context;
 * every other method works from the headless background-service engine too,
 * since this is registered as a real Flutter plugin rather than an
 * Activity-only method channel.
 */
class DeviceAdminBridgePlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private lateinit var adminComponent: ComponentName
    private var activity: Activity? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        adminComponent = ComponentName(
            appContext.packageName,
            "${appContext.packageName}.SecurityDeviceAdminReceiver",
        )
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "nl.hiddebalestra.device_admin_bridge/device_admin")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val devicePolicyManager = appContext.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

        when (call.method) {
            "isActive" -> result.success(devicePolicyManager.isAdminActive(adminComponent))

            "requestActivation" -> {
                val currentActivity = activity
                if (currentActivity == null) {
                    result.error("NO_ACTIVITY", "requestActivation() requires the app to be in the foreground", null)
                    return
                }
                val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                    putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                    putExtra(
                        DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                        "Lets Find My Android detect failed lock-screen unlock attempts, to log a security " +
                            "snapshot (photo + location) the same way it already does for failed in-app logins.",
                    )
                }
                currentActivity.startActivity(intent)
                result.success(null)
            }

            "setThreshold" -> {
                val threshold = (call.argument<Int>("threshold")) ?: 1
                DeviceAdminPrefs.setThreshold(appContext, threshold)
                result.success(null)
            }

            "consumePendingTrigger" -> result.success(DeviceAdminPrefs.consumePendingTrigger(appContext))

            "setDebugNotifyEnabled" -> {
                val enabled = (call.argument<Boolean>("enabled")) ?: false
                DeviceAdminPrefs.setDebugNotifyEnabled(appContext, enabled)
                result.success(null)
            }

            "sendTestNotification" -> {
                DebugNotifier.notifyFailedAttemptDetected(appContext)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
