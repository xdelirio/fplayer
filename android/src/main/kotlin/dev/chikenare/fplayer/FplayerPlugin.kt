package dev.chikenare.fplayer

import dev.chikenare.fplayer.download.DownloadBridge
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
 * Downloads are attached the same way but own nothing here: the queue outlives the engine, so
 * [DownloadBridge] is only the translator between it and Dart.
 */
class FplayerPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler {
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var channel: MethodChannel? = null
    private var pip: PipController? = null
    private val window = WindowController()
    private var downloads: DownloadBridge? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val players = mutableMapOf<Long, PlayerHost>()
    private var nextPlayerId = 1L

    private val userLeaveHintListener =
        PluginRegistry.UserLeaveHintListener { players.values.forEach(PlayerHost::onUserLeaveHint) }

    // Losing window focus is the earliest reliable hint that the app slipped into the PiP window;
    // the configuration change that follows confirms it.
    private val windowFocusListener =
        PluginRegistry.WindowFocusChangedListener { pip?.syncState() }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        binding = flutterPluginBinding
        pip = PipController(flutterPluginBinding.applicationContext)
        // Constructed eagerly so the channels answer, but it builds nothing until Dart asks: an
        // app that never downloads pays no cache, database or threads for the feature.
        downloads =
            DownloadBridge(
                flutterPluginBinding.applicationContext,
                flutterPluginBinding.binaryMessenger,
            )
        channel =
            MethodChannel(flutterPluginBinding.binaryMessenger, Channels.MAIN).also {
                it.setMethodCallHandler(this)
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disposeAll()
        downloads?.dispose()
        downloads = null
        channel?.setMethodCallHandler(null)
        channel = null
        // Detached explicitly rather than dropped: the PiP controller registers a receiver on the
        // *application* context, which is a GC root — an unbalanced detach would pin it, and the
        // Activity through it. The framework happens to detach the activity first today; this
        // does not depend on that.
        pip?.detach()
        pip = null
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
                    val playerId = nextPlayerId++
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
                            "textureId" to host.textureId,
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
