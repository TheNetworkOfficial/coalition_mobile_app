package com.example.coalition_mobile_app

import android.content.Context
import android.util.AttributeSet
import android.view.SurfaceView
import android.widget.FrameLayout
import androidx.media3.exoplayer.ExoPlayer

class VideoPreviewView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {

    private val surfaceView = SurfaceView(context)
    private var player: ExoPlayer? = null

    init {
        surfaceView.layoutParams = LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.MATCH_PARENT,
        )
        surfaceView.holder.setKeepScreenOn(true)
        addView(surfaceView)
    }

    fun setPlayer(player: ExoPlayer?) {
        if (this.player === player) {
            return
        }

        this.player?.clearVideoSurfaceView(surfaceView)
        this.player = player

        player?.setVideoSurfaceView(surfaceView)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        player?.setVideoSurfaceView(surfaceView)
    }

    override fun onDetachedFromWindow() {
        player?.clearVideoSurfaceView(surfaceView)
        super.onDetachedFromWindow()
    }
}
