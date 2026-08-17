package dev.chikenare.fplayer.download

import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.offline.Download
import java.io.FileNotFoundException
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * Serialises a queue entry for Dart.
 *
 * Failures are classified into the same taxonomy playback errors use, so an app branches on one
 * set of codes whether the bytes were being streamed or stored.
 */
@OptIn(UnstableApi::class)
internal object DownloadMapper {
    fun toMap(
        download: Download,
        failure: Throwable?,
    ): Map<String, Any?> =
        mapOf(
            "id" to download.request.id,
            "uri" to download.request.uri.toString(),
            "state" to stateName(download),
            "percent" to download.percentDownloaded.toDouble(),
            "bytesDownloaded" to download.bytesDownloaded,
            "contentLength" to download.contentLength,
            "startedAtMs" to download.startTimeMs,
            "updatedAtMs" to download.updateTimeMs,
            "metadata" to DownloadStore.metadataOf(download.request.data),
            "error" to
                if (download.state == Download.STATE_FAILED) errorMap(failure) else null,
        )

    /**
     * `STATE_STOPPED` is Media3's name for "held by a stop reason", which only this plugin sets,
     * and only when the app pauses a download.
     */
    private fun stateName(download: Download): String =
        when (download.state) {
            Download.STATE_QUEUED -> "queued"
            Download.STATE_DOWNLOADING -> "downloading"
            Download.STATE_STOPPED -> "paused"
            Download.STATE_COMPLETED -> "completed"
            Download.STATE_FAILED -> "failed"
            Download.STATE_REMOVING -> "removing"
            Download.STATE_RESTARTING -> "restarting"
            else -> "queued"
        }

    fun errorMap(failure: Throwable?): Map<String, Any?> {
        val status = httpStatusOf(failure)
        val code = classify(failure, status)

        return mapOf(
            "code" to code,
            "message" to (failure?.message ?: "The download failed"),
            "nativeCode" to failure?.let { it::class.java.simpleName },
            "httpStatus" to status,
            "retryable" to isRetryable(code, status),
        )
    }

    private fun classify(
        failure: Throwable?,
        status: Int?,
    ): String =
        when {
            status == 401 -> "unauthorized"
            status == 403 -> "forbidden"
            status == 404 || status == 410 -> "notFound"
            status != null -> "badHttpStatus"
            failure is UnknownHostException -> "network"
            failure is SocketTimeoutException -> "timeout"
            failure is HttpDataSource.CleartextNotPermittedException -> "cleartextNotPermitted"
            failure is FileNotFoundException -> "notFound"
            failure is IOException -> "io"
            failure == null -> "unknown"
            else -> "io"
        }

    private fun isRetryable(
        code: String,
        status: Int?,
    ): Boolean =
        when (code) {
            "network", "timeout", "io", "unknown" -> true
            "badHttpStatus" -> status == null || status >= 500 || status == 429
            else -> false
        }

    private fun httpStatusOf(failure: Throwable?): Int? {
        var cause: Throwable? = failure
        while (cause != null) {
            if (cause is HttpDataSource.InvalidResponseCodeException) return cause.responseCode
            cause = cause.cause
        }
        return null
    }
}
