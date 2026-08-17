package dev.chikenare.fplayer.download

import android.content.ComponentName
import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.DatabaseProvider
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadRequest
import androidx.media3.exoplayer.scheduler.Requirements
import dev.chikenare.fplayer.bool
import dev.chikenare.fplayer.int
import dev.chikenare.fplayer.map
import dev.chikenare.fplayer.string
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/**
 * Process-wide home of the download cache and queue.
 *
 * Singleton by necessity rather than by taste: there can only be one writer to a Media3 cache
 * directory, the download index is a single database, and the system may spin up
 * [FplayerDownloadService] at any moment — after a reboot, say — with no Dart engine running to
 * hand it collaborators.
 *
 * Nothing here is built until [initialize] is called, so an app that never downloads pays no
 * disk, no database and no threads for the feature.
 */
@OptIn(UnstableApi::class)
internal object DownloadStore {
    private const val PREFERENCES = "dev.chikenare.fplayer.downloads"
    private const val KEY_CONFIG = "config"

    /** Reserved keys inside a download's payload. The app's own metadata is nested under one. */
    private const val PAYLOAD_METADATA = "metadata"
    private const val PAYLOAD_HEADERS = "headers"

    private var cache: Cache? = null
    private var databaseProvider: DatabaseProvider? = null
    private var manager: DownloadManager? = null
    private var configuration: Map<String, Any?> = emptyMap()

    val isInitialized: Boolean get() = manager != null

    val downloadManager: DownloadManager? get() = manager

    /** Settings the last [initialize] ran with, for the service to read. */
    val config: Map<String, Any?> get() = configuration

    /**
     * Builds the cache and the queue, or does nothing if they already exist.
     *
     * The config is persisted because the service can be created without Dart: a scheduler
     * resuming work after a reboot has no engine to ask, and bootstrapping with defaults would
     * point the queue at a different cache directory than the one holding the bytes.
     */
    @Synchronized
    fun initialize(
        context: Context,
        config: Map<String, Any?>?,
    ) {
        if (manager != null) return

        val applicationContext = context.applicationContext
        configuration = config ?: readPersistedConfig(applicationContext)
        if (config != null) persistConfig(applicationContext, config)

        val provider = StandaloneDatabaseProvider(applicationContext).also { databaseProvider = it }
        val directory =
            File(
                applicationContext.filesDir,
                configuration.string("directoryName") ?: "fplayer_downloads",
            )

        // No evictor: downloads are explicit. Silently deleting an episode the user asked to keep
        // because a newer one needed room would be worse than failing the newer download.
        val simpleCache = SimpleCache(directory, NoOpCacheEvictor(), provider)
        cache = simpleCache

        manager =
            DownloadManager(
                applicationContext,
                provider,
                simpleCache,
                networkDataSourceFactory(),
                Executors.newFixedThreadPool(MAX_DOWNLOAD_THREADS),
            ).apply {
                maxParallelDownloads = configuration.int("maxParallelDownloads") ?: 3
                minRetryCount = configuration.int("minRetryCount") ?: 5
                requirements = requirementsOf(configuration.map("requirements"))
            }
    }

    /**
     * Wraps a playback data source so it reads what has been downloaded.
     *
     * Returns [upstream] untouched when downloads were never initialised, which is what keeps
     * this a one-line, zero-cost change at the playback call site.
     *
     * The cache is opened **read-only** for playback: without that, ordinary streaming would
     * quietly fill the download directory with content the user never asked to keep, and the
     * no-op evictor would never let it go.
     */
    fun readThrough(upstream: DataSource.Factory): DataSource.Factory {
        val simpleCache = cache ?: return upstream

        return CacheDataSource
            .Factory()
            .setCache(simpleCache)
            .setUpstreamDataSourceFactory(upstream)
            .setCacheWriteDataSinkFactory(null)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
    }

    /**
     * The request behind a finished download of [uri], or null if there is none.
     *
     * Playback needs it because a downloaded adaptive stream is only *partly* on disk: the
     * manifest still advertises every rendition, so offline the adaptive selector will reach for
     * one that was never fetched and the stream dies. The request carries the stream keys that
     * were actually downloaded, which is what constrains the source back to reality.
     */
    fun completedRequestFor(uri: String): DownloadRequest? {
        val index = manager?.downloadIndex ?: return null

        return try {
            index.getDownload(uri)?.takeIf { it.state == Download.STATE_COMPLETED }?.request
        } catch (e: IOException) {
            // The index is a local database; a read failure means we fall back to streaming,
            // which is strictly better than failing to play at all.
            null
        }
    }

    /**
     * Data source the queue fetches with.
     *
     * Headers travel with each download rather than being set on the factory, because one queue
     * serves sources from different hosts with different credentials.
     */
    fun networkDataSourceFactory(): DataSource.Factory {
        val http = DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true)

