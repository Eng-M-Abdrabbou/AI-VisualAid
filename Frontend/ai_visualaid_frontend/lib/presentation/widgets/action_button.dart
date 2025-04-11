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

    final bool isTapEnabled = onTap != null;

    final iconColor = isListening
        ? Colors.red
        : isTapEnabled
            ? color.withAlpha(200)
            : Colors.grey.shade600;

    final buttonColor = isListening ? Colors.red.shade100 : Colors.white;


    final icon = isListening
        ? Icons.mic
        : isTapEnabled
            ? Icons.play_arrow
            : Icons.camera_alt;


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

                  color: Colors.black.withAlpha(isTapEnabled ? 60 : 30),
                  spreadRadius: isTapEnabled ? 3 : 1,
                  blurRadius: isTapEnabled ? 6 : 3,
                  offset: Offset(0, isTapEnabled ? 2 : 1),
                ),
              ],


            ),
            padding: const EdgeInsets.all(15),
            child: Icon(
              icon,
              color: iconColor,
              size: 60,
            ),
          ),
        ),
      ),
    );
  }
}