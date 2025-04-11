// lib/features/object_detection/presentation/pages/object_detection_page.dart
import 'package:flutter/material.dart';


class ObjectDetectionPage extends StatelessWidget {
  final String detectionResult; 

  const ObjectDetectionPage({
    super.key,
    required this.detectionResult 
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Text(
        detectionResult.replaceAll('_', ' '),
        style: const TextStyle(
          fontSize: 24, 
          fontWeight: FontWeight.bold,
          color: Colors.white, 
          shadows: [ 
            Shadow(
              blurRadius: 8.0,
              color: Colors.black87, 
              offset: Offset(2.0, 2.0),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}