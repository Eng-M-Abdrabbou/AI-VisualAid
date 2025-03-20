import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../models/page_model.dart';
import '../widgets/page_content.dart';

class CarouselPage extends StatefulWidget {
  final CameraDescription camera;

  const CarouselPage({super.key, required this.camera});

  @override
  _CarouselPageState createState() => _CarouselPageState();
}

class _CarouselPageState extends State<CarouselPage> {
  late CameraController _cameraController;
  late Future<void> _initializeControllerFuture;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<PageModel> _pages = const [
    PageModel(
      title: 'Object Detection',
      content: 'Content 1',
      color: Colors.blue,
    ),
    PageModel(
      title: 'Scene Detection',
      content: 'Content 2',
      color: Colors.green,
    ),
    PageModel(
      title: 'Hazard Detection',
      content: 'Content 3',
      color: Colors.orange,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.max,
    );
    _initializeControllerFuture = _cameraController.initialize();
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return CameraPreview(_cameraController);
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
          PageView(
            controller: _pageController,
            children: _pages
                .map((page) => PageContent(
                      title: page.title,
                      content: page.content,
                      color: page.color,
                    ))
                .toList(),
            onPageChanged: (index) => setState(() => _currentPage = index),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 20),
                  decoration: BoxDecoration(
                    color: _pages[_currentPage]
                        .color
                        .withAlpha((0.7 * 255).toInt()),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    _pages[_currentPage].title,
                    style: const TextStyle(
                      fontFamily: 'Arial',
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 30,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}