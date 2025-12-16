# Travel Weather API - Cloudflare Worker

Batch fetches weather (WeatherAPI.com) and METAR (CheckWX) data for travel routes in a single request. This dramatically speeds up the travel weather screen by replacing multiple sequential API calls with one parallel batch request.

## Benefits

- **Single Request**: App makes 1 request instead of 10-20
- **Parallel Fetching**: Worker fetches all data simultaneously  
- **Edge Caching**: Cloudflare caches results globally
- **API Key Security**: Keys stay on server, not in app
- **10x Faster**: Load time drops from 10-15s to under 1s

## Deployment

### 1. Install Wrangler CLI
```bash
npm install -g wrangler
wrangler login
```

### 2. Set API Keys as Secrets
```bash
cd cloudflare-worker

# Set WeatherAPI.com key
wrangler secret put WEATHER_API_KEY -c wrangler-travel.toml
# Enter your key from https://www.weatherapi.com/

# Set CheckWX API key  
wrangler secret put CHECKWX_API_KEY -c wrangler-travel.toml
# Enter your key from https://www.checkwx.com/
```

### 3. Deploy
```bash
wrangler deploy -c wrangler-travel.toml
```

You'll get a URL like: `https://travel-weather-api.YOUR_SUBDOMAIN.workers.dev`

### 4. Update Flutter App

Edit `lib/services/travel_weather_service.dart`:

```dart
// Update these two lines:
static const String _workerUrl = 'https://travel-weather-api.YOUR_SUBDOMAIN.workers.dev';
static const bool _useWorker = true;
```

## API Reference

### POST /travel-weather

Fetch weather and METAR data for multiple points.

**Request:**
```json
{
  "points": [
    {"id": "toll_plaza_1", "lat": 33.6844, "lon": 73.0479},
    {"id": "toll_plaza_2", "lat": 33.5651, "lon": 72.8495},
    {"id": "toll_plaza_3", "lat": 33.4567, "lon": 72.7234}
  ],
  "icao_codes": ["OPIS", "OPLA"]
}
```

**Response:**
```json
{
  "weather": {
    "toll_plaza_1": {
      "id": "toll_plaza_1",
      "temp_c": 25.3,
      "condition": "Sunny",
      "icon": "//cdn.weatherapi.com/weather/64x64/day/113.png",
      "humidity": 45,
      "wind_kph": 12.5,
      "wind_dir": "NW",
      "feelslike_c": 24.8,
      "pressure_mb": 1015,
      "vis_km": 10,
      "uv": 5,
      "cloud": 20,
      "is_day": 1,
      "cached": false
    },
    "toll_plaza_2": { ... },
    "toll_plaza_3": { ... }
  },
  "metar": {
    "OPIS": {
      "icao": "OPIS",
      "raw_text": "METAR OPIS 150800Z 32005KT 9999 FEW040 25/10 Q1015",
      "temp_c": 25,
      "dewpoint_c": 10,
      "humidity": 38,
      "wind_kph": 9.3,
      "wind_degrees": 320,
      "visibility_km": 10,
      "pressure_hpa": 1015,
      "flight_category": "VFR",
      "clouds": [...],
      "cached": false
    },
    "OPLA": { ... }
  },
  "cached_at": "2025-12-15T10:30:00Z"
}
```

### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2025-12-15T10:30:00Z"
}
```

## Caching

| Data Type | Cache Duration |
|-----------|----------------|
| Weather   | 10 minutes     |
| METAR     | 20 minutes     |

Caching uses Cloudflare's Cache API at the edge for global performance.

## Error Handling

If a single point fails, the worker returns partial data with error info:

```json
{
  "weather": {
    "toll_plaza_1": { "temp_c": 25, ... },
    "toll_plaza_2": { "id": "toll_plaza_2", "error": "WeatherAPI error: 429" }
  }
}
```

The app should handle individual point errors gracefully.
