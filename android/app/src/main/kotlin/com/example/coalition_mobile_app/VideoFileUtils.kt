package com.example.coalition_mobile_app

import android.content.Context
import java.io.File

internal fun createVideoTempFile(context: Context, prefix: String, suffix: String): File {
    val directory = File(context.cacheDir, "video_native")
    if (!directory.exists()) {
        directory.mkdirs()
    }
    return File.createTempFile(prefix, suffix, directory)
}
