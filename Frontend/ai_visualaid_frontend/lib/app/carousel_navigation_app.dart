// lib/app/carousel_navigation_app.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../presentation/screens/home_screen.dart'; 

class CarouselNavigationApp extends StatelessWidget {
  final CameraDescription camera;

const CarouselNavigationApp({
  super.key,
  required this.camera  
});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(camera: camera),
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
       debugShowCheckedModeBanner: false, 
    );
  }
}