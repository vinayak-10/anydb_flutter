package com.example.anydb_flutter

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.anydb_flutter/file_saver"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveFileToDocuments") {
                val sourcePath = call.argument<String>("sourcePath")
                val displayName = call.argument<String>("displayName")
                val relativePath = call.argument<String>("relativePath") // e.g. "xyz.maya/anydb/schema/MySchema/Aggregators"
                val mimeType = call.argument<String>("mimeType")

                if (sourcePath == null || displayName == null || relativePath == null) {
                    result.error("INVALID_ARGUMENTS", "Arguments cannot be null", null)
                    return@setMethodCallHandler
                }

                val sourceFile = File(sourcePath)
                if (!sourceFile.exists()) {
                    result.error("FILE_NOT_FOUND", "Source file does not exist at $sourcePath", null)
                    return@setMethodCallHandler
                }

                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val contentValues = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                            // CRITICAL HIERARCHY FIX: Force MediaStore to target the nested path under public Documents folder
                            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOCUMENTS}/$relativePath")
                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                        }

                        val resolver = context.contentResolver
                        val collectionUri = MediaStore.Files.getContentUri("external")
                        val itemUri = resolver.insert(collectionUri, contentValues)

                        if (itemUri != null) {
                            resolver.openOutputStream(itemUri).use { outputStream ->
                                sourceFile.inputStream().use { inputStream ->
                                    inputStream.copyTo(outputStream!!)
                                }
                            }
                            contentValues.clear()
                            contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                            resolver.update(itemUri, contentValues, null, null)
                            result.success(true)
                        } else {
                            result.error("MEDIASTORE_ERROR", "Failed to create MediaStore entry", null)
                        }
                    } else {
                        // Fallback for legacy target devices (Android 9 or below)
                        val publicDocsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
                        val targetDir = File(publicDocsDir, relativePath)
                        if (!targetDir.exists()) {
                            targetDir.mkdirs()
                        }
                        val targetFile = File(targetDir, displayName)
                        sourceFile.inputStream().use { inputStream ->
                            targetFile.outputStream().use { outputStream ->
                                inputStream.copyTo(outputStream)
                            }
                        }
                        result.success(true)
                    }
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.localizedMessage, e.toString())
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
