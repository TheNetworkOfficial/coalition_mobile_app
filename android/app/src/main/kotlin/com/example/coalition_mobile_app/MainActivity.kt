package com.example.coalition_mobile_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var videoNative: VideoNative? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        videoNative = VideoNative(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        videoNative?.dispose()
        videoNative = null
        super.onDestroy()
    }
}
