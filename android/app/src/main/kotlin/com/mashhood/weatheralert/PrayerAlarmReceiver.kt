package com.mashhood.weatheralert

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Receives prayer alarm broadcasts and shows prayer notification with azan sound.
 * This is a native Android implementation for reliable prayer notifications.
 */
class PrayerAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "PrayerAlarmReceiver"
        const val ACTION_PRAYER_ALARM = "com.mashhood.weatheralert.PRAYER_ALARM"
        const val EXTRA_PRAYER_NAME = "prayer_name"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val EXTRA_USE_AZAN = "use_azan"
        const val CHANNEL_ID = "prayer_azan_native"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_PRAYER_ALARM) return

        val prayerName = intent.getStringExtra(EXTRA_PRAYER_NAME) ?: "Prayer"
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 2000)
        val useAzan = intent.getBooleanExtra(EXTRA_USE_AZAN, true)

        Log.d(TAG, "Prayer alarm received: $prayerName, useAzan: $useAzan")

        showPrayerNotification(context, prayerName, notificationId, useAzan)
    }

    private fun showPrayerNotification(
        context: Context,
        prayerName: String,
        notificationId: Int,
        useAzan: Boolean
    ) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create notification channel for Android 8+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val azanSoundUri = Uri.parse("android.resource://${context.packageName}/raw/azan")
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()

            val channel = NotificationChannel(
                CHANNEL_ID,
                "Prayer Time Azan (Native)",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Prayer time notifications with azan sound"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500, 200, 500)
                if (useAzan) {
                    setSound(azanSoundUri, audioAttributes)
                }
                enableLights(true)
                lightColor = 0xFF4CAF50.toInt()
            }
            notificationManager.createNotificationChannel(channel)
        }

        // Create intent to open app when notification is tapped
        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context, notificationId, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Build notification
        val azanSoundUri = Uri.parse("android.resource://${context.packageName}/raw/azan")
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("🕌 $prayerName Time")
            .setContentText("Allahu Akbar - It's time for $prayerName prayer")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setVibrate(longArrayOf(0, 500, 200, 500, 200, 500, 200, 500))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setFullScreenIntent(pendingIntent, true)

        if (useAzan && Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // For pre-Oreo, set sound directly on notification
            builder.setSound(azanSoundUri)
        }

        notificationManager.notify(notificationId, builder.build())
        Log.d(TAG, "Prayer notification shown: $prayerName (ID: $notificationId)")
    }
}
