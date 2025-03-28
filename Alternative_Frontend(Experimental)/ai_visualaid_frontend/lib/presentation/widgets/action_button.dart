// lib/presentation/widgets/action_button.dart
import 'package:flutter/material.dart';

class ActionButton extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isListening;
  final Color color;

  const ActionButton({
    super.key,
    this.onTap,
    this.onLongPress,
    required this.isListening,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isListening ? Colors.red.shade100 : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(25),
                  spreadRadius: 2,
                  blurRadius: 5,
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Icon(
              isListening ? Icons.mic : Icons.play_arrow,
              color: isListening ? Colors.red : color.withAlpha(180),
              size: 60,
            ),
          ),
        ),
      ),
    );
  }
}