// lib/presentation/widgets/camera_view_widget.dart
import 'dart:math'; // For Point calculation if needed, but likely not here
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
    // --- Start of existing error handling and future builder ---
    if (cameraController == null || initializeControllerFuture == null) {
      return Container(
        color: Colors.black,
        child: const Center(child: Text("Camera not available", style: TextStyle(color: Colors.white))),
      );
    }

    return FutureBuilder<void>(
      future: initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
             color: Colors.black,
             child: const Center(child: CircularProgressIndicator())
          );
        }

        final controller = cameraController!;

        if (snapshot.hasError || !controller.value.isInitialized) {
           String errorMessage = "..."; // Simplified
           if (snapshot.hasError && snapshot.error is CameraException) {
              errorMessage = "Camera Error: ${(snapshot.error as CameraException).description}";
           } else if (snapshot.hasError) {
               errorMessage = "Error initializing camera: ${snapshot.error}";
           } else {
               errorMessage = "Camera not initialized";
           }
           debugPrint("[CameraViewWidget] $errorMessage");
           return Container(
             color: Colors.black,
             child: Center(child: Text(errorMessage, style: TextStyle(color: Colors.red), textAlign: TextAlign.center)),
           );
        }
        // --- End of existing error handling ---


        final mediaQuery = MediaQuery.of(context);
        final screenWidth = mediaQuery.size.width;
        final screenHeight = mediaQuery.size.height;
        final screenAspectRatio = screenWidth / screenHeight; // Should be < 1 for portrait

        final reportedCameraAspectRatio = controller.value.aspectRatio;
        if (reportedCameraAspectRatio <= 0) {
           return Container(color: Colors.black, child: const Center(child: Text("Invalid Camera Aspect Ratio", style: TextStyle(color: Colors.red))));
        }

        debugPrint("[CameraViewWidget] Screen Size: ${screenWidth}x$screenHeight (AR: $screenAspectRatio)");
        debugPrint("[CameraViewWidget] Reported Camera AR: $reportedCameraAspectRatio");


        Widget preview = RotatedBox(
          // Rotate 90 degrees clockwise. If upside down, change to 3.
          quarterTurns: 0,
          child: CameraPreview(controller),
        );


        final rotatedPreviewAspectRatio = 1.0 / reportedCameraAspectRatio;
        debugPrint("[CameraViewWidget] Rotated Preview AR: $rotatedPreviewAspectRatio");


 
        return Container(
          width: screenWidth,
          height: screenHeight,
          color: Colors.black, // Background
          child: FittedBox(
            fit: BoxFit.cover, // Scale the child to cover this container
            alignment: Alignment.center,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(

              width: 100, // Arbitrary base width
              height: 100 / rotatedPreviewAspectRatio, // Height matching the rotated ratio
              child: preview, // Place the rotated preview widget here
            ),
          ),
        );
      },
    );
  }
}