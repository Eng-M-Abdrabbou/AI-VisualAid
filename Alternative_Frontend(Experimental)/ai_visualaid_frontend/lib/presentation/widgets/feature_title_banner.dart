// lib/presentation/widgets/feature_title_banner.dart
import 'package:flutter/material.dart';

class FeatureTitleBanner extends StatelessWidget {
  final String title;
  final Color backgroundColor;

  const FeatureTitleBanner({
    super.key,
    required this.title,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false, 
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 65.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            decoration: BoxDecoration(
              color: backgroundColor.withAlpha((0.75 * 255).toInt()),
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Arial',
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 30,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}