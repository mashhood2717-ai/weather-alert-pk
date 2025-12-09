package com.mashhood.weatheralert

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.mashhood.weatheralert/persistent_notification"
        private const val WIDGET_CHANNEL = "com.mashhood.weatheralert/widget"
        private var methodChannel: MethodChannel? = null
        private var widgetChannel: MethodChannel? = null

        fun sendRefreshEvent() {
            methodChannel?.invokeMethod("onRefreshPressed", null)
        }

        fun sendWidgetRefreshEvent() {
            widgetChannel?.invokeMethod("onWidgetRefresh", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Persistent notification channel
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

        // Widget channel
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
        widgetChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val city = call.argument<String>("city")
                    val temp = call.argument<String>("temp")
                    val condition = call.argument<String>("condition")
                    val feelsLike = call.argument<String>("feelsLike")
                    val humidity = call.argument<String>("humidity")
                    val wind = call.argument<String>("wind")
                    val uv = call.argument<String>("uv")
                    val isDay = call.argument<Boolean>("isDay") ?: true
                    val nextPrayer = call.argument<String>("nextPrayer")
                    val nextPrayerTime = call.argument<String>("nextPrayerTime")
                    val fajr = call.argument<String>("fajr")
                    val dhuhr = call.argument<String>("dhuhr")
                    val asr = call.argument<String>("asr")
                    val maghrib = call.argument<String>("maghrib")
                    val isha = call.argument<String>("isha")

                    WeatherWidgetProvider.saveWidgetData(
                        this,
                        city, temp, condition, feelsLike,
                        humidity, wind, uv, isDay,
                        nextPrayer, nextPrayerTime,
                        fajr, dhuhr, asr, maghrib, isha
                    )
                    result.success(true)
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
