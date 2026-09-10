package com.eekashaenuga.drivetracker

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ATTACHMENTS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "managedRoot" -> {
                    val root = File(filesDir, "drive_tracker")
                    root.mkdirs()
                    result.success(root.absolutePath)
                }
                "pickAttachment" -> pickAttachment(result)
                "openAttachment" -> {
                    val path = call.argument<String>("path")
                    val mimeType = call.argument<String>("mimeType")
                    if (path == null) {
                        result.error("missing_path", "Attachment path is required.", null)
                    } else {
                        openAttachment(path, mimeType, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Android API, but still compatible with FlutterActivity.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_ATTACHMENT_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingPickResult ?: return
        pendingPickResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }

        try {
            val info = copyPickedUriToCache(uri)
            result.success(info)
        } catch (error: Exception) {
            result.error("pick_failed", error.message ?: "Could not read selected file.", null)
        }
    }

    private fun pickAttachment(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("pick_in_progress", "Another file picker is already open.", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/pdf", "image/jpeg", "image/png")
            )
        }
        try {
            pendingPickResult = result
            startActivityForResult(intent, PICK_ATTACHMENT_REQUEST)
        } catch (error: ActivityNotFoundException) {
            pendingPickResult = null
            result.error("picker_unavailable", "No file picker is available.", null)
        }
    }

    private fun copyPickedUriToCache(uri: Uri): Map<String, Any?> {
        val displayName = displayNameFor(uri) ?: "Attachment"
        val mimeType = contentResolver.getType(uri)
        val extension = extensionFor(displayName, mimeType)
        val tempDir = File(cacheDir, "picked_attachments")
        tempDir.mkdirs()
        val tempFile = File.createTempFile("picked_", ".$extension", tempDir)
        contentResolver.openInputStream(uri).use { input ->
            if (input == null) {
                throw IllegalStateException("Selected file could not be opened.")
            }
            tempFile.outputStream().use { output -> input.copyTo(output) }
        }
        return mapOf(
            "path" to tempFile.absolutePath,
            "fileName" to displayName,
            "mimeType" to mimeType,
            "fileSize" to tempFile.length()
        )
    }

    private fun openAttachment(path: String, mimeType: String?, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.success(false)
            return
        }

        val uri = FileProvider.getUriForFile(this, "$packageName.attachments", file)
        val resolvedMime = mimeType ?: mimeTypeForFile(file.name)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, resolvedMime ?: "*/*")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.success(false)
        } catch (error: Exception) {
            result.error("open_failed", error.message ?: "Could not open attachment.", null)
        }
    }

    private fun displayNameFor(uri: Uri): String? {
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, null, null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    return cursor.getString(index)
                }
            }
        } finally {
            cursor?.close()
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }

    private fun extensionFor(displayName: String, mimeType: String?): String {
        val fromName = displayName.substringAfterLast('.', "").lowercase()
        if (fromName.isNotBlank()) {
            return fromName
        }
        return when (mimeType) {
            "application/pdf" -> "pdf"
            "image/jpeg" -> "jpg"
            "image/png" -> "png"
            else -> "bin"
        }
    }

    private fun mimeTypeForFile(fileName: String): String? {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        if (extension.isBlank()) {
            return null
        }
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
    }

    companion object {
        private const val ATTACHMENTS_CHANNEL = "drivetracker/attachments"
        private const val PICK_ATTACHMENT_REQUEST = 6406
    }
}