        return ResolvingDataSource.Factory(http) { dataSpec ->
            val headers = DownloadHeaders.forUri(dataSpec.uri.toString())
            if (headers.isEmpty()) dataSpec else dataSpec.withAdditionalHeaders(headers)
        }
    }

    fun requirementsOf(requirements: Map<String, Any?>): Requirements {
        var flags = 0
        if (requirements.bool("network") ?: true) flags = flags or Requirements.NETWORK
        if (requirements.bool("unmeteredNetwork") == true) {
            flags = flags or Requirements.NETWORK_UNMETERED
        }
        if (requirements.bool("charging") == true) flags = flags or Requirements.DEVICE_CHARGING
        if (requirements.bool("deviceIdle") == true) flags = flags or Requirements.DEVICE_IDLE
        if (requirements.bool("storageNotLow") ?: true) {
            flags = flags or Requirements.DEVICE_STORAGE_NOT_LOW
        }
        return Requirements(flags)
    }

    /**
     * Whether the host app declared the download service.
     *
     * Without the declaration `startService` throws, so downloads fall back to running only while
     * the app is alive instead of taking the app down with them.
     */
    fun isServiceDeclared(context: Context): Boolean =
        runCatching {
            context.packageManager.getServiceInfo(
                ComponentName(context, FplayerDownloadService::class.java),
                0,
            )
            true
        }.getOrDefault(false)

    // region Payload

    /**
     * Packs the app's metadata and the request headers into the bytes Media3 stores with a
     * download.
     *
     * Headers have to be persisted, not held in memory: a download resumed after a reboot has to
     * re-authenticate with no app running to supply credentials. They live in the app's private
     * download index, which is the same protection the rest of the app's storage gets — but it
     * does mean a long-lived token sits on disk, so prefer short-lived ones.
     */
    fun encodePayload(
        metadata: String?,
        headers: Map<String, String>,
    ): ByteArray {
        val payload = JSONObject()
        if (metadata != null) payload.put(PAYLOAD_METADATA, metadata)
        if (headers.isNotEmpty()) payload.put(PAYLOAD_HEADERS, JSONObject(headers.toMap()))
        return payload.toString().toByteArray()
    }

    /** The app's own metadata string, or null. */
    fun metadataOf(data: ByteArray): String? =
        runCatching {
            JSONObject(String(data)).optString(PAYLOAD_METADATA).takeIf { it.isNotEmpty() }
        }.getOrNull()

    fun headersOf(data: ByteArray): Map<String, String> =
        runCatching {
            val headers = JSONObject(String(data)).optJSONObject(PAYLOAD_HEADERS)
                ?: return@runCatching emptyMap()
            buildMap {
                headers.keys().forEach { key -> put(key, headers.optString(key)) }
            }
        }.getOrDefault(emptyMap())

    // endregion

    private fun persistConfig(
        context: Context,
        config: Map<String, Any?>,
    ) {
        val directory = config.string("directoryName") ?: return
        context
            .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CONFIG, JSONObject(mapOf("directoryName" to directory)).toString())
            .apply()
    }

    private fun readPersistedConfig(context: Context): Map<String, Any?> {
        val stored =
            context
                .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .getString(KEY_CONFIG, null)
                ?: return emptyMap()

        return runCatching {
            val json = JSONObject(stored)
            buildMap<String, Any?> {
                json.keys().forEach { key -> put(key, json.get(key)) }
            }
        }.getOrDefault(emptyMap())
    }

    /** Six is what Media3's own sample uses; segment fetches are I/O bound, not CPU bound. */
    private const val MAX_DOWNLOAD_THREADS = 6
}

/**
 * Headers for downloads that are currently known.
 *
 * A cache in front of the download index: reading the persisted payload for every segment request
 * would mean a database hit per chunk, so entries are registered when a download is enqueued and
 * re-hydrated from the index when the queue is first read.
 */
internal object DownloadHeaders {
    private val byUri = mutableMapOf<String, Map<String, String>>()

    fun register(
        uri: String,
        headers: Map<String, String>,
    ) {
        if (headers.isEmpty()) byUri.remove(uri) else byUri[uri] = headers
    }

    fun forget(uri: String) {
        byUri.remove(uri)
    }

    /**
     * Headers for a request.
     *
     * Segments do not share the manifest's URI, so an exact match is only the first guess; the
     * fallback matches on origin, which is what keeps a token flowing to every chunk of the same
     * stream without leaking it to a different host.
     */
    fun forUri(uri: String): Map<String, String> {
        byUri[uri]?.let { return it }

        val origin = originOf(uri) ?: return emptyMap()
        return byUri.entries.firstOrNull { originOf(it.key) == origin }?.value.orEmpty()
    }

    private fun originOf(uri: String): String? {
        val schemeEnd = uri.indexOf("://")
        if (schemeEnd < 0) return null
        val pathStart = uri.indexOf('/', schemeEnd + 3)
        return if (pathStart < 0) uri else uri.substring(0, pathStart)
    }
}
