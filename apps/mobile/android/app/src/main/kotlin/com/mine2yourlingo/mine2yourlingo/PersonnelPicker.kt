package com.mine2yourlingo.mine2yourlingo

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class PersonnelPicker(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var profile = false
    fun pick(kind: String, result: MethodChannel.Result) {
        if (pending != null) { result.error("picker_busy", "Finish choosing the current photo first.", null); return }
        profile = kind == "profile"; pending = result
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"; addCategory(Intent.CATEGORY_OPENABLE)
            }, 4402)
        } catch (_: Exception) { pending = null; result.error("picker_unavailable", "No photo picker is available on this phone.", null) }
    }
    fun returned(code: Int, data: Intent?) {
        val result = pending ?: return
        if (code != Activity.RESULT_OK || data?.data == null) { pending = null; result.success(null); return }
        val uri = data.data!!
        val isProfile = profile
        Thread {
            try {
                val bytes = activity.contentResolver.openInputStream(uri)?.use { stream ->
                    val out = ByteArrayOutputStream(); val buffer = ByteArray(8192)
                    while (true) { val count = stream.read(buffer); if (count < 0) break; out.write(buffer, 0, count); require(out.size() <= 16 * 1024 * 1024) }
                    out.toByteArray()
                } ?: error("No photo selected")
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                require(bounds.outWidth > 0 && bounds.outHeight > 0)
                val size = if (isProfile) 512 else 1600
                var sample = 1
                while (maxOf(bounds.outWidth, bounds.outHeight) / sample > size * 2) sample *= 2
                var bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: error("Unreadable photo")
                val scale = minOf(1.0, size.toDouble() / maxOf(bitmap.width, bitmap.height))
                if (scale < 1) {
                    val resized = Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * scale).toInt()), maxOf(1, (bitmap.height * scale).toInt()), true)
                    if (resized != bitmap) bitmap.recycle(); bitmap = resized
                }
                val limit = if (isProfile) 256 * 1024 else 1024 * 1024
                var quality = 90
                val out = ByteArrayOutputStream()
                do { out.reset(); bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out); quality -= 10 } while (out.size() > limit && quality >= 30)
                bitmap.recycle(); require(out.size() <= limit)
                val encoded = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
                activity.runOnUiThread { if (pending === result) { pending = null; result.success(mapOf("base64" to encoded, "mimeType" to "image/jpeg")) } }
            } catch (_: Exception) {
                activity.runOnUiThread { if (pending === result) { pending = null; result.error("invalid_photo", "Choose a readable photo smaller than 16 MB.", null) } }
            }
        }.start()
    }
    fun close() { pending?.error("activity_closed", "Photo selection was closed.", null); pending = null }
}
