package com.mashhood.weatheralert

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.mashhood.weatheralert/persistent_notification"
        private const val WIDGET_CHANNEL = "com.mashhood.weatheralert/widget"
        private const val SETTINGS_CHANNEL = "com.mashhood.weatheralert/settings"
        private const val PRAYER_CHANNEL = "com.mashhood.weatheralert/prayer_alarm"
        private var methodChannel: MethodChannel? = null
        private var widgetChannel: MethodChannel? = null
        private var settingsChannel: MethodChannel? = null
        private var prayerChannel: MethodChannel? = null

        fun sendRefreshEvent() {
            methodChannel?.invokeMethod("onRefreshPressed", null)
        }

        fun sendWidgetRefreshEvent() {
            widgetChannel?.invokeMethod("onWidgetRefresh", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Prayer alarm channel for native AlarmManager scheduling
        prayerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRAYER_CHANNEL)
        prayerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "schedulePrayerAlarm" -> {
                    val prayerName = call.argument<String>("prayerName") ?: "Prayer"
                    val triggerTimeMillis = call.argument<Long>("triggerTimeMillis") ?: 0L
                    val notificationId = call.argument<Int>("notificationId") ?: 2000
                    val useAzan = call.argument<Boolean>("useAzan") ?: true

                    PrayerAlarmScheduler.schedulePrayerAlarm(
                        this, prayerName, triggerTimeMillis, notificationId, useAzan
                    )
                    result.success(true)
                }
                "triggerImmediateAzan" -> {
                    // Trigger azan notification immediately using native MediaPlayer
                    val prayerName = call.argument<String>("prayerName") ?: "Test"
                    val notificationId = call.argument<Int>("notificationId") ?: 2999
                    val useAzan = call.argument<Boolean>("useAzan") ?: true
                    
                    // Create and send broadcast intent directly
                    val intent = android.content.Intent(this, PrayerAlarmReceiver::class.java).apply {
                        action = PrayerAlarmReceiver.ACTION_PRAYER_ALARM
                        putExtra(PrayerAlarmReceiver.EXTRA_PRAYER_NAME, prayerName)
                        putExtra(PrayerAlarmReceiver.EXTRA_NOTIFICATION_ID, notificationId)
                        putExtra(PrayerAlarmReceiver.EXTRA_USE_AZAN, useAzan)
                    }
                    sendBroadcast(intent)
                    result.success(true)
                }
                "cancelPrayerAlarm" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: 2000
                    PrayerAlarmScheduler.cancelPrayerAlarm(this, notificationId)
                    result.success(true)
                }
                "cancelAllPrayerAlarms" -> {
                    PrayerAlarmScheduler.cancelAllPrayerAlarms(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Settings channel for opening system settings
        settingsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
        settingsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Fallback to app settings
                            openAppSettings()
                            result.success(false)
                        }
                    } else {
                        result.success(true) // Not needed on older Android
                    }
                }
                "openBatteryOptimizationSettings" -> {
                    try {
                        // Try to open battery optimization settings for this app
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        // Fallback to general battery settings
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e2: Exception) {
                            openAppSettings()
                            result.success(false)
                        }
                    }
                }
                "openAutoStartSettings" -> {
                    // OnePlus/Oppo/Xiaomi have AutoStart managers that block scheduled tasks
                    val opened = openAutoStartSettings()
                    result.success(opened)
                }
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

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
                    val lastUpdated = call.argument<String>("lastUpdated") ?: "now"

                    startPersistentNotification(condition, temperature, nextPrayer, nextPrayerTime, city, lastUpdated)
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
                    val lastUpdated = call.argument<String>("lastUpdated") ?: "now"

                    PersistentNotificationService.updateNotification(
                        this, condition, temperature, nextPrayer, nextPrayerTime, city, lastUpdated
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
        city: String,
        lastUpdated: String
    ) {
        val intent = Intent(this, PersistentNotificationService::class.java).apply {
            putExtra("condition", condition)
            putExtra("temperature", temperature)
            putExtra("nextPrayer", nextPrayer)
            putExtra("nextPrayerTime", nextPrayerTime)
            putExtra("city", city)
            putExtra("lastUpdated", lastUpdated)
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

    /**
     * Try to open AutoStart settings for Chinese OEMs (OnePlus, Oppo, Xiaomi, etc.)
     * These manufacturers block AlarmManager scheduled tasks unless the app is whitelisted.
     */
    private fun openAutoStartSettings(): Boolean {
        val intents = listOf(
            // Xiaomi
            Intent().setComponent(android.content.ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            )),
            // Oppo
            Intent().setComponent(android.content.ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            )),
            // Oppo (alternative)
            Intent().setComponent(android.content.ComponentName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity"
            )),
            // OnePlus
            Intent().setComponent(android.content.ComponentName(
                "com.oneplus.security",
                "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
            )),
            // Vivo
            Intent().setComponent(android.content.ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            )),
            // Huawei
            Intent().setComponent(android.content.ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            )),
            // Samsung (no dedicated autostart, use app settings)
            Intent().setComponent(android.content.ComponentName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.battery.ui.BatteryActivity"
            )),
            // Letv
            Intent().setComponent(android.content.ComponentName(
                "com.letv.android.letvsafe",
                "com.letv.android.letvsafe.AutobootManageActivity"
            )),
            // Asus
            Intent().setComponent(android.content.ComponentName(
                "com.asus.mobilemanager",
                "com.asus.mobilemanager.autostart.AutoStartActivity"
            ))
        )

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (packageManager.resolveActivity(intent, 0) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (e: Exception) {
                // Try next intent
            }
        }

        // Fallback: open app settings
        openAppSettings()
        return false
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }
}
