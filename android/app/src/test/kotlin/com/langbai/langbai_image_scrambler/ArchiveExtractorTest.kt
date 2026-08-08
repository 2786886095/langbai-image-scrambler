package com.langbai.imagescrambler

import net.lingala.zip4j.ZipFile
import net.lingala.zip4j.model.ZipParameters
import net.lingala.zip4j.model.enums.AesKeyStrength
import net.lingala.zip4j.model.enums.CompressionMethod
import net.lingala.zip4j.model.enums.EncryptionMethod
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.charset.Charset
import java.nio.file.Files

class ArchiveExtractorTest {
    private lateinit var cache: File
    private lateinit var extractor: ArchiveExtractor

    @Before
    fun setUp() {
        cache = Files.createTempDirectory("langbai-archive-test-").toFile()
        extractor = ArchiveExtractor(cache, null)
    }

    @After
    fun tearDown() {
        cache.deleteRecursively()
    }

    @Test
    fun encryptedZipPreservesChineseTreeAndFiltersUnsupportedFiles() {
        val archive = File(cache, "混合图包.zip")
        val image = File(cache, "画面.png").apply { writeBytes("pixels".toByteArray()) }
        val novel = File(cache, "小说.txt").apply { writeBytes("bytes".toByteArray()) }
        val ignored = File(cache, "说明.pdf").apply { writeBytes("pdf".toByteArray()) }
        ZipFile(archive, "密码123".toCharArray()).use { zip ->
            zip.addFile(image, encryptedParameters("章节一/画面.png"))
            zip.addFile(novel, encryptedParameters("章节一/小说.txt"))
            zip.addFile(ignored, encryptedParameters("说明.pdf"))
        }

        val result = extractor.extractFromPath(archive.path, archive.name, "密码123")
        val items = result.items()

        assertEquals("混合图包", result["rootName"])
        assertEquals(2, items.size)
        assertEquals(1, result["skippedCount"])
        assertEquals(setOf("章节一/画面.png", "章节一/小说.txt"), items.relativePaths())
        assertEquals(setOf("image", "text"), items.map { it["kind"] }.toSet())
    }

    @Test
    fun encryptedZipRejectsWrongPassword() {
        val archive = File(cache, "protected.zip")
        val novel = File(cache, "novel.txt").apply { writeText("content") }
        ZipFile(archive, "correct".toCharArray()).use { zip ->
            zip.addFile(novel, encryptedParameters("novel.txt"))
        }

        expectPasswordError {
            extractor.extractFromPath(archive.path, archive.name, "wrong")
        }
    }

    @Test
    fun legacyGbkZipNamesAreRecoveredWithoutMojibake() {
        val archive = File(cache, "旧版中文.zip")
        val novel = File(cache, "source.txt").apply { writeText("正文") }
        ZipFile(archive).use { zip ->
            zip.charset = Charset.forName("GB18030")
            zip.addFile(
                novel,
                ZipParameters().apply {
                    fileNameInZip = "本章/小说（1）.txt"
                    compressionMethod = CompressionMethod.DEFLATE
                },
            )
        }

        val result = extractor.extractFromPath(archive.path, archive.name, null)

        assertEquals(setOf("本章/小说（1）.txt"), result.items().relativePaths())
    }

    @Test
    fun encryptedSevenZipExtractsImageAndTextWithPassword() {
        val archive = resourceFile("encrypted-mixed.7z")
        val result = extractor.extractFromPath(archive.path, "mixed.7z", "langbai-test")
        val items = result.items()

        assertEquals(2, items.size)
        assertEquals(1, result["skippedCount"])
        assertEquals(
            setOf("chapter-1/image.png", "chapter-1/novel.txt"),
            items.relativePaths(),
        )
    }

    @Test
    fun encryptedSevenZipRejectsWrongPassword() {
        val archive = resourceFile("encrypted-mixed.7z")
        expectPasswordError {
            extractor.extractFromPath(archive.path, archive.name, "wrong")
        }
    }

    @Test
    fun encryptedRar5ExtractsTextWithPassword() {
        val archive = resourceFile("rar5-password-junrar.rar")
        val result = extractor.extractFromPath(archive.path, "novel.rar", "junrar")
        val items = result.items()

        assertEquals(1, items.size)
        assertEquals("file1.txt", items.single()["relativePath"])
        assertEquals("text", items.single()["kind"])
        assertEquals(6L, items.single()["size"])
    }

    @Test
    fun encryptedRar5RejectsWrongPassword() {
        val archive = resourceFile("rar5-password-junrar.rar")
        expectPasswordError {
            extractor.extractFromPath(archive.path, archive.name, "wrong")
        }
    }

    private fun encryptedParameters(name: String) = ZipParameters().apply {
        fileNameInZip = name
        compressionMethod = CompressionMethod.DEFLATE
        isEncryptFiles = true
        encryptionMethod = EncryptionMethod.AES
        aesKeyStrength = AesKeyStrength.KEY_STRENGTH_256
    }

    private fun resourceFile(name: String): File {
        val source = checkNotNull(javaClass.getResourceAsStream("/archives/$name"))
        val destination = File(cache, name)
        source.use { input -> destination.outputStream().use(input::copyTo) }
        assertTrue(destination.isFile)
        return destination
    }

    private fun expectPasswordError(block: () -> Unit) {
        try {
            block()
            fail("Expected password failure")
        } catch (error: ArchiveImportException) {
            assertEquals(
                "message=${error.message}; cause=${error.cause?.javaClass?.name}:${error.cause?.message}",
                "archive_password",
                error.code,
            )
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun Map<String, Any>.items(): List<Map<String, Any>> =
        this["items"] as List<Map<String, Any>>

    private fun List<Map<String, Any>>.relativePaths(): Set<Any?> =
        map { it["relativePath"] }.toSet()
}
