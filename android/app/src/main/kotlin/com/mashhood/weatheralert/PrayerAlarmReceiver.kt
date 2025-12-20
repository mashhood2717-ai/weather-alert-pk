package com.mashhood.weatheralert

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
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
        
        // Static MediaPlayer to keep azan playing
        private var mediaPlayer: MediaPlayer? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "🕌 onReceive called! Action: ${intent.action}")
        
        if (intent.action != ACTION_PRAYER_ALARM) {
            Log.w(TAG, "Unknown action: ${intent.action}")
            return
        }

        val prayerName = intent.getStringExtra(EXTRA_PRAYER_NAME) ?: "Prayer"
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 2000)
        val useAzan = intent.getBooleanExtra(EXTRA_USE_AZAN, true)

        Log.d(TAG, "🕌 Prayer alarm received: $prayerName, useAzan: $useAzan, id: $notificationId")

        // Acquire wake lock to ensure notification is shown even if device is sleeping
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "weatheralert:prayeralarm"
        )
        wakeLock.acquire(300000) // 5 minutes max for full azan
        
        try {
            showPrayerNotification(context, prayerName, notificationId, useAzan)
            
            // Play azan sound using MediaPlayer (for full duration)
            if (useAzan) {
                playAzanSound(context, wakeLock)
            } else {
                // Just vibration, release wake lock after a short delay
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    if (wakeLock.isHeld) wakeLock.release()
                }, 5000)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error showing prayer notification: ${e.message}")
            if (wakeLock.isHeld) wakeLock.release()
        }
    }
    
    private fun playAzanSound(context: Context, wakeLock: PowerManager.WakeLock) {
        try {
            // Stop any existing playback
            mediaPlayer?.stop()
            mediaPlayer?.release()
            
            val azanUri = Uri.parse("android.resource://${context.packageName}/raw/azan")
            
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .build()
                )
                setDataSource(context, azanUri)
                prepare()
                
                setOnCompletionListener {
                    Log.d(TAG, "🕌 Azan playback completed")
                    it.release()
                    mediaPlayer = null
                    if (wakeLock.isHeld) wakeLock.release()
                }
                
                setOnErrorListener { mp, what, extra ->
                    Log.e(TAG, "MediaPlayer error: what=$what, extra=$extra")
                    mp.release()
                    mediaPlayer = null
                    if (wakeLock.isHeld) wakeLock.release()
                    true
                }
                
                start()
                Log.d(TAG, "🕌 Azan playback started")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error playing azan: ${e.message}")
            if (wakeLock.isHeld) wakeLock.release()
        }
    }

    private fun showPrayerNotification(
        context: Context,
        prayerName: String,
        notificationId: Int,
        useAzan: Boolean
    ) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create notification channel for Android 8+
        // Sound is handled separately via MediaPlayer for full azan duration
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Prayer Time Azan (Native)",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Prayer time notifications with azan sound"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500, 200, 500)
                // Don't set sound on channel - we play via MediaPlayer for full duration
                setSound(null, null)
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

        // Build notification - sound handled via MediaPlayer
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
            .setSilent(false) // Allow vibration

        notificationManager.notify(notificationId, builder.build())
        Log.d(TAG, "Prayer notification shown: $prayerName (ID: $notificationId)")
    }
}
