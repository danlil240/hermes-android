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
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Submits a run to Hermes and synchronizes its status. The Hermes server owns
 * the model/tool execution; this service is only a reconnectable status
 * observer and cannot cancel the server-side run when the Activity disappears.
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
        thread(name = "hermes-run-sync-$sessionId") {
            submitAndSyncRun(endpoint, headers, body, sessionId)
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    private fun submitAndSyncRun(
        endpoint: String,
        headers: Map<String, String>,
        body: String,
        sessionId: String,
    ) {
        var connection: HttpURLConnection? = null
        try {
            // POST /v1/runs returns immediately. Hermes continues the agent
            // run on the server after this request has ended.
            connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 20_000
                readTimeout = 30_000
                setRequestProperty("Accept", "application/json")
                headers.forEach { (name, value) -> setRequestProperty(name, value) }
            }
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

            if (connection.responseCode !in 200..299) {
                val message = connection.errorStream?.bufferedReader()?.use { it.readText() }
                    ?.takeIf { it.isNotBlank() } ?: "HTTP ${connection.responseCode}"
                sendEvent(sessionId, "error", error = message)
                notifyFailure(message)
                return
            }

            val runId = connection.inputStream.bufferedReader().use { JSONObject(it.readText()).optString("run_id") }
            if (runId.isBlank()) throw IllegalStateException("Hermes did not return a run_id")
            connection.disconnect()
            connection = null

            var lastStatus = ""
            while (true) {
                val status = getRunStatus(endpoint, headers, runId)
                val state = status.optString("status")
                if (state != lastStatus) {
                    lastStatus = state
                    sendEvent(sessionId, "status", error = state)
                }
                when (state) {
                    "completed" -> {
                        sendEvent(sessionId, "done")
                        if (!MainActivity.isActivityVisible) notifyReply(status.optString("output"))
                        return
                    }
                    "failed", "cancelled" -> {
                        val message = status.optString("error").ifBlank { "Hermes run $state" }
                        sendEvent(sessionId, "error", error = message)
                        notifyFailure(message)
                        return
                    }
                }
                Thread.sleep(2000)
            }
        } catch (error: Exception) {
            val message = error.message ?: "Connection to Hermes failed"
            sendEvent(sessionId, "error", error = message)
            notifyFailure(message)
        } finally {
            connection?.disconnect()
        }
    }

    private fun getRunStatus(endpoint: String, headers: Map<String, String>, runId: String): JSONObject {
        val statusUrl = endpoint.substringBeforeLast("/runs") + "/runs/" + runId
        val connection = (URL(statusUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 20_000
            readTimeout = 30_000
            headers.forEach { (name, value) -> setRequestProperty(name, value) }
        }
        return try {
            if (connection.responseCode !in 200..299) throw IllegalStateException("HTTP ${connection.responseCode}")
            connection.inputStream.bufferedReader().use { JSONObject(it.readText()) }
        } finally {
            connection.disconnect()
        }
    }

    private fun sendEvent(sessionId: String, type: String, token: String? = null, error: String? = null) {
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
        manager.createNotificationChannel(NotificationChannel(WORK_CHANNEL, "Hermes active chats", NotificationManager.IMPORTANCE_LOW))
        manager.createNotificationChannel(NotificationChannel(REPLY_CHANNEL, "Hermes replies", NotificationManager.IMPORTANCE_DEFAULT))
    }

    private fun workingNotification() = NotificationCompat.Builder(this, WORK_CHANNEL)
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle("Hermes is working")
        .setContentText("The session is running on your Hermes server.")
        .setOngoing(true)
        .build()

    private fun notifyReply(reply: String) {
        val preview = reply.trim().replace(Regex("\\s+"), " ").ifBlank { "Hermes finished your request." }.take(240)
        notificationManager().notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), NotificationCompat.Builder(this, REPLY_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher).setContentTitle("Hermes replied")
            .setContentText(preview).setStyle(NotificationCompat.BigTextStyle().bigText(preview))
            .setContentIntent(launchIntent()).setAutoCancel(true).build())
    }

    private fun notifyFailure(message: String) {
        if (MainActivity.isActivityVisible) return
        notificationManager().notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), NotificationCompat.Builder(this, REPLY_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher).setContentTitle("Hermes chat failed")
            .setContentText(message.take(240)).setContentIntent(launchIntent()).setAutoCancel(true).build())
    }

    private fun launchIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        } ?: Intent()
        return PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun notificationManager() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null
}
