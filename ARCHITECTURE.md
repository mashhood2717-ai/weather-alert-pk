# Weather Alert Pakistan - Technical Architecture

> **Version:** 1.1.19+20  
> **Last Updated:** December 2025

## Overview

Weather Alert Pakistan is a Flutter-based weather application for Pakistan that combines multiple weather data sources, Islamic prayer times, and real-time navigation features. The app uses a hybrid architecture with Flutter for UI and native Android (Kotlin) for system-level features.

---

## Tech Stack Summary

| Layer | Technology |
|-------|------------|
| **Frontend** | Flutter 3.x (Dart) |
| **Native Android** | Kotlin |
| **Backend** | Firebase (Firestore, FCM, Functions) |
| **Serverless** | Cloudflare Workers |
| **Maps** | Google Maps Flutter SDK |
| **Navigation** | Google Directions REST API |
| **Weather Data** | Open-Meteo, CheckWX METAR, Weather Underground |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        FLUTTER APP                               │
├──────────────┬──────────────┬──────────────┬───────────────────┤
│   Screens    │   Services   │   Models     │   Widgets         │
├──────────────┼──────────────┼──────────────┼───────────────────┤
│ HomeScreen   │ WeatherCtrl  │ CurrentWx    │ CurrentWeatherTile│
│ TravelWx     │ TravelWxSvc  │ HourlyWx     │ ForecastTile      │
│ Alerts       │ NotifSvc     │ DailyWx      │ PrayerWidget      │
│ Settings     │ PrayerSvc    │ MetarData    │ MetarTile         │
│ Onboarding   │ UserSvc      │ MotorwayPt   │ AqiWidget         │
│ AdminPortal  │ GeocodingSvc │ WeatherAlert │ SunWidget         │
└──────────────┴──────────────┴──────────────┴───────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
    ┌──────────┐       ┌──────────────┐     ┌──────────┐
    │ Firebase │       │  REST APIs   │     │  Native  │
    │ Backend  │       │  (Weather)   │     │ Android  │
    └──────────┘       └──────────────┘     └──────────┘
```

---

## Platform Channels (Flutter ↔ Native Android)

The app uses **4 MethodChannels** for Flutter-to-Kotlin communication:

| Channel Name | Purpose |
|-------------|---------|
| `com.mashhood.weatheralert/persistent_notification` | Persistent notification control |
| `com.mashhood.weatheralert/widget` | Home screen widget updates |
| `com.mashhood.weatheralert/settings` | Open system settings (alarm permissions) |
| `com.mashhood.weatheralert/prayer_alarm` | Native AlarmManager for prayer times |

### Example Usage

**Dart Side:**
```dart
const platform = MethodChannel('com.mashhood.weatheralert/prayer_alarm');
await platform.invokeMethod('schedulePrayerAlarm', {
  'prayerName': 'Fajr',
  'triggerTimeMillis': timestamp,
  'notificationId': 2001,
  'useAzan': true,
});
```

**Kotlin Side (MainActivity.kt):**
```kotlin
prayerChannel?.setMethodCallHandler { call, result ->
    when (call.method) {
        "schedulePrayerAlarm" -> {
            val prayerName = call.argument<String>("prayerName")
            PrayerAlarmScheduler.schedulePrayerAlarm(...)
            result.success(true)
        }
    }
}
```

---

## Google Services

| SDK/API | Type | Purpose |
|---------|------|---------|
| `google_maps_flutter` | **Flutter SDK** | Map display in Travel Weather screen |
| Google Directions API | **REST HTTP** | Route polylines, turn-by-turn navigation |
| Google Geocoding API | **REST HTTP** | City name → coordinates lookup |
| Google Places API | **REST HTTP** | Location search/autocomplete |

### Important Note
The app uses the **Directions REST API** (HTTP calls), NOT the Google Navigation SDK. This is significantly cheaper:
- Directions API: ~$5 per 1,000 requests
- Navigation SDK: ~$0.05 per user per month minimum

---

## Firebase Services

| Service | Purpose |
|---------|---------|
| **Firebase Core** | Base initialization |
| **Cloud Firestore** | User data, road alerts, manual weather alerts |
| **Firebase Messaging (FCM)** | Push notifications for weather alerts |
| **Firebase Cloud Functions** | Server-side alert broadcasting (optional) |

### Firestore Collections
- `users` - User profiles and FCM tokens
- `road_alerts` - Live road condition updates
- `manual_alerts` - Admin-created weather alerts

---

## Weather Data Sources

| API | Purpose | Cache Duration |
|-----|---------|----------------|
| **Open-Meteo** | Primary weather forecasts (FREE) | 15 minutes |
| **CheckWX METAR** | Aviation weather for airports | 20 minutes |
| **Weather Underground PWS** | Personal weather stations | 10 minutes |
| **WeatherAPI.com** | Backup/alternative data | 15 minutes |

### Data Flow
```
User Input (city/ICAO/location)
         ↓
   WeatherController
         ↓
   ┌─────┴─────┐
   ▼           ▼
