// lib/features/text_detection/presentation/pages/text_detection_page.dart
import 'package:flutter/material.dart';
// Removed PageContent import

class TextDetectionPage extends StatelessWidget {
  final String detectionResult; // Added to receive results

  const TextDetectionPage({
    super.key,
    required this.detectionResult // Make it required
  });

  @override
  Widget build(BuildContext context) {
    // Display the result directly in the center
    return Container(
      // Transparent background allows camera view to show through
      color: Colors.transparent,
      alignment: Alignment.center,
       padding: const EdgeInsets.symmetric(horizontal: 20.0), // Add padding
      child: Text(
        detectionResult.replaceAll('_', ' '), // Format result here
        style: const TextStyle(
          fontSize: 24, // Adjust size as needed
          fontWeight: FontWeight.bold,
          color: Colors.white, // White text for visibility over camera
          shadows: [ // Add shadow for better readability
            Shadow(
              blurRadius: 8.0,
              color: Colors.black87, // Slightly darker shadow
              offset: Offset(2.0, 2.0),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}