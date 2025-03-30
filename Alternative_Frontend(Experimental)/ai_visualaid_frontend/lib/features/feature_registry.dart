// lib/features/feature_registry.dart
import 'package:flutter/material.dart';
import '../core/models/feature_config.dart';


import 'object_detection/presentation/pages/object_detection_page.dart';
import 'scene_detection/presentation/pages/scene_detection_page.dart';
import 'text_detection/presentation/pages/text_detection_page.dart';
import 'hazard_detection/presentation/pages/hazard_detection_page.dart';



const FeatureConfig objectDetectionFeature = FeatureConfig(
  id: 'object_detection',
  title: 'Object Detection',
  color: Colors.blue,
  voiceCommandKeywords: ['page 1', 'first page', 'object detection', 'what is this thing','object'],
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
  voiceCommandKeywords: ['page 3', 'third page', 'scene detection','where am I','what is this place','scene','place'],
  pageBuilder: _buildSceneDetectionPage,
);

const FeatureConfig textDetectionFeature = FeatureConfig(
  id: 'text_detection',
  title: 'Text Detection',
  color: Colors.red,
  voiceCommandKeywords: ['page 4', 'fourth page', 'text detection','text','what is this text','what is this word','what is this letter','what is this character','what is this symbol','what is this number','what am I reading','what is written'],
  pageBuilder: _buildTextDetectionPage,
);




final List<FeatureConfig> availableFeatures = [
  objectDetectionFeature,
  hazardDetectionFeature,
  sceneDetectionFeature,
  textDetectionFeature,
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