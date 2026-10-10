package com.mine2yourlingo.mine2yourlingo

/** Wall-clock playback boundary supplied by the app's local quiet-hours policy. */
object PlaybackDeadlinePolicy {
    const val MAX_AHEAD_MILLIS = 48L * 60 * 60 * 1000

    // StandardMessageCodec represents integer values as either Int or Long.
    fun parse(value: Any?): Long? = when (value) {
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }

    fun error(deadline: Long?, now: Long = System.currentTimeMillis()): String? {
        if (deadline == null) return null
        if (deadline <= 0) return "invalid_playback_deadline"
        if (deadline <= now) return "quiet_hours_started"
        if (deadline - now > MAX_AHEAD_MILLIS) return "invalid_playback_deadline"
        return null
    }

    fun expired(deadline: Long?, now: Long = System.currentTimeMillis()): Boolean =
        deadline != null && deadline <= now
}
