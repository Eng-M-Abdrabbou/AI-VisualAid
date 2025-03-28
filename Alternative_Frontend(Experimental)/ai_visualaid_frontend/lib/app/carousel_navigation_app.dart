// lib/app/carousel_navigation_app.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
// Import the NEW home screen
import '../presentation/screens/home_screen.dart'; // Corrected import path

class CarouselNavigationApp extends StatelessWidget {
  final CameraDescription camera;

const CarouselNavigationApp({
  super.key,
  required this.camera  // Must match exactly
});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Use HomeScreen instead of CarouselPage
      home: HomeScreen(camera: camera),
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // Consider a dark theme if your background is mostly camera preview
        // brightness: Brightness.dark,
      ),
       debugShowCheckedModeBanner: false, // Optional: remove debug banner
    );
  }
}