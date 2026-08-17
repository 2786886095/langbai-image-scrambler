package com.langbai.imagescrambler

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.langbai.imagescrambler/saf"
        private const val REQUEST_TREE = 9401
        private const val REQUEST_SAVE = 9402
        private const val REQUEST_INSTALL_PERMISSION = 9403
    }

    private var pendingTreeResult: MethodChannel.Result? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveSourcePath: String? = null
    private var pendingInstallResult: MethodChannel.Result? = null
    private var pendingInstallPath: String? = null
    private var platformChannel: MethodChannel? = null
    private val pendingShares = ArrayDeque<Map<String, Any>>()
    private val archiveExtractor by lazy { ArchiveExtractor(cacheDir, contentResolver) }
    private val archiveCreator by lazy { ArchiveCreator(cacheDir) }
    private val videoFfmpeg by lazy { VideoFfmpegBridge(this) }
    private val videoLinkBridge by lazy { VideoLinkBridge(applicationContext) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        collectSharedIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        platformChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result -> handleCall(call, result) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (collectSharedIntent(intent)) {
            platformChannel?.invokeMethod("sharedIntentAvailable", null)
        }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePendingShare" -> result.success(pendingShares.pollFirst())
            "pickTree" -> pickTree(result)
            "listTree" -> runInBackground(result) {
                val treeUri = Uri.parse(call.argument<String>("treeUri")!!)
                mapOf("items" to listDirectory(treeUri))
            }
            "listSharedDirectory" -> runInBackground(result) {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                mapOf(
                    "name" to queryDisplayName(uri),
                    "items" to listDirectory(uri),
                )
            }
            "extractArchive" -> runInBackground(result) {
                val name = call.argument<String>("name") ?: "压缩包.zip"
                val password = call.argument<String>("password")?.takeIf { it.isNotEmpty() }
                val sourcePath = call.argument<String>("sourcePath")
                if (sourcePath != null) {
                    archiveExtractor.extractFromPath(sourcePath, name, password)
                } else {
                    archiveExtractor.extractFromUri(
                        Uri.parse(call.argument<String>("uri")!!),
                        name,
                        password,
                    )
                }
            }
            "createArchive" -> runInBackground(result) {
                val format = call.argument<String>("format") ?: "7z"
                if (format != "7z") error("Android 原生压缩仅处理 7Z")
                @Suppress("UNCHECKED_CAST")
                val entries = call.argument<List<Map<String, Any?>>>("entries") ?: emptyList()
                archiveCreator.create7z(
                    call.argument<String>("outputPath")!!,
                    entries,
                    call.argument<String>("password"),
                )
            }
            "runFfmpeg" -> runInBackground(result) {
                val arguments = call.argument<List<String>>("arguments") ?: emptyList()
                videoFfmpeg.run(arguments)
            }
            "resolveVideoLink" -> runInBackground(result) {
                videoLinkBridge.resolveAndDownload(
                    call.argument<String>("url")?.trim().orEmpty(),
                )
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
            "deleteEmptyFile" -> runInBackground(result) {
                deleteEmptyFile(Uri.parse(call.argument<String>("uri")!!))
            }
            "writeFileToUri" -> runInBackground(result) {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                writeFileToUri(uri, call.argument<String>("sourcePath")!!)
                mapOf("uri" to uri.toString(), "name" to queryDisplayName(uri))
            }
            "installApk" -> installApk(call, result)
            "openOutputLocation" -> {
                try {
                    openOutputLocation(
                        Uri.parse(call.argument<String>("uri")!!),
                        call.argument<Boolean>("isDirectory") ?: false,
                        call.argument<String>("fallbackUri")?.let(Uri::parse),
                    )
                    result.success(null)
                } catch (error: Throwable) {
                    result.error("open_output_failed", error.message, null)
                }
            }
            "pickSaveDocument" -> saveDocument(call, result)
            "saveDocument" -> saveDocument(call, result)
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun collectSharedIntent(source: Intent?): Boolean {
        val intent = source ?: return false
        if (intent.action !in setOf(Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE, Intent.ACTION_VIEW)) {
            return false
        }
        val uris = linkedSetOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::addAll)
            Intent.ACTION_VIEW -> intent.data?.let(uris::add)
        }
        val clipData = intent.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let(uris::add)
            }
        }
        if (uris.isEmpty()) return false

        val permissionFlags = intent.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        val items = uris.mapNotNull { uri ->
            if (permissionFlags != 0) {
                try {
                    contentResolver.takePersistableUriPermission(uri, permissionFlags)
                } catch (_: SecurityException) {
                    // Most share providers grant temporary access for this activity task.
                }
            }
            incomingItem(uri, intent.type)
        }
        if (items.isEmpty()) return false
        pendingShares.addLast(
            mapOf(
                "id" to UUID.randomUUID().toString(),
                "items" to items,
            ),
        )
        return true
    }

    private fun incomingItem(uri: Uri, fallbackMime: String?): Map<String, Any>? {
        var name: String? = null
        var mime: String? = null
        var size = 0L
        try {
            contentResolver.query(
                uri,
                arrayOf(
                    OpenableColumns.DISPLAY_NAME,
                    OpenableColumns.SIZE,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                    if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex)
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
                    if (mimeIndex >= 0 && !cursor.isNull(mimeIndex)) mime = cursor.getString(mimeIndex)
                }
            }
        } catch (_: Throwable) {
            // Fall back to URI metadata below.
        }
        val file = if (uri.scheme == "file") uri.path?.let(::File) else null
        name = name ?: file?.name ?: uri.lastPathSegment?.substringAfterLast('/') ?: "分享文件"
        mime = mime ?: contentResolver.getType(uri) ?: fallbackMime ?: "application/octet-stream"
        val isDirectory = mime == DocumentsContract.Document.MIME_TYPE_DIR ||
            mime == "resource/folder" ||
            mime == "inode/directory" ||
            file?.isDirectory == true
        if (size == 0L && file?.isFile == true) size = file.length()
        val resolvedName = name ?: "分享文件"
        val resolvedMime = mime ?: "application/octet-stream"
        return mapOf(
            "uri" to uri.toString(),
            "name" to resolvedName,
            "mimeType" to resolvedMime,
            "size" to size,
            "isDirectory" to isDirectory,
        )
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
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    result?.success(null)
                    return
                }
                val flags = data.flags and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                try {
                    contentResolver.takePersistableUriPermission(uri, flags)
                } catch (_: SecurityException) {
                    // The current grant remains usable for this app session.
                }
                if (sourcePath == null) {
                    result?.success(mapOf("uri" to uri.toString(), "name" to queryDisplayName(uri)))
                    return
                }
                thread {
                    try {
                        writeFileToUri(uri, sourcePath)
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
            REQUEST_INSTALL_PERMISSION -> {
                val result = pendingInstallResult
                val installPath = pendingInstallPath
                pendingInstallResult = null
                pendingInstallPath = null
                if (
                    installPath != null &&
                    (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        packageManager.canRequestPackageInstalls())
                ) {
                    try {
                        launchApkInstaller(File(installPath))
                        result?.success(true)
                    } catch (error: Throwable) {
                        result?.error("install_failed", error.message, null)
                    }
                } else {
                    result?.success(false)
                }
            }
        }
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val packageFile = File(call.argument<String>("path") ?: "")
        if (!packageFile.exists() || packageFile.length() == 0L) {
            result.error("missing_apk", "下载的 APK 不存在", null)
            return
        }
        if (pendingInstallResult != null) {
            result.error("busy", "已有安装请求正在处理", null)
            return
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            pendingInstallResult = result
            pendingInstallPath = packageFile.absolutePath
            try {
                startActivityForResult(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ),
                    REQUEST_INSTALL_PERMISSION,
                )
            } catch (error: Throwable) {
                pendingInstallResult = null
                pendingInstallPath = null
                result.error("install_permission_failed", error.message, null)
            }
            return
        }
        try {
            launchApkInstaller(packageFile)
            result.success(true)
        } catch (error: Throwable) {
            result.error("install_failed", error.message, null)
        }
    }

    private fun launchApkInstaller(packageFile: File) {
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            packageFile,
        )
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }

    private fun writeFileToUri(uri: Uri, sourcePath: String) {
        contentResolver.openOutputStream(uri, "wt")!!.use { output ->
            File(sourcePath).inputStream().use { input -> input.copyTo(output) }
        }
    }

    private fun listDirectory(rootUri: Uri): List<Map<String, Any>> {
        val isTree = DocumentsContract.isTreeUri(rootUri)
        val rootId = if (isTree) {
            DocumentsContract.getTreeDocumentId(rootUri)
        } else {
            DocumentsContract.getDocumentId(rootUri)
        }
        val output = mutableListOf<Map<String, Any>>()
        walkChildren(rootUri, rootId, "", output, isTree)
        return output
    }

    private fun walkChildren(
        rootUri: Uri,
        parentDocumentId: String,
        relativeDirectory: String,
        output: MutableList<Map<String, Any>>,
        isTree: Boolean,
    ) {
        val childrenUri = if (isTree) {
            DocumentsContract.buildChildDocumentsUriUsingTree(rootUri, parentDocumentId)
        } else {
            DocumentsContract.buildChildDocumentsUri(rootUri.authority!!, parentDocumentId)
        }
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
                    walkChildren(rootUri, id, childRelative, output, isTree)
                } else if (mime.startsWith("image/") || isSupportedName(name)) {
                    val uri = if (isTree) {
                        DocumentsContract.buildDocumentUriUsingTree(rootUri, id)
                    } else {
                        DocumentsContract.buildDocumentUri(rootUri.authority!!, id)
                    }
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

    private fun deleteEmptyFile(uri: Uri): Boolean {
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            OpenableColumns.SIZE,
        )
        val values = contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val mime = cursor.getString(0)
            val size = if (cursor.isNull(1)) null else cursor.getLong(1)
            mime to size
        } ?: return false
        if (values.first == DocumentsContract.Document.MIME_TYPE_DIR || values.second != 0L) {
            return false
        }
        return DocumentsContract.deleteDocument(contentResolver, uri)
    }

    private fun openOutputLocation(uri: Uri, isDirectory: Boolean, fallbackUri: Uri?) {
        val candidates = linkedMapOf<String, Intent>()
        if (isDirectory) {
            val documentUri = try {
                DocumentsContract.buildDocumentUriUsingTree(
                    uri,
                    DocumentsContract.getTreeDocumentId(uri),
                )
            } catch (_: Throwable) {
                uri
            }
            collectViewCandidates(
                candidates,
                documentUri,
                listOf(DocumentsContract.Document.MIME_TYPE_DIR, "resource/folder", "*/*"),
                grantWrite = true,
            )
            if (documentUri != uri) {
                collectViewCandidates(
                    candidates,
                    uri,
                    listOf(DocumentsContract.Document.MIME_TYPE_DIR, "resource/folder", "*/*"),
                    grantWrite = true,
                )
            }
        } else {
            collectViewCandidates(
                candidates,
                uri,
                listOf(contentResolver.getType(uri) ?: "*/*", "*/*"),
            )
        }

        if (candidates.isEmpty() && fallbackUri != null) {
            collectViewCandidates(
                candidates,
                fallbackUri,
                listOf(contentResolver.getType(fallbackUri) ?: "*/*", "*/*"),
            )
        }
        if (candidates.isEmpty()) throw ActivityNotFoundException("没有可打开输出位置的应用")

        val choices = candidates.values.toList()
        val chooser = Intent.createChooser(choices.first(), "选择应用打开输出位置").apply {
            putExtra("android.intent.extra.AUTO_LAUNCH_SINGLE_CHOICE", false)
            if (choices.size > 1) {
                putExtra(Intent.EXTRA_INITIAL_INTENTS, choices.drop(1).toTypedArray())
            }
        }
        startActivity(chooser)
    }

    private fun collectViewCandidates(
        candidates: MutableMap<String, Intent>,
        uri: Uri,
        mimeTypes: List<String>,
        grantWrite: Boolean = false,
    ) {
        val grantFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION or
            if (grantWrite) Intent.FLAG_GRANT_WRITE_URI_PERMISSION else 0
        for (mimeType in mimeTypes.distinct()) {
            val implicitIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(grantFlags)
            }
            for (match in packageManager.queryIntentActivities(implicitIntent, 0)) {
                val activityInfo = match.activityInfo ?: continue
                val key = "${activityInfo.packageName}/${activityInfo.name}"
                if (candidates.containsKey(key)) continue
                candidates[key] = Intent(implicitIntent).apply {
                    setClassName(activityInfo.packageName, activityInfo.name)
                }
                grantUriPermission(activityInfo.packageName, uri, grantFlags)
            }
        }
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
            } catch (error: ArchiveImportException) {
                runOnUiThread { result.error(error.code, error.message, null) }
            } catch (error: Throwable) {
                runOnUiThread { result.error("saf_error", error.message, null) }
            }
        }
    }
}
