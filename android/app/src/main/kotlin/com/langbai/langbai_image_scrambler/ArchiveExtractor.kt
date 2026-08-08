package com.langbai.imagescrambler

import android.content.ContentResolver
import android.net.Uri
import com.github.junrar.Archive
import net.lingala.zip4j.ZipFile
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import java.io.File
import java.io.InputStream
import java.util.UUID

internal class ArchiveExtractor(
    private val cacheDirectory: File,
    private val contentResolver: ContentResolver?,
) {
    companion object {
        private const val MAX_ENTRY_COUNT = 20_000
        private const val MAX_ENTRY_BYTES = 1024L * 1024L * 1024L
        private const val MAX_TOTAL_BYTES = 4L * 1024L * 1024L * 1024L
        private const val MAX_MEMORY_KIB = 512 * 1024
        private val supportedExtensions = setOf(
            "png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff", "txt",
        )
    }

    fun extractFromUri(uri: Uri, displayName: String, password: String?): Map<String, Any> {
        val resolver = contentResolver
            ?: throw ArchiveImportException("archive_read_failed", "压缩包读取器未初始化")
        val extension = displayName.substringAfterLast('.', "").lowercase()
        val archiveFile = File(
            cacheDirectory,
            "langbai-archive-source-${UUID.randomUUID()}.$extension",
        )
        try {
            resolver.openInputStream(uri)?.use { input ->
                archiveFile.outputStream().buffered().use { output -> input.copyTo(output) }
            } ?: throw ArchiveImportException("archive_read_failed", "压缩包无法读取")
            return extractFile(archiveFile, displayName, password)
        } finally {
            archiveFile.delete()
        }
    }

    fun extractFromPath(sourcePath: String, displayName: String, password: String?): Map<String, Any> {
        val file = File(sourcePath)
        if (!file.isFile) throw ArchiveImportException("archive_read_failed", "压缩包不存在")
        return extractFile(file, displayName, password)
    }

    private fun extractFile(file: File, displayName: String, password: String?): Map<String, Any> {
        val extension = displayName.substringAfterLast('.', "").lowercase()
        if (extension !in setOf("zip", "7z", "rar")) {
            throw ArchiveImportException("archive_unsupported", "仅支持 ZIP、7Z、RAR 压缩包")
        }
        val rootName = safeRootName(displayName.substringBeforeLast('.', displayName))
        val sessionRoot = File(cacheDirectory, "langbai-archive-${UUID.randomUUID()}")
        val outputRoot = File(sessionRoot, rootName)
        outputRoot.mkdirs()
        val state = ExtractionState(outputRoot)
        try {
            when (extension) {
                "zip" -> extractZip(file, password, state)
                "7z" -> extractSevenZip(file, password, state)
                "rar" -> extractRar(file, password, state)
            }
            return mapOf(
                "rootName" to rootName,
                "temporaryRoot" to sessionRoot.absolutePath,
                "skippedCount" to state.skippedCount,
                "items" to state.items,
            )
        } catch (error: ArchiveImportException) {
            sessionRoot.deleteRecursively()
            throw error
        } catch (error: Throwable) {
            sessionRoot.deleteRecursively()
            val message = error.message.orEmpty()
            val passwordFailure = message.contains("password", ignoreCase = true) ||
                message.contains("密码") ||
                message.contains("CRC", ignoreCase = true) ||
                message.contains("checksum", ignoreCase = true) ||
                message.contains("decrypt", ignoreCase = true)
            if (passwordFailure) {
                throw ArchiveImportException(
                    "archive_password",
                    "密码为空或不正确，请重新输入",
                    error,
                )
            }
            throw ArchiveImportException(
                "archive_extract_failed",
                if (message.isBlank()) "压缩包解压失败" else message,
                error,
            )
        }
    }

    private fun extractZip(file: File, password: String?, state: ExtractionState) {
        ZipFile(file, password.orEmpty().toCharArray()).use { archive ->
            val headers = archive.fileHeaders
            state.checkEntryCount(headers.size)
            for (header in headers) {
                if (header.isDirectory) continue
                val size = header.uncompressedSize
                if (!state.shouldExtract(header.fileName, size)) continue
                archive.getInputStream(header).use { input ->
                    state.write(header.fileName, size, input)
                }
            }
        }
    }

    private fun extractSevenZip(file: File, password: String?, state: ExtractionState) {
        try {
            val builder = SevenZFile.builder()
                .setFile(file)
                .setMaxMemoryLimitKiB(MAX_MEMORY_KIB)
            if (!password.isNullOrEmpty()) builder.setPassword(password)
            builder.get().use { archive ->
                var count = 0
                while (true) {
                    val entry = archive.nextEntry ?: break
                    count++
                    state.checkEntryCount(count)
                    if (entry.isDirectory) continue
                    val name = entry.name ?: run {
                        state.skippedCount++
                        continue
                    }
                    if (!state.shouldExtract(name, entry.size)) continue
                    archive.getInputStream(entry).use { input ->
                        state.write(name, entry.size, input)
                    }
                }
            }
        } catch (error: Throwable) {
            if (!password.isNullOrEmpty() && error.message.orEmpty().contains("no Header")) {
                throw ArchiveImportException(
                    "archive_password",
                    "密码为空或不正确，请重新输入",
                    error,
                )
            }
            throw error
        }
    }

    private fun extractRar(file: File, password: String?, state: ExtractionState) {
        Archive(file, password).use { archive ->
            var count = 0
            while (true) {
                val header = archive.nextFileHeader() ?: break
                count++
                state.checkEntryCount(count)
                if (header.isDirectory) continue
                val name = header.fileName
                val size = header.fullUnpackSize
                if (!state.shouldExtract(name, size)) continue
                try {
                    archive.getInputStream(header).use { input ->
                        state.write(name, size, input)
                    }
                } catch (error: Throwable) {
                    if (header.isEncrypted) {
                        throw ArchiveImportException(
                            "archive_password",
                            "密码为空或不正确，请重新输入",
                            error,
                        )
                    }
                    throw error
                }
            }
        }
    }

    private inner class ExtractionState(private val outputRoot: File) {
        val items = mutableListOf<Map<String, Any>>()
        var skippedCount = 0
        private var totalBytes = 0L

        fun checkEntryCount(count: Int) {
            if (count > MAX_ENTRY_COUNT) {
                throw ArchiveImportException("archive_limit", "压缩包文件数量超过 20000 个")
            }
        }

        fun shouldExtract(name: String, declaredSize: Long): Boolean {
            val extension = name.substringAfterLast('.', "").lowercase()
            if (extension !in supportedExtensions) {
                skippedCount++
                return false
            }
            if (declaredSize > MAX_ENTRY_BYTES) {
                throw ArchiveImportException("archive_limit", "单个文件解压后超过 1 GB")
            }
            return true
        }

        fun write(rawName: String, declaredSize: Long, input: InputStream) {
            val normalizedName = normalizedEntryName(rawName)
            val desired = safeDestination(outputRoot, normalizedName)
            val destination = uniqueFile(desired)
            destination.parentFile?.mkdirs()
            var written = 0L
            destination.outputStream().buffered().use { output ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (read == 0) continue
                    written += read
                    if (written > MAX_ENTRY_BYTES || totalBytes + written > MAX_TOTAL_BYTES) {
                        throw ArchiveImportException("archive_limit", "压缩包解压内容超过安全上限")
                    }
                    output.write(buffer, 0, read)
                }
            }
            if (declaredSize >= 0 && written != declaredSize) {
                destination.delete()
                throw ArchiveImportException("archive_corrupt", "压缩包内文件大小校验失败")
            }
            totalBytes += written
            val relativePath = destination.relativeTo(outputRoot).invariantSeparatorsPath
            val relativeDirectory = destination.parentFile
                ?.relativeTo(outputRoot)
                ?.invariantSeparatorsPath
                ?.takeUnless { it == "." }
                .orEmpty()
            items.add(
                mapOf(
                    "path" to destination.absolutePath,
                    "name" to destination.name,
                    "relativeDirectory" to relativeDirectory,
                    "relativePath" to relativePath,
                    "size" to written,
                    "kind" to if (destination.extension.equals("txt", true)) "text" else "image",
                ),
            )
        }
    }

    private fun normalizedEntryName(rawName: String): String {
        val normalized = rawName.replace('\\', '/').trimStart('/')
        val segments = normalized.split('/').filter { it.isNotBlank() && it != "." }
        if (segments.isEmpty() || segments.any { it == ".." }) {
            throw ArchiveImportException("archive_unsafe_path", "压缩包包含不安全路径")
        }
        return segments.joinToString("/") { segment ->
            segment.replace(Regex("[\\u0000-\\u001f]"), "_")
        }
    }

    private fun safeDestination(root: File, relativeName: String): File {
        val target = File(root, relativeName)
        val rootPath = root.canonicalFile.toPath()
        val targetPath = target.canonicalFile.toPath()
        if (!targetPath.startsWith(rootPath)) {
            throw ArchiveImportException("archive_unsafe_path", "压缩包包含越界路径")
        }
        return target
    }

    private fun uniqueFile(desired: File): File {
        if (!desired.exists()) return desired
        val extension = desired.extension.let { if (it.isEmpty()) "" else ".$it" }
        val base = desired.name.removeSuffix(extension)
        var index = 1
        while (true) {
            val candidate = File(desired.parentFile, "$base（$index）$extension")
            if (!candidate.exists()) return candidate
            index++
        }
    }

    private fun safeRootName(value: String): String {
        val cleaned = value.replace(Regex("[\\u0000-\\u001f/\\\\]"), "_").trim()
        return cleaned.ifBlank { "压缩包" }
    }
}

internal class ArchiveImportException(
    val code: String,
    override val message: String,
    cause: Throwable? = null,
) : Exception(message, cause)
