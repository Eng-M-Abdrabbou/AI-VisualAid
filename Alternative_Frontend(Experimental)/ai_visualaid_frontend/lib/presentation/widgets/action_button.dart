// lib/presentation/widgets/action_button.dart
import 'package:flutter/material.dart';

class ActionButton extends StatelessWidget {
  final VoidCallback? onTap; // Can be null if disabled
  final VoidCallback? onLongPress;
  final bool isListening;
  final Color color;

  const ActionButton({
    super.key,
    this.onTap, // Keep accepting null
    this.onLongPress,
    required this.isListening,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if the button should appear active for tap
    final bool isTapEnabled = onTap != null;
    // Use a slightly dimmed color or different icon when tap is disabled
    final iconColor = isListening
        ? Colors.red // Listening color override
        : isTapEnabled
            ? color.withAlpha(200) // Active color
            : Colors.grey.shade600; // Disabled color

    final buttonColor = isListening ? Colors.red.shade100 : Colors.white;
    final icon = isListening
        ? Icons.mic // Microphone when listening
        : isTapEnabled
            ? Icons.play_arrow // Play icon when tap enabled (manual trigger)
            : Icons.camera; // Camera icon when tap disabled (real-time auto mode)


    return Positioned(
      // Adjust positioning if needed (e.g., slightly higher)
      bottom: 80, // Moved up slightly from 100 to better clear snackbar potentially
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          // Only assign onTap if it's not null
          onTap: onTap,
          onLongPress: onLongPress, // Long press always works for speech
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buttonColor,
              boxShadow: [
                BoxShadow(
                  // Make shadow softer when disabled? Optional.
                  color: Colors.black.withAlpha(isTapEnabled ? 60 : 30),
                  spreadRadius: isTapEnabled ? 3 : 1,
                  blurRadius: isTapEnabled ? 6 : 3,
                  offset: Offset(0, isTapEnabled ? 2 : 1),
                ),
              ],
              // Optional: Add a border that changes color when disabled
              // border: Border.all(
              //   color: isTapEnabled ? Colors.transparent : Colors.grey.shade400,
              //   width: 1.0,
              // )
            ),
            padding: const EdgeInsets.all(15), // Slightly larger padding
            child: Icon(
              icon, // Use the determined icon
              color: iconColor, // Use the determined color
              size: 60, // Keep size consistent
            ),
          ),
        ),
      ),
    );
  }
}