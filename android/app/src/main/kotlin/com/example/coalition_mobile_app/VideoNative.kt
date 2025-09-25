package com.example.coalition_mobile_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ColorMatrix
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.ClippingConfiguration
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.ColorFilter
import androidx.media3.effect.Crop
import androidx.media3.effect.Effect
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.OptIn

private const val CHANNEL_NAME = "video_native"

class VideoNative(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val transformerLock = Any()
    private var transformer: Transformer? = null
    private val isDisposed = AtomicBoolean(false)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        if (isDisposed.compareAndSet(false, true)) {
            channel.setMethodCallHandler(null)
            synchronized(transformerLock) {
                transformer?.cancel()
                transformer = null
            }
            executor.shutdownNow()
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
        val filePath = call.argument<String>("filePath")
        val timeline = call.argument<Map<String, Any?>>("timelineJson")
        val targetBitrate = call.argument<Number>("targetBitrateBps")?.toInt()

        if (filePath.isNullOrBlank() || timeline == null || targetBitrate == null) {
            result.error("bad_args", "Missing export arguments", null)
            return
        }

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
            synchronized(transformerLock) {
                transformer?.cancel()
                transformer = null
            }
            postSuccess(result, null)
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

    private fun generateCoverImage(filePath: String, seconds: Double): String {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(filePath)
            val frameTimeUs = (seconds * 1_000_000L).toLong()
            val bitmap = retriever.getFrameAtTime(frameTimeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                ?: throw IOException("Unable to retrieve frame")

            val outputFile = createTempFile(prefix = "cover_", suffix = ".png")
            FileOutputStream(outputFile).use { output ->
                if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                    throw IOException("Failed to write cover image")
                }
            }
            return outputFile.absolutePath
        } finally {
            retriever.release()
        }
    }

    @OptIn(UnstableApi::class)
    private fun exportEdits(
        filePath: String,
        timeline: Map<String, Any?>,
        targetBitrate: Int,
    ): String {
        val editedMediaItem = buildEditedMediaItem(filePath, timeline)
        val outputFile = createTempFile(prefix = "export_", suffix = ".mp4")

        val latch = CountDownLatch(1)
        var exportError: Exception? = null

        val listener = object : Transformer.Listener {
            override fun onCompleted(transformationResult: Transformer.TransformationResult) {
                latch.countDown()
            }

            override fun onError(exception: Exception) {
                exportError = exception
                latch.countDown()
            }
        }

        val encoderFactory = DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(
                VideoEncoderSettings.Builder().setBitrate(targetBitrate).build(),
            )
            .build()

        val transformer = Transformer.Builder(context)
            .setEncoderFactory(encoderFactory)
            .addListener(listener)
            .build()

        synchronized(transformerLock) {
            this.transformer?.cancel()
            this.transformer = transformer
        }

        transformer.start(editedMediaItem, outputFile.absolutePath)

        try {
            latch.await()
        } catch (ie: InterruptedException) {
            Thread.currentThread().interrupt()
            transformer.cancel()
            throw ie
        } finally {
            synchronized(transformerLock) {
                if (this.transformer === transformer) {
                    this.transformer = null
                }
            }
        }

        exportError?.let { throw it }
        return outputFile.absolutePath
    }

    @OptIn(UnstableApi::class)
    private fun buildEditedMediaItem(
        filePath: String,
        timeline: Map<String, Any?>,
    ): EditedMediaItem {
        val mediaItem = MediaItem.fromUri(Uri.fromFile(File(filePath)))
        val builder = EditedMediaItem.Builder(mediaItem)

        (timeline["trim"] as? Map<*, *>)?.let { trim ->
            val clipBuilder = ClippingConfiguration.Builder()
            (trim["startSeconds"] as? Number)?.let { clipBuilder.setStartPositionMs((it.toDouble() * 1000).toLong()) }
            (trim["endSeconds"] as? Number)?.let { clipBuilder.setEndPositionMs((it.toDouble() * 1000).toLong()) }
            builder.setClippingConfiguration(clipBuilder.build())
        }

        val videoEffects = mutableListOf<Effect>()

        (timeline["crop"] as? Map<*, *>)?.let { crop ->
            val left = (crop["left"] as? Number)?.toFloat() ?: 0f
            val top = (crop["top"] as? Number)?.toFloat() ?: 0f
            val right = (crop["right"] as? Number)?.toFloat() ?: 1f
            val bottom = (crop["bottom"] as? Number)?.toFloat() ?: 1f
            videoEffects += Crop(left, top, right, bottom)
        }

        (timeline["scale"] as? Map<*, *>)?.let { scale ->
            val scaleX = (scale["x"] as? Number)?.toFloat()
                ?: (scale["scaleX"] as? Number)?.toFloat()
                ?: (scale["width"] as? Number)?.toFloat()
                ?: 1f
            val scaleY = (scale["y"] as? Number)?.toFloat()
                ?: (scale["scaleY"] as? Number)?.toFloat()
                ?: (scale["height"] as? Number)?.toFloat()
                ?: 1f
            val rotation = (scale["rotationDegrees"] as? Number)?.toFloat() ?: 0f
            videoEffects += ScaleAndRotateTransformation.Builder()
                .setScale(scaleX, scaleY)
                .setRotationDegrees(rotation)
                .build()
        }

        (timeline["effects"] as? List<*>)?.forEach { effect ->
            parseEffect(effect)?.let { videoEffects += it }
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
            "colorFilter" -> {
                val values = (map["matrix"] as? List<*>)?.mapNotNull { (it as? Number)?.toFloat() }
                if (values == null || values.size != 20) {
                    null
                } else {
                    val matrixArray = FloatArray(20) { index -> values[index] }
                    ColorFilter(ColorMatrix(matrixArray))
                }
            }
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
            androidx.media3.effect.Lut(bitmap, width, height, depth)
        } catch (_: Exception) {
            null
        }
    }

    private fun createTempFile(prefix: String, suffix: String): File {
        val directory = File(context.cacheDir, "video_native")
        if (!directory.exists()) {
            directory.mkdirs()
        }
        return File.createTempFile(prefix, suffix, directory)
    }
}
