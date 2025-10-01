package com.example.coalition_mobile_app

import android.content.Context
import android.graphics.PixelFormat
import android.media.Image
import android.media.ImageReader
import android.media.MediaCodec
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.decoder.DecoderInputBuffer
import androidx.media3.transformer.Codec
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentLinkedQueue

@UnstableApi
object FrameExtractionSupport {
    interface Listener {
        fun onImageAvailable(image: Image)
    }

    fun buildFrameExtractorTransformer(
        context: Context,
        listener: Listener,
    ): Transformer {
        return Transformer.Builder(context)
            .experimentalSetTrimOptimizationEnabled(false)
            .setEncoderFactory(ImageReaderEncoder.Factory(listener))
            .setMaxDelayBetweenMuxerSamplesMs(C.TIME_UNSET)
            .setMuxerFactory(
                NoOpMuxer.Factory(
                    ImmutableList.of(MimeTypes.AUDIO_AAC),
                    ImmutableList.of(MimeTypes.VIDEO_H264),
                ),
            )
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .experimentalSetMaxFramesInEncoder(1)
            .build()
    }

    private class ImageReaderEncoder(
        private val configurationFormat: Format,
        listener: Listener,
    ) : Codec {
        class Factory(private val listener: Listener) : Codec.EncoderFactory {
            override fun createForAudioEncoding(format: Format): Codec {
                throw UnsupportedOperationException()
            }

            override fun createForVideoEncoding(format: Format): Codec {
                return ImageReaderEncoder(format, listener)
            }
        }

        private val imageReader = ImageReader.newInstance(
            configurationFormat.width,
            configurationFormat.height,
            PixelFormat.RGBA_8888,
            /* maxImages = */ 1,
        )
        private val processedImageTimestampsNs = ConcurrentLinkedQueue<Long>()
        private val outputBufferInfo = MediaCodec.BufferInfo()
        private var hasOutputBuffer = false
        private var inputStreamEnded = false

        init {
            imageReader.setOnImageAvailableListener(
                { reader ->
                    val image = reader.acquireNextImage()
                    if (image != null) {
                        image.use {
                            processedImageTimestampsNs.add(it.timestamp)
                            listener.onImageAvailable(it)
                        }
                    }
                },
                Util.createHandlerForCurrentOrMainLooper(),
            )
        }

        override fun getName(): String = NAME

        override fun getConfigurationFormat(): Format = configurationFormat

        override fun getInputSurface(): Surface = imageReader.surface

        override fun maybeDequeueInputBuffer(inputBuffer: DecoderInputBuffer): Boolean {
            throw UnsupportedOperationException()
        }

        override fun queueInputBuffer(inputBuffer: DecoderInputBuffer) {
            throw UnsupportedOperationException()
        }

        override fun signalEndOfInputStream() {
            inputStreamEnded = true
        }

        override fun getOutputFormat(): Format = configurationFormat

        override fun getOutputBuffer(): ByteBuffer? =
            if (maybeGenerateOutputBuffer()) EMPTY_BUFFER else null

        override fun getOutputBufferInfo(): MediaCodec.BufferInfo? =
            if (maybeGenerateOutputBuffer()) outputBufferInfo else null

        override fun isEnded(): Boolean = inputStreamEnded && processedImageTimestampsNs.isEmpty()

        override fun releaseOutputBuffer(render: Boolean) {
            releaseOutputBuffer()
        }

        override fun releaseOutputBuffer(renderPresentationTimeUs: Long) {
            releaseOutputBuffer()
        }

        private fun releaseOutputBuffer() {
            hasOutputBuffer = false
        }

        override fun release() {
            imageReader.close()
        }

        private fun maybeGenerateOutputBuffer(): Boolean {
            if (hasOutputBuffer) {
                return true
            }
            val timeNs = processedImageTimestampsNs.poll() ?: return false
            hasOutputBuffer = true
            outputBufferInfo.presentationTimeUs = timeNs / 1_000
            outputBufferInfo.size = 0
            outputBufferInfo.offset = 0
            outputBufferInfo.flags = 0
            return true
        }

        companion object {
            private const val NAME = "ImageReaderEncoder"
            private val EMPTY_BUFFER: ByteBuffer = ByteBuffer.allocateDirect(0)
        }
    }

    private class NoOpMuxer : androidx.media3.muxer.Muxer {
        class Factory(
            private val audioMimeTypes: ImmutableList<String>,
            private val videoMimeTypes: ImmutableList<String>,
        ) : androidx.media3.muxer.Muxer.Factory {
            override fun create(path: String): androidx.media3.muxer.Muxer = NoOpMuxer()

            override fun getSupportedSampleMimeTypes(trackType: Int): ImmutableList<String> {
                return when (trackType) {
                    C.TRACK_TYPE_AUDIO -> audioMimeTypes
                    C.TRACK_TYPE_VIDEO -> videoMimeTypes
                    else -> ImmutableList.of()
                }
            }
        }

        override fun addTrack(format: Format): androidx.media3.muxer.Muxer.TrackToken {
            return object : androidx.media3.muxer.Muxer.TrackToken {}
        }

        override fun writeSampleData(
            trackToken: androidx.media3.muxer.Muxer.TrackToken,
            data: ByteBuffer,
            bufferInfo: MediaCodec.BufferInfo,
        ) = Unit

        override fun addMetadataEntry(metadataEntry: androidx.media3.common.Metadata.Entry) = Unit

        override fun close() = Unit
    }
}
