// lib/presentation/widgets/camera_view_widget.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraViewWidget extends StatelessWidget {
  final CameraController? cameraController;
  final Future<void>? initializeControllerFuture;

  const CameraViewWidget({
    super.key,
    required this.cameraController,
    required this.initializeControllerFuture,
  });

  @override
  Widget build(BuildContext context) {
    if (cameraController == null || initializeControllerFuture == null) {
      return const Center(child: Text("Camera not available"));
    }

    return FutureBuilder<void>(
      future: initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError || !cameraController!.value.isInitialized) {
             return Center(child: Text("Error initializing camera: ${snapshot.error}"));
          }
          // Calculate aspect ratio and fit
          final mediaQuery = MediaQuery.of(context);
          final screenWidth = mediaQuery.size.width;
          final screenHeight = mediaQuery.size.height;
          // Ensure aspectRatio is calculated only after initialization
          final cameraAspectRatio = cameraController!.value.aspectRatio;

          // Use FittedBox to cover the screen while maintaining aspect ratio
          return Center(
            child: OverflowBox( // Allows child to exceed parent bounds
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: SizedBox(
                width: screenWidth, // Force width to match screen
                height: screenHeight, // Force height to match screen
                child: FittedBox(
                  fit: BoxFit.cover, // Cover the container
                  child: SizedBox(
                    // Calculate the size needed to maintain aspect ratio while covering
                    width: screenHeight * cameraAspectRatio, // Based on height coverage
                    height: screenHeight,
                    child: CameraPreview(cameraController!),
                  ),
                ),
              ),
            ),
          );
        } else {
          // While waiting for initialization
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}