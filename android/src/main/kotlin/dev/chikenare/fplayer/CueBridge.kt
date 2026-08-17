package dev.chikenare.fplayer

import android.text.Layout
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup

/**
 * Serialises subtitle cues for the Flutter renderer.
 *
 * Only the geometry a renderer can act on crosses the bridge. Positions are normalised to
 * fractions of the video rectangle so the Dart side never has to know about ExoPlayer's anchor
 * and line-type constants.
 */
internal object CueBridge {
    /** WebVTT's assumed number of text rows, used to turn line *numbers* into fractions. */
    private const val ASSUMED_ROWS = 15f

    fun toMap(group: CueGroup): Map<String, Any?> =
        mapOf(
            "event" to "cues",
            "cues" to group.cues.mapNotNull(::describe),
        )

    private fun describe(cue: Cue): Map<String, Any?>? {
        // Bitmap cues (PGS, DVB, some CEA-708) carry an image rather than text. Skipping them is
        // better than showing an empty box; rendering them needs an image channel.
        val text = cue.text?.toString()?.takeIf { it.isNotBlank() } ?: return null

        val (line, lineAnchor) = verticalPlacement(cue)

        return mapOf(
            "text" to text,
            "align" to alignmentOf(cue.textAlignment),
            "line" to line,
            "lineAnchor" to lineAnchor,
            "position" to cue.position.orNull(),
            "positionAnchor" to anchorOf(cue.positionAnchor),
            "size" to cue.size.orNull(),
            "isVertical" to (cue.verticalType != Cue.TYPE_UNSET),
        )
    }

    /**
     * Vertical placement as a fraction of the video height, plus which edge of the cue box that
     * fraction pins.
     *
     * `LINE_TYPE_FRACTION` is already a fraction. `LINE_TYPE_NUMBER` counts text rows and is
     * converted against the 15-row grid WebVTT assumes — the same approximation Media3's own
     * subtitle view makes. A *negative* row counts up from the bottom, and crucially anchors the
     * bottom of the cue: `line:-1` means "the last row", so the box has to grow upward. Treating
     * it as a top anchor pushes multi-line cues off the bottom of the picture.
     */
    private fun verticalPlacement(cue: Cue): Pair<Double?, String> {
        val line = cue.line
        if (line == Cue.DIMEN_UNSET) return null to anchorOf(cue.lineAnchor)

        return when (cue.lineType) {
            Cue.LINE_TYPE_FRACTION -> line.toDouble().coerceIn(0.0, 1.0) to anchorOf(cue.lineAnchor)

            Cue.LINE_TYPE_NUMBER ->
                if (line >= 0) {
                    (line / ASSUMED_ROWS).toDouble().coerceIn(0.0, 1.0) to "start"
                } else {
                    ((ASSUMED_ROWS + line + 1) / ASSUMED_ROWS).toDouble().coerceIn(0.0, 1.0) to "end"
                }

            else -> null to anchorOf(cue.lineAnchor)
        }
    }

    private fun alignmentOf(alignment: Layout.Alignment?): String =
        when (alignment) {
            Layout.Alignment.ALIGN_NORMAL -> "start"
            Layout.Alignment.ALIGN_OPPOSITE -> "end"
            else -> "center"
        }

    private fun anchorOf(anchor: Int): String =
        when (anchor) {
            Cue.ANCHOR_TYPE_MIDDLE -> "middle"
            Cue.ANCHOR_TYPE_END -> "end"
            else -> "start"
        }

    private fun Float.orNull(): Double? = takeIf { it != Cue.DIMEN_UNSET }?.toDouble()
}
