import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

// --- Imports Based on Official Example & Deduced Pattern ---
import 'package:speech_to_text/speech_to_text.dart';
// Explicitly import the result and error types
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
// --- End Imports ---

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

// Core & Services
import '../../core/models/feature_config.dart';
import '../../core/services/websocket_service.dart';

// Features
import '../../features/feature_registry.dart';

// Widgets
import '../widgets/camera_view_widget.dart';
import '../widgets/feature_title_banner.dart';
import '../widgets/action_button.dart';

class HomeScreen extends StatefulWidget {
  final CameraDescription? camera;

  const HomeScreen({Key? key, required this.camera}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // --- Use Direct Types ---
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  // Official example uses this flag, let's keep it for consistency
  bool _speechEnabled = false;

  final WebSocketService _webSocketService = WebSocketService();
  late List<FeatureConfig> _features;

  @override
  void initState() {
    super.initState();
    _features = availableFeatures.map((config) {
      return FeatureConfig(
        id: config.id,
        title: config.title,
        color: config.color,
        voiceCommandKeywords: config.voiceCommandKeywords,
        pageBuilder: config.pageBuilder,
        action: () => _handleFeatureAction(config.id),
      );
    }).toList();

    _initializeCameraController();
    // Call the separate init method like the official example
    _initSpeech();
    _initializeWebSocket();
  }

  // --- Separate Init method like official example ---
  void _initSpeech() async {
    // Initialize with status and error listeners
    _speechEnabled = await _speechToText.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError, // Signature uses direct type
        debugLogging: kDebugMode);
    if (!_speechEnabled) {
      debugPrint('Speech recognition not available during init.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition unavailable.')),
        );
      }
    } else {
       debugPrint('Speech recognition initialized successfully.');
    }
    // Update state if needed after initialization completes
    if (mounted) {
       setState(() {});
    }
  }
  // --- End Init method ---


  void _initializeCameraController() {
     if (widget.camera != null) {
      _cameraController = CameraController(
        widget.camera!,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _initializeControllerFuture = _cameraController!.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
      }).catchError((error) {
        debugPrint("Camera initialization error: $error");
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Failed to initialize camera: $error")),
           );
        }
      });
    } else {
      debugPrint("No camera provided to HomeScreen");
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("No camera available")),
         );
      }
    }
  }

  void _initializeWebSocket() {
     _webSocketService.responseStream.listen(
      (data) {
        debugPrint('[HomeScreen] WebSocket Received: $data');
        // TODO: Handle received data (e.g., display results)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Server response: ${data['result'] ?? 'OK'}")),
          );
        }
      },
      onError: (error) {
        debugPrint('[HomeScreen] WebSocket Error: $error');
        String errorMessage = "Connection Error";
        if (error is WebSocketChannelException) {
          errorMessage = "Connection Error: ${error.message ?? 'WebSocket issue'}";
        } else {
          errorMessage = "Connection Error: ${error.toString()}";
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage)),
          );
        }
      },
      onDone: () {
        debugPrint('[HomeScreen] WebSocket connection closed.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Disconnected from server.')),
          );
        }
      },
    );
    _webSocketService.connect();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _cameraController?.dispose();
    // Stop listening if active before cancelling
    if (_speechToText.isListening) {
       _speechToText.stop();
    }
    _speechToText.cancel(); // Recommended by docs/examples
    _webSocketService.close();
    super.dispose();
  }

   void _handleFeatureAction(String featureId) async {
     debugPrint('Action triggered for feature: $featureId');
     if (_cameraController == null || !_cameraController!.value.isInitialized) {
       debugPrint('Camera not ready for action.');
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("Camera not ready")),
         );
       }
       return;
     }

     if (!_webSocketService.isConnected) {
       debugPrint('WebSocket not connected for action.');
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("Not connected to server")),
         );
       }
       _webSocketService.connect();
       return;
     }

     try {
       if (_cameraController!.value.isTakingPicture) {
         debugPrint('Camera busy, skipping action.');
         return;
       }

       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("Capturing..."), duration: Duration(seconds: 1)),
         );
       }
       final XFile imageFile = await _cameraController!.takePicture();
       debugPrint('Picture taken: ${imageFile.path}');

       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("Processing..."), duration: Duration(seconds: 2)),
         );
       }
       _webSocketService.sendImageForProcessing(imageFile, featureId);

     } on CameraException catch (e) {
       debugPrint('Error taking picture: ${e.code} - ${e.description}');
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Capture Error: ${e.description ?? e.code}")),
         );
       }
     } catch (e) {
       debugPrint('Error during feature action: $e');
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Action Error: $e")),
         );
       }
     }
   }

  void _handleSpeechStatus(String status) {
    debugPrint('Speech recognition status: $status');
    if (!mounted) return;
    // Use status constants from direct type
    final bool isCurrentlyListening = status == SpeechToText.listeningStatus;
    if (_isListening != isCurrentlyListening) {
       // Update state based on status
       setState(() {
          _isListening = isCurrentlyListening;
       });
    }
     // Update _speechEnabled based on status if needed (e.g., handle 'unavailable')
     // Example: if (status == SpeechToText.unavailable) { setState(() => _speechEnabled = false); }
  }

  // --- Use Direct Type ---
  void _handleSpeechError(SpeechRecognitionError error) {
    debugPrint('Speech recognition error: ${error.errorMsg} (Permanent: ${error.permanent})');
    if (!mounted) return;

    // Ensure listening state is reset on error
    if (_isListening) {
      setState(() => _isListening = false);
    }

    String errorMessage = 'Speech error: ${error.errorMsg}';
    SnackBarAction? action;

    if (error.errorMsg.contains('permission') || error.permanent) {
      errorMessage = 'Microphone permission error.';
      action = SnackBarAction(
        label: 'Help',
        onPressed: _showPermissionInstructions,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        action: action,
      ),
    );
     // Potentially disable speech if error is permanent
     // if(error.permanent && mounted) { setState(() => _speechEnabled = false); }
  }

  // --- Use Direct Type ---
  void _startListening() async {
    // No need to check isListening here, official example doesn't,
    // and the UI button logic handles it.
    // Ensure it's initialized and available first
     if (!_speechEnabled) {
        debugPrint('Attempted to listen but speech is not enabled/initialized.');
        // Maybe show a message? Or try initializing again?
        _initSpeech(); // Try re-initializing
        return;
     }
    // Check permission just before listening
     bool hasPermission = await _speechToText.hasPermission;
     if (!hasPermission) {
       debugPrint('Microphone permission denied before listening attempt.');
       if (mounted) {
         _showPermissionInstructions();
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Microphone permission needed.')),
         );
       }
       return;
     }

    // Use parameters matching your working CarouselPage
    await _speechToText.listen(
        onResult: _handleSpeechResult, // Signature uses direct type
        listenFor: const Duration(seconds: 7), // Keep your desired duration
        pauseFor: const Duration(seconds: 4), // Keep your desired duration
        partialResults: false, // Keep your desired setting
        cancelOnError: true, // Keep your desired setting
        listenMode: ListenMode.confirmation // Use type from direct import
        );
    // Update state to reflect listening started (official example pattern)
    if (mounted){
        setState(() {}); // Update UI based on _speechToText.isListening
    }
  }

   // --- Use Direct Type ---
  void _stopListening() async {
    await _speechToText.stop();
     // Update state to reflect listening stopped (official example pattern)
     if (mounted){
        setState(() {});
     }
  }

  // --- Use Direct Type ---
  void _handleSpeechResult(SpeechRecognitionResult result) {
     // Let setState handle UI update based on result
     if (mounted) {
        setState(() {
           // Process the result here, similar to previous logic
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
              String command = result.recognizedWords.toLowerCase().trim();
              debugPrint('Final recognized command: "$command"');

              int targetPageIndex = -1;
              for (int i = 0; i < _features.length; i++) {
                for (String keyword in _features[i].voiceCommandKeywords) {
                  if (command.contains(keyword)) {
                    targetPageIndex = i;
                    debugPrint('Matched command "$command" to feature "${_features[i].title}" (index $i) via keyword "$keyword"');
                    break;
                  }
                }
                if (targetPageIndex != -1) break;
              }

              if (targetPageIndex != -1) {
                _navigateToPage(targetPageIndex);
                // Stop listening after successful command like official example implies?
                // Or let timeout handle it. If needed:
                // _stopListening();
              } else {
                debugPrint('No matching page command found for "$command"');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Command "$command" not recognized.'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
              }
          } else if (result.finalResult) {
              debugPrint('Final result received but empty.');
          }
           // Optionally update a display string like _lastWords in the example
           // _lastWords = result.recognizedWords;
        });
     }
  }


  void _navigateToPage(int pageIndex) {
    if (pageIndex >= 0 && pageIndex < _features.length && mounted) {
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

   void _showPermissionInstructions() {
     if (!mounted) return;
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
     if (_features.isEmpty) {
      return const Scaffold(body: Center(child: Text("No features configured.")));
    }
    final validPageIndex = _currentPage.clamp(0, _features.length - 1);
    final currentFeature = _features[validPageIndex];

    // Determine icon/tooltip based on listening state like official example
    final bool isListening = _speechToText.isListening;
    final IconData micIcon = isListening ? Icons.mic : Icons.mic_off;
    final String tooltip = isListening ? 'Stop listening' : 'Start listening';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraViewWidget(
            cameraController: _cameraController,
            initializeControllerFuture: _initializeControllerFuture,
          ),
          PageView.builder(
            controller: _pageController,
            itemCount: _features.length,
            onPageChanged: (index) {
              if (mounted) {
                setState(() => _currentPage = index);
              }
            },
            itemBuilder: (context, index) {
              return _features[index].pageBuilder(context);
            },
          ),
          FeatureTitleBanner(
            title: currentFeature.title,
            backgroundColor: currentFeature.color,
          ),
          // Use the ActionButton, but pass the correct state/callbacks
          ActionButton(
            onTap: currentFeature.action, // Keep the single tap action
            onLongPress: () {
              // Use start/stop listening like official example's button
              if (!_speechEnabled) {
                 ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text('Speech not available/enabled.')),
                  );
                 return;
              }
              if (_speechToText.isNotListening) {
                _startListening(); // Use the method similar to example
              } else {
                _stopListening(); // Use the method similar to example
              }
            },
            // Reflect actual listening state
            isListening: isListening,
            color: currentFeature.color,
            // Optionally change icon based on listening state if ActionButton supports it
            // Or keep existing icon logic in ActionButton
          ),
        ],
      ),
    );
  }
}