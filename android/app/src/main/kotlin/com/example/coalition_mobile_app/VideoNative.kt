package com.example.coalition_mobile_app

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.provider.DocumentsContract
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Crop
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.SingleColorLut
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.TransformationException
import androidx.media3.transformer.TransformationResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max
import kotlin.OptIn

private const val CHANNEL_NAME = "video_native"
private const val TAG = "VideoNative"
private const val CROP_EPSILON = 1e-4f

class VideoNative(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val transformerThread = HandlerThread("VideoTransformerThread").apply { start() }
    private val transformerHandler = Handler(transformerThread.looper)
    private var transformer: Transformer? = null
    private val isDisposed = AtomicBoolean(false)
    private val frameExtractor = VideoFrameExtractor.getInstance(context)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        if (isDisposed.compareAndSet(false, true)) {
            channel.setMethodCallHandler(null)
            runOnTransformerThread {
                transformer?.cancel()
                transformer = null
            }
            executor.shutdownNow()
            transformerThread.quitSafely()
            try {
                transformerThread.join()
            } catch (ie: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (isDisposed.get()) {
            result.error("disposed", "VideoNative has been disposed", null)
            return
        }

        when (call.method) {
            "generateCoverImage" -> handleGenerateCoverImage(call, result)
            "exportEdits" -> handleExportEdits(call, result)
            "cancelExport" -> handleCancelExport(result)
            "persistUriPermission" -> handlePersistUriPermission(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleGenerateCoverImage(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        val seconds = call.argument<Double>("seconds")

        if (filePath.isNullOrBlank() || seconds == null) {
            result.error("bad_args", "Missing filePath or seconds", null)
            return
        }

        executor.execute {
            try {
                val outputPath = generateCoverImage(filePath, seconds)
                postSuccess(result, outputPath)
            } catch (t: Throwable) {
                postError(result, t)
            }
        }
    }

    private fun handleExportEdits(call: MethodCall, result: MethodChannel.Result) {
        // Defensive parsing + logging so we can see what arguments arrived from Dart.
        try {
            android.util.Log.d(TAG, "handleExportEdits: raw call.arguments=${call.arguments}")
        } catch (_: Throwable) {
        }

        // Try to read a top-level map first (some codecs decode into LinkedHashMap)
        val rawArgs = call.arguments as? Map<*, *>
        val filePath = (rawArgs?.get("filePath") as? String) ?: call.argument<String>("filePath")
        // timelineJson may be passed as a Map or as a JSON string; handle both.
        var timeline: Map<String, Any?>? = null
        val timelineRaw = rawArgs?.get("timelineJson") ?: call.argument<Any>("timelineJson")
        if (timelineRaw is Map<*, *>) {
            // Convert keys to String and preserve values as Any?
            val m = mutableMapOf<String, Any?>()
            for ((k, v) in timelineRaw) {
                m[k.toString()] = v
            }
            timeline = m
        } else if (timelineRaw is String) {
            try {
                val obj = JSONObject(timelineRaw)
                timeline = obj.toMap()
            } catch (_: Exception) {
                // leave timeline null
            }
        }
        val targetBitrate = ((rawArgs?.get("targetBitrateBps") as? Number)?.toInt()
            ?: call.argument<Number>("targetBitrateBps")?.toInt())

        if (filePath.isNullOrBlank() || timeline == null || targetBitrate == null) {
            android.util.Log.w(TAG, "Missing export arguments: filePath=${filePath}, timeline=${timeline}, targetBitrate=${targetBitrate}")
            result.error("bad_args", "Missing export arguments", null)
            return
        }

        // Log a compact preview of the parsed timeline for diagnostics.
        try {
            val preview = timeline.toString().take(200)
            android.util.Log.d(TAG, "handleExportEdits: parsed timeline preview=$preview")
        } catch (_: Throwable) {}

        executor.execute {
            try {
                val outputPath = exportEdits(filePath, timeline, targetBitrate)
                postSuccess(result, outputPath)
            } catch (t: Throwable) {
                postError(result, t)
            }
        }
    }

    private fun handleCancelExport(result: MethodChannel.Result) {
        executor.execute {
            runOnTransformerThread {
                transformer?.cancel()
                transformer = null
            }
            postSuccess(result, null)
        }
    }

    private fun handlePersistUriPermission(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrBlank()) {
            result.error("bad_args", "Missing uri", null)
            return
        }

        executor.execute {
            try {
                val uri = Uri.parse(uriString)
                val intentFlags = call.argument<Int>("flags") ?: 0
                if (uri.scheme.equals("content", ignoreCase = true)) {
                    maybeTakePersistableUriPermission(uri, intentFlags)
                }
                postSuccess(result, null)
            } catch (t: Throwable) {
                android.util.Log.w(TAG, "Failed to persist permission for $uriString", t)
                postError(result, t)
            }
        }
    }

    private fun postSuccess(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun postError(result: MethodChannel.Result, throwable: Throwable) {
        mainHandler.post {
            result.error(
                "error",
                throwable.message ?: throwable::class.java.simpleName,
                null,
            )
        }
    }

    private fun runOnTransformerThread(block: () -> Unit) {
        if (Looper.myLooper() == transformerHandler.looper) {
            block()
            return
        }

        val latch = CountDownLatch(1)
        val failure = arrayOfNulls<Throwable>(1)
        transformerHandler.post {
            try {
                block()
            } catch (t: Throwable) {
                failure[0] = t
            } finally {
                latch.countDown()
            }
        }

        try {
            latch.await()
        } catch (ie: InterruptedException) {
            Thread.currentThread().interrupt()
            throw ie
        }

        val error = failure[0]
        if (error != null) {
            throw error
        }
    }

    private fun generateCoverImage(filePath: String, seconds: Double): String {
        val frameTimeUs = (seconds * 1_000_000L).toLong()
        val parsedUri = try {
            Uri.parse(filePath)
        } catch (_: Throwable) {
            null
        }

        val bitmap = when {
            parsedUri != null && parsedUri.scheme.equals("content", ignoreCase = true) -> {
                frameExtractor.extractFrameFromUri(parsedUri, frameTimeUs)
            }
            parsedUri != null && parsedUri.scheme.equals("file", ignoreCase = true) -> {
                frameExtractor.extractFrameFromUri(parsedUri, frameTimeUs)
            }
            parsedUri != null && parsedUri.scheme.isNullOrEmpty().not() -> {
                frameExtractor.extractFrameFromUri(parsedUri, frameTimeUs)
            }
            else -> {
                frameExtractor.extractFrameFromPath(filePath, frameTimeUs)
            }
        }

        return writeBitmapToCache(bitmap)
    }

    private fun writeBitmapToCache(bitmap: Bitmap): String {
        val outputFile = createVideoTempFile(context, prefix = "cover_", suffix = ".png")
        FileOutputStream(outputFile).use { output ->
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                throw IOException("Failed to write cover image")
            }
        }
        return outputFile.absolutePath
    }

    private fun maybeTakePersistableUriPermission(uri: Uri, intentFlags: Int) {
        if ((intentFlags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) == 0) {
            return
        }
        if (!DocumentsContract.isDocumentUri(context, uri)) {
            return
        }

        try {
            context.contentResolver.takePersistableUriPermission(
                uri,
                intentFlags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION),
            )
        } catch (security: SecurityException) {
            android.util.Log.w(TAG, "Unable to persist URI permission for $uri", security)
        } catch (_: Throwable) {
        }
    }

    @OptIn(UnstableApi::class)
    private fun exportEdits(
        filePath: String,
        timeline: Map<String, Any?>,
        targetBitrate: Int,
    ): String {
        val editedMediaItem = buildEditedMediaItem(filePath, timeline)
        val outputFile = createVideoTempFile(context, prefix = "export_", suffix = ".mp4")

        val latch = CountDownLatch(1)
        var exportError: Exception? = null

        val listener = object : Transformer.Listener {
            override fun onTransformationCompleted(
                mediaItem: MediaItem,
                transformationResult: TransformationResult,
            ) {
                android.util.Log.i(TAG, "exportEdits: transformation completed for mediaItem=$mediaItem")
                latch.countDown()
            }

            override fun onTransformationError(
                mediaItem: MediaItem,
                exception: TransformationException,
            ) {
                android.util.Log.e(TAG, "exportEdits: transformation error for mediaItem=$mediaItem: ${exception.message}", exception)
                exportError = exception
                latch.countDown()
            }

            override fun onTransformationError(
                mediaItem: MediaItem,
                transformationResult: TransformationResult,
                exception: TransformationException,
            ) {
                onTransformationError(mediaItem, exception)
            }
        }

        val encoderFactory = DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(
                VideoEncoderSettings.Builder().setBitrate(targetBitrate).build(),
            )
            .build()

        var transformer: Transformer? = null
        runOnTransformerThread {
            val createdTransformer = Transformer.Builder(context)
                .setEncoderFactory(encoderFactory)
                .addListener(listener)
                .build()

            android.util.Log.i(
                TAG,
                "exportEdits: starting transformer for filePath=$filePath output=${outputFile.absolutePath} targetBitrate=$targetBitrate",
            )

            this.transformer?.cancel()
            this.transformer = createdTransformer
            createdTransformer.start(editedMediaItem, outputFile.absolutePath)
            transformer = createdTransformer
        }

        val activeTransformer = transformer
            ?: throw IllegalStateException("Transformer failed to start")

        try {
            latch.await()
        } catch (ie: InterruptedException) {
            Thread.currentThread().interrupt()
            activeTransformer.cancel()
            throw ie
        } finally {
            runOnTransformerThread {
                if (this.transformer === activeTransformer) {
                    this.transformer = null
                }
            }
        }

        exportError?.let { throw it }
        android.util.Log.i(TAG, "exportEdits: finished successfully, output=${outputFile.absolutePath}")
        return outputFile.absolutePath
    }

    @OptIn(UnstableApi::class)
    private fun buildEditedMediaItem(
        filePath: String,
        timeline: Map<String, Any?>,
    ): EditedMediaItem {
        android.util.Log.d(TAG, "buildEditedMediaItem: timeline=$timeline")
        val mediaItemBuilder = MediaItem.Builder().setUri(Uri.fromFile(File(filePath)))

        val trimMap = timeline["trim"] as? Map<*, *>
        if (trimMap != null) {
            android.util.Log.d(TAG, "buildEditedMediaItem: trimMap=$trimMap")
            val clipBuilder = MediaItem.ClippingConfiguration.Builder()
            (trimMap["startSeconds"] as? Number)?.let {
                clipBuilder.setStartPositionMs((it.toDouble() * 1000).toLong())
            }
            (trimMap["endSeconds"] as? Number)?.let {
                clipBuilder.setEndPositionMs((it.toDouble() * 1000).toLong())
            }
            mediaItemBuilder.setClippingConfiguration(clipBuilder.build())
        }

        val mediaItem = mediaItemBuilder.build()
        val builder = EditedMediaItem.Builder(mediaItem)

        val videoEffects = mutableListOf<Effect>()

        (timeline["crop"] as? Map<*, *>)?.let { crop ->
            try {
                android.util.Log.d(TAG, "buildEditedMediaItem: crop=$crop")
                val left = (crop["left"] as? Number)?.toFloat() ?: 0f
                val top = (crop["top"] as? Number)?.toFloat() ?: 0f
                val right = (crop["right"] as? Number)?.toFloat() ?: 1f
                val bottom = (crop["bottom"] as? Number)?.toFloat() ?: 1f

                val sanitizedLeft = left.coerceIn(0f, 1f)
                val sanitizedTop = top.coerceIn(0f, 1f)
                val sanitizedRight = right.coerceIn(0f, 1f)
                val sanitizedBottom = bottom.coerceIn(0f, 1f)

                val width = sanitizedRight - sanitizedLeft
                val height = sanitizedBottom - sanitizedTop
                val hasValidArea = width > CROP_EPSILON && height > CROP_EPSILON
                val isFullFrame =
                    sanitizedLeft <= CROP_EPSILON &&
                        sanitizedTop <= CROP_EPSILON &&
                        (1f - sanitizedRight) <= CROP_EPSILON &&
                        (1f - sanitizedBottom) <= CROP_EPSILON

                android.util.Log.d(
                    TAG,
                    "buildEditedMediaItem: crop values left=$sanitizedLeft top=$sanitizedTop right=$sanitizedRight bottom=$sanitizedBottom hasValidArea=$hasValidArea isFullFrame=$isFullFrame",
                )

                if (hasValidArea && !isFullFrame) {
                    videoEffects += Crop(sanitizedLeft, sanitizedTop, sanitizedRight, sanitizedBottom)
                } else {
                    android.util.Log.w(
                        TAG,
                        "buildEditedMediaItem: Ignoring crop due to invalid area or full-frame bounds $crop",
                    )
                }
            } catch (iae: IllegalArgumentException) {
                android.util.Log.e(TAG, "buildEditedMediaItem: Crop construction failed with crop=$crop", iae)
                throw iae
            } catch (t: Throwable) {
                android.util.Log.e(TAG, "buildEditedMediaItem: Unexpected error building Crop with crop=$crop", t)
                throw t
            }
        }

        (timeline["scale"] as? Map<*, *>)?.let { scale ->
            try {
                android.util.Log.d(TAG, "buildEditedMediaItem: scale=$scale")
                val scaleX = (scale["x"] as? Number)?.toFloat()
                    ?: (scale["scaleX"] as? Number)?.toFloat()
                    ?: (scale["width"] as? Number)?.toFloat()
                    ?: 1f
                val scaleY = (scale["y"] as? Number)?.toFloat()
                    ?: (scale["scaleY"] as? Number)?.toFloat()
                    ?: (scale["height"] as? Number)?.toFloat()
                    ?: 1f
                val rotation = (scale["rotationDegrees"] as? Number)?.toFloat() ?: 0f
                android.util.Log.d(TAG, "buildEditedMediaItem: scale values scaleX=$scaleX scaleY=$scaleY rotation=$rotation")
                videoEffects += ScaleAndRotateTransformation.Builder()
                    .setScale(scaleX, scaleY)
                    .setRotationDegrees(rotation)
                    .build()
            } catch (iae: IllegalArgumentException) {
                android.util.Log.e(TAG, "buildEditedMediaItem: Scale/Rotate construction failed with scale=$scale", iae)
                throw iae
            } catch (t: Throwable) {
                android.util.Log.e(TAG, "buildEditedMediaItem: Unexpected error building Scale/Rotate with scale=$scale", t)
                throw t
            }
        }

        (timeline["effects"] as? List<*>)?.forEach { effect ->
            try {
                parseEffect(effect)?.let { videoEffects += it }
            } catch (t: Throwable) {
                android.util.Log.e(TAG, "buildEditedMediaItem: parseEffect failed for effect=$effect", t)
                // continue; skip invalid effects
            }
        }

        if (videoEffects.isNotEmpty()) {
            builder.setEffects(Effects(emptyList(), videoEffects))
        }

        return builder.build()
    }

    @OptIn(UnstableApi::class)
    private fun parseEffect(raw: Any?): Effect? {
        val map = raw as? Map<*, *> ?: return null
        val type = map["type"] as? String ?: return null
        return when (type) {
            "lut" -> buildLutEffect(map)
            else -> null
        }
    }

    @OptIn(UnstableApi::class)
    private fun buildLutEffect(map: Map<*, *>): Effect? {
        val path = map["path"] as? String ?: return null
        val width = (map["width"] as? Number)?.toInt() ?: return null
        val height = (map["height"] as? Number)?.toInt() ?: return null
        val depth = (map["depth"] as? Number)?.toInt() ?: return null
        val bitmap = BitmapFactory.decodeFile(path) ?: return null
        return try {
            if (width <= 0 || height <= 0 || depth <= 0) {
                bitmap.recycle()
                null
            } else {
                SingleColorLut.createFromBitmap(bitmap).also { bitmap.recycle() }
            }
        } catch (_: Exception) {
            bitmap.recycle()
            null
        }
    }

    // Helpers to convert org.json types into Kotlin collections.
    private fun JSONObject.toMap(): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = this.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = this.get(key)
            map[key] = when (value) {
                is JSONObject -> value.toMap()
                is JSONArray -> value.toList()
                JSONObject.NULL -> null
                else -> value
            }
        }
        return map
    }

    private fun JSONArray.toList(): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until this.length()) {
            val value = this.get(i)
            list.add(
                when (value) {
                    is JSONObject -> value.toMap()
                    is JSONArray -> value.toList()
                    JSONObject.NULL -> null
                    else -> value
                }
            )
        }
        return list
    }
}
