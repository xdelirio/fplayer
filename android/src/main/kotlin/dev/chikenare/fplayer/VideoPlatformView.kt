package dev.chikenare.fplayer

import android.content.Context
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Builds the [SurfaceView] a player renders into when it is not rendering into a texture.
 *
 * The view binds itself to an existing [PlayerHost] through the player id in its creation
 * params: the native player is always built first, by `create`, and Dart only mounts the view
 * once it holds that id.
 */
internal class VideoPlatformViewFactory(
    private val hostFor: (Long) -> PlayerHost?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(
        context: Context,
        viewId: Int,
        args: Any?,
    ): PlatformView {
        val playerId =
            ((args as? Map<*, *>)?.get("playerId") as? Number)?.toLong()
                ?: throw IllegalArgumentException("A video platform view needs a playerId")
        val host =
            hostFor(playerId)
                ?: throw IllegalStateException("No player $playerId to render into")
        return VideoPlatformView(context, host)
    }

    companion object {
        const val VIEW_TYPE = "${Channels.MAIN}/video"
    }
}

/**
 * A [SurfaceView] wired to a [PlayerHost] for as long as its surface exists.
 *
 * This is the path that exists because the texture one cannot serve every decoder. A frame that
 * reaches a Flutter texture has gone through an `ImageReader` and been imported into the GPU as
 * an external image, which only works while the decoder writes a plain, linear buffer. Television
 * SoCs hand their AV1 output over in a vendor-compressed layout (AFBC on Mali) that the import
 * misreads into green and magenta banding — the decode itself is fine, the handoff is not. A
 * SurfaceView has no handoff: the buffer goes to SurfaceFlinger in whatever layout it arrived in.
 */
private class VideoPlatformView(
    context: Context,
    private val host: PlayerHost,
) : PlatformView,
    SurfaceHolder.Callback {
    private val surfaceView =
        SurfaceView(context).apply {
            // The controls are Flutter widgets stacked on top of this. A focusable view down
            // here would swallow the first press of a TV remote before the overlay ever saw it.
            isFocusable = false
            isFocusableInTouchMode = false
        }

    private var isDisposed = false

    init {
        surfaceView.holder.addCallback(this)
    }

    override fun getView(): View = surfaceView

    override fun surfaceCreated(holder: SurfaceHolder) {
        if (!isDisposed) host.attachExternalSurface(holder.surface)
    }

    override fun surfaceChanged(
        holder: SurfaceHolder,
        format: Int,
        width: Int,
        height: Int,
    ) {
        // A resize can replace the buffers behind the holder. Re-attaching an unchanged surface
        // costs nothing, and skipping it when it did change costs the picture.
        if (!isDisposed) host.attachExternalSurface(holder.surface)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        host.detachExternalSurface(holder.surface)
    }

    override fun dispose() {
        if (isDisposed) return
        isDisposed = true
        surfaceView.holder.removeCallback(this)
        host.detachExternalSurface(surfaceView.holder.surface)
    }
}
