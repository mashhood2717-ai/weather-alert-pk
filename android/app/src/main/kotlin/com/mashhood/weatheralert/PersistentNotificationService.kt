package com.mashhood.weatheralert

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat

class PersistentNotificationService : Service() {

    companion object {
        const val CHANNEL_ID = "weather_persistent_channel"
        const val NOTIFICATION_ID = 9999
        const val ACTION_REFRESH = "com.mashhood.weatheralert.ACTION_REFRESH"

        private var instance: PersistentNotificationService? = null

        fun updateNotification(
            context: Context,
            condition: String,
            temperature: String,
            nextPrayer: String,
            nextPrayerTime: String,
            city: String,
            lastUpdated: String
        ) {
            instance?.updateNotificationContent(condition, temperature, nextPrayer, nextPrayerTime, city, lastUpdated)
        }

        fun isRunning(): Boolean = instance != null
    }

    private var condition = "--"
    private var temperature = "--"
    private var nextPrayer = "--"
    private var nextPrayerTime = "--"
    private var city = "--"
    private var lastUpdated = "now"

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_REFRESH -> {
                // Send refresh event to Flutter
                MainActivity.sendRefreshEvent()
            }
            else -> {
                // Update data from intent
                intent?.let {
                    condition = it.getStringExtra("condition") ?: condition
                    temperature = it.getStringExtra("temperature") ?: temperature
                    nextPrayer = it.getStringExtra("nextPrayer") ?: nextPrayer
                    nextPrayerTime = it.getStringExtra("nextPrayerTime") ?: nextPrayerTime
                    city = it.getStringExtra("city") ?: city
                    lastUpdated = it.getStringExtra("lastUpdated") ?: lastUpdated
                }

                // Start foreground with notification
                val notification = buildNotification()
                startForeground(NOTIFICATION_ID, notification)
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Weather & Prayer Status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows current weather and next prayer time"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        // Intent to open the app
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Intent for refresh button
        val refreshIntent = Intent(this, PersistentNotificationService::class.java).apply {
            action = ACTION_REFRESH
        }
        val refreshPendingIntent = PendingIntent.getService(
            this, 1, refreshIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Build the notification with custom content
        val title = "$condition • $temperature"
        val text = "$nextPrayer at $nextPrayerTime • $city • $lastUpdated"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openPendingIntent)
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                android.R.drawable.ic_popup_sync,
                "Refresh",
                refreshPendingIntent
            )
            .build()
    }

    fun updateNotificationContent(
        condition: String,
        temperature: String,
        nextPrayer: String,
        nextPrayerTime: String,
        city: String,
        lastUpdated: String
    ) {
        this.condition = condition
        this.temperature = temperature
        this.nextPrayer = nextPrayer
        this.nextPrayerTime = nextPrayerTime
        this.city = city
        this.lastUpdated = lastUpdated

        val notification = buildNotification()
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }
}
