package com.perfectsolutions.mtzhr

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WALKIE_CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startForegroundService",
                    "updateForegroundService" -> {
                        val title = call.argument<String>("title").orEmpty()
                        val message = call.argument<String>("message").orEmpty()
                        val action =
                            if (call.method == "startForegroundService") {
                                WalkieTalkieForegroundService.ACTION_START
                            } else {
                                WalkieTalkieForegroundService.ACTION_UPDATE
                            }

                        val intent =
                            Intent(
                                applicationContext,
                                WalkieTalkieForegroundService::class.java,
                            ).apply {
                                this.action = action
                                putExtra(WalkieTalkieForegroundService.EXTRA_TITLE, title)
                                putExtra(WalkieTalkieForegroundService.EXTRA_MESSAGE, message)
                            }

                        ContextCompat.startForegroundService(applicationContext, intent)
                        result.success(true)
                    }

                    "stopForegroundService" -> {
                        val intent =
                            Intent(
                                applicationContext,
                                WalkieTalkieForegroundService::class.java,
                            ).apply {
                                action = WalkieTalkieForegroundService.ACTION_STOP
                            }

                        applicationContext.startService(intent)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            } catch (exception: Exception) {
                result.error(
                    "walkie_foreground_error",
                    exception.message ?: "Foreground service operation failed.",
                    null,
                )
            }
        }
    }

    companion object {
        private const val WALKIE_CHANNEL_NAME = "smart_vision/walkie_foreground"
    }
}
