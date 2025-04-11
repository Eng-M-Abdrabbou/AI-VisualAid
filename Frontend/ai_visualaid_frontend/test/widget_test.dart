import 'package:ai_visualaid_frontend/app/carousel_navigation_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_visualaid_frontend/main.dart';
import 'package:camera/camera.dart';

void main() {
  testWidgets('App initializes correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    final cameras = await availableCameras();
    await tester.pumpWidget(CarouselNavigationApp(camera: cameras.first));

    // Verify that the app title is displayed
    expect(find.text('AI Visual Aid App'), findsOneWidget);
  });
}
