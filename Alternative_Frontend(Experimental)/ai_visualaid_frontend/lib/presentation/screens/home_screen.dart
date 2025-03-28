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
  bool _speechEnabled = false;

  final WebSocketService _webSocketService = WebSocketService();
  late List<FeatureConfig> _features;

  // To potentially display results more persistently if needed later
  String _lastDetectionResult = "";

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
        // Action is correctly set to trigger image capture and sending
        action: () => _handleFeatureAction(config.id),
      );
    }).toList();

    _initializeCameraController();
    _initSpeech();
    _initializeWebSocket(); // Initialize WebSocket connection and listener
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
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
    if (mounted) setState(() {});
  }


  void _initializeCameraController() {
     if (widget.camera != null) {
      _cameraController = CameraController(
        widget.camera!,
        // Consider using a lower preset initially for faster processing/transfer
        // ResolutionPreset.high or ResolutionPreset.medium might be sufficient
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg, // JPEG is usually smaller
      );
      _initializeControllerFuture = _cameraController!.initialize().then((_) {
        if (!mounted) return;
        debugPrint("Camera initialized successfully.");
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
      // Optionally, disable features requiring camera
    }
  }

  void _initializeWebSocket() {
     debugPrint("[HomeScreen] Initializing WebSocket listener...");
     _webSocketService.responseStream.listen(
      (data) { // data is expected to be Map<String, dynamic>
        debugPrint('[HomeScreen] WebSocket Received: $data');

        // *** UPDATED/REFINED LISTENER LOGIC ***
        if (mounted) {
          // Check if the expected 'result' key exists and is a String
          if (data.containsKey('result') && data['result'] is String) {
            final resultText = data['result'] as String;
             setState(() {
               _lastDetectionResult = resultText; // Store result if needed elsewhere
             });
             ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Remove previous messages
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Result: $resultText"),
                duration: const Duration(seconds: 4), // Show result longer
              ),
            );
          } else {
             // Handle cases where 'result' key is missing or not a string
             debugPrint('[HomeScreen] Received unexpected data format from server: $data');
             ScaffoldMessenger.of(context).removeCurrentSnackBar();
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text("Received unexpected data format from server.")),
             );
          }
        }
        // ****************************************

      },
      onError: (error) {
        debugPrint('[HomeScreen] WebSocket Error: $error');
        String errorMessage = "Connection Error";
        if (error is WebSocketChannelException) {
          errorMessage = "Connection Error: ${error.message ?? 'WebSocket issue'}";
        } else if (error is ArgumentError) { // Catch config errors from connect()
           errorMessage = error.message;
        }
         else {
          errorMessage = "Connection Error: ${error.toString()}";
        }

        if (mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage)),
          );
        }
      },
      onDone: () {
        debugPrint('[HomeScreen] WebSocket connection closed by server.');
        if (mounted) {
           ScaffoldMessenger.of(context).removeCurrentSnackBar();
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Disconnected from server. Trying to reconnect...')),
          );
           // Optional: Trigger a reconnect attempt visually or let the service handle it
           // _webSocketService.connect(); // Be careful not to create rapid reconnect loops
        }
      },
      cancelOnError: false // Keep listening even after errors
    );
    // Initiate the connection
    _webSocketService.connect();
  }

  @override
  void dispose() {
    debugPrint("[HomeScreen] Disposing...");
    _pageController.dispose();
    _cameraController?.dispose();
    if (_speechToText.isListening) {
       _speechToText.stop();
    }
    _speechToText.cancel();
    _webSocketService.close(); // Close WebSocket connection and stream
    debugPrint("[HomeScreen] Dispose complete.");
    super.dispose();
  }

   // This function sends the image and the correct feature type to the backend
   void _handleFeatureAction(String featureId) async {
     debugPrint('Action triggered for feature: $featureId');

     // 1. Check Camera
     if (_cameraController == null || !_cameraController!.value.isInitialized) {
       debugPrint('Camera not ready for action.');
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("Camera not ready")),
         );
       }
       return;
     }
     if (_cameraController!.value.isTakingPicture) {
       debugPrint('Camera busy, skipping action.');
       // Optionally show a message that camera is busy
       // ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Camera busy...")));
       return;
     }


     // 2. Check WebSocket Connection
     if (!_webSocketService.isConnected) {
       debugPrint('WebSocket not connected for action.');
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("Not connected to server. Attempting to connect...")),
         );
       }
       _webSocketService.connect(); // Attempt to reconnect
       return;
     }

     // 3. Capture and Send Image
     try {
       if (mounted) {
         ScaffoldMessenger.of(context).removeCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("Capturing..."), duration: Duration(seconds: 1)),
         );
       }

       final XFile imageFile = await _cameraController!.takePicture();
       debugPrint('Picture taken: ${imageFile.path}');

       if (mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("Processing..."), duration: Duration(seconds: 2)),
         );
       }
       // *** Send image with the feature ID as the type ***
       _webSocketService.sendImageForProcessing(imageFile, featureId);
       // ***************************************************

     } on CameraException catch (e) {
       debugPrint('Error taking picture: ${e.code} - ${e.description}');
       if (mounted) {
         ScaffoldMessenger.of(context).removeCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Capture Error: ${e.description ?? e.code}")),
         );
       }
     } catch (e, stackTrace) { // Catch broader errors during send
       debugPrint('Error during feature action (capture/send): $e');
        debugPrintStack(stackTrace: stackTrace);
       if (mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Action Error: $e")),
         );
       }
     }
   }

  // --- Speech Handling Methods (Keep as is) ---
  void _handleSpeechStatus(String status) {
    debugPrint('Speech recognition status: $status');
    if (!mounted) return;
    final bool isCurrentlyListening = status == SpeechToText.listeningStatus;
    if (_isListening != isCurrentlyListening) {
       setState(() => _isListening = isCurrentlyListening);
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    debugPrint('Speech recognition error: ${error.errorMsg} (Permanent: ${error.permanent})');
    if (!mounted) return;
    if (_isListening) setState(() => _isListening = false);

    String errorMessage = 'Speech error: ${error.errorMsg}';
    SnackBarAction? action;
    if (error.errorMsg.contains('permission') || error.permanent) {
      errorMessage = 'Microphone permission error.';
      action = SnackBarAction(label: 'Help', onPressed: _showPermissionInstructions);
    }
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage), action: action));
  }

  void _startListening() async {
     if (!_speechEnabled) {
        debugPrint('Attempted to listen but speech is not enabled/initialized.');
        _initSpeech();
        return;
     }
     bool hasPermission = await _speechToText.hasPermission;
     if (!hasPermission && mounted) {
       debugPrint('Microphone permission denied before listening attempt.');
       _showPermissionInstructions();
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission needed.')));
       return;
     }
     if(!mounted) return; // Check mounted state again after async gap

    await _speechToText.listen(
        onResult: _handleSpeechResult,
        listenFor: const Duration(seconds: 7),
        pauseFor: const Duration(seconds: 4),
        partialResults: false,
        cancelOnError: true,
        listenMode: ListenMode.confirmation
    );
    if (mounted) setState(() {});
  }

  void _stopListening() async {
    await _speechToText.stop();
     if (mounted) setState(() {});
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
     if (mounted) {
        setState(() {
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
              } else {
                debugPrint('No matching page command found for "$command"');
                ScaffoldMessenger.of(context).removeCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Command "$command" not recognized.')));
              }
          }
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
     // (Keep existing permission instructions dialog)
     // ...
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
    // Ensure _currentPage is valid before accessing _features
    final validPageIndex = _currentPage.clamp(0, _features.length - 1);
    final currentFeature = _features[validPageIndex];

    final bool isCurrentlyListening = _speechToText.isListening;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera View in the background
          CameraViewWidget(
            cameraController: _cameraController,
            initializeControllerFuture: _initializeControllerFuture,
          ),

          // PageView for different feature UIs (currently placeholders)
          PageView.builder(
            controller: _pageController,
            itemCount: _features.length,
            onPageChanged: (index) {
              if (mounted) {
                setState(() {
                  _currentPage = index;
                  _lastDetectionResult = ""; // Clear old results on page change
                });
                debugPrint("Switched to page: ${_features[index].title}");
              }
            },
            itemBuilder: (context, index) {
              // Here you could potentially pass the _lastDetectionResult
              // to the specific feature page if it needs to display it.
              // For now, PageContent is just a placeholder.
              return _features[index].pageBuilder(context);
            },
          ),

          // Title banner at the top
          FeatureTitleBanner(
            title: currentFeature.title,
            backgroundColor: currentFeature.color,
          ),

          // Action button at the bottom
          ActionButton(
            // Single tap triggers image capture and sending for the current feature
            onTap: currentFeature.action,
            // Long press triggers voice recognition
            onLongPress: () {
              if (!_speechEnabled) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speech not available/enabled.')));
                 return;
              }
              if (_speechToText.isNotListening) {
                _startListening();
              } else {
                _stopListening();
              }
            },
            isListening: isCurrentlyListening, // Reflects voice listening state
            color: currentFeature.color,
          ),

          // Optional: Display last result text somewhere on screen?
          // Positioned(
          //   bottom: 200,
          //   left: 20,
          //   right: 20,
          //   child: Container(
          //     padding: EdgeInsets.all(8),
          //     color: Colors.black.withOpacity(0.5),
          //     child: Text(
          //       _lastDetectionResult,
          //       style: TextStyle(color: Colors.white),
          //       textAlign: TextAlign.center,
          //     ),
          //   ),
          // ),

        ],
      ),
    );
  }
}