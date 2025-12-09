package com.mashhood.weatheralert

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.mashhood.weatheralert/persistent_notification"
        private var methodChannel: MethodChannel? = null

        fun sendRefreshEvent() {
            methodChannel?.invokeMethod("onRefreshPressed", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startNotification" -> {
                    val condition = call.argument<String>("condition") ?: "--"
                    val temperature = call.argument<String>("temperature") ?: "--"
                    val nextPrayer = call.argument<String>("nextPrayer") ?: "--"
                    val nextPrayerTime = call.argument<String>("nextPrayerTime") ?: "--"
                    val city = call.argument<String>("city") ?: "--"

                    startPersistentNotification(condition, temperature, nextPrayer, nextPrayerTime, city)
                    result.success(true)
                }
                "stopNotification" -> {
                    stopPersistentNotification()
                    result.success(true)
                }
                "updateNotification" -> {
                    val condition = call.argument<String>("condition") ?: "--"
                    val temperature = call.argument<String>("temperature") ?: "--"
                    val nextPrayer = call.argument<String>("nextPrayer") ?: "--"
                    val nextPrayerTime = call.argument<String>("nextPrayerTime") ?: "--"
                    val city = call.argument<String>("city") ?: "--"

                    PersistentNotificationService.updateNotification(
                        this, condition, temperature, nextPrayer, nextPrayerTime, city
                    )
                    result.success(true)
                }
                "isRunning" -> {
                    result.success(PersistentNotificationService.isRunning())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startPersistentNotification(
        condition: String,
        temperature: String,
        nextPrayer: String,
        nextPrayerTime: String,
        city: String
    ) {
        val intent = Intent(this, PersistentNotificationService::class.java).apply {
            putExtra("condition", condition)
            putExtra("temperature", temperature)
            putExtra("nextPrayer", nextPrayer)
            putExtra("nextPrayerTime", nextPrayerTime)
            putExtra("city", city)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopPersistentNotification() {
        val intent = Intent(this, PersistentNotificationService::class.java)
        stopService(intent)
    }
}
