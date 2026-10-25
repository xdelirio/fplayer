package dev.chikenare.fplayer

import android.app.Activity
import android.provider.Settings
import android.view.WindowManager

/**
 * The two things a video player needs from the host window: that it stays lit, and that its
 * brightness can be dragged.
 *
 * Both are Activity-level properties, not player-level ones, which is why this is shared rather
 * than owned by a [PlayerHost]. Several players can coexist, so keeping the screen on is
 * reference-counted: the flag stays while *any* of them is playing and clears when the last one
 * stops. A single boolean would let a paused player switch the screen off under a playing one.
 */
internal class WindowController {
    private var activity: Activity? = null

    /** Players currently asking for the screen to stay on. */
    private val holders = mutableSetOf<Long>()

    /** Brightness override in `0..1`, or null while the system value is in force. */
    private var override: Float? = null

    /** The player that set [override], so its disposal can hand the screen back. */
    private var overrideOwner: Long? = null

    fun attach(activity: Activity) {
        this.activity = activity
        // A configuration change rebuilds the Activity with a fresh window, so both settings have
        // to be reapplied rather than assumed to have survived.
        applyKeepScreenOn()
        applyBrightness()
    }

    fun detach() {
        activity = null
    }

    fun setKeepScreenOn(
        playerId: Long,
        enabled: Boolean,
    ) {
        val changed = if (enabled) holders.add(playerId) else holders.remove(playerId)
        if (changed) applyKeepScreenOn()
    }

    /**
     * Lets go of everything [playerId] asked of the window.
     *
     * Brightness included: the override lives on the Activity's window, not on the player, so
     * left in place it dimmed or lit every other screen of the app long after the video closed.
     */
    fun release(playerId: Long) {
        setKeepScreenOn(playerId, false)
        if (overrideOwner == playerId) setBrightness(playerId, null)
    }

    /**
     * Sets the window's brightness, or restores the system value when [value] is null.
     *
     * Scoped to this window: it does not touch the device setting, so leaving the app — or
     * crashing — puts the screen back to normal on its own.
     */
    fun setBrightness(
        playerId: Long,
        value: Double?,
    ) {
        override = value?.toFloat()?.coerceIn(0f, 1f)
        overrideOwner = if (override == null) null else playerId
        applyBrightness()
    }

    /**
     * Brightness the drag should start from.
     *
     * With no override in force there is nothing to read off the window, so the device setting is
     * used instead — otherwise the first drag would jump from wherever the system happened to be
     * to whatever the gesture computed from zero.
     */
    fun brightness(): Double {
        override?.let { return it.toDouble() }

        val resolver = activity?.contentResolver ?: return 0.5
        return try {
            // Some vendors widen the range past 255; a start above 1 made the first drag stall.
            (Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0)
                .coerceIn(0.0, 1.0)
        } catch (e: Settings.SettingNotFoundException) {
            0.5
        }
    }

    private fun applyKeepScreenOn() {
        val window = activity?.window ?: return
        if (holders.isEmpty()) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun applyBrightness() {
        val window = activity?.window ?: return
        window.attributes =
            window.attributes.apply {
                screenBrightness =
                    override ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            }
    }
}
