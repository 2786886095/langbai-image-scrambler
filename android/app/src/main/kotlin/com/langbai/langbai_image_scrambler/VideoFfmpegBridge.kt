package com.langbai.imagescrambler

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import java.io.File

internal class VideoFfmpegBridge(private val context: Context) {
    fun run(arguments: List<String>): Map<String, Any> {
        FFmpeg.getInstance().init(context.applicationContext)
        val binary = File(context.applicationInfo.nativeLibraryDir, "libffmpeg.so")
        require(binary.isFile) { "内置 FFmpeg 不可用" }
        val command = buildList {
            add(binary.absolutePath)
            addAll(arguments)
        }
        val process = ProcessBuilder(command).apply {
            redirectErrorStream(true)
            environment()["TMPDIR"] = context.cacheDir.absolutePath
            environment()["LD_LIBRARY_PATH"] = listOf(
                File(context.noBackupFilesDir, "youtubedl-android/packages/ffmpeg/usr/lib").absolutePath,
                context.applicationInfo.nativeLibraryDir,
            ).joinToString(":")
        }.start()
        val output = process.inputStream.bufferedReader().use { it.readText() }
        return mapOf("exitCode" to process.waitFor(), "output" to output)
    }
}
