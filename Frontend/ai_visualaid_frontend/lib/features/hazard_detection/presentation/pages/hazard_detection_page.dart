// lib/features/hazard_detection/presentation/pages/hazard_detection_page.dart
import 'package:flutter/material.dart';

class HazardDetectionPage extends StatelessWidget {
  final String detectionResult; 
  final bool isHazardAlert;     

  const HazardDetectionPage({
    super.key,
    required this.detectionResult,
    required this.isHazardAlert,
  });

  @override
  Widget build(BuildContext context) {
    if (!isHazardAlert) {
      return Container(
         color: Colors.transparent,
         alignment: Alignment.center,
         padding: const EdgeInsets.symmetric(horizontal: 20.0),
         child: const Text(
           "", 
         ),
      );
    }

    return Container(
      color: Colors.transparent, 
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Text(
        detectionResult.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          fontSize: 48, 
          fontWeight: FontWeight.bold,
          color: Colors.redAccent, 
          shadows: [ 
            Shadow(
              blurRadius: 10.0,
              color: Colors.black87,
              offset: Offset(3.0, 3.0),
            ),
             Shadow( 
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