package com.example.copy_cat

import android.app.Activity
import android.content.Intent
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Host-side audio helpers so the app builds fully offline:
 * - SAF document picker (replaces file_picker, whose Gradle deps are
 *   unreachable on this network)
 * - android.media.MediaPlayer playback + duration probe (replaces just_audio /
 *   ExoPlayer for the same reason)
 */
class MainActivity : FlutterActivity() {
    private val channelName = "mimic_party/audio"
    private val pickCode = 41201
    private var pendingPick: MethodChannel.Result? = null
    private var pendingPlay: MethodChannel.Result? = null
    private var player: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAudio" -> startPick(result)
                    "playOnce" -> playOnce(call.argument<String>("path"), result)
                    "stopPlayback" -> {
                        stopPlayer()
                        completePlay(null)
                        result.success(null)
                    }
                    "probeDurationMs" -> result.success(
                        probeDurationMs(call.argument<String>("path"))
                    )
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("NO_URL", "Missing url", null)
                        } else {
                            try {
                                startActivity(
                                    Intent(
                                        Intent.ACTION_VIEW,
                                        Uri.parse(url)
                                    )
                                )
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("OPEN_FAILED", e.message, null)
                            }
                        }
                    }
                    "decodeToWav" -> decodeToWavAsync(
                        call.argument<String>("path"),
                        result
                    )
                    else -> result.notImplemented()
                }
            }
    }

    // ---------- SAF import ----------

    private fun startPick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("BUSY", "Picker already open", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "audio/wav", "audio/x-wav", "audio/mpeg", "audio/mp3",
                    "audio/mp4", "audio/x-m4a", "audio/aac"
                )
            )
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, pickCode)
    }

    @Deprecated("Legacy onActivityResult still works for SAF picks")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickCode) return
        val result = pendingPick
        pendingPick = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        try {
            result.success(copyToCache(data.data!!))
        } catch (e: Exception) {
            result.error("COPY_FAILED", e.message, null)
        }
    }

    private fun copyToCache(uri: Uri): String {
        val name = queryName(uri) ?: "import_${System.currentTimeMillis()}"
        val ext = when {
            name.contains('.') -> name.substringAfterLast('.', "m4a")
            else -> when (contentResolver.getType(uri)) {
                "audio/wav", "audio/x-wav" -> "wav"
                "audio/mpeg", "audio/mp3" -> "mp3"
                else -> "m4a"
            }
        }
        val dest = File(cacheDir, "mimic_import_${System.currentTimeMillis()}.$ext")
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(dest).use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("Cannot open picked file")
        return dest.absolutePath
    }

    private fun queryName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex("_display_name")
                if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    // ---------- Playback / probe ----------

    private fun playOnce(path: String?, result: MethodChannel.Result) {
        if (path == null) {
            result.error("NO_PATH", "Missing path", null)
            return
        }
        if (pendingPlay != null) {
            result.error("BUSY", "Already playing", null)
            return
        }
        pendingPlay = result
        try {
            stopPlayer()
            val mp = MediaPlayer()
            player = mp
            mp.setDataSource(path)
            mp.setOnCompletionListener { completePlay(null) }
            mp.setOnErrorListener { _, what, extra ->
                completePlayError("PLAY_FAILED", "MediaPlayer error $what/$extra")
                true
            }
            mp.prepare()
            mp.start()
        } catch (e: Exception) {
            stopPlayer()
            completePlayError("PLAY_FAILED", e.message)
        }
    }

    private fun stopPlayer() {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        try {
            player?.release()
        } catch (_: Exception) {
        }
        player = null
    }

    private fun completePlay(value: Any?) {
        val r = pendingPlay
        pendingPlay = null
        stopPlayer()
        r?.success(value)
    }

    private fun completePlayError(code: String, message: String?) {
        val r = pendingPlay
        pendingPlay = null
        stopPlayer()
        r?.error(code, message, null)
    }

    private fun probeDurationMs(path: String?): Int {
        if (path == null) return -1
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toInt() ?: -1
        } catch (_: Exception) {
            -1
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    // ---------- Decode to PCM WAV (scoring needs samples, not AAC) ----------

    private fun decodeToWavAsync(path: String?, result: MethodChannel.Result) {
        Thread {
            try {
                val out = transcodeToWav(path)
                runOnUiThread {
                    try {
                        result.success(out)
                    } catch (_: Exception) {
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    try {
                        result.error("DECODE_FAILED", e.message, null)
                    } catch (_: Exception) {
                    }
                }
            }
        }.start()
    }

    private fun transcodeToWav(path: String?): String {
        if (path.isNullOrBlank()) throw IllegalArgumentException("Missing path")
        if (path.endsWith(".wav", ignoreCase = true)) return path
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            var track = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val candidate = extractor.getTrackFormat(i)
                val mime = candidate.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    track = i
                    format = candidate
                    break
                }
            }
            if (track < 0 || format == null) {
                throw IllegalStateException("No audio track")
            }
            extractor.selectTrack(track)
            val mime = format.getString(MediaFormat.KEY_MIME)
                ?: throw IllegalStateException("No mime")
            val decoder = MediaCodec.createDecoderByType(mime)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()

            var sampleRate = optInt(format, MediaFormat.KEY_SAMPLE_RATE, 44100)
            var channels = optInt(format, MediaFormat.KEY_CHANNEL_COUNT, 1)
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            val pcm = ByteArrayOutputStream()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var spins = 0
            var emptySpins = 0
            while (!outputDone && spins < 8000) {
                spins++
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buf = decoder.getInputBuffer(inIndex)
                            ?: throw IllegalStateException("No input buffer")
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(
                                inIndex, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(
                                inIndex, 0, size, extractor.sampleTime, 0
                            )
                            extractor.advance()
                        }
                    }
                }
                when (val outIndex = decoder.dequeueOutputBuffer(info, 10_000)) {
                    MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        if (inputDone) {
                            emptySpins++
                            if (emptySpins > 40) outputDone = true
                        }
                    }
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val outFormat = decoder.outputFormat
                        sampleRate = optInt(outFormat, MediaFormat.KEY_SAMPLE_RATE, sampleRate)
                        channels = optInt(outFormat, MediaFormat.KEY_CHANNEL_COUNT, channels)
                        encoding = optInt(outFormat, MediaFormat.KEY_PCM_ENCODING, encoding)
                    }
                    else -> {
                        if (outIndex >= 0) {
                            emptySpins = 0
                            val out = decoder.getOutputBuffer(outIndex)
                            val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                            if (out != null && info.size > 0 && !config) {
                                appendPcm(pcm, out, info, encoding)
                            }
                            decoder.releaseOutputBuffer(outIndex, false)
                            val cap = sampleRate.coerceAtLeast(1) * channels.coerceAtLeast(1) * 2 * 8
                            if (pcm.size() >= cap) outputDone = true
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                outputDone = true
                            }
                        }
                    }
                }
            }
            var bytes = pcm.toByteArray()
            val block = (channels.coerceAtLeast(1) * 2)
            val trimmed = bytes.size - (bytes.size % block)
            if (trimmed <= 0 || sampleRate <= 0 || channels <= 0) {
                throw IllegalStateException("Decoder produced no audio")
            }
            if (trimmed != bytes.size) bytes = bytes.copyOf(trimmed)
            val dest = File(cacheDir, "mimic_dec_${System.currentTimeMillis()}.wav")
            FileOutputStream(dest).use { stream ->
                stream.write(wavHeader(bytes.size, sampleRate, channels))
                stream.write(bytes)
            }
            return dest.absolutePath
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            try {
                codec?.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun optInt(format: MediaFormat, key: String, fallback: Int): Int {
        return if (format.containsKey(key)) format.getInteger(key) else fallback
    }

    private fun appendPcm(
        dest: ByteArrayOutputStream,
        buf: ByteBuffer,
        info: MediaCodec.BufferInfo,
        encoding: Int,
    ) {
        val dup = buf.duplicate()
        dup.position(info.offset)
        dup.limit(info.offset + info.size)
        dup.order(ByteOrder.LITTLE_ENDIAN)
        if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
            val n = dup.remaining() / 4
            for (i in 0 until n) {
                val f = dup.float.coerceIn(-1f, 1f)
                val s = (f * 32767f).toInt()
                dest.write(s and 0xFF)
                dest.write((s shr 8) and 0xFF)
            }
        } else {
            val bytes = ByteArray(dup.remaining())
            dup.get(bytes)
            dest.write(bytes)
        }
    }

    private fun wavHeader(dataLen: Int, sampleRate: Int, channels: Int): ByteArray {
        val bits = 16
        val byteRate = sampleRate * channels * bits / 8
        val blockAlign = channels * bits / 8
        val bb = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        bb.put(byteArrayOf(0x52, 0x49, 0x46, 0x46)) // RIFF
        bb.putInt(36 + dataLen)
        bb.put(byteArrayOf(0x57, 0x41, 0x56, 0x45)) // WAVE
        bb.put(byteArrayOf(0x66, 0x6D, 0x74, 0x20)) // fmt
        bb.putInt(16)
        bb.putShort(1)
        bb.putShort(channels.toShort())
        bb.putInt(sampleRate)
        bb.putInt(byteRate)
        bb.putShort(blockAlign.toShort())
        bb.putShort(bits.toShort())
        bb.put(byteArrayOf(0x64, 0x61, 0x74, 0x61)) // data
        bb.putInt(dataLen)
        return bb.array()
    }

    override fun onDestroy() {
        stopPlayer()
        super.onDestroy()
    }
}
