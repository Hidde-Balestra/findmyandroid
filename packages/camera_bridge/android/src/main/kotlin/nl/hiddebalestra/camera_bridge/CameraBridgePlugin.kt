package nl.hiddebalestra.camera_bridge

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Deliberately not `ActivityAware`: unlike the official `camera` plugin,
 * capture here never needs an Activity (see FrontCameraCapturer's doc
 * comment) -- it works identically whether called from the app's own UI
 * engine or `flutter_background_service`'s headless one.
 */
class CameraBridgePlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: android.content.Context
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "nl.hiddebalestra.camera_bridge/camera")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "captureFrontPhoto" -> {
                FrontCameraCapturer(appContext).capture { outcome ->
                    // FrontCameraCapturer's callback fires on its own
                    // background thread -- MethodChannel.Result must only
                    // ever be completed on the platform (main) thread.
                    mainHandler.post {
                        outcome.fold(
                            onSuccess = { bytes -> result.success(bytes) },
                            onFailure = { error -> result.error("CAPTURE_FAILED", error.message, null) },
                        )
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
