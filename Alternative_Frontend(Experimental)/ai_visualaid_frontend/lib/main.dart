// lib/main.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'app/carousel_navigation_app.dart'; // Keep this for MaterialApp setup
import 'presentation/screens/home_screen.dart'; // Import the new home screen

// Keep the instance of the app separate for potential future setup
late CameraDescription firstCamera;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize camera
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
       debugPrint("Error: No cameras available!");
       // Handle case with no cameras (e.g., show an error message or exit)
       runApp(const ErrorApp(message: "No cameras found on this device."));
       return;
    }
     firstCamera = cameras.first;

     // Run the app using the separate App widget
     runApp(CarouselNavigationApp(camera: firstCamera));

  } catch (e) {
     debugPrint("Error during initialization: $e");
     // Handle camera initialization errors
     runApp(ErrorApp(message: "Failed to initialize cameras: $e"));
  }
}


// Optional: A simple app to display errors if main initialization fails
class ErrorApp extends StatelessWidget {
  final String message;
  const ErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text("Error: $message"),
        ),
      ),
    );
  }
}

// --- IMPORTANT ---
// Ensure CarouselNavigationApp now uses HomeScreen
// Modify lib/app/carousel_navigation_app.dart like this:

/*
// lib/app/carousel_navigation_app.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
// Import the NEW home screen
import '../presentation/screens/home_screen.dart';

class CarouselNavigationApp extends StatelessWidget {
  final CameraDescription camera;

  const CarouselNavigationApp({
    super.key,
    required this.camera, // Must match exactly
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Use HomeScreen instead of CarouselPage
      home: HomeScreen(camera: camera),
      theme: ThemeData(
        primarySwatch: Colors.blue,
        // Consider a dark theme if your background is mostly camera preview
        // brightness: Brightness.dark,
      ),
      debugShowCheckedModeBanner: false, // Optional: remove debug banner
    );
  }
}
*/