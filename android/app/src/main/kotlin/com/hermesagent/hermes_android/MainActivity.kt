package com.hermesagent.hermes_android

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        @Volatile
        var isActivityVisible: Boolean = false
    }

    private var eventSink: EventChannel.EventSink? = null
    private val chatEventReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != ChatForegroundService.ACTION_CHAT_EVENT) return
            eventSink?.success(
                mapOf(
                    "sessionId" to intent.getStringExtra(ChatForegroundService.EXTRA_SESSION_ID),
                    "type" to intent.getStringExtra(ChatForegroundService.EXTRA_TYPE),
                    "token" to intent.getStringExtra(ChatForegroundService.EXTRA_TOKEN),
                    "error" to intent.getStringExtra(ChatForegroundService.EXTRA_ERROR),
                ),
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hermes/background_chat")
            .setMethodCallHandler { call, result ->
                if (call.method != "startChat") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                startChat(call, result)
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "hermes/background_chat/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun startChat(call: MethodCall, result: MethodChannel.Result) {
        val endpoint = call.argument<String>("endpoint")
        val body = call.argument<String>("body")
        val sessionId = call.argument<String>("sessionId")
        @Suppress("UNCHECKED_CAST")
        val headers = call.argument<Map<String, String>>("headers")

        if (endpoint.isNullOrBlank() || body.isNullOrBlank() || sessionId.isNullOrBlank() || headers == null) {
            result.error("invalid_chat_request", "Missing a required chat request field", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7331)
        }

        val serviceIntent = Intent(this, ChatForegroundService::class.java).apply {
            putExtra(ChatForegroundService.EXTRA_ENDPOINT, endpoint)
            putExtra(ChatForegroundService.EXTRA_BODY, body)
            putExtra(ChatForegroundService.EXTRA_SESSION_ID, sessionId)
            putExtra(ChatForegroundService.EXTRA_HEADERS, HashMap(headers))
        }
        ContextCompat.startForegroundService(this, serviceIntent)
        result.success(true)
    }

    override fun onResume() {
        super.onResume()
        isActivityVisible = true
    }

    override fun onPause() {
        isActivityVisible = false
        super.onPause()
    }

    override fun onStart() {
        super.onStart()
        ContextCompat.registerReceiver(
            this,
            chatEventReceiver,
            IntentFilter(ChatForegroundService.ACTION_CHAT_EVENT),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onStop() {
        unregisterReceiver(chatEventReceiver)
        super.onStop()
    }
}
