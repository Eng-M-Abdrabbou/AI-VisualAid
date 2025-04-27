import 'package:flutter/material.dart';

class FocusModePage extends StatelessWidget {
  final String? focusedObject;
  final bool isPrompting; // True when waiting for user to name the object
  final bool isObjectDetectedInFrame; // True if the focused object is detected anywhere
  final bool isObjectCentered; // True if the focused object is near the center

  const FocusModePage({
    super.key,
    required this.focusedObject,
    required this.isPrompting,
    required this.isObjectDetectedInFrame,
    required this.isObjectCentered,
  });

  @override
  Widget build(BuildContext context) {
    // Determine text style for visibility
    const TextStyle baseStyle = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      shadows: [
        Shadow(blurRadius: 8.0, color: Colors.black87, offset: Offset(2.0, 2.0)),
      ],
    );
    final TextStyle foundStyle = baseStyle.copyWith(
      fontSize: 48,
      color: Colors.lightGreenAccent, // Highlight when found
       shadows: [
        Shadow(blurRadius: 10.0, color: Colors.black, offset: Offset(3.0, 3.0)),
        Shadow(blurRadius: 15.0, color: Colors.white.withOpacity(0.4), offset: Offset(0,0)),
      ],
    );

    Widget content;

    if (isPrompting) {
      content = Text(
        "Say the object name...",
        style: baseStyle.copyWith(color: Colors.yellowAccent), // Prompt color
        textAlign: TextAlign.center,
      );
    } else if (focusedObject == null) {
      // Should ideally not happen if isPrompting is false, but handle defensively
      content = Text(
        "No object selected.\nLong press button to select.",
        style: baseStyle.copyWith(fontSize: 20),
        textAlign: TextAlign.center,
      );
    } else {
      // Object is selected
      if (isObjectCentered) {
        content = Text(
          "FOUND!",
          style: foundStyle,
          textAlign: TextAlign.center,
        );
      } else if (isObjectDetectedInFrame) {
        content = Text(
          "Finding: ${focusedObject ?? ''}",
          style: baseStyle.copyWith(color: Colors.orangeAccent), // Indicate searching/detected
          textAlign: TextAlign.center,
        );
      } else {
        content = Text(
          "Looking for: ${focusedObject ?? ''}",
          style: baseStyle, // Normal searching state
          textAlign: TextAlign.center,
        );
      }
    }

    return Container(
      color: Colors.transparent, // Make page background transparent
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: content,
    );
  }
}