import 'dart:async';
import 'dart:convert'; // For json decoding in websocket handler (if needed)
import 'dart:math'; // For proximity calculation
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:flutter/foundation.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

import '../../core/models/feature_config.dart';
import '../../core/services/websocket_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/services/barcode_api_service.dart';

import '../../features/feature_registry.dart'; // Should contain focusModeFeature now
import '../../features/object_detection/presentation/pages/object_detection_page.dart';
import '../../features/hazard_detection/presentation/pages/hazard_detection_page.dart';
import '../../features/scene_detection/presentation/pages/scene_detection_page.dart';
import '../../features/text_detection/presentation/pages/text_detection_page.dart';
import '../../features/barcode_scanner/presentation/pages/barcode_scanner_page.dart';
import '../../features/focus_mode/presentation/pages/focus_mode_page.dart'; // Import the new page

import '../widgets/camera_view_widget.dart';
import '../widgets/feature_title_banner.dart';
import '../widgets/action_button.dart';

import 'settings_screen.dart';
// --- Imports End -----------------------------------------------------------------------------------------






class HomeScreen extends StatefulWidget {
  final CameraDescription? camera;

  const HomeScreen({Key? key, required this.camera}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}








class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // --- State Variables -----------------------------------------------------------------------------------
  // Camera & Page View
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  bool _isMainCameraInitializing = false;
  Key _cameraViewKey = UniqueKey();
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Speech Recognition
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;
  bool _isListeningForFocusObject = false; // Flag for focus object selection

  // Services & Settings
  final WebSocketService _webSocketService = WebSocketService();
  late List<FeatureConfig> _features;
  final SettingsService _settingsService = SettingsService();
  final TtsService _ttsService = TtsService();
  final BarcodeApiService _barcodeApiService = BarcodeApiService();
  bool _ttsInitialized = false;
  String _selectedOcrLanguage = SettingsService.getValidatedDefaultLanguage();
  String _selectedObjectCategory = defaultObjectCategory;

  // Detection Results & State
  String _lastObjectResult = ""; // For Object Detection page
  String _lastSceneTextResult = ""; // For Scene/Text pages
  String _lastHazardRawResult = ""; // Raw data for hazard check
  String _currentDisplayedHazardName = ""; // For Hazard Detection page
  bool _isHazardAlertActive = false;
  Timer? _hazardAlertClearTimer;
  Timer? _detectionTimer;
  bool _isProcessingImage = false;
  String? _lastRequestedFeatureId; // Tracks which feature requested the last image

  // Focus Mode State
  bool _isFocusModeActive = false;
  String? _focusedObject; // The object name to focus on
  bool _isFocusPromptActive = false; // True when prompting user to say the object
  bool _isFocusObjectDetectedInFrame = false; // True if the focused object is seen
  bool _isFocusObjectCentered = false; // True if the focused object is near center
  bool _announcedFocusFound = false; // Prevent spamming "found" message
  double _currentProximity = 0.0; // 0.0 (far/none) to 1.0 (center)
  Timer? _focusBeepTimer; // Timer for periodic beeps
  final AudioPlayer _beepPlayer = AudioPlayer(); // Player for focus beep

  // Audio & Haptics
  final AudioPlayer _alertAudioPlayer = AudioPlayer(); // Separate player for alerts
  bool _hasVibrator = false;
  bool? _hasAmplitudeControl; // To check if vibration intensity can be controlled






  // --- Constants ------------------------------------------------------------------------------------------
  static const String _alertSoundPath = "audio/alert.mp3"; // For hazard alerts
  static const String _beepSoundPath = "assets/audio/short_beep.mp3"; // For focus mode - PATH MUST MATCH pubspec.yaml and actual file location
  static const Duration _detectionInterval = Duration(seconds: 1);
  static const Duration _hazardAlertPersistence = Duration(seconds: 4);
  static const Duration _focusFoundAnnounceCooldown = Duration(seconds: 5); // Cooldown for saying "found"
  static const double _focusCenterThreshold = 0.15; // Normalized distance from center to be considered "centered"
  static const int _focusBeepMaxIntervalMs = 1200; // Slowest beep interval
  static const int _focusBeepMinIntervalMs = 150; // Fastest beep interval
  static const Set<String> _hazardObjectNames = {
    "car", "bicycle", "motorcycle", "bus", "train", "truck", "boat",
    "traffic light", "stop sign", "knife", "scissors", "fork",
    "oven", "toaster", "microwave", "bird", "cat", "dog", "horse",
    "sheep", "cow", "elephant", "bear", "zebra", "giraffe"
    // Add more specific hazards if needed
  };






