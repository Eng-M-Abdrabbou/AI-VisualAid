// lib/features/feature_registry.dart
import 'package:flutter/material.dart';
import '../core/models/feature_config.dart';

// Import feature pages
import 'object_detection/presentation/pages/object_detection_page.dart';
import 'scene_detection/presentation/pages/scene_detection_page.dart';
import 'text_detection/presentation/pages/text_detection_page.dart';

// --- Feature Definitions ---

const FeatureConfig objectDetectionFeature = FeatureConfig(
  id: 'object_detection',
  title: 'Object Detection',
  color: Colors.blue,
  voiceCommandKeywords: ['page 1', 'first page', 'object detection'],
  pageBuilder: _buildObjectDetectionPage,
  // Action will be assigned in HomeScreen where context/services are available
);

const FeatureConfig sceneDetectionFeature = FeatureConfig(
  id: 'scene_detection',
  title: 'Scene Detection',
  color: Colors.green,
  voiceCommandKeywords: ['page 2', 'second page', 'scene detection'],
  pageBuilder: _buildSceneDetectionPage,
);

const FeatureConfig textDetectionFeature = FeatureConfig(
  id: 'text_detection',
  title: 'Text Detection',
  color: Colors.red,
  voiceCommandKeywords: ['page 3', 'third page', 'text detection'],
  pageBuilder: _buildTextDetectionPage,
);

// --- List of All Features ---

// This list defines the order and the features included in the app.
// To add/remove/reorder features, modify this list.
final List<FeatureConfig> availableFeatures = [
  objectDetectionFeature,
  sceneDetectionFeature,
  textDetectionFeature,
];

// --- Widget Builders (kept private to this file) ---

Widget _buildObjectDetectionPage(BuildContext context) {
  return const ObjectDetectionPage(detectionResult: '',);
}

Widget _buildSceneDetectionPage(BuildContext context) {
  return const SceneDetectionPage(detectionResult: '',);
}

Widget _buildTextDetectionPage(BuildContext context) {
  return const TextDetectionPage(detectionResult: '',);
}