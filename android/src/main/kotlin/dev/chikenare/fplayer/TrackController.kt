package dev.chikenare.fplayer

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector

/**
 * Reads the tracks the media exposes and applies the user's choices.
 *
 * Track handles are regenerated on every [snapshot], because ExoPlayer's group indices only mean
 * anything for the current [Tracks] instance. Dart holds ids and never sees an index, so a stale
 * id resolves to nothing instead of selecting the wrong track.
 */
@OptIn(UnstableApi::class)
internal class TrackController(
    private val trackSelector: DefaultTrackSelector,
) {
    private val byId = mutableMapOf<String, Pair<TrackGroup, Int>>()

    fun snapshot(player: ExoPlayer): Map<String, Any?> {
        byId.clear()

        val audio = mutableListOf<Map<String, Any?>>()
        val text = mutableListOf<Map<String, Any?>>()
        val video = mutableListOf<Map<String, Any?>>()

        player.currentTracks.groups.forEachIndexed { groupIndex, group ->
            val bucket =
                when (group.type) {
                    C.TRACK_TYPE_AUDIO -> audio
                    C.TRACK_TYPE_TEXT -> text
                    C.TRACK_TYPE_VIDEO -> video
                    else -> return@forEachIndexed
                }

            // What is actually being decoded right now. Needed because an adaptive selection
            // marks every candidate quality as "selected", not just the one on screen.
            val playing =
                when (group.type) {
                    C.TRACK_TYPE_AUDIO -> player.audioFormat
                    C.TRACK_TYPE_VIDEO -> player.videoFormat
                    else -> null
                }

            // When the selection holds a single track there is nothing to disambiguate, so it is
            // the active one by definition. Comparing formats is only needed inside an adaptive
            // group, and those always come from a manifest that gives every rendition an id.
            val isUnambiguous = (0 until group.length).count(group::isTrackSelected) == 1

            for (trackIndex in 0 until group.length) {
                val id = "${typeName(group.type)}:$groupIndex:$trackIndex"
                byId[id] = group.mediaTrackGroup to trackIndex
                bucket += describe(id, bucket.size, group, trackIndex, playing, isUnambiguous)
            }
        }

        val parameters = trackSelector.parameters
        return mapOf(
            "event" to "tracks",
            "audio" to audio,
            "text" to text,
            "video" to video,
            "isTextDisabled" to parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT),
            "isVideoAuto" to parameters.overrides.values.none { it.type == C.TRACK_TYPE_VIDEO },
        )
    }

    /**
     * Fingerprint of what is being decoded right now.
     *
     * Adaptive switches do not raise `onTracksChanged` — the track list is identical, only the
     * chosen rung moved — so this is what tells the host whether a fresh snapshot is worth
     * sending.
     */
    fun activeSignature(player: ExoPlayer): String =
        "${player.videoFormat?.id}|${player.audioFormat?.id}"

    /**
     * Pins a track, or hands the choice back to the engine when [id] is null.
     *
     * For text, "no override" means off rather than automatic: showing subtitles is a deliberate
     * act, and a viewer who turned them off should not get them back on the next quality switch.
     */
    /**
     * Applies a selection, answering whether [id] resolved to a track.
     *
     * An id from a stale track list — or from before any list arrived — used to be swallowed and
     * reported as a success, which is indistinguishable from a device that simply refused it.
     */
    fun select(
        trackType: Int,
        id: String?,
    ): Boolean {
        val builder = trackSelector.buildUponParameters()

        if (id == null) {
            builder.clearOverridesOfType(trackType)
            if (trackType == C.TRACK_TYPE_TEXT) {
                builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            }
        } else {
            val (group, trackIndex) = byId[id] ?: return false
            builder.setOverrideForType(TrackSelectionOverride(group, trackIndex))
            if (trackType == C.TRACK_TYPE_TEXT) {
                builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            }
        }

        trackSelector.setParameters(builder)
        return true
    }

    /**
     * Sets the languages used when the engine picks tracks on its own.
     *
     * Subtitles stay off unless [autoSelectText] is set: matching a preferred language is what
     * decides *which* subtitle track wins, not whether subtitles appear at all.
     */
    fun applyPreferences(
        audioLanguages: List<String>?,
        textLanguages: List<String>?,
        autoSelectText: Boolean?,
    ) {
        val builder = trackSelector.buildUponParameters()

        audioLanguages?.let { builder.setPreferredAudioLanguages(*it.toTypedArray()) }
        textLanguages?.let { builder.setPreferredTextLanguages(*it.toTypedArray()) }
        autoSelectText?.let {
            builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, !it)
            builder.setSelectUndeterminedTextLanguage(it && textLanguages.isNullOrEmpty())
        }

        trackSelector.setParameters(builder)
    }

    private fun describe(
        id: String,
        index: Int,
        group: Tracks.Group,
        trackIndex: Int,
        playing: Format?,
        isUnambiguous: Boolean,
    ): Map<String, Any?> {
        val format = group.getTrackFormat(trackIndex)
        val isSelected = group.isTrackSelected(trackIndex)
        val isActive =
            isSelected && (isUnambiguous || playing == null || format.matches(playing))
        val common =
            mutableMapOf<String, Any?>(
                "id" to id,
                "index" to index,
                "label" to format.label,
                // "und" is the ISO code for "undetermined" and is what muxers write when nobody
                // tagged the track. Showing it in a picker is worse than showing nothing.
                "language" to format.language?.takeIf { it.isNotBlank() && it != "und" },
                "isSelected" to isSelected,
                "isActive" to isActive,
                "isSupported" to group.isTrackSupported(trackIndex),
                "isDefault" to format.hasSelectionFlag(C.SELECTION_FLAG_DEFAULT),
                "codecs" to format.codecs,
                "bitrate" to format.bitrate.orNull(),
            )

        when (group.type) {
            C.TRACK_TYPE_AUDIO ->
                common +=
                    mapOf(
                        "sampleRate" to format.sampleRate.orNull(),
                        "channelCount" to format.channelCount.orNull(),
                        "isDescriptive" to format.hasRoleFlag(C.ROLE_FLAG_DESCRIBES_VIDEO),
                    )

            C.TRACK_TYPE_TEXT ->
                common +=
                    mapOf(
                        "mimeType" to format.sampleMimeType,
                        "isForced" to format.hasSelectionFlag(C.SELECTION_FLAG_FORCED),
                        "isClosedCaption" to
                            (
                                format.hasRoleFlag(C.ROLE_FLAG_CAPTION) ||
                                    format.hasRoleFlag(C.ROLE_FLAG_DESCRIBES_MUSIC_AND_SOUND)
                            ),
                    )

            C.TRACK_TYPE_VIDEO ->
                common +=
                    mapOf(
                        "width" to format.width.orNull(),
                        "height" to format.height.orNull(),
                        "frameRate" to
                            format.frameRate.takeIf { it != Format.NO_VALUE.toFloat() }?.toDouble(),
                    )
        }

        return common
    }

    private fun typeName(trackType: Int): String =
        when (trackType) {
            C.TRACK_TYPE_AUDIO -> "audio"
            C.TRACK_TYPE_TEXT -> "text"
            C.TRACK_TYPE_VIDEO -> "video"
            else -> "other"
        }

    /**
     * Whether this format is the one the renderer is decoding.
     *
     * Manifest ids are the reliable comparison — the renderer's [Format] can carry extra fields
     * (initialisation data, DRM metadata) that make object equality fail on the same track.
     */
    private fun Format.matches(other: Format): Boolean =
        if (id != null && other.id != null) id == other.id else this == other

    private fun Format.hasSelectionFlag(flag: Int): Boolean = selectionFlags and flag != 0

    private fun Format.hasRoleFlag(flag: Int): Boolean = roleFlags and flag != 0

    private fun Int.orNull(): Int? = takeIf { it != Format.NO_VALUE }

    companion object {
        fun trackTypeOf(name: String?): Int =
            when (name) {
                "audio" -> C.TRACK_TYPE_AUDIO
                "text" -> C.TRACK_TYPE_TEXT
                "video" -> C.TRACK_TYPE_VIDEO
                else -> C.TRACK_TYPE_UNKNOWN
            }
    }
}
