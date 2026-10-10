package com.mine2yourlingo.mine2yourlingo

import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URI

/** Pure JVM download guards, independent of Android lifecycle and player state. */
object AudioDownloadPolicy {
    const val MAX_BYTES = 4_000_000

    fun validateUrl(address: String, debug: Boolean): URI {
        val uri = URI(address)
        val host = uri.host?.lowercase().orEmpty()
        val loopback = host in setOf("localhost", "127.0.0.1", "[::1]", "::1", "10.0.2.2")
        val parts = host.split('.').mapNotNull { it.toIntOrNull() }
        val privateIpv4 = parts.size == 4 && parts.all { it in 0..255 } &&
            (parts[0] == 10 || (parts[0] == 172 && parts[1] in 16..31) || (parts[0] == 192 && parts[1] == 168))
        // Dart first requires the audio origin to match the configured API.
        // The review server uses LAN/mDNS; Android cleartext stays debug-only.
        val localReview = loopback || privateIpv4 || host.endsWith(".local")
        require(!uri.host.isNullOrBlank() && uri.userInfo == null && uri.fragment == null)
        require(uri.scheme == "https" || (debug && localReview && uri.scheme == "http"))
        return uri
    }

    fun open(uri: URI, headers: Map<String, String>): HttpURLConnection {
        val request = uri.toURL().openConnection() as HttpURLConnection
        request.instanceFollowRedirects = false
        request.connectTimeout = 10000; request.readTimeout = 20000
        request.setRequestProperty("Accept", "audio/*")
        headers.filterKeys { it.equals("Authorization", true) || it.equals("Accept", true) }
            .forEach { (key, value) -> request.setRequestProperty(key, value) }
        return request
    }

    fun copyBounded(input: InputStream, output: OutputStream, cancelled: () -> Boolean): Int {
        var count = 0
        val bytes = ByteArray(8192)
        while (true) {
            if (Thread.currentThread().isInterrupted || cancelled()) throw InterruptedException()
            val read = input.read(bytes)
            if (read < 0) break
            count += read
            require(count <= MAX_BYTES) { "Audio exceeds size limit" }
            output.write(bytes, 0, read)
        }
        require(count > 0) { "Empty audio" }
        return count
    }
}
