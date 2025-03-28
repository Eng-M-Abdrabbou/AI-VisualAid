// lib/features/text_detection/presentation/pages/text_detection_page.dart
import 'package:flutter/material.dart';
import '../../../../presentation/widgets/page_content.dart'; // Adjust import

class TextDetectionPage extends StatelessWidget {
  const TextDetectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageContent(
      title: 'Text Detection',
      content: 'Text Detection Content Area',
      color: Colors.red,
    );
  }
}