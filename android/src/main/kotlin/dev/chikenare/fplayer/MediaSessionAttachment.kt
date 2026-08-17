package dev.chikenare.fplayer

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession

/**
 * The media session published for one player: lock screen, notification, headset buttons.
 *
 * Creation can legitimately fail — the host app may not have declared [FplayerMediaService] — so
 * this is built through [attach], which returns null instead of throwing. A player without a
 * session is still a perfectly working player.
 */
internal class MediaSessionAttachment private constructor(
    private val context: Context,
    private val playerId: Long,
    private val session: MediaSession,
) {
    fun release() {
        MediaSessionRegistry.unregister(context, playerId)
        session.release()
    }

    companion object {
        fun attach(
            context: Context,
            playerId: Long,
            player: ExoPlayer,
            background: Map<String, Any?>,
        ): MediaSessionAttachment? {
            if (background.bool("mediaSession") != true) return null
            if (!MediaSessionRegistry.isServiceDeclared(context)) return null

            val notification = background.map("notification")
            val session =
                runCatching {
                    MediaSession
                        .Builder(context, player)
                        // Ids must be unique within the process; two players would otherwise
                        // collide the moment a second one enabled its session.
                        .setId("fplayer_$playerId")
                        .apply { launchIntent(context)?.let(::setSessionActivity) }
                        .build()
                }.getOrNull() ?: return null

            MediaSessionRegistry.register(
                context = context,
                playerId = playerId,
                session = session,
                notificationOptions =
                    MediaSessionRegistry.NotificationOptions(
                        channelId = notification.string("channelId") ?: "fplayer_playback",
                        channelName = notification.string("channelName") ?: "Playback",
                        smallIconResource = notification.string("smallIconResource"),
                    ),
            )

            return MediaSessionAttachment(context.applicationContext, playerId, session)
        }

        /** Where tapping the notification takes the user: back into the app. */
        private fun launchIntent(context: Context): PendingIntent? {
            val intent =
                context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: return null
            intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)

            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