Open-Meteo   METAR API
   ↓           ↓
   └─────┬─────┘
         ▼
   Merge/Override Logic
   (METAR overrides when available)
         ↓
   CurrentWeather Model
         ↓
   UI Widgets
```

---

## Real-time Features

The app uses **Dart Streams** for real-time updates (NOT WebSockets):

| Stream | Source | Purpose |
|--------|--------|---------|
| `Geolocator.getPositionStream()` | GPS | Real-time navigation tracking |
| `Firestore.snapshots()` | Firebase | Live road alerts ticker |

### Navigation Real-time Updates
- GPS updates: 10 Hz (100ms intervals) during navigation
- Position smoothing with low-pass filter for 60fps animation
- Road snapping for accurate route following

---

## Native Android Features

| Feature | Implementation | File |
|---------|----------------|------|
| **AlarmManager** | Exact alarms for prayer times | `PrayerAlarmScheduler.kt` |
| **MediaPlayer** | Azan audio playback | `AzanService.kt` |
| **BroadcastReceiver** | Receives alarm intents | `PrayerAlarmReceiver.kt` |
| **Home Screen Widget** | Weather widget | `WeatherWidget.kt` |
| **Foreground Service** | Persistent notification | `PersistentNotificationService.kt` |

---

## Local Storage

| Storage | Purpose |
|---------|---------|
| `SharedPreferences` | Settings, cached weather, user preferences |
| Local JSON cache | Weather data for offline access |
| METAR cache | 20-minute cache for aviation data |

---

## Cloudflare Worker

A serverless Cloudflare Worker handles FCM push notifications:
- Uses Google OAuth2 for FCM HTTP v1 API authentication
- Bypasses CORS for browser-based admin portal
- Located in `cloudflare-worker/worker.js`

---

## Project Structure

```
lib/
├── main.dart                 # Entry point, Firebase init
├── app.dart                  # MaterialApp configuration
├── secrets.dart              # API keys (gitignored)
├── firebase_options.dart     # Firebase configuration
├── models/
│   ├── current_weather.dart  # Current weather data model
│   ├── hourly_weather.dart   # Hourly forecast model
│   ├── daily_weather.dart    # Daily forecast model
│   ├── metar_data.dart       # Aviation METAR data model
│   ├── motorway_point.dart   # Navigation waypoint model
│   └── weather_alert.dart    # Push notification alert model
├── screens/
│   ├── home_screen.dart      # Main weather display (6 tabs)
│   ├── travel_weather_screen.dart  # Navigation & travel weather
│   ├── alerts_screen.dart    # Notification history
│   ├── settings_screen.dart  # App settings
│   ├── onboarding_screen.dart # First-time setup
│   └── admin_portal_screen.dart # Admin alert management
├── services/
│   ├── weather_controller.dart    # Central weather orchestrator
│   ├── travel_weather_service.dart # Navigation & route weather
│   ├── notification_service.dart  # FCM & local notifications
│   ├── prayer_service.dart        # Prayer time calculations
│   ├── user_service.dart          # User ID & tracking
│   ├── geocoding_service.dart     # Location search
│   ├── location_service.dart      # GPS management
│   ├── open_meteo_service.dart    # Open-Meteo API
│   ├── metar_service.dart         # CheckWX METAR API
│   ├── wu_service.dart            # Weather Underground API
│   ├── aqi_service.dart           # Air quality data
│   ├── widget_service.dart        # Home screen widget updates
│   └── ... (21 services total)
├── utils/
│   └── icon_mapper.dart      # Weather icon & description mapping
└── widgets/
    ├── current_weather_tile.dart
    ├── forecast_tile.dart
    ├── hourly_tile.dart
    ├── prayer_widget.dart
    ├── metar_tile.dart
    ├── aqi_widget.dart
    ├── sun_widget.dart
    └── ... (10 widgets total)

