package dev.chikenare.fplayer.download

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadNotificationHelper
import androidx.media3.exoplayer.offline.DownloadService
import androidx.media3.exoplayer.scheduler.PlatformScheduler
import androidx.media3.exoplayer.scheduler.Scheduler
import dev.chikenare.fplayer.map
import dev.chikenare.fplayer.string

/**
 * Foreground service that keeps downloads running when the app is not on screen.
 *
 * Deliberately **not** declared in the plugin's manifest, for the same reason as the media
 * session service: declaring it would make every consuming app carry foreground-service
 * permissions and justify them on the Play Console, including the ones that never download
 * anything. Apps that want offline playback declare it themselves; see the README.
 *
 * Without the declaration downloads still work, but only while the app is alive — which is a
 * reasonable degradation, and better than a crash inside `startService`.
 */
@OptIn(UnstableApi::class)
class FplayerDownloadService :
    DownloadService(
        FOREGROUND_NOTIFICATION_ID,
        DEFAULT_FOREGROUND_NOTIFICATION_UPDATE_INTERVAL,
    ) {
    private var notifications: DownloadNotificationHelper? = null

    override fun onCreate() {
        super.onCreate()
        // The system can create this service with no Dart engine running — after a reboot, or
        // when a scheduler decides the conditions are finally met. Initialising from the
        // persisted config is what makes it find the same cache directory as the app did.
        DownloadStore.initialize(this, null)
        createChannel()
    }

    override fun getDownloadManager(): DownloadManager {
        DownloadStore.initialize(this, null)
        return requireNotNull(DownloadStore.downloadManager) {
            "The download queue could not be created"
        }
    }

    /**
     * Scheduler that restarts pending work once its requirements are met.
     *
     * Null unless the app declared `RECEIVE_BOOT_COMPLETED`: the platform scheduler persists jobs
     * across reboots, and without the permission the job is silently dropped. Returning null keeps
     * the behaviour honest — downloads resume when the app next opens rather than pretending they
     * will resume on their own.
     */
    override fun getScheduler(): Scheduler? {
        if (!hasBootPermission()) return null
        return PlatformScheduler(this, JOB_ID)
    }

    override fun getForegroundNotification(
        downloads: MutableList<Download>,
        notMetRequirements: Int,
    ): Notification {
        val helper = notifications ?: DownloadNotificationHelper(this, channelId()).also {
            notifications = it
        }

        return helper.buildProgressNotification(
            this,
            smallIcon(),
            contentIntent(),
            null,
            downloads,
            notMetRequirements,
        )
    }

    /**
     * Creates the channel with the configured name.
     *
     * Media3's own helper names channels from a string resource, which settings arriving over a
     * method channel cannot provide.
     */
    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val id = channelId()
        if (manager.getNotificationChannel(id) != null) return

        manager.createNotificationChannel(
            NotificationChannel(
                id,
                notificationConfig().string("channelName") ?: "Downloads",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    /** Tapping the notification returns to the app rather than doing nothing. */
    private fun contentIntent(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        return PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun smallIcon(): Int {
        val name = notificationConfig().string("smallIconResource")
        if (name != null) {
            @Suppress("DiscouragedApi")
            val id = resources.getIdentifier(name, "drawable", packageName)
            if (id != 0) return id
        }
        return android.R.drawable.stat_sys_download
    }

    private fun notificationConfig(): Map<String, Any?> = DownloadStore.config.map("notification")

    private fun channelId(): String =
        notificationConfig().string("channelId") ?: "fplayer_downloads"

    private fun hasBootPermission(): Boolean =
        checkSelfPermission(android.Manifest.permission.RECEIVE_BOOT_COMPLETED) ==
            PackageManager.PERMISSION_GRANTED

    private companion object {
        const val FOREGROUND_NOTIFICATION_ID = 0x1F19
        const val JOB_ID = 0x1F19
    }
}
