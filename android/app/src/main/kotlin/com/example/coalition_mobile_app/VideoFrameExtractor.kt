package com.example.coalition_mobile_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.Image
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.util.Size
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.muxer.Muxer
import androidx.media3.transformer.Codec
import androidx.media3.transformer.TransformationResult
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max

@OptIn(UnstableApi::class)
internal class VideoFrameExtractor private constructor(private val appContext: Context) {

    fun extractFrameFromUri(
        uri: Uri,
        frameTimeUs: Long,
        targetSizePx: Int = DEFAULT_TARGET_SIZE,
    ): Bitmap {
        return extractFrame(DataSource.UriSource(uri), frameTimeUs, targetSizePx)
    }

    fun extractFrameFromPath(
        path: String,
        frameTimeUs: Long,
        targetSizePx: Int = DEFAULT_TARGET_SIZE,
    ): Bitmap {
        return extractFrame(DataSource.PathSource(path), frameTimeUs, targetSizePx)
    }

    fun extractFrameFromFileDescriptor(
        descriptor: ParcelFileDescriptor,
        frameTimeUs: Long,
        targetSizePx: Int = DEFAULT_TARGET_SIZE,
    ): Bitmap {
        return extractFrame(DataSource.DescriptorSource(descriptor), frameTimeUs, targetSizePx)
    }

    private fun extractFrame(
        dataSource: DataSource,
        requestedFrameTimeUs: Long,
        targetSizePx: Int,
    ): Bitmap {
        val sanitizedFrameTimeUs = sanitizeFrameTime(requestedFrameTimeUs)
        val retrieverResult = try {
            runWithTimeout(DECODE_TIMEOUT_MS) {
                attemptWithMediaMetadataRetriever(dataSource, sanitizedFrameTimeUs)
            }
        } catch (timeout: TimeoutException) {
            android.util.Log.w(TAG, "MediaMetadataRetriever timed out for $dataSource", timeout)
            null
        } catch (error: Throwable) {
            android.util.Log.w(TAG, "MediaMetadataRetriever failed for $dataSource", error)
            null
        }

        if (retrieverResult != null) {
            return maybeScale(retrieverResult, targetSizePx)
        }

        val thumbnailResult = try {
            attemptWithThumbnailUtils(dataSource)
        } catch (error: Throwable) {
            android.util.Log.w(TAG, "ThumbnailUtils fallback failed for $dataSource", error)
            null
        }

        if (thumbnailResult != null) {
            return maybeScale(thumbnailResult, targetSizePx)
        }

        val media3Result = try {
            attemptWithMedia3(dataSource, sanitizedFrameTimeUs)
        } catch (error: Throwable) {
            android.util.Log.e(TAG, "Media3 fallback failed for $dataSource", error)
            null
        }

        if (media3Result != null) {
            return maybeScale(media3Result, targetSizePx)
        }

        throw IOException("Unable to extract frame for $dataSource")
    }

    private fun attemptWithMediaMetadataRetriever(
        dataSource: DataSource,
        frameTimeUs: Long,
    ): Bitmap? {
        var retriever: MediaMetadataRetriever? = null
        var parcelFileDescriptor: ParcelFileDescriptor? = null
        var tempFile: File? = null
        return try {
            retriever = MediaMetadataRetriever()
            when (dataSource) {
                is DataSource.UriSource -> {
                    val result = openUriForRetriever(dataSource.uri)
                    parcelFileDescriptor = result.first
                    tempFile = result.second
                    when {
                        parcelFileDescriptor != null -> retriever.setDataSource(parcelFileDescriptor.fileDescriptor)
                        tempFile != null -> retriever.setDataSource(tempFile.absolutePath)
                        else -> retriever.setDataSource(appContext, dataSource.uri)
                    }
                }
                is DataSource.PathSource -> {
                    retriever.setDataSource(dataSource.path)
                }
                is DataSource.DescriptorSource -> {
                    parcelFileDescriptor = dataSource.duplicate()
                    retriever.setDataSource(parcelFileDescriptor!!.fileDescriptor)
                }
            }
            retriever.getFrameAtTime(frameTimeUs, MediaMetadataRetriever.OPTION_CLOSEST)
        } catch (error: Throwable) {
            android.util.Log.w(TAG, "MediaMetadataRetriever threw for $dataSource", error)
            null
        } finally {
            retriever?.release()
            try {
                parcelFileDescriptor?.close()
            } catch (_: Throwable) {
            }
            tempFile?.let {
                if (!it.delete()) {
                    android.util.Log.d(TAG, "Temporary copy ${it.absolutePath} could not be deleted immediately")
                }
            }
        }
    }

