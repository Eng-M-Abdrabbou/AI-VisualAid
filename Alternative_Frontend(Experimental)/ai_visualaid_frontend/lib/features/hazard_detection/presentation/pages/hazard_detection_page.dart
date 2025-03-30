// lib/features/hazard_detection/presentation/pages/hazard_detection_page.dart
import 'package:flutter/material.dart';

class HazardDetectionPage extends StatelessWidget {
  final String detectionResult; // The name of the detected object
  final bool isHazardAlert;     // Flag indicating if it's a hazard to display

  const HazardDetectionPage({
    super.key,
    required this.detectionResult,
    required this.isHazardAlert,
  });

  @override
  Widget build(BuildContext context) {
    // Only display the content if it's an active hazard alert
    if (!isHazardAlert) {
      // Return an empty container or a subtle placeholder if desired
      return Container(
         color: Colors.transparent,
         alignment: Alignment.center,
         padding: const EdgeInsets.symmetric(horizontal: 20.0),
         child: const Text(
           "", // Added empty string to resolve missing argument
           // Optional: Placeholder text when no hazard is detected
           // "Scanning for hazards...",
           // style: TextStyle(
           //   fontSize: 20,
           //   color: Colors.white.withOpacity(0.7),
           //   shadows: [ Shadow( blurRadius: 4.0, color: Colors.black54, offset: Offset(1.0, 1.0), ), ],
           // ),
           // textAlign: TextAlign.center,
         ),
      );
    }

    // Display the hazard alert prominently
    return Container(
      // Semi-transparent red overlay during alert? (Optional)
      // color: Colors.red.withOpacity(0.1),
      color: Colors.transparent, // Keep camera view clear
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Text(
        // Format the result (e.g., replace underscores, capitalize)
        detectionResult.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          fontSize: 48, // Larger font size for alert
          fontWeight: FontWeight.bold,
          color: Colors.redAccent, // Bright red color for alert
          shadows: [ // Enhance readability
            Shadow(
              blurRadius: 10.0,
              color: Colors.black87,
              offset: Offset(3.0, 3.0),
            ),
             Shadow( // Add a subtle white glow maybe?
              blurRadius: 15.0,
              color: Colors.white.withOpacity(0.3),
              offset: Offset(0, 0),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}