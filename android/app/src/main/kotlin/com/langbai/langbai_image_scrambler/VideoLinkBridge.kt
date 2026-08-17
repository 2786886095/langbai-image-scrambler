package com.langbai.imagescrambler

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.File
import java.util.UUID

/** One-click mobile resolver adapted from the Langbai Resolver project. */
class VideoLinkBridge(private val context: Context) {
    @Synchronized
    private fun ensureEngine() {
        if (engineReady) return
        YoutubeDL.getInstance().init(context.applicationContext)
        FFmpeg.getInstance().init(context.applicationContext)
        engineReady = true
    }

    fun resolveAndDownload(url: String, netscapeCookies: String = ""): Map<String, Any> {
        require(url.startsWith("http://") || url.startsWith("https://")) {
            "请输入有效的视频链接"
        }
        ensureEngine()
        val processId = "langbai-video-${UUID.randomUUID()}"
        val directory = File(context.cacheDir, "resolved-video/$processId")
        require(directory.mkdirs() || directory.isDirectory) { "无法创建视频下载缓存" }
        val template = File(directory, "%(title).120B.%(ext)s").absolutePath
        val cookieFile = File(directory, "cookies.txt")
        if (netscapeCookies.isNotBlank()) cookieFile.writeText(netscapeCookies)
        val request = YoutubeDLRequest(url)
            .addOption("--no-playlist")
            .addOption("--no-mtime")
            .addOption("--newline")
            .addOption("--concurrent-fragments", "4")
            .addOption("--retries", "4")
            .addOption("--socket-timeout", "30")
            .addOption("--max-filesize", MAX_VIDEO_BYTES.toString())
            .addOption("-f", "bestvideo*+bestaudio/best")
            .addOption("--merge-output-format", "mp4")
            .also {
                if (cookieFile.isFile) it.addOption("--cookies", cookieFile.absolutePath)
            }
            .addOption("-o", template)
        try {
            YoutubeDL.getInstance().execute(request, processId) { _, _, _ -> }
        } finally {
            cookieFile.delete()
        }
        val output = directory.walkTopDown()
            .filter {
                it.isFile && it.length() > 0L &&
                    it.extension.lowercase() in VIDEO_EXTENSIONS
            }
            .maxByOrNull(File::lastModified)
            ?: error("解析完成但没有找到可处理的视频文件")
        require(output.length() <= MAX_VIDEO_BYTES) { "解析视频超过 8 GB 安全上限" }
        return mapOf(
            "path" to output.absolutePath,
            "name" to output.name,
            "size" to output.length(),
        )
    }

    companion object {
        @Volatile
        private var engineReady = false
        private const val MAX_VIDEO_BYTES = 8L * 1024L * 1024L * 1024L
        private val VIDEO_EXTENSIONS = setOf("mp4", "mkv", "webm", "mov", "m4v", "avi")
    }
}
