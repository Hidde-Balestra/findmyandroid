package nl.hiddebalestra.location_bridge

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Deliberately talks to Android's built-in [LocationManager] (GPS_PROVIDER /
 * NETWORK_PROVIDER) instead of any Play-Services-backed fused location API,
 * so this app works on devices without Google Play Services / microG.
 *
 * Registered as a real Flutter plugin (not an ad-hoc Activity method channel)
 * so it also attaches to the headless engine flutter_background_service runs
 * for the periodic background check-in, not just the foreground UI engine.
 */
class LocationBridgePlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "nl.hiddebalestra.location_bridge/location")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasLocationPermission())
            "getCurrentLocation" -> {
                val timeoutMs = (call.argument<Int>("timeoutMs") ?: 20_000).toLong()
                getCurrentLocation(timeoutMs, result)
            }
            "isLocationEnabled" -> result.success(isLocationEnabled())
            else -> result.notImplemented()
        }
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION)
        return fine == PackageManager.PERMISSION_GRANTED || coarse == PackageManager.PERMISSION_GRANTED
    }

    private fun isLocationEnabled(): Boolean {
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    /**
     * Requests a single fresh fix from whichever enabled provider replies
     * first (GPS and/or network), falling back to the last known location of
     * either provider if no fresh fix arrives within [timeoutMs].
     */
    private fun getCurrentLocation(timeoutMs: Long, result: Result) {
        if (!hasLocationPermission()) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }

        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers =
            listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
                .filter { locationManager.isProviderEnabled(it) }

        if (providers.isEmpty()) {
            val fallback = bestLastKnown(locationManager)
            if (fallback != null) {
                result.success(fallback.toMap())
            } else {
                result.error("PROVIDER_DISABLED", "No location provider is enabled", null)
            }
            return
        }

        val delivered = AtomicBoolean(false)
        val handler = android.os.Handler(Looper.getMainLooper())
        val listeners = mutableMapOf<String, LocationListener>()

        fun finish(location: Location?) {
            if (!delivered.compareAndSet(false, true)) return
            listeners.forEach { (provider, listener) ->
                try {
                    locationManager.removeUpdates(listener)
                } catch (_: SecurityException) {
                }
            }
            handler.post {
                if (location != null) {
                    result.success(location.toMap())
                } else {
                    val fallback = bestLastKnown(locationManager)
                    if (fallback != null) {
                        result.success(fallback.toMap())
                    } else {
                        result.error("TIMEOUT", "No location fix within timeout", null)
                    }
                }
            }
        }

        providers.forEach { provider ->
            val listener =
                object : LocationListener {
                    override fun onLocationChanged(location: Location) = finish(location)

                    @Deprecated("Deprecated in Java")
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

                    override fun onProviderEnabled(provider: String) {}

                    override fun onProviderDisabled(provider: String) {}
                }
            listeners[provider] = listener
            try {
                locationManager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
            } catch (_: SecurityException) {
            }
        }

        handler.postDelayed({ finish(null) }, timeoutMs)
    }

    private fun bestLastKnown(locationManager: LocationManager): Location? {
        return listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .mapNotNull {
                try {
                    locationManager.getLastKnownLocation(it)
                } catch (_: SecurityException) {
                    null
                }
            }
            .maxByOrNull { it.time }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}

private fun Location.toMap(): Map<String, Any?> =
    mapOf(
        "latitude" to latitude,
        "longitude" to longitude,
        "accuracy" to if (hasAccuracy()) accuracy.toDouble() else null,
        "altitude" to if (hasAltitude()) altitude else null,
        "speed" to if (hasSpeed()) speed.toDouble() else null,
        "timestamp" to time,
        "provider" to provider,
    )
