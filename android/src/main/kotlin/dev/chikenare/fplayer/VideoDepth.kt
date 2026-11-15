package dev.chikenare.fplayer

import androidx.annotation.OptIn
import androidx.media3.common.ColorInfo
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi

/**
 * Tells video a Flutter texture can show from video it cannot: more than 8 bits a sample.
 *
 * See `PlayerHost.moveToSurfaceView` for what goes wrong and what is done about it.
 */
@OptIn(UnstableApi::class)
internal object VideoDepth {
    fun isBeyondTexture(format: Format): Boolean {
        val color = format.colorInfo
        if (color != null) {
            if (color.lumaBitdepth > 8 || color.chromaBitdepth > 8) return true
            // HDR is never 8-bit, and some containers give the transfer without the depth.
            if (ColorInfo.isTransferHdr(color)) return true
        }
        if (format.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION) return true
        return isBeyondTexture(format.codecs)
    }

    /**
     * The same question asked of an RFC 6381 codecs string, which is all an HLS or DASH manifest
     * gives before the first segment is read.
     */
    fun isBeyondTexture(codecs: String?): Boolean =
        codecs.orEmpty().split(',').any { isDeepCodec(it.trim()) }

    private fun isDeepCodec(codec: String): Boolean {
        val parts = codec.split('.')
        return when (parts[0]) {
            // av01.<profile>.<level><tier>.<bitDepth>
            "av01" -> (parts.getOrNull(3)?.toIntOrNull() ?: 8) > 8
            // vp09.<profile>.<level>.<bitDepth>
            "vp09" -> (parts.getOrNull(3)?.toIntOrNull() ?: 8) > 8
            // hvc1.<space><profile>…: profile 2 is Main 10. The others above it are range
            // extensions, deeper more often than not.
            "hvc1", "hev1" ->
                (parts.getOrNull(1)?.trimStart('A', 'B', 'C')?.toIntOrNull() ?: 1) >= 2
            // Dolby Vision, in all its spellings.
            "dvhe", "dvh1", "dvav", "dva1", "dav1" -> true
            else -> false
        }
    }
}
