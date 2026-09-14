package dev.chikenare.fplayer

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.Timeline
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.TrackGroupArray
import androidx.media3.exoplayer.trackselection.ExoTrackSelection
import androidx.media3.exoplayer.upstream.Allocator
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

        return HeapBoundLoadControl(builder.build(), heapBufferCeilingBytes())
    }

    /**
     * The most media the buffer may hold, from what this process's Java heap can spare.
     *
     * Media3 keeps every buffered byte in 64 KB arrays on the Java heap. Its own byte target
     * assumes a phone's heap, and `prioritizeTimeOverSizeThresholds` — on in both the fast-start
     * and the resilient presets — sets that target aside until the time goal is met: a minute of
     * a 4K stream is a couple of hundred megabytes, and a television box with a 256 MB heap
     * answered with an OutOfMemoryError that closed the app mid-film.
     */
    private fun heapBufferCeilingBytes(): Long {
        val heap = Runtime.getRuntime().maxMemory()
        if (heap <= 0 || heap == Long.MAX_VALUE) return Long.MAX_VALUE
        return (heap * 2 / 5).coerceAtLeast(MIN_BUFFER_CEILING_BYTES)
    }

    private const val MIN_BUFFER_CEILING_BYTES = 32L * 1024 * 1024

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
                        // Either bound on its own counts — "cap at 720p" is the common one,
                        // and it did nothing at all unless a width came with it.
                        if (maxWidth != null || maxHeight != null) {
                            setMaxVideoSize(
                                maxWidth ?: Int.MAX_VALUE,
                                maxHeight ?: Int.MAX_VALUE,
                            )
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

/**
 * A [LoadControl] that stops loading once the buffer reaches [ceilingBytes], whatever the load
 * control underneath would have done.
 *
 * Every other decision is the underlying one's. Each member is forwarded by hand rather than
 * through interface delegation: most of [LoadControl] is Java default methods, and a default
 * that is not forwarded would quietly run the interface's no-op instead of the real control's.
 */
@OptIn(UnstableApi::class)
private class HeapBoundLoadControl(
    private val delegate: LoadControl,
    private val ceilingBytes: Long,
) : LoadControl {
    override fun onPrepared(playerId: PlayerId) = delegate.onPrepared(playerId)

    override fun onTracksSelected(
        parameters: LoadControl.Parameters,
        trackGroups: TrackGroupArray,
        trackSelections: Array<out ExoTrackSelection?>,
    ) = delegate.onTracksSelected(parameters, trackGroups, trackSelections)

    override fun onStopped(playerId: PlayerId) = delegate.onStopped(playerId)

    override fun onReleased(playerId: PlayerId) = delegate.onReleased(playerId)

    override fun getAllocator(playerId: PlayerId): Allocator = delegate.getAllocator(playerId)

    override fun getBackBufferDurationUs(playerId: PlayerId): Long =
        delegate.getBackBufferDurationUs(playerId)

    override fun retainBackBufferFromKeyframe(playerId: PlayerId): Boolean =
        delegate.retainBackBufferFromKeyframe(playerId)

    override fun shouldContinueLoading(parameters: LoadControl.Parameters): Boolean {
        // Asked first either way, so the control underneath keeps its own loading state current.
        val wanted = delegate.shouldContinueLoading(parameters)
        return wanted && delegate.getAllocator(parameters.playerId).totalBytesAllocated < ceilingBytes
    }

    override fun shouldContinuePreloading(
        playerId: PlayerId,
        timeline: Timeline,
        mediaPeriodId: MediaSource.MediaPeriodId,
        bufferedDurationUs: Long,
    ): Boolean = delegate.shouldContinuePreloading(playerId, timeline, mediaPeriodId, bufferedDurationUs)

    override fun shouldStartPlayback(parameters: LoadControl.Parameters): Boolean =
        delegate.shouldStartPlayback(parameters)
}
