// lib/main.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'app/carousel_navigation_app.dart';

late CameraDescription firstCamera;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  try {

    debugPrint("Fetching available cameras...");
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
       debugPrint("CRITICAL ERROR: No cameras available on this device!");
       runApp(const ErrorApp(message: "No cameras found on this device."));
       return;
    }
     debugPrint("Cameras found: ${cameras.length}. Using the first one.");
     firstCamera = cameras.first;

     runApp(CarouselNavigationApp(camera: firstCamera));

  } catch (e) {
     debugPrint("CRITICAL ERROR during camera initialization: $e");
     runApp(ErrorApp(message: "Failed to initialize cameras: $e"));
  }
}


class ErrorApp extends StatelessWidget {
  final String message;
  const ErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red[900],
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Application Error:\n$message",
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
       debugShowCheckedModeBanner: false,
    );
  }
}
