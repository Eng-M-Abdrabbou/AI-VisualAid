import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_visualaid_frontend/main.dart';

void main() {
  testWidgets('App initializes correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(CarouselNavigationApp());

    // Verify that the app title is displayed
    expect(find.text('AI Visual Aid App'), findsOneWidget);
  });
}
