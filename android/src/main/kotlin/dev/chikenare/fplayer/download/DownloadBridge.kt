package dev.chikenare.fplayer.download

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadRequest
import androidx.media3.exoplayer.offline.DownloadService
import dev.chikenare.fplayer.ErrorCodes
import dev.chikenare.fplayer.QueuingEventSink
import dev.chikenare.fplayer.SourceFactory
import dev.chikenare.fplayer.int
import dev.chikenare.fplayer.long
import dev.chikenare.fplayer.map
import dev.chikenare.fplayer.string
import dev.chikenare.fplayer.stringMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The download queue's side of the platform channels.
 *
 * Owns no state of its own — [DownloadStore] holds the queue, because the queue outlives any
 * Flutter engine. This is the part that translates, watches and publishes.
 */
@OptIn(UnstableApi::class)
internal class DownloadBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    DownloadManager.Listener {
    private val handler = Handler(Looper.getMainLooper())
    private val events = QueuingEventSink()
    private val methodChannel = MethodChannel(messenger, CHANNEL)
    private val eventChannel = EventChannel(messenger, "$CHANNEL/events")

    /**
     * Last failure per download.
     *
     * The queue records *that* a download failed but not why; only the listener sees the
     * exception, so it is kept here to enrich the entry the app reads.
     */
    private val failures = mutableMapOf<String, Throwable>()

    private var progressIntervalMs = 1000L
    private var isTicking = false
    private var isDisposed = false

