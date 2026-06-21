package com.example.anydb_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.anydb_flutter/file_saver"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveFileToDocuments") {
                val sourcePath = call.argument<String>("sourcePath")
                val displayName = call.argument<String>("displayName")
                val relativePath = call.argument<String>("relativePath") ?: "xyz.maya/anydb"
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                if (sourcePath == null || displayName == null) {
                    result.error("INVALID_ARGUMENTS", "sourcePath or displayName is null", null)
                    return@setMethodCallHandler
                }

                try {
                    val file = File(sourcePath)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "Source file does not exist", null)
                        return@setMethodCallHandler
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val resolver = contentResolver
                        val values = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOCUMENTS + "/" + relativePath)
                            put(MediaStore.Files.FileColumns.IS_PENDING, 1)
                        }

                        val collection = MediaStore.Files.getContentUri("external")
                        val uri = resolver.insert(collection, values)

                        if (uri == null) {
                            result.error("WRITE_ERROR", "Failed to insert record into MediaStore", null)
                            return@setMethodCallHandler
                        }

                        resolver.openOutputStream(uri).use { outputStream ->
                            FileInputStream(file).use { inputStream ->
                                val buffer = ByteArray(1024)
                                var bytesRead: Int
                                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                                    outputStream?.write(buffer, 0, bytesRead)
                                }
                            }
                        }

                        values.clear()
                        values.put(MediaStore.Files.FileColumns.IS_PENDING, 0)
                        resolver.update(uri, values, null, null)

                        result.success(uri.toString())
                    } else {
                        val documentsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
                        val targetDir = File(documentsDir, relativePath)
                        if (!targetDir.exists()) {
                            targetDir.mkdirs()
                        }
                        val targetFile = File(targetDir, displayName)
                        file.copyTo(targetFile, overwrite = true)
                        result.success(targetFile.absolutePath)
                    }
                } catch (e: Exception) {
                    result.error("WRITE_ERROR", e.message, e.stackTraceToString())
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
