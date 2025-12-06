package com.mashhood.weatheralert

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Receives boot completed broadcast to ensure FCM can deliver
 * notifications after device restart.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            Log.d("BootReceiver", "Boot completed - FCM ready to receive notifications")
            // FCM will automatically reconnect after boot
            // No additional action needed here
        }
    }
}
