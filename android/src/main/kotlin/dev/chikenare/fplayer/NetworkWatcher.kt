package dev.chikenare.fplayer

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper

/**
 * Watches whether this device has a usable network, per player.
 *
 * The point is not to display a signal bar: it is to tell a failed load apart from a failed
 * *network*. Retrying a segment against a device that is in a tunnel burns the retry budget in a
 * couple of seconds and lands the viewer on an error screen, when the right behaviour is to wait
 * and resume the moment the signal returns.
 *
 * Needs `ACCESS_NETWORK_STATE`, which `media3-exoplayer` already declares, so consuming apps get
 * it transitively and nothing has to be added to their manifest. If an app strips it anyway, every
 * query degrades to "online" and the player behaves exactly as it did before this class existed —
 * losing a nicety is acceptable, breaking playback is not.
 */
internal class NetworkWatcher(
    context: Context,
    private val onNetworkRestored: () -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())

    private val connectivity: ConnectivityManager? =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    private var isRegistered = false

    /** Last state seen, so a restored network is only announced when it was actually lost. */
    private var wasOnline = true

    private val callback =
        object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                post()
            }

            override fun onLost(network: Network) {
                post()
            }

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) {
                post()
            }

            // Callbacks arrive on a binder thread; ExoPlayer and the Flutter channels both insist
            // on the main one.
            private fun post() {
                handler.post(::reconcile)
            }
        }

    /**
     * Whether a network capable of carrying traffic exists *right now*.
     *
     * Queried live rather than read from the last callback because the two race: ExoPlayer often
     * notices a dead socket before the system posts `onLost`, and the whole decision of whether an
     * error means "retry" or "wait" hangs on getting this right at that instant.
     *
     * Capability, not validation: a network that has not finished captive-portal checks still
     * carries a CDN request more often than not, and treating it as offline would strand playback
     * on connections that work.
     */
    fun isOnline(): Boolean {
        val manager = connectivity ?: return true
        return try {
            val network = manager.activeNetwork ?: return false
            val capabilities = manager.getNetworkCapabilities(network) ?: return false
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } catch (_: SecurityException) {
            true
        }
    }

    fun start() {
        val manager = connectivity ?: return
        if (isRegistered) return

        try {
            manager.registerDefaultNetworkCallback(callback)
            isRegistered = true
            wasOnline = isOnline()
        } catch (_: SecurityException) {
            // No permission: stay unregistered and let isOnline() report optimistically.
        } catch (_: RuntimeException) {
            // Some OEM builds throw from the connectivity stack under memory pressure.
        }
    }

    fun stop() {
        val manager = connectivity ?: return
        if (!isRegistered) return
        isRegistered = false

        handler.removeCallbacksAndMessages(null)
        try {
            manager.unregisterNetworkCallback(callback)
        } catch (_: IllegalArgumentException) {
            // Already unregistered by a system teardown.
        }
    }

    private fun reconcile() {
        val online = isOnline()
        if (online == wasOnline) return

        wasOnline = online
        if (online) onNetworkRestored()
    }
}
