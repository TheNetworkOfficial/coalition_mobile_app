package com.example.coalition_mobile_app

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Size
import java.io.File
import java.io.IOException

internal class VideoFrameExtractor private constructor(
    private val contentResolver: ContentResolver,
) {

    private val timeoutMs = 1_500L

    fun extractFrameFromUri(
        uri: Uri,
        frameTimeUs: Long,
        targetSizePx: Int = DEFAULT_TARGET_SIZE,
    ): Bitmap {
        val sanitizedFrameTimeUs = sanitizeFrameTime(frameTimeUs)
        val bitmap = extractFrame(uri, sanitizedFrameTimeUs, targetSizePx)
        return bitmap ?: throw IOException("Unable to extract frame for $uri")
    }

    fun extractFrameFromPath(
        path: String,
        frameTimeUs: Long,
        targetSizePx: Int = DEFAULT_TARGET_SIZE,
    ): Bitmap {
        val file = File(path)
        if (!file.exists()) {
            throw IOException("File does not exist: $path")
        }
        val sanitizedFrameTimeUs = sanitizeFrameTime(frameTimeUs)
        var parcelFileDescriptor: ParcelFileDescriptor? = null
        return try {
            parcelFileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            val bitmap = extractFrameFromFileDescriptorInternal(parcelFileDescriptor, sanitizedFrameTimeUs)
            parcelFileDescriptor = null
            bitmap ?: throw IOException("Unable to extract frame for $path")
        } catch (error: Throwable) {
            if (error is IOException) throw error
            throw IOException("Unable to extract frame for $path", error)
        } finally {
            try {
                parcelFileDescriptor?.close()
            } catch (_: Throwable) {
            }
        }
    }

    fun extractFrameFromFileDescriptor(
        descriptor: ParcelFileDescriptor,
        frameTimeUs: Long,
        targetSizePx: Int = DEFAULT_TARGET_SIZE,
    ): Bitmap {
        val sanitizedFrameTimeUs = sanitizeFrameTime(frameTimeUs)
        val bitmap = extractFrameFromFileDescriptorInternal(descriptor, sanitizedFrameTimeUs)
        return bitmap ?: throw IOException("Unable to extract frame from descriptor")
    }

    fun extractFrameFromFileDescriptor(descriptor: ParcelFileDescriptor): Bitmap? {
        return extractFrameFromFileDescriptorInternal(descriptor, DEFAULT_FRAME_TIME_US)
    }

    private fun extractFrame(
        uri: Uri,
        frameTimeUs: Long,
        targetSizePx: Int,
    ): Bitmap? {
        val start = SystemClock.elapsedRealtime()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val cancellationSignal = CancellationSignal()
            try {
                val size = Size(targetSizePx.coerceAtLeast(1), targetSizePx.coerceAtLeast(1))
                val bitmap = contentResolver.loadThumbnail(uri, size, cancellationSignal)
                if (SystemClock.elapsedRealtime() - start <= timeoutMs) {
                    return bitmap
                }
            } catch (_: Throwable) {
                // Fallback to retriever path
            } finally {
                if (!cancellationSignal.isCanceled) {
                    cancellationSignal.cancel()
                }
            }
        }
        return extractWithRetriever(uri, frameTimeUs, start)
    }

    private fun extractWithRetriever(
        uri: Uri,
        frameTimeUs: Long,
        start: Long,
    ): Bitmap? {
        var parcelFileDescriptor: ParcelFileDescriptor? = null
        var retriever: MediaMetadataRetriever? = null
        return try {
            parcelFileDescriptor = contentResolver.openFileDescriptor(uri, "r") ?: return null
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(parcelFileDescriptor.fileDescriptor)
            val bitmap = retriever.getFrameAtTime(frameTimeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (SystemClock.elapsedRealtime() - start > timeoutMs) {
                null
            } else {
                bitmap
            }
        } catch (_: Throwable) {
            null
        } finally {
            try {
                retriever?.release()
            } catch (_: Throwable) {
            }
            try {
                parcelFileDescriptor?.close()
            } catch (_: Throwable) {
            }
        }
    }

    private fun extractFrameFromFileDescriptorInternal(
        descriptor: ParcelFileDescriptor,
        frameTimeUs: Long,
    ): Bitmap? {
        val start = SystemClock.elapsedRealtime()
        var retriever: MediaMetadataRetriever? = null
        return try {
            retriever = MediaMetadataRetriever()
            retriever.setDataSource(descriptor.fileDescriptor)
            val bitmap = retriever.getFrameAtTime(frameTimeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (SystemClock.elapsedRealtime() - start > timeoutMs) {
                null
            } else {
                bitmap
            }
        } catch (_: Throwable) {
            null
        } finally {
            try {
                retriever?.release()
            } catch (_: Throwable) {
            }
            try {
                descriptor.close()
            } catch (_: Throwable) {
            }
        }
    }

    private fun sanitizeFrameTime(frameTimeUs: Long): Long {
        return if (frameTimeUs <= 0L) DEFAULT_FRAME_TIME_US else frameTimeUs
    }

    companion object {
        private const val DEFAULT_TARGET_SIZE = 320
        private const val DEFAULT_FRAME_TIME_US = 1_000_000L

        @Volatile
        private var instance: VideoFrameExtractor? = null

        fun getInstance(context: Context): VideoFrameExtractor {
            val current = instance
            if (current != null) {
                return current
            }
            return synchronized(this) {
                val cached = instance
                if (cached != null) {
                    cached
                } else {
                    val resolver = context.applicationContext.contentResolver
                    VideoFrameExtractor(resolver).also { extractor ->
                        instance = extractor
                    }
                }
            }
        }
    }
}
