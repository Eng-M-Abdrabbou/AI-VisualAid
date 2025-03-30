// lib/features/feature_registry.dart
import 'package:flutter/material.dart';
import '../core/models/feature_config.dart';

// Import feature pages
import 'object_detection/presentation/pages/object_detection_page.dart';
import 'scene_detection/presentation/pages/scene_detection_page.dart';
import 'text_detection/presentation/pages/text_detection_page.dart';
// *** ADD IMPORT FOR HAZARD DETECTION PAGE ***
import 'hazard_detection/presentation/pages/hazard_detection_page.dart';

// --- Feature Definitions ---

const FeatureConfig objectDetectionFeature = FeatureConfig(
  id: 'object_detection',
  title: 'Object Detection',
  color: Colors.blue,
  // Keep original voice commands
  voiceCommandKeywords: ['page 1', 'first page', 'object detection'],
  pageBuilder: _buildObjectDetectionPage,
  // Action is not needed as it's handled by real-time updates or manual trigger logic
);

// *** ADD HAZARD DETECTION FEATURE CONFIG ***
const FeatureConfig hazardDetectionFeature = FeatureConfig(
  id: 'hazard_detection', // Unique ID for the new feature
  title: 'Hazard Detection', // Title for the banner
  color: Colors.orangeAccent, // Choose a distinct color (e.g., orange for warning)
  // *** ADD VOICE COMMANDS FOR HAZARD DETECTION ***
  voiceCommandKeywords: ['page 2', 'second page', 'hazard', 'danger', 'alert', 'hazards', 'hazard detection'], // Keywords to navigate here
  pageBuilder: _buildHazardDetectionPage, // Link to its builder function
  // No specific action needed on tap, it's real-time
);

const FeatureConfig sceneDetectionFeature = FeatureConfig(
  id: 'scene_detection',
  title: 'Scene Detection',
  color: Colors.green,
  // Keep original voice commands
  voiceCommandKeywords: ['page 3', 'third page', 'scene detection'],
  pageBuilder: _buildSceneDetectionPage,
);

const FeatureConfig textDetectionFeature = FeatureConfig(
  id: 'text_detection',
  title: 'Text Detection',
  color: Colors.red,
  // Keep original voice commands
  voiceCommandKeywords: ['page 4', 'fourth page', 'text detection'],
  pageBuilder: _buildTextDetectionPage,
);

// --- List of All Features ---

// This list defines the order and the features included in the app.
// The order here determines the swipe order in the PageView.
final List<FeatureConfig> availableFeatures = [
  objectDetectionFeature,
  hazardDetectionFeature, // *** ADD HAZARD FEATURE TO THE LIST (e.g., after Object Detection) ***
  sceneDetectionFeature,
  textDetectionFeature,
];

// --- Widget Builders (kept private to this file) ---
// These functions are simple placeholders because the actual page widgets
// are constructed within HomeScreen's PageView.builder, where the
// necessary state (_lastObjectResult, _isHazardAlertActive, etc.) is available.

Widget _buildObjectDetectionPage(BuildContext context) {
  // This is just a formality for the FeatureConfig structure.
  // The actual ObjectDetectionPage is built in HomeScreen.
  return const Placeholder();
}

// *** ADD HAZARD DETECTION PAGE BUILDER FUNCTION ***
Widget _buildHazardDetectionPage(BuildContext context) {
  // This is just a formality for the FeatureConfig structure.
  // The actual HazardDetectionPage is built in HomeScreen.
  return const Placeholder();
}

Widget _buildSceneDetectionPage(BuildContext context) {
  // Formality for FeatureConfig. Actual page built in HomeScreen.
  return const Placeholder();
}

Widget _buildTextDetectionPage(BuildContext context) {
  // Formality for FeatureConfig. Actual page built in HomeScreen.
  return const Placeholder();
}