# Weather Alert Pakistan - AI Coding Instructions

## Project Overview
A Flutter weather app for Pakistan using multiple data sources: **WeatherAPI** (primary forecasts), **CheckWX METAR** (aviation weather), **Weather Underground PWS** (personal weather stations), and **Windy** (embedded wind maps).

## Architecture

### Data Flow
```
User Input (city/ICAO/location) → WeatherController → Multiple APIs → Models → UI
```

- **`WeatherController`** (`lib/services/weather_controller.dart`) is the central orchestrator—handles API calls, data merging, and METAR override logic
- METAR data can **override** WeatherAPI data when available for major Pakistani airports (ICAO lookup in `icaoFromCity()`)
- Weather Underground stations are city-mapped in `lib/wu_stations.dart`

### Key Services
| Service | API | Purpose |
|---------|-----|---------|
| `WeatherApiService` | WeatherAPI.com | Primary forecast (3-day, hourly) |
| `fetchMetar()` | CheckWX | Aviation METAR with 20-min cache |
| `fetchWUCurrentByStation()` | Weather Underground | PWS data with 10-min cache |

### API Keys
All API keys are in `lib/secrets.dart`. **Never commit real keys**—this file contains placeholders.

## Code Patterns

### Models
Plain Dart classes without factory constructors. Data is parsed in `WeatherController._parseWeather()`:
```dart
// lib/models/current_weather.dart pattern
class CurrentWeather {
  final String city;
  final double tempC;
  // ... required fields with named constructor
}
```

### Widgets
Widgets use **glassmorphism** with `BackdropFilter` and `ClipRRect`. Use `background_utils.dart` helpers:
```dart
final fg = foregroundForCard(isDay);  // Text color based on time
final tint = cardTint(isDay);         // Card background tint
```

All widgets accept `isDay` parameter for theme switching (day=light, night=dark).

### Icon Mapping
- WeatherAPI icons: use `weatherApiIconUrl(iconFile)` from `lib/utils/icon_mapper.dart`
- METAR codes: use `mapMetarIcon(code)` for icon file, `mapMetarCodeToDescription(code)` for Urdu descriptions

### Localization
METAR weather codes have Urdu descriptions in `metarDescriptions` map (`lib/utils/icon_mapper.dart`). Example:
```dart
"TSRA": "Bijli k saath barsaat (Thunderstorm with Rain)"
"FG": "Bohot ghari dhund (Fog)"
```
Follow this pattern when adding new weather condition descriptions.

### Null Safety
Use helper methods `_toD(v)` and `_toI(v)` in `WeatherController` for safe type conversion from JSON. Always handle `null` and `'--'` as fallback values.

## UI Structure (HomeScreen)
6 tabs in `TabController`:
1. **Home** - Current weather + tiles + sunrise/sunset + 3-day forecast
2. **Hourly** - Horizontal scroll of hourly forecasts
3. **Raw** - JSON debug view of `rawWeatherJson`
4. **Windy** - Embedded WebView map (dynamically updates lat/lon from current weather)
5. **METAR** - Aviation weather tile (requires ICAO search)
6. **WU** - Weather Underground station selector

### Windy Map Integration
The Windy embed URL is built dynamically in `_updateWindy()`:
```dart
final url = 'https://embed.windy.com/embed2.html?lat=$lat&lon=$lon&zoom=8&overlay=wind&level=surface&marker=true';
```
Coordinates come from `controller.current` or fall back to Pakistan center (30.0, 70.0).

## Commands
```bash
flutter pub get          # Install dependencies
flutter run              # Run on connected device
flutter analyze          # Static analysis
flutter build apk        # Build Android APK
```

## Common Tasks

### Adding a New Weather Parameter
1. Add field to appropriate model in `lib/models/`
2. Parse it in `WeatherController._parseWeather()`
3. Add to `getTilesForUI()` if it should show in tiles
4. Create/update widget in `lib/widgets/`

### Adding ICAO Airport Support
Add mapping in `WeatherController.icaoFromCity()`:
```dart
if (city.contains("NEWCITY")) return "ICAO";
```

### Adding Weather Underground Station
Add to `lib/wu_stations.dart` under appropriate city key.

## Dependencies
- `http` - API calls
- `geolocator` - Device location
- `webview_flutter` - Windy embed
- `collection` - Utility extensions