    private fun attemptWithThumbnailUtils(dataSource: DataSource): Bitmap? {
        val prepared = dataSource.prepareLocalCopy(appContext)
        val cleanup = prepared.cleanup
        var legacyTemp: File? = null
        try {
            val uri = prepared.uri
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val signal = CancellationSignal()
                ThumbnailUtils.createVideoThumbnail(appContext.contentResolver, uri, Size(DEFAULT_TARGET_SIZE, DEFAULT_TARGET_SIZE), signal)
            } else {
                val path = when (uri.scheme?.lowercase()) {
                    "content" -> {
                        legacyTemp = copyUriToTempFile(uri)
                        legacyTemp?.absolutePath
                    }
                    "file" -> uri.path
                    else -> uri.path
                }
                if (path != null) {
                    ThumbnailUtils.createVideoThumbnail(path, MediaStore.Images.Thumbnails.MINI_KIND)
                } else {
                    null
                }
            }
        } finally {
            legacyTemp?.let {
                if (!it.delete()) {
                    android.util.Log.d(TAG, "Temporary legacy thumbnail ${it.absolutePath} could not be deleted")
                }
            }
            cleanup?.invoke()
        }
    }

    private fun attemptWithMedia3(
        dataSource: DataSource,
        frameTimeUs: Long,
    ): Bitmap? {
        val prepared = dataSource.prepareLocalCopy(appContext)
        val cleanupAction = prepared.cleanup
        val latch = CountDownLatch(1)
        val result = AtomicReference<Bitmap?>()
        val failure = AtomicReference<Throwable?>()
        val finished = AtomicBoolean(false)
        val transformerRef = AtomicReference<Transformer?>()
        val output = createVideoTempFile(appContext, "frame_extract_", ".tmp")

        mainHandler.post {
            if (finished.get()) {
                return@post
            }
            try {
                val frameListener = object : FrameExtractionSupport.Listener {
                    override fun onImageAvailable(image: Image) {
                        try {
                            result.compareAndSet(null, imageToBitmap(image))
                        } catch (error: Throwable) {
                            failure.compareAndSet(null, error)
                        } finally {
                            try {
                                image.close()
                            } catch (_: Throwable) {
                            }
                            if (finished.compareAndSet(false, true)) {
                                latch.countDown()
                            }
                        }
                    }
                }

                val encoderFactoryClass = Class.forName(
                    "com.example.coalition_mobile_app.FrameExtractionSupport\$ImageReaderEncoder\$Factory",
                )
                val encoderFactoryConstructor =
                    encoderFactoryClass.getDeclaredConstructor(FrameExtractionSupport.Listener::class.java)
                encoderFactoryConstructor.isAccessible = true
                val encoderFactory =
                    encoderFactoryConstructor.newInstance(frameListener) as Codec.EncoderFactory

                val muxerFactoryClass = Class.forName(
                    "com.example.coalition_mobile_app.FrameExtractionSupport\$NoOpMuxer\$Factory",
                )
                val muxerFactoryConstructor = muxerFactoryClass.getDeclaredConstructor(
                    ImmutableList::class.java,
                    ImmutableList::class.java,
                )
                muxerFactoryConstructor.isAccessible = true
                val muxerFactory = muxerFactoryConstructor.newInstance(
                    ImmutableList.of(MimeTypes.AUDIO_AAC),
                    ImmutableList.of(MimeTypes.VIDEO_H264),
                ) as Muxer.Factory

                val transformer = Transformer.Builder(appContext)
                    .setApplicationLooper(Looper.getMainLooper())
                    .experimentalSetTrimOptimizationEnabled(false)
                    .setEncoderFactory(encoderFactory)
                    .setMaxDelayBetweenMuxerSamplesMs(C.TIME_UNSET)
                    .setMuxerFactory(muxerFactory)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .experimentalSetMaxFramesInEncoder(1)
                    .build()

                transformerRef.set(transformer)

                transformer.addListener(
                    object : Transformer.Listener {
                        override fun onTransformationError(mediaItem: MediaItem, exception: Exception) {
                            failure.compareAndSet(null, exception)
                            if (finished.compareAndSet(false, true)) {
                                latch.countDown()
                            }
                        }

                        override fun onTransformationCompleted(
                            mediaItem: MediaItem,
                            transformationResult: TransformationResult,
                        ) {
                            if (result.get() == null) {
                                failure.compareAndSet(null, IOException("No frame extracted"))
                            }
                            if (finished.compareAndSet(false, true)) {
                                latch.countDown()
                            }
                        }
                    },
                )

                val clipStartMs = max(0L, frameTimeUs / 1000)
                val clipEndMs = clipStartMs + 1_000L
                val mediaItemBuilder = MediaItem.Builder().setUri(prepared.uri)
                mediaItemBuilder.setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(clipStartMs)
                        .setEndPositionMs(clipEndMs)
                        .build(),
                )
                val edited = androidx.media3.transformer.EditedMediaItem.Builder(mediaItemBuilder.build())
                    .setRemoveAudio(true)
                    .build()

                transformer.start(edited, output.absolutePath)
            } catch (error: Throwable) {
                failure.compareAndSet(null, error)
                if (finished.compareAndSet(false, true)) {
                    latch.countDown()
                }
            }
        }

        val completed = try {
            latch.await(3, TimeUnit.SECONDS)
        } catch (interrupted: InterruptedException) {
            Thread.currentThread().interrupt()
            failure.compareAndSet(null, interrupted)
            false
        }

        if (!completed) {
            failure.compareAndSet(null, TimeoutException("Timed out waiting for frame extraction"))
            if (finished.compareAndSet(false, true)) {
                latch.countDown()
            }
        }

        val cancelPosted = mainHandler.post {
            transformerRef.get()?.cancel()
            if (!output.delete()) {
                android.util.Log.d(
                    TAG,
                    "Temporary transformer output ${output.absolutePath} could not be deleted",
                )
            }
            cleanupAction?.let { action ->
                decodeExecutor.execute { action() }
            }
        }

        if (!cancelPosted) {
            cleanupAction?.let { action ->
                decodeExecutor.execute { action() }
            }
            if (!output.delete()) {
                android.util.Log.d(
                    TAG,
                    "Temporary transformer output ${output.absolutePath} could not be deleted",
                )
            }
        }

        return if (failure.get() == null && completed) {
            result.get()
        } else {
            null
        }
    }

    private fun openUriForRetriever(uri: Uri): Pair<ParcelFileDescriptor?, File?> {
        return try {
            val pfd = appContext.contentResolver.openFileDescriptor(uri, "r")
            Pair(pfd, null)
        } catch (security: SecurityException) {
            android.util.Log.w(TAG, "openFileDescriptor security exception for $uri", security)
            Pair(null, copyUriToTempFile(uri))
        } catch (ioe: IOException) {
            android.util.Log.w(TAG, "openFileDescriptor IO exception for $uri", ioe)
            Pair(null, copyUriToTempFile(uri))
        } catch (error: Throwable) {
            android.util.Log.w(TAG, "openFileDescriptor unexpected error for $uri", error)
            Pair(null, copyUriToTempFile(uri))
        }
    }

    private fun copyUriToTempFile(uri: Uri): File? {
        return try {
            val inputStream = appContext.contentResolver.openInputStream(uri) ?: return null
            inputStream.use { input ->
                val tempFile = createVideoTempFile(appContext, "scoped_video_", ".tmp")
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
                tempFile
            }
        } catch (error: Throwable) {
            android.util.Log.w(TAG, "Failed to copy scoped URI $uri to temp file", error)
            null
        }
    }

    private fun DataSource.prepareLocalCopy(context: Context): PreparedUri {
        return when (this) {
            is DataSource.UriSource -> PreparedUri(uri)
            is DataSource.PathSource -> PreparedUri(Uri.fromFile(File(path)))
            is DataSource.DescriptorSource -> {
                val dup = duplicate()
                val temp = createVideoTempFile(context, "descriptor_copy_", ".tmp")
                try {
                    FileInputStream(dup.fileDescriptor).use { input ->
                        FileOutputStream(temp).use { output ->
                            input.channel.transferTo(0, Long.MAX_VALUE, output.channel)
                        }
                    }
                } catch (error: Throwable) {
                    if (!temp.delete()) {
                        android.util.Log.d(TAG, "Temporary descriptor copy ${temp.absolutePath} could not be deleted after failure")
                    }
                    throw error
                } finally {
                    try {
                        dup.close()
                    } catch (_: Throwable) {
                    }
                }
                PreparedUri(Uri.fromFile(temp)) {
                    if (!temp.delete()) {
                        android.util.Log.d(TAG, "Temporary descriptor copy ${temp.absolutePath} could not be deleted")
                    }
                }
            }
        }
    }

    private fun sanitizeFrameTime(frameTimeUs: Long): Long {
        return if (frameTimeUs <= 0L) DEFAULT_FALLBACK_FRAME_TIME_US else frameTimeUs
    }

    private fun maybeScale(bitmap: Bitmap, targetSizePx: Int): Bitmap {
        if (targetSizePx <= 0) {
            return bitmap
        }
        val maxDimension = max(bitmap.width, bitmap.height)
        if (maxDimension <= targetSizePx) {
            return bitmap
        }
        val scale = targetSizePx.toFloat() / maxDimension.toFloat()
        val matrix = Matrix()
        matrix.postScale(scale, scale)
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    private fun imageToBitmap(image: Image): Bitmap {
        val plane = image.planes.firstOrNull() ?: throw IOException("Image contains no planes")
        val buffer = plane.buffer
        buffer.rewind()
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * image.width
        val bitmap = Bitmap.createBitmap(
            image.width + rowPadding / pixelStride,
            image.height,
            Bitmap.Config.ARGB_8888,
        )
        bitmap.copyPixelsFromBuffer(buffer)
        return Bitmap.createBitmap(bitmap, 0, 0, image.width, image.height)
    }

    private fun <T> runWithTimeout(timeoutMs: Long, block: () -> T): T {
        val future: Future<T> = decodeExecutor.submit(Callable(block))
        return try {
            future.get(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (timeout: TimeoutException) {
            future.cancel(true)
            throw timeout
        } catch (error: Exception) {
            future.cancel(true)
            throw error
        }
    }

    private sealed class DataSource {
        data class UriSource(val uri: Uri) : DataSource() {
            override fun toString(): String = "UriSource(uri=$uri)"
        }

        data class PathSource(val path: String) : DataSource() {
            override fun toString(): String = "PathSource(path=$path)"
        }

        data class DescriptorSource(private val descriptor: ParcelFileDescriptor) : DataSource() {
            fun duplicate(): ParcelFileDescriptor {
                return ParcelFileDescriptor.dup(descriptor.fileDescriptor)
            }

            override fun toString(): String = "DescriptorSource(descriptor=${descriptor.fd})"
        }
    }

    private data class PreparedUri(val uri: Uri, val cleanup: (() -> Unit)? = null)

    companion object {
        private const val TAG = "VideoFrameExtractor"
        private const val DEFAULT_TARGET_SIZE = 320
        private const val DEFAULT_FALLBACK_FRAME_TIME_US = 1_000_000L
        private const val DECODE_TIMEOUT_MS = 1_200L
        private const val MAX_CONCURRENT_DECODE_JOBS = 2

        private val threadId = AtomicInteger(0)

        private val executor: ExecutorService by lazy {
            Executors.newFixedThreadPool(MAX_CONCURRENT_DECODE_JOBS) { runnable ->
                Thread(runnable, "VideoFrameDecode-${threadId.incrementAndGet()}").apply {
                    priority = Thread.NORM_PRIORITY - 1
                }
            }
        }

        fun getInstance(context: Context): VideoFrameExtractor {
            return VideoFrameExtractor(context.applicationContext)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private val decodeExecutor: ExecutorService
        get() = executor
}
