// lib/presentation/screens/home_screen.dart
import 'dart:async'; // Import Timer
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:web_socket_channel/web_socket_channel.dart'; // Keep for exception type
import 'package:flutter/foundation.dart';

// Core & Services
import '../../core/models/feature_config.dart';
import '../../core/services/websocket_service.dart';

// Features (Need specific page types and the registry for feature IDs)
import '../../features/feature_registry.dart'; // To access feature IDs
import '../../features/object_detection/presentation/pages/object_detection_page.dart';
import '../../features/scene_detection/presentation/pages/scene_detection_page.dart';
import '../../features/text_detection/presentation/pages/text_detection_page.dart';

// Widgets
import '../widgets/camera_view_widget.dart';
import '../widgets/feature_title_banner.dart';
import '../widgets/action_button.dart';

// *** NEW: Import Settings Screen ***
import 'settings_screen.dart';


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

  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;

  final WebSocketService _webSocketService = WebSocketService();
  late List<FeatureConfig> _features;

  // *** MODIFIED: Separate result variables ***
  String _lastObjectResult = "";
  String _lastSceneTextResult = ""; // For Scene and Text results
  Timer? _objectResultClearTimer; // Timer to clear object result

  // *** Timer for periodic OBJECT detection ***
  Timer? _detectionTimer;
  final Duration _detectionInterval = const Duration(seconds: 1);
  final Duration _objectResultPersistence = const Duration(seconds: 2);

  // Flag to prevent concurrent detections (for both timer and manual)
  bool _isProcessingImage = false;
  // Store the type of the last request sent
  String? _lastRequestedFeatureId;


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
        action: null, // Action is handled conditionally in build()
      );
    }).toList();


    _initializeCameraController();
    _initSpeech();
    _initializeWebSocket();
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
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _initializeControllerFuture = _cameraController!.initialize().then((_) {
        if (!mounted) return;
        debugPrint("Camera initialized successfully.");
        setState(() {});
        // Start timer ONLY if connected AND on object detection page initially
        _startObjectDetectionTimerIfNeeded();
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
     debugPrint("[HomeScreen] Initializing WebSocket listener...");
     _webSocketService.responseStream.listen(
      (data) {
        debugPrint('[HomeScreen] WebSocket Received: $data');

        if (mounted && data.containsKey('result') && data['result'] is String) {
           final resultText = data['result'] as String;
           final String? receivedForFeatureId = _lastRequestedFeatureId; // Capture the ID when response arrives

           // Clear the request ID now that we have a response
           _lastRequestedFeatureId = null;

           setState(() {
               if (receivedForFeatureId == objectDetectionFeature.id) {
                   _lastObjectResult = resultText;
                   // Cancel previous clear timer (if any) and start a new one
                   _objectResultClearTimer?.cancel();
                   _objectResultClearTimer = Timer(_objectResultPersistence, () {
                       if (mounted) {
                           setState(() {
                               _lastObjectResult = ""; // Clear after persistence duration
                           });
                       }
                   });
               } else if (receivedForFeatureId == sceneDetectionFeature.id || receivedForFeatureId == textDetectionFeature.id) {
                   // Scene/Text result persists until next detection for that type
                   _lastSceneTextResult = resultText;
               } else {
                   debugPrint("[HomeScreen] Received result for unknown or unset feature ID: $receivedForFeatureId");
               }
           });
        } else if (mounted && data.containsKey('event') && data['event'] == 'connect') {
             // WebSocket just connected
             _startObjectDetectionTimerIfNeeded(); // Try starting timer if on object page
             ScaffoldMessenger.of(context).removeCurrentSnackBar();
             ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Connected"), duration: Duration(seconds: 2)),
             );
        } else if (mounted) {
           debugPrint('[HomeScreen] Received non-result or unexpected data format: $data');
        }

      },
      onError: (error) {
        debugPrint('[HomeScreen] WebSocket Error: $error');
        _stopObjectDetectionTimer(); // Stop timer on error
        _objectResultClearTimer?.cancel(); // Cancel clear timer
         if (mounted) {
            setState(() {
                // Clear results or show error message in the display area
                _lastObjectResult = "";
                _lastSceneTextResult = "Connection Error";
            });
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Connection Error: ${error.toString()}")),
            );
         }
      },
      onDone: () {
        debugPrint('[HomeScreen] WebSocket connection closed by server.');
        _stopObjectDetectionTimer(); // Stop timer on disconnect
        _objectResultClearTimer?.cancel(); // Cancel clear timer
        if (mounted) {
           setState(() {
             _lastObjectResult = "";
             _lastSceneTextResult = "Disconnected";
           });
           ScaffoldMessenger.of(context).removeCurrentSnackBar();
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Disconnected. Trying to reconnect...')),
          );
        }
      },
      cancelOnError: false
    );
    _webSocketService.connect();
  }

  // *** MODIFIED: Start timer only if on Object Detection page ***
  void _startObjectDetectionTimerIfNeeded() {
    // Check if current page is Object Detection
    bool isObjectDetectionPage = _features.isNotEmpty &&
                                 _currentPage.clamp(0, _features.length - 1) < _features.length &&
                                 _features[_currentPage.clamp(0, _features.length - 1)].id == objectDetectionFeature.id;

    if (isObjectDetectionPage &&
        _detectionTimer == null &&
        (_cameraController?.value.isInitialized ?? false) &&
        _webSocketService.isConnected)
    {
        debugPrint("[HomeScreen] Starting OBJECT detection timer...");
        _detectionTimer = Timer.periodic(_detectionInterval, (_) {
            _performPeriodicDetection(); // This now only runs for object detection
        });
    } else {
        debugPrint("[HomeScreen] Conditions not met to start OBJECT timer (isObjPage: $isObjectDetectionPage, timer: ${_detectionTimer != null}, camera: ${_cameraController?.value.isInitialized}, socket: ${_webSocketService.isConnected})");
    }
  }

  // *** RENAMED: Stop the OBJECT detection timer ***
  void _stopObjectDetectionTimer() {
    if (_detectionTimer?.isActive ?? false) {
        debugPrint("[HomeScreen] Stopping OBJECT detection timer...");
        _detectionTimer!.cancel();
        _detectionTimer = null;
         _isProcessingImage = false; // Reset flag
    }
  }

   // *** NEW: Function for manual detection (Scene/Text) ***
   void _performManualDetection(String featureId) async {
     debugPrint('Manual detection triggered for feature: $featureId');

     // 1. Check Camera and Processing Flag
     if (_cameraController == null || !_cameraController!.value.isInitialized) {
       debugPrint('Manual detection: Camera not ready.');
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Camera not ready")));
       return;
     }
     if (_cameraController!.value.isTakingPicture || _isProcessingImage) {
       debugPrint('Manual detection: Camera busy or already processing, skipping.');
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Processing... Please wait."), duration: Duration(milliseconds: 500)));
       return;
     }

     // 2. Check WebSocket Connection
     if (!_webSocketService.isConnected) {
       debugPrint('Manual detection: WebSocket not connected.');
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Not connected. Retrying...")));
       _webSocketService.connect(); // Attempt reconnect
       return;
     }

     // 3. Capture and Send Image
     try {
       _isProcessingImage = true; // Set flag
        // Optionally show brief "Capturing..." message for manual clicks
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Capturing..."), duration: Duration(seconds: 1)));

       // Store the type of request we are making NOW
       _lastRequestedFeatureId = featureId;

       final XFile imageFile = await _cameraController!.takePicture();
       debugPrint('Manual detection: Picture taken: ${imageFile.path}');

       // Optionally show "Processing..."
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Processing..."), duration: Duration(seconds: 2)));

       _webSocketService.sendImageForProcessing(imageFile, featureId);

     } on CameraException catch (e) {
       debugPrint('Manual detection: Error taking picture: ${e.code} - ${e.description}');
       _lastRequestedFeatureId = null; // Clear request ID on error
       if (mounted) {
          setState(() { _lastSceneTextResult = "Capture Error"; }); // Show error in display
         ScaffoldMessenger.of(context).removeCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Capture Error: ${e.description ?? e.code}")),
         );
       }
     } catch (e, stackTrace) {
       debugPrint('Manual detection: Error during action (capture/send): $e');
       debugPrintStack(stackTrace: stackTrace);
       _lastRequestedFeatureId = null; // Clear request ID on error
       if (mounted) {
         setState(() { _lastSceneTextResult = "Action Error"; }); // Show error in display
         ScaffoldMessenger.of(context).removeCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Action Error: $e")),
         );
       }
     } finally {
        _isProcessingImage = false;
     }
   }


  @override
  void dispose() {
    debugPrint("[HomeScreen] Disposing...");
    _stopObjectDetectionTimer(); // Stop the timer
    _objectResultClearTimer?.cancel(); // Cancel the clear timer
    _pageController.dispose();
    _cameraController?.dispose();
    if (_speechToText.isListening) {
       _speechToText.stop();
    }
    _speechToText.cancel();
    _webSocketService.close();
    debugPrint("[HomeScreen] Dispose complete.");
    super.dispose();
  }

   // *** Called ONLY by the timer for Object Detection ***
   void _performPeriodicDetection() async {
     // Feature ID is implicitly objectDetectionFeature.id here
     final currentFeatureId = objectDetectionFeature.id;
     debugPrint('Timer Tick: Requesting detection for feature: $currentFeatureId');

     // Checks are similar to manual, but context is timer
     if (_cameraController == null || !_cameraController!.value.isInitialized) {
       debugPrint('Timer Tick: Camera not ready.');
       _stopObjectDetectionTimer(); // Stop timer if camera issue
       return;
     }
     if (_cameraController!.value.isTakingPicture || _isProcessingImage) {
       debugPrint('Timer Tick: Camera busy or already processing, skipping.');
       return;
     }
     if (!_webSocketService.isConnected) {
       debugPrint('Timer Tick: WebSocket not connected.');
       // Don't stop timer, let service reconnect
       return;
     }

     try {
       _isProcessingImage = true;

       // Store the type of request we are making NOW
       _lastRequestedFeatureId = currentFeatureId;

       final XFile imageFile = await _cameraController!.takePicture();
       // debugPrint('Timer Tick: Picture taken: ${imageFile.path}'); // Can be verbose

       _webSocketService.sendImageForProcessing(imageFile, currentFeatureId);

     } on CameraException catch (e) {
       debugPrint('Timer Tick: Error taking picture: ${e.code} - ${e.description}');
       _lastRequestedFeatureId = null; // Clear request ID on error
       if (mounted) {
          setState(() { _lastObjectResult = "Capture Error"; }); // Show error
           _objectResultClearTimer?.cancel(); // Stop any pending clear
       }
     } catch (e, stackTrace) {
       debugPrint('Timer Tick: Error during periodic detection (capture/send): $e');
       debugPrintStack(stackTrace: stackTrace);
       _lastRequestedFeatureId = null; // Clear request ID on error
       if (mounted) {
          setState(() { _lastObjectResult = "Processing Error"; }); // Show error
           _objectResultClearTimer?.cancel(); // Stop any pending clear
       }
     } finally {
        _isProcessingImage = false; // Reset flag
     }
   }

  // --- Speech Handling Methods ---
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

   // *** MODIFIED: Handle speech result to include "settings" command ***
   void _handleSpeechResult(SpeechRecognitionResult result) {
     if (mounted) {
         setState(() {
           if (result.finalResult && result.recognizedWords.isNotEmpty) {
               String command = result.recognizedWords.toLowerCase().trim();
               debugPrint('Final recognized command: "$command"');

               // *** NEW: Check for "settings" command first ***
               if (command == 'settings') {
                 debugPrint('Matched command "settings"');
                 _navigateToSettingsPage(); // Navigate to settings
                 return; // Exit early
               }

               // Existing feature matching logic
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

   // *** NEW: Navigation function for Settings ***
   void _navigateToSettingsPage() {
     if (mounted) {
       debugPrint("Navigating to Settings page...");
       // Stop listening if active before navigating
       if (_speechToText.isListening) {
         _stopListening();
       }
       Navigator.push(
         context,
         MaterialPageRoute(builder: (context) => const SettingsScreen()),
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
    final bool isObjectDetectionPage = currentFeature.id == objectDetectionFeature.id;

    final bool isCurrentlyListening = _speechToText.isListening;

    // Determine which result to display
    final String resultToShow = isObjectDetectionPage ? _lastObjectResult : _lastSceneTextResult;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera View
          CameraViewWidget(
            cameraController: _cameraController,
            initializeControllerFuture: _initializeControllerFuture,
          ),

          // PageView
          PageView.builder(
            controller: _pageController,
            itemCount: _features.length,
            onPageChanged: (index) {
              if (mounted) {
                 final previousFeatureId = _features[_currentPage.clamp(0, _features.length - 1)].id;
                 final newFeatureId = _features[index.clamp(0, _features.length - 1)].id;

                setState(() {
                  _currentPage = index;
                   _isProcessingImage = false; // Reset processing flag on swipe

                   // *** Clear only object result on page change ***
                   _lastObjectResult = "";

                });

                // Cancel any pending object clear timer
                _objectResultClearTimer?.cancel();

                // Stop timer if we are *leaving* object detection
                 if (previousFeatureId == objectDetectionFeature.id && newFeatureId != objectDetectionFeature.id) {
                    _stopObjectDetectionTimer();
                 }
                 // Start timer if we are *entering* object detection
                 if (newFeatureId == objectDetectionFeature.id) {
                    _startObjectDetectionTimerIfNeeded();
                 }

                debugPrint("Switched to page: ${_features[index].title}");
              }
            },
            itemBuilder: (context, index) {
               // Pass the *correct* result based on the page type
               final feature = _features[index];
               final String displayData = (feature.id == objectDetectionFeature.id)
                                          ? _lastObjectResult
                                          // *** MODIFIED: Pass scene/text result consistently ***
                                          : _lastSceneTextResult;

               if (feature.id == objectDetectionFeature.id) {
                  return ObjectDetectionPage(detectionResult: displayData);
               } else if (feature.id == sceneDetectionFeature.id) {
                  return SceneDetectionPage(detectionResult: displayData);
               } else if (feature.id == textDetectionFeature.id) {
                  return TextDetectionPage(detectionResult: displayData);
               } else {
                  return Center(child: Text('Unknown Page Type: ${feature.id}', style: TextStyle(color: Colors.white)));
               }
            },
          ),

          // Title banner (Positioned lower via its internal padding now)
          FeatureTitleBanner(
            title: currentFeature.title,
            backgroundColor: currentFeature.color,
          ),

          // *** NEW: Settings Icon Button ***
          Align(
            alignment: Alignment.topRight,
            child: SafeArea( // Ensures icon is not under status bar/notch
              child: Padding(
                // Adjust padding to position icon relative to safe area top-right
                padding: const EdgeInsets.only(top: 10.0, right: 15.0),
                child: IconButton(
                  icon: const Icon(
                    Icons.settings,
                    color: Colors.white,
                    size: 32.0, // Slightly larger icon
                    shadows: [ // Add shadow for better visibility
                       Shadow(
                         blurRadius: 6.0,
                         color: Colors.black54,
                         offset: Offset(1.0, 1.0),
                       ),
                    ],
                  ),
                  onPressed: _navigateToSettingsPage, // Navigate on tap
                  tooltip: 'Settings', // For accessibility
                ),
              ),
            ),
          ),

          // Action button (remains at the bottom)
          ActionButton(
            onTap: isObjectDetectionPage
                   ? null // No action on tap for object detection
                   : () => _performManualDetection(currentFeature.id), // Trigger manual for scene/text
            onLongPress: () { // Keep long press for voice commands
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
            isListening: isCurrentlyListening,
            color: currentFeature.color,
          ),
        ],
      ),
    );
  }
}