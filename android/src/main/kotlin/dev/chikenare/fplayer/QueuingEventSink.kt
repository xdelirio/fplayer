package dev.chikenare.fplayer

import io.flutter.plugin.common.EventChannel

/**
 * Buffers events emitted before Dart subscribes to the event channel.
 *
 * ExoPlayer starts reporting as soon as it is built, which is typically a few frames before the
 * Dart side finishes wiring up its stream listener. Without this queue the very first
 * `initialized` event is silently dropped and the player looks stuck on "loading".
 *
 * Bounded, because the far end can also go away and not come back: after `onCancel` the player
 * keeps reporting progress four times a second, and a queue nobody will ever drain is a leak
 * that grows for as long as the player lives. Past the cap the oldest events are dropped — they
 * are the least interesting ones, and a listener arriving late wants the current state, not a
 * transcript.
 *
 * Not thread safe: every call happens on the main thread.
 */
internal class QueuingEventSink : EventChannel.EventSink {
    private var delegate: EventChannel.EventSink? = null
    private val queue = mutableListOf<Any>()
    private var done = false

    fun setDelegate(sink: EventChannel.EventSink?) {
        delegate = sink
        flush()
    }

    override fun success(event: Any?) {
        if (done || event == null) return
        queue.add(Event.Success(event))
        trim()
        flush()
    }

    override fun error(
        errorCode: String,
        errorMessage: String?,
        errorDetails: Any?,
    ) {
        if (done) return
        queue.add(Event.Error(errorCode, errorMessage, errorDetails))
        trim()
        flush()
    }

    override fun endOfStream() {
        if (done) return
        queue.add(Event.EndOfStream)
        flush()
        done = true
    }

    private fun trim() {
        if (queue.size <= MAX_QUEUED) return
        queue.subList(0, queue.size - MAX_QUEUED).clear()
    }

    private fun flush() {
        val sink = delegate ?: return
        queue.forEach {
            when (it) {
                is Event.Success -> sink.success(it.value)
                is Event.Error -> sink.error(it.code, it.message, it.details)
                Event.EndOfStream -> sink.endOfStream()
            }
        }
        queue.clear()
    }

    private companion object {
        /** Roughly a minute of progress ticks at the default interval. */
        const val MAX_QUEUED = 256
    }

    private sealed interface Event {
        data class Success(
            val value: Any,
        ) : Event

        data class Error(
            val code: String,
            val message: String?,
            val details: Any?,
        ) : Event

        data object EndOfStream : Event
    }
}
