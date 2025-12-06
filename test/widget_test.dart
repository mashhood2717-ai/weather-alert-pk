// Basic Flutter widget test for Weather Alert Pakistan

import 'package:flutter_test/flutter_test.dart';
import 'package:weather_alert_pakistan/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const WeatherAlertApp());

    // Verify app title is displayed
    expect(find.text('Weather Alert'), findsOneWidget);
    expect(find.text('Pakistan'), findsOneWidget);
  });
}
