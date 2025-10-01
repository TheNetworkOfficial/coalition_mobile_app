package com.example.coalition_mobile_app

import android.content.Context
import android.graphics.Bitmap
import android.os.ParcelFileDescriptor
import com.bumptech.glide.Glide
import com.bumptech.glide.Registry
import com.bumptech.glide.load.Options
import com.bumptech.glide.load.ResourceDecoder
import com.bumptech.glide.load.engine.Resource
import com.bumptech.glide.load.engine.bitmap_recycle.BitmapPool
import com.bumptech.glide.load.resource.bitmap.BitmapResource
import com.bumptech.glide.load.resource.bitmap.VideoDecoder
import java.io.IOException
import kotlin.math.max
import kotlin.math.min

private const val DEFAULT_FRAME_TIME_US = 1_000_000L
private const val DEFAULT_TARGET_SIZE = 320
private const val TAG = "CoalitionVideoDecoder"

internal class CoalitionParcelFileDescriptorVideoDecoder(
    context: Context,
    private val bitmapPool: BitmapPool,
) : ResourceDecoder<ParcelFileDescriptor, Bitmap> {

    private val extractor = VideoFrameExtractor.getInstance(context)

    override fun handles(data: ParcelFileDescriptor, options: Options): Boolean = true

    override fun decode(
        data: ParcelFileDescriptor,
        outWidth: Int,
        outHeight: Int,
        options: Options,
    ): Resource<Bitmap> {
        val requestedFrame = options.get(VideoDecoder.TARGET_FRAME) ?: VideoDecoder.DEFAULT_FRAME
        val frameTimeUs = sanitizeFrameTimeUs(requestedFrame)
        val targetSize = computeTargetSize(outWidth, outHeight)

        return runCatching {
            val bitmap = extractor.extractFrameFromFileDescriptor(data, frameTimeUs, targetSize)
            BitmapResource.obtain(bitmap, bitmapPool)
                ?: throw IOException("Unable to obtain bitmap resource")
        }.getOrElse { error ->
            android.util.Log.w(TAG, "ParcelFileDescriptor decode failed", error)
            val placeholder = makePlaceholderBitmap()
            BitmapResource.obtain(placeholder, bitmapPool)
                ?: BitmapResource(placeholder, bitmapPool)
        }
    }

    private fun makePlaceholderBitmap(size: Int = 80): Bitmap {
        val dimension = if (size > 0) size else 80
        val bitmap = Bitmap.createBitmap(dimension, dimension, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)

        canvas.drawColor(0xFFE0E0E0.toInt())

        val trianglePaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFF424242.toInt()
            style = android.graphics.Paint.Style.FILL
        }

        val path = android.graphics.Path().apply {
            val left = dimension * 0.35f
            val top = dimension * 0.25f
            val right = dimension * 0.65f
            val bottom = dimension * 0.75f
            moveTo(left, top)
            lineTo(right, dimension * 0.5f)
            lineTo(left, bottom)
            close()
        }

        canvas.drawPath(path, trianglePaint)
        return bitmap
    }

    private fun sanitizeFrameTimeUs(requested: Long): Long {
        if (requested == VideoDecoder.DEFAULT_FRAME || requested <= 0L) {
            return DEFAULT_FRAME_TIME_US
        }
        return requested
    }

    private fun computeTargetSize(outWidth: Int, outHeight: Int): Int {
        val width = if (outWidth > 0) outWidth else 0
        val height = if (outHeight > 0) outHeight else 0
        val largest = max(width, height)
        return if (largest > 0) {
            min(largest, DEFAULT_TARGET_SIZE)
        } else {
            DEFAULT_TARGET_SIZE
        }
    }
}
