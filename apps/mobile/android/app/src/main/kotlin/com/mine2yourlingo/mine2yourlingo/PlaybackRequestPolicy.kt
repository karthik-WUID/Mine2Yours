package com.mine2yourlingo.mine2yourlingo

/** Public request correlation is bounded and distinct from the native utterance token. */
object PlaybackRequestPolicy {
    const val MAX_LENGTH = 128

    fun valid(value: String): Boolean = value.length in 1..MAX_LENGTH && value.all {
        it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '_' || it == '-'
    }

    fun parse(value: Any?): String? = (value as? String)?.takeIf(::valid)
}
