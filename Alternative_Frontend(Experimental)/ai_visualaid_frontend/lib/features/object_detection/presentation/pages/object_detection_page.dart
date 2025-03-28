// lib/features/object_detection/presentation/pages/object_detection_page.dart
import 'package:flutter/material.dart';
import '../../../../presentation/widgets/page_content.dart'; // Adjust import if needed

class ObjectDetectionPage extends StatelessWidget {
  const ObjectDetectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    // You can customize this page's content.
    // For now, it just shows the title using the shared PageContent widget.
    // Later, this could display bounding boxes or results.
    return const PageContent(
      title: 'Object Detection', // Or fetch dynamically if needed
      content: 'Object Detection Content Area', // Placeholder
      color: Colors.blue, // Or fetch dynamically
    );
  }
}