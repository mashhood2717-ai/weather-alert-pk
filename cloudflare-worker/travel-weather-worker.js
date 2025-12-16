/**
 * Cloudflare Worker for Travel Weather - Batch API
 * Pre-fetches weather + METAR and stores in KV for instant loading
 * 
 * Environment Variables needed:
 * - WEATHER_API_KEY: Your WeatherAPI.com key
 * - CHECKWX_API_KEY: Your CheckWX API key
 * 
 * KV Namespace needed:
 * - METAR_CACHE: For storing pre-fetched Pakistan METAR and Weather data
 * 
 * Cron Schedule:
 * - METAR: Every 15 minutes
 * - WeatherAPI for toll plazas: Every 30 minutes
 * 
 * Deploy: wrangler deploy -c wrangler-travel.toml
 */

const WEATHER_API_URL = 'https://api.weatherapi.com/v1/current.json';
const CHECKWX_API_URL = 'https://api.checkwx.com/metar';

// Cache TTL in seconds
const METAR_CACHE_TTL = 1200;   // 20 minutes (METAR refreshes every 15 min)
const WEATHER_CACHE_TTL = 2100; // 35 minutes (Weather refreshes every 30 min)

// Pakistan major airports with their coordinates and radius
// OPIS = Islamabad (Benazir Bhutto) - better for M1/M2 motorway coverage
const PAKISTAN_AIRPORTS = {
  'OPPS': { name: 'Peshawar', lat: 33.9939, lon: 71.5147, radius: 30 },
  'OPIS': { name: 'Islamabad', lat: 33.5605, lon: 72.8495, radius: 40 },
  'OPFA': { name: 'Faisalabad', lat: 31.3650, lon: 72.9950, radius: 30 },
  'OPST': { name: 'Sialkot', lat: 32.5356, lon: 74.3639, radius: 30 },
  'OPLA': { name: 'Lahore', lat: 31.5216, lon: 74.4039, radius: 30 },
  'OPKC': { name: 'Karachi', lat: 24.9065, lon: 67.1608, radius: 40 },
  'OPMT': { name: 'Multan', lat: 30.2033, lon: 71.4192, radius: 30 },
};

// All toll plaza points (M1 + M2 motorways) - pre-fetch weather for these
const TOLL_PLAZAS = [
  // M2 Motorway (Islamabad to Lahore) - 20 points
  { id: 'm2_01', name: 'ISB Toll Plaza', lat: 33.58080, lon: 72.87590 },
  { id: 'm2_02', name: 'Thalian', lat: 33.535637, lon: 72.901509 },
  { id: 'm2_03', name: 'Capital Smart City', lat: 33.455312, lon: 72.836096 },
  { id: 'm2_04', name: 'Chakri', lat: 33.30822, lon: 72.78097 },
  { id: 'm2_05', name: 'Neelah Dullah', lat: 33.16597, lon: 72.65091 },
  { id: 'm2_06', name: 'Balkasar', lat: 32.93740, lon: 72.68220 },
  { id: 'm2_07', name: 'Kallar Kahar', lat: 32.77400, lon: 72.71890 },
  { id: 'm2_08', name: 'Lillah', lat: 32.57670, lon: 72.79930 },
  { id: 'm2_09', name: 'Bhera', lat: 32.46050, lon: 72.87490 },
  { id: 'm2_10', name: 'Salam', lat: 32.31410, lon: 73.01990 },
  { id: 'm2_11', name: 'Kot Momin', lat: 32.19940, lon: 73.03220 },
  { id: 'm2_12', name: 'Sial Morr/Makhdoom', lat: 31.97300, lon: 73.10800 },
  { id: 'm2_13', name: 'Pindi Bhattian', lat: 31.93165, lon: 73.28644 },
  { id: 'm2_14', name: 'Kot Sarwar', lat: 31.91450, lon: 73.49960 },
  { id: 'm2_15', name: 'Khangah Dogran', lat: 31.87418, lon: 73.66956 },
  { id: 'm2_16', name: 'Hiran Minar', lat: 31.76670, lon: 73.95070 },
  { id: 'm2_17', name: 'Sheikhupura', lat: 31.747390, lon: 74.007271 },
  { id: 'm2_18', name: 'Kot Pindi Daas', lat: 31.69770, lon: 74.16670 },
  { id: 'm2_19', name: 'Faizpur', lat: 31.592222, lon: 74.218446 },
  { id: 'm2_20', name: 'Ravi Toll Plaza', lat: 31.55840, lon: 74.24170 },
  // M1 Motorway (Islamabad to Peshawar) - 12 points
  { id: 'm1_01', name: 'Islamabad Peshawar Motorway Toll Plaza', lat: 33.5998126034548, lon: 72.86421022885995 },
  { id: 'm1_02', name: 'Fatehjhang Toll Plaza', lat: 33.63812718485647, lon: 72.83764766533295 },
  { id: 'm1_03', name: 'Sangjani Toll Plaza', lat: 33.65451991934462, lon: 72.82525440515146 },
  { id: 'm1_04', name: 'Brahma Jang Bahtar Toll Plaza', lat: 33.74394427383943, lon: 72.70463465828914 },
  { id: 'm1_05', name: 'Jallo Burhan Toll Plaza', lat: 33.82528847591289, lon: 72.62760261329203 },
  { id: 'm1_06', name: 'Ghazi Toll Plaza', lat: 33.886715, lon: 72.551022 },
  { id: 'm1_07', name: 'Chach Toll Plaza', lat: 33.92863069167004, lon: 72.50919507271355 },
  { id: 'm1_08', name: 'Swabi Toll Plaza', lat: 34.04260906367794, lon: 72.40883011741614 },
  { id: 'm1_09', name: 'Kernel Sher Khan Toll Plaza', lat: 34.06706378926631, lon: 72.21231899345337 },
  { id: 'm1_10', name: 'Rashakai Toll Plaza', lat: 34.10693024496253, lon: 72.02389497754581 },
  { id: 'm1_11', name: 'Charsadda Toll Plaza', lat: 34.11952276757881, lon: 71.79021563518248 },
  { id: 'm1_12', name: 'Peshawar Toll Plaza', lat: 34.02699031773744, lon: 71.65019267618838 },
];

export default {
  // HTTP request handler
  async fetch(request, env, ctx) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return corsResponse();
    }

    const url = new URL(request.url);
    
    // Health check
    if (url.pathname === '/health') {
      return handleHealthCheck(env);
    }

    // Get all cached Pakistan METAR data
    if (url.pathname === '/pakistan-metar') {
      return handlePakistanMetar(env);
    }

    // Get airports list
    if (url.pathname === '/airports') {
      return jsonResponse({ airports: PAKISTAN_AIRPORTS });
    }
    
    // Get toll plazas list
    if (url.pathname === '/toll-plazas') {
      return jsonResponse({ toll_plazas: TOLL_PLAZAS, count: TOLL_PLAZAS.length });
    }

    // Main travel weather endpoint
    if (url.pathname === '/travel-weather' && request.method === 'POST') {
      return handleTravelWeather(request, env, ctx);
    }

    // Manual trigger for METAR refresh (testing)
    if (url.pathname === '/refresh-metar') {
      await refreshPakistanMetar(env);
      return jsonResponse({ status: 'metar_refreshed', timestamp: new Date().toISOString() });
    }
    
    // Manual trigger for Weather refresh (testing)
    if (url.pathname === '/refresh-weather') {
      await refreshTollPlazaWeather(env);
      return jsonResponse({ status: 'weather_refreshed', timestamp: new Date().toISOString() });
    }
    
    // Manual trigger for full refresh (both METAR + Weather)
    if (url.pathname === '/refresh-all') {
      await refreshPakistanMetar(env);
      await refreshTollPlazaWeather(env);
      return jsonResponse({ status: 'all_refreshed', timestamp: new Date().toISOString() });
    }

    // Check nearest airport for a location
    if (url.pathname === '/nearest-airport') {
      const lat = parseFloat(url.searchParams.get('lat'));
      const lon = parseFloat(url.searchParams.get('lon'));
      
      if (isNaN(lat) || isNaN(lon)) {
        return jsonResponse({ error: 'Missing lat/lon parameters' }, 400);
      }
      
      return handleNearestAirport(lat, lon, env);
    }

    // Root URL - API info
    if (url.pathname === '/') {
      return jsonResponse({
        name: 'Travel Weather API - Pakistan',
        version: '2.0.0',
        description: 'Pre-cached Weather and METAR data for Pakistan motorway travel',
        cron_schedule: {
          metar: 'Every 15 minutes',
          weather: 'Every 30 minutes',
        },
        endpoints: {
          '/health': 'GET - Health check with cache status',
          '/airports': 'GET - List all Pakistan airports with METAR coverage',
          '/toll-plazas': 'GET - List all pre-cached toll plaza points',
          '/pakistan-metar': 'GET - Get cached METAR for all Pakistan airports',
          '/travel-weather': 'POST - Batch fetch weather for multiple points (from cache)',
          '/nearest-airport': 'GET - Find nearest airport with METAR (?lat=XX&lon=XX)',
          '/refresh-metar': 'GET - Manually refresh METAR cache',
          '/refresh-weather': 'GET - Manually refresh Weather cache',
          '/refresh-all': 'GET - Manually refresh all caches',
        },
        coverage: Object.entries(PAKISTAN_AIRPORTS).map(([icao, info]) => ({
          icao,
          name: info.name,
          radius_km: info.radius,
        })),
        toll_plaza_count: TOLL_PLAZAS.length,
      });
    }

    return jsonResponse({ error: 'Not found' }, 404);
  },

  // Scheduled cron handler
  // Cron 1: */15 * * * * - METAR refresh every 15 minutes
  // Cron 2: */30 * * * * - Weather refresh every 30 minutes
  async scheduled(event, env, ctx) {
    const cronPattern = event.cron;
    console.log(`Cron triggered: ${cronPattern}`);
    
    if (cronPattern === '*/15 * * * *') {
      // Every 15 minutes: refresh METAR
      console.log('Refreshing Pakistan METAR data...');
      ctx.waitUntil(refreshPakistanMetar(env));
    } else if (cronPattern === '*/30 * * * *') {
      // Every 30 minutes: refresh Weather
      console.log('Refreshing toll plaza weather data...');
      ctx.waitUntil(refreshTollPlazaWeather(env));
    } else {
      // Fallback: refresh both
      console.log('Unknown cron, refreshing all...');
      ctx.waitUntil(Promise.all([
        refreshPakistanMetar(env),
        refreshTollPlazaWeather(env),
      ]));
    }
  },
};

/**
 * Health check with cache status
 */
async function handleHealthCheck(env) {
  const metarStatus = await env.METAR_CACHE.get('pakistan_metar_all');
  const weatherCount = await env.METAR_CACHE.get('toll_weather_count');
  
  let metarAge = null;
  if (metarStatus) {
    const parsed = JSON.parse(metarStatus);
    metarAge = Math.round((Date.now() - new Date(parsed.last_updated).getTime()) / 60000);
  }
  
  return jsonResponse({
    status: 'ok',
    timestamp: new Date().toISOString(),
    cache: {
      metar: metarStatus ? 'available' : 'empty',
      metar_age_minutes: metarAge,
      weather_points_cached: weatherCount ? parseInt(weatherCount) : 0,
    },
    toll_plaza_count: TOLL_PLAZAS.length,
    airport_count: Object.keys(PAKISTAN_AIRPORTS).length,
  });
}

/**
 * Refresh METAR for all Pakistan airports and store in KV
 * Called by cron every 15 minutes
 */
async function refreshPakistanMetar(env) {
  const icaoCodes = Object.keys(PAKISTAN_AIRPORTS);
  console.log(`Fetching METAR for ${icaoCodes.length} Pakistan airports...`);

  const results = {};
  const timestamp = new Date().toISOString();

  // Fetch all METAR in parallel
  const metarPromises = icaoCodes.map(async (icao) => {
    try {
      const url = `${CHECKWX_API_URL}/${icao}/decoded`;
      const response = await fetch(url, {
        headers: {
          'X-API-Key': env.CHECKWX_API_KEY,
          'Accept': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`CheckWX error: ${response.status}`);
      }

      const data = await response.json();

      if (!data.data || data.data.length === 0) {
        return { icao, error: 'No METAR data' };
      }

      const metar = data.data[0];
      const airport = PAKISTAN_AIRPORTS[icao];

      return {
        icao,
        airport_name: airport.name,
        lat: airport.lat,
        lon: airport.lon,
        radius: airport.radius,
        raw_text: metar.raw_text || '',
        temp_c: metar.temperature?.celsius ?? null,
        dewpoint_c: metar.dewpoint?.celsius ?? null,
        humidity: metar.humidity?.percent ?? null,
        wind_kph: metar.wind?.speed_kph ?? null,
        wind_degrees: metar.wind?.degrees ?? null,
        wind_dir: metar.wind?.direction ?? '',
        visibility_km: metar.visibility?.meters 
          ? metar.visibility.meters / 1000 
          : (metar.visibility?.kilometers ?? null),
        pressure_hpa: metar.barometer?.hpa ?? null,
        clouds: metar.clouds || [],
        conditions: metar.conditions || [],
        flight_category: metar.flight_category || '',
        observed: metar.observed || '',
        fetched_at: timestamp,
      };

    } catch (error) {
      console.error(`METAR fetch error for ${icao}:`, error);
      return { icao, error: error.message };
    }
  });

  const metarResults = await Promise.all(metarPromises);

  // Store each METAR individually for quick lookup
  for (const result of metarResults) {
    results[result.icao] = result;
    
    // Store in KV with 20 minute expiration (slightly longer than 15 min cron interval)
    await env.METAR_CACHE.put(
      `metar_${result.icao}`,
      JSON.stringify(result),
      { expirationTtl: METAR_CACHE_TTL }
    );
  }

  // Also store combined data for /pakistan-metar endpoint
  await env.METAR_CACHE.put(
    'pakistan_metar_all',
    JSON.stringify({
      airports: results,
      last_updated: timestamp,
      count: Object.keys(results).length,
    }),
    { expirationTtl: METAR_CACHE_TTL }
  );

  console.log(`Stored METAR for ${Object.keys(results).length} airports`);
  return results;
}

/**
 * Refresh Weather for all toll plazas and store in KV
 * Called by cron every 30 minutes
 */
async function refreshTollPlazaWeather(env) {
  console.log(`Fetching weather for ${TOLL_PLAZAS.length} toll plazas...`);
  
  const timestamp = new Date().toISOString();
  let successCount = 0;
  let errorCount = 0;

  // Process in batches of 10 to avoid rate limits
  const batchSize = 10;
  for (let i = 0; i < TOLL_PLAZAS.length; i += batchSize) {
    const batch = TOLL_PLAZAS.slice(i, i + batchSize);
    
    const weatherPromises = batch.map(async (plaza) => {
      try {
        const url = `${WEATHER_API_URL}?key=${env.WEATHER_API_KEY}&q=${plaza.lat},${plaza.lon}&aqi=no`;
        const response = await fetch(url);
        
        if (!response.ok) {
          throw new Error(`WeatherAPI error: ${response.status}`);
        }

        const data = await response.json();
        const current = data.current;

        const result = {
          id: plaza.id,
          name: plaza.name,
          source: 'weatherapi',
          temp_c: current.temp_c,
          condition: current.condition?.text || 'Unknown',
          icon: current.condition?.icon || '',
          humidity: current.humidity,
          wind_kph: current.wind_kph,
          wind_dir: current.wind_dir,
          feelslike_c: current.feelslike_c,
          pressure_mb: current.pressure_mb,
          vis_km: current.vis_km,
          uv: current.uv,
          cloud: current.cloud,
          precip_mm: current.precip_mm,
          is_day: current.is_day,
          fetched_at: timestamp,
        };

        // Store in KV cache
        await env.METAR_CACHE.put(
          `weather_${plaza.id}`,
          JSON.stringify(result),
          { expirationTtl: WEATHER_CACHE_TTL }
        );

        successCount++;
        return { id: plaza.id, success: true };

      } catch (error) {
        console.error(`Weather fetch error for ${plaza.id}:`, error);
        errorCount++;
        return { id: plaza.id, error: error.message };
      }
    });

    await Promise.all(weatherPromises);
    
    // Small delay between batches to be nice to the API
    if (i + batchSize < TOLL_PLAZAS.length) {
      await new Promise(resolve => setTimeout(resolve, 500));
    }
  }

  // Store count for health check
  await env.METAR_CACHE.put('toll_weather_count', String(successCount), {
    expirationTtl: WEATHER_CACHE_TTL,
  });
  
  // Store last update time
  await env.METAR_CACHE.put('toll_weather_last_updated', timestamp, {
    expirationTtl: WEATHER_CACHE_TTL,
  });

  console.log(`Stored weather for ${successCount}/${TOLL_PLAZAS.length} toll plazas (${errorCount} errors)`);
  return { success: successCount, errors: errorCount };
}

/**
 * Get all cached Pakistan METAR data
 */
async function handlePakistanMetar(env) {
  try {
    const cached = await env.METAR_CACHE.get('pakistan_metar_all');
    
    if (cached) {
      return jsonResponse(JSON.parse(cached));
    }

    // If no cached data, trigger a refresh
    const results = await refreshPakistanMetar(env);
    return jsonResponse({
      airports: results,
      last_updated: new Date().toISOString(),
      count: Object.keys(results).length,
    });

  } catch (error) {
    console.error('Error fetching Pakistan METAR:', error);
    return jsonResponse({ error: error.message }, 500);
  }
}

async function handleTravelWeather(request, env, ctx) {
  try {
    const body = await request.json();
    const { points } = body;

    if (!points || !Array.isArray(points)) {
      return jsonResponse({ error: 'Missing or invalid points array' }, 400);
    }

    // Process each point - check METAR range and get appropriate data FROM CACHE ONLY
    const weatherResults = await fetchWeatherFromCache(points, env);

    return jsonResponse({
      weather: weatherResults,
      pakistan_airports: Object.keys(PAKISTAN_AIRPORTS),
      cached_at: new Date().toISOString(),
      source: 'kv_cache',
    });

  } catch (error) {
    console.error('Travel weather error:', error);
    return jsonResponse({ error: error.message }, 500);
  }
}

/**
 * Fetch weather for all points FROM CACHE ONLY
 * Uses METAR when in range, pre-cached WeatherAPI otherwise
 * NO live API calls - everything comes from KV cache
 */
async function fetchWeatherFromCache(points, env) {
  const weatherPromises = points.map(async (point) => {
    // Check if point is within any airport's METAR range
    const nearestAirport = findNearestAirport(point.lat, point.lon);
    
    if (nearestAirport.inRange) {
      // Use METAR data from cache
      const metarData = await getMetarForPoint(nearestAirport.icao, env);
      if (metarData && !metarData.error) {
        return {
          id: point.id,
          source: 'metar',
          airport_icao: nearestAirport.icao,
          airport_name: nearestAirport.name,
          distance_to_airport_km: nearestAirport.distance,
          temp_c: metarData.temp_c,
          condition: formatMetarCondition(metarData.conditions, metarData.clouds),
          icon: mapMetarToIcon(metarData.conditions, metarData.clouds, metarData.visibility_km),
          humidity: metarData.humidity,
          wind_kph: metarData.wind_kph,
          wind_dir: metarData.wind_dir || '',
          visibility_km: metarData.visibility_km,
          pressure_mb: metarData.pressure_hpa,
          flight_category: metarData.flight_category,
          raw_metar: metarData.raw_text,
          observed: metarData.observed,
          cached: true,
        };
      }
    }
    
    // Outside METAR range - use pre-cached WeatherAPI data
    return await getWeatherFromCache(point, env);
  });

  const results = await Promise.all(weatherPromises);
  
  // Convert array to object keyed by point ID
  const weatherMap = {};
  for (const result of results) {
    weatherMap[result.id] = result;
  }
  return weatherMap;
}

/**
 * Find the nearest airport and check if point is within its METAR range
 */
function findNearestAirport(lat, lon) {
  let nearestAirport = null;
  let nearestDistance = Infinity;
  
  for (const [icao, airport] of Object.entries(PAKISTAN_AIRPORTS)) {
    const distance = haversineDistance(lat, lon, airport.lat, airport.lon);
    
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestAirport = { icao, ...airport };
    }
  }
  
  if (!nearestAirport) {
    return { inRange: false };
  }
  
  return {
    icao: nearestAirport.icao,
    name: nearestAirport.name,
    distance: Math.round(nearestDistance * 10) / 10,
    inRange: nearestDistance <= nearestAirport.radius,
  };
}

/**
 * Get METAR data from KV cache
 */
async function getMetarForPoint(icao, env) {
  try {
    const cached = await env.METAR_CACHE.get(`metar_${icao}`);
    if (cached) {
      return JSON.parse(cached);
    }
    return null;
  } catch (error) {
    console.error(`Error getting METAR for ${icao}:`, error);
    return null;
  }
}

/**
 * Get weather from KV cache ONLY - no live API calls
 * Data is pre-fetched by cron job every 30 minutes
 */
async function getWeatherFromCache(point, env) {
  const cacheKey = `weather_${point.id}`;
  
  try {
    // Try KV cache
    const cached = await env.METAR_CACHE.get(cacheKey);
    if (cached) {
      const data = JSON.parse(cached);
      return { id: point.id, ...data, cached: true };
    }
    
    // Cache miss - return error, no live fetch
    // This means the cron job hasn't run yet or the point is not in TOLL_PLAZAS
    return {
      id: point.id,
      source: 'cache_miss',
      temp_c: null,
      condition: 'No cached data',
      humidity: null,
      wind_kph: null,
      cached: false,
      error: 'Weather not pre-cached. Wait for next cron job or call /refresh-weather',
    };

  } catch (error) {
    console.error(`Cache read error for ${point.id}:`, error);
    return {
      id: point.id,
      source: 'error',
      temp_c: null,
      condition: 'Error',
      humidity: null,
      wind_kph: null,
      error: error.message,
    };
  }
}

/**
 * Format METAR conditions into human-readable text
 */
function formatMetarCondition(conditions, clouds) {
  if (conditions && conditions.length > 0) {
    // Priority conditions
    const conditionTexts = conditions.map(c => c.text || c.code);
    return conditionTexts.join(', ');
  }
  
  if (clouds && clouds.length > 0) {
    const cloudTexts = clouds.map(c => c.text || c.code);
    return cloudTexts[0] || 'Clear';
  }
  
  return 'Clear';
}

/**
 * Map METAR conditions to WeatherAPI-compatible icon URL
 */
function mapMetarToIcon(conditions, clouds, visibility) {
  // Check for fog/mist (low visibility)
  if (visibility !== null && visibility < 1) {
    return '//cdn.weatherapi.com/weather/64x64/day/248.png'; // Fog
  }
  
  if (conditions && conditions.length > 0) {
    const codes = conditions.map(c => c.code).join(' ');
    
    if (codes.includes('TS')) {
      if (codes.includes('RA')) return '//cdn.weatherapi.com/weather/64x64/day/389.png'; // Thunder rain
      return '//cdn.weatherapi.com/weather/64x64/day/200.png'; // Thunder
    }
    if (codes.includes('RA') || codes.includes('DZ')) {
      return '//cdn.weatherapi.com/weather/64x64/day/296.png'; // Rain
    }
    if (codes.includes('SN')) {
      return '//cdn.weatherapi.com/weather/64x64/day/338.png'; // Snow
    }
    if (codes.includes('FG') || codes.includes('BR')) {
      return '//cdn.weatherapi.com/weather/64x64/day/248.png'; // Fog/Mist
    }
    if (codes.includes('HZ') || codes.includes('FU') || codes.includes('DU')) {
      return '//cdn.weatherapi.com/weather/64x64/day/143.png'; // Haze/Smoke/Dust
    }
  }
  
  if (clouds && clouds.length > 0) {
    const cloudCode = clouds[0]?.code;
    if (cloudCode === 'OVC' || cloudCode === 'BKN') {
      return '//cdn.weatherapi.com/weather/64x64/day/122.png'; // Overcast
    }
    if (cloudCode === 'SCT') {
      return '//cdn.weatherapi.com/weather/64x64/day/116.png'; // Partly cloudy
    }
    if (cloudCode === 'FEW') {
      return '//cdn.weatherapi.com/weather/64x64/day/113.png'; // Mostly sunny
    }
  }
  
  return '//cdn.weatherapi.com/weather/64x64/day/113.png'; // Clear/Sunny
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    },
  });
}

function corsResponse() {
  return new Response(null, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    },
  });
}

/**
 * Calculate distance between two points using Haversine formula
 */
function haversineDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * Find the nearest airport to a given location
 * Returns METAR if within radius, or info about nearest airport
 */
async function handleNearestAirport(lat, lon, env) {
  let nearestAirport = null;
  let nearestDistance = Infinity;
  let withinRadius = false;
  
  // Find nearest airport
  for (const [icao, airport] of Object.entries(PAKISTAN_AIRPORTS)) {
    const distance = haversineDistance(lat, lon, airport.lat, airport.lon);
    
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestAirport = { icao, ...airport };
      withinRadius = distance <= airport.radius;
    }
  }
  
  if (!nearestAirport) {
    return jsonResponse({
      in_metar_range: false,
      message: 'No airports found',
      location: { lat, lon },
    });
  }
  
  const response = {
    location: { lat, lon },
    nearest_airport: {
      icao: nearestAirport.icao,
      name: nearestAirport.name,
      lat: nearestAirport.lat,
      lon: nearestAirport.lon,
      radius_km: nearestAirport.radius,
    },
    distance_km: Math.round(nearestDistance * 10) / 10,
    in_metar_range: withinRadius,
  };
  
  // If within range, also return METAR data
  if (withinRadius) {
    const cached = await env.METAR_CACHE.get(`metar_${nearestAirport.icao}`);
    if (cached) {
      response.metar = JSON.parse(cached);
      response.message = `Within ${nearestAirport.name} METAR coverage`;
    } else {
      response.message = `Within ${nearestAirport.name} range but no cached METAR`;
    }
  } else {
    response.message = `Outside METAR coverage. Nearest: ${nearestAirport.name} (${Math.round(nearestDistance)}km away, needs to be within ${nearestAirport.radius}km)`;
  }
  
  return jsonResponse(response);
}
