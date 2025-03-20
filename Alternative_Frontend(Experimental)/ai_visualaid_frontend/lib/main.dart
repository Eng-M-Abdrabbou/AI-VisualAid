// main.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'app/carousel_navigation_app.dart';  // Correct path

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(CarouselNavigationApp(camera: cameras.first));
}