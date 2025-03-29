// lib/presentation/screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:flutter/foundation.dart'; // for kDebugMode, debugPrint

// Core & Services
import '../../core/models/feature_config.dart';
import '../../core/services/websocket_service.dart';
import '../../core/services/settings_service.dart';

// Features
import '../../features/feature_registry.dart';
import '../../features/object_detection/presentation/pages/object_detection_page.dart';
import '../../features/scene_detection/presentation/pages/scene_detection_page.dart';
import '../../features/text_detection/presentation/pages/text_detection_page.dart';

// Widgets
import '../widgets/camera_view_widget.dart';
import '../widgets/feature_title_banner.dart';
import '../widgets/action_button.dart';

// Screens
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final CameraDescription? camera;

  const HomeScreen({Key? key, required this.camera}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // Camera
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;

  // Page View
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Speech
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;

  // WebSocket & Features
  final WebSocketService _webSocketService = WebSocketService();
  late List<FeatureConfig> _features;
  final SettingsService _settingsService = SettingsService();
  String _selectedOcrLanguage = SettingsService.getValidatedDefaultLanguage();

  // Results & State
  String _lastObjectResult = "";
  String _lastSceneTextResult = "";
  Timer? _objectResultClearTimer;

  // Detection Control
  Timer? _detectionTimer;
  final Duration _detectionInterval = const Duration(seconds: 1);
  final Duration _objectResultPersistence = const Duration(seconds: 2);
  bool _isProcessingImage = false;
  String? _lastRequestedFeatureId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFeatures();
    _initializeServices();
  }

  void _initializeFeatures() {
     _features = availableFeatures.map((config) {
      return FeatureConfig(
        id: config.id,
        title: config.title,
        color: config.color,
        voiceCommandKeywords: config.voiceCommandKeywords,
        pageBuilder: config.pageBuilder,
        action: null,
      );
    }).toList();
  }

  Future<void> _initializeServices() async {
    await _loadSettings();
    _initializeCameraController();
    _initSpeech();
    _initializeWebSocket();
  }

  Future<void> _loadSettings() async {
    _selectedOcrLanguage = await _settingsService.getOcrLanguage();
    if (mounted) {
      setState(() {});
    }
     debugPrint("[HomeScreen] OCR language setting loaded: $_selectedOcrLanguage");
  }

  void _initSpeech() async {
     try {
       // Use initialize with status/error listeners
       _speechEnabled = await _speechToText.initialize(
           onStatus: _handleSpeechStatus,
           onError: _handleSpeechError,
           debugLogging: kDebugMode);
       if (!_speechEnabled) {
         debugPrint('Speech recognition not available during init.');
         _showStatusMessage('Speech unavailable', durationSeconds: 3);
       } else {
          debugPrint('Speech recognition initialized successfully.');
       }
     } catch (e) {
        debugPrint('Error initializing speech: $e');
         _showStatusMessage('Speech init failed', durationSeconds: 3);
     }
    if (mounted) setState(() {});
  }

  void _initializeCameraController() {
     if (widget.camera == null) {
       debugPrint("No camera provided to HomeScreen");
       _showStatusMessage("No camera available", isError: true);
       return;
     }
     _cameraController?.dispose();
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
        _startObjectDetectionTimerIfNeeded();
      }).catchError((error) {
        debugPrint("Camera initialization error: $error");
        if (mounted) {
           _showStatusMessage("Camera init failed: ${error is CameraException ? error.description : error}", isError: true);
           _cameraController = null;
           _initializeControllerFuture = null;
           setState(() {});
        }
      });
       if (mounted) setState(() {});
  }

  void _initializeWebSocket() {
     debugPrint("[HomeScreen] Initializing WebSocket listener...");
     _webSocketService.responseStream.listen(
      (data) {
        if (!mounted) return;
        debugPrint('[HomeScreen] WebSocket Received: $data');
        if (data.containsKey('event') && data['event'] == 'connect') {
             _showStatusMessage("Connected", durationSeconds: 2);
             _startObjectDetectionTimerIfNeeded();
             return;
        }
        if (data.containsKey('result')) {
           final resultText = data['result'] as String? ?? "No result";
           final String? receivedForFeatureId = _lastRequestedFeatureId;
           _lastRequestedFeatureId = null;
           setState(() {
               if (receivedForFeatureId == objectDetectionFeature.id) {
                   _lastObjectResult = resultText;
                   _objectResultClearTimer?.cancel();
                   _objectResultClearTimer = Timer(_objectResultPersistence, () {
                       if (mounted) setState(() => _lastObjectResult = "");
                   });
               } else if (receivedForFeatureId == sceneDetectionFeature.id || receivedForFeatureId == textDetectionFeature.id) {
                   _lastSceneTextResult = resultText;
               } else {
                   debugPrint("[HomeScreen] Received result for unknown/unset feature ID: $receivedForFeatureId. Result: $resultText");
               }
           });
        } else { debugPrint('[HomeScreen] Received non-result/event data: $data'); }
      },
      onError: (error) {
        if (!mounted) return;
        debugPrint('[HomeScreen] WebSocket Error: $error');
        _stopObjectDetectionTimer();
        _objectResultClearTimer?.cancel();
        setState(() { _lastObjectResult = ""; _lastSceneTextResult = "Connection Error"; });
        _showStatusMessage("Connection Error: ${error.toString()}", isError: true);
      },
      onDone: () {
        if (!mounted) return;
        debugPrint('[HomeScreen] WebSocket connection closed.');
        _stopObjectDetectionTimer();
        _objectResultClearTimer?.cancel();
        if (mounted) {
           setState(() { _lastObjectResult = ""; _lastSceneTextResult = "Disconnected"; });
           _showStatusMessage('Disconnected. Trying to reconnect...', isError: true, durationSeconds: 5);
        }
      },
      cancelOnError: false
    );
    _webSocketService.connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) { return; }
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      debugPrint("[HomeScreen] App inactive/paused - Disposing camera & stopping timer");
      _stopObjectDetectionTimer();
      controller.dispose();
       if (mounted) { setState(() { _cameraController = null; }); }
    } else if (state == AppLifecycleState.resumed) {
      debugPrint("[HomeScreen] App resumed - Reinitializing camera");
      if (_cameraController == null) { _initializeCameraController(); }
       if (!_webSocketService.isConnected) {
           debugPrint("[HomeScreen] App resumed - Attempting WebSocket reconnect");
           _webSocketService.connect();
       }
    }
  }

  @override
  void dispose() {
    debugPrint("[HomeScreen] Disposing...");
    WidgetsBinding.instance.removeObserver(this);
    _stopObjectDetectionTimer();
    _objectResultClearTimer?.cancel();
    _pageController.dispose();
    _cameraController?.dispose();
    if (_speechToText.isListening) { _speechToText.stop(); }
    _speechToText.cancel();
    _webSocketService.close();
    debugPrint("[HomeScreen] Dispose complete.");
    super.dispose();
  }

  void _startObjectDetectionTimerIfNeeded() {
    if (_features.isEmpty) return;
    bool isObjectDetectionPage = _features[_currentPage.clamp(0, _features.length - 1)].id == objectDetectionFeature.id;
    if (isObjectDetectionPage &&
        _detectionTimer == null &&
        (_cameraController?.value.isInitialized ?? false) &&
        _webSocketService.isConnected) {
        debugPrint("[HomeScreen] Starting OBJECT detection timer...");
        _detectionTimer = Timer.periodic(_detectionInterval, (_) { _performPeriodicDetection(); });
    } else {
        // debugPrint("[HomeScreen] Conditions not met to start OBJECT timer..."); // Less verbose
    }
  }

  void _stopObjectDetectionTimer() {
    if (_detectionTimer?.isActive ?? false) {
        debugPrint("[HomeScreen] Stopping OBJECT detection timer...");
        _detectionTimer!.cancel();
        _detectionTimer = null;
         _isProcessingImage = false;
    }
  }

   void _performPeriodicDetection() async {
     final currentFeatureId = objectDetectionFeature.id;
     if (!_cameraControllerCheck() || _isProcessingImage || !_webSocketService.isConnected) return;
     try {
       _isProcessingImage = true;
       _lastRequestedFeatureId = currentFeatureId;
       final XFile imageFile = await _cameraController!.takePicture();
       _webSocketService.sendImageForProcessing(imageFile, currentFeatureId);
     } catch (e, stackTrace) {
       _handleCaptureError(e, stackTrace, currentFeatureId);
       _lastRequestedFeatureId = null;
     } finally {
        Future.delayed(const Duration(milliseconds: 100), () { if (mounted) _isProcessingImage = false; });
     }
   }

   void _performManualDetection(String featureId) async {
     debugPrint('Manual detection triggered for feature: $featureId');
     if (!_cameraControllerCheck()) return;
      if (_isProcessingImage) { _showStatusMessage("Processing...", durationSeconds: 1); return; }
     if (!_webSocketService.isConnected) { _showStatusMessage("Not connected", isError: true); _webSocketService.connect(); return; }
     try {
       _isProcessingImage = true;
       _lastRequestedFeatureId = featureId;
       _showStatusMessage("Capturing...", durationSeconds: 1);
       final XFile imageFile = await _cameraController!.takePicture();
       debugPrint('Manual detection: Picture taken: ${imageFile.path}');
       _showStatusMessage("Processing...", durationSeconds: 2);
       _webSocketService.sendImageForProcessing( imageFile, featureId,
           languageCode: (featureId == textDetectionFeature.id) ? _selectedOcrLanguage : null, );
     } catch (e, stackTrace) {
       _handleCaptureError(e, stackTrace, featureId);
        _lastRequestedFeatureId = null;
     } finally { if (mounted) _isProcessingImage = false; }
   }

   bool _cameraControllerCheck() {
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
       debugPrint('Camera not ready.');
       _showStatusMessage("Camera not ready", isError: true);
       if (_cameraController == null && widget.camera != null) { _initializeCameraController(); }
       return false;
     }
      if (_cameraController!.value.isTakingPicture) {
          debugPrint('Camera busy taking picture.');
          _showStatusMessage("Camera busy...", durationSeconds: 1); return false;
      }
      return true;
   }

  void _handleCaptureError(Object e, StackTrace stackTrace, String featureId) {
     debugPrint('Capture/Send Error for $featureId: $e');
     debugPrintStack(stackTrace: stackTrace);
     String errorMsg = e is CameraException ? "Capture Error: ${e.description ?? e.code}" : "Processing Error";
     if (mounted) {
       setState(() {
         if (featureId == objectDetectionFeature.id) { _lastObjectResult = "Error"; _objectResultClearTimer?.cancel(); }
         else { _lastSceneTextResult = "Error"; }
       });
       _showStatusMessage(errorMsg, isError: true, durationSeconds: 4);
     }
   }

  void _showStatusMessage(String message, {bool isError = false, int durationSeconds = 3}) {
    if (!mounted) return;
    debugPrint("[Status] $message ${isError ? '(Error)' : ''}");
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar( SnackBar(
        content: Text(message), backgroundColor: isError ? Colors.redAccent : Colors.grey[800],
        duration: Duration(seconds: durationSeconds), behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(10), shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(10.0), ), ), );
  }

   void _handleSpeechStatus(String status) {
     debugPrint('Speech recognition status: $status');
     if (!mounted) return;
     final bool isCurrentlyListening = status == SpeechToText.listeningStatus;
     if (_isListening != isCurrentlyListening) { setState(() => _isListening = isCurrentlyListening); }
   }

   void _handleSpeechError(SpeechRecognitionError error) {
     debugPrint('Speech recognition error: ${error.errorMsg} (Permanent: ${error.permanent})');
     if (!mounted) return;
     if (_isListening) setState(() => _isListening = false);
     String errorMessage = 'Speech error: ${error.errorMsg}';
     bool isPermissionError = error.errorMsg.contains('permission') || error.errorMsg.contains('denied');
     if (isPermissionError || error.permanent) {
       errorMessage = 'Microphone permission needed.'; _showPermissionInstructions();
     } else if (error.errorMsg.contains('No speech')) { errorMessage = 'No speech detected.'; }
      _showStatusMessage(errorMessage, isError: true, durationSeconds: 4);
   }

   // *** REVERTED to use older parameters as per working example ***
   void _startListening() async {
     if (!_speechEnabled) {
         _showStatusMessage('Speech not available', isError: true); _initSpeech(); return;
     }
     bool hasPermission = await _speechToText.hasPermission;
     if (!hasPermission && mounted) {
        _showPermissionInstructions(); _showStatusMessage('Microphone permission needed', isError: true); return;
     }
     if (!mounted) return;

     if (_speechToText.isListening) {
         debugPrint("Stopping prior listening session before starting new one.");
         await _stopListening(); // Ensure prior session is stopped. Correctly awaits Future<void>.
         await Future.delayed(const Duration(milliseconds: 100)); // Brief pause is okay.
     }

     try {
        // Using the parameters directly as in the older working code
        await _speechToText.listen(
           onResult: _handleSpeechResult,
           listenFor: const Duration(seconds: 7),
           pauseFor: const Duration(seconds: 3),
           partialResults: false, // Deprecated, but was working
           cancelOnError: true, // Deprecated, but was working
           listenMode: ListenMode.confirmation, // Deprecated, but was working
           // localeId: 'en_US', // Optional: specify locale
        );
         if (mounted) setState(() {}); // Reflect listening state in UI
     } catch (e) {
        debugPrint("Error starting speech listener: $e");
        _showStatusMessage("Could not start listening", isError: true);
     }
   }

   // This function correctly returns Future<void>
   Future<void> _stopListening() async {
      if (_speechToText.isListening) {
         await _speechToText.stop(); // speech_to_text.stop() returns Future<void>
         if (mounted) setState(() {});
      }
      // No explicit return needed, Future<void> is inferred
   }

   void _handleSpeechResult(SpeechRecognitionResult result) {
     if (mounted && result.finalResult && result.recognizedWords.isNotEmpty) {
         String command = result.recognizedWords.toLowerCase().trim();
         debugPrint('Final recognized command: "$command"');
         if (command == 'settings' || command == 'setting') { _navigateToSettingsPage(); return; }
         int targetPageIndex = -1;
         for (int i = 0; i < _features.length; i++) {
           for (String keyword in _features[i].voiceCommandKeywords) {
             if (command.contains(keyword)) { targetPageIndex = i; debugPrint('Matched command "$command" to feature "${_features[i].title}" (index $i)'); break; } }
           if (targetPageIndex != -1) break;
         }
         if (targetPageIndex != -1) { _navigateToPage(targetPageIndex); }
         else { _showStatusMessage('Command "$command" not recognized.', durationSeconds: 3); }
     }
   }

   void _navigateToPage(int pageIndex) {
      if (_features.isEmpty) return;
      final targetIndex = pageIndex.clamp(0, _features.length - 1);
      if (targetIndex != _currentPage && mounted) {
         _pageController.animateToPage( targetIndex, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut, );
      }
   }

   // This function signature is correct (async => Future<void>)
   void _navigateToSettingsPage() async {
     if (mounted) {
       debugPrint("Navigating to Settings page...");
       if (_speechToText.isListening) {
         await _stopListening(); // Awaiting Future<void> is correct
       }
       _stopObjectDetectionTimer(); // This is void, no await needed

       // This await is on Future<T?> which is correct
       await Navigator.push( context, MaterialPageRoute(builder: (context) => const SettingsScreen()), );

       // --- After returning ---
       if (!mounted) return; // Correct mounted check after async gap
       debugPrint("Returned from Settings page.");

       // This await is on Future<void> which is correct
       await _loadSettings();

       // This is void, no await needed
       _startObjectDetectionTimerIfNeeded();
     }
   }

   void _showPermissionInstructions() {
    if (!mounted) return;
     showDialog( context: context, builder: (BuildContext dialogContext) {
         return AlertDialog( title: const Text('Microphone Permission'),
           content: const Text( 'Voice control requires microphone access.\n\nPlease enable the Microphone permission for this app in your device\'s Settings.', ),
           actions: <Widget>[ TextButton( child: const Text('OK'), onPressed: () => Navigator.of(dialogContext).pop(), ), ], ); }, );
   }

  @override
  Widget build(BuildContext context) {
     if (_features.isEmpty) { return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text("No features configured.", style: TextStyle(color: Colors.white)))); }
     final validPageIndex = _currentPage.clamp(0, _features.length - 1);
     final currentFeature = _features[validPageIndex];
     final bool isObjectDetectionPage = currentFeature.id == objectDetectionFeature.id;

     return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraViewWidget( cameraController: _cameraController, initializeControllerFuture: _initializeControllerFuture, ),
          PageView.builder(
            controller: _pageController,
            itemCount: _features.length,
            onPageChanged: (index) {
              if (mounted) {
                 final previousPageIndex = _currentPage.clamp(0, _features.length - 1);
                 final newPageIndex = index.clamp(0, _features.length - 1);
                 if (previousPageIndex >= _features.length || newPageIndex >= _features.length) { debugPrint("Error: Page index out of bounds during page change."); return; }
                 final previousFeatureId = _features[previousPageIndex].id;
                 final newFeatureId = _features[newPageIndex].id;
                 debugPrint("Page changed from ${_features[previousPageIndex].title} to ${_features[newPageIndex].title}");
                 setState(() { _currentPage = newPageIndex; _isProcessingImage = false; _lastRequestedFeatureId = null; _objectResultClearTimer?.cancel(); _lastObjectResult = ""; });
                 if (previousFeatureId == objectDetectionFeature.id && newFeatureId != objectDetectionFeature.id) { _stopObjectDetectionTimer(); }
                 if (newFeatureId == objectDetectionFeature.id) { _startObjectDetectionTimerIfNeeded(); }
              }
            },
            itemBuilder: (context, index) {
               if (index >= _features.length) { return const Center(child: Text("Error: Invalid page index", style: TextStyle(color: Colors.red))); }
               final feature = _features[index];
               final String displayData = (feature.id == objectDetectionFeature.id) ? _lastObjectResult : _lastSceneTextResult;
               if (feature.id == objectDetectionFeature.id) { return ObjectDetectionPage(detectionResult: displayData); }
               else if (feature.id == sceneDetectionFeature.id) { return SceneDetectionPage(detectionResult: displayData); }
               else if (feature.id == textDetectionFeature.id) { return TextDetectionPage(detectionResult: displayData); }
               else { return Center(child: Text('Unknown Page: ${feature.id}', style: const TextStyle(color: Colors.white))); }
            },
          ),
          FeatureTitleBanner( title: currentFeature.title, backgroundColor: currentFeature.color, ),
          Align( alignment: Alignment.topRight,
            child: SafeArea( child: Padding( padding: const EdgeInsets.only(top: 10.0, right: 15.0),
                child: IconButton( icon: const Icon(Icons.settings, color: Colors.white, size: 32.0, shadows: [Shadow(blurRadius: 6.0, color: Colors.black54, offset: Offset(1.0, 1.0))]),
                  onPressed: _navigateToSettingsPage, tooltip: 'Settings', ), ), ), ),
          ActionButton(
            onTap: isObjectDetectionPage ? null : () => _performManualDetection(currentFeature.id),
            onLongPress: () {
               if (!_speechEnabled) { _showStatusMessage('Speech not available', isError: true); _initSpeech(); return; }
               if (_speechToText.isNotListening) { _startListening(); } else { _stopListening(); } },
            isListening: _isListening, color: currentFeature.color,
          ),
        ],
      ),
    );
  }
}