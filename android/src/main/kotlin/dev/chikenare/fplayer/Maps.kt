package dev.chikenare.fplayer

/**
 * Typed accessors for the maps that arrive over the method channel.
 *
 * Flutter's standard codec sends integers as `Integer` or `Long` depending on magnitude, so every
 * numeric read goes through [Number] instead of casting directly.
 */

internal fun Map<String, Any?>.string(key: String): String? = this[key] as? String

internal fun Map<String, Any?>.bool(key: String): Boolean? = this[key] as? Boolean

internal fun Map<String, Any?>.int(key: String): Int? = (this[key] as? Number)?.toInt()

internal fun Map<String, Any?>.long(key: String): Long? = (this[key] as? Number)?.toLong()

internal fun Map<String, Any?>.double(key: String): Double? = (this[key] as? Number)?.toDouble()

internal fun Map<String, Any?>.float(key: String): Float? = (this[key] as? Number)?.toFloat()

@Suppress("UNCHECKED_CAST")
internal fun Map<String, Any?>.map(key: String): Map<String, Any?> =
    (this[key] as? Map<String, Any?>).orEmpty()

@Suppress("UNCHECKED_CAST")
internal fun Map<String, Any?>.stringMap(key: String): Map<String, String> =
    (this[key] as? Map<String, String>).orEmpty()

internal fun Map<String, Any?>.stringList(key: String): List<String>? =
    (this[key] as? List<*>)?.filterIsInstance<String>()
