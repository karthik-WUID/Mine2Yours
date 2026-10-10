package com.mine2yourlingo.mine2yourlingo

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.net.InetSocketAddress
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicInteger
import com.sun.net.httpserver.HttpServer
import com.sun.net.httpserver.Headers
import org.junit.Assert.*
import org.junit.Test

class AudioDownloadPolicyTest {
    @Test fun productionAllowsHttpsButRejectsCleartextAndCredentialUrls() {
        assertEquals("https", AudioDownloadPolicy.validateUrl("https://api.example.com/v1/audio/example?signature=sample", false).scheme)
        for (url in listOf("http://localhost:3100/audio", "http://api.example.com/audio", "http://192.168.0.101/audio", "http://Karthikeyans-MacBook-Pro.local/audio", "https://user:pass@api.example.com/audio", "file:///tmp/audio", "https://api.example.com/audio#fragment")) {
            assertThrows(IllegalArgumentException::class.java) { AudioDownloadPolicy.validateUrl(url, false) }
        }
    }

    @Test fun debugHttpAllowsLocalReviewHostsAndRejectsPublicOrSpoofedAddresses() {
        for (host in listOf("localhost", "127.0.0.1", "10.0.2.2", "[::1]", "192.168.0.101", "172.16.0.3", "10.12.0.2", "Karthikeyans-MacBook-Pro.local")) {
            assertEquals("http", AudioDownloadPolicy.validateUrl("http://$host:3100/audio", true).scheme)
        }
        for (host in listOf("localhost.evil.example", "192.168.1.999", "172.32.0.1", "8.8.8.8", "api.example.com", "server.local.evil.example", "127.0.0.1.evil.example")) {
            assertThrows(IllegalArgumentException::class.java) { AudioDownloadPolicy.validateUrl("http://$host/audio", true) }
        }
    }

    @Test fun authenticatedRequestsNeverFollowRedirectsAndDropOtherHeaders() {
        val captured = AtomicReference<Headers>()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/audio") { exchange ->
            captured.set(exchange.requestHeaders)
            exchange.responseHeaders.add("Content-Type", "audio/wav")
            exchange.sendResponseHeaders(200, 1)
            exchange.responseBody.use { it.write(1) }
            exchange.close()
        }
        server.start()
        try {
            val request = AudioDownloadPolicy.open(AudioDownloadPolicy.validateUrl("http://127.0.0.1:${server.address.port}/audio", true),
                mapOf("Authorization" to "Bearer local-test", "Cookie" to "private-cookie", "X-Provider-Key" to "not-allowed"))
            assertFalse(request.instanceFollowRedirects)
            assertEquals(200, request.responseCode)
            assertEquals("Bearer local-test", captured.get().getFirst("Authorization"))
            assertNull(captured.get().getFirst("Cookie"))
            assertNull(captured.get().getFirst("X-Provider-Key"))
            request.disconnect()
        } finally { server.stop(0) }
    }

    @Test fun redirectCannotForwardCredentialsOrFetchAnotherEndpoint() {
        val destinationRequests = AtomicInteger()
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/redirect") { exchange ->
            exchange.responseHeaders.add("Location", "http://127.0.0.1:${server.address.port}/destination")
            exchange.sendResponseHeaders(302, -1); exchange.close()
        }
        server.createContext("/destination") { exchange ->
            destinationRequests.incrementAndGet(); exchange.sendResponseHeaders(200, -1); exchange.close()
        }
        server.start()
        try {
            val request = AudioDownloadPolicy.open(AudioDownloadPolicy.validateUrl("http://127.0.0.1:${server.address.port}/redirect", true), mapOf("Authorization" to "Bearer local-test"))
            assertEquals(302, request.responseCode)
            assertEquals(0, destinationRequests.get())
            request.disconnect()
        } finally { server.stop(0) }
    }

    @Test fun exactSizeLimitIsAccepted() {
        val output = ByteArrayOutputStream()
        assertEquals(AudioDownloadPolicy.MAX_BYTES, AudioDownloadPolicy.copyBounded(
            ByteArrayInputStream(ByteArray(AudioDownloadPolicy.MAX_BYTES)), output) { false })
        assertEquals(AudioDownloadPolicy.MAX_BYTES, output.size())
    }

    @Test fun oversizedAndEmptyStreamsAreRejectedWithoutWritingBeyondLimit() {
        val output = ByteArrayOutputStream()
        assertThrows(IllegalArgumentException::class.java) {
            AudioDownloadPolicy.copyBounded(ByteArrayInputStream(ByteArray(AudioDownloadPolicy.MAX_BYTES + 1)), output) { false }
        }
        assertTrue(output.size() <= AudioDownloadPolicy.MAX_BYTES)
        assertThrows(IllegalArgumentException::class.java) {
            AudioDownloadPolicy.copyBounded(ByteArrayInputStream(byteArrayOf()), ByteArrayOutputStream()) { false }
        }
    }

    @Test fun cancelledPlaybackCannotWriteDownloadedBytes() {
        val output = ByteArrayOutputStream()
        assertThrows(InterruptedException::class.java) {
            AudioDownloadPolicy.copyBounded(ByteArrayInputStream(byteArrayOf(1, 2, 3)), output) { true }
        }
        assertEquals(0, output.size())
    }
}
