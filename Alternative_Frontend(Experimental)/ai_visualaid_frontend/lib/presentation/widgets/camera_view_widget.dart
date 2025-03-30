// lib/presentation/widgets/camera_view_widget.dart
import 'dart:math'; 
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
           String errorMessage = "..."; 
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
 


        final mediaQuery = MediaQuery.of(context);
        final screenWidth = mediaQuery.size.width;
        final screenHeight = mediaQuery.size.height;
        final screenAspectRatio = screenWidth / screenHeight; 

        final reportedCameraAspectRatio = controller.value.aspectRatio;
        if (reportedCameraAspectRatio <= 0) {
           return Container(color: Colors.black, child: const Center(child: Text("Invalid Camera Aspect Ratio", style: TextStyle(color: Colors.red))));
        }

        debugPrint("[CameraViewWidget] Screen Size: ${screenWidth}x$screenHeight (AR: $screenAspectRatio)");
        debugPrint("[CameraViewWidget] Reported Camera AR: $reportedCameraAspectRatio");


        Widget preview = RotatedBox(
          quarterTurns: 0,
          child: CameraPreview(controller),
        );


        final rotatedPreviewAspectRatio = 1.0 / reportedCameraAspectRatio;
        debugPrint("[CameraViewWidget] Rotated Preview AR: $rotatedPreviewAspectRatio");


 
        return Container(
          width: screenWidth,
          height: screenHeight,
          color: Colors.black, 
          child: FittedBox(
            fit: BoxFit.cover, 
            alignment: Alignment.center,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: 100, 
              height: 100 / rotatedPreviewAspectRatio, 
              child: preview, 
            ),
          ),
        );
      },
    );
  }
}