package dev.chikenare.fplayer

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector

/** Builds the ExoPlayer collaborators that are configured once, at player creation. */
@OptIn(UnstableApi::class)
internal object PlayerBuilders {
    fun loadControl(buffering: Map<String, Any?>): LoadControl {
        val builder = DefaultLoadControl.Builder()

        // Clamped rather than trusted: ExoPlayer throws on a negative duration, and that throw
        // lands in the middle of building a player that already owns a texture and a session.
        val minBuffer =
            (buffering.int("minBufferMs") ?: DefaultLoadControl.DEFAULT_MIN_BUFFER_MS)
                .coerceAtLeast(0)
        val maxBuffer =
            (buffering.int("maxBufferMs") ?: DefaultLoadControl.DEFAULT_MAX_BUFFER_MS)
                .coerceAtLeast(minBuffer)
        val forPlayback =
            (
                buffering.int("bufferForPlaybackMs")
                    ?: DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS
            ).coerceIn(0, minBuffer)
        val afterRebuffer =
            (
                buffering.int("bufferForPlaybackAfterRebufferMs")
                    ?: DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS
            ).coerceIn(0, minBuffer)

        builder.setBufferDurationsMs(minBuffer, maxBuffer, forPlayback, afterRebuffer)

        val backBuffer = buffering.int("backBufferMs") ?: 0
        if (backBuffer > 0) {
            builder.setBackBuffer(backBuffer, /* retainBackBufferFromKeyframe = */ true)
        }

        buffering.bool("prioritizeTimeOverSizeThresholds")?.let(builder::setPrioritizeTimeOverSizeThresholds)

        return builder.build()
    }

    fun renderersFactory(
        context: Context,
        decoding: Map<String, Any?>,
    ): RenderersFactory {
        val mode = decoding.string("mode") ?: "hardwareFirst"

        return DefaultRenderersFactory(context)
            .setEnableDecoderFallback(decoding.bool("enableDecoderFallback") ?: true)
            .setMediaCodecSelector(codecSelector(mode))
    }

    fun trackSelector(
        context: Context,
        config: Map<String, Any?>,
    ): DefaultTrackSelector {
        val decoding = config.map("decoding")
        val selector = DefaultTrackSelector(context)

        val maxWidth = decoding.int("maxWidth")
        val maxHeight = decoding.int("maxHeight")
        val maxBitrate = decoding.int("maxVideoBitrate")

        if (maxWidth != null || maxHeight != null || maxBitrate != null) {
            selector.setParameters(
                selector
                    .buildUponParameters()
                    .apply {
                        if (maxWidth != null && maxHeight != null) {
                            setMaxVideoSize(maxWidth, maxHeight)
                        }
                        if (maxBitrate != null) {
                            setMaxVideoBitrate(maxBitrate)
                        }
                    },
            )
        }

        return selector
    }

    /**
     * Hardware decoders are what Media3 prefers by default. The software modes exist for the
     * cases where a device ships a broken hardware decoder for a given codec, or for debugging.
     *
     * `softwareOnly` and `hardwareOnly` are strict on purpose: if no decoder of the requested kind
     * exists, playback fails with a decoder error instead of silently doing the opposite of what
     * was asked.
     */
    private fun codecSelector(mode: String): MediaCodecSelector =
        when (mode) {
            "hardwareFirst" -> MediaCodecSelector.DEFAULT
            else ->
                MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
                    val infos =
                        MediaCodecUtil.getDecoderInfos(
                            mimeType,
                            requiresSecureDecoder,
                            requiresTunnelingDecoder,
                        )
                    when (mode) {
                        "hardwareOnly" -> infos.filter { it.hardwareAccelerated }
                        "softwareOnly" -> infos.filter { !it.hardwareAccelerated }
                        // Stable sort: software decoders first, original ranking preserved within
                        // each group.
                        "softwareFirst" -> infos.sortedBy { it.hardwareAccelerated }
                        else -> infos
                    }
                }
        }
}