    private val ticker =
        object : Runnable {
            override fun run() {
                if (isDisposed) return
                publish()
                if (hasActiveDownloads()) {
                    handler.postDelayed(this, progressIntervalMs)
                } else {
                    isTicking = false
                }
            }
        }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    sink: EventChannel.EventSink?,
                ) {
                    events.setDelegate(sink)
                    if (DownloadStore.isInitialized) publish()
                }

                override fun onCancel(arguments: Any?) = events.setDelegate(null)
            },
        )
    }

    // region Method channel

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (isDisposed) {
            result.error(ErrorCodes.DISPOSED, "The download bridge has been disposed", null)
            return
        }

        when (call.method) {
            "initialize" -> initialize(call, result)
            "list" -> result.success(snapshot())
            "inspect" -> inspect(call, result)
            "enqueue" -> enqueue(call, result)
            "setPaused" -> setPaused(call, result)
            "setAllPaused" -> setAllPaused(call, result)
            "remove" -> remove(call, result)
            "removeAll" -> removeAll(result)
            "dispose" -> {
                dispose()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * A readable cause.
     *
     * Media3's assertion helpers throw with no message at all, and a `PlatformException` whose
     * message is null tells whoever hits it nothing about where to look.
     */
    private fun describe(error: Throwable): String =
        error.message ?: error::class.java.simpleName

    private fun initialize(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val config = call.argument<Map<String, Any?>>("config").orEmpty()
        progressIntervalMs = (config.long("progressIntervalMs") ?: 1000L).coerceAtLeast(200L)

        try {
            DownloadStore.initialize(context, config)
        } catch (e: Exception) {
            result.error(ErrorCodes.CREATE_FAILED, e.message, null)
            return
        }

        val manager = requireManager() ?: run {
            result.error(ErrorCodes.CREATE_FAILED, "The download queue is unavailable", null)
            return
        }
        manager.addListener(this)

        // Without a DownloadService, nobody else starts the queue: creating that service is what
        // normally calls this. An app that declares no service still expects an enqueued download
        // to begin, instead of sitting at "queued" until something happens to resume it.
        // Per-download stop reasons are persisted separately, so an item the user paused stays
        // paused.
        if (!DownloadStore.isServiceDeclared(context)) {
            manager.resumeDownloads()
        }

        // Downloads restored from disk carry their headers in the stored payload; re-registering
        // them here is what lets a queue resumed on a cold start authenticate its next segment.
        rehydrateHeaders()

        result.success(null)
        publish()
    }

    private fun inspect(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val source = call.argument<Map<String, Any?>>("source")
        if (source == null) {
            result.error(ErrorCodes.BAD_ARGUMENT, "source is required", null)
            return
        }

        DownloadHeaders.register(source.string("uri").orEmpty(), source.stringMap("headers"))

        DownloadSelector.inspect(
            context = context,
            mediaItem = SourceFactory.mediaItem(withoutSideLoadedSubtitles(source)),
            dataSourceFactory = DownloadStore.networkDataSourceFactory(),
            onResult = result::success,
            onError = { result.error(ErrorCodes.CREATE_FAILED, describe(it), null) },
        )
    }

    private fun enqueue(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val source = call.argument<Map<String, Any?>>("source")
        val id = call.argument<String>("id")
        if (source == null || id == null) {
            result.error(ErrorCodes.BAD_ARGUMENT, "id and source are required", null)
            return
        }
        if (requireManager() == null) {
            result.error(ErrorCodes.DETACHED, "initialize() has not been called", null)
            return
        }

        val headers = source.stringMap("headers")
        DownloadHeaders.register(source.string("uri").orEmpty(), headers)
        failures.remove(id)

        DownloadSelector.buildRequest(
            context = context,
            id = id,
            mediaItem = SourceFactory.mediaItem(withoutSideLoadedSubtitles(source)),
            dataSourceFactory = DownloadStore.networkDataSourceFactory(),
            selection = call.argument<Map<String, Any?>>("selection").orEmpty(),
            payload = DownloadStore.encodePayload(call.argument<String>("metadata"), headers),
            onResult = { request ->
                send(request)
                // Answered before publishing: `publish` reaches the Flutter sink, and anything
                // it throws is routed to `onError` below — which would reply a second time and
                // crash the platform thread with "reply already submitted".
                result.success(null)
                publish()
            },
            onError = { result.error(ErrorCodes.CREATE_FAILED, describe(it), null) },
        )
    }

    private fun setPaused(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val id = call.argument<String>("id")
        if (id == null) {
            result.error(ErrorCodes.BAD_ARGUMENT, "id is required", null)
            return
        }

        // A non-zero stop reason is how Media3 models "held"; the value is ours to choose and is
        // persisted, so a paused download is still paused after a restart.
        val reason = if (call.argument<Boolean>("paused") == true) STOP_REASON_PAUSED else 0
        if (DownloadStore.isServiceDeclared(context)) {
            DownloadService.sendSetStopReason(context, SERVICE, id, reason, false)
        } else {
            requireManager()?.setStopReason(id, reason)
        }

        result.success(null)
        publish()
    }

    private fun setAllPaused(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val paused = call.argument<Boolean>("paused") == true
        if (DownloadStore.isServiceDeclared(context)) {
            if (paused) {
                DownloadService.sendPauseDownloads(context, SERVICE, false)
            } else {
                DownloadService.sendResumeDownloads(context, SERVICE, false)
            }
        } else {
            requireManager()?.let { if (paused) it.pauseDownloads() else it.resumeDownloads() }
        }

        result.success(null)
        publish()
    }

    private fun remove(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val id = call.argument<String>("id")
        if (id == null) {
            result.error(ErrorCodes.BAD_ARGUMENT, "id is required", null)
            return
        }

        failures.remove(id)
        DownloadHeaders.forget(id)
        if (DownloadStore.isServiceDeclared(context)) {
            DownloadService.sendRemoveDownload(context, SERVICE, id, false)
        } else {
            requireManager()?.removeDownload(id)
        }

        result.success(null)
        publish()
    }

    private fun removeAll(result: MethodChannel.Result) {
        failures.clear()
        if (DownloadStore.isServiceDeclared(context)) {
            DownloadService.sendRemoveAllDownloads(context, SERVICE, false)
        } else {
            requireManager()?.removeAllDownloads()
        }

        result.success(null)
        publish()
    }

    /**
     * Hands a request to the service when the app declared one, and to the queue directly when it
     * did not.
     *
     * The difference the user sees is whether a download survives leaving the app.
     */
    private fun send(request: DownloadRequest) {
        if (DownloadStore.isServiceDeclared(context)) {
            DownloadService.sendAddDownload(context, SERVICE, request, false)
        } else {
            requireManager()?.addDownload(request)
        }
    }

    // endregion

    // region DownloadManager.Listener

    override fun onInitialized(downloadManager: DownloadManager) = publish()

    override fun onDownloadChanged(
        downloadManager: DownloadManager,
        download: Download,
        finalException: Exception?,
    ) {
        if (finalException != null) {
            failures[download.request.id] = finalException
        } else if (download.state != Download.STATE_FAILED) {
            failures.remove(download.request.id)
        }
        publish()
    }

    override fun onDownloadRemoved(
        downloadManager: DownloadManager,
        download: Download,
    ) {
        failures.remove(download.request.id)
        publish()
    }

    override fun onDownloadsPausedChanged(
        downloadManager: DownloadManager,
        downloadsPaused: Boolean,
    ) = publish()

    override fun onIdle(downloadManager: DownloadManager) = publish()

    // endregion

    /**
     * Publishes the queue and keeps a ticker running while anything is transferring.
     *
     * The platform announces state changes but not bytes, so a progress bar needs polling — and
     * only while there is progress to poll.
     */
    private fun publish() {
        if (isDisposed) return
        events.success(snapshot())

        if (!isTicking && hasActiveDownloads()) {
            isTicking = true
            handler.postDelayed(ticker, progressIntervalMs)
        }
    }

    /**
     * The whole queue, with live figures for whatever is running.
     *
     * The index is the record of what exists; the active list is the only place with byte counts
     * fresher than the last state change, so it is laid over the top.
     */
    private fun snapshot(): List<Map<String, Any?>> {
        val manager = DownloadStore.downloadManager ?: return emptyList()

        val live = manager.currentDownloads.associateBy { it.request.id }
        val all = mutableListOf<Map<String, Any?>>()

        runCatching {
            manager.downloadIndex.getDownloads().use { cursor ->
                while (cursor.moveToNext()) {
                    val stored = cursor.download
                    val download = live[stored.request.id] ?: stored
                    all += DownloadMapper.toMap(download, failures[download.request.id])
                }
            }
        }

        return all
    }

    private fun hasActiveDownloads(): Boolean =
        DownloadStore.downloadManager?.currentDownloads?.isNotEmpty() == true

    private fun rehydrateHeaders() {
        val manager = DownloadStore.downloadManager ?: return
        runCatching {
            manager.downloadIndex.getDownloads().use { cursor ->
                while (cursor.moveToNext()) {
                    val request = cursor.download.request
                    DownloadHeaders.register(
                        request.uri.toString(),
                        DownloadStore.headersOf(request.data),
                    )
                }
            }
        }
    }

    /**
     * Strips subtitle files that were attached for playback.
     *
     * They are separate resources, not part of the media's own periods, so the download helper
     * would pull them into a merging source and confuse the track selection. Downloading them
     * alongside the media is a feature in its own right; see the report.
     */
    private fun withoutSideLoadedSubtitles(source: Map<String, Any?>): Map<String, Any?> =
        source - "subtitles"

    private fun requireManager(): DownloadManager? = DownloadStore.downloadManager

    fun dispose() {
        if (isDisposed) return
        isDisposed = true

        handler.removeCallbacks(ticker)
        DownloadStore.downloadManager?.removeListener(this)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        events.endOfStream()
    }

    private companion object {
        const val CHANNEL = "dev.chikenare.fplayer/downloads"
        const val STOP_REASON_PAUSED = 1
        val SERVICE = FplayerDownloadService::class.java
    }
}
