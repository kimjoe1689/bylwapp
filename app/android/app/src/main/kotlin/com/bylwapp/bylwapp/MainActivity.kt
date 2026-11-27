package com.bylwapp.bylwapp

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bylw/log")
            .setMethodCallHandler { call, result ->
                if (call.method == "log") {
                    Log.i("BYLW", call.argument<String>("message") ?: "")
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
