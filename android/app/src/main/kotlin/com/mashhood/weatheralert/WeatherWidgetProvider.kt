package com.mashhood.weatheralert

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.*

class WeatherWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_REFRESH = "com.mashhood.weatheralert.WIDGET_REFRESH"
        const val PREFS_NAME = "WeatherWidgetPrefs"
        
        // Data keys
        const val KEY_CITY = "widget_city"
        const val KEY_TEMP = "widget_temp"
        const val KEY_CONDITION = "widget_condition"
        const val KEY_FEELS_LIKE = "widget_feels_like"
        const val KEY_HUMIDITY = "widget_humidity"
        const val KEY_WIND = "widget_wind"
        const val KEY_UV = "widget_uv"
        const val KEY_IS_DAY = "widget_is_day"
        const val KEY_NEXT_PRAYER = "widget_next_prayer"
        const val KEY_NEXT_PRAYER_TIME = "widget_next_prayer_time"
        const val KEY_FAJR = "widget_fajr"
        const val KEY_DHUHR = "widget_dhuhr"
        const val KEY_ASR = "widget_asr"
        const val KEY_MAGHRIB = "widget_maghrib"
        const val KEY_ISHA = "widget_isha"
        const val KEY_LAST_UPDATE = "widget_last_update"

        fun updateWidget(context: Context) {
            val intent = Intent(context, WeatherWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            }
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val widgetComponent = ComponentName(context, WeatherWidgetProvider::class.java)
            val widgetIds = appWidgetManager.getAppWidgetIds(widgetComponent)
            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
            context.sendBroadcast(intent)
        }

        fun saveWidgetData(
            context: Context,
            city: String?,
            temp: String?,
            condition: String?,
            feelsLike: String?,
            humidity: String?,
            wind: String?,
            uv: String?,
            isDay: Boolean,
            nextPrayer: String?,
            nextPrayerTime: String?,
            fajr: String?,
            dhuhr: String?,
            asr: String?,
            maghrib: String?,
            isha: String?
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()
            
            city?.let { editor.putString(KEY_CITY, it) }
            temp?.let { editor.putString(KEY_TEMP, it) }
            condition?.let { editor.putString(KEY_CONDITION, it) }
            feelsLike?.let { editor.putString(KEY_FEELS_LIKE, it) }
            humidity?.let { editor.putString(KEY_HUMIDITY, it) }
            wind?.let { editor.putString(KEY_WIND, it) }
            uv?.let { editor.putString(KEY_UV, it) }
            editor.putBoolean(KEY_IS_DAY, isDay)
            nextPrayer?.let { editor.putString(KEY_NEXT_PRAYER, it) }
            nextPrayerTime?.let { editor.putString(KEY_NEXT_PRAYER_TIME, it) }
            fajr?.let { editor.putString(KEY_FAJR, it) }
            dhuhr?.let { editor.putString(KEY_DHUHR, it) }
            asr?.let { editor.putString(KEY_ASR, it) }
            maghrib?.let { editor.putString(KEY_MAGHRIB, it) }
            isha?.let { editor.putString(KEY_ISHA, it) }
            
            val sdf = SimpleDateFormat("hh:mm a", Locale.getDefault())
            editor.putString(KEY_LAST_UPDATE, "Updated ${sdf.format(Date())}")
            
            editor.apply()
            
            // Trigger widget update
            updateWidget(context)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        if (intent.action == ACTION_REFRESH) {
            try {
                // Send refresh request to Flutter (may fail if app not running)
                MainActivity.sendWidgetRefreshEvent()
            } catch (e: Exception) {
                // App might not be running, ignore
            }
            
            // Update widget to show refreshing state
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val widgetComponent = ComponentName(context, WeatherWidgetProvider::class.java)
            val widgetIds = appWidgetManager.getAppWidgetIds(widgetComponent)
            
            for (widgetId in widgetIds) {
                try {
                    val views = RemoteViews(context.packageName, R.layout.widget_weather)
                    views.setTextViewText(R.id.widget_updated, "Refreshing...")
                    appWidgetManager.updateAppWidget(widgetId, views)
                } catch (e: Exception) {
                    // Ignore widget update errors
                }
            }
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.widget_weather)
            
            // Load data from SharedPreferences
            val city = prefs.getString(KEY_CITY, "Tap to load")
            val temp = prefs.getString(KEY_TEMP, "--°")
            val condition = prefs.getString(KEY_CONDITION, "--")
            val feelsLike = prefs.getString(KEY_FEELS_LIKE, "Feels like --°")
            val humidity = prefs.getString(KEY_HUMIDITY, "--%")
            val wind = prefs.getString(KEY_WIND, "-- km/h")
            val uv = prefs.getString(KEY_UV, "--")
            val isDay = prefs.getBoolean(KEY_IS_DAY, true)
            val nextPrayer = prefs.getString(KEY_NEXT_PRAYER, "--")
            val nextPrayerTime = prefs.getString(KEY_NEXT_PRAYER_TIME, "--:--")
            val fajr = prefs.getString(KEY_FAJR, "--:--")
            val dhuhr = prefs.getString(KEY_DHUHR, "--:--")
            val asr = prefs.getString(KEY_ASR, "--:--")
            val maghrib = prefs.getString(KEY_MAGHRIB, "--:--")
            val isha = prefs.getString(KEY_ISHA, "--:--")
            val lastUpdate = prefs.getString(KEY_LAST_UPDATE, "Tap to open app")
            
            // Set background based on day/night
            val bgRes = if (isDay) R.drawable.widget_background else R.drawable.widget_background_night
            views.setInt(R.id.widget_container, "setBackgroundResource", bgRes)
            
            // Update all text views
            views.setTextViewText(R.id.widget_city, city)
            views.setTextViewText(R.id.widget_temp, temp)
            views.setTextViewText(R.id.widget_condition, condition)
            views.setTextViewText(R.id.widget_feels_like, feelsLike)
            views.setTextViewText(R.id.widget_humidity, humidity)
            views.setTextViewText(R.id.widget_wind, wind)
            views.setTextViewText(R.id.widget_uv, uv)
            views.setTextViewText(R.id.widget_next_prayer, nextPrayer)
            views.setTextViewText(R.id.widget_next_prayer_time, nextPrayerTime)
            views.setTextViewText(R.id.widget_fajr, fajr)
            views.setTextViewText(R.id.widget_dhuhr, dhuhr)
            views.setTextViewText(R.id.widget_asr, asr)
            views.setTextViewText(R.id.widget_maghrib, maghrib)
            views.setTextViewText(R.id.widget_isha, isha)
            views.setTextViewText(R.id.widget_updated, lastUpdate)
            
            // Click on widget opens app
            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openAppPendingIntent = PendingIntent.getActivity(
                context, 0, openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_container, openAppPendingIntent)
            
            // Refresh button click
            val refreshIntent = Intent(context, WeatherWidgetProvider::class.java).apply {
                action = ACTION_REFRESH
            }
            val refreshPendingIntent = PendingIntent.getBroadcast(
                context, 1, refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_refresh, refreshPendingIntent)
            
            // Update the widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Exception) {
            // Log error but don't crash
            android.util.Log.e("WeatherWidget", "Error updating widget: ${e.message}")
        }
    }
}
