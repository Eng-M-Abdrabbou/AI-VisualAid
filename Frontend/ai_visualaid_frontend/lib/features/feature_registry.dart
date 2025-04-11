import 'package:flutter/material.dart';
import '../core/models/feature_config.dart';

import 'object_detection/presentation/pages/object_detection_page.dart';
import 'scene_detection/presentation/pages/scene_detection_page.dart';
import 'text_detection/presentation/pages/text_detection_page.dart';
import 'hazard_detection/presentation/pages/hazard_detection_page.dart';
import 'barcode_scanner/presentation/pages/barcode_scanner_page.dart';


const FeatureConfig objectDetectionFeature = FeatureConfig(
  id: 'object_detection',
  title: 'Object Detection',
  color: Colors.blue,
  voiceCommandKeywords: ['page 1', 'first page', 'object detection'],
  pageBuilder: _buildObjectDetectionPage,
);

const FeatureConfig hazardDetectionFeature = FeatureConfig(
  id: 'hazard_detection',
  title: 'Hazard Detection',
  color: Colors.orangeAccent,
  voiceCommandKeywords: ['page 2', 'second page', 'hazard', 'danger', 'alert', 'hazards', 'hazard detection'],
  pageBuilder: _buildHazardDetectionPage,
);

const FeatureConfig sceneDetectionFeature = FeatureConfig(
  id: 'scene_detection',
  title: 'Scene Detection',
  color: Colors.green,
  voiceCommandKeywords: ['page 3', 'third page', 'scene detection'],
  pageBuilder: _buildSceneDetectionPage,
);

const FeatureConfig textDetectionFeature = FeatureConfig(
  id: 'text_detection',
  title: 'Text Detection',
  color: Colors.red,
  voiceCommandKeywords: ['page 4', 'fourth page', 'text detection'],
  pageBuilder: _buildTextDetectionPage,
);


const FeatureConfig barcodeScannerFeature = FeatureConfig(
  id: 'barcode_scanner',
  title: 'Barcode Scanner',
  color: Colors.teal,
  voiceCommandKeywords: ['page 5', 'fifth page', 'barcode', 'scan code', 'scanner'],
  pageBuilder: _buildBarcodeScannerPage,
);


final List<FeatureConfig> availableFeatures = [
  objectDetectionFeature,
  hazardDetectionFeature,
  sceneDetectionFeature,
  textDetectionFeature,
  barcodeScannerFeature,
];


Widget _buildObjectDetectionPage(BuildContext context) {
  return const Placeholder();
}

Widget _buildHazardDetectionPage(BuildContext context) {
  return const Placeholder();
}

Widget _buildSceneDetectionPage(BuildContext context) {
  return const Placeholder();
}

Widget _buildTextDetectionPage(BuildContext context) {
  return const Placeholder();
}

Widget _buildBarcodeScannerPage(BuildContext context) {
  return const Placeholder();
}