package com.mine2yourlingo.mine2yourlingo

import org.junit.Assert.*
import org.junit.Test

class PlaybackRequestPolicyTest {
    @Test fun acceptsUuidAndEveryAllowedCharacter() {
        val uuid = "179e8a43-cc78-4d99-978b-aad2eb4e10c4"
        assertEquals(uuid, PlaybackRequestPolicy.parse(uuid))
        val allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
        assertEquals(allowed, PlaybackRequestPolicy.parse(allowed))
    }

    @Test fun identifiersHaveInclusiveLengthBounds() {
        assertEquals("a", PlaybackRequestPolicy.parse("a"))
        assertEquals("a".repeat(128), PlaybackRequestPolicy.parse("a".repeat(128)))
        assertNull(PlaybackRequestPolicy.parse(""))
        assertNull(PlaybackRequestPolicy.parse("a".repeat(129)))
    }

    @Test fun rejectsNullAndOtherCodecTypesRatherThanStringifying() {
        for (value in listOf(null, 123, 123L, 123.0, true, byteArrayOf(1), listOf("uuid"), mapOf("id" to "uuid"))) {
            assertNull(PlaybackRequestPolicy.parse(value))
        }
    }

    @Test fun rejectsWhitespacePunctuationControlCharactersAndNonAscii() {
        for (value in listOf(" a", "a ", "a.b", "a/b", "a?signature=x", "a\n", "a\r", "a\t", "a\u0000", "é", "தமிழ்", "😀")) {
            assertNull(PlaybackRequestPolicy.parse(value))
        }
    }
}
