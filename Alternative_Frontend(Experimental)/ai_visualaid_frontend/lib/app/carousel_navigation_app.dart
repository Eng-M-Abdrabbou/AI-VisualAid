import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../screens/carousel_page.dart';

class CarouselNavigationApp extends StatelessWidget {
  final CameraDescription camera;

const CarouselNavigationApp({
  super.key,
  required this.camera  // Must match exactly
});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CarouselPage(camera: camera),
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
    );
  }
}