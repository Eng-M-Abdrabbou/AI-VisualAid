// lib/main.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart'; // Import services for orientation lock
import 'app/carousel_navigation_app.dart'; // Keep this for MaterialApp setup
// No direct import of HomeScreen needed here if CarouselNavigationApp handles it

// Keep the instance of the app separate for potential future setup
late CameraDescription firstCamera;

void main() async {
  // Ensure Flutter bindings are initialized. Crucial for async operations before runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Lock device orientation to Portrait Up (standard phone holding)
  // This helps ensure the camera preview aspect ratio matches the screen orientation consistently.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  try {
    // Initialize camera list asynchronously.
    debugPrint("Fetching available cameras...");
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
       // Handle the critical error case where no cameras are found.
       debugPrint("CRITICAL ERROR: No cameras available on this device!");
       // Run a fallback error app to inform the user.
       runApp(const ErrorApp(message: "No cameras found on this device."));
       return; // Stop execution if no cameras.
    }
     debugPrint("Cameras found: ${cameras.length}. Using the first one.");
     // Store the first available camera.
     firstCamera = cameras.first;

     // Run the main application, passing the initialized camera.
     runApp(CarouselNavigationApp(camera: firstCamera));

  } catch (e) {
     // Catch any errors during camera initialization.
     debugPrint("CRITICAL ERROR during camera initialization: $e");
     // Run the fallback error app with the error message.
     runApp(ErrorApp(message: "Failed to initialize cameras: $e"));
  }
}


// Optional: A simple fallback app to display critical errors during startup.
class ErrorApp extends StatelessWidget {
  final String message;
  const ErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red[900], // Use a distinct error background
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