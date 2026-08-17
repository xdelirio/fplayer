package dev.chikenare.fplayer

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy

/**
 * How a single failed *load* is retried, as opposed to a failed *source*.
 *
 * These are two different ladders and confusing them produces minute-long stalls:
 *
 * - **This one** runs inside ExoPlayer, per segment, manifest refresh or key request. A dropped
 *   chunk is retried here without the player ever leaving the playing state, and the viewer sees
 *   at most a brief stall.
 * - **`FRetryPolicy`** runs in `FPlayerController`, per source. It only comes into play once this
 *   ladder is exhausted and the whole playback has failed, and every attempt means re-preparing
 *   from scratch.
 *
 * Their budgets multiply. Three segment retries at up to 5 s each, wrapped in three source retries
 * with exponential backoff, is over a minute of spinner before an error is shown — which is why
 * both are configurable and why the difference is spelled out here.
 */
@OptIn(UnstableApi::class)
internal class FplayerLoadErrorPolicy(
    retryCount: Int,
    private val baseDelayMs: Long,
    private val maxDelayMs: Long,
    private val isOnline: () -> Boolean,
) : DefaultLoadErrorHandlingPolicy(retryCount) {
    override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
        // Retrying a chunk against a device with no network cannot succeed, and each attempt is a
        // socket timeout of dead waiting. Give up immediately so the failure reaches the host,
        // which parks playback until the signal is back instead of grinding through the budget.
        if (!isOnline()) return C.TIME_UNSET

        // Superclass first: it is what knows a 404 or a 403 will never become a 200, and its
        // verdict of "do not retry" must survive our own backoff.
        if (super.getRetryDelayMsFor(loadErrorInfo) == C.TIME_UNSET) return C.TIME_UNSET

        val exponent = (loadErrorInfo.errorCount - 1).coerceIn(0, MAX_EXPONENT)
        return (baseDelayMs shl exponent).coerceAtMost(maxDelayMs)
    }

    companion object {
        /** Caps the shift so a pathological error count cannot overflow the delay. */
        private const val MAX_EXPONENT = 16

        fun from(
            network: Map<String, Any?>,
            isOnline: () -> Boolean,
        ): LoadErrorHandlingPolicy {
            val retryCount =
                network.int("segmentRetryCount") ?: DEFAULT_MIN_LOADABLE_RETRY_COUNT
            val baseDelay = network.long("segmentRetryBaseDelayMs") ?: DEFAULT_BASE_DELAY_MS
            val maxDelay =
                (network.long("segmentRetryMaxDelayMs") ?: DEFAULT_MAX_DELAY_MS)
                    .coerceAtLeast(baseDelay)

            return FplayerLoadErrorPolicy(
                retryCount = retryCount.coerceAtLeast(0),
                baseDelayMs = baseDelay.coerceAtLeast(0),
                maxDelayMs = maxDelay,
                isOnline = isOnline,
            )
        }

        /** Media3's own first-retry delay, kept so the default behaviour is unchanged. */
        private const val DEFAULT_BASE_DELAY_MS = 1_000L
        private const val DEFAULT_MAX_DELAY_MS = 5_000L
    }
}
