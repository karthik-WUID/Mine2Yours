package com.mine2yourlingo.mine2yourlingo

import org.junit.Assert.*
import org.junit.Test

class PlaybackDeadlinePolicyTest {
    private val now = 1_700_000_000_000L

    @Test fun deadlineAcceptsCodecIntegersOnly() {
        assertEquals(100L, PlaybackDeadlinePolicy.parse(100))
        assertEquals(now + 1, PlaybackDeadlinePolicy.parse(now + 1))
        for (value in listOf(null, "1700000000001", 1700000000001.0, true)) {
            assertNull(PlaybackDeadlinePolicy.parse(value))
        }
    }

    @Test fun omittedDeadlineAndFutureBoundariesAreAccepted() {
        assertNull(PlaybackDeadlinePolicy.error(null, now))
        assertNull(PlaybackDeadlinePolicy.error(now + 1, now))
        assertNull(PlaybackDeadlinePolicy.error(now + PlaybackDeadlinePolicy.MAX_AHEAD_MILLIS, now))
        assertFalse(PlaybackDeadlinePolicy.expired(null, now))
        assertFalse(PlaybackDeadlinePolicy.expired(now + 1, now))
    }

    @Test fun elapsedBoundariesUseQuietHoursCancellationReason() {
        assertEquals("quiet_hours_started", PlaybackDeadlinePolicy.error(now, now))
        assertEquals("quiet_hours_started", PlaybackDeadlinePolicy.error(now - 1, now))
        assertTrue(PlaybackDeadlinePolicy.expired(now, now))
    }

    @Test fun nonPositiveAndOverlongDeadlinesAreRejected() {
        for (deadline in listOf(0L, -1L, Long.MIN_VALUE, now + PlaybackDeadlinePolicy.MAX_AHEAD_MILLIS + 1, Long.MAX_VALUE)) {
            assertEquals("invalid_playback_deadline", PlaybackDeadlinePolicy.error(deadline, now))
        }
    }
}
