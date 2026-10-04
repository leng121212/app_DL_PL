package com.trabekprey.trabekprey_downloader

import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.trabekprey.downloader/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isManageStorageGranted" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        result.success(Environment.isExternalStorageManager())
                    } else {
                        result.success(true)
                    }
                }
                "openStorageSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.error("SETTINGS_ERROR", e.message, null)
                            }
                        } catch (e2: Exception) {
                            result.error("SETTINGS_ERROR", e2.message, null)
                        }
                    }
                }
                "scanMediaFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val mime = if (path.endsWith(".jpg", true) || path.endsWith(".jpeg", true)) {
                            "image/jpeg"
                        } else if (path.endsWith(".png", true)) {
                            "image/png"
                        } else {
                            "video/mp4"
                        }
                        MediaScannerConnection.scanFile(context, arrayOf(path), arrayOf(mime), null)
                        result.success(true)
                    } else {
                        result.error("INVALID_PATH", "Path is null", null)
                    }
                }
                "installApk" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath.isNullOrBlank()) {
                        result.error("bad_args", "Missing apkPath.", null)
                        return@setMethodCallHandler
                    }
                    val file = File(apkPath)
                    if (!file.exists() || file.length() == 0L) {
                        result.error("not_found", "APK file does not exist or is empty.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val intent = Intent(Intent.ACTION_VIEW)
                        val uri = FileProvider.getUriForFile(
                            applicationContext,
                            "${applicationContext.packageName}.fileprovider",
                            file
                        )
                        intent.setDataAndType(uri, "application/vnd.android.package-archive")
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("install_error", t.message ?: "Failed to launch installer", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
