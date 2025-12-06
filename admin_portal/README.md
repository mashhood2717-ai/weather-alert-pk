# Weather Alert Pakistan - Admin Portal

A web-based admin portal for sending manual weather alerts to app users with location-based targeting.

## Features

- 🗺️ **Interactive Map**: Click anywhere in Pakistan to set alert location
- 📍 **Quick City Selection**: One-click access to major Pakistani cities
- 🎯 **Radius Control**: Set coverage area from 5km to 100km
- ⚡ **Multiple Alert Types**: Rain, heat, cold, storm, wind, fog, dust, snow
- 🚨 **Severity Levels**: Low, Medium, High, Extreme
- 📱 **Real-time Delivery**: Alerts pushed to app users within radius

## How It Works

1. **Admin sends alert** → Alert saved to Firestore `manual_alerts` collection
2. **App listens** → `ManualAlertService` listens for new alerts in real-time
3. **Location check** → App checks if user is within alert radius:
   - By GPS location (if available)
   - By subscribed cities (fallback)
4. **Notification shown** → Local notification displayed to matching users

## Deployment

### Option 1: Firebase Hosting (Recommended)

```bash
# Login to Firebase
firebase login

# Deploy hosting and Firestore rules
firebase deploy --only hosting,firestore
```

Portal will be available at: `https://weather-alert-pk.web.app`

### Option 2: Local Testing

Simply open `index.html` in a browser. Note: Firestore writes will still go to your production database.

## Setup Requirements

1. **Enable Firestore** in Firebase Console
2. **Deploy Firestore Rules** (`firestore.rules`)
3. **Create Firestore Index** (may be auto-created on first query):
   - Collection: `manual_alerts`
   - Fields: `timestamp` (Descending)

## Alert Data Structure

```javascript
{
  title: "Heavy Rain Warning",
  message: "Expected flooding in low-lying areas...",
  type: "rain",           // rain, heat, cold, storm, wind, fog, dust, snow, other
  severity: "high",       // low, medium, high, extreme
  location: {
    lat: 33.6844,
    lng: 73.0479,
    city: "Islamabad",
    radius: 25            // km
  },
  timestamp: ServerTimestamp,
  sentBy: "admin",
  status: "pending"
}
```

## Security (TODO)

Currently the portal has no authentication. To secure it:

1. Add Firebase Authentication
2. Update Firestore rules:
   ```javascript
   match /manual_alerts/{alertId} {
     allow read: if true;
     allow write: if request.auth != null && request.auth.token.admin == true;
   }
   ```
3. Set admin claims via Firebase Admin SDK

## Targeting Methods

### 1. GPS-Based (Primary)
- App registers user location in `user_locations` collection
- Haversine formula calculates distance to alert center
- Users within radius receive the alert

### 2. City-Based (Fallback)
- If GPS unavailable, checks user's subscribed cities
- Matches alert city name against subscription list

## Future Enhancements

- [ ] Admin authentication
- [ ] Alert scheduling (send at specific time)
- [ ] Alert expiry (auto-dismiss after duration)
- [ ] Delivery tracking (see how many users received)
- [ ] Multi-language support (Urdu, English)
- [ ] Alert templates for common scenarios
