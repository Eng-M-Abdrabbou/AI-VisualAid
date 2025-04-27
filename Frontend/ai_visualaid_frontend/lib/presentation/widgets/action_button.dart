import 'package:flutter/material.dart';

class ActionButton extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isListening;
  final Color color;
  final IconData? iconOverride; // New optional parameter

  const ActionButton({
    super.key,
    this.onTap,
    this.onLongPress,
    required this.isListening,
    required this.color,
    this.iconOverride, // Accept the override
  });

  @override
  Widget build(BuildContext context) {
    final bool isTapEnabled = onTap != null;

    // Determine icon based on state or override
    final IconData finalIcon = iconOverride ?? // Use override if provided
                               (isListening
                                  ? Icons.mic
                                  : isTapEnabled
                                      ? Icons.play_arrow
                                      : Icons.camera_alt);

    final iconColor = isListening
        ? Colors.red // Listening color
        : isTapEnabled || iconOverride == Icons.filter_center_focus // Active color if tap enabled OR focus icon
            ? color.withAlpha(200)
            : Colors.grey.shade600; // Inactive color

    final buttonColor = isListening ? Colors.red.shade100 : Colors.white;

    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buttonColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isTapEnabled || iconOverride != null ? 60 : 30),
                  spreadRadius: isTapEnabled || iconOverride != null ? 3 : 1,
                  blurRadius: isTapEnabled || iconOverride != null ? 6 : 3,
                  offset: Offset(0, isTapEnabled || iconOverride != null ? 2 : 1),
                ),
              ],
            ),
            padding: const EdgeInsets.all(15),
            child: Icon(
              finalIcon, // Use the determined icon
              color: iconColor,
              size: 60,
            ),
          ),
        ),
      ),
    );
  }
}