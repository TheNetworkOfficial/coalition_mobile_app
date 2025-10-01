package com.example.coalition_mobile_app

import android.content.Context
import com.bumptech.glide.Glide
import com.bumptech.glide.annotation.GlideModule
import com.bumptech.glide.module.AppGlideModule
import com.bumptech.glide.Registry

@GlideModule
class CoalitionGlideModule : AppGlideModule() {
    override fun registerComponents(context: Context, glide: Glide, registry: Registry) {
        registry.prepend(
            android.os.ParcelFileDescriptor::class.java,
            android.graphics.Bitmap::class.java,
            com.example.coalition_mobile_app.CoalitionParcelFileDescriptorVideoDecoder(
                context,
                glide.bitmapPool,
            ),
        )
        registry.registerCoalitionVideoDecoders(context, glide)
    }
}
