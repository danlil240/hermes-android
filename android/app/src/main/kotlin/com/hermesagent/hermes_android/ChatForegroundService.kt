package com.hermesagent.hermes_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Owns an in-flight Hermes SSE chat request independently of the Flutter
 * activity. A foreground service is the Android-supported way to continue a
 * user-initiated long-running network operation after the app UI is closed.
 */
class ChatForegroundService : Service() {
    companion object {
        const val ACTION_CHAT_EVENT = "com.hermesagent.hermes_android.CHAT_EVENT"
        const val EXTRA_ENDPOINT = "endpoint"
        const val EXTRA_HEADERS = "headers"
        const val EXTRA_BODY = "body"
        const val EXTRA_SESSION_ID = "sessionId"
        const val EXTRA_TYPE = "type"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_ERROR = "error"

        private const val WORK_CHANNEL = "hermes_chat_work"
        private const val REPLY_CHANNEL = "hermes_chat_replies"
        private const val WORK_NOTIFICATION_ID = 7331
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val endpoint = intent?.getStringExtra(EXTRA_ENDPOINT)
        val body = intent?.getStringExtra(EXTRA_BODY)
        val sessionId = intent?.getStringExtra(EXTRA_SESSION_ID)
        @Suppress("DEPRECATION")
        val headers = intent?.getSerializableExtra(EXTRA_HEADERS) as? HashMap<String, String>

        if (endpoint.isNullOrBlank() || body.isNullOrBlank() || sessionId.isNullOrBlank() || headers == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        createChannels()
        startForeground(WORK_NOTIFICATION_ID, workingNotification())
        thread(name = "hermes-chat-$sessionId") {
            runChat(endpoint, headers, body, sessionId)
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    private fun runChat(
        endpoint: String,
        headers: Map<String, String>,
        body: String,
        sessionId: String,
    ) {
        var connection: HttpURLConnection? = null
        val response = StringBuilder()
        try {
            connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 20_000
                readTimeout = 0
                setRequestProperty("Accept", "text/event-stream")
                headers.forEach { (name, value) -> setRequestProperty(name, value) }
            }
            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(body)
            }

            if (connection.responseCode !in 200..299) {
                val message = connection.errorStream?.bufferedReader()?.use { it.readText() }
                    ?.takeIf { it.isNotBlank() }
                    ?: "HTTP ${connection.responseCode}"
                sendEvent(sessionId, "error", error = message)
                notifyFailure(message)
                return
            }

            connection.inputStream.bufferedReader().use { reader ->
                readSse(reader, sessionId, response)
            }
            sendEvent(sessionId, "done")
            if (!MainActivity.isActivityVisible) notifyReply(response.toString())
        } catch (error: Exception) {
            val message = error.message ?: "Connection to Hermes failed"
            sendEvent(sessionId, "error", error = message)
            notifyFailure(message)
        } finally {
            connection?.disconnect()
        }
    }

    private fun readSse(reader: BufferedReader, sessionId: String, response: StringBuilder) {
        val dataLines = mutableListOf<String>()
        fun consumeFrame() {
            if (dataLines.isEmpty()) return
            val data = dataLines.joinToString("\n").trim()
            dataLines.clear()
            if (data.isEmpty() || data == "[DONE]") return
            val token = parseToken(data) ?: return
            response.append(token)
            sendEvent(sessionId, "token", token = token)
        }

        while (true) {
            val line = reader.readLine() ?: break
            when {
                line.isEmpty() -> consumeFrame()
                line.startsWith("data:") -> dataLines += line.removePrefix("data:").trimStart()
            }
        }
        consumeFrame()
    }

    private fun parseToken(data: String): String? = try {
        val choices = JSONObject(data).optJSONArray("choices") ?: return null
        if (choices.length() == 0) return null
        choices.optJSONObject(0)
            ?.optJSONObject("delta")
            ?.optString("content")
            ?.takeIf { it.isNotEmpty() }
    } catch (_: Exception) {
        null
    }

    private fun sendEvent(
        sessionId: String,
        type: String,
        token: String? = null,
        error: String? = null,
    ) {
        sendBroadcast(Intent(ACTION_CHAT_EVENT).setPackage(packageName).apply {
            putExtra(EXTRA_SESSION_ID, sessionId)
            putExtra(EXTRA_TYPE, type)
            token?.let { putExtra(EXTRA_TOKEN, it) }
            error?.let { putExtra(EXTRA_ERROR, it) }
        })
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                WORK_CHANNEL,
                "Hermes active chats",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Shows when Hermes is finishing a request." },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                REPLY_CHANNEL,
                "Hermes replies",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = "Notifies you when Hermes has replied." },
        )
    }

    private fun workingNotification() = NotificationCompat.Builder(this, WORK_CHANNEL)
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle("Hermes is working")
        .setContentText("Your session will continue if you leave the app.")
        .setOngoing(true)
        .build()

    private fun notifyReply(reply: String) {
        val preview = reply.trim().replace(Regex("\\s+"), " ")
            .ifBlank { "Hermes finished your request." }
            .take(240)
        notificationManager().notify(
            (System.currentTimeMillis() % Int.MAX_VALUE).toInt(),
            NotificationCompat.Builder(this, REPLY_CHANNEL)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Hermes replied")
                .setContentText(preview)
                .setStyle(NotificationCompat.BigTextStyle().bigText(preview))
                .setContentIntent(launchIntent())
                .setAutoCancel(true)
                .build(),
        )
    }

    private fun notifyFailure(message: String) {
        if (MainActivity.isActivityVisible) return
        notificationManager().notify(
            (System.currentTimeMillis() % Int.MAX_VALUE).toInt(),
            NotificationCompat.Builder(this, REPLY_CHANNEL)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Hermes chat failed")
                .setContentText(message.take(240))
                .setContentIntent(launchIntent())
                .setAutoCancel(true)
                .build(),
        )
    }

    private fun launchIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        } ?: Intent()
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notificationManager() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null
}
