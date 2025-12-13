/**
 * Firebase Cloud Functions for Weather Alert Pakistan
 * 
 * Sends push notifications when new alerts are created in Firestore
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

// Initialize Firebase Admin
initializeApp();

const db = getFirestore();
const messaging = getMessaging();

/**
 * Triggered when a new manual_alert is created in Firestore
 * Sends FCM notifications to users in the target area
 */
exports.sendAlertNotification = onDocumentCreated(
  "manual_alerts/{alertId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data in document");
      return null;
    }

    const alertData = snapshot.data();
    console.log("New alert created:", event.params.alertId, alertData);

    const { title, message, type, severity, location } = alertData;

    // Build the notification payload
    const notification = {
      title: title || "Weather Alert",
      body: message || "Check weather conditions in your area",
    };

    const data = {
      alertId: event.params.alertId,
      type: type || "weather",
      severity: severity || "medium",
      city: location?.city || "",
      lat: String(location?.lat || ""),
      lng: String(location?.lng || ""),
      mode: location?.mode || "radius",
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    };

    // Get users to notify based on location mode
    const usersToNotify = await getUsersInTargetArea(location);
    console.log(`Found ${usersToNotify.length} users in target area`);

    if (usersToNotify.length === 0) {
      // No users found in target area - do NOT fallback to topic
      // This ensures polygon/radius targeting is respected
      console.log("No users found in target area - alert not sent (respecting polygon/radius targeting)");
      return null;
    }

    // Send to specific users
    const tokens = usersToNotify
      .map((u) => u.fcmToken)
      .filter((t) => t && t.length > 0);

    if (tokens.length > 0) {
      console.log(`Sending to ${tokens.length} device tokens`);
      
      // Send in batches of 500 (FCM limit)
      const batchSize = 500;
      for (let i = 0; i < tokens.length; i += batchSize) {
        const batchTokens = tokens.slice(i, i + batchSize);
        try {
          const response = await messaging.sendEachForMulticast({
            tokens: batchTokens,
            notification: notification,
            data: data,
            android: {
              priority: "high",
              notification: {
                channelId: getChannelId(severity),
                priority: getPriority(severity),
                defaultSound: true,
                defaultVibrateTimings: true,
              },
            },
          });
          console.log(
            `Batch sent: ${response.successCount} success, ${response.failureCount} failed`
          );
        } catch (error) {
          console.error("Error sending batch:", error);
        }
      }
    }

    // Also send to topic for broader coverage
    try {
      await messaging.send({
        topic: "weather_alerts_pk",
        notification: notification,
        data: data,
        android: {
          priority: "high",
          notification: {
            channelId: getChannelId(severity),
            priority: getPriority(severity),
            defaultSound: true,
            defaultVibrateTimings: true,
          },
        },
      });
      console.log("Also sent to topic for broader coverage");
    } catch (error) {
      console.error("Error sending to topic:", error);
    }

    // Update alert status to 'sent'
    try {
      await snapshot.ref.update({
        status: "sent",
        sentAt: new Date(),
        recipientCount: usersToNotify.length,
      });
    } catch (error) {
      console.error("Error updating alert status:", error);
    }

    return null;
  }
);

/**
 * Get users within the target area based on location mode
 */
async function getUsersInTargetArea(location) {
  if (!location) return [];

  const usersRef = db.collection("user_locations");
  const users = [];

  try {
    const snapshot = await usersRef.get();

    for (const doc of snapshot.docs) {
      const userData = doc.data();
      if (!userData.lat || !userData.lng) continue;

      let isInArea = false;

      if (location.mode === "polygon" && location.polygon) {
        // Check if user is inside polygon
        isInArea = isPointInPolygon(
          userData.lat,
          userData.lng,
          location.polygon
        );
      } else if (location.mode === "radius" && location.lat && location.lng) {
        // Check if user is within radius
        const distance = getDistanceKm(
          location.lat,
          location.lng,
          userData.lat,
          userData.lng
        );
        isInArea = distance <= (location.radius || 50);
      } else {
        // Default: include all users
        isInArea = true;
      }

      if (isInArea) {
        users.push({
          id: doc.id,
          fcmToken: userData.fcmToken,
          lat: userData.lat,
          lng: userData.lng,
        });
      }
    }
  } catch (error) {
    console.error("Error getting users:", error);
  }

  return users;
}

/**
 * Check if a point is inside a polygon using ray casting algorithm
 */
function isPointInPolygon(lat, lng, polygon) {
  if (!polygon || polygon.length < 3) return false;

  let inside = false;
  const n = polygon.length;

  for (let i = 0, j = n - 1; i < n; j = i++) {
    const xi = polygon[i].lat || polygon[i][0];
    const yi = polygon[i].lng || polygon[i][1];
    const xj = polygon[j].lat || polygon[j][0];
    const yj = polygon[j].lng || polygon[j][1];

    const intersect =
      yi > lng !== yj > lng && lat < ((xj - xi) * (lng - yi)) / (yj - yi) + xi;

    if (intersect) inside = !inside;
  }

  return inside;
}

/**
 * Calculate distance between two points in kilometers using Haversine formula
 */
function getDistanceKm(lat1, lng1, lat2, lng2) {
  const R = 6371; // Earth's radius in km
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(deg) {
  return deg * (Math.PI / 180);
}

/**
 * Get notification channel ID based on severity
 */
function getChannelId(severity) {
  switch (severity?.toLowerCase()) {
    case "extreme":
    case "high":
      return "weather_alerts_high";
    case "medium":
      return "weather_alerts_medium";
    case "low":
    default:
      return "weather_alerts_low";
  }
}

/**
 * Get notification priority based on severity
 */
function getPriority(severity) {
  switch (severity?.toLowerCase()) {
    case "extreme":
    case "high":
      return "max";
    case "medium":
      return "high";
    case "low":
    default:
      return "default";
  }
}
