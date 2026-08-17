package dev.chikenare.fplayer

import android.app.Activity
import android.app.AppOpsManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.ComponentCallbacks
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import androidx.core.content.ContextCompat

/**
 * Drives Picture-in-Picture for the host Activity.
 *
 * PiP is an Activity-level mode, not a view-level one: the system shrinks the whole window. Only
 * one player can own it at a time, so this lives on the plugin and players borrow it.
 *
 * Window controls are [RemoteAction]s backed by broadcasts, because the system draws them in its
 * own process and can only talk back through a [PendingIntent].
 */
internal class PipController(
    private val appContext: Context,
) {
    /** The player currently driving the PiP window. */
    interface Owner {
        /** Video shape, or null before a first frame has arrived. */
        val pipAspectRatio: Rational?

        val pipIsPlaying: Boolean

        fun onPipAction(action: String)

        fun onPipStateChanged(
            isActive: Boolean,
            isSupported: Boolean,
        )
    }

    private val actionIntent = "${appContext.packageName}.fplayer.PIP_ACTION"

    private var activity: Activity? = null
    private var owner: Owner? = null
    private var isReceiverRegistered = false

    private val receiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context?,
                intent: Intent?,
            ) {
                val action = intent?.getStringExtra(EXTRA_ACTION) ?: return
                owner?.onPipAction(action)
            }
        }

    /**
     * Entering and leaving PiP resizes the Activity, and a resize is a configuration change.
     * The framework's own `onPictureInPictureModeChanged` is not forwarded by Flutter's plugin
     * binding, so this is how the state transition is observed.
     */
    private val configCallbacks =
        object : ComponentCallbacks {
            override fun onConfigurationChanged(newConfig: Configuration) = syncState()

            override fun onLowMemory() = Unit
        }

    fun attach(activity: Activity) {
        this.activity = activity
        activity.registerComponentCallbacks(configCallbacks)
        registerReceiver()
        syncState()
    }

    fun detach() {
        disarmAutoEnter()
        activity?.unregisterComponentCallbacks(configCallbacks)
        activity = null
        unregisterReceiver()
        // The button Dart is showing now leads nowhere: with no Activity, `isSupported` is false.
        syncState()
    }

    fun setOwner(owner: Owner?) {
        if (this.owner === owner) return
        this.owner = owner
        syncState()
    }

    /** Drops [owner] only if it is the one currently registered, so disposal cannot steal PiP. */
    fun releaseOwner(owner: Owner) {
        if (this.owner !== owner) return
        disarmAutoEnter()
        setOwner(null)
    }

    /**
     * Tells the system to stop shrinking this Activity into PiP when the user leaves.
     *
     * The parameters set with `setAutoEnterEnabled(true)` live on the Activity, not on the
     * player, and nothing clears them when the player goes away. Left armed, pressing Home from
     * a settings screen — long after the video was closed — put the app into a PiP window with
     * no video in it, for the rest of the Activity's life.
     */
    private fun disarmAutoEnter() {
        if (!autoEnterRequested) return
        autoEnterRequested = false

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val activity = activity ?: return
        runCatching {
            activity.setPictureInPictureParams(
                PictureInPictureParams.Builder().setAutoEnterEnabled(false).build(),
            )
        }
    }

    /**
     * Whether a PiP request could succeed right now.
     *
     * Covers the OS version, the hardware (Android Go and many TVs ship without PiP) and the
     * per-app permission. It cannot cover the Activity's `supportsPictureInPicture` flag: the
     * `ActivityInfo` constant that would reveal it is hidden from the public SDK, so a missing
     * declaration only shows up as [enter] returning false.
     */
    fun isSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (activity == null) return false

        if (!appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            return false
        }

        return isPipAllowedByUser()
    }

    fun isActive(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity?.isInPictureInPictureMode == true

    /**
     * Requests the PiP window.
     *
     * Returns false rather than throwing when the platform refuses: a missing manifest flag or a
     * revoked permission is a configuration problem the caller should be able to react to, not a
     * crash.
     */
    fun enter(
        owner: Owner,
        actions: List<String>,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val activity = activity ?: return false
        if (!isSupported()) return false

        setOwner(owner)
        return runCatching {
            activity.enterPictureInPictureMode(buildParams(owner, actions))
        }.getOrDefault(false)
    }

    /**
     * Leaves PiP by bringing the Activity back to the front.
     *
     * Android offers no "exit PiP" call; re-launching the task is the supported way, and it is
     * what the system itself does when the user taps the window.
     */
    fun exit() {
        val activity = activity ?: return
        if (!isActive()) return

        val intent =
            appContext.packageManager
                .getLaunchIntentForPackage(appContext.packageName)
                ?.apply { addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT) }
                ?: return
        activity.startActivity(intent)
    }

    /**
     * Refreshes the window controls, so the play button becomes a pause button as soon as
     * playback starts rather than at the next transition.
     */
    fun refreshActions(
        owner: Owner,
        actions: List<String>,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (this.owner !== owner) return
        val activity = activity ?: return
        if (!isActive() && !autoEnterRequested) return

        runCatching { activity.setPictureInPictureParams(buildParams(owner, actions)) }
    }

    /**
     * Arms the seamless auto-enter transition.
     *
     * On Android 12+ the system performs the shrink itself when the user leaves, which animates
     * far better than reacting to the leave hint after the fact. Older versions fall back to
     * [onUserLeaveHint].
     */
    fun setAutoEnter(
        owner: Owner,
        enabled: Boolean,
        actions: List<String>,
    ) {
        autoEnterRequested = enabled
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val activity = activity ?: return
        if (!isSupported()) return

        setOwner(owner)
        runCatching { activity.setPictureInPictureParams(buildParams(owner, actions)) }
    }

    /**
     * Last-resort auto-enter for Android 11 and below, where `setAutoEnterEnabled` does not exist.
     *
     * The transition is visibly less smooth, which is why it is only used as a fallback.
     */
    fun onUserLeaveHint(
        owner: Owner,
        actions: List<String>,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        if (!autoEnterRequested || !owner.pipIsPlaying) return
        enter(owner, actions)
    }

    /** Re-reads the platform state and reports it upward when something moved. */
    fun syncState() {
        val owner = this.owner ?: return
        val active = isActive()
        // The window needs a shape to size itself, so a player with no frame yet cannot offer PiP.
        val supported = isSupported() && owner.pipAspectRatio != null

        owner.onPipStateChanged(isActive = active, isSupported = supported)
    }

    private var autoEnterRequested = false

    private fun buildParams(
        owner: Owner,
        actions: List<String>,
    ): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()

        owner.pipAspectRatio?.let(builder::setAspectRatio)
        builder.setActions(remoteActions(owner, actions))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnterRequested)
            // Without this the system crossfades on every resize, which looks like a glitch on a
            // surface that is already producing frames at the new size.
            builder.setSeamlessResizeEnabled(true)
        }

        return builder.build()
    }

    private fun remoteActions(
        owner: Owner,
        actions: List<String>,
    ): List<RemoteAction> {
        val activity = activity ?: return emptyList()
        val max =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.maxNumPictureInPictureActions
            } else {
                0
            }
        if (max <= 0) return emptyList()

        return actions.take(max).mapIndexedNotNull { index, action ->
            val isPause = action == ACTION_PLAY_PAUSE && owner.pipIsPlaying
            val icon =
                when (action) {
                    ACTION_PLAY_PAUSE ->
                        if (isPause) {
                            android.R.drawable.ic_media_pause
                        } else {
                            android.R.drawable.ic_media_play
                        }
                    ACTION_SKIP_FORWARD -> android.R.drawable.ic_media_ff
                    ACTION_SKIP_BACKWARD -> android.R.drawable.ic_media_rew
                    else -> return@mapIndexedNotNull null
                }
            val title =
                when (action) {
                    ACTION_PLAY_PAUSE -> if (isPause) "Pause" else "Play"
                    ACTION_SKIP_FORWARD -> "Forward"
                    else -> "Rewind"
                }

            RemoteAction(
                Icon.createWithResource(appContext, icon),
                title,
                title,
                pendingIntentFor(action, index),
            )
        }
    }

    private fun pendingIntentFor(
        action: String,
        requestCode: Int,
    ): PendingIntent =
        PendingIntent.getBroadcast(
            appContext,
            requestCode,
            Intent(actionIntent)
                .setPackage(appContext.packageName)
                .putExtra(EXTRA_ACTION, action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun registerReceiver() {
        if (isReceiverRegistered) return
        val filter = IntentFilter(actionIntent)

        // Below Tiramisu an action-only filter with no permission is exported by default, so
        // any app on the device could drive play, pause and seek by broadcasting the action.
        // `ContextCompat` back-fills the not-exported flag on those versions.
        ContextCompat.registerReceiver(
            appContext,
            receiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        isReceiverRegistered = true
    }

    private fun unregisterReceiver() {
        if (!isReceiverRegistered) return
        runCatching { appContext.unregisterReceiver(receiver) }
        isReceiverRegistered = false
    }

    /**
     * Users can turn PiP off per app in system settings. When they have, entering silently fails,
     * so it is better to stop offering the button. An unreadable app-op is treated as allowed —
     * failing open keeps a working feature working on devices with an odd AppOps implementation.
     */
    private fun isPipAllowedByUser(): Boolean {
        val appOps =
            appContext.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return true

        return runCatching {
            val mode =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    appOps.unsafeCheckOpNoThrow(
                        OP_PICTURE_IN_PICTURE,
                        android.os.Process.myUid(),
                        appContext.packageName,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    appOps.checkOpNoThrow(
                        OP_PICTURE_IN_PICTURE,
                        android.os.Process.myUid(),
                        appContext.packageName,
                    )
                }
            mode == AppOpsManager.MODE_ALLOWED
        }.getOrDefault(true)
    }

    companion object {
        const val ACTION_PLAY_PAUSE = "playPause"
        const val ACTION_SKIP_FORWARD = "skipForward"
        const val ACTION_SKIP_BACKWARD = "skipBackward"

        private const val EXTRA_ACTION = "fplayer.action"
        private const val OP_PICTURE_IN_PICTURE = "android:picture_in_picture"
    }
}
