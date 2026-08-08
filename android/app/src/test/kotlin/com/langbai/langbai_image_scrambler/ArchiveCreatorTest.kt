package com.langbai.imagescrambler

import org.apache.commons.compress.archivers.sevenz.SevenZFile
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.File
import java.nio.file.Files

class ArchiveCreatorTest {
    @Test
    fun createsEncrypted7zWithExactPathAndBytes() {
        val root = Files.createTempDirectory("langbai-creator-test").toFile()
        try {
            val input = File(root, "input.png").apply { writeBytes(byteArrayOf(0, 1, 2, 3, 255.toByte())) }
            val output = File(root, "encrypted.7z")
            ArchiveCreator(root).create7z(
                output.absolutePath,
                listOf(mapOf("sourcePath" to input.absolutePath, "archivePath" to "原目录/图片.png")),
                "langbai-test",
            )

            assertThrows(Exception::class.java) {
                SevenZFile.builder().setFile(output).get().use { archive ->
                    val entry = archive.nextEntry
                    archive.read(ByteArray(entry.size.toInt()))
                }
            }
            SevenZFile.builder().setFile(output).setPassword("langbai-test").get().use { archive ->
                val entry = archive.nextEntry
                assertEquals("原目录/图片.png", entry.name)
                val restored = ByteArray(entry.size.toInt())
                var offset = 0
                while (offset < restored.size) {
                    val count = archive.read(restored, offset, restored.size - offset)
                    if (count < 0) break
                    offset += count
                }
                assertEquals(restored.size, offset)
                assertArrayEquals(input.readBytes(), restored)
            }
        } finally {
            root.deleteRecursively()
        }
    }
}
