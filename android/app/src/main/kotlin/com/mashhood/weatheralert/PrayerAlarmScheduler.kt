package com.mashhood.weatheralert

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Helper class to schedule prayer alarms using AlarmManager.
 * This is more reliable than flutter_local_notifications on some devices.
 */
object PrayerAlarmScheduler {

    private const val TAG = "PrayerAlarmScheduler"

    /**
     * Schedule a prayer alarm at the specified time.
     * Uses setAlarmClock for highest reliability on all Android versions.
     */
    fun schedulePrayerAlarm(
        context: Context,
        prayerName: String,
        triggerTimeMillis: Long,
        notificationId: Int,
        useAzan: Boolean = true
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(context, PrayerAlarmReceiver::class.java).apply {
            action = PrayerAlarmReceiver.ACTION_PRAYER_ALARM
            putExtra(PrayerAlarmReceiver.EXTRA_PRAYER_NAME, prayerName)
            putExtra(PrayerAlarmReceiver.EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(PrayerAlarmReceiver.EXTRA_USE_AZAN, useAzan)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Check if time is in the future
        val now = System.currentTimeMillis()
        if (triggerTimeMillis <= now) {
            Log.d(TAG, "Skipping past alarm for $prayerName")
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Android 12+ - check if we can schedule exact alarms
                if (alarmManager.canScheduleExactAlarms()) {
                    // Use setAlarmClock for highest priority (shows in status bar)
                    val showIntent = PendingIntent.getActivity(
                        context, 0,
                        Intent(context, MainActivity::class.java),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    alarmManager.setAlarmClock(
                        AlarmManager.AlarmClockInfo(triggerTimeMillis, showIntent),
                        pendingIntent
                    )
                    Log.d(TAG, "Scheduled alarm clock for $prayerName at $triggerTimeMillis")
                } else {
                    // Fallback to inexact alarm
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerTimeMillis,
                        pendingIntent
                    )
                    Log.w(TAG, "Using inexact alarm for $prayerName (no exact alarm permission)")
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // Android 6-11 - use setAlarmClock for reliability
                val showIntent = PendingIntent.getActivity(
                    context, 0,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(triggerTimeMillis, showIntent),
                    pendingIntent
                )
                Log.d(TAG, "Scheduled alarm clock for $prayerName at $triggerTimeMillis")
            } else {
                // Older Android
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerTimeMillis,
                    pendingIntent
                )
                Log.d(TAG, "Scheduled exact alarm for $prayerName at $triggerTimeMillis")
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception scheduling alarm: ${e.message}")
            // Fallback to inexact alarm
            alarmManager.set(
                AlarmManager.RTC_WAKEUP,
                triggerTimeMillis,
                pendingIntent
            )
        }
    }

    /**
     * Cancel a specific prayer alarm.
     */
    fun cancelPrayerAlarm(context: Context, notificationId: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(context, PrayerAlarmReceiver::class.java).apply {
            action = PrayerAlarmReceiver.ACTION_PRAYER_ALARM
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        alarmManager.cancel(pendingIntent)
        Log.d(TAG, "Cancelled alarm with ID: $notificationId")
    }

    /**
     * Cancel all prayer alarms (IDs 2000-2019).
     */
    fun cancelAllPrayerAlarms(context: Context) {
        for (id in 2000..2019) {
            cancelPrayerAlarm(context, id)
        }
        Log.d(TAG, "Cancelled all prayer alarms")
    }
}
