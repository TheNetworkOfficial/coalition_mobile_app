package com.example.coalition_mobile_app

import android.content.Context
import android.graphics.Bitmap
import android.os.ParcelFileDescriptor
import com.bumptech.glide.load.Options
import com.bumptech.glide.load.ResourceDecoder
import com.bumptech.glide.load.engine.Resource
import com.bumptech.glide.load.engine.bitmap_recycle.BitmapPool
import com.bumptech.glide.load.resource.bitmap.BitmapResource
import java.io.IOException

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
    ): Resource<Bitmap>? {
        var opened: ParcelFileDescriptor? = null
        return try {
            opened = ParcelFileDescriptor.dup(data.fileDescriptor)
            val bitmap = extractor.extractFrameFromFileDescriptor(opened)
            opened = null
            if (bitmap != null) {
                BitmapResource.obtain(bitmap, bitmapPool)
            } else {
                null
            }
        } catch (error: Throwable) {
            throw IOException("Unable to decode video frame", error)
        } finally {
            try {
                opened?.close()
            } catch (_: Throwable) {
            }
        }
    }
}
