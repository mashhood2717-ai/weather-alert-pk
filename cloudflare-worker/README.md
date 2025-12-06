# Cloudflare Worker for Weather Alert FCM Notifications

This worker sends FCM push notifications when alerts are created from the admin portal.

## Setup Instructions

### 1. Get your FCM Server Key

1. Go to [Firebase Console](https://console.firebase.google.com/project/weather-alert-pk/settings/cloudmessaging)
2. Click on your project → Project Settings → Cloud Messaging
3. If you see "Cloud Messaging API (Legacy)" is disabled, click the three dots and enable it
4. Copy the **Server key** (starts with `AAAA...`)

### 2. Deploy the Worker

```bash
# Install Wrangler CLI (if not already installed)
npm install -g wrangler

# Login to Cloudflare
wrangler login

# Navigate to worker directory
cd cloudflare-worker

# Add your FCM Server Key as a secret
wrangler secret put FCM_SERVER_KEY
# Paste your server key when prompted

# Deploy the worker
wrangler deploy
```

### 3. Update Admin Portal

After deploying, you'll get a URL like:
```
https://weather-alert-fcm.YOUR_SUBDOMAIN.workers.dev
```

Update the `FCM_WORKER_URL` in `admin_portal/index.html`:
```javascript
const FCM_WORKER_URL = 'https://weather-alert-fcm.YOUR_SUBDOMAIN.workers.dev';
```

Then redeploy the admin portal:
```bash
firebase deploy --only hosting
```

### 4. Test

1. Open the app on your phone
2. Close the app completely
3. Send an alert from the admin portal
4. You should receive a push notification!

## Troubleshooting

### "Cloud Messaging API (Legacy)" not available
The legacy API might be deprecated. In that case, you need to use FCM HTTP v1 API which requires OAuth2 authentication. Contact support for help setting this up.

### CORS errors
The worker is configured to allow all origins. If you still see CORS errors, check the browser console for details.

### Notifications not received
1. Make sure the app has notification permissions
2. Check that the app is subscribed to `weather_alerts_pk` topic
3. Check Cloudflare Worker logs: `wrangler tail`
