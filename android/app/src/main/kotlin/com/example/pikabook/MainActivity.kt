package com.example.pikabook

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ContentObserver
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.content.Context
import io.flutter.plugins.GeneratedPluginRegistrant
import java.lang.Exception

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.pikabook/screenshot"
    private var screenshotObserver: ContentObserver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startScreenshotDetection" -> {
                    registerScreenshotObserver()
                    result.success(true)
                }
                "stopScreenshotDetection" -> {
                    unregisterScreenshotObserver()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun registerScreenshotObserver() {
        if (screenshotObserver == null) {
            screenshotObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    super.onChange(selfChange, uri)
                    if (isScreenshotUri(uri)) {
                        // 스크린샷이 감지되면 Flutter에 이벤트 전달
                        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                            .invokeMethod("onScreenshotTaken", null)
                    }
                }
            }

            contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                screenshotObserver!!
            )
        }
    }

    private fun unregisterScreenshotObserver() {
        screenshotObserver?.let {
            contentResolver.unregisterContentObserver(it)
            screenshotObserver = null
        }
    }

    private fun isScreenshotUri(uri: Uri?): Boolean {
        if (uri == null) return false
        
        try {
            val cursor: Cursor? = contentResolver.query(
                uri,
                arrayOf(MediaStore.Images.Media.DISPLAY_NAME),
                null,
                null,
                null
            )
            
            if (cursor != null && cursor.moveToFirst()) {
                val displayNameIndex = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                if (displayNameIndex >= 0) {
                    val fileName = cursor.getString(displayNameIndex)
                    val isScreenshot = fileName.toLowerCase().contains("screenshot")
                    cursor.close()
                    return isScreenshot
                }
                cursor.close()
            }
        } catch (e: Exception) {
            // 에러 처리
        }
        
        return false
    }

    override fun onDestroy() {
        unregisterScreenshotObserver()
        super.onDestroy()
    }
} 