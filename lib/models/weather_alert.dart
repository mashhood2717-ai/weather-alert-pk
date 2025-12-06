// lib/models/weather_alert.dart

class WeatherAlert {
  final String id;
  final String title;
  final String body;
  final String? city;
  final String? severity; // low, medium, high, extreme
  final DateTime receivedAt;
  final bool isRead;
  final Map<String, dynamic>? data;

  WeatherAlert({
    required this.id,
    required this.title,
    required this.body,
    this.city,
    this.severity,
    required this.receivedAt,
    this.isRead = false,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'city': city,
        'severity': severity,
        'receivedAt': receivedAt.toIso8601String(),
        'isRead': isRead,
        'data': data,
      };

  factory WeatherAlert.fromJson(Map<String, dynamic> json) => WeatherAlert(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        body: json['body'] ?? '',
        city: json['city'],
        severity: json['severity'],
        receivedAt: DateTime.parse(json['receivedAt']),
        isRead: json['isRead'] ?? false,
        data: json['data'],
      );

  WeatherAlert copyWith({bool? isRead}) => WeatherAlert(
        id: id,
        title: title,
        body: body,
        city: city,
        severity: severity,
        receivedAt: receivedAt,
        isRead: isRead ?? this.isRead,
        data: data,
      );
}