android/app/src/main/kotlin/com/mashhood/weatheralert/
├── MainActivity.kt           # MethodChannel handlers
├── PrayerAlarmReceiver.kt    # BroadcastReceiver for alarms
├── PrayerAlarmScheduler.kt   # AlarmManager wrapper
├── WeatherWidget.kt          # Home screen widget provider
├── WeatherWidgetReceiver.kt  # Widget update receiver
└── AzanService.kt            # Foreground service for azan

functions/
├── index.js                  # Firebase Cloud Functions
└── package.json

cloudflare-worker/
├── worker.js                 # FCM notification worker
├── travel-weather-worker.js  # Travel weather proxy
└── wrangler.toml             # Cloudflare config
```

---

## Dependencies

### Flutter Packages
```yaml
dependencies:
  flutter: sdk
  http: ^1.2.0                    # REST API calls
  geolocator: ^12.0.0             # GPS location
  webview_flutter: ^4.8.0         # Embedded web views (Windy map)
  firebase_core: ^4.2.1           # Firebase base
  firebase_messaging: ^16.0.4     # Push notifications
  cloud_firestore: ^6.1.0         # Real-time database
  flutter_local_notifications: ^19.5.0  # Local notifications
  shared_preferences: ^2.5.3      # Local storage
  google_maps_flutter: ^2.5.3     # Maps display
  adhan: ^2.0.0+1                 # Islamic prayer times
  timezone: ^0.10.1               # Timezone handling
  home_widget: ^0.8.1             # Home screen widgets
  device_info_plus: ^12.3.0       # Device information
  permission_handler: ^11.3.1     # Runtime permissions
```

---

## What This App Does NOT Use

| Technology | Status | Reason |
|------------|--------|--------|
| WebSockets | ❌ | Firebase handles real-time |
| GraphQL | ❌ | Simple REST is sufficient |
| Redux/Bloc/Provider | ❌ | Simple setState + ValueNotifier |
| SQLite/Hive | ❌ | SharedPreferences is enough |
| Google Navigation SDK | ❌ | Too expensive, using Directions API |
| gRPC | ❌ | Not needed |

---

## API Cost Estimation (10,000 Users)

| API | Usage | Monthly Cost |
|-----|-------|--------------|
| Google Directions | ~100k requests | ~$300 (after $200 free credit) |
| Google Maps Display | Unlimited | Free (mobile SDK) |
| Open-Meteo | Unlimited | Free |
| CheckWX METAR | ~50k requests | Free tier |
| Firebase Firestore | ~1M reads | ~$0.36 |
| Firebase FCM | Unlimited | Free |

**Total Estimated Cost: ~$300-500/month for 10,000 active users**

---

## Key Architectural Decisions

1. **Hybrid Flutter + Native**: System-level features (alarms, widgets) require native code
2. **Multi-source Weather**: Redundancy and specialized data (aviation METAR)
3. **REST over SDK**: Google Directions API is 10x cheaper than Navigation SDK
4. **Firebase for Real-time**: Simpler than managing WebSocket connections
5. **Cloudflare Workers**: Serverless FCM without managing servers
6. **Caching Strategy**: Aggressive caching to reduce API costs

---

## Commands

```bash
# Install dependencies
flutter pub get

# Run on Android device
flutter run

# Run on Chrome (web - limited features)
flutter run -d chrome

# Build release APK
flutter build apk --release

# Analyze code
flutter analyze

# Deploy Firebase Functions
cd functions && npm run deploy

# Deploy Cloudflare Worker
cd cloudflare-worker && wrangler deploy
```

---

## Contact

For technical questions about this architecture, refer to this document or the inline code comments.
