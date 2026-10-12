package com.perfectsolutions.mtzhr

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class WalkieTalkieForegroundService : Service() {
    private var isStartedInForeground = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // #region debug-point A:service-command-received
        reportDebugEvent(
            "A",
            "WalkieTalkieForegroundService:onStartCommand",
            "Walkie foreground service received command",
            """{"action":${jsonQuote(intent?.action ?: "null")},"startId":$startId,"isStartedInForeground":$isStartedInForeground}""",
        )
        // #endregion
        when (intent?.action) {
            ACTION_STOP -> {
                // #region debug-point A:service-stop
                reportDebugEvent(
                    "A",
                    "WalkieTalkieForegroundService:onStartCommand",
                    "Stopping walkie foreground service",
                    """{"action":"$ACTION_STOP"}""",
                )
                // #endregion
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_START,
            ACTION_UPDATE -> {
                val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
                val message = intent.getStringExtra(EXTRA_MESSAGE).orEmpty()
                createNotificationChannel()

                val notification = buildNotification(title, message)
                if (!isStartedInForeground || intent.action == ACTION_START) {
                    // #region debug-point B:service-start-foreground
                    reportDebugEvent(
                        "B",
                        "WalkieTalkieForegroundService:onStartCommand",
                        "Starting walkie foreground notification",
                        """{"action":${jsonQuote(intent.action ?: "null")},"title":${jsonQuote(title)},"message":${jsonQuote(message)}}""",
                    )
                    // #endregion
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startForeground(
                            NOTIFICATION_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                        )
                    } else {
                        startForeground(NOTIFICATION_ID, notification)
                    }
                    isStartedInForeground = true
                } else {
                    // #region debug-point B:service-update-notification
                    reportDebugEvent(
                        "B",
                        "WalkieTalkieForegroundService:onStartCommand",
                        "Updating walkie foreground notification",
                        """{"action":${jsonQuote(intent.action ?: "null")},"title":${jsonQuote(title)},"message":${jsonQuote(message)}}""",
                    )
                    // #endregion
                    NotificationManagerCompat.from(this).notify(
                        NOTIFICATION_ID,
                        notification,
                    )
                }

                return START_STICKY
            }
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        // #region debug-point E:service-destroyed
        reportDebugEvent(
            "E",
            "WalkieTalkieForegroundService:onDestroy",
            "Walkie foreground service destroyed",
            """{"isStartedInForeground":$isStartedInForeground}""",
        )
        // #endregion
        isStartedInForeground = false
        super.onDestroy()
    }

    private fun buildNotification(title: String, message: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setLargeIcon(BitmapFactory.decodeResource(resources, R.mipmap.launcher_icon))
            .setContentTitle(title.ifBlank { DEFAULT_TITLE })
            .setContentText(message.ifBlank { DEFAULT_MESSAGE })
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    message.ifBlank { DEFAULT_MESSAGE },
                ),
            )
            .setContentIntent(contentIntent)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setOngoing(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = CHANNEL_DESCRIPTION
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
        // #region debug-point B:channel-created
        reportDebugEvent(
            "B",
            "WalkieTalkieForegroundService:createNotificationChannel",
            "Walkie notification channel ensured",
            """{"channelId":"$CHANNEL_ID","importance":${NotificationManager.IMPORTANCE_LOW}}""",
        )
        // #endregion
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
        const val ACTION_START = "walkie.start"
        const val ACTION_UPDATE = "walkie.update"
        const val ACTION_STOP = "walkie.stop"
        const val EXTRA_TITLE = "title"
        const val EXTRA_MESSAGE = "message"

        private const val CHANNEL_ID = "walkie_talkie_background_channel"
        private const val CHANNEL_NAME = "Walkie-Talkie / ووكي-توكي"
        private const val CHANNEL_DESCRIPTION = "Persistent walkie-talkie connection"
        private const val NOTIFICATION_ID = 41021
        private const val DEFAULT_TITLE = "Walkie-Talkie Active"
        private const val DEFAULT_MESSAGE = "Background audio connection is active."
        private const val DEBUG_SERVER_URL = "http://192.168.1.168:7777/event"
        private const val DEBUG_SESSION_ID = "walkie-background-audio"
    }
}
