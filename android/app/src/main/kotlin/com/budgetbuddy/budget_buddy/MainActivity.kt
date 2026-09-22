package com.budgetbuddy.budget_buddy

import android.os.Build
import android.os.Bundle
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var backChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        backChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "budget_buddy/back",
        )
        backChannel?.setMethodCallHandler { call, result ->
            if (call.method == "exitApp") {
                finishAndRemoveTask()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            ) {
                sendBackToFlutter()
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        sendBackToFlutter()
    }

    private fun sendBackToFlutter() {
        backChannel?.invokeMethod("backPressed", null)
    }
}
