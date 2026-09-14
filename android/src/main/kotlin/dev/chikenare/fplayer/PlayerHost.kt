package dev.chikenare.fplayer

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Rational
import android.view.Surface
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.MediaLoadData
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Whether this is a television, which is what `renderMode: auto` keys off.
 *
 * Two checks because they answer slightly different questions: `UI_MODE_TYPE_TELEVISION` is the
 * device's current mode, while `FEATURE_LEANBACK` is what the TV Play Store filters on. Devices
 * exist that report only one of them.
 */
private const val LOG_TAG = "fplayer"

/** Whether [name] is one of the platform's software codecs rather than the SoC's own. */
private fun isSoftwareDecoder(name: String): Boolean =
    name.startsWith("c2.android.") || name.startsWith("OMX.google.") || name.startsWith("c2.ffmpeg.")

private fun isTelevision(context: Context): Boolean {
    val uiMode = context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
    if (uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
    return context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
}

/**
 * One playback instance: an [ExoPlayer], the texture it renders into, and the pair of channels
 * that connect it to a single Dart `FPlayerController`.
 *
 * Everything here runs on the main thread — ExoPlayer requires it, and so do the Flutter channels.
 */
@OptIn(UnstableApi::class)
internal class PlayerHost(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textureRegistry: TextureRegistry,
    private val playerId: Long,
    private val config: Map<String, Any?>,
    private val pip: PipController,
    private val window: WindowController,
) : Player.Listener,
    TextureRegistry.SurfaceProducer.Callback,
    MethodChannel.MethodCallHandler,
    PipController.Owner {
    private val handler = Handler(Looper.getMainLooper())
    private val events = QueuingEventSink()

    // Created in `build`, so the try/catch that releases a half-built host covers it. As a
    // property initializer it ran before `init`, and a throw from anything after it left this
    // texture registered with the engine for the life of the process. Never created at all on
    // the SurfaceView path, where there is no texture to render into.
    private lateinit var surfaceProducer: TextureRegistry.SurfaceProducer

    /**
     * Whether frames go to a `SurfaceView` handed over by a platform view rather than to a
     * Flutter texture.
     *
     * `auto` resolves to the SurfaceView on televisions and to the texture everywhere else. Both
     * halves of that are deliberate: TV decoders are the ones that write buffers the texture
     * import cannot read — see `VideoPlatformView` — while on a phone the platform view forces
     * hybrid composition, which makes every Flutter frame above the video cost a copy.
     */
    private val usesSurfaceView: Boolean =
        when (config.string("renderMode")) {
            "surfaceView" -> true
            "texture" -> false
            else -> isTelevision(context)
        }

    /** What `usesSurfaceView` resolved to, so Dart knows which widget to build. */
    val renderMode: String get() = if (usesSurfaceView) "surfaceView" else "texture"

    /** The SurfaceView's surface while one is attached, so a stale view cannot unhook a live one. */
    private var externalSurface: Surface? = null
    private val methodChannel = MethodChannel(messenger, Channels.method(playerId))
    private val eventChannel = EventChannel(messenger, Channels.events(playerId))

    // `lateinit`, because construction is wrapped in a try/catch that has to be able to release
    // whatever was built before a failure — see `init`.
    private lateinit var player: ExoPlayer
    private lateinit var trackSelector: DefaultTrackSelector
    private lateinit var tracks: TrackController
    private var progressIntervalMs: Long = 250L
    private var needsSurface = true
    private var isDisposed = false
    private var hasReportedInitialized = false
    private var surfaceWidth = 0
    private var surfaceHeight = 0

    /** Last source handed to the engine, kept so subtitles can be added without losing it. */
    private var currentSource: Map<String, Any?>? = null

    /** Whether this player keeps the CPU awake, which only background playback needs. */
    private var holdsWakeLock = false

    /** Title, subtitle and artwork for the lock screen and the notification. */
    private var currentMetadata: Map<String, Any?> = emptyMap()

    /** Guards against re-sending the track list when nothing about the active tracks moved. */
    private var lastActiveSignature = ""

    private val networkConfig = config.map("network")

    /**
     * Whether a lost network parks playback instead of failing it.
     *
     * Off is a legitimate choice: an app that already runs its own connectivity handling would
     * otherwise have two layers deciding when to re-prepare, and they would fight.
     */
    private val waitForNetwork = networkConfig.bool("waitForNetwork") ?: true

    private val networkWatcher = NetworkWatcher(context) { onNetworkRestored() }

    private val loadErrorPolicy =
        FplayerLoadErrorPolicy.from(networkConfig) { !waitForNetwork || networkWatcher.isOnline() }

    /** Set while a network-class failure is being held rather than surfaced. */
    private var isWaitingForNetwork = false

    /** Where to resume from once the network is back. */
    private var parkedPositionMs = 0L

    private var lastConnectivityReport: Pair<Boolean, Boolean>? = null

    private val pipActions: List<String> =
        config.map("pip").stringList("actions")
            ?: listOf(
                PipController.ACTION_SKIP_BACKWARD,
                PipController.ACTION_PLAY_PAUSE,
                PipController.ACTION_SKIP_FORWARD,
            )
    private val keepScreenOn = config.map("playback").bool("keepScreenOn") ?: true
    private val isPipEnabled = config.map("pip").bool("enabled") ?: true
    private val autoEnterPip = config.map("pip").bool("autoEnterOnLeave") ?: false
    private var mediaSession: MediaSessionAttachment? = null
    private var lastPipReport: Pair<Boolean, Boolean>? = null

    /**
     * How far the PiP skip buttons jump.
     *
     * Falls back to ten seconds because `FPlaybackConfig.seekStep` is not serialised yet; once it
     * is, the configured value flows through with no change here.
     */
    private val seekStepMs: Long = config.map("playback").long("seekStepMs") ?: 10_000L

    /** Texture handed back to Dart so it can build a `Texture(textureId: ...)` widget. */
    val textureId: Long? get() = if (usesSurfaceView) null else surfaceProducer.id()

    private val progressTicker =
        object : Runnable {
            override fun run() {
                if (isDisposed) return
                emitProgress()
                handler.postDelayed(this, progressIntervalMs)
            }
        }

    init {
        // Everything below allocates something that has to be released: a texture, an ExoPlayer,
        // a process-wide MediaSession registration that also starts a service. A throw halfway
        // through — a bad buffering config is enough — used to leave every one of them running
        // with nobody holding a reference, for the life of the process.
        try {
            build(config)
        } catch (error: Throwable) {
            dispose()
            throw error
        }
    }

    private fun build(config: Map<String, Any?>) {
        if (!usesSurfaceView) surfaceProducer = textureRegistry.createSurfaceProducer()

        val playback = config.map("playback")
        progressIntervalMs = (playback.long("progressIntervalMs") ?: 250L).coerceAtLeast(50L)

        trackSelector = PlayerBuilders.trackSelector(context, config)
        tracks = TrackController(trackSelector)
        tracks.applyPreferences(
            audioLanguages = playback.stringList("preferredAudioLanguages"),
            textLanguages = playback.stringList("preferredTextLanguages"),
            autoSelectText = playback.bool("autoSelectSubtitles") ?: false,
        )

        player =
            ExoPlayer
                .Builder(context, PlayerBuilders.renderersFactory(context, config.map("decoding")))
                .setLoadControl(PlayerBuilders.loadControl(config.map("buffering")))
                .setTrackSelector(trackSelector)
                .build()

        player.setAudioAttributes(
            AudioAttributes
                .Builder()
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .setUsage(C.USAGE_MEDIA)
                .build(),
            /* handleAudioFocus = */ playback.bool("handleAudioFocus") ?: true,
        )
        player.setHandleAudioBecomingNoisy(playback.bool("pauseOnBecomingNoisy") ?: true)
        player.repeatMode =
            if (playback.bool("loop") == true) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
        playback.float("volume")?.let { player.volume = it.coerceIn(0f, 1f) }
        playback.float("speed")?.let { player.setPlaybackParameters(PlaybackParameters(it)) }

        player.addListener(this)

        // Adaptive bitrate switches keep the same track list, so `onTracksChanged` stays silent.
        // This is what lets the UI show which quality is really playing in auto mode.
        player.addAnalyticsListener(
            object : AnalyticsListener {
                override fun onDownstreamFormatChanged(
                    eventTime: AnalyticsListener.EventTime,
                    mediaLoadData: MediaLoadData,
                ) {
                    emitTracksIfActiveChanged()
                }

                // What a stutter on a television is, told apart in logcat. A box has one or two
                // hardware decoder instances; when another player still holds them, decoder
                // fallback quietly hands this one a software decoder, and a 4K or AV1 stream
                // plays at a few frames a second — sometimes, depending on who got there first.
                override fun onVideoDecoderInitialized(
                    eventTime: AnalyticsListener.EventTime,
                    decoderName: String,
                    initializedTimestampMs: Long,
                    initializationDurationMs: Long,
                ) {
                    if (isSoftwareDecoder(decoderName)) {
                        Log.w(LOG_TAG, "player $playerId: software video decoder $decoderName")
                    } else {
                        Log.i(LOG_TAG, "player $playerId: video decoder $decoderName")
                    }
                }

                // Reported in batches by Media3, at most once per fifty frames: cheap to log.
                override fun onDroppedVideoFrames(
                    eventTime: AnalyticsListener.EventTime,
                    droppedFrames: Int,
                    elapsedMs: Long,
                ) {
                    Log.w(LOG_TAG, "player $playerId: dropped $droppedFrames frames in ${elapsedMs}ms")
                }
            },
        )

        if (!usesSurfaceView) surfaceProducer.setCallback(this)
        attachSurface()

        val background = config.map("background")
        mediaSession =
            MediaSessionAttachment.attach(
                context = context,
                playerId = playerId,
                player = player,
                background = background,
            )

        // Playing on with the screen off is the whole point of a media session, and nothing was
        // keeping the CPU awake to serve it: between buffer fills the device suspends and audio
        // stutters or stops. Media3 acquires and releases the lock itself, tied to `isPlaying`,
        // so there is no release path here to get wrong. Only armed when background playback was
        // actually asked for — a foreground-only player has the screen keeping it awake.
        // Applied per source in `setSource`, where it is known whether the bytes come over the
        // network. Media3 acquires and releases the lock itself, tied to `isPlaying`.
        holdsWakeLock = background.bool("mediaSession") == true

        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    sink: EventChannel.EventSink?,
                ) = events.setDelegate(sink)

                override fun onCancel(arguments: Any?) = events.setDelegate(null)
            },
        )

        if (waitForNetwork) networkWatcher.start()

        emitMediaSessionState()
        emitPipState()
        emitConnectivity()

        // Arming auto-enter up front matters on Android 12+: the system needs the parameters
        // before the user leaves, not after.
        if (isPipEnabled && autoEnterPip) {
            pip.setAutoEnter(this, enabled = true, actions = pipActions)
        }
    }

    // region Method channel

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (isDisposed) {
            result.error(ErrorCodes.DISPOSED, "Player $playerId has been disposed", null)
            return
        }

        when (call.method) {
            "setSource" -> {
                val source = call.argument<Map<String, Any?>>("source")
                if (source == null) {
                    result.error(ErrorCodes.BAD_ARGUMENT, "source is required", null)
                    return
                }
                currentMetadata = call.argument<Map<String, Any?>>("metadata").orEmpty()
                setSource(source)
                result.success(null)
            }

            "play" -> {
                player.play()
                result.success(null)
            }

            "pause" -> {
                player.pause()
                result.success(null)
            }

            "stop" -> {
                player.stop()
                player.clearMediaItems()
                // Forgotten with the media: a later `addSubtitle` rebuilds from this, and would
                // otherwise re-prepare the source the app just stopped.
                currentSource = null
                hasReportedInitialized = false
                result.success(null)
            }

            "seekTo" -> {
                val positionMs = call.argument<Number>("positionMs")?.toLong()
                if (positionMs == null) {
                    result.error(ErrorCodes.BAD_ARGUMENT, "positionMs is required", null)
                    return
                }
                player.seekTo(positionMs)
                result.success(null)
            }

            "seekToDefaultPosition" -> {
                player.seekToDefaultPosition()
                result.success(null)
            }

            "setSpeed" -> {
                val speed = call.argument<Number>("speed")?.toFloat() ?: 1f
                player.setPlaybackParameters(PlaybackParameters(speed.coerceAtLeast(0.05f)))
                result.success(null)
            }

            "setVolume" -> {
                val volume = call.argument<Number>("volume")?.toFloat() ?: 1f
                player.volume = volume.coerceIn(0f, 1f)
                emit("volumeChanged", "volume" to player.volume.toDouble())
                result.success(null)
            }

            "setLooping" -> {
                val looping = call.argument<Boolean>("looping") ?: false
                player.repeatMode =
                    if (looping) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
                result.success(null)
            }

            "retry" -> {
                // A retry from a parked player is the same move as the network coming back: the
                // fatal error left the player idle, so a bare `prepare()` restarts the media
                // from zero and leaves the "waiting for signal" flag set forever.
                if (isWaitingForNetwork) {
                    isWaitingForNetwork = false
                    player.seekTo(parkedPositionMs)
                    player.prepare()
                    emitConnectivity()
                } else {
                    player.prepare()
                }
                result.success(null)
            }

            "selectTrack" -> {
                val trackType = TrackController.trackTypeOf(call.argument<String>("type"))
                val id = call.argument<String>("id")
                if (!tracks.select(trackType, id)) {
                    result.error(ErrorCodes.BAD_ARGUMENT, "No such track: $id", null)
                    return
                }
                emitTracks()
                result.success(null)
            }

            "setPreferredLanguages" -> {
                tracks.applyPreferences(
                    audioLanguages = call.argument<List<String>>("audio"),
                    textLanguages = call.argument<List<String>>("text"),
                    autoSelectText = null,
                )
                emitTracks()
                result.success(null)
            }

            "addSubtitle" -> {
                val subtitle = call.argument<Map<String, Any?>>("subtitle")
                val source = currentSource
                if (subtitle == null || source == null) {
                    result.error(
                        ErrorCodes.BAD_ARGUMENT,
                        "addSubtitle needs a subtitle and a loaded source",
                        null,
                    )
                    return
                }
                addSubtitle(source, subtitle)
                result.success(null)
            }

            "enterPip" -> {
                if (!isPipEnabled) {
                    result.success(false)
                    return
                }
                val entered = pip.enter(this, pipActions)
                emitPipState()
                result.success(entered)
            }

            "exitPip" -> {
                pip.exit()
                result.success(null)
            }

            "setBrightness" -> {
                window.setBrightness(call.argument<Number>("brightness")?.toDouble())
                result.success(null)
            }

            "getBrightness" -> result.success(window.brightness())

            "getSnapshot" -> result.success(snapshot())

            else -> result.notImplemented()
        }
    }

    private fun setSource(
        source: Map<String, Any?>,
        startAtMs: Long = SourceFactory.startPositionMs(source),
        play: Boolean = config.map("playback").bool("autoPlay") == true,
    ) {
        hasReportedInitialized = false
        stopTicker()
        currentSource = source

        // Set per source, not once at build time: a wifi lock on top of the partial one is worth
        // holding for a stream and pointless for a local file, and one player sees both.
        if (holdsWakeLock) {
            val mode =
                if (source.string("kind") == "network") C.WAKE_MODE_NETWORK else C.WAKE_MODE_LOCAL
            runCatching { player.setWakeMode(mode) }
        }

        isWaitingForNetwork = false

        player.setMediaSource(
            SourceFactory.mediaSource(
                context = context,
                source = source,
                network = networkConfig,
                metadata = currentMetadata,
                loadErrorPolicy = loadErrorPolicy,
            ),
            startAtMs,
        )
        player.prepare()

        if (play) player.play()
    }

    /**
     * Appends a subtitle file to the media that is already loaded.
     *
     * The subtitle set is part of the [MediaItem], so the source has to be rebuilt. Position and
     * play/pause state are carried over, which turns a hard reload into a short rebuffer.
     */
    private fun addSubtitle(
        source: Map<String, Any?>,
        subtitle: Map<String, Any?>,
    ) {
        @Suppress("UNCHECKED_CAST")
        val existing = (source["subtitles"] as? List<Map<String, Any?>>).orEmpty()
        val updated = source + ("subtitles" to existing + subtitle)

        setSource(updated, startAtMs = player.currentPosition, play = player.playWhenReady)
    }

    /** Point-in-time state, used by Dart to resync after an app resume. */
    private fun snapshot(): Map<String, Any?> =
        mapOf(
            "positionMs" to player.currentPosition,
            "bufferedMs" to player.bufferedPosition,
            "bufferedAheadMs" to player.totalBufferedDuration,
            "durationMs" to durationOrNull(),
            "isPlaying" to player.isPlaying,
            "speed" to player.playbackParameters.speed.toDouble(),
            "volume" to player.volume.toDouble(),
        )

    // endregion

    // region Player.Listener

    override fun onPlaybackStateChanged(playbackState: Int) {
        // A fatal error drops the player to IDLE and then reports the error. Emitting the idle
        // state too would make Dart flash "no media loaded" for a frame before the error lands.
        if (playbackState == Player.STATE_IDLE && player.playerError != null) return

        val name =
            when (playbackState) {
                Player.STATE_IDLE -> "idle"
                Player.STATE_BUFFERING -> "buffering"
                Player.STATE_READY -> "ready"
                Player.STATE_ENDED -> "ended"
                else -> "idle"
            }
        emit("playbackState", "state" to name)

        if (playbackState == Player.STATE_READY) {
            maybeEmitInitialized()
        }
        if (playbackState == Player.STATE_ENDED) {
            stopTicker()
            emitProgress()
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        // Tied to actual playback rather than to "a source is loaded": a player left paused
        // overnight should not hold the screen on.
        window.setKeepScreenOn(playerId, isPlaying && keepScreenOn)

        emit("isPlayingChanged", "isPlaying" to isPlaying)
        if (isPlaying) startTicker() else stopTicker()
        emitProgress()
        // Flips the window's play button to a pause button while PiP is open.
        pip.refreshActions(this, pipActions)
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        resizeSurface(videoSize.width, videoSize.height)
        // The first frame is what makes PiP viable: the window needs a shape.
        emitPipState()
        val (width, height) = displaySize(videoSize)
        emit(
            "videoSize",
            "width" to width,
            "height" to height,
            "rotationDegrees" to rotationCorrection(),
            "pixelAspectRatio" to videoSize.pixelWidthHeightRatio.toDouble(),
        )
        maybeEmitInitialized()
    }

    override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
        emit("speedChanged", "speed" to playbackParameters.speed.toDouble())
    }

    override fun onPositionDiscontinuity(
        oldPosition: Player.PositionInfo,
        newPosition: Player.PositionInfo,
        reason: Int,
    ) {
        // Report the new position right away instead of waiting for the next tick, so the seek bar
        // does not snap back for a frame after a seek.
        emitProgress()
    }

    override fun onTracksChanged(tracks: Tracks) {
        emitTracks()
    }

    override fun onCues(cueGroup: CueGroup) {
        events.success(CueBridge.toMap(cueGroup))
    }

    override fun onTimelineChanged(
        timeline: Timeline,
        reason: Int,
    ) {
        if (hasReportedInitialized) {
            emit(
                "durationChanged",
                "durationMs" to durationOrNull(),
                "isSeekable" to player.isCurrentMediaItemSeekable,
            )
        } else {
            maybeEmitInitialized()
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
            // Standard live recovery: the playback position fell out of the sliding window
            // (usually after a long pause). Jump back to the live edge instead of surfacing an
            // error the user can do nothing about.
            // https://developer.android.com/media/media3/exoplayer/live-streaming
            player.seekToDefaultPosition()
            player.prepare()
            return
        }

        val described = ErrorMapper.toMap(error)

        if (shouldWaitForNetwork(described["code"] as? String)) {
            // Swallowing the error is the point: reporting it would start the source-level retry
            // ladder, which cannot succeed and only spends its budget before showing an error the
            // viewer can do nothing about. Dart stays on its spinner — the idle state that follows
            // a fatal error is already suppressed above — and the connectivity event tells the UI
            // to say "no connection" rather than "unknown error".
            parkedPositionMs = player.currentPosition
            isWaitingForNetwork = true
            stopTicker()
            emitConnectivity()
            return
        }

        stopTicker()
        events.success(described + mapOf("event" to "error"))
    }

    /** A failure worth waiting out: caused by the transport, and the transport is gone. */
    private fun shouldWaitForNetwork(code: String?): Boolean =
        waitForNetwork &&
            // Only worth parking on if something can wake us: a watcher that failed to register
            // will never report the network coming back, and the spinner would never end.
            networkWatcher.isWatching &&
            (code == "network" || code == "timeout" || code == "io") &&
            !networkWatcher.isOnline()

    private fun onNetworkRestored() {
        if (isDisposed) return

        if (isWaitingForNetwork) {
            isWaitingForNetwork = false
            // Seek before preparing: a fatal error leaves the player idle, and preparing without
            // restoring the position would restart the media from the beginning.
            player.seekTo(parkedPositionMs)
            player.prepare()
        }
        emitConnectivity()
    }

    private fun emitConnectivity() {
        if (isDisposed) return

        val online = !waitForNetwork || networkWatcher.isOnline()
        val report = online to isWaitingForNetwork
        if (report == lastConnectivityReport) return

        lastConnectivityReport = report
        emit("connectivity", "isOnline" to online, "isWaitingForNetwork" to isWaitingForNetwork)
    }

    // endregion

    // region Picture-in-Picture

    /**
     * Aspect ratio for the PiP window, or null before a frame is decoded.
     *
     * Android rejects anything outside 1:2.39 … 2.39:1 with an exception, so extreme shapes are
     * clamped rather than allowed to crash a perfectly good playback session.
     */
    override val pipAspectRatio: Rational?
        get() {
            val size = player.videoSize
            if (size.width <= 0 || size.height <= 0) return null

            val ratio = size.width.toDouble() / size.height.toDouble()
            val clamped = ratio.coerceIn(MIN_PIP_RATIO, MAX_PIP_RATIO)
            // Scaling to a fixed denominator keeps Rational away from huge reduced fractions.
            return Rational((clamped * RATIO_PRECISION).toInt(), RATIO_PRECISION)
        }

    override val pipIsPlaying: Boolean get() = player.isPlaying

    override fun onPipAction(action: String) {
        when (action) {
            PipController.ACTION_PLAY_PAUSE ->
                if (player.isPlaying) player.pause() else player.play()

            PipController.ACTION_SKIP_FORWARD -> player.seekTo(player.currentPosition + seekStepMs)
            PipController.ACTION_SKIP_BACKWARD -> player.seekTo(player.currentPosition - seekStepMs)
        }
        pip.refreshActions(this, pipActions)
    }

    override fun onPipStateChanged(
        isActive: Boolean,
        isSupported: Boolean,
    ) = emitPipState()

    /** Fallback auto-enter path for Android 11 and below. */
    fun onUserLeaveHint() {
        if (isPipEnabled && autoEnterPip) pip.onUserLeaveHint(this, pipActions)
    }

    /** Re-arms Activity-bound state after the Activity was recreated. */
    fun onActivityAttached() {
        if (isPipEnabled && autoEnterPip) {
            pip.setAutoEnter(this, enabled = true, actions = pipActions)
        }
        emitPipState()
    }

    private fun emitPipState() {
        if (isDisposed) return

        val supported = isPipEnabled && pip.isSupported() && pipAspectRatio != null
        val active = pip.isActive()
        val report = supported to active
        if (report == lastPipReport) return

        lastPipReport = report
        emit("pip", "isSupported" to supported, "isActive" to active)
    }

    private fun emitMediaSessionState() {
        if (isDisposed) return
        emit("mediaSession", "isActive" to (mediaSession != null))
    }

    // endregion

    // region Surface lifecycle

    override fun onSurfaceAvailable() {
        // "Available" can mean "a different surface exists now" — Flutter swaps the backing
        // ImageReader on some resizes without a cleanup first — so re-attach unconditionally
        // instead of trusting the needsSurface flag.
        needsSurface = true
        attachSurface()
    }

    override fun onSurfaceCleanup() {
        player.setVideoSurface(null)
        needsSurface = true
    }

    /**
     * Take the `SurfaceView`'s surface as the output. Called by the platform view, not by Dart.
     *
     * There is no `needsSurface` bookkeeping here because there is nothing to rebuild: the view
     * owns the surface and tells us when it appears and when it goes.
     */
    fun attachExternalSurface(surface: Surface) {
        if (isDisposed || !usesSurfaceView) return
        if (externalSurface === surface) return
        externalSurface = surface
        player.setVideoSurface(surface)
    }

    /**
     * Drop [surface] if it is still the one in use.
     *
     * Matching on identity rather than clearing unconditionally: Flutter can build the
     * replacement view before tearing the old one down, and an unconditional clear from the
     * outgoing view would then blank the incoming one.
     */
    fun detachExternalSurface(surface: Surface) {
        if (isDisposed || externalSurface !== surface) return
        externalSurface = null
        player.setVideoSurface(null)
    }

    private fun attachSurface() {
        // Guarded here rather than at each call site: `build` calls this before anything is
        // playing, and on the SurfaceView path there is no producer to read a surface from — the
        // platform view owns the surface and hands it over through `attachExternalSurface`.
        // Reaching the line below with an uninitialised `surfaceProducer` throws, and the throw
        // lands in `init`, which releases the player it just built.
        if (usesSurfaceView || !needsSurface) return
        val surface = surfaceProducer.surface
        player.setVideoSurface(surface)
        needsSurface = surface == null
    }

    /**
     * Match the texture's buffer to the decoded frame size.
     *
     * On the ImageReader-backed path (Impeller/Vulkan) the producer keeps whatever size it was
     * created with, so frames smaller than that land in the top-left corner and the rest of the
     * picture is cropped away. Resizing may hand back a different Surface, hence the re-attach.
     */
    private fun resizeSurface(
        width: Int,
        height: Int,
    ) {
        // The SurfaceView sizes itself from its layout, and ExoPlayer scales the frame into it.
        if (usesSurfaceView) return
        if (width <= 0 || height <= 0) return
        if (width == surfaceWidth && height == surfaceHeight) return

        surfaceWidth = width
        surfaceHeight = height
        surfaceProducer.setSize(width, height)
        needsSurface = true
        attachSurface()
    }

    // endregion

    // region Events

    private fun maybeEmitInitialized() {
        if (hasReportedInitialized) return
        // Wait until the duration is known, except for live streams where it never will be.
        val isLive = player.isCurrentMediaItemLive
        if (player.duration == C.TIME_UNSET && !isLive) return

        hasReportedInitialized = true
        val (width, height) = displaySize(player.videoSize)
        val videoSize = player.videoSize
        emit(
            "initialized",
            "durationMs" to durationOrNull(),
            "width" to width,
            "height" to height,
            "rotationDegrees" to rotationCorrection(),
            "pixelAspectRatio" to videoSize.pixelWidthHeightRatio.toDouble(),
            "isLive" to isLive,
            "isSeekable" to player.isCurrentMediaItemSeekable,
        )
        emitProgress()
    }

    private fun emitTracks() {
        if (isDisposed) return
        lastActiveSignature = tracks.activeSignature(player)
        events.success(tracks.snapshot(player))
    }

    private fun emitTracksIfActiveChanged() {
        if (isDisposed) return
        if (tracks.activeSignature(player) == lastActiveSignature) return
        emitTracks()
    }

    private fun emitProgress() {
        if (isDisposed) return
        emit(
            "progress",
            "positionMs" to player.currentPosition,
            "bufferedMs" to player.bufferedPosition,
            // What is buffered *ahead of the playhead*, which is the number that decides whether
            // playback is about to stall. `bufferedMs` is absolute and says nothing about that
            // after a seek.
            "bufferedAheadMs" to player.totalBufferedDuration,
        )
    }

    private fun emit(
        event: String,
        vararg entries: Pair<String, Any?>,
    ) {
        events.success(mapOf("event" to event) + entries.toMap())
    }

    private fun durationOrNull(): Long? =
        player.duration.takeIf { it != C.TIME_UNSET && it >= 0 }

    /**
     * Rotation Flutter must apply itself.
     *
     * When the texture backend already crops and rotates (SurfaceTexture path), the frames arrive
     * upright and applying the format rotation again would double-rotate them. Same on the
     * SurfaceView path, for a different reason: Media3 puts the format's rotation on the codec as
     * `MediaFormat.KEY_ROTATION`, and SurfaceFlinger honours that hint before the frame is shown.
     * Only the `ImageReader` path ignores it, which is what leaves the work to Flutter.
     */
    private fun rotationCorrection(): Int =
        when {
            usesSurfaceView -> 0
            surfaceProducer.handlesCropAndRotation() -> 0
            else -> player.videoFormat?.rotationDegrees ?: 0
        }

    /**
     * Frame size in the orientation Dart has to lay out.
     *
     * [rotationCorrection] reports zero for a quarter-turned video on the SurfaceView path, so
     * the dimensions have to arrive already swapped: left as they are, a portrait video would be
     * given a landscape box to sit in.
     */
    private fun displaySize(videoSize: VideoSize): Pair<Int, Int> {
        val rotation = player.videoFormat?.rotationDegrees ?: 0
        val isQuarterTurned = usesSurfaceView && (rotation == 90 || rotation == 270)
        return if (isQuarterTurned) {
            videoSize.height to videoSize.width
        } else {
            videoSize.width to videoSize.height
        }
    }

    private fun startTicker() {
        handler.removeCallbacks(progressTicker)
        handler.postDelayed(progressTicker, progressIntervalMs)
    }

    private fun stopTicker() {
        handler.removeCallbacks(progressTicker)
    }

    // endregion

    fun dispose() {
        if (isDisposed) return
        isDisposed = true

        // Every step is guarded: this also runs as the unwind path for a construction that threw
        // partway, where some of what follows was never built.
        runCatching { stopTicker() }
        runCatching { networkWatcher.stop() }
        runCatching { window.release(playerId) }
        runCatching { methodChannel.setMethodCallHandler(null) }
        runCatching { eventChannel.setStreamHandler(null) }
        runCatching { events.endOfStream() }

        runCatching { pip.releaseOwner(this) }
        // Before the player is released: the session holds a reference to it.
        runCatching { mediaSession?.release() }
        mediaSession = null

        if (this::player.isInitialized) {
            runCatching { player.removeListener(this) }
            runCatching { player.release() }
        }

        if (this::surfaceProducer.isInitialized) {
            runCatching { surfaceProducer.setCallback(null) }
            runCatching { surfaceProducer.release() }
        }
    }

    private companion object {
        /** Android refuses PiP aspect ratios outside this range. */
        const val MIN_PIP_RATIO = 1.0 / 2.39
        const val MAX_PIP_RATIO = 2.39

        const val RATIO_PRECISION = 1000
    }
}
