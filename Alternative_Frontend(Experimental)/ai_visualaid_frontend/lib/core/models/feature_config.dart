// lib/core/models/feature_config.dart
import 'package:flutter/material.dart';

class FeatureConfig {
  final String id; 
  final String title;
  final Color color;
  final List<String> voiceCommandKeywords;
  final WidgetBuilder pageBuilder; 
  final VoidCallback? action; 

  const FeatureConfig({
    required this.id,
    required this.title,
    required this.color,
    required this.voiceCommandKeywords,
    required this.pageBuilder,
    this.action,
  });
}