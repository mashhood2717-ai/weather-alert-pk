/**
 * Cloudflare Worker for Weather Alert Pakistan
 * Sends FCM push notifications using HTTP v1 API with Service Account
 * 
 * Environment Variables needed:
 * - FCM_CLIENT_EMAIL: firebase-adminsdk-fbsvc@weather-alert-pk.iam.gserviceaccount.com
 * - FCM_PRIVATE_KEY: The private key from service account JSON
 */

const FCM_URL = 'https://fcm.googleapis.com/v1/projects/weather-alert-pk/messages:send';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';

export default {
  async fetch(request, env) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: corsHeaders(),
      });
    }

    // Only allow POST requests
    if (request.method !== 'POST') {
      return jsonResponse({ error: 'Method not allowed' }, 405);
    }

    try {
      const body = await request.json();
      
      // Validate required fields
      if (!body.title || !body.message) {
        return jsonResponse({ error: 'Missing title or message' }, 400);
      }

      // Get OAuth2 access token
      const accessToken = await getAccessToken(env);
      
      if (!accessToken) {
        return jsonResponse({ error: 'Failed to get access token' }, 500);
      }

      // Build FCM v1 payload with high priority for background delivery
      const fcmPayload = {
        message: {
          // Use token if provided, otherwise use topic
          ...(body.token ? { token: body.token } : { topic: body.topic || 'weather_alerts_pk' }),
          notification: {
            title: body.title,
            body: body.message,
          },
          android: {
            priority: 'high',
            ttl: '86400s',
            notification: {
              channel_id: 'weather_alerts_channel',
              sound: 'default',
              default_vibrate_timings: true,
              notification_priority: 'PRIORITY_MAX',
              visibility: 'PUBLIC',
              icon: 'ic_launcher',
            },
            direct_boot_ok: true,
          },
          data: {
            alertId: body.alertId || Date.now().toString(),
            type: body.type || 'weather',
            severity: body.severity || 'medium',
            city: body.city || '',
            lat: String(body.lat || ''),
            lng: String(body.lng || ''),
            mode: body.mode || 'radius',
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
            title: body.title,
            message: body.message,
          },
        },
      };

      // Send to FCM
      const fcmResponse = await fetch(FCM_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
        body: JSON.stringify(fcmPayload),
      });

      const fcmResult = await fcmResponse.json();

      if (!fcmResponse.ok) {
        console.error('FCM Error:', fcmResult);
        return jsonResponse({ 
          error: 'FCM send failed', 
          details: fcmResult 
        }, 500);
      }

      return jsonResponse({ 
        success: true, 
        message: 'Notification sent successfully',
        messageId: fcmResult.name
      }, 200);

    } catch (error) {
      console.error('Worker error:', error);
      return jsonResponse({ 
        error: 'Internal server error', 
        message: error.message 
      }, 500);
    }
  },
};

// Get OAuth2 access token using service account
async function getAccessToken(env) {
  try {
    const now = Math.floor(Date.now() / 1000);
    const expiry = now + 3600; // 1 hour

    // Create JWT header and payload
    const header = {
      alg: 'RS256',
      typ: 'JWT',
    };

    const payload = {
      iss: env.FCM_CLIENT_EMAIL,
      sub: env.FCM_CLIENT_EMAIL,
      aud: TOKEN_URL,
      iat: now,
      exp: expiry,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
    };

    // Sign JWT
    const jwt = await signJWT(header, payload, env.FCM_PRIVATE_KEY);

    // Exchange JWT for access token
    const tokenResponse = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    });

    const tokenData = await tokenResponse.json();
    
    if (!tokenResponse.ok) {
      console.error('Token error:', JSON.stringify(tokenData));
      return null;
    }

    return tokenData.access_token;
  } catch (error) {
    console.error('getAccessToken error:', error.message, error.stack);
    return null;
  }
}

// Sign JWT using RS256
async function signJWT(header, payload, privateKeyPem) {
  try {
    // Encode header and payload
    const encodedHeader = base64urlEncode(JSON.stringify(header));
    const encodedPayload = base64urlEncode(JSON.stringify(payload));
    const signatureInput = `${encodedHeader}.${encodedPayload}`;

    // Import private key
    const privateKey = await importPrivateKey(privateKeyPem);

    // Sign
    const signature = await crypto.subtle.sign(
      { name: 'RSASSA-PKCS1-v1_5' },
      privateKey,
      new TextEncoder().encode(signatureInput)
    );

    const encodedSignature = base64urlEncode(signature);
    return `${signatureInput}.${encodedSignature}`;
  } catch (error) {
    console.error('signJWT error:', error.message);
    throw error;
  }
}

// Import PEM private key
async function importPrivateKey(pem) {
  try {
    // Handle escaped newlines from environment variable
    let pemNormalized = pem;
    if (pem.includes('\\n')) {
      pemNormalized = pem.replace(/\\n/g, '\n');
    }
    
    // Remove PEM headers and all whitespace
    const pemContents = pemNormalized
      .replace(/-----BEGIN PRIVATE KEY-----/, '')
      .replace(/-----END PRIVATE KEY-----/, '')
      .replace(/[\r\n\s]/g, '')
      .trim();

    // Decode base64
    const binaryString = atob(pemContents);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    // Import key
    return await crypto.subtle.importKey(
      'pkcs8',
      bytes.buffer,
      {
        name: 'RSASSA-PKCS1-v1_5',
        hash: 'SHA-256',
      },
      false,
      ['sign']
    );
  } catch (error) {
    console.error('importPrivateKey error:', error.message);
    throw error;
  }
}

// Base64url encode
function base64urlEncode(input) {
  let base64;
  if (typeof input === 'string') {
    base64 = btoa(input);
  } else {
    // ArrayBuffer
    const bytes = new Uint8Array(input);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    base64 = btoa(binary);
  }
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders(),
    },
  });
}

function getChannelId(severity) {
  switch (severity?.toLowerCase()) {
    case 'extreme':
    case 'high':
      return 'weather_alerts_high';
    case 'medium':
      return 'weather_alerts_medium';
    case 'low':
    default:
      return 'weather_alerts_low';
  }
}

function getPriority(severity) {
  switch (severity?.toLowerCase()) {
    case 'extreme':
    case 'high':
      return 'PRIORITY_MAX';
    case 'medium':
      return 'PRIORITY_HIGH';
    case 'low':
    default:
      return 'PRIORITY_DEFAULT';
  }
}
