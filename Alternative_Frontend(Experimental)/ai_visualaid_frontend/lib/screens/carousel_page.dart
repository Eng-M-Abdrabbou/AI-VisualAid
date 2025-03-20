import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/page_model.dart';
import '../widgets/page_content.dart';

class CarouselPage extends StatefulWidget {
  final CameraDescription? camera;

  const CarouselPage({Key? key, required this.camera}) : super(key: key);

  @override
  State<CarouselPage> createState() => _CarouselPageState();
}

class _CarouselPageState extends State<CarouselPage> {
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Speech recognition instance
  final stt.SpeechToText _speechToText = stt.SpeechToText();

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
      title: 'Text Detection',
      content: 'Content 3',
      color: Colors.red,
    ),
  ];

  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _initializeCameraController();
    _initializeSpeechRecognition();
  }

  void _initializeCameraController() {
    if (widget.camera != null) {
      _cameraController = CameraController(
        widget.camera!,
        ResolutionPreset.max,
      );
      _initializeControllerFuture = _cameraController!.initialize();
    }
  }

  void _initializeSpeechRecognition() async {
    bool available = await _speechToText.initialize(
      onStatus: (status) => debugPrint('Speech status: $status'),
      onError: (error) => debugPrint('Speech error: $error'),
    );
    if (!available) {
      debugPrint('Speech recognition not available');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _speechToText.cancel();
    super.dispose();
  }

  Future<void> _startVoiceNavigation() async {
    if (_isListening) return;

    // Check if speech recognition is available
    bool available = await _speechToText.initialize(
      onStatus: (status) {
        debugPrint('Speech recognition status: $status');
        if (status == 'listening') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Listening... Speak a page command'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      },
      onError: (error) {
        debugPrint('Speech recognition error: ${error.errorMsg}');
        
        // Handle specific permission-related errors
        if (error.errorMsg.toLowerCase().contains('permission')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Microphone permission error: ${error.errorMsg}'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () {
                  // Provide guidance on how to enable permissions
                  _showPermissionInstructions();
                },
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speech error: ${error.errorMsg}')),
          );
        }
      },
    );

    // Check if speech recognition is not available
    if (!available) {
      debugPrint('Speech recognition not available');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition unavailable')),
      );
      return;
    }

    try {
      // Check microphone permission explicitly
      bool hasMicPermission = await _speechToText.hasPermission;
      if (!hasMicPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Microphone permission is required'),
            action: SnackBarAction(
              label: 'Help',
              onPressed: _showPermissionInstructions,
            ),
          ),
        );
        return;
      }

      setState(() {
        _isListening = true;
      });

      _speechToText.listen(
        onResult: (result) {
          debugPrint('Speech result: ${result.recognizedWords}');
          debugPrint('Is final result: ${result.finalResult}');

          if (result.finalResult) {
            String command = result.recognizedWords.toLowerCase();
            debugPrint('Recognized command: $command');

            // Expanded navigation logic with more flexible matching
            final navigationCommands = {
              'page 1': 0,
              'first page': 0,
              'object detection': 0,
              'page 2': 1,
              'second page': 1,
              'scene detection': 1,
              'page 3': 2,
              'third page': 2,
              'text detection': 2,
            };

            final matchedPage = navigationCommands.entries.firstWhere(
              (entry) => command.contains(entry.key),
              orElse: () => MapEntry('', -1),
            );

            if (matchedPage.value != -1) {
              _navigateToPage(matchedPage.value);
              _stopVoiceNavigation();
            } else {
              debugPrint('No matching page command found');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Command not recognized. Try "page 1", "page 2", or "page 3"'),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        },
        listenFor: const Duration(seconds: 5),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      );
    } catch (e) {
      debugPrint('Voice navigation exception: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice navigation failed: $e')),
      );
      _stopVoiceNavigation();
    }
  }

  void _stopVoiceNavigation() {
    _speechToText.stop();
    setState(() {
      _isListening = false;
    });
  }

  void _navigateToPage(int pageIndex) {
    if (pageIndex >= 0 && pageIndex < _pages.length) {
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentPage = pageIndex;
      });
    }
  }

  void _showPermissionInstructions() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Microphone Permission'),
          content: const Text(
            'To use voice navigation:\n\n'
            '1. Go to your device Settings\n'
            '2. Find App Permissions or Application Manager\n'
            '3. Select this app\n'
            '4. Enable Microphone permissions',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraController != null)
            FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  final mediaQuery = MediaQuery.of(context);
                  final screenWidth = mediaQuery.size.width;
                  final screenHeight = mediaQuery.size.height;
                  final cameraAspectRatio = _cameraController!.value.aspectRatio;

                  return Center(
                    child: OverflowBox(
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      child: SizedBox(
                        width: screenWidth,
                        height: screenHeight,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: screenWidth / cameraAspectRatio,
                            height: screenHeight,
                            child: CameraPreview(_cameraController!),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            children: _pages.map((page) => Center(child: Text(page.title))).toList(),
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
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  switch (_currentPage) {
                    case 0: // Object Detection
                      debugPrint('Starting Object Detection');
                      break;
                    case 1: // Scene Detection
                      debugPrint('Starting Scene Detection');
                      break;
                    case 2: // Text Detection
                      debugPrint('Starting Text Detection');
                      break;
                  }
                },
                onLongPress: () {
                  if (!_isListening) {
                    _startVoiceNavigation();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Listening for voice commands...'),
                        duration: Duration(seconds: 5),
                      ),
                    );
                  } else {
                    _stopVoiceNavigation();
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening ? Colors.red.shade100 : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(25),
                        spreadRadius: 2,
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    _isListening ? Icons.mic : Icons.play_arrow,
                    color: _isListening ? Colors.red : _pages[_currentPage].color.withAlpha(180),
                    size: 60,
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