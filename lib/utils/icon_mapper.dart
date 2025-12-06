// ============================================
// 13. lib/utils/icon_mapper.dart
// ============================================

String weatherApiIconUrl(String iconFile) {
  if (iconFile.startsWith('http'))
    return iconFile.replaceFirst('http:', 'https:');
  if (iconFile.startsWith('//')) return 'https:$iconFile';

  if (iconFile.isNotEmpty && !iconFile.contains('/')) {
    return 'https://cdn.weatherapi.com/weather/64x64/day/$iconFile';
  }

  return 'https://cdn.weatherapi.com/weather/$iconFile';
}

String mapMetarIcon(String code) {
  code = code.toUpperCase();
  code = code.replaceAll(RegExp(r'[+\-]'), '');

  // Haze/Mist/Fog (Common in Pakistan)
  if (code.contains("FU") ||
      code.contains("BR") ||
      code.contains("HZ") ||
      code.contains("DU") ||
      code.contains("SA")) return "143.png";
  if (code.contains("FG")) return "248.png";

  // Cloud Cover
  if (code.contains("OVC") || code.contains("BKN")) return "122.png";
  if (code.contains("SCT") || code.contains("FEW")) return "119.png";

  // Precipitation
  if (code.contains("TSRA") || code.contains("TS")) return "389.png";
  if (code.contains("SHRA")) return "356.png";
  if (code.contains("RA") || code.contains("DZ")) return "308.png";
  if (code.contains("SN")) return "338.png";

  // Default (Clear)
  return "113.png";
}

final Map<String, String> metarDescriptions = {
  // Thunderstorm / Rain
  "TSRA": "Bijli k saath barsaat (Thunderstorm with Rain)",
  "TS": "Bijli garajj, bijli chamak (Thunderstorm)",
  "SHRA": "Achanak wali phoار (Rain Showers)",
  "RA": "Normal barsaat (Rain)",
  "DZ": "Bohot halki, mist jaisi barsaat (Drizzle)",

  // Snow / Ice
  "SN": "Barf bars rahi ho (Snow)",
  "SG": "Tiny ice grains (Snow Grains)",

  // Visibility / Obstruction
  "FG": "Bohot ghari dhund (Fog)",
  "BR": "Halki dhund (Mist)",
  "HZ": "Dry particles ki dhund (Haze)",
  "DU": "Hawa mein dust particles (Dust)",
  "SA": "Hawa mein Sand particles (Sand Haze)",
  "FU": "Aag/Factory ka dhuwaan (Smoke)",
  "VA": "Jawaal jala ki raakh (Volcanic Ash)",

  // Cloud/Default
  "SKC": "Aasman saaf (Clear Sky)",
  "CLR": "Aasman saaf (Clear Sky)",
  "FEW": "Halkay badal (Few Clouds)",
  "SCT": "Bikhray huay badal (Scattered Clouds)",
  "BKN": "Tootay huay badal (Broken Clouds)",
  "OVC": "Ghanay badal (Overcast Sky)",
};

String mapMetarCodeToDescription(String code) {
  code = code.toUpperCase();

  if (metarDescriptions.containsKey(code)) {
    return metarDescriptions[code]!;
  }

  for (var entry in metarDescriptions.entries) {
    if (code.contains(entry.key)) {
      return entry.value;
    }
  }

  return metarDescriptions["SKC"]!;
}
