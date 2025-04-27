import 'package:flutter/material.dart';
import '../core/models/feature_config.dart';

// Import page widgets if you plan to use the pageBuilder directly for simple placeholders,
// but the actual pages are now built conditionally in home_screen.dart's PageView.builder.
// import 'object_detection/presentation/pages/object_detection_page.dart';
// import 'scene_detection/presentation/pages/scene_detection_page.dart';
// import 'text_detection/presentation/pages/text_detection_page.dart';
// import 'hazard_detection/presentation/pages/hazard_detection_page.dart';
// import 'barcode_scanner/presentation/pages/barcode_scanner_page.dart';
// import 'focus_mode/presentation/pages/focus_mode_page.dart'; // New


// --- Feature Definitions ---

const FeatureConfig objectDetectionFeature = FeatureConfig(
  id: 'object_detection',
  title: 'Object Detection',
  color: Colors.blue,
  voiceCommandKeywords: ['page 1', 'first page', 'object detection', 'detect object', 'objects'],
  pageBuilder: _buildPlaceholderPage, // Placeholder - actual page built in HomeScreen
);

const FeatureConfig hazardDetectionFeature = FeatureConfig(
  id: 'hazard_detection',
  title: 'Hazard Detection',
  color: Colors.orangeAccent,
  voiceCommandKeywords: ['page 2', 'second page', 'hazard', 'danger', 'alert', 'hazards', 'hazard detection'],
  pageBuilder: _buildPlaceholderPage, // Placeholder
);

// --- New Focus Mode Feature ---
const FeatureConfig focusModeFeature = FeatureConfig(
  id: 'focus_mode',
  title: 'Focus Mode',
  color: Colors.purple, // Or another distinct color
  voiceCommandKeywords: ['page 3', 'third page', 'focus mode', 'focus', 'find object', 'find'], // Added more keywords
  pageBuilder: _buildPlaceholderPage, // Placeholder
);
// --- End New Feature ---

const FeatureConfig sceneDetectionFeature = FeatureConfig(
  id: 'scene_detection',
  title: 'Scene Detection',
  color: Colors.green,
  voiceCommandKeywords: ['page 4', 'fourth page', 'scene detection', 'describe scene'], // Adjusted index due to new feature
  pageBuilder: _buildPlaceholderPage, // Placeholder
);

const FeatureConfig textDetectionFeature = FeatureConfig(
  id: 'text_detection',
  title: 'Text Detection',
  color: Colors.red,
  voiceCommandKeywords: ['page 5', 'fifth page', 'text detection', 'read text'], // Adjusted index
  pageBuilder: _buildPlaceholderPage, // Placeholder
);

const FeatureConfig barcodeScannerFeature = FeatureConfig(
  id: 'barcode_scanner',
  title: 'Barcode Scanner',
  color: Colors.teal,
  voiceCommandKeywords: ['page 6', 'sixth page', 'barcode', 'scan code', 'scanner'], // Adjusted index
  pageBuilder: _buildPlaceholderPage, // Placeholder
);


// --- List of Available Features (Order matters for page index) ---

final List<FeatureConfig> availableFeatures = [
  objectDetectionFeature,   // Index 0
  hazardDetectionFeature,   // Index 1
  focusModeFeature,         // Index 2 (New)
  sceneDetectionFeature,    // Index 3
  textDetectionFeature,     // Index 4
  barcodeScannerFeature,    // Index 5
];


// --- Placeholder Builder Function ---
// Since pages are now built conditionally in HomeScreen's PageView builder,
// these pageBuilder functions in FeatureConfig might not be strictly necessary
// unless used elsewhere. A simple placeholder is fine.
Widget _buildPlaceholderPage(BuildContext context) {
  // This function is less relevant now as HomeScreen handles page creation.
  // Returning a simple placeholder.
  return const Center(child: Text("Loading...", style: TextStyle(color: Colors.white)));
}

// You can remove the specific build functions like _buildObjectDetectionPage, etc.
// if they are not used anywhere else, as HomeScreen now handles the logic.

Widget _buildObjectDetectionPage(BuildContext context) => const Placeholder();
Widget _buildHazardDetectionPage(BuildContext context) => const Placeholder();
Widget _buildSceneDetectionPage(BuildContext context) => const Placeholder();
Widget _buildTextDetectionPage(BuildContext context) => const Placeholder();
Widget _buildBarcodeScannerPage(BuildContext context) => const Placeholder();
Widget _buildFocusModePage(BuildContext context) => const Placeholder(); // New placeholder
