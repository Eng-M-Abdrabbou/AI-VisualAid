// lib/features/scene_detection/presentation/pages/scene_detection_page.dart
import 'package:flutter/material.dart';
import '../../../../presentation/widgets/page_content.dart'; // Adjust import

class SceneDetectionPage extends StatelessWidget {
  const SceneDetectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageContent(
      title: 'Scene Detection',
      content: 'Scene Detection Content Area',
      color: Colors.green,
    );
  }
}