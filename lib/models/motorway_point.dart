// lib/models/motorway_point.dart

/// Represents a point on the motorway (toll plaza, interchange, service area)
class MotorwayPoint {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final PointType type;
  final int distanceFromStart; // km from route start
  final String? facilities; // Rest area, fuel, food, etc.

  const MotorwayPoint({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.type,
    required this.distanceFromStart,
    this.facilities,
  });
}

enum PointType {
  tollPlaza,
  interchange,
  serviceArea,
  destination,
}

/// Travel point with weather and ETA info
class TravelPoint {
  final MotorwayPoint point;
  final Duration? etaFromStart;
  final DateTime? estimatedArrival;
  final TravelWeather? weather;
  final String? nextPrayer;
  final String? nextPrayerTime;
  final bool isPassed;

  TravelPoint({
    required this.point,
    this.etaFromStart,
    this.estimatedArrival,
    this.weather,
    this.nextPrayer,
    this.nextPrayerTime,
    this.isPassed = false,
  });

  TravelPoint copyWith({
    Duration? etaFromStart,
    DateTime? estimatedArrival,
    TravelWeather? weather,
    String? nextPrayer,
    String? nextPrayerTime,
    bool? isPassed,
  }) {
    return TravelPoint(
      point: point,
      etaFromStart: etaFromStart ?? this.etaFromStart,
      estimatedArrival: estimatedArrival ?? this.estimatedArrival,
      weather: weather ?? this.weather,
      nextPrayer: nextPrayer ?? this.nextPrayer,
      nextPrayerTime: nextPrayerTime ?? this.nextPrayerTime,
      isPassed: isPassed ?? this.isPassed,
    );
  }
}

/// Simplified weather for travel view
class TravelWeather {
  final double tempC;
  final String condition;
  final String icon;
  final int humidity;
  final double windKph;
  final double? rainChance;

  TravelWeather({
    required this.tempC,
    required this.condition,
    required this.icon,
    required this.humidity,
    required this.windKph,
    this.rainChance,
  });
}

/// M2 Motorway Data (Islamabad to Lahore)
class M2Motorway {
  static const String routeId = 'm2';
  static const String routeName = 'M2 Motorway';
  static const String startCity = 'Islamabad';
  static const String endCity = 'Lahore';
  static const int totalDistanceKm = 367;

  static const List<MotorwayPoint> points = [
    MotorwayPoint(
      id: 'm2_01',
      name: 'ISB Toll Plaza',
      lat: 33.58080,
      lon: 72.87590,
      type: PointType.tollPlaza,
      distanceFromStart: 0,
    ),
    MotorwayPoint(
      id: 'm2_02',
      name: 'Thalian',
      lat: 33.535637,
      lon: 72.901509,
      type: PointType.interchange,
      distanceFromStart: 8,
    ),
    MotorwayPoint(
      id: 'm2_03',
      name: 'Capital Smart City',
      lat: 33.455312,
      lon: 72.836096,
      type: PointType.interchange,
      distanceFromStart: 22,
    ),
    MotorwayPoint(
      id: 'm2_04',
      name: 'Chakri',
      lat: 33.30822,
      lon: 72.78097,
      type: PointType.serviceArea,
      distanceFromStart: 40,
      facilities: 'Rest Area, Fuel, Food',
    ),
    MotorwayPoint(
      id: 'm2_05',
      name: 'Neelah Dullah',
      lat: 33.16597,
      lon: 72.65091,
      type: PointType.interchange,
      distanceFromStart: 60,
    ),
    MotorwayPoint(
      id: 'm2_06',
      name: 'Balkasar',
      lat: 32.93740,
      lon: 72.68220,
      type: PointType.interchange,
      distanceFromStart: 85,
    ),
    MotorwayPoint(
      id: 'm2_07',
      name: 'Kallar Kahar',
      lat: 32.77400,
      lon: 72.71890,
      type: PointType.serviceArea,
      distanceFromStart: 105,
      facilities: 'Rest Area, Food Court, Fuel, Mosque',
    ),
    MotorwayPoint(
      id: 'm2_08',
      name: 'Lillah',
      lat: 32.57670,
      lon: 72.79930,
      type: PointType.interchange,
      distanceFromStart: 130,
    ),
    MotorwayPoint(
      id: 'm2_09',
      name: 'Bhera',
      lat: 32.46050,
      lon: 72.87490,
      type: PointType.interchange,
      distanceFromStart: 150,
    ),
    MotorwayPoint(
      id: 'm2_10',
      name: 'Salam',
      lat: 32.31410,
      lon: 73.01990,
      type: PointType.interchange,
      distanceFromStart: 175,
    ),
    MotorwayPoint(
      id: 'm2_11',
      name: 'Kot Momin',
      lat: 32.19940,
      lon: 73.03220,
      type: PointType.interchange,
      distanceFromStart: 195,
    ),
    MotorwayPoint(
      id: 'm2_12',
      name: 'Sial Morr/Makhdoom',
      lat: 31.97300,
      lon: 73.10800,
      type: PointType.serviceArea,
      distanceFromStart: 220,
      facilities: 'Rest Area, Fuel, Food',
    ),
    MotorwayPoint(
      id: 'm2_13',
      name: 'Pindi Bhattian',
      lat: 31.93165,
      lon: 73.28644,
      type: PointType.interchange,
      distanceFromStart: 240,
    ),
    MotorwayPoint(
      id: 'm2_14',
      name: 'Kot Sarwar',
      lat: 31.91450,
      lon: 73.49960,
      type: PointType.interchange,
      distanceFromStart: 262,
    ),
    MotorwayPoint(
      id: 'm2_15',
      name: 'Khangah Dogran',
      lat: 31.87418,
      lon: 73.66956,
      type: PointType.interchange,
      distanceFromStart: 280,
    ),
    MotorwayPoint(
      id: 'm2_16',
      name: 'Hiran Minar',
      lat: 31.76670,
      lon: 73.95070,
      type: PointType.serviceArea,
      distanceFromStart: 305,
      facilities: 'Rest Area, Fuel, Food, Historical Site',
    ),
    MotorwayPoint(
      id: 'm2_17',
      name: 'Sheikhupura',
      lat: 31.747390,
      lon: 74.007271,
      type: PointType.interchange,
      distanceFromStart: 315,
    ),
    MotorwayPoint(
      id: 'm2_18',
      name: 'Kot Pindi Daas',
      lat: 31.69770,
      lon: 74.16670,
      type: PointType.interchange,
      distanceFromStart: 335,
    ),
    MotorwayPoint(
      id: 'm2_19',
      name: 'Faizpur',
      lat: 31.592222,
      lon: 74.218446,
      type: PointType.interchange,
      distanceFromStart: 352,
    ),
    MotorwayPoint(
      id: 'm2_20',
      name: 'Ravi Toll Plaza',
      lat: 31.55840,
      lon: 74.24170,
      type: PointType.destination,
      distanceFromStart: 367,
      facilities: 'Toll Plaza, Fuel',
    ),
  ];

  /// Get points from start to destination
  static List<MotorwayPoint> getPointsTo(String destinationId) {
    final destIndex = points.indexWhere((p) => p.id == destinationId);
    if (destIndex == -1) return points;
    return points.sublist(0, destIndex + 1);
  }

  /// Get points between two points
  static List<MotorwayPoint> getPointsBetween(String fromId, String toId) {
    final fromIndex = points.indexWhere((p) => p.id == fromId);
    final toIndex = points.indexWhere((p) => p.id == toId);
    if (fromIndex == -1 || toIndex == -1) return [];
    if (fromIndex > toIndex) {
      // Reverse direction (Lahore to Islamabad)
      return points.sublist(toIndex, fromIndex + 1).reversed.toList();
    }
    return points.sublist(fromIndex, toIndex + 1);
  }
}

/// M1 Motorway Data (Islamabad to Peshawar)
class M1Motorway {
  static const String routeId = 'm1';
  static const String routeName = 'M1 Motorway';
  static const String startCity = 'Islamabad';
  static const String endCity = 'Peshawar';
  static const int totalDistanceKm = 155;

  static const List<MotorwayPoint> points = [
    MotorwayPoint(
      id: 'm1_01',
      name: 'Islamabad Peshawar Motorway Toll Plaza',
      lat: 33.5998126034548,
      lon: 72.86421022885995,
      type: PointType.tollPlaza,
      distanceFromStart: 0,
    ),
    MotorwayPoint(
      id: 'm1_02',
      name: 'Fatehjhang Toll Plaza',
      lat: 33.63812718485647,
      lon: 72.83764766533295,
      type: PointType.tollPlaza,
      distanceFromStart: 8,
    ),
    MotorwayPoint(
      id: 'm1_03',
      name: 'Sangjani Toll Plaza',
      lat: 33.65451991934462,
      lon: 72.82525440515146,
      type: PointType.tollPlaza,
      distanceFromStart: 12,
    ),
    MotorwayPoint(
      id: 'm1_04',
      name: 'Brahma Jang Bahtar Toll Plaza',
      lat: 33.74394427383943,
      lon: 72.70463465828914,
      type: PointType.tollPlaza,
      distanceFromStart: 28,
    ),
    MotorwayPoint(
      id: 'm1_05',
      name: 'Jallo Burhan Toll Plaza',
      lat: 33.82528847591289,
      lon: 72.62760261329203,
      type: PointType.tollPlaza,
      distanceFromStart: 42,
    ),
    MotorwayPoint(
      id: 'm1_06',
      name: 'Ghazi Toll Plaza',
      lat: 33.886715,
      lon: 72.551022,
      type: PointType.tollPlaza,
      distanceFromStart: 55,
    ),
    MotorwayPoint(
      id: 'm1_07',
      name: 'Chach Toll Plaza',
      lat: 33.92863069167004,
      lon: 72.50919507271355,
      type: PointType.tollPlaza,
      distanceFromStart: 65,
    ),
    MotorwayPoint(
      id: 'm1_08',
      name: 'Swabi Toll Plaza',
      lat: 34.04260906367794,
      lon: 72.40883011741614,
      type: PointType.tollPlaza,
      distanceFromStart: 85,
    ),
    MotorwayPoint(
      id: 'm1_09',
      name: 'Kernel Sher Khan Toll Plaza',
      lat: 34.06706378926631,
      lon: 72.21231899345337,
      type: PointType.tollPlaza,
      distanceFromStart: 105,
    ),
    MotorwayPoint(
      id: 'm1_10',
      name: 'Rashakai Toll Plaza',
      lat: 34.10693024496253,
      lon: 72.02389497754581,
      type: PointType.tollPlaza,
      distanceFromStart: 125,
    ),
    MotorwayPoint(
      id: 'm1_11',
      name: 'Charsadda Toll Plaza',
      lat: 34.11952276757881,
      lon: 71.79021563518248,
      type: PointType.tollPlaza,
      distanceFromStart: 145,
    ),
    MotorwayPoint(
      id: 'm1_12',
      name: 'Peshawar Toll Plaza',
      lat: 34.02699031773744,
      lon: 71.65019267618838,
      type: PointType.destination,
      distanceFromStart: 155,
      facilities: 'Toll Plaza, Entry to Peshawar',
    ),
  ];

  /// Get points from start to destination
  static List<MotorwayPoint> getPointsTo(String destinationId) {
    final destIndex = points.indexWhere((p) => p.id == destinationId);
    if (destIndex == -1) return points;
    return points.sublist(0, destIndex + 1);
  }

  /// Get points between two points
  static List<MotorwayPoint> getPointsBetween(String fromId, String toId) {
    final fromIndex = points.indexWhere((p) => p.id == fromId);
    final toIndex = points.indexWhere((p) => p.id == toId);
    if (fromIndex == -1 || toIndex == -1) return [];
    if (fromIndex > toIndex) {
      // Reverse direction (Peshawar to Islamabad)
      return points.sublist(toIndex, fromIndex + 1).reversed.toList();
    }
    return points.sublist(fromIndex, toIndex + 1);
  }
}

/// Unified motorway helper for all Pakistan motorways
class PakistanMotorways {
  static const List<MotorwayInfo> motorways = [
    MotorwayInfo(
      id: 'm2',
      name: 'M2 Motorway',
      subtitle: 'Islamabad - Lahore',
      distanceKm: 367,
    ),
    MotorwayInfo(
      id: 'm1',
      name: 'M1 Motorway',
      subtitle: 'Islamabad - Peshawar',
      distanceKm: 155,
    ),
  ];

  /// Get all points for a motorway
  static List<MotorwayPoint> getPoints(String motorwayId) {
    switch (motorwayId) {
      case 'm1':
        return M1Motorway.points;
      case 'm2':
      default:
        return M2Motorway.points;
    }
  }

  /// Get points to destination on specific motorway
  static List<MotorwayPoint> getPointsTo(
      String motorwayId, String destinationId) {
    switch (motorwayId) {
      case 'm1':
        return M1Motorway.getPointsTo(destinationId);
      case 'm2':
      default:
        return M2Motorway.getPointsTo(destinationId);
    }
  }

  /// Get points between two points on specific motorway
  static List<MotorwayPoint> getPointsBetween(
      String motorwayId, String fromId, String toId) {
    switch (motorwayId) {
      case 'm1':
        return M1Motorway.getPointsBetween(fromId, toId);
      case 'm2':
      default:
        return M2Motorway.getPointsBetween(fromId, toId);
    }
  }
}

/// Info about a motorway for selection UI
class MotorwayInfo {
  final String id;
  final String name;
  final String subtitle;
  final int distanceKm;

  const MotorwayInfo({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.distanceKm,
  });
}
