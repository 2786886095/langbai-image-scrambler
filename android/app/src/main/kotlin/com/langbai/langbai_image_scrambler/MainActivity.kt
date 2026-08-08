package com.langbai.imagescrambler

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.langbai.imagescrambler/saf"
        private const val REQUEST_TREE = 9401
        private const val REQUEST_SAVE = 9402
    }

    private var pendingTreeResult: MethodChannel.Result? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveSourcePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handleCall(call, result) }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickTree" -> pickTree(result)
            "listTree" -> runInBackground(result) {
                val treeUri = Uri.parse(call.argument<String>("treeUri")!!)
                mapOf("items" to listTree(treeUri))
            }
            "copyUriToCache" -> runInBackground(result) {
                copyUriToCache(
                    Uri.parse(call.argument<String>("uri")!!),
                    call.argument<String>("name") ?: "image",
                )
            }
            "createUniqueDirectory" -> runInBackground(result) {
                createUniqueDirectory(
                    Uri.parse(call.argument<String>("treeUri")!!),
                    call.argument<String>("desiredName") ?: "导出",
                )
            }
            "writeFileToTree" -> runInBackground(result) {
                writeFileToTree(
                    Uri.parse(call.argument<String>("treeUri")!!),
                    call.argument<String>("relativeFolder") ?: "",
                    call.argument<String>("fileName") ?: "image.png",
                    call.argument<String>("sourcePath")!!,
                    call.argument<String>("mimeType") ?: "image/png",
                )
            }
            "deleteDocumentIfHash" -> runInBackground(result) {
                deleteDocumentIfHash(
                    Uri.parse(call.argument<String>("uri")!!),
                    call.argument<String>("sha256") ?: "",
                )
            }
            "deleteEmptyDocument" -> runInBackground(result) {
                deleteEmptyDocument(Uri.parse(call.argument<String>("uri")!!))
            }
            "saveDocument" -> saveDocument(call, result)
            else -> result.notImplemented()
        }
    }

    private fun pickTree(result: MethodChannel.Result) {
        if (pendingTreeResult != null) {
            result.error("busy", "已有资料夹选择视窗正在显示", null)
            return
        }
        pendingTreeResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
        }
        startActivityForResult(intent, REQUEST_TREE)
    }

    private fun saveDocument(call: MethodCall, result: MethodChannel.Result) {
        if (pendingSaveResult != null) {
            result.error("busy", "已有储存视窗正在显示", null)
            return
        }
        pendingSaveResult = result
        pendingSaveSourcePath = call.argument<String>("sourcePath")
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
            type = call.argument<String>("mimeType") ?: "image/png"
            putExtra(Intent.EXTRA_TITLE, call.argument<String>("suggestedName") ?: "image.png")
        }
        startActivityForResult(intent, REQUEST_SAVE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_TREE -> {
                val result = pendingTreeResult
                pendingTreeResult = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result?.success(null)
                    return
                }
                val flags = data.flags and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                try {
                    contentResolver.takePersistableUriPermission(uri, flags)
                } catch (_: SecurityException) {
                    // Some document providers grant session access only; continue with that grant.
                }
                result?.success(mapOf("uri" to uri.toString(), "name" to queryName(uri)))
            }
            REQUEST_SAVE -> {
                val result = pendingSaveResult
                val sourcePath = pendingSaveSourcePath
                pendingSaveResult = null
                pendingSaveSourcePath = null
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null || sourcePath == null) {
                    result?.success(null)
                    return
                }
                thread {
                    try {
                        val flags = data.flags and
                            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        try {
                            contentResolver.takePersistableUriPermission(uri, flags)
                        } catch (_: SecurityException) {
                            // The current grant remains usable for this app session.
                        }
                        contentResolver.openOutputStream(uri, "wt")!!.use { output ->
                            File(sourcePath).inputStream().use { input -> input.copyTo(output) }
                        }
                        runOnUiThread {
                            result?.success(
                                mapOf(
                                    "uri" to uri.toString(),
                                    "name" to queryDisplayName(uri),
                                ),
                            )
                        }
                    } catch (error: Throwable) {
                        runOnUiThread { result?.error("save_failed", error.message, null) }
                    }
                }
            }
        }
    }

    private fun listTree(treeUri: Uri): List<Map<String, Any>> {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val output = mutableListOf<Map<String, Any>>()
        walkChildren(treeUri, rootId, "", output)
        return output
    }

    private fun walkChildren(
        treeUri: Uri,
        parentDocumentId: String,
        relativeDirectory: String,
        output: MutableList<Map<String, Any>>,
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            while (cursor.moveToNext()) {
                val id = cursor.getString(idIndex)
                val name = cursor.getString(nameIndex) ?: "image"
                val mime = cursor.getString(mimeIndex) ?: ""
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    val childRelative = if (relativeDirectory.isEmpty()) name else "$relativeDirectory/$name"
                    walkChildren(treeUri, id, childRelative, output)
                } else if (mime.startsWith("image/") || isSupportedName(name)) {
                    val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                    output.add(
                        mapOf(
                            "uri" to uri.toString(),
                            "name" to name,
                            "relativeDirectory" to relativeDirectory,
                            "size" to if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) cursor.getLong(sizeIndex) else 0L,
                        ),
                    )
                }
            }
        }
    }

    private fun copyUriToCache(uri: Uri, name: String): String {
        val safeName = name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
        val target = File(cacheDir, "langbai-import-${UUID.randomUUID()}-$safeName")
        contentResolver.openInputStream(uri)!!.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        return target.absolutePath
    }

    private fun createUniqueDirectory(treeUri: Uri, desiredName: String): Map<String, String> {
        val parentId = DocumentsContract.getTreeDocumentId(treeUri)
        var actualName = desiredName
        var index = 1
        while (findChild(treeUri, parentId, actualName) != null) {
            actualName = "$desiredName（$index）"
            index++
        }
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, parentId)
        val created = DocumentsContract.createDocument(
            contentResolver,
            parentUri,
            DocumentsContract.Document.MIME_TYPE_DIR,
            actualName,
        ) ?: error("无法建立资料夹：$actualName")
        return mapOf("name" to actualName, "uri" to created.toString())
    }

    private fun writeFileToTree(
        treeUri: Uri,
        relativeFolder: String,
        fileName: String,
        sourcePath: String,
        mimeType: String,
    ): Map<String, Any> {
        var parentId = DocumentsContract.getTreeDocumentId(treeUri)
        val createdDirectories = mutableListOf<String>()
        for (segment in relativeFolder.split('/').filter { it.isNotBlank() }) {
            val existing = findChild(treeUri, parentId, segment)
            if (existing != null) {
                parentId = existing.first
            } else {
                val created = DocumentsContract.createDocument(
                    contentResolver,
                    DocumentsContract.buildDocumentUriUsingTree(treeUri, parentId),
                    DocumentsContract.Document.MIME_TYPE_DIR,
                    segment,
                ) ?: error("无法建立资料夹：$segment")
                parentId = DocumentsContract.getDocumentId(created)
                createdDirectories.add(created.toString())
            }
        }

        val actualName = uniqueChildName(treeUri, parentId, fileName)
        val outputUri = DocumentsContract.createDocument(
            contentResolver,
            DocumentsContract.buildDocumentUriUsingTree(treeUri, parentId),
            mimeType,
            actualName,
        ) ?: error("无法建立输出文件：$actualName")
        contentResolver.openOutputStream(outputUri, "wt")!!.use { output ->
            File(sourcePath).inputStream().use { input -> input.copyTo(output) }
        }
        return mapOf(
            "uri" to outputUri.toString(),
            "name" to actualName,
            "createdDirectories" to createdDirectories,
        )
    }

    private fun uniqueChildName(treeUri: Uri, parentId: String, desiredName: String): String {
        if (findChild(treeUri, parentId, desiredName) == null) return desiredName
        val dot = desiredName.lastIndexOf('.')
        val hasExtension = dot > 0
        val base = if (hasExtension) desiredName.substring(0, dot) else desiredName
        val extension = if (hasExtension) desiredName.substring(dot) else ""
        var index = 1
        while (true) {
            val candidate = "$base（$index）$extension"
            if (findChild(treeUri, parentId, candidate) == null) return candidate
            index++
        }
    }

    private fun deleteDocumentIfHash(uri: Uri, expectedHash: String): String {
        return try {
            val actualHash = contentResolver.openInputStream(uri)?.use { input ->
                val digest = MessageDigest.getInstance("SHA-256")
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (read > 0) digest.update(buffer, 0, read)
                }
                digest.digest().joinToString("") { "%02x".format(it) }
            } ?: return "missing"
            if (!actualHash.equals(expectedHash, ignoreCase = true)) return "modified"
            if (DocumentsContract.deleteDocument(contentResolver, uri)) "deleted" else "failed"
        } catch (_: FileNotFoundException) {
            "missing"
        }
    }

    private fun deleteEmptyDocument(uri: Uri): Boolean {
        val projection = arrayOf(DocumentsContract.Document.COLUMN_MIME_TYPE)
        val mime = contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: return false
        if (mime != DocumentsContract.Document.MIME_TYPE_DIR) return false
        val documentId = DocumentsContract.getDocumentId(uri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(uri, documentId)
        val hasChildren = contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
            null,
            null,
            null,
        )?.use { it.moveToFirst() } ?: false
        return !hasChildren && DocumentsContract.deleteDocument(contentResolver, uri)
    }

    private fun findChild(treeUri: Uri, parentId: String, name: String): Pair<String, String>? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                if (cursor.getString(nameIndex) == name) {
                    return cursor.getString(idIndex) to cursor.getString(mimeIndex)
                }
            }
        }
        return null
    }

    private fun queryName(treeUri: Uri): String {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        contentResolver.query(
            documentUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0) ?: "图片"
        }
        return "图片"
    }

    private fun queryDisplayName(uri: Uri): String {
        contentResolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0) ?: "文件"
        }
        return "文件"
    }

    private fun isSupportedName(name: String): Boolean {
        val extension = name.substringAfterLast('.', "").lowercase()
        return extension in setOf("png", "jpg", "jpeg", "webp", "bmp", "tif", "tiff", "txt")
    }

    private fun runInBackground(result: MethodChannel.Result, block: () -> Any?) {
        thread {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (error: Throwable) {
                runOnUiThread { result.error("saf_error", error.message, null) }
            }
        }
    }
}
