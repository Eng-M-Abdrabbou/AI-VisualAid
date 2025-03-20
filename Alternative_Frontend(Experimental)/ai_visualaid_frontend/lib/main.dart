import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void main() async {
  // Ensure plugin services are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Obtain a list of the available cameras on the device
  final cameras = await availableCameras();
  
  // Get the first camera (usually the back camera)
  final firstCamera = cameras.first;
  
  runApp(CarouselNavigationApp(camera: firstCamera));
}

// Define PageModel class
class PageModel {
  final String title;
  final String content;
  final Color color;

  const PageModel({
    required this.title, 
    required this.content, 
    required this.color
  });
}

// Define PageContent class
class PageContent extends StatelessWidget {
  final String title;
  final String content;
  final Color color;

  const PageContent({
    Key? key, 
    required this.title,
    required this.content, 
    required this.color,
  }) : super(key: key);

 @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent, // Make background transparent
      child: Center(
        child: Text(
          content,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white, // Ensure text is visible on camera background
            shadows: [
              Shadow(
                blurRadius: 10.0,
                color: Colors.black,
                offset: Offset(2.0, 2.0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CarouselNavigationApp extends StatelessWidget {
  final CameraDescription camera;

  const CarouselNavigationApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CarouselPage(camera: camera),
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
    );
  }
}

class CarouselPage extends StatefulWidget {
  final CameraDescription camera;

  const CarouselPage({Key? key, required this.camera}) : super(key: key);

  @override
  _CarouselPageState createState() => _CarouselPageState();
}

class _CarouselPageState extends State<CarouselPage> {
  late CameraController _cameraController;
  late Future<void> _initializeControllerFuture;

  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Define the pages for the carousel with custom titles
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
    // Initialize the camera controller
    _cameraController = CameraController(
      widget.camera, 
      ResolutionPreset.max,
    );

    // Next, initialize the controller. This returns a Future.
    _initializeControllerFuture = _cameraController.initialize();
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _cameraController.dispose();
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        // Camera Preview as Background (for ALL pages)
        FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              // If the Future is complete, display the preview.
              return CameraPreview(_cameraController);
            } else {
              // Otherwise, display a loading indicator.
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),

          // Background Pages (now behind camera)
      PageView(
          controller: _pageController,
          children: _pages.map((page) => PageContent(
            title: page.title,
            content: page.content,
            color: page.color,
          )).toList(),
          onPageChanged: (index) {
            setState(() {
              _currentPage = index;
            });
          },
        ),
          
          // Floating Bubble on Top (in front of everything)
         SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                decoration: BoxDecoration(
                  color: _pages[_currentPage].color.withAlpha((0.7 * 255).toInt()),
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
}}