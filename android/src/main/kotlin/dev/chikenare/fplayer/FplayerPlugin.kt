package dev.chikenare.fplayer

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Entry point of the plugin.
 *
 * Owns the registry of [PlayerHost] instances. Every player created from Dart gets its own
 * texture, method channel and event channel, so several players can coexist without sharing
 * state.
 *
 * The Activity is tracked because Picture-in-Picture is a window-level mode: it belongs to the
 * Activity, not to any one player, so a single [PipController] is shared and players borrow it.
 *
 */
class FplayerPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler {
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var channel: MethodChannel? = null
    private var pip: PipController? = null
    private val window = WindowController()
    private var activityBinding: ActivityPluginBinding? = null
    private val players = mutableMapOf<Long, PlayerHost>()
    /**
     * Process-wide, not per plugin instance.
     *
     * The media session registry and Media3's own session map are statics, and the session id is
     * built from this: a second Flutter engine starting again at 1 collided with the first
     * engine's player, which made `MediaSession.Builder.build()` throw and left that player
     * silently without a session.
     */
    private val nextPlayerId = java.util.concurrent.atomic.AtomicLong(1)

    private val userLeaveHintListener =
        PluginRegistry.UserLeaveHintListener { players.values.forEach(PlayerHost::onUserLeaveHint) }

    // Losing window focus is the earliest reliable hint that the app slipped into the PiP window;
    // the configuration change that follows confirms it.
    private val windowFocusListener =
        PluginRegistry.WindowFocusChangedListener { pip?.syncState() }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        binding = flutterPluginBinding
        pip = PipController(flutterPluginBinding.applicationContext)
        // Registered unconditionally: the factory builds nothing until Dart mounts a view, and a
        // view is only mounted for a player that resolved to the SurfaceView path.
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            VideoPlatformViewFactory.VIEW_TYPE,
            VideoPlatformViewFactory { playerId -> players[playerId] },
        )
        // Constructed eagerly so the channels answer, but it builds nothing until Dart asks: an
        channel =
            MethodChannel(flutterPluginBinding.binaryMessenger, Channels.MAIN).also {
                it.setMethodCallHandler(this)
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disposeAll()
        channel?.setMethodCallHandler(null)
        channel = null
        // Detached explicitly rather than dropped: the PiP controller registers a receiver on the
        // *application* context, which is a GC root — an unbalanced detach would pin it, and the
        // Activity through it. The framework happens to detach the activity first today; this
        // does not depend on that.
        pip?.detach()
        pip = null
        // Same reasoning as the PiP receiver above: these are registered on the activity binding
        // and removed only in `onDetachedFromActivity` today, which leaves this depending on the
        // framework's ordering rather than on anything here.
        activityBinding?.removeOnUserLeaveHintListener(userLeaveHintListener)
        activityBinding?.removeOnWindowFocusChangedListener(windowFocusListener)
        activityBinding = null
        this.binding = null
    }

    // region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnUserLeaveHintListener(userLeaveHintListener)
        binding.addOnWindowFocusChangedListener(windowFocusListener)
        pip?.attach(binding.activity)
        window.attach(binding.activity)
        players.values.forEach(PlayerHost::onActivityAttached)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnUserLeaveHintListener(userLeaveHintListener)
        activityBinding?.removeOnWindowFocusChangedListener(windowFocusListener)
        activityBinding = null
        pip?.detach()
        window.detach()
    }

    // A configuration change the Activity does not handle itself tears it down and rebuilds it.
    // The players survive, so the Activity-bound parts are simply rebound.
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    // endregion

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        val pluginBinding = binding
        val pipController = pip
        if (pluginBinding == null || pipController == null) {
            result.error(ErrorCodes.DETACHED, "Plugin is not attached to an engine", null)
            return
        }

        when (call.method) {
            "create" -> {
                try {
                    val playerId = nextPlayerId.getAndIncrement()
                    val host =
                        PlayerHost(
                            context = pluginBinding.applicationContext,
                            messenger = pluginBinding.binaryMessenger,
                            textureRegistry = pluginBinding.textureRegistry,
                            playerId = playerId,
                            config = call.argument<Map<String, Any?>>("config").orEmpty(),
                            pip = pipController,
                            window = window,
                        )
                    players[playerId] = host
                    result.success(
                        mapOf(
                            "playerId" to playerId,
                            // Null on the SurfaceView path, where there is no texture and Dart
                            // mounts a platform view instead.
                            "textureId" to host.textureId,
                            "renderMode" to host.renderMode,
                        ),
                    )
                } catch (e: Exception) {
                    result.error(ErrorCodes.CREATE_FAILED, e.message, null)
                }
            }

            "dispose" -> {
                val playerId = call.argument<Number>("playerId")?.toLong()
                players.remove(playerId)?.dispose()
                result.success(null)
            }

            "disposeAll" -> {
                disposeAll()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun disposeAll() {
        players.values.forEach(PlayerHost::dispose)
        players.clear()
    }
}

internal object Channels {
    const val MAIN = "dev.chikenare.fplayer"

    fun method(playerId: Long): String = "$MAIN/player/$playerId"

    fun events(playerId: Long): String = "$MAIN/player/$playerId/events"
}

internal object ErrorCodes {
    const val DETACHED = "detached"
    const val CREATE_FAILED = "create_failed"
    const val BAD_ARGUMENT = "bad_argument"
    const val DISPOSED = "disposed"
}
