package dev.chikenare.fplayer.download

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.util.Util
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.dash.manifest.DashManifest
import androidx.media3.exoplayer.hls.HlsManifest
import androidx.media3.exoplayer.offline.DownloadHelper
import androidx.media3.exoplayer.offline.DownloadRequest
import dev.chikenare.fplayer.bool
import dev.chikenare.fplayer.int
import dev.chikenare.fplayer.stringList
import java.io.IOException

/**
 * Reads a manifest to find out what could be downloaded, and turns a caller's choice into a
 * [DownloadRequest].
 *
 * Both jobs need the manifest parsed and its renditions enumerated, which is what
 * [DownloadHelper] does. It is prepared and released per call: holding one open between an
 * inspection and the download that follows would mean keeping a manifest — and its staleness —
 * across an arbitrary amount of user hesitation.
 */
@OptIn(UnstableApi::class)
internal object DownloadSelector {
    /** Reports what the source offers, for a quality picker. */
    fun inspect(
        context: Context,
        mediaItem: MediaItem,
        dataSourceFactory: DataSource.Factory,
        onResult: (Map<String, Any?>) -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        prepare(context, mediaItem, dataSourceFactory, onError) { helper ->
            // A progressive file has nothing to enumerate — it is one stream, taken whole — and
            // the helper was never prepared with a media source to answer questions about.
            val periodCount = if (isProgressive(mediaItem)) 0 else helper.periodCount
            val durationMs = if (isProgressive(mediaItem)) null else durationMsOf(helper)
            val tracks = mutableListOf<Map<String, Any?>>()

            for (period in 0 until periodCount) {
                helper.getTracks(period).groups.forEachIndexed { groupIndex, group ->
                    for (trackIndex in 0 until group.length) {
                        describe(group.getTrackFormat(trackIndex), group.type, groupIndex, trackIndex, durationMs)
                            ?.let(tracks::add)
                    }
                }
            }

            onResult(
                mapOf(
                    "durationMs" to durationMs,
                    // Lowest quality first, which is the order a picker reads best.
                    "video" to tracks.filter { it["type"] == "video" }.sortedBy { it.heightOrZero() },
                    "audio" to tracks.filter { it["type"] == "audio" },
                    "text" to tracks.filter { it["type"] == "text" },
                ),
            )
        }
    }

    /** Builds the request for what the caller asked to keep. */
    fun buildRequest(
        context: Context,
        id: String,
        mediaItem: MediaItem,
        dataSourceFactory: DataSource.Factory,
        selection: Map<String, Any?>,
        payload: ByteArray,
        onResult: (DownloadRequest) -> Unit,
        onError: (Throwable) -> Unit,
    ) {
        prepare(context, mediaItem, dataSourceFactory, onError) { helper ->
            // A progressive file has no renditions to choose between: it is downloaded whole.
            // Asking the helper about periods in that case throws, because it was never prepared
            // with a media source to describe.
            if (!isProgressive(mediaItem)) {
                applySelection(context, helper, selection)
            }
            onResult(helper.getDownloadRequest(id, payload))
        }
    }

    /**
     * Narrows what the helper will download.
     *
     * The default parameters take one video rendition and the default audio, which is already the
     * right shape for an offline copy; the caller's constraints tighten it further, and the
     * language calls widen it back where they asked.
     */
    private fun applySelection(
        context: Context,
        helper: DownloadHelper,
        selection: Map<String, Any?>,
    ) {
        val maxHeight = selection.int("maxHeight")
        val maxBitrate = selection.int("maxBitrate")
        val wantsAllAudio = selection.bool("allAudioLanguages") == true
        val wantsAllText = selection.bool("allTextLanguages") == true
        val audioLanguages = selection.stringList("audioLanguages").orEmpty()
        val textLanguages = selection.stringList("textLanguages").orEmpty()

        val parameters =
            DownloadHelper
                .getDefaultTrackSelectorParameters(context)
                .buildUpon()
                .apply {
                    if (maxHeight != null) setMaxVideoSize(Int.MAX_VALUE, maxHeight)
                    if (maxBitrate != null) setMaxVideoBitrate(maxBitrate)
                    if (audioLanguages.isNotEmpty()) {
                        setPreferredAudioLanguages(*audioLanguages.toTypedArray())
                    }
                    // Text is opt-in: subtitles nobody can reach in the UI are wasted bytes.
                    setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                }.build()

        for (period in 0 until helper.periodCount) {
            helper.clearTrackSelections(period)
            helper.addTrackSelection(period, parameters)
        }

        val extraAudio =
            if (wantsAllAudio) languagesOf(helper, C.TRACK_TYPE_AUDIO) else audioLanguages
        if (extraAudio.isNotEmpty()) {
            helper.addAudioLanguagesToSelection(*extraAudio.toTypedArray())
        }

        val wantedText = if (wantsAllText) languagesOf(helper, C.TRACK_TYPE_TEXT) else textLanguages
        if (wantedText.isNotEmpty()) {
            helper.addTextLanguagesToSelection(false, *wantedText.toTypedArray())
        }
    }

    private fun languagesOf(
        helper: DownloadHelper,
        trackType: Int,
    ): List<String> {
        val languages = linkedSetOf<String>()
        for (period in 0 until helper.periodCount) {
            helper.getTracks(period).groups.forEach { group ->
                if (group.type != trackType) return@forEach
                for (index in 0 until group.length) {
                    group.getTrackFormat(index).language?.let(languages::add)
                }
            }
        }
        return languages.toList()
    }

    /**
     * Whether the item is a single self-contained file rather than an adaptive manifest.
     *
     * Inferred the same way Media3 infers it when choosing a media source, so the two never
     * disagree about what kind of media this is.
     */
    private fun isProgressive(mediaItem: MediaItem): Boolean {
        val configuration = mediaItem.localConfiguration ?: return true
        return Util.inferContentTypeForUriAndMimeType(
            configuration.uri,
            configuration.mimeType,
        ) == C.CONTENT_TYPE_OTHER
    }

    private fun prepare(
        context: Context,
        mediaItem: MediaItem,
        dataSourceFactory: DataSource.Factory,
        onError: (Throwable) -> Unit,
        onPrepared: (DownloadHelper) -> Unit,
    ) {
        val helper =
            DownloadHelper.forMediaItem(
                context,
                mediaItem,
                DefaultRenderersFactory(context),
                dataSourceFactory,
            )

        helper.prepare(
            object : DownloadHelper.Callback {
                override fun onPrepared(
                    helper: DownloadHelper,
                    isLive: Boolean,
                ) {
                    var answered = false
                    try {
                        onPrepared(helper)
                        answered = true
                    } catch (e: Exception) {
                        // Only when the callback did not get far enough to answer itself. A
                        // failure *after* it replied — the Flutter sink throwing on the way out,
                        // say — must not turn into a second reply on the same result.
                        if (!answered) onError(e)
                    } finally {
                        helper.release()
                    }
                }

                override fun onPrepareError(
                    helper: DownloadHelper,
                    e: IOException,
                ) {
                    helper.release()
                    onError(e)
                }
            },
        )
    }

    /**
     * Rough size of one rendition, from its bitrate and the media's length.
     *
     * Only an estimate — variable-bitrate content lands within a few percent — but it is the
     * difference between a menu that says "720p" and one that says "720p · 480 MB".
     */
    private fun estimatedBytes(
        format: Format,
        durationMs: Long?,
    ): Long? {
        if (durationMs == null || durationMs <= 0) return null
        if (format.bitrate == Format.NO_VALUE) return null
        return format.bitrate.toLong() / 8 * durationMs / 1000
    }

    private fun describe(
        format: Format,
        trackType: Int,
        groupIndex: Int,
        trackIndex: Int,
        durationMs: Long?,
    ): Map<String, Any?>? {
        val type =
            when (trackType) {
                C.TRACK_TYPE_VIDEO -> "video"
                C.TRACK_TYPE_AUDIO -> "audio"
                C.TRACK_TYPE_TEXT -> "text"
                else -> return null
            }

        return mapOf(
            "type" to type,
            "groupIndex" to groupIndex,
            "trackIndex" to trackIndex,
            "label" to format.label,
            "language" to format.language?.takeIf { it.isNotBlank() && it != "und" },
            "codecs" to format.codecs,
            "bitrate" to format.bitrate.orNull(),
            "width" to format.width.orNull(),
            "height" to format.height.orNull(),
            "estimatedBytes" to estimatedBytes(format, durationMs),
        )
    }

    /**
     * Length of the media, where the manifest states one.
     *
     * Progressive files declare it in their container rather than in a manifest, so they report
     * null and their renditions simply carry no size estimate.
     */
    private fun durationMsOf(helper: DownloadHelper): Long? =
        when (val manifest = helper.manifest) {
            is DashManifest -> manifest.durationMs.takeIf { it != C.TIME_UNSET }
            is HlsManifest -> (manifest.mediaPlaylist.durationUs / 1000).takeIf { it > 0 }
            else -> null
        }

    private fun Int.orNull(): Int? = takeIf { it != Format.NO_VALUE }

    private fun Map<String, Any?>.heightOrZero(): Int = (this["height"] as? Number)?.toInt() ?: 0
}
