package dev.chikenare.fplayer

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.offline.DownloadHelper
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import dev.chikenare.fplayer.download.DownloadStore
import io.flutter.FlutterInjector

/**
 * Turns the `source` map sent from Dart into a [MediaItem] plus the [MediaSource.Factory] that
 * knows how to fetch it — headers, timeouts, user agent, side-loaded subtitles.
 *
 * A fresh factory is built per source because headers belong to the source, not to the player.
 */
@OptIn(UnstableApi::class)
internal object SourceFactory {
    private const val FLUTTER_ASSET_PREFIX = "asset:///"

    fun mediaItem(
        source: Map<String, Any?>,
        metadata: Map<String, Any?> = emptyMap(),
    ): MediaItem {
        val builder = MediaItem.Builder().setUri(resolveUri(source))

        mimeTypeFor(source.string("type"))?.let(builder::setMimeType)
        builder.setMediaMetadata(mediaMetadata(metadata))

        val subtitles = subtitlesOf(source)
        if (subtitles.isNotEmpty()) {
            builder.setSubtitleConfigurations(subtitles.map(::subtitleConfiguration))
        }

        drmConfiguration(source.map("drm"))?.let(builder::setDrmConfiguration)

        return builder.build()
    }

    fun mediaSourceFactory(
        context: Context,
        source: Map<String, Any?>,
        network: Map<String, Any?>,
        loadErrorPolicy: LoadErrorHandlingPolicy? = null,
    ): MediaSource.Factory {
        val factory =
            DefaultMediaSourceFactory(context)
                .setDataSourceFactory(dataSourceFactory(context, source, network))

        return if (loadErrorPolicy == null) {
            factory
        } else {
            factory.setLoadErrorHandlingPolicy(loadErrorPolicy)
        }
    }

    /**
     * Where the bytes come from: the download cache first, the network behind it.
     *
     * [DownloadStore.readThrough] returns its argument untouched when downloads were never
     * initialised, so this costs nothing for apps that do not use them. The header-injecting
     * resolver sits *upstream* of the cache on purpose: a cache hit needs no credentials, and only
     * misses reach the wire.
     */
    private fun dataSourceFactory(
        context: Context,
        source: Map<String, Any?>,
        network: Map<String, Any?>,
    ): DataSource.Factory {
        val base: DataSource.Factory =
            if (isRemote(source)) {
                DefaultDataSource.Factory(context, httpFactory(source, network))
            } else {
                DefaultDataSource.Factory(context)
            }

        return DownloadStore.readThrough(headerInjecting(base, source))
    }

    /**
     * The media source for [source], constrained to what was downloaded when there is a download.
     *
     * A downloaded adaptive stream is only partly on disk: its manifest still advertises every
     * rendition, so offline the adaptive selector reaches for one that was never fetched and the
     * stream dies. The download request carries the stream keys that were actually written, which
     * is what pins the source back to reality. Streaming and progressive media fall through to the
     * ordinary path.
     */
    fun mediaSource(
        context: Context,
        source: Map<String, Any?>,
        network: Map<String, Any?>,
        metadata: Map<String, Any?> = emptyMap(),
        loadErrorPolicy: LoadErrorHandlingPolicy? = null,
    ): MediaSource {
        val request = DownloadStore.completedRequestFor(resolveUri(source))

        if (request == null) {
            return mediaSourceFactory(context, source, network, loadErrorPolicy)
                .createMediaSource(mediaItem(source, metadata))
        }

        // Everything is on disk, so the load error policy has nothing to retry against.
        //
        // Built through the ordinary factory from a media item that carries *both* — the stream
        // keys that pin playback to what was actually written, and everything the app configured.
        // `DownloadHelper.createMediaSource(request, …)` takes the request alone, and a request
        // holds only what identifies the bytes: going through it dropped the title and artwork
        // the lock screen shows, every side-loaded subtitle, and the DRM configuration of a
        // protected download.
        return mediaSourceFactory(context, source, network, loadErrorPolicy = null)
            .createMediaSource(request.toMediaItem(mediaItem(source, metadata).buildUpon()))
    }

    /** Position, in milliseconds, the item should start at. */
    fun startPositionMs(source: Map<String, Any?>): Long = source.long("startAtMs") ?: 0L

    /**
     * What the lock screen, the notification and Android Auto display for this media.
     *
     * `artworkUri` is fetched by Media3's own bitmap loader, so a poster URL is all that is needed
     * — no bitmap ever crosses the platform channel.
     */
    private fun mediaMetadata(metadata: Map<String, Any?>): MediaMetadata =
        MediaMetadata
            .Builder()
            .setTitle(metadata.string("title"))
            .setArtist(metadata.string("subtitle"))
            .setArtworkUri(metadata.string("artworkUri")?.let(Uri::parse))
            .setIsBrowsable(false)
            .setIsPlayable(true)
            .build()

    /**
     * Applies the right headers to each request based on its URI.
     *
     * Headers are injected per request rather than set as defaults on the HTTP factory so that a
     * subtitle hosted on someone else's server never receives the media's `Authorization` token.
     * Everything that is not a declared subtitle URI — the manifest, every segment, every key —
     * gets the media's headers.
     */
    private fun headerInjecting(
        base: DataSource.Factory,
        source: Map<String, Any?>,
    ): DataSource.Factory {
        val mediaHeaders = source.stringMap("headers")
        val subtitleHeaders =
            subtitlesOf(source)
                .filter { it.stringMap("headers").isNotEmpty() }
                .associate { it.string("uri").orEmpty() to it.stringMap("headers") }

        if (mediaHeaders.isEmpty() && subtitleHeaders.isEmpty()) return base

        return ResolvingDataSource.Factory(base) { dataSpec ->
            val headers = subtitleHeaders[dataSpec.uri.toString()] ?: mediaHeaders
            if (headers.isEmpty()) dataSpec else dataSpec.withAdditionalHeaders(headers)
        }
    }

    private fun httpFactory(
        source: Map<String, Any?>,
        network: Map<String, Any?>,
    ): DefaultHttpDataSource.Factory {
        // A per-source User-Agent wins over the player-wide default. It is set on the factory
        // rather than injected, because DefaultHttpDataSource writes it after request properties.
        val userAgent =
            source
                .stringMap("headers")
                .entries
                .firstOrNull { it.key.equals("user-agent", ignoreCase = true) }
                ?.value
                ?: network.string("userAgent")

        return DefaultHttpDataSource
            .Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(network.bool("allowCrossProtocolRedirects") ?: true)
            .setConnectTimeoutMs(
                network.int("connectTimeoutMs")
                    ?: DefaultHttpDataSource.DEFAULT_CONNECT_TIMEOUT_MILLIS,
            ).setReadTimeoutMs(
                network.int("readTimeoutMs") ?: DefaultHttpDataSource.DEFAULT_READ_TIMEOUT_MILLIS,
            )
    }

    /**
     * Widevine parameters for protected media, or null when the source is in the clear.
     *
     * The license request carries its own headers rather than the media's: a license server is a
     * different service from the CDN, usually with different credentials, and sending a CDN token
     * to it would leak one to the other.
     */
    private fun drmConfiguration(drm: Map<String, Any?>): MediaItem.DrmConfiguration? {
        val licenseUrl = drm.string("licenseUrl") ?: return null

        return MediaItem.DrmConfiguration
            .Builder(C.WIDEVINE_UUID)
            .setLicenseUri(licenseUrl)
            .setLicenseRequestHeaders(drm.stringMap("headers"))
            .setMultiSession(drm.bool("multiSession") ?: false)
            .setPlayClearContentWithoutKey(drm.bool("playClearContentWithoutKey") ?: false)
            .setForceDefaultLicenseUri(drm.bool("forceDefaultLicenseUri") ?: false)
            .build()
    }

    @Suppress("UNCHECKED_CAST")
    private fun subtitlesOf(source: Map<String, Any?>): List<Map<String, Any?>> =
        (source["subtitles"] as? List<Map<String, Any?>>).orEmpty()

    private fun subtitleConfiguration(subtitle: Map<String, Any?>): MediaItem.SubtitleConfiguration {
        val uri = subtitle.string("uri").orEmpty()
        val resolved = if (subtitle.string("kind") == "file" && !uri.startsWith("file://")) {
            "file://$uri"
        } else {
            uri
        }

        return MediaItem.SubtitleConfiguration
            .Builder(Uri.parse(resolved))
            .setMimeType(subtitle.string("mimeType") ?: subtitleMimeType(uri))
            .setLanguage(subtitle.string("language"))
            .setLabel(subtitle.string("label"))
            .setSelectionFlags(
                if (subtitle.bool("selectedByDefault") == true) C.SELECTION_FLAG_DEFAULT else 0,
            ).build()
    }

    /**
     * Media3 needs a MIME type to pick a parser for a side-loaded subtitle; unlike media, it will
     * not sniff one. The extension is the only hint available before the file is fetched.
     */
    private fun subtitleMimeType(uri: String): String {
        val path = uri.substringBefore('?').substringBefore('#').lowercase()
        return when {
            path.endsWith(".srt") -> MimeTypes.APPLICATION_SUBRIP
            path.endsWith(".vtt") || path.endsWith(".webvtt") -> MimeTypes.TEXT_VTT
            path.endsWith(".ass") || path.endsWith(".ssa") -> MimeTypes.TEXT_SSA
            path.endsWith(".ttml") || path.endsWith(".dfxp") || path.endsWith(".xml") ->
                MimeTypes.APPLICATION_TTML
            // WebVTT is the most common format served without a telling extension.
            else -> MimeTypes.TEXT_VTT
        }
    }

    private fun resolveUri(source: Map<String, Any?>): String {
        val uri =
            source.string("uri")
                ?: throw IllegalArgumentException("source.uri is required")

        return when (source.string("kind")) {
            "asset" -> FLUTTER_ASSET_PREFIX + lookupKeyForAsset(uri, source.string("package"))
            "file" -> if (uri.startsWith("file://")) uri else "file://$uri"
            else -> uri
        }
    }

    private fun lookupKeyForAsset(
        asset: String,
        packageName: String?,
    ): String {
        val loader = FlutterInjector.instance().flutterLoader()
        return if (packageName != null) {
            loader.getLookupKeyForAsset(asset, packageName)
        } else {
            loader.getLookupKeyForAsset(asset)
        }
    }

    private fun isRemote(source: Map<String, Any?>): Boolean = source.string("kind") == "network"

    /**
     * Only set an explicit MIME type when the caller forced one. On `auto` we let Media3 infer it
     * from the URI (and from the response `Content-Type`), which is more reliable than guessing
     * from the file extension — plenty of HLS endpoints have no `.m3u8` in the path.
     */
    private fun mimeTypeFor(type: String?): String? =
        when (type) {
            "hls" -> MimeTypes.APPLICATION_M3U8
            "dash" -> MimeTypes.APPLICATION_MPD
            "smoothStreaming" -> MimeTypes.APPLICATION_SS
            else -> null
        }
}
