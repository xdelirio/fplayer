package dev.chikenare.fplayer

import androidx.media3.common.PlaybackException
import androidx.media3.datasource.HttpDataSource

/**
 * Translates a [PlaybackException] into the stable taxonomy consumed by Dart.
 *
 * The point is that callers can branch on *meaning* ("the token expired", "this codec is not
 * supported here") instead of on ExoPlayer's numeric codes, which are an implementation detail of
 * the current engine.
 */
internal object ErrorMapper {
    fun toMap(error: PlaybackException): Map<String, Any?> {
        val httpStatus = httpStatusOf(error)
        val code = classify(error, httpStatus)

        return mapOf(
            "code" to code,
            "message" to (error.message ?: error.errorCodeName),
            "nativeCode" to error.errorCodeName,
            "httpStatus" to httpStatus,
            "retryable" to isRetryable(code, httpStatus),
        )
    }

    private fun classify(
        error: PlaybackException,
        httpStatus: Int?,
    ): String =
        when (error.errorCode) {
            PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW -> "behindLiveWindow"

            PlaybackException.ERROR_CODE_TIMEOUT,
            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            -> "timeout"

            PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED -> "network"

            PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS ->
                when (httpStatus) {
                    401 -> "unauthorized"
                    403 -> "forbidden"
                    404, 410 -> "notFound"
                    else -> "badHttpStatus"
                }

            PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND -> "notFound"
            PlaybackException.ERROR_CODE_IO_NO_PERMISSION -> "forbidden"
            PlaybackException.ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED -> "cleartextNotPermitted"

            PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
            PlaybackException.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE,
            PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,
            -> "io"

            PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED,
            -> "malformedContent"

            PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
            PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            -> "unsupportedFormat"

            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FAILED,
            -> "decoder"

            PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED,
            PlaybackException.ERROR_CODE_AUDIO_TRACK_WRITE_FAILED,
            -> "audioOutput"

            in DRM_ERROR_RANGE -> "drm"

            else -> "unknown"
        }

    /**
     * Whether retrying the same source has a plausible chance of succeeding. A 5xx is transient;
     * a 404 or an unsupported codec is not.
     */
    private fun isRetryable(
        code: String,
        httpStatus: Int?,
    ): Boolean =
        when (code) {
            "network", "timeout", "io", "behindLiveWindow" -> true
            "badHttpStatus" -> httpStatus == null || httpStatus >= 500 || httpStatus == 429
            else -> false
        }

    private fun httpStatusOf(error: PlaybackException): Int? {
        var cause: Throwable? = error.cause
        while (cause != null) {
            if (cause is HttpDataSource.InvalidResponseCodeException) {
                return cause.responseCode
            }
            cause = cause.cause
        }
        return null
    }

    private val DRM_ERROR_RANGE =
        PlaybackException.ERROR_CODE_DRM_UNSPECIFIED..PlaybackException.ERROR_CODE_DRM_DEVICE_REVOKED
}
