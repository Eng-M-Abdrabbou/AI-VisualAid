// lib/core/models/feature_config.dart
import 'package:flutter/material.dart';

class FeatureConfig {
  final String id; // Unique identifier (e.g., 'object_detection')
  final String title;
  final Color color;
  final List<String> voiceCommandKeywords;
  final WidgetBuilder pageBuilder; // Function to build the page widget
  final VoidCallback? action; // Optional: Action to execute on tap

  const FeatureConfig({
    required this.id,
    required this.title,
    required this.color,
    required this.voiceCommandKeywords,
    required this.pageBuilder,
    this.action,
  });
}