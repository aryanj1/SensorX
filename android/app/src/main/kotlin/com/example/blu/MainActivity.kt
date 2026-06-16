package com.example.blu

import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.blu.storage/free_space"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getFreeDiskSpaceMb") {
                    try {
                        val stat = StatFs(Environment.getDataDirectory().path)
                        val freeMb =
                            stat.availableBlocksLong * stat.blockSizeLong / 1_048_576.0
                        result.success(freeMb)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
