package dev.chikenare.fplayer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Foreground service that carries the playback notification and keeps audio alive in the
 * background.
 *
 * It is deliberately **not** declared in the plugin's manifest. Declaring it would force every
 * consuming app to ship the foreground-service permissions and justify them on the Play Console,
 * even the ones that only ever play video inline. Apps that want a media session add the
 * declaration themselves; see the README.
 *
 * The usual Media3 flow is inverted here: the session already exists, owned by a [PlayerHost] that
 * Dart created, so the service adopts it from [MediaSessionRegistry] instead of building its own.
 */
class FplayerMediaService : MediaSessionService() {
    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()

        MediaSessionRegistry.options?.let { options ->
            createChannel(options)
            setMediaNotificationProvider(
                DefaultMediaNotificationProvider
                    .Builder(this)
                    .setChannelId(options.channelId)
                    .build()
                    .apply { options.smallIconResourceId(this@FplayerMediaService)?.let(::setSmallIcon) },
            )
        }

        MediaSessionRegistry.attachService(this)
    }

    override fun onDestroy() {
        MediaSessionRegistry.detachService(this)
        super.onDestroy()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
        MediaSessionRegistry.primary()

    /**
     * Creates the channel up front so the configured name is used.
     *
     * Media3's provider only creates the channel when it is missing, and it names it from a string
     * resource — which config coming over a method channel cannot supply.
     */
    private fun createChannel(options: MediaSessionRegistry.NotificationOptions) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(options.channelId) != null) return

        manager.createNotificationChannel(
            NotificationChannel(
                options.channelId,
                options.channelName,
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }
}

/**
 * Bridge between the players, which own the sessions, and the service, which the system owns.
 *
 * Process-wide state is unusual in this codebase, but a service cannot be handed constructor
 * arguments and the system may create it at any moment, so the sessions have to be reachable
 * without an instance.
 */
internal object MediaSessionRegistry {
    /** Notification settings of the most recently registered session. */
    var options: NotificationOptions? = null
        private set

    private val sessions = linkedMapOf<Long, MediaSession>()
    private var service: FplayerMediaService? = null

    /** Whether `startService` has been called for a service the system has not created yet. */
    private var isStartRequested = false

    data class NotificationOptions(
        val channelId: String,
        val channelName: String,
        val smallIconResource: String?,
    ) {
        fun smallIconResourceId(context: Context): Int? {
            val name = smallIconResource ?: return null
            @Suppress("DiscouragedApi")
            val id = context.resources.getIdentifier(name, "drawable", context.packageName)
            return id.takeIf { it != 0 }
        }
    }

    /**
     * Whether the host app declared the service.
     *
     * Without the declaration `startService` throws, so this is checked before a session is ever
     * built and the feature degrades to "no session" instead of crashing the app.
     */
    fun isServiceDeclared(context: Context): Boolean =
        runCatching {
            context.packageManager.getServiceInfo(
                ComponentName(context, FplayerMediaService::class.java),
                0,
            )
            true
        }.getOrDefault(false)

    fun register(
        context: Context,
        playerId: Long,
        session: MediaSession,
        notificationOptions: NotificationOptions,
    ) {
        options = notificationOptions
        sessions[playerId] = session

        service?.addSession(session)

        // Unconditional, even when the service looks alive: `stopSelf` is asynchronous, so a
        // player registering between a stop and the `onDestroy` that follows it would otherwise
        // attach to a service on its way out and end up with none at all. `startService` is
        // idempotent and supersedes a pending stop, which is exactly what is wanted here.
        //
        // Safe at this point: a player is only created while the app is in the foreground, and
        // the service promotes itself once playback actually begins.
        runCatching {
            context.startService(Intent(context, FplayerMediaService::class.java))
            isStartRequested = true
        }
    }

    fun unregister(
        context: Context,
        playerId: Long,
    ) {
        val session = sessions.remove(playerId) ?: return
        service?.let { if (it.isSessionAdded(session)) it.removeSession(session) }
        if (sessions.isNotEmpty()) return

        val running = service
        if (running != null) {
            running.stopSelf()
            return
        }
        // Started but not yet created — a player opened and disposed in the same breath. Nothing
        // exists to call `stopSelf` on, and without this the service would arrive to an empty
        // registry and sit in the process with nothing to do and nobody to stop it.
        if (isStartRequested) {
            runCatching { context.stopService(Intent(context, FplayerMediaService::class.java)) }
            isStartRequested = false
        }
    }

    fun primary(): MediaSession? = sessions.values.firstOrNull()

    fun attachService(service: FplayerMediaService) {
        this.service = service
        isStartRequested = false
        // The last player went away while the service was still being created.
        if (sessions.isEmpty()) {
            service.stopSelf()
            return
        }
        sessions.values.forEach { session ->
            if (!service.isSessionAdded(session)) service.addSession(session)
        }
    }

    fun detachService(service: FplayerMediaService) {
        if (this.service === service) this.service = null
    }
}
