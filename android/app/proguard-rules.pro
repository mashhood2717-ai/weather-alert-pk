# ==================== APP-SPECIFIC CLASSES ====================
# Keep all app native classes
-keep class com.mashhood.weatheralert.** { *; }

# Keep PrayerAlarmReceiver and related classes (redundant but explicit)
-keep class com.mashhood.weatheralert.PrayerAlarmReceiver { *; }
-keep class com.mashhood.weatheralert.PrayerAlarmScheduler { *; }
-keep class com.mashhood.weatheralert.BootReceiver { *; }
-keep class com.mashhood.weatheralert.MainActivity { *; }
-keep class com.mashhood.weatheralert.PersistentNotificationService { *; }
-keep class com.mashhood.weatheralert.WeatherWidgetProvider { *; }

# ==================== ANDROID FRAMEWORK ====================
# Keep MediaPlayer related classes
-keep class android.media.MediaPlayer { *; }
-keep class android.media.AudioAttributes { *; }
-keep class android.media.AudioAttributes$Builder { *; }
-keep class android.media.AudioManager { *; }

# Keep BroadcastReceiver classes
-keep class * extends android.content.BroadcastReceiver { *; }

# Keep Service classes
-keep class * extends android.app.Service { *; }

# Keep NotificationManager and related
-keep class android.app.NotificationManager { *; }
-keep class android.app.NotificationChannel { *; }
-keep class androidx.core.app.NotificationCompat { *; }
-keep class androidx.core.app.NotificationCompat$** { *; }

# Keep PowerManager for wake locks
-keep class android.os.PowerManager { *; }
-keep class android.os.PowerManager$WakeLock { *; }

# Keep AlarmManager
-keep class android.app.AlarmManager { *; }
-keep class android.app.AlarmManager$AlarmClockInfo { *; }

# Keep PendingIntent
-keep class android.app.PendingIntent { *; }

# ==================== FLUTTER ====================
# Don't obfuscate Flutter plugin method channels
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep raw resources (like azan.mp3)
-keep class **.R { *; }
-keep class **.R$* { *; }

# ==================== FIREBASE ====================
# Firebase Messaging
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ==================== GEOLOCATOR ====================
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# ==================== WEBVIEW ====================
-keep class io.flutter.plugins.webviewflutter.** { *; }
-dontwarn io.flutter.plugins.webviewflutter.**

# ==================== GOOGLE MAPS ====================
-keep class com.google.android.gms.maps.** { *; }
-keep class com.google.maps.** { *; }
-dontwarn com.google.android.gms.maps.**

# ==================== PERMISSION HANDLER ====================
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# ==================== JSON / SERIALIZATION ====================
# Keep Gson classes if used
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# ==================== PLAY CORE (not used but referenced) ====================
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ==================== GENERAL RULES ====================
# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Parcelables
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep enum values
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Prevent stripping of methods/classes annotated with @Keep
-keep class androidx.annotation.Keep
-keep @androidx.annotation.Keep class * {*;}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <fields>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <init>(...);
}

# ==================== DEBUG (remove in production if needed) ====================
# Keep line numbers for stack traces
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
