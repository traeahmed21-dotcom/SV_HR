package com.example.smart_vision

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.perfectsolutions.mtzhr.WalkieTalkieForegroundService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class WalkieForegroundPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(
            binding.binaryMessenger,
            CHANNEL_NAME,
        ).also {
            it.setMethodCallHandler(this)
        }
        // #region debug-point D:plugin-attached
        reportDebugEvent(
            "D",
            "WalkieForegroundPlugin:onAttachedToEngine",
            "Walkie foreground plugin attached to engine",
            """{"channel":"$CHANNEL_NAME"}""",
        )
        // #endregion
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            // #region debug-point D:context-unavailable
            reportDebugEvent(
                "D",
                "WalkieForegroundPlugin:onMethodCall",
                "Walkie foreground plugin context is unavailable",
                """{"method":"${call.method}"}""",
            )
            // #endregion
            result.error("context_unavailable", "Application context is unavailable.", null)
            return
        }

        try {
            when (call.method) {
                "startForegroundService" -> {
                    val title = call.argument<String>("title").orEmpty()
                    val message = call.argument<String>("message").orEmpty()
                    // #region debug-point A:plugin-start-request
                    reportDebugEvent(
                        "A",
                        "WalkieForegroundPlugin:onMethodCall",
                        "Received foreground start request from Flutter",
                        """{"method":"startForegroundService","title":${jsonQuote(title)},"message":${jsonQuote(message)}}""",
                    )
                    // #endregion
                    startWalkieForegroundService(
                        context,
                        WalkieTalkieForegroundService.ACTION_START,
                        title,
                        message,
                    )
                    result.success(true)
                }

                "updateForegroundService" -> {
                    val title = call.argument<String>("title").orEmpty()
                    val message = call.argument<String>("message").orEmpty()
                    // #region debug-point B:plugin-update-request
                    reportDebugEvent(
                        "B",
                        "WalkieForegroundPlugin:onMethodCall",
                        "Received foreground update request from Flutter",
                        """{"method":"updateForegroundService","title":${jsonQuote(title)},"message":${jsonQuote(message)}}""",
                    )
                    // #endregion
                    startWalkieForegroundService(
                        context,
                        WalkieTalkieForegroundService.ACTION_UPDATE,
                        title,
                        message,
                    )
                    result.success(true)
                }

                "stopForegroundService" -> {
                    // #region debug-point A:plugin-stop-request
                    reportDebugEvent(
                        "A",
                        "WalkieForegroundPlugin:onMethodCall",
                        "Received foreground stop request from Flutter",
                        """{"method":"stopForegroundService"}""",
                    )
                    // #endregion
                    val intent = Intent(
                        context,
                        WalkieTalkieForegroundService::class.java,
                    ).apply {
                        action = WalkieTalkieForegroundService.ACTION_STOP
                    }
                    context.startService(intent)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (exception: Exception) {
            // #region debug-point D:plugin-error
            reportDebugEvent(
                "D",
                "WalkieForegroundPlugin:onMethodCall",
                "Walkie foreground plugin threw an exception",
                """{"method":"${call.method}","error":${jsonQuote(exception.message ?: exception.javaClass.simpleName)}}""",
            )
            // #endregion
            result.error(
                "walkie_foreground_error",
                exception.message ?: "Foreground service operation failed.",
                null,
            )
        }
    }

    private fun startWalkieForegroundService(
        context: Context,
        action: String,
        title: String,
        message: String,
    ) {
        val intent = Intent(
            context,
            WalkieTalkieForegroundService::class.java,
        ).apply {
            this.action = action
            putExtra(WalkieTalkieForegroundService.EXTRA_TITLE, title)
            putExtra(WalkieTalkieForegroundService.EXTRA_MESSAGE, message)
        }

        ContextCompat.startForegroundService(context, intent)
    }

    private fun reportDebugEvent(
        hypothesisId: String,
        location: String,
        msg: String,
        dataJson: String,
    ) {
        Thread {
            try {
                val connection = URL(DEBUG_SERVER_URL).openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")

                val payload =
                    """{"sessionId":"$DEBUG_SESSION_ID","runId":"pre-fix","hypothesisId":"$hypothesisId","location":"$location","msg":"[DEBUG] ${escapeJson(msg)}","data":$dataJson,"ts":${System.currentTimeMillis()}}"""

                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use {
                    it.write(payload)
                }
                connection.inputStream.close()
                connection.disconnect()
            } catch (_: Exception) {
            }
        }.start()
    }

    private fun jsonQuote(value: String): String = "\"${escapeJson(value)}\""

    private fun escapeJson(value: String): String =
        value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")

    companion object {
        private const val CHANNEL_NAME = "smart_vision/walkie_foreground"
        private const val DEBUG_SERVER_URL = "http://192.168.1.168:7777/event"
        private const val DEBUG_SESSION_ID = "walkie-background-audio"
    }
}