  // --- Lifecycle Methods ------------------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
    debugPrint("[HomeScreen] initState Completed");
  }

  @override
  void dispose() {
    debugPrint("[HomeScreen] Disposing...");
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _disposeMainCameraController();
    _stopDetectionTimer();
    _hazardAlertClearTimer?.cancel();
    _stopFocusFeedback(); // Ensure beep timer is cancelled
    if (_speechToText.isListening) _speechToText.stop();
    _speechToText.cancel();
    if (_ttsInitialized) _ttsService.dispose();
    _alertAudioPlayer.dispose();
    _beepPlayer.dispose();
    _webSocketService.close();
    debugPrint("[HomeScreen] Dispose complete.");
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
    debugPrint("[Lifecycle] State changed to: $state, Current Page: $currentFeatureId (Focus Active: $_isFocusModeActive)");

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _handleAppPause();
    } else if (state == AppLifecycleState.resumed) {
      _handleAppResume();
    }
  }






  // --- Initialization Helper -----------------------------------------------------------------------------------
  Future<void> _initializeApp() async {
    _initializeFeatures();
    await _loadAndInitializeSettings();
    await _checkVibratorAndAmplitude(); // Check vibration capabilities
    await _prepareAudioPlayers(); // Prepare audio players

    final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
    // Don't init main camera if starting on barcode or focus mode (until object selected)
    if (currentFeatureId != barcodeScannerFeature.id && currentFeatureId != focusModeFeature.id) {
      await _initializeMainCameraController();
    } else {
      debugPrint("[HomeScreen] Initializing on barcode/focus page, skipping initial main camera init.");
    }
    await _initSpeech(); // Await speech init
    _initializeWebSocket();
    // Announce the initial feature if TTS is ready
    if(_ttsInitialized && _features.isNotEmpty) {
      _ttsService.speak(_features[0].title);
    }
  }

  void _initializeFeatures() {
     _features = availableFeatures; // Assumes availableFeatures includes focusModeFeature
     debugPrint("[HomeScreen] Features Initialized: ${_features.map((f) => f.id).toList()}");
  }

  Future<void> _loadAndInitializeSettings() async {
    // (Keep existing settings loading logic)
    final results = await Future.wait([
      _settingsService.getOcrLanguage(), _settingsService.getTtsVolume(),
      _settingsService.getTtsPitch(), _settingsService.getTtsRate(),
      _settingsService.getObjectDetectionCategory(),
    ]);
    _selectedOcrLanguage = results[0] as String;
    final ttsVolume = results[1] as double; final ttsPitch = results[2] as double;
    final ttsRate = results[3] as double; _selectedObjectCategory = results[4] as String;

    if (!_ttsInitialized) {
       await _ttsService.initTts(initialVolume: ttsVolume, initialPitch: ttsPitch, initialRate: ttsRate);
       _ttsInitialized = true;
    } else { await _ttsService.updateSettings(ttsVolume, ttsPitch, ttsRate); }
    debugPrint("[HomeScreen] Settings loaded. OCR: $_selectedOcrLanguage, Cat: $_selectedObjectCategory");
  }

  Future<void> _checkVibratorAndAmplitude() async {
    try {
      _hasVibrator = await Vibration.hasVibrator() ?? false;
      if (_hasVibrator) {
        _hasAmplitudeControl = await Vibration.hasAmplitudeControl() ?? false;
      } else {
        _hasAmplitudeControl = false;
      }
      debugPrint("[HomeScreen] Vibrator available: $_hasVibrator, Amplitude Control: $_hasAmplitudeControl");
    } catch (e) {
       debugPrint("[HomeScreen] Error checking vibration capabilities: $e");
        _hasVibrator = false; _hasAmplitudeControl = false;
    }
    if (mounted) setState(() {}); // Update state if needed
  }

   Future<void> _prepareAudioPlayers() async {
      try {
         // Set release mode to keep audio session active - important for repeated sounds
         await _beepPlayer.setReleaseMode(ReleaseMode.stop);
         await _alertAudioPlayer.setReleaseMode(ReleaseMode.stop);
         // Pre-load beep sound? Might reduce delay slightly but uses memory.
         // await _beepPlayer.setSource(AssetSource(_beepSoundPath));
         // await _beepPlayer.pause(); // Pause after setting source
      } catch (e) {
         debugPrint("[HomeScreen] Error preparing audio players: $e");
      }
   }






  // --- Lifecycle Event Handlers -----------------------------------------------------------------------------------
  void _handleAppPause() {
     debugPrint("[Lifecycle] App inactive/paused - Cleaning up...");
      _stopDetectionTimer(); // Stops timer for all modes
      _stopFocusFeedback(); // Stops focus beep timer
      if(_ttsInitialized) _ttsService.stop();
      _alertAudioPlayer.pause(); // Pause alerts
      _beepPlayer.pause(); // Pause beeps
      _hazardAlertClearTimer?.cancel();

      // Dispose camera only if not on barcode page
      final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
      if (currentFeatureId != barcodeScannerFeature.id) {
        _disposeMainCameraController();
      } else {
          debugPrint("[Lifecycle] App paused on barcode page, main camera already disposed.");
      }
  }

  void _handleAppResume() {
     debugPrint("[Lifecycle] App resumed");
      final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;

      // Re-initialize camera if needed (not barcode or focus mode without object)
      if (currentFeatureId != barcodeScannerFeature.id && !(_isFocusModeActive && _focusedObject == null)) {
         debugPrint("[Lifecycle] Resumed on non-barcode/non-initial-focus page. Ensuring main camera.");
         _initializeMainCameraController(); // Trigger init, don't await fully
      } else {
          debugPrint("[Lifecycle] Resumed on barcode page or initial focus page. Main camera remains off/uninitialized.");
      }

       if (!_webSocketService.isConnected) {
           debugPrint("[Lifecycle] Attempting WebSocket reconnect on resume...");
           _webSocketService.connect();
       } else {
           _startDetectionTimerIfNeeded(); // Restart timer if applicable
       }
  }






  // --- Camera Management (Keep _disposeMainCameraController and _initializeMainCameraController largely as before) ---
  Future<void> _disposeMainCameraController() async {
    // (Implementation from previous steps - ensure it handles _isMainCameraInitializing correctly)
     if (_cameraController == null && _initializeControllerFuture == null && !_isMainCameraInitializing) return;
     debugPrint("[HomeScreen] Disposing main camera controller...");
     _stopDetectionTimer(); // Stop before disposing
     final controllerToDispose = _cameraController; final initFuture = _initializeControllerFuture;
     _cameraController = null; _initializeControllerFuture = null; _isMainCameraInitializing = false;
     _cameraViewKey = UniqueKey(); // Reset key
     if(mounted) setState((){}); // Update UI to remove camera view
     try {
       if (initFuture != null) await initFuture.timeout(const Duration(milliseconds: 200)).catchError((_){});
       if (controllerToDispose != null) { await controllerToDispose.dispose(); debugPrint("[HomeScreen] Main camera disposed."); }
     } catch (e, s) { debugPrint("[HomeScreen] Error disposing camera: $e \n$s"); }
     debugPrint("[HomeScreen] Main camera dispose sequence finished."); // Added log
  }

  Future<void> _initializeMainCameraController() async {
    debugPrint("[HomeScreen] Attempting to initialize main camera controller..."); // Added log
    // (Implementation from previous steps - check conditions carefully)
     final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
     // Skip if no camera, barcode page, focus mode waiting for object, already exists, or already initializing
     bool isFocusModeWaitingForObject = _isFocusModeActive && _focusedObject == null; // Added variable for clarity
     if (widget.camera == null || currentFeatureId == barcodeScannerFeature.id || isFocusModeWaitingForObject || _cameraController != null || _isMainCameraInitializing) {
        debugPrint("[HomeScreen] Skipping main camera init. Reason: No camera (${widget.camera == null}), Barcode ($currentFeatureId == ${barcodeScannerFeature.id}), Initial Focus ($isFocusModeWaitingForObject), Exists (${_cameraController != null}), Initializing ($_isMainCameraInitializing)"); // Updated log
       return;
     }
     if (!mounted) { debugPrint("[HomeScreen] Camera init skipped: Not mounted."); return; } // Added log
     debugPrint("[HomeScreen] Proceeding with main CameraController initialization..."); // Added log
     _isMainCameraInitializing = true; _cameraController = null; _initializeControllerFuture = null;
     _cameraViewKey = UniqueKey(); // Reset key
     if (mounted) setState((){}); // Show loading indicator
     await Future.delayed(const Duration(milliseconds: 50)); // Reduced delay
     isFocusModeWaitingForObject = _isFocusModeActive && _focusedObject == null; // Re-check condition after delay
     if(!mounted || currentFeatureId == barcodeScannerFeature.id || isFocusModeWaitingForObject) { _isMainCameraInitializing = false; if(mounted) setState((){}); debugPrint("[HomeScreen] Aborting camera init after delay due to page change/unmount/focus state. Mounted: $mounted, Feature: $currentFeatureId, FocusWaiting: $isFocusModeWaitingForObject"); return; } // Updated log

     CameraController newController;
     try {
        debugPrint("[HomeScreen] Creating new CameraController instance..."); // Added log
        newController = CameraController(widget.camera!, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
     }
     catch(e) { debugPrint("[HomeScreen] Error creating CameraController: $e"); if (mounted) { _showStatusMessage("Failed to create camera", isError: true); _isMainCameraInitializing = false; setState((){}); } return; }

     Future<void> initFuture;
     try { _cameraController = newController; initFuture = newController.initialize(); _initializeControllerFuture = initFuture; if(mounted) setState((){}); }
     catch (e) { debugPrint("[HomeScreen] Error assigning init future: $e"); if (mounted) { _showStatusMessage("Failed camera init", isError: true); _cameraController = null; _initializeControllerFuture = null; _isMainCameraInitializing = false; setState((){}); } return; }

     try {
       await initFuture;
       if (!mounted) { debugPrint("[HomeScreen] Camera init successful but widget unmounted before completion. Disposing new controller."); try { await newController.dispose(); } catch (_) {} return; } // Added log
       if (_cameraController == newController) {
          debugPrint("[HomeScreen] Main Camera initialized successfully."); // Added log
          _isMainCameraInitializing = false;
          _startDetectionTimerIfNeeded(); // Crucial: Start timer now that camera is ready
       } else {
          debugPrint("[HomeScreen] Camera controller changed during initialization. Disposing new controller."); // Added log
          try { await newController.dispose(); } catch (_) {}
          _isMainCameraInitializing = false;
       }
      } catch (error,s) {
        debugPrint("[HomeScreen] Main Camera initialization error: $error\n$s"); // Added log
        if (!mounted) { _isMainCameraInitializing = false; return; }
       final bool shouldReset = _cameraController == newController;
        if(shouldReset) {
           debugPrint("[HomeScreen] Resetting camera controller state due to init error."); // Added log
           _showStatusMessage("Camera init failed", isError: true);
           _cameraController = null;
           _initializeControllerFuture = null;
        }
        else { try { await newController.dispose(); } catch (_) {} }
       _isMainCameraInitializing = false;
     } finally { if(mounted) setState(() {}); } // Final UI update
  }






  // --- WebSocket Handling -----------------------------------------------------------------------------
  void _initializeWebSocket() {
     debugPrint("[HomeScreen] Initializing WebSocket listener...");
     _webSocketService.responseStream.listen(
      _handleWebSocketData, // Changed to handle structured data
      onError: _handleWebSocketError,
      onDone: _handleWebSocketDone,
      cancelOnError: false
    );
    _webSocketService.connect();
  }

  void _handleWebSocketData(Map<String, dynamic> data) {
    if (!mounted) return;

    // Handle connection event separately
    if (data.containsKey('event') && data['event'] == 'connect') {
         _showStatusMessage("Connected", durationSeconds: 2);
         _startDetectionTimerIfNeeded();
         return;
    }

    // Expect 'result' to be the structured dictionary from the backend
    if (data.containsKey('result') && data['result'] is Map<String, dynamic>) {
        final Map<String, dynamic> resultData = data['result'];
        final String status = resultData['status'] ?? 'error'; // Default to error if status missing
        final String? receivedForFeatureId = _lastRequestedFeatureId;

        // Log raw status for debugging
        // debugPrint('[HomeScreen] Received WS Data Status: $status, For Feature: $receivedForFeatureId');
        // debugPrint('[HomeScreen] Full result data: $resultData');

        if (receivedForFeatureId == null && !_isFocusModeActive) {
           debugPrint('[HomeScreen] Received result, but _lastRequestedFeatureId is null and not focus mode. Ignoring.');
           return;
        }
        // In focus mode, we always process, don't need _lastRequestedFeatureId strictly
        // _lastRequestedFeatureId = null; // Clear ID after use (only relevant for non-focus)

        _processFeatureResult(receivedForFeatureId, status, resultData);

    } else {
        debugPrint('[HomeScreen] Received unexpected WS data format: $data');
        // Optionally handle raw string results if backend might still send them
        if(data.containsKey('result') && data['result'] is String) {
           // Handle legacy string result if necessary, maybe for hazard/object detection
           // if(_currentPage == objectDetectionFeatureIndex) { _lastObjectResult = data['result']; }
           // ...
        }
        // Reset processing flag if we get unexpected data
        if (_isProcessingImage) setState(() => _isProcessingImage = false);
    }
  }

  void _processFeatureResult(String? featureId, String status, Map<String, dynamic> resultData) {
     if (!mounted) return;

     // --- Always handle Hazard Check (using raw object detection results if available) ---
     // This part needs careful thought. If focus mode only returns the focused object,
     // hazard detection might stop working unless we run a separate object detection in parallel?
     // For now, let's assume hazard check only works reliably in 'object_detection' mode.
     // OR modify backend 'focus_detection' to *also* return all detected objects separately for hazard check.
     // --- Current simple approach: Check only if the *explicit* request was for object detection ---
     if (featureId == objectDetectionFeature.id && status == 'ok') {
         // Process raw detections for hazards if available
         List<String> currentDetections = (resultData['detections'] as List<dynamic>?)
             ?.map((d) => (d as Map<String, dynamic>)['name'] as String? ?? '')
             .where((name) => name.isNotEmpty)
             .toList() ?? [];
         _processHazardDetection(currentDetections);
     } else if (featureId == hazardDetectionFeature.id) {
        // If hazard has its own explicit call type, handle it here
     }
     // --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---


     setState(() {
         // --- Handle Focus Mode Results ---
         if (_isFocusModeActive) {
             if (status == 'found') {
                 final detection = resultData['detection'] as Map<String, dynamic>?;
                 final String detectedName = (detection?['name'] as String?)?.toLowerCase() ?? "null"; // Added log variable
                 final String targetName = _focusedObject?.toLowerCase() ?? "null"; // Added log variable
                 debugPrint("[Focus] Received detection: '$detectedName'. Target: '$targetName'. Status: '$status'"); // Added log
                 if (detection != null && detectedName == targetName) {
                     final double centerX = detection['center_x'] as double? ?? 0.5;
                     final double centerY = detection['center_y'] as double? ?? 0.5;
                     // Calculate distance from center (0.5, 0.5)
                     final double dx = centerX - 0.5;
                     final double dy = centerY - 0.5;
                     final double dist = sqrt(dx * dx + dy * dy); // Distance from 0 to sqrt(0.5^2 + 0.5^2) = 0.707
                     // Normalize proximity: 1.0 at center, 0.0 at corner
                     final double newProximity = (1.0 - (dist / 0.707)).clamp(0.0, 1.0); // Added log variable
                     debugPrint("[Focus] Target '$targetName' found. Center: ($centerX, $centerY), Dist: ${dist.toStringAsFixed(3)}, Proximity: ${newProximity.toStringAsFixed(3)}"); // Added log
                     _currentProximity = newProximity;
                     _isFocusObjectDetectedInFrame = true;
                     _isFocusObjectCentered = dist < _focusCenterThreshold;

                     // Announce "Found!" only once when centered, with cooldown
                     if (_isFocusObjectCentered && !_announcedFocusFound) {
                        if(_ttsInitialized) _ttsService.speak("${_focusedObject ?? 'Object'} found!");
                        _announcedFocusFound = true;
                        // Reset announcement flag after cooldown
                        Future.delayed(_focusFoundAnnounceCooldown, () {
                           if (mounted) _announcedFocusFound = false;
                        });
                     }
                     // Update UI state for FocusModePage handled by setState
                 } else {
                     // Found something, but not the focused object? Reset state.
                     debugPrint("[Focus] Detected object '$detectedName' does not match target '$targetName'. Resetting proximity."); // Added log
                     _currentProximity = 0.0;
                     _isFocusObjectDetectedInFrame = false;
                     _isFocusObjectCentered = false;
                 }
             } else { // 'not_found', 'none', 'error'
                 debugPrint("[Focus] Target '$_focusedObject' not found or error status '$status'. Resetting proximity."); // Added log
                 _currentProximity = 0.0;
                 _isFocusObjectDetectedInFrame = false;
                 _isFocusObjectCentered = false;
                 // Optionally announce "lost" if it was previously found?
             }
             _updateFocusFeedback(); // Update beeps/vibration based on new proximity
         }
         // --- Handle Normal Mode Results ---
         else {
             bool speakResult = false;
             String textToSpeak = "";
             String displayResult = "";

             if (featureId == objectDetectionFeature.id) {
                 if (status == 'ok') {
                     List<String> names = (resultData['detections'] as List<dynamic>?)
                         ?.map((d) => (d as Map<String, dynamic>)['name'] as String? ?? '')
                         .where((name) => name.isNotEmpty)
                         .toList() ?? [];
                     // Filter based on category (using _selectedObjectCategory and cocoObjectToCategoryMap)
                     List<String> filteredNames = _filterObjectsByCategory(names);
                     displayResult = filteredNames.isNotEmpty ? filteredNames.join(', ') : "No objects in category";
                     speakResult = filteredNames.isNotEmpty;
                     textToSpeak = displayResult;
                 } else if (status == 'none') {
                     displayResult = "No objects detected";
                 } else { // error
                     displayResult = resultData['message'] ?? "Detection Error";
                 }
                 _lastObjectResult = displayResult;
             }
             else if (featureId == sceneDetectionFeature.id) {
                 if (status == 'ok') {
                     displayResult = (resultData['scene'] as String? ?? "Unknown Scene").replaceAll('_', ' ');
                     speakResult = true;
                     textToSpeak = "Scene: $displayResult";
                 } else { displayResult = resultData['message'] ?? "Scene Error"; }
                 _lastSceneTextResult = displayResult;
             }
             else if (featureId == textDetectionFeature.id) {
                  if (status == 'ok') {
                     displayResult = resultData['text'] as String? ?? "No text";
                     // Avoid speaking very long text? Add length check if needed.
                     speakResult = true;
                     textToSpeak = "Text detected: $displayResult";
                 } else if (status == 'none') {
                     displayResult = "No text detected";
                 } else { displayResult = resultData['message'] ?? "Text Error"; }
                 _lastSceneTextResult = displayResult;
             }
             // Ignore hazard feature ID explicitly here, as it's handled by _processHazardDetection

             // Speak result if needed (excluding hazards and focus mode)
             if (speakResult && _ttsInitialized && featureId != hazardDetectionFeature.id) {
                 _ttsService.speak(textToSpeak);
             }
         }
         _isProcessingImage = false; // Reset processing flag
     });
  }

  List<String> _filterObjectsByCategory(List<String> objectNames) {
      if (_selectedObjectCategory == 'all') return objectNames;
      return objectNames.where((obj) {
          String lowerObj = obj.toLowerCase();
          return cocoObjectToCategoryMap[lowerObj] == _selectedObjectCategory;
      }).toList();
  }

  void _processHazardDetection(List<String> detectedObjectNames){
        String specificHazardFound = "";
        bool hazardFoundInFrame = false;
        String lowerCaseName = "";

        for (String objName in detectedObjectNames) {
            lowerCaseName = objName.toLowerCase();
            if (_hazardObjectNames.contains(lowerCaseName)) {
                hazardFoundInFrame = true;
                specificHazardFound = lowerCaseName; // Use the detected name
                break;
            }
        }

        if (hazardFoundInFrame) {
            _triggerHazardAlert(specificHazardFound);
        }
        // No 'else' needed - if no hazard, the alert timer will clear the display
  }

  void _handleWebSocketError(error) {
    if (!mounted) return;
    debugPrint('[HomeScreen] WebSocket Error: $error');
    _stopDetectionTimer();
    _stopFocusFeedback();
    _hazardAlertClearTimer?.cancel();
    if(_ttsInitialized) _ttsService.stop();
    setState(() {
      _isProcessingImage = false;
      _lastObjectResult = "Connection Error"; _lastSceneTextResult = "Connection Error";
      _lastHazardRawResult = ""; _isHazardAlertActive = false; _currentDisplayedHazardName = "";
      _isFocusModeActive = false; _focusedObject = null; // Reset focus mode on error too
    });
    _showStatusMessage("Connection Error: ${error.toString()}", isError: true);
  }

  void _handleWebSocketDone() {
    if (!mounted) return;
    debugPrint('[HomeScreen] WebSocket connection closed.');
    _stopDetectionTimer();
    _stopFocusFeedback();
    _hazardAlertClearTimer?.cancel();
    if(_ttsInitialized) _ttsService.stop();
    if (mounted) {
       setState(() {
         _isProcessingImage = false;
         _lastObjectResult = "Disconnected"; _lastSceneTextResult = "Disconnected";
         _lastHazardRawResult = ""; _isHazardAlertActive = false; _currentDisplayedHazardName = "";
         _isFocusModeActive = false; _focusedObject = null;
       });
       _showStatusMessage('Disconnected. Trying to reconnect...', isError: true, durationSeconds: 5);
    }
  }






  // --- Speech Recognition Handling -----------------------------------------------------------------------------------------
  Future<void> _initSpeech() async {
     try {
       _speechEnabled = await _speechToText.initialize(
           onStatus: _handleSpeechStatus, onError: _handleSpeechError, debugLogging: kDebugMode);
       debugPrint('Speech recognition initialized: $_speechEnabled');
       if (!_speechEnabled && mounted) _showStatusMessage('Speech unavailable', durationSeconds: 3);
     } catch (e) { debugPrint('Error initializing speech: $e'); if (mounted) _showStatusMessage('Speech init failed', durationSeconds: 3); }
  }

   void _handleSpeechStatus(String status) {
     if (!mounted) return;
     debugPrint('Speech status: $status');
     final bool isCurrentlyListening = status == SpeechToText.listeningStatus;
     if (_isListening != isCurrentlyListening) {
         setState(() => _isListening = isCurrentlyListening);
     }
     // REMOVED: Premature reset of _isListeningForFocusObject flag
     // if (!isCurrentlyListening && _isListeningForFocusObject) {
     //    debugPrint("[Speech Status] Listening stopped, resetting _isListeningForFocusObject flag (prematurely?)."); // Added log for debugging removal
     //    _isListeningForFocusObject = false;
     // }
   }

   void _handleSpeechError(SpeechRecognitionError error) {
     if (!mounted) return;
     debugPrint('Speech error: ${error.errorMsg} (Permanent: ${error.permanent})');
     if (_isListening) setState(() => _isListening = false);
     if (_isListeningForFocusObject) {
        debugPrint("[Speech Error] Resetting _isListeningForFocusObject flag due to error."); // Added log
        _isListeningForFocusObject = false; // Reset flag on error
     }
     String errorMessage = 'Speech error: ${error.errorMsg}';
     // --- Refined Error Handling ---
     if (error.errorMsg.contains('permission') || error.errorMsg.contains('denied')) {
        // Only show permission instructions for actual permission errors
        errorMessage = 'Microphone permission needed.';
        _showPermissionInstructions();
     } else if (error.errorMsg == 'error_no_match') {
        errorMessage = 'Could not recognize speech. Please try again.'; // Specific message for no match
     } else if (error.errorMsg.contains('No speech')) {
        errorMessage = 'No speech detected.';
     } else if (error.errorMsg.contains('timeout')) {
        errorMessage = 'Listening timed out.';
     } else if (error.permanent) {
        // Handle other permanent errors if necessary, but avoid generic permission message
        errorMessage = 'Speech recognition error. Please restart the app if issues persist.';
     }
     // --- End Refined Error Handling ---
     _showStatusMessage(errorMessage, isError: true, durationSeconds: 4);
   }

   // Modified to handle focus object selection
   void _startListening({bool isForFocusObject = false}) async {
     if (!_speechEnabled) { _showStatusMessage('Speech not available', isError: true); _initSpeech(); return; }
     bool hasPermission = await _speechToText.hasPermission;
     if (!hasPermission && mounted) { _showPermissionInstructions(); _showStatusMessage('Microphone permission needed', isError: true); return; }
     if (!mounted) return;
     if (_speechToText.isListening) await _stopListening(); // Stop previous before starting new

     _isListeningForFocusObject = isForFocusObject; // Set the flag
     debugPrint("Starting speech listener... (For Focus Object: $_isListeningForFocusObject)");
     if(_ttsInitialized) _ttsService.stop(); // Stop TTS before listening

     try {
        // Use a slightly longer timeout if waiting for focus object name?
        await _speechToText.listen(
           onResult: _handleSpeechResult,
           listenFor: Duration(seconds: isForFocusObject ? 10 : 7), // Longer if prompting
           pauseFor: const Duration(seconds: 3),
           partialResults: false, // We need the final result
           cancelOnError: true, // Stop listening on error
           listenMode: ListenMode.confirmation // Or deviceDefault
        );
         if (mounted) setState(() {}); // Update UI immediately
     } catch (e) {
        debugPrint("Error starting speech listener: $e");
        if (mounted) { _showStatusMessage("Could not start listening", isError: true); setState(() => _isListening = false); }
        if (_isListeningForFocusObject) {
           debugPrint("[Speech Start Error] Resetting _isListeningForFocusObject flag due to start error."); // Added log
           _isListeningForFocusObject = false; // Reset flag on error
        }
     }
   }

   Future<void> _stopListening() async {
      if (_speechToText.isListening) {
         debugPrint("Stopping speech listener...");
         await _speechToText.stop();
         // Status callback (_handleSpeechStatus) should set _isListening to false
         // No need for setState here if status callback works reliably
      }
      if (_isListeningForFocusObject) {
         debugPrint("[Speech Stop] Resetting _isListeningForFocusObject flag due to manual stop."); // Added log
         _isListeningForFocusObject = false; // Ensure flag is reset when manually stopping
      }
   }

   void _handleSpeechResult(SpeechRecognitionResult result) {
     if (mounted && result.finalResult && result.recognizedWords.isNotEmpty) {
         String command = result.recognizedWords.toLowerCase().trim();
         debugPrint('Final recognized speech: "$command" (Was for focus: $_isListeningForFocusObject)');

         if (_isFocusModeActive && _isListeningForFocusObject) {
            // --- Set/Change Focused Object ---
            debugPrint("[Focus] Setting focused object to: '$command'"); // Added log
            setState(() {
               _focusedObject = command;
               _isFocusPromptActive = false; // Hide the prompt message
               _isFocusObjectDetectedInFrame = false; // Reset detection state
               _isFocusObjectCentered = false;
               _currentProximity = 0.0;
               _announcedFocusFound = false;
            });
            _stopFocusFeedback(); // Stop previous beeps/vibration
            if (_ttsInitialized) {
               _ttsService.speak("Focusing on ${_focusedObject ?? 'object'}");
            }
            // CRITICAL: Initialize camera now that we have an object
            debugPrint("[Focus] Object set. Triggering camera initialization..."); // Added log
            _initializeMainCameraController(); // <<<--- ADDED CAMERA INIT CALL
            // Timer will be started by _initializeMainCameraController if successful
            // _startDetectionTimerIfNeeded(); // Start/ensure timer is running for the new object - Now handled by camera init callback
            debugPrint("Focus object set to: $_focusedObject. Camera init requested."); // Updated log
         } else {
            // --- Process General Command ---
            debugPrint("[Speech] Processing general command: '$command'"); // Added log
            _processGeneralSpeechCommand(command);
         }
         // Reset flag AFTER processing the result
         if (_isListeningForFocusObject) {
            debugPrint("[Speech Result] Resetting _isListeningForFocusObject flag after processing result."); // Added log
            _isListeningForFocusObject = false;
         }
     }
   }

   void _processGeneralSpeechCommand(String command) {
       // (Keep existing command processing logic for navigation/settings)
       if (command == 'settings' || command == 'setting') { _navigateToSettingsPage(); return; }
       int targetPageIndex = -1;
       for (int i = 0; i < _features.length; i++) {
         for (String keyword in _features[i].voiceCommandKeywords) {
           if (command.contains(keyword)) { targetPageIndex = i; break; }
         }
         if (targetPageIndex != -1) break;
       }
       if (targetPageIndex != -1) {
           if (targetPageIndex == _features.indexWhere((f) => f.id == focusModeFeature.id)) {
              // Explicitly navigate to focus mode (will trigger onPageChanged logic)
              _navigateToPage(targetPageIndex);
           } else {
              _navigateToPage(targetPageIndex); // Navigate to other pages
           }
       } else { _showStatusMessage('Command "$command" not recognized.', durationSeconds: 3); }
   }






  // --- Detection Logic -------------------------------------------------------------------------------------------
  void _startDetectionTimerIfNeeded() {
    if (!mounted || _features.isEmpty) return;
    final currentFeatureId = _features[_currentPage.clamp(0, _features.length - 1)].id;

    bool shouldRunTimer = false;
    // Condition 1: Normal realtime pages (Object/Hazard)
    bool isNormalRealtime = (currentFeatureId == objectDetectionFeature.id || currentFeatureId == hazardDetectionFeature.id);
    // Condition 2: Focus mode is active AND an object has been selected
    bool isFocusModeRunning = _isFocusModeActive && _focusedObject != null;

    if ((isNormalRealtime || isFocusModeRunning) &&
        _detectionTimer == null &&
        _cameraController != null &&
        (_cameraController?.value.isInitialized ?? false) &&
        !_isMainCameraInitializing &&
        _webSocketService.isConnected)
    {
        shouldRunTimer = true;
    }

    if (shouldRunTimer) {
        debugPrint("[HomeScreen] Starting detection timer. Mode: ${isFocusModeRunning ? 'Focus' : 'Normal Realtime'}");
        _detectionTimer = Timer.periodic(_detectionInterval, (_) { _performPeriodicDetection(); });
    } else {
        // Stop timer if conditions are not met for the current active mode
         bool shouldStopTimer = false;
         if (_detectionTimer != null) {
            if (_isFocusModeActive && _focusedObject == null) shouldStopTimer = true; // Stop if in focus mode but no object yet
            else if (!isNormalRealtime && !isFocusModeRunning) shouldStopTimer = true; // Stop if not in any realtime mode
         }
        if (shouldStopTimer) {
             _stopDetectionTimer();
        }
        // Log why timer isn't starting if relevant
        // else if (isNormalRealtime || isFocusModeRunning) {
        //    debugPrint("[HomeScreen] Not starting detection timer. Conditions not met: Timer Exists (${_detectionTimer != null}), Controller Null (${_cameraController == null}), Controller Uninit (${!(_cameraController?.value.isInitialized ?? false)}), Controller Initializing ($_isMainCameraInitializing), WS Disconnected (${!_webSocketService.isConnected}), Focus Object Null (${_isFocusModeActive && _focusedObject == null})");
        // }
    }
  }

  void _stopDetectionTimer() {
    if (_detectionTimer?.isActive ?? false) {
        debugPrint("[HomeScreen] Stopping detection timer...");
        _detectionTimer!.cancel(); _detectionTimer = null;
        // Reset processing flag when timer stops
        if (mounted && _isProcessingImage) setState(() => _isProcessingImage = false);
    }
  }

  void _performPeriodicDetection() async {
     // --- Stricter Check: Ensure controller used is the *current* one and not disposed ---
     final currentController = _cameraController; // Capture instance at start of check
     if (!mounted || currentController == null || !currentController.value.isInitialized || currentController.value.isTakingPicture || _isMainCameraInitializing || _isProcessingImage || !_webSocketService.isConnected || _features.isEmpty) {
        // debugPrint("[HomeScreen] Periodic detection skipped: Pre-checks failed. Mounted: $mounted, ControllerNull: ${currentController == null}, ControllerUninit: ${!(currentController?.value.isInitialized ?? false)}, TakingPic: ${currentController?.value.isTakingPicture ?? false}, CamInitializing: $_isMainCameraInitializing, ProcessingImg: $_isProcessingImage, WSConnected: ${_webSocketService.isConnected}, FeaturesEmpty: ${_features.isEmpty}");
        return;
     }
     // --- End Stricter Check ---

     final currentFeatureId = _features[_currentPage.clamp(0, _features.length - 1)].id;
     bool isFocusDetection = _isFocusModeActive && _focusedObject != null && currentFeatureId == focusModeFeature.id;
     bool isNormalObjectDetection = currentFeatureId == objectDetectionFeature.id;
     bool isHazardDetection = currentFeatureId == hazardDetectionFeature.id; // Usually relies on object detection

     // Determine the type of detection needed
     String detectionTypeToSend;
     String? focusObjectToSend;
     String? featureRequesting;

     if (isFocusDetection) {
        detectionTypeToSend = 'focus_detection';
        focusObjectToSend = _focusedObject;
        featureRequesting = focusModeFeature.id; // Mark as focus request
     } else if (isNormalObjectDetection || isHazardDetection) {
        // Send 'object_detection' for both normal object and hazard pages
        detectionTypeToSend = 'object_detection';
        featureRequesting = currentFeatureId; // Mark as object/hazard request
     } else {
         // Not a page requiring periodic detection
         // debugPrint("[HomeScreen] Periodic detection skipped: Not a realtime page.");
         _stopDetectionTimer(); // Stop timer if we landed here unexpectedly
         return;
     }

     if (!_cameraControllerCheck(showError: false)) return; // Quick camera check

     try {
       // --- Check again if controller changed or became invalid before taking picture ---
       if (!mounted || _cameraController != currentController || !_cameraController!.value.isInitialized) {
          debugPrint("[Detection] Aborting takePicture: State changed during check.");
          if (mounted && _isProcessingImage) setState(() => _isProcessingImage = false); // Reset flag if we abort here
          return;
       }
       // --- End Check ---

       if (mounted) setState(() => _isProcessingImage = true); else return; // Check mount before setState
       _lastRequestedFeatureId = featureRequesting; // Track who requested this frame
       debugPrint("[Detection] Taking picture for feature: $featureRequesting (Focus Object: $focusObjectToSend)"); // Added log

       // Use the controller instance captured at the start of the function
       final XFile imageFile = await currentController.takePicture();

       // Send to backend using the modified service method
  _webSocketService.sendImageForProcessing(
        imageFile: imageFile, // Use named parameter
        processingType: detectionTypeToSend, // Use named parameter
        focusObject: focusObjectToSend,
   );

     } catch (e, stackTrace) {
       // Check if the error is specifically about using a disposed controller
       if (e is CameraException && e.code == 'disposed') {
          debugPrint("[Detection] Error: Attempted to use disposed CameraController for $featureRequesting. Likely race condition during page change. Ignoring.");
          // Don't call _handleCaptureError for this specific case if it's expected during transitions
       } else {
          _handleCaptureError(e, stackTrace, featureRequesting);
       }
       _lastRequestedFeatureId = null; // Reset on error
       if (mounted) setState(() => _isProcessingImage = false); // Reset flag on error
     }
     // Note: _isProcessingImage is reset in _handleWebSocketData upon receiving a response
     // Adding a timeout reset might be wise if backend responses can be lost
  }

  // Manual detection for non-realtime pages (Scene, Text)
  void _performManualDetection(String featureId) async {
     // Exclude realtime and barcode pages
     if (featureId == objectDetectionFeature.id || featureId == hazardDetectionFeature.id || featureId == focusModeFeature.id || featureId == barcodeScannerFeature.id) return;

     debugPrint('Manual detection triggered for feature: $featureId');
     if (!_cameraControllerCheck(showError: true)) { debugPrint('Manual detection aborted: Camera check failed.'); return; }
     if (_isProcessingImage || !_webSocketService.isConnected) { debugPrint('Manual detection aborted: Processing/WS disconnected.'); return; }

     try {
       setState(() => _isProcessingImage = true);
       _lastRequestedFeatureId = featureId; // Track request
       if(_ttsInitialized) _ttsService.stop();
       _showStatusMessage("Capturing...", durationSeconds: 1);
       final XFile imageFile = await _cameraController!.takePicture();
       _showStatusMessage("Processing...", durationSeconds: 2);

       // Send appropriate type and language if needed
   _webSocketService.sendImageForProcessing(
        imageFile: imageFile, // Use named parameter
        processingType: featureId, // Use named parameter (sending featureId as the type)
        languageCode: (featureId == textDetectionFeature.id) ? _selectedOcrLanguage : null,
   );
     } catch (e, stackTrace) {
       _handleCaptureError(e, stackTrace, featureId);
       _lastRequestedFeatureId = null; // Reset on error
       if (mounted) setState(() => _isProcessingImage = false); // Reset flag
     }
     // _isProcessingImage reset in _handleWebSocketData
   }

  bool _cameraControllerCheck({required bool showError}) {
    // (Keep existing implementation, ensures camera is ready for non-barcode pages)
      final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
      if(currentFeatureId == barcodeScannerFeature.id) return false; // No check needed for barcode

      bool isReady = _cameraController != null && _cameraController!.value.isInitialized && !_isMainCameraInitializing;
      if (!isReady) {
        // debugPrint('Camera check failed (Null: ${_cameraController == null}, Uninit: ${!(_cameraController?.value.isInitialized ?? true)}, Initializing: $_isMainCameraInitializing).');
        if (!_isMainCameraInitializing && showError) _showStatusMessage("Camera not ready", isError: true);
        if (_cameraController == null && widget.camera != null && !_isMainCameraInitializing && showError) { _initializeMainCameraController(); }
        return false;
      }
      if (_cameraController!.value.isTakingPicture) { /* debugPrint('Camera busy.'); */ return false; }
      return true;
   }

  void _handleCaptureError(Object e, StackTrace stackTrace, String? featureId) {
     // (Keep existing implementation)
     final idForLog = featureId ?? "unknown_feature";
     debugPrint('Capture/Send Error for $idForLog: $e'); debugPrintStack(stackTrace: stackTrace);
     String errorMsg = e is CameraException ? "Capture Error: ${e.description ?? e.code}" : "Processing Error";
     if (mounted) {
       if(_ttsInitialized) _ttsService.stop();
       setState(() {
         if (featureId == objectDetectionFeature.id) _lastObjectResult = "Error";
         else if (featureId == hazardDetectionFeature.id) { _lastHazardRawResult = ""; _clearHazardAlert(); _hazardAlertClearTimer?.cancel(); }
         else if (featureId == focusModeFeature.id) { _stopFocusFeedback(); _focusedObject=null; _isFocusModeActive=false; /* maybe navigate away? */ }
         else if (featureId != null && featureId != barcodeScannerFeature.id) _lastSceneTextResult = "Error";
       });
       _showStatusMessage(errorMsg, isError: true, durationSeconds: 4);
     }
   }






  // --- Alerting (Hazard & Focus) --------------------------------------------------------------------------------
   void _triggerHazardAlert(String hazardName) {
    // (Keep existing implementation - uses _alertAudioPlayer)
    debugPrint("[ALERT] Hazard Triggering for: $hazardName");
    bool wasAlreadyActive = _isHazardAlertActive;
    if (mounted) setState(() { _isHazardAlertActive = true; _currentDisplayedHazardName = hazardName; });
    _playAlertSound(); // Use separate player
    _triggerVibration(isHazard: true); // Indicate hazard vibration
    if (!wasAlreadyActive && _ttsInitialized) _ttsService.speak("Hazard detected: ${hazardName.replaceAll('_', ' ')}");
    _hazardAlertClearTimer?.cancel();
    _hazardAlertClearTimer = Timer(_hazardAlertPersistence, _clearHazardAlert);
  }

   void _clearHazardAlert() {
      // (Keep existing implementation)
      if (mounted && _isHazardAlertActive) { setState(() { _isHazardAlertActive = false; _currentDisplayedHazardName = ""; }); debugPrint("[ALERT] Hazard alert cleared."); }
      _hazardAlertClearTimer = null;
   }

   Future<void> _playAlertSound() async {
    // (Keep existing implementation - uses _alertAudioPlayer)
    try { await _alertAudioPlayer.play(AssetSource(_alertSoundPath), volume: 1.0); debugPrint("[ALERT] Playing hazard sound."); }
    catch (e) { debugPrint("[ALERT] Error playing hazard sound: $e"); }
  }

  // --- Focus Mode Feedback ---
  void _updateFocusFeedback() {
      if (!mounted || !_isFocusModeActive) {
          _stopFocusFeedback(); // Ensure stopped if not active
          return;
      }
      _focusBeepTimer?.cancel(); // Cancel previous timer

      if (_currentProximity > 0.05) { // Only beep/vibrate if object detected and somewhat close
          // Calculate interval (inversely proportional to proximity)
          final double proximityFactor = _currentProximity * _currentProximity; // Square for faster change near center
          int interval = (_focusBeepMaxIntervalMs - (proximityFactor * (_focusBeepMaxIntervalMs - _focusBeepMinIntervalMs))).toInt();
          interval = interval.clamp(_focusBeepMinIntervalMs, _focusBeepMaxIntervalMs); // Ensure within bounds
          debugPrint("[Focus Feedback] Updating feedback. Proximity: ${_currentProximity.toStringAsFixed(2)}, Interval: $interval ms"); // Added log

          _focusBeepTimer = Timer.periodic(Duration(milliseconds: interval), (_) {
             if(!mounted || !_isFocusModeActive) {
                debugPrint("[Focus Feedback] Timer tick skipped: Not mounted or focus mode inactive."); // Added log
                _focusBeepTimer?.cancel();
                return;
             } // Check validity inside timer
             _playBeepSound();
             _triggerVibration(proximity: _currentProximity); // Trigger vibration with proximity
          });
      } else {
           debugPrint("[Focus Feedback] Proximity (${_currentProximity.toStringAsFixed(2)}) too low. Stopping feedback."); // Added log
          // Timer already cancelled above
      }
  }

  void _stopFocusFeedback() {
     _focusBeepTimer?.cancel();
     _focusBeepTimer = null;
     // Don't stop the player here, just cancel the timer
     // debugPrint("Focus feedback stopped.");
  }

  Future<void> _playBeepSound() async {
      debugPrint("[Focus Feedback] Playing beep sound..."); // Added log
      try {
         // Use lowLatency mode for faster playback of short sounds
         await _beepPlayer.play(AssetSource(_beepSoundPath), mode: PlayerMode.lowLatency, volume: 0.8); // Adjust volume as needed
      } catch (e) {
         debugPrint("[Focus Feedback] Error playing beep sound: $e"); // Updated log prefix
      }
  }

  // Modified to handle different vibration types/intensities
  Future<void> _triggerVibration({bool isHazard = false, double proximity = 0.0}) async {
    if (!_hasVibrator) return; // Exit if no vibrator

    try {
      if (isHazard) {
        // Strong, longer vibration for hazards
        Vibration.vibrate(duration: 500, amplitude: 255);
        debugPrint("[ALERT] Triggering hazard vibration.");
      } else if (_isFocusModeActive && proximity > 0.05) {
        // Focus mode vibration - intensity based on proximity
        if (_hasAmplitudeControl ?? false) {
           // Amplitude control available: Scale amplitude (1-255)
           int amplitude = (1 + (proximity * 254)).toInt().clamp(1, 255);
           Vibration.vibrate(duration: 80, amplitude: amplitude); // Short pulse, varying intensity
           // debugPrint("[Focus Vibrate] Amp: $amplitude");
        } else {
           // No amplitude control: Simple short pulse
           Vibration.vibrate(duration: 80);
           // debugPrint("[Focus Vibrate] Simple pulse");
        }
      }
    } catch (e) {
       debugPrint("[Vibration] Error triggering vibration: $e");
    }
  }






  // --- Navigation & UI Helpers -----------------------------------------------------------------------------------------
  void _showStatusMessage(String message, {bool isError = false, int durationSeconds = 3}) {
    // (Keep existing implementation)
    if (!mounted) return; debugPrint("[Status] $message ${isError ? '(Error)' : ''}");
    final messenger = ScaffoldMessenger.of(context); messenger.removeCurrentSnackBar();
    messenger.showSnackBar( SnackBar( content: Text(message), backgroundColor: isError ? Colors.redAccent : Colors.grey[800], duration: Duration(seconds: durationSeconds), behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(bottom: 90.0, left: 15.0, right: 15.0), shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(10.0), ), ), );
  }

   void _navigateToPage(int pageIndex) {
      // (Keep existing implementation)
      if (!mounted || _features.isEmpty) return; final targetIndex = pageIndex.clamp(0, _features.length - 1);
      if (targetIndex != _currentPage && _pageController.hasClients) { if(_ttsInitialized) _ttsService.stop(); debugPrint("Navigating to page index: $targetIndex (${_features[targetIndex].title})"); _pageController.animateToPage( targetIndex, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut, ); }
   }

   Future<void> _navigateToSettingsPage() async {
    // (Keep existing implementation, ensures focus feedback stops)
     if (!mounted) return; debugPrint("Navigating to Settings...");
     if (_speechToText.isListening) await _stopListening();
     if(_ttsInitialized) _ttsService.stop();
     _stopDetectionTimer(); _stopFocusFeedback(); // Stop focus things
     final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
     bool isMainCameraPage = currentFeatureId != barcodeScannerFeature.id;
     if (isMainCameraPage) await _disposeMainCameraController();
     await Navigator.push( context, MaterialPageRoute(builder: (context) => const SettingsScreen()), );
     if (!mounted) return; debugPrint("Returned from Settings."); await _loadAndInitializeSettings(); // Reload
     if (isMainCameraPage && !(_isFocusModeActive && _focusedObject == null)) await _initializeMainCameraController(); // Re-init camera if needed
     _startDetectionTimerIfNeeded(); // Restart timer if applicable
   }

   void _showPermissionInstructions() {
    // (Keep existing implementation)
     if (!mounted) return; showDialog( context: context, builder: (BuildContext dialogContext) => AlertDialog( title: const Text('Microphone Permission'), content: const Text(
      'Voice control requires microphone access.\nPlease enable the Microphone permission in Settings.',
     ), actions: <Widget>[ TextButton( child: const Text('OK'), onPressed: () => Navigator.of(dialogContext).pop(), ), ], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)), ), );
   }






   // --- Page Change Handler -----------------------------------------------------------------------------------------
   void _onPageChanged(int index) async {
      if (!mounted) return;
      final newPageIndex = index.clamp(0, _features.length - 1);
      if (newPageIndex >= _features.length) return;
      final previousPageIndex = _currentPage.clamp(0, _features.length - 1);
      if (previousPageIndex >= _features.length || previousPageIndex == newPageIndex) return;

      final previousFeature = _features[previousPageIndex];
      final newFeature = _features[newPageIndex];
      debugPrint("[Navigation] Page changed from ${previousFeature.id} (index $previousPageIndex) to ${newFeature.id} (index $newPageIndex)"); // Updated log

      // --- Stop everything from previous page ---
      debugPrint("[Navigation] Stopping activities from previous page: ${previousFeature.id}"); // Added log
      if(_ttsInitialized) _ttsService.stop();
      _stopDetectionTimer();
      _stopFocusFeedback(); // Stop focus beeps/vibration if leaving focus mode
      if (previousFeature.id == hazardDetectionFeature.id) _clearHazardAlert();
      // --- --- --- --- --- --- --- --- --- ---

      // --- Handle State Transitions ---
      bool wasFocusMode = _isFocusModeActive;
      _isFocusModeActive = newFeature.id == focusModeFeature.id; // Set focus mode flag based on new page

      // --- Update page index state FIRST ---
      if(mounted) setState(() => _currentPage = newPageIndex); else return;

      // --- Camera Transitions ---
      bool isSwitchingToBarcode = newFeature.id == barcodeScannerFeature.id;
      bool isSwitchingToFocusInitial = _isFocusModeActive; // Entering focus mode
      bool isSwitchingFromBarcode = previousFeature.id == barcodeScannerFeature.id;
      bool isSwitchingFromFocus = wasFocusMode; // Leaving focus mode specifically

      debugPrint("[Navigation] Camera Transition Logic: ToBarcode=$isSwitchingToBarcode, ToFocusInitial=$isSwitchingToFocusInitial, FromBarcode=$isSwitchingFromBarcode, FromFocus=$isSwitchingFromFocus"); // Added log

      if (isSwitchingToBarcode || isSwitchingToFocusInitial) {
          // Dispose camera if entering Barcode or Focus mode (before object selected)
          if (_cameraController != null || _isMainCameraInitializing) {
             debugPrint("[Navigation] Switching TO barcode/initial focus - disposing main camera..."); // Updated log
             await _disposeMainCameraController();
          } else {
             debugPrint("[Navigation] Switching TO barcode/initial focus - main camera already null or not initializing."); // Added log
          }
      } else if (isSwitchingFromBarcode || isSwitchingFromFocus) {
          // Initialize camera if leaving Barcode or Focus mode *and* the new page requires it
          // (Focus mode requires camera *after* object selection, other pages might too)
          bool newPageRequiresCamera = newFeature.id != barcodeScannerFeature.id; // Assume all others might need it
          if (newPageRequiresCamera) {
             debugPrint("[Navigation] Switching FROM barcode/focus TO a page needing camera (${newFeature.id}) - initializing main camera..."); // Updated log
             await _initializeMainCameraController();
          } else {
              debugPrint("[Navigation] Switching FROM barcode/focus, but new page (${newFeature.id}) doesn't need camera immediately."); // Added log
          }
      } else {
          debugPrint("[Navigation] No major camera transition needed between ${previousFeature.id} and ${newFeature.id}. Ensuring timer state."); // Added log
          // Ensure timer is started/stopped correctly if switching between two camera-using pages
          _startDetectionTimerIfNeeded();
      }
      // --- --- --- --- --- --- ---

      // --- Clear Previous Page Results & Reset State ---
      if(mounted) {
        setState(() {
          _isProcessingImage = false; _lastRequestedFeatureId = null;
          // Clear results specific to the *previous* page type
          if (previousFeature.id == objectDetectionFeature.id) _lastObjectResult = "";
          else if (previousFeature.id == hazardDetectionFeature.id) { _hazardAlertClearTimer?.cancel(); _clearHazardAlert(); _lastHazardRawResult = ""; }
          else if (previousFeature.id == sceneDetectionFeature.id || previousFeature.id == textDetectionFeature.id) _lastSceneTextResult = "";
          // Reset focus state IF leaving focus mode
          if (isSwitchingFromFocus) {
             _focusedObject = null; _isFocusPromptActive = false; _isFocusObjectDetectedInFrame = false; _isFocusObjectCentered = false; _currentProximity = 0.0; _announcedFocusFound = false;
          }
        });
      } else { return; }
      // --- --- --- --- --- --- --- --- --- ---


      // --- Announce & Handle New Page ---
      if (_ttsInitialized) _ttsService.speak(newFeature.title); // Announce the new feature name

      if (_isFocusModeActive) {
         // --- Entering Focus Mode Specific Logic ---
         setState(() {
           _focusedObject = null; // Start with no object selected
           _isFocusPromptActive = true; // Show the prompt
           _isFocusObjectDetectedInFrame = false;
           _isFocusObjectCentered = false;
           _currentProximity = 0.0;
           _announcedFocusFound = false;
         });
         _stopFocusFeedback(); // Ensure feedback is off initially
         debugPrint("[Focus] Entered Focus Mode. Prompting for object."); // Added log
         // Prompt user and start listening
         if (_ttsInitialized) {
            // Modified prompt to include tap instruction
            await _ttsService.speak("Focus Mode. Tap the button, then say the object name."); // <<< MODIFIED PROMPT
         }
         // Removed automatic listening on entry - user must tap now
         // // Delay slightly after TTS finishes before listening
         // await Future.delayed(const Duration(milliseconds: 1500));
         // if (mounted && _isFocusModeActive) { // Check if still on focus page
         //    debugPrint("[Focus] Starting initial listening for object name."); // Added log
         //    _startListening(isForFocusObject: true);
         // }
       } else {
           // --- Entering Normal Page Specific Logic ---
          debugPrint("[Navigation] Entered normal page (${newFeature.id}). Starting timer if needed."); // Added log
          _startDetectionTimerIfNeeded(); // Start timer for object/hazard pages
       }
       // --- --- --- --- --- --- --- --- --- ---
    }






  // --- Widget Build Logic -----------------------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
     if (_features.isEmpty) return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text("No features.", style: TextStyle(color: Colors.white))));

     final currentFeature = _features[_currentPage.clamp(0, _features.length - 1)];
     final bool isBarcodePage = currentFeature.id == barcodeScannerFeature.id;
     // Determine if camera should be shown (not barcode, not focus mode before object selected)
     final bool shouldShowMainCamera = !isBarcodePage && !(_isFocusModeActive && _focusedObject == null);

     return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- Camera Display Area ---
          // Show camera only if conditions are met
          if (shouldShowMainCamera)
             _buildCameraDisplay() // Simplified call
          else // Show black placeholder for barcode or initial focus mode
             Container(key: ValueKey('placeholder_${currentFeature.id}'), color: Colors.black),

          // --- Page View for Features ---
          _buildFeaturePageView(),

          // --- Overlay Widgets ---
          FeatureTitleBanner( title: currentFeature.title, backgroundColor: currentFeature.color, ),
          _buildSettingsButton(),
          _buildMainActionButton(currentFeature), // Handles focus mode actions too
        ],
      ),
    );
  }

  // Updated camera display builder - no longer needs bool parameter
  Widget _buildCameraDisplay() {
      if (_isMainCameraInitializing) {
        return Container( key: const ValueKey('placeholder_initializing'), color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.white,)));
     } else if (_cameraController != null && _initializeControllerFuture != null) {
        return FutureBuilder<void>(
            key: _cameraViewKey, future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                 if (_cameraController != null && _cameraController!.value.isInitialized) {
                    return CameraViewWidget( cameraController: _cameraController, initializeControllerFuture: _initializeControllerFuture, );
                 } else { return _buildCameraErrorPlaceholder("Camera failed"); }
              } else { return Container( color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.white,)) ); }
            },
        );
     } else { return _buildCameraErrorPlaceholder("Camera unavailable"); }
  }

  Widget _buildCameraErrorPlaceholder(String message) {
      return Container( key: ValueKey('placeholder_error_$message'), color: Colors.black, child: Center(child: Text(message, style: const TextStyle(color: Colors.red))) );
  }

  Widget _buildFeaturePageView() {
      return PageView.builder(
            controller: _pageController,
            itemCount: _features.length,
            physics: const ClampingScrollPhysics(), // Prevent overscroll glow
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
               if (index >= _features.length) return Center(child: Text("Error: Invalid page index $index", style: const TextStyle(color: Colors.red)));

               final feature = _features[index];

               // Build page based on feature ID
               switch(feature.id) {
                  case 'barcode_scanner':
                     return BarcodeScannerPage(key: const ValueKey('barcodeScanner'), barcodeApiService: _barcodeApiService, ttsService: _ttsService);
                  case 'object_detection':
                     return ObjectDetectionPage(detectionResult: _lastObjectResult);
                  case 'hazard_detection':
                     return HazardDetectionPage(detectionResult: _currentDisplayedHazardName, isHazardAlert: _isHazardAlertActive);
                  case 'scene_detection':
                     return SceneDetectionPage(detectionResult: _lastSceneTextResult);
                  case 'text_detection':
                     return TextDetectionPage(detectionResult: _lastSceneTextResult);
                  case 'focus_mode':
                     return FocusModePage(
                        key: const ValueKey('focusMode'), // Add key
                        focusedObject: _focusedObject,
                        isObjectDetectedInFrame: _isFocusObjectDetectedInFrame, // Corrected variable name
                        isObjectCentered: _isFocusObjectCentered, // Corrected variable name
                        isPrompting: _isFocusPromptActive,
                     );
                  default:
                     return Center(child: Text('Unknown Page: ${feature.id}', style: const TextStyle(color: Colors.white)));
               }
            },
          );
  }

  Widget _buildSettingsButton() {
     // (Keep existing implementation)
     return Align( alignment: Alignment.topRight, child: SafeArea( child: Padding( padding: const EdgeInsets.only(top: 10.0, right: 15.0), child: IconButton( icon: const Icon(Icons.settings, color: Colors.white, size: 32.0, shadows: [Shadow(blurRadius: 6.0, color: Colors.black54, offset: Offset(1.0, 1.0))]), onPressed: _navigateToSettingsPage, tooltip: 'Settings', ), ), ), );
  }

  Widget _buildMainActionButton(FeatureConfig currentFeature) {
     final bool isRealtimePage = currentFeature.id == objectDetectionFeature.id || currentFeature.id == hazardDetectionFeature.id;
     final bool isBarcodePage = currentFeature.id == barcodeScannerFeature.id;
     final bool isFocusActive = currentFeature.id == focusModeFeature.id;

     // Determine tap action
     VoidCallback? onTapAction;
     if (!isRealtimePage && !isBarcodePage && !isFocusActive) {
        // --- Manual Trigger Tap Action (Scene/Text) ---
        onTapAction = () {
           debugPrint("[Action Button] Manual detection tap for ${currentFeature.id}"); // Added log
           _performManualDetection(currentFeature.id);
        };
      } else if (isFocusActive) {
         // --- Focus Mode Tap Action ---
         onTapAction = () {
            debugPrint("[Action Button] Focus mode tap - starting listening for object."); // Added log
            if (!_speechEnabled) { _showStatusMessage('Speech not available', isError: true); _initSpeech(); return; }
            if (_speechToText.isNotListening) {
               _startListening(isForFocusObject: true); // Tap starts listening for object name
            } else {
               _stopListening(); // If already listening, tap stops it
            }
         };
      }
      // Tap does nothing in realtime (object/hazard) or barcode modes

      // --- Long Press Action (Always General Navigation/Command) ---
      VoidCallback onLongPressAction = () {
         debugPrint("[Action Button] Long press detected - starting listening for general command."); // Added log
         if (!_speechEnabled) { _showStatusMessage('Speech not available', isError: true); _initSpeech(); return; }
         if (_speechToText.isNotListening) {
             // Long press ALWAYS listens for general commands, regardless of mode
             _startListening(isForFocusObject: false); // <<< CHANGED: Always false for long press
         } else {
             _stopListening();
         }
      };

     // Icon changes based on state
     IconData iconData = Icons.mic_none; // Default
     if (_isListening) iconData = Icons.mic;
     else if (isFocusActive) iconData = Icons.filter_center_focus; // Specific icon for focus
     else if (!isRealtimePage && !isBarcodePage) iconData = Icons.play_arrow; // Manual trigger pages
     else iconData = Icons.camera_alt; // Default for realtime pages when not listening

     return ActionButton(
            onTap: onTapAction,
            onLongPress: onLongPressAction,
            isListening: _isListening,
            color: currentFeature.color,
            iconOverride: iconData, // Pass the determined icon
          );
  }

} // End of _HomeScreenState