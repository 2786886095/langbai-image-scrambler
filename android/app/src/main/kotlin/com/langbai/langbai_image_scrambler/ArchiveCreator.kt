package com.langbai.imagescrambler

import org.apache.commons.compress.archivers.sevenz.SevenZOutputFile
import java.io.File

class ArchiveCreator(private val cacheDirectory: File) {
    fun create7z(
        outputPath: String,
        rawEntries: List<Map<String, Any?>>,
        password: String?,
    ): Map<String, Any> {
        val output = File(outputPath)
        output.parentFile?.mkdirs()
        val passwordChars = password?.takeIf { it.isNotEmpty() }?.toCharArray()
        try {
            SevenZOutputFile(output, passwordChars).use { archive ->
                for (raw in rawEntries) {
                    val sourcePath = raw["sourcePath"] as? String
                        ?: error("压缩项目缺少来源路径")
                    val source = File(sourcePath).canonicalFile
                    if (!source.isFile) error("压缩来源不存在：${source.name}")
                    val archivePath = safeArchivePath(raw["archivePath"] as? String ?: source.name)
                    val entry = archive.createArchiveEntry(source, archivePath)
                    archive.putArchiveEntry(entry)
                    source.inputStream().buffered().use { input ->
                        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (count > 0) archive.write(buffer, 0, count)
                        }
                    }
                    archive.closeArchiveEntry()
                }
                archive.finish()
            }
        } finally {
            passwordChars?.fill('\u0000')
        }
        if (!output.isFile || output.length() == 0L) error("7Z 输出为空")
        return mapOf("path" to output.absolutePath, "size" to output.length())
    }

    private fun safeArchivePath(value: String): String {
        val segments = value.replace('\\', '/').split('/').filter { it.isNotBlank() }
        if (segments.isEmpty()) error("压缩项目名称为空")
        val safe = segments.map { segment ->
            if (segment == "." || segment == "..") error("压缩项目路径无效")
            segment.replace(Regex("[<>:\"|?*\\u0000-\\u001f]"), "_")
        }.joinToString("/")
        val probe = File(cacheDirectory, safe).canonicalFile
        val root = cacheDirectory.canonicalFile
        if (probe.path != root.path && !probe.path.startsWith(root.path + File.separator)) {
            error("压缩项目路径越界")
        }
        return safe
    }
}
