package nl.hiddebalestra.camera_bridge

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Captures a single JPEG still frame from the front camera using Android's
 * Camera2 API directly, deliberately bypassing the official `camera` Flutter
 * plugin.
 *
 * Why: `camera`'s Android implementation (camera_android_camerax) always
 * requires a live Activity to check/request camera permission and throws
 * `IllegalStateException` otherwise -- even when permission is already
 * granted (see `SystemServicesManager.requestCameraPermissions`). That makes
 * it unusable from `flutter_background_service`'s headless isolate, which is
 * exactly where the lock-screen security-snapshot trigger runs. Camera2
 * itself has no such requirement: opening a camera and capturing a frame only
 * needs a `Context` (an Application Context is enough) and the CAMERA runtime
 * permission already granted -- this class never attempts to request that
 * permission itself, since (like the rest of this app's permission model)
 * that only ever happens via the normal in-app Settings flow.
 *
 * Every callback below arrives on [backgroundHandler]'s single-threaded
 * looper, including the timeout -- so [finish] never races itself and needs
 * no separate synchronization beyond the [finished] guard.
 */
class FrontCameraCapturer(private val context: Context) {
    companion object {
        private const val CAPTURE_TIMEOUT_MS = 10_000L

        /** Keeps the encrypted upload small -- this is a security-log
         * snapshot, not a high-resolution photo. Picks the smallest
         * available JPEG size that's still large enough to be recognizable. */
        private const val MIN_DIMENSION = 480
    }

    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private var imageReader: ImageReader? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private val finished = AtomicBoolean(false)
    private var onResult: ((Result<ByteArray?>) -> Unit)? = null

    /** Callback runs on [backgroundHandler]. Result is `null` if there's
     * simply no camera available; a failure (permission denied, camera
     * opened but capture failed, timeout) completes with a [Result.failure]
     * instead of a silent null, so the caller can log the real cause. */
    fun capture(onResult: (Result<ByteArray?>) -> Unit) {
        this.onResult = onResult

        // Plain framework API rather than androidx.core's ContextCompat, to
        // avoid pulling in a dependency this module otherwise has no need
        // for -- checkPermission() reflects the current runtime grant on
        // API 23+ and is always PERMISSION_GRANTED pre-23, matching that
        // era's install-time permission model.
        if (context.packageManager.checkPermission(Manifest.permission.CAMERA, context.packageName) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            finish(Result.failure(IllegalStateException("Camera permission not granted")))
            return
        }

        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = findFrontCameraId(cameraManager)
        if (cameraId == null) {
            finish(Result.success(null))
            return
        }

        try {
            startBackgroundThread()
            val handler = backgroundHandler!!

            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val (width, height) = pickJpegSize(characteristics)
            val reader = ImageReader.newInstance(width, height, ImageFormat.JPEG, 1)
            imageReader = reader
            reader.setOnImageAvailableListener({ onImageAvailable(it) }, handler)

            handler.postDelayed({ finish(Result.failure(IllegalStateException("Camera capture timed out"))) }, CAPTURE_TIMEOUT_MS)

            cameraManager.openCamera(cameraId, cameraStateCallback, handler)
        } catch (e: Exception) {
            finish(Result.failure(e))
        }
    }

    private fun findFrontCameraId(cameraManager: CameraManager): String? {
        val ids = cameraManager.cameraIdList
        val front = ids.firstOrNull { id ->
            cameraManager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) ==
                CameraCharacteristics.LENS_FACING_FRONT
        }
        return front ?: ids.firstOrNull()
    }

    /** Camera2 only reports discrete supported JPEG sizes, never arbitrary
     * ones -- picks the smallest that meets [MIN_DIMENSION] on its shorter
     * side, falling back to the largest available if every size is smaller
     * than that (some low-end front cameras only offer small sizes). */
    private fun pickJpegSize(characteristics: CameraCharacteristics): Pair<Int, Int> {
        val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) as StreamConfigurationMap
        val sizes = map.getOutputSizes(ImageFormat.JPEG)
        val sorted = sizes.sortedBy { it.width.toLong() * it.height }
        val adequate = sorted.firstOrNull { minOf(it.width, it.height) >= MIN_DIMENSION }
        val chosen = adequate ?: sorted.last()
        return chosen.width to chosen.height
    }

    private val cameraStateCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(camera: CameraDevice) {
            cameraDevice = camera
            try {
                val reader = imageReader!!
                camera.createCaptureSession(listOf(reader.surface), captureSessionCallback, backgroundHandler)
            } catch (e: Exception) {
                finish(Result.failure(e))
            }
        }

        override fun onDisconnected(camera: CameraDevice) {
            finish(Result.failure(IllegalStateException("Camera disconnected before capture completed")))
        }

        override fun onError(camera: CameraDevice, error: Int) {
            finish(Result.failure(IllegalStateException("Camera device error: $error")))
        }
    }

    private val captureSessionCallback = object : CameraCaptureSession.StateCallback() {
        override fun onConfigured(session: CameraCaptureSession) {
            captureSession = session
            try {
                val camera = cameraDevice!!
                val reader = imageReader!!
                val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE).apply {
                    addTarget(reader.surface)
                }
                session.capture(request.build(), captureCallback, backgroundHandler)
            } catch (e: Exception) {
                finish(Result.failure(e))
            }
        }

        override fun onConfigureFailed(session: CameraCaptureSession) {
            finish(Result.failure(IllegalStateException("Camera capture session configuration failed")))
        }
    }

    private val captureCallback = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureFailed(
            session: CameraCaptureSession,
            request: CaptureRequest,
            failure: CaptureFailure,
        ) {
            finish(Result.failure(IllegalStateException("Camera capture failed: reason=${failure.reason}")))
        }
        // Success is handled by the ImageReader's OnImageAvailableListener,
        // not here -- the capture completing doesn't guarantee the image
        // buffer is ready to read yet.
    }

    private fun onImageAvailable(reader: ImageReader) {
        var image: Image? = null
        try {
            image = reader.acquireLatestImage() ?: return
            val buffer = image.planes[0].buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            finish(Result.success(bytes))
        } catch (e: Exception) {
            finish(Result.failure(e))
        } finally {
            image?.close()
        }
    }

    /** Safe to call more than once (multiple callback paths can race to
     * report an outcome) and from a partially-set-up state (e.g. permission
     * denied before anything was opened) -- every field it touches is
     * nullable and closed defensively. */
    private fun finish(result: Result<ByteArray?>) {
        if (!finished.compareAndSet(false, true)) return

        captureSession?.close()
        cameraDevice?.close()
        imageReader?.close()
        backgroundHandler?.removeCallbacksAndMessages(null)
        backgroundThread?.quitSafely()

        captureSession = null
        cameraDevice = null
        imageReader = null
        backgroundHandler = null
        backgroundThread = null

        onResult?.invoke(result)
        onResult = null
    }

    private fun startBackgroundThread() {
        val thread = HandlerThread("CameraBridgeCapture")
        thread.start()
        backgroundThread = thread
        backgroundHandler = Handler(thread.looper)
    }
}
