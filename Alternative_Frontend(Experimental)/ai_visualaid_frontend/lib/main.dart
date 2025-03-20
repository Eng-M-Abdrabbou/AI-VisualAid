// main.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'app/carousel_navigation_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize camera
  final cameras = await availableCameras();
  
  // Run the app
  runApp(CarouselNavigationApp(camera: cameras.first));
}