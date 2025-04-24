// lib/presentation/screens/home_screen.dart
import 'dart:async';
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

import '../../features/feature_registry.dart';
import '../../features/object_detection/presentation/pages/object_detection_page.dart';
import '../../features/hazard_detection/presentation/pages/hazard_detection_page.dart';
import '../../features/scene_detection/presentation/pages/scene_detection_page.dart';
import '../../features/text_detection/presentation/pages/text_detection_page.dart';
import '../../features/barcode_scanner/presentation/pages/barcode_scanner_page.dart';

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
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  bool _isMainCameraInitializing = false;
  Key _cameraViewKey = UniqueKey();

  final PageController _pageController = PageController();
  int _currentPage = 0;

  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;

  final WebSocketService _webSocketService = WebSocketService();
  late List<FeatureConfig> _features;
  final SettingsService _settingsService = SettingsService();
  final TtsService _ttsService = TtsService();
  final BarcodeApiService _barcodeApiService = BarcodeApiService();
  bool _ttsInitialized = false;

  String _selectedOcrLanguage = SettingsService.getValidatedDefaultLanguage();
  String _selectedObjectCategory = defaultObjectCategory;

  String _lastObjectResult = "";
  String _lastSceneTextResult = "";
  String _lastHazardRawResult = "";
  String _currentDisplayedHazardName = "";
  bool _isHazardAlertActive = false;

  Timer? _hazardAlertClearTimer;
  Timer? _detectionTimer;
  bool _isProcessingImage = false;
  String? _lastRequestedFeatureId;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _hasVibrator = false;











  // --- Constants ------------------------------------------------------------------------------------------
  static const String _alertSoundPath = "audio/alert.mp3";
  static const Duration _detectionInterval = Duration(seconds: 3);
  static const Duration _hazardAlertPersistence = Duration(seconds: 4);
  static const Set<String> _hazardObjectNames = {
    "car", "bicycle", "motorcycle", "bus", "train", "truck", "boat",
    "traffic light", "stop sign",
    "knife", "scissors", "fork",
    "oven", "toaster", "microwave",
    "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe"
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
    if (_speechToText.isListening) _speechToText.stop();
    _speechToText.cancel();
    if (_ttsInitialized) _ttsService.dispose();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    _webSocketService.close();
    debugPrint("[HomeScreen] Dispose complete.");
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
    debugPrint("[Lifecycle] State changed to: $state, Current Page: $currentFeatureId");

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
    await _checkVibrator();

    final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
    if (currentFeatureId != barcodeScannerFeature.id) {
      await _initializeMainCameraController();
    } else {
      debugPrint("[HomeScreen] Initializing on barcode page, skipping main camera init.");
    }
    await _initSpeech(); // Await speech init
    _initializeWebSocket();
  }

  void _initializeFeatures() {
     _features = availableFeatures;
     debugPrint("[HomeScreen] Features Initialized: ${_features.map((f) => f.id).toList()}");
  }

  Future<void> _loadAndInitializeSettings() async {
    final results = await Future.wait([
      _settingsService.getOcrLanguage(),
      _settingsService.getTtsVolume(),
      _settingsService.getTtsPitch(),
      _settingsService.getTtsRate(),
      _settingsService.getObjectDetectionCategory(),
    ]);

    _selectedOcrLanguage = results[0] as String;
    final ttsVolume = results[1] as double;
    final ttsPitch = results[2] as double;
    final ttsRate = results[3] as double;
    _selectedObjectCategory = results[4] as String;

    if (!_ttsInitialized) {
       await _ttsService.initTts(
         initialVolume: ttsVolume,
         initialPitch: ttsPitch,
         initialRate: ttsRate,
       );
       _ttsInitialized = true;
    } else {
       await _ttsService.updateSettings(ttsVolume, ttsPitch, ttsRate);
    }

    debugPrint("[HomeScreen] OCR language setting loaded: $_selectedOcrLanguage");
    debugPrint("[HomeScreen] TTS settings loaded V:$ttsVolume P:$ttsPitch R:$ttsRate");
    debugPrint("[HomeScreen] Object Category loaded: $_selectedObjectCategory");

    // No setState here, initial build will use loaded values
  }

  Future<void> _checkVibrator() async {
    try {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (mounted) {
        setState(() { _hasVibrator = hasVibrator ?? false; });
        debugPrint("[HomeScreen] Vibrator available: $_hasVibrator");
      }
    } catch (e) {
       debugPrint("[HomeScreen] Error checking for vibrator: $e");
        if (mounted) setState(() => _hasVibrator = false);
    }
  }











  // --- Lifecycle Event Handlers -----------------------------------------------------------------------------------
  void _handleAppPause() {
     debugPrint("[Lifecycle] App inactive/paused - Cleaning up...");
      _stopDetectionTimer();
      if(_ttsInitialized) _ttsService.stop();
      _audioPlayer.pause();
      _hazardAlertClearTimer?.cancel();

      final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
      if (currentFeatureId != barcodeScannerFeature.id) {
        _disposeMainCameraController();
      } else {
          debugPrint("[Lifecycle] App paused/inactive on barcode page, main camera should be disposed.");
      }
  }

  void _handleAppResume() {
     debugPrint("[Lifecycle] App resumed");
      final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;

      if (currentFeatureId != barcodeScannerFeature.id) {
         debugPrint("[Lifecycle] Resumed on non-barcode page. Ensuring main camera is initialized.");
         _initializeMainCameraController(); // Trigger init, don't await
      } else {
          debugPrint("[Lifecycle] App resumed on barcode page, main camera should remain off.");
      }

       if (!_webSocketService.isConnected) {
           debugPrint("[Lifecycle] Attempting WebSocket reconnect on resume...");
           _webSocketService.connect(); // Let service handle connection logic
       } else {
           // If already connected, ensure timer starts if appropriate
           _startDetectionTimerIfNeeded();
       }
  }











  // --- Camera Management -----------------------------------------------------------------------------------------
  Future<void> _disposeMainCameraController() async {
     if (_cameraController == null && _initializeControllerFuture == null && !_isMainCameraInitializing) {
        debugPrint("[HomeScreen] Dispose called but main camera controller is already null/uninitialized.");
        return;
     }
     debugPrint("[HomeScreen] Attempting to dispose main camera controller...");
     _stopDetectionTimer();

     final controllerToDispose = _cameraController;
     final initFuture = _initializeControllerFuture;

     _cameraController = null;
     _initializeControllerFuture = null;
     _isMainCameraInitializing = false;
     _cameraViewKey = UniqueKey();

     if(mounted) {
        setState((){});
     }

     try {
       if (initFuture != null) {
           await initFuture.timeout(const Duration(milliseconds: 200), onTimeout: () {
                debugPrint("[HomeScreen] Timeout waiting for previous init future during dispose.");
           }).catchError((_){ /* Ignore errors */ });
       }
        if (controllerToDispose != null) {
         debugPrint("[HomeScreen] Awaiting controller dispose...");
         await controllerToDispose.dispose();
         debugPrint("[HomeScreen] Main camera controller disposed successfully.");
       } else {
         debugPrint("[HomeScreen] Controller was null before dispose could be called.");
       }
     } catch (e, s) {
       debugPrint("[HomeScreen] Error during main camera controller disposal: $e \n$s");
     } finally {
        await Future.delayed(const Duration(milliseconds: 150));
         if (mounted && _cameraController == null) {
             debugPrint("[HomeScreen] Final state check after dispose: Controller is null.");
         } else if (mounted) {
              debugPrint("[HomeScreen] Warning: Controller was not null after dispose completed.");
         }
     }
  }

  Future<void> _initializeMainCameraController() async {
     final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
     if (widget.camera == null || currentFeatureId == barcodeScannerFeature.id || _cameraController != null || _isMainCameraInitializing) {
        debugPrint("[HomeScreen] Skipping main camera initialization. "
                   "Reason: No camera (${widget.camera == null}), "
                   "Barcode Page ($currentFeatureId == ${barcodeScannerFeature.id}), "
                   "Already exists (${_cameraController != null}), "
                   "Already Initializing (${_isMainCameraInitializing})");
       return;
     }
     if (!mounted) return;

     debugPrint("[HomeScreen] Initializing main CameraController...");
     _isMainCameraInitializing = true;
     _cameraController = null;
     _initializeControllerFuture = null;
     _cameraViewKey = UniqueKey();
     if (mounted) setState((){});

     await Future.delayed(const Duration(milliseconds: 250));
     if(!mounted || currentFeatureId == barcodeScannerFeature.id) {
        _isMainCameraInitializing = false;
        if(mounted) setState((){});
        debugPrint("[HomeScreen] Aborting init due to unmount or page change during delay.");
        return;
     }

     CameraController newController;
     try {
        newController = CameraController(widget.camera!, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
     } catch(e) {
        debugPrint("[HomeScreen] Error creating CameraController: $e");
         if (mounted) {
             _showStatusMessage("Failed to create camera controller", isError: true);
             _isMainCameraInitializing = false;
             setState((){});
         }
         return;
     }

     Future<void> initFuture;
     try {
        _cameraController = newController;
        initFuture = newController.initialize();
        _initializeControllerFuture = initFuture;
        if(mounted) setState((){});
     } catch (e) {
         debugPrint("[HomeScreen] Error assigning initialize future: $e");
          if (mounted) {
             _showStatusMessage("Failed to initialize camera", isError: true);
             _cameraController = null;
             _initializeControllerFuture = null;
             _isMainCameraInitializing = false;
             setState((){});
         }
         return;
     }

     try {
       await initFuture;
       if (!mounted) {
           debugPrint("[HomeScreen] Widget unmounted during camera initialization, disposing new controller.");
           try { await newController.dispose(); } catch (_) {}
           return;
       }
       if (_cameraController == newController) {
          debugPrint("[HomeScreen] Main Camera initialized successfully.");
           _isMainCameraInitializing = false;
           _startDetectionTimerIfNeeded();
       } else {
           debugPrint("[HomeScreen] Camera controller changed during initialization, disposing new controller.");
           try { await newController.dispose(); } catch (_) {}
           _isMainCameraInitializing = false;
       }
     } catch (error,s) {
       debugPrint("[HomeScreen] Main Camera initialization error: $error\n$s");
       if (!mounted) {
           _isMainCameraInitializing = false;
           return;
       }
       final bool shouldReset = _cameraController == newController;
        if(shouldReset) {
             _showStatusMessage("Camera init failed: ${error is CameraException ? error.description : error}", isError: true);
             _cameraController = null;
             _initializeControllerFuture = null;
        } else {
           debugPrint("[HomeScreen] Controller changed after initialization error. Disposing new controller.");
            try { await newController.dispose(); } catch (_) {}
        }
       _isMainCameraInitializing = false;
     } finally {
       if(mounted){
           setState(() {});
       }
     }
  }











  // --- WebSocket Handling -----------------------------------------------------------------------------
  void _initializeWebSocket() {
     debugPrint("[HomeScreen] Initializing WebSocket listener...");
     _webSocketService.responseStream.listen(
      _handleWebSocketData,
      onError: _handleWebSocketError,
      onDone: _handleWebSocketDone,
      cancelOnError: false
    );
    _webSocketService.connect();
  }

  void _handleWebSocketData(Map<String, dynamic> data) {
    if (!mounted) return;

    if (data.containsKey('event') && data['event'] == 'connect') {
         _showStatusMessage("Connected", durationSeconds: 2);
         _startDetectionTimerIfNeeded();
         return;
    }

    if (data.containsKey('result')) {
       final resultTextRaw = data['result'] as String? ?? "No result";
       final String rawDetectionsForHazards = resultTextRaw;
       final String? receivedForFeatureId = _lastRequestedFeatureId; // Use before clearing

       if (receivedForFeatureId == null) {
           debugPrint('[HomeScreen] Received result, but _lastRequestedFeatureId is null. Ignoring.');
           return;
       }

       _lastRequestedFeatureId = null; // Clear ID after using it

       debugPrint('[HomeScreen] Received result for "$receivedForFeatureId": "$resultTextRaw"');

       // Process based on the feature that requested it
       _processFeatureResult(receivedForFeatureId, resultTextRaw, rawDetectionsForHazards);

    } else {
        debugPrint('[HomeScreen] Received non-result/event data: $data');
    }
  }

  void _processFeatureResult(String featureId, String resultTextRaw, String rawDetectionsForHazards){
       setState(() {
           bool speakResult = false;
           String textToSpeak = "";
           String displayResult = "";

           // Hazard Check (Always uses raw data if applicable)
           if (
            // featureId == objectDetectionFeature.id ||
            featureId == hazardDetectionFeature.id) {
               _processHazardDetection(rawDetectionsForHazards);
           }

           // Update specific feature state
           if (featureId == objectDetectionFeature.id) {
               final odResult = _processObjectDetection(rawDetectionsForHazards);
               displayResult = odResult['display'];
               speakResult = odResult['speak'];
               textToSpeak = odResult['speakText'];
               _lastObjectResult = displayResult;
           } else if (featureId == hazardDetectionFeature.id) {
               // Display handled by hazard state
           } else if (featureId == sceneDetectionFeature.id) {
               final sceneResult = _processSceneDetection(resultTextRaw);
               displayResult = sceneResult['display'];
               speakResult = sceneResult['speak'];
               textToSpeak = sceneResult['speakText'];
               _lastSceneTextResult = displayResult;
           } else if (featureId == textDetectionFeature.id) {
               final textResult = _processTextDetection(resultTextRaw);
               displayResult = textResult['display'];
               speakResult = textResult['speak'];
               textToSpeak = textResult['speakText'];
               _lastSceneTextResult = displayResult;
           } else {
               debugPrint("[HomeScreen] Received result for UNKNOWN feature ID: $featureId.");
           }

           // Speak result if needed (excluding hazards)
           if (speakResult && _ttsInitialized && featureId != hazardDetectionFeature.id) {
               _ttsService.speak(textToSpeak);
           }
       });
  }

  void _processHazardDetection(String rawDetections){
        _lastHazardRawResult = rawDetections;
        String specificHazardFound = "";
        bool hazardFoundInFrame = false;

        if (rawDetections.isNotEmpty && rawDetections != "No objects detected" && !rawDetections.startsWith("Error")) {
            List<String> detectedObjects = rawDetections.toLowerCase().split(',').map((e) => e.trim()).toList();
            for (String obj in detectedObjects) {
                if (_hazardObjectNames.contains(obj)) {
                    hazardFoundInFrame = true;
                    specificHazardFound = obj;
                    break;
                }
            }
        }
        if (hazardFoundInFrame) {
            _triggerHazardAlert(specificHazardFound);
        }
  }

 Map<String, dynamic> _processObjectDetection(String rawDetections) {
        String displayResult;
        bool speakResult = false;
        String textToSpeak = "";

        if (rawDetections.isNotEmpty && rawDetections != "No objects detected" && !rawDetections.startsWith("Error")) {
            List<String> allDetected = rawDetections.split(',').map((e) => e.trim()).toList();
            List<String> filteredObjects = [];

            if (_selectedObjectCategory == 'all') {
                filteredObjects = allDetected;
            } else {
                for (String obj in allDetected) {
                    String lowerObj = obj.toLowerCase();
                    if (cocoObjectToCategoryMap[lowerObj] == _selectedObjectCategory) {
                        filteredObjects.add(obj);
                    }
                }
            }

            if (filteredObjects.isNotEmpty) {
                displayResult = filteredObjects.join(', ');
                speakResult = true;
                textToSpeak = displayResult;
            } else {
                displayResult = "No objects found in category: ${objectDetectionCategories[_selectedObjectCategory] ?? _selectedObjectCategory}";
                speakResult = false;
            }
        } else {
            displayResult = rawDetections;
            speakResult = false;
        }
        return {'display': displayResult, 'speak': speakResult, 'speakText': textToSpeak};
 }

 Map<String, dynamic> _processSceneDetection(String resultTextRaw) {
      String displayResult = resultTextRaw.replaceAll('_', ' ');
      bool speakResult = displayResult.isNotEmpty && !displayResult.startsWith("Error");
      String textToSpeak = speakResult ? "Scene: $displayResult" : "";
      return {'display': displayResult, 'speak': speakResult, 'speakText': textToSpeak};
 }

 Map<String, dynamic> _processTextDetection(String resultTextRaw) {
      String displayResult = resultTextRaw;
      bool speakResult = displayResult.isNotEmpty && displayResult != "No text detected" && !displayResult.startsWith("Error");
      String textToSpeak = speakResult ? "Text detected: $displayResult" : "";
      return {'display': displayResult, 'speak': speakResult, 'speakText': textToSpeak};
 }


  void _handleWebSocketError(error) {
    if (!mounted) return;
    debugPrint('[HomeScreen] WebSocket Error: $error');
    _stopDetectionTimer();
    _hazardAlertClearTimer?.cancel();
    if(_ttsInitialized) _ttsService.stop();
    setState(() {
      _lastObjectResult = ""; _lastSceneTextResult = "Connection Error";
      _lastHazardRawResult = ""; _isHazardAlertActive = false; _currentDisplayedHazardName = "";
    });
    _showStatusMessage("Connection Error: ${error.toString()}", isError: true);
  }

  void _handleWebSocketDone() {
    if (!mounted) return;
    debugPrint('[HomeScreen] WebSocket connection closed.');
    _stopDetectionTimer();
    _hazardAlertClearTimer?.cancel();
    if(_ttsInitialized) _ttsService.stop();
    if (mounted) {
       setState(() {
         _lastObjectResult = ""; _lastSceneTextResult = "Disconnected";
         _lastHazardRawResult = ""; _isHazardAlertActive = false; _currentDisplayedHazardName = "";
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
     } catch (e) {
        debugPrint('Error initializing speech: $e');
        if (mounted) _showStatusMessage('Speech init failed', durationSeconds: 3);
     }
     // No setState needed here as it's called in the main init sequence
  }

   void _handleSpeechStatus(String status) {
     debugPrint('Speech status: $status'); if (!mounted) return;
     final bool isCurrentlyListening = status == SpeechToText.listeningStatus;
     if (_isListening != isCurrentlyListening) setState(() => _isListening = isCurrentlyListening);
   }

   void _handleSpeechError(SpeechRecognitionError error) {
     debugPrint('Speech error: ${error.errorMsg} (Permanent: ${error.permanent})'); if (!mounted) return;
     if (_isListening) setState(() => _isListening = false);
     String errorMessage = 'Speech error: ${error.errorMsg}';
     if (error.errorMsg.contains('permission') || error.errorMsg.contains('denied') || error.permanent) {
       errorMessage = 'Microphone permission needed.'; _showPermissionInstructions();
     } else if (error.errorMsg.contains('No speech')) errorMessage = 'No speech detected.';
      _showStatusMessage(errorMessage, isError: true, durationSeconds: 4);
   }

   void _startListening() async {
     if (!_speechEnabled) { _showStatusMessage('Speech not available', isError: true); _initSpeech(); return; }
     bool hasPermission = await _speechToText.hasPermission;
     if (!hasPermission && mounted) { _showPermissionInstructions(); _showStatusMessage('Microphone permission needed', isError: true); return; }
     if (!mounted) return; if (_speechToText.isListening) await _stopListening();
     debugPrint("Starting speech listener...");
     if(_ttsInitialized) _ttsService.stop();
     try {
        await _speechToText.listen(
           onResult: _handleSpeechResult, listenFor: const Duration(seconds: 7),
           pauseFor: const Duration(seconds: 3), partialResults: false,
           cancelOnError: true, listenMode: ListenMode.confirmation );
         if (mounted) setState(() {}); // Update UI to show listening state
     } catch (e) {
        debugPrint("Error starting speech listener: $e");
        if (mounted) { _showStatusMessage("Could not start listening", isError: true); setState(() => _isListening = false); }
     }
   }

   Future<void> _stopListening() async {
      if (_speechToText.isListening) {
         debugPrint("Stopping speech listener..."); await _speechToText.stop(); if (mounted) setState(() {});
      }
   }

   void _handleSpeechResult(SpeechRecognitionResult result) {
     if (mounted && result.finalResult && result.recognizedWords.isNotEmpty) {
         String command = result.recognizedWords.toLowerCase().trim();
         debugPrint('Final recognized command: "$command"');
         _processSpeechCommand(command);
     }
   }

   void _processSpeechCommand(String command) {
       if (command == 'settings' || command == 'setting') { _navigateToSettingsPage(); return; }
       int targetPageIndex = -1;
       for (int i = 0; i < _features.length; i++) {
         for (String keyword in _features[i].voiceCommandKeywords) {
           if (command.contains(keyword)) {
             targetPageIndex = i;
             debugPrint('Matched "$command" to "${_features[i].title}" ($i)');
             break;
           }
         }
         if (targetPageIndex != -1) break;
       }
       if (targetPageIndex != -1) {
           _navigateToPage(targetPageIndex);
       } else {
           _showStatusMessage('Command "$command" not recognized.', durationSeconds: 3);
       }
   }











  // --- Detection Logic -------------------------------------------------------------------------------------------
  void _startDetectionTimerIfNeeded() {
    if (!mounted || _features.isEmpty) return;
    final currentFeatureId = _features[_currentPage.clamp(0, _features.length - 1)].id;
    final isRealtimePage = (currentFeatureId == objectDetectionFeature.id || currentFeatureId == hazardDetectionFeature.id);

    if (isRealtimePage && _detectionTimer == null && _cameraController != null && (_cameraController?.value.isInitialized ?? false) && !_isMainCameraInitializing && _webSocketService.isConnected) {
        debugPrint("[HomeScreen] Starting detection timer for page: $currentFeatureId");
        _detectionTimer = Timer.periodic(_detectionInterval, (_) { _performPeriodicDetection(); });
    } else {
        if (isRealtimePage) {
          debugPrint("[HomeScreen] Not starting detection timer. Conditions not met: "
                     "Timer exists (${_detectionTimer != null}), "
                     "Controller null (${_cameraController == null}), "
                     "Controller uninitialized (${!(_cameraController?.value.isInitialized ?? false)}), "
                     "Controller initializing (${_isMainCameraInitializing}), "
                     "WS disconnected (${!_webSocketService.isConnected})");
        }
        // Ensure timer is stopped if conditions aren't met for realtime page
        if (_detectionTimer != null && !isRealtimePage) {
             _stopDetectionTimer();
        }
    }
  }


  void _stopDetectionTimer() {
    if (_detectionTimer?.isActive ?? false) {
        debugPrint("[HomeScreen] Stopping detection timer...");
        _detectionTimer!.cancel(); _detectionTimer = null;
        _isProcessingImage = false;
    }
  }


   void _performPeriodicDetection() async {
     final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
     if (!mounted || _features.isEmpty || currentFeatureId == barcodeScannerFeature.id || _cameraController == null || !_cameraController!.value.isInitialized || _isMainCameraInitializing || _isProcessingImage) {
        return;
     }

     if (currentFeatureId != objectDetectionFeature.id && currentFeatureId != hazardDetectionFeature.id) {
         _stopDetectionTimer(); return;
     }
     if (!_cameraControllerCheck(showError: false) || !_webSocketService.isConnected) return;

     try {
       _isProcessingImage = true;
       _lastRequestedFeatureId = currentFeatureId;

       final XFile imageFile = await _cameraController!.takePicture();
       _webSocketService.sendImageForProcessing(imageFile, objectDetectionFeature.id); // Always send as object_detection type

     } catch (e, stackTrace) {
       _handleCaptureError(e, stackTrace, currentFeatureId);
       _lastRequestedFeatureId = null; // Reset on error
     } finally {
        // Short delay before allowing next capture
        await Future.delayed(const Duration(milliseconds: 50));
        if(mounted) {
           _isProcessingImage = false; // Reset flag
        }
     }
   }

   void _performManualDetection(String featureId) async {
     if (featureId == objectDetectionFeature.id || featureId == hazardDetectionFeature.id || featureId == barcodeScannerFeature.id) return;
     debugPrint('Manual detection triggered for feature: $featureId');
     if (!_cameraControllerCheck(showError: true)) {
        debugPrint('Manual detection aborted: Camera check failed.');
        return;
     }
     if (_isProcessingImage || !_webSocketService.isConnected) {
         debugPrint('Manual detection aborted: Processing or WS disconnected.');
         return;
     }

     try {
       _isProcessingImage = true; _lastRequestedFeatureId = featureId;
       if(_ttsInitialized) _ttsService.stop();
       _showStatusMessage("Capturing...", durationSeconds: 1);
       final XFile imageFile = await _cameraController!.takePicture();
       _showStatusMessage("Processing...", durationSeconds: 2);
       _webSocketService.sendImageForProcessing( imageFile, featureId,
           languageCode: (featureId == textDetectionFeature.id) ? _selectedOcrLanguage : null, );
     } catch (e, stackTrace) {
       _handleCaptureError(e, stackTrace, featureId);
       _lastRequestedFeatureId = null; // Reset on error
     } finally {
        if (mounted) setState(() => _isProcessingImage = false); // Reset flag
     }
   }


   bool _cameraControllerCheck({required bool showError}) {
      final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
      if(currentFeatureId == barcodeScannerFeature.id) return false;

      bool isReady = _cameraController != null &&
                     _cameraController!.value.isInitialized &&
                     !_isMainCameraInitializing;

      if (!isReady) {
        debugPrint('Main camera check failed (Null: ${_cameraController == null}, Uninit: ${!(_cameraController?.value.isInitialized ?? true)}, Initializing: $_isMainCameraInitializing).');
        if (!_isMainCameraInitializing && showError) {
             _showStatusMessage("Camera not ready", isError: true);
        }
        if (_cameraController == null && widget.camera != null && !_isMainCameraInitializing && showError) {
            debugPrint("Triggering re-initialization from _cameraControllerCheck (Manual Trigger)");
            _initializeMainCameraController(); // Trigger init
        }
        return false;
      }

      if (_cameraController!.value.isTakingPicture) {
          debugPrint('Camera busy taking picture.'); return false;
      }
      return true;
   }


  void _handleCaptureError(Object e, StackTrace stackTrace, String? featureId) {
     final idForLog = featureId ?? "unknown_feature";
     debugPrint('Capture/Send Error for $idForLog: $e'); debugPrintStack(stackTrace: stackTrace);
     String errorMsg = e is CameraException ? "Capture Error: ${e.description ?? e.code}" : "Processing Error";
     if (mounted) {
       if(_ttsInitialized) _ttsService.stop();
       setState(() {
         if (featureId == objectDetectionFeature.id) { _lastObjectResult = "Error"; }
         else if (featureId == hazardDetectionFeature.id) { _lastHazardRawResult = ""; _clearHazardAlert(); _hazardAlertClearTimer?.cancel(); }
         else if (featureId != null && featureId != barcodeScannerFeature.id) { _lastSceneTextResult = "Error"; }
       });
       _showStatusMessage(errorMsg, isError: true, durationSeconds: 4);
     }
   }











  // --- Alerting -------------------------------------------------------------------------------------------
  void _triggerHazardAlert(String hazardName) {
    debugPrint("[ALERT] Triggering for: $hazardName");
    bool wasAlreadyActive = _isHazardAlertActive;

    if (mounted) {
      setState(() {
        _isHazardAlertActive = true;
        _currentDisplayedHazardName = hazardName;
      });
    }

    _playAlertSound();
    _triggerVibration();

    if (!wasAlreadyActive && _ttsInitialized) {
      _ttsService.speak("Hazard detected: ${hazardName.replaceAll('_', ' ')}");
    }

    _hazardAlertClearTimer?.cancel();
    _hazardAlertClearTimer = Timer(_hazardAlertPersistence, _clearHazardAlert);
  }

   void _clearHazardAlert() {
      if (mounted && _isHazardAlertActive) {
        setState(() {
          _isHazardAlertActive = false;
          _currentDisplayedHazardName = "";
        });
        debugPrint("[ALERT] Hazard alert display cleared by timer.");
      }
      _hazardAlertClearTimer = null;
   }

  Future<void> _playAlertSound() async {
    try {
       await _audioPlayer.play(AssetSource(_alertSoundPath), volume: 1.0);
       debugPrint("[ALERT] Playing alert sound.");
    } catch (e) {
       debugPrint("[ALERT] Error playing sound: $e");
    }
  }

  Future<void> _triggerVibration() async {
    if (_hasVibrator) {
      try {
        Vibration.vibrate(duration: 500, amplitude: 255);
        debugPrint("[ALERT] Triggering vibration.");
      } catch (e) {
         debugPrint("[ALERT] Error triggering vibration: $e");
      }
    }
  }











  // --- Navigation & UI Helpers -----------------------------------------------------------------------------------------
  void _showStatusMessage(String message, {bool isError = false, int durationSeconds = 3}) {
    if (!mounted) return;
    debugPrint("[Status] $message ${isError ? '(Error)' : ''}");
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar( SnackBar(
        content: Text(message), backgroundColor: isError ? Colors.redAccent : Colors.grey[800],
        duration: Duration(seconds: durationSeconds), behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 90.0, left: 15.0, right: 15.0),
        shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(10.0), ), ), );
  }

   void _navigateToPage(int pageIndex) {
      if (!mounted || _features.isEmpty) return;
      final targetIndex = pageIndex.clamp(0, _features.length - 1);
      if (targetIndex != _currentPage && _pageController.hasClients) {
         if(_ttsInitialized) _ttsService.stop();
         debugPrint("Navigating to page index: $targetIndex (${_features[targetIndex].title})");
         _pageController.animateToPage( targetIndex, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut, );
      }
   }

   Future<void> _navigateToSettingsPage() async {
     if (!mounted) return;
     debugPrint("Navigating to Settings page...");
     if (_speechToText.isListening) await _stopListening();
     if(_ttsInitialized) _ttsService.stop();
     _stopDetectionTimer();

     final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
     bool isMainCameraPage = currentFeatureId != barcodeScannerFeature.id;

     if (isMainCameraPage) {
        await _disposeMainCameraController();
        debugPrint("Disposed main camera before settings.");
     }

     await Navigator.push( context, MaterialPageRoute(builder: (context) => const SettingsScreen()), );
     if (!mounted) return;
     debugPrint("Returned from Settings page.");
     await _loadAndInitializeSettings(); // Reload settings after returning

      if (isMainCameraPage) {
         debugPrint("Attempting to reinitialize main camera after settings.");
         await _initializeMainCameraController(); // Re-init camera if needed
      }

     _startDetectionTimerIfNeeded(); // Restart timer if applicable
   }

   void _showPermissionInstructions() {
    if (!mounted) return;
     showDialog( context: context, builder: (BuildContext dialogContext) => AlertDialog(
           title: const Text('Microphone Permission'),
           content: const Text( 'Voice control requires microphone access.\n\nPlease enable the Microphone permission for this app in Settings.', ),
           actions: <Widget>[ TextButton( child: const Text('OK'), onPressed: () => Navigator.of(dialogContext).pop(), ), ],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)), ), );
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
      debugPrint("Page changed from ${previousFeature.title} to ${newFeature.title}");


      if(_ttsInitialized) _ttsService.stop(); // Stop any ongoing speech
      _stopDetectionTimer();

      bool isSwitchingFromBarcode = previousFeature.id == barcodeScannerFeature.id;
      bool isSwitchingToBarcode = newFeature.id == barcodeScannerFeature.id;

      // Update page index state FIRST
      if(mounted) {
         setState(() { _currentPage = newPageIndex; });
      } else { return; }


       // Handle Camera Transitions
       if (isSwitchingToBarcode) {
           debugPrint("Switching TO barcode page - disposing main camera...");
           await _disposeMainCameraController();
           debugPrint("Main camera disposed (awaited).");
       } else if (isSwitchingFromBarcode) {
           debugPrint("Switching FROM barcode page - initializing main camera...");
           await _initializeMainCameraController(); // Await completion
           setState((){});
           _buildCameraDisplay(false); // This might be redundant, state will update
           debugPrint("Main camera initialization attempt completed in onPageChanged.");
           // Force final UI update after init completes when coming from barcode
           if(mounted) setState((){});
       }


      // Clear previous page results AFTER camera ops (if any) are done
      if(mounted) {
        setState(() {
          _isProcessingImage = false; _lastRequestedFeatureId = null;
          if (previousFeature.id == objectDetectionFeature.id) { _lastObjectResult = ""; }
          else if (previousFeature.id == hazardDetectionFeature.id) { _hazardAlertClearTimer?.cancel(); _clearHazardAlert(); _lastHazardRawResult = ""; }
          else if (previousFeature.id != barcodeScannerFeature.id) { _lastSceneTextResult = ""; }
        });
      } else { return; }

      // Announce the new feature name
      if (_ttsInitialized) {
        _ttsService.speak(newFeature.title); // <<<--- ADDED TTS CALL
        debugPrint("TTS announced feature: ${newFeature.title}");
      }

      // Start timer for the NEW page if applicable
      final bool isNowRealtime = newFeature.id == objectDetectionFeature.id || newFeature.id == hazardDetectionFeature.id;
      if (isNowRealtime) {
          _startDetectionTimerIfNeeded();
      }
   }











  // --- Widget Build Logic -----------------------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
     if (_features.isEmpty) {
        return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: Text("No features configured.", style: TextStyle(color: Colors.white)))
        );
     }
     final currentFeature = _features[_currentPage.clamp(0, _features.length - 1)];
     final bool isBarcodePage = currentFeature.id == barcodeScannerFeature.id;

     return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Display Area
          _buildCameraDisplay(isBarcodePage),

          // Page View for Features
          _buildFeaturePageView(),

          // Overlay Widgets
          FeatureTitleBanner( title: currentFeature.title, backgroundColor: currentFeature.color, ),
          _buildSettingsButton(),
          _buildMainActionButton(currentFeature),
        ],
      ),
    );
  }

  Widget _buildCameraDisplay(bool isBarcodePage) {
     if (isBarcodePage) {
       return Container(key: const ValueKey('barcode_placeholder'), color: Colors.black);
     } else if (_isMainCameraInitializing) {
        return Container( // Show loading indicator while initializing
            key: const ValueKey('placeholder_initializing'),
            color: Colors.black,
            child: const Center(child: CircularProgressIndicator(color: Colors.white,)));
     } else if (_cameraController != null && _initializeControllerFuture != null) {
        // Use FutureBuilder for camera view
        return FutureBuilder<void>(
            key: _cameraViewKey, // Use key to ensure FutureBuilder rebuilds
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                 if (_cameraController != null && _cameraController!.value.isInitialized) {
                    return CameraViewWidget(
                      cameraController: _cameraController,
                      initializeControllerFuture: _initializeControllerFuture,
                    );
                 } else {
                     return _buildCameraErrorPlaceholder();
                 }
              } else {
                 // Still waiting for future or future is null
                 return Container(
                      color: Colors.black,
                      child: const Center(child: CircularProgressIndicator(color: Colors.white,))
                      );
              }
            },
        );
     } else {
        // Fallback / Error state
        return _buildCameraErrorPlaceholder();
     }
  }

  Widget _buildCameraErrorPlaceholder() {
      return Container(
             key: const ValueKey('placeholder_error'),
             color: Colors.black,
             child: const Center(child: Text("Camera unavailable", style: TextStyle(color: Colors.red)))
             );
  }


  Widget _buildFeaturePageView() {
      return PageView.builder(
            controller: _pageController,
            itemCount: _features.length,
            physics: const ClampingScrollPhysics(),
            onPageChanged: _onPageChanged, // Call the extracted handler
            itemBuilder: (context, index) {
               if (index >= _features.length) return const Center(child: Text("Error: Invalid page index", style: TextStyle(color: Colors.red)));
               final feature = _features[index];

               // Build page based on feature ID
               if (feature.id == barcodeScannerFeature.id) {
                   return BarcodeScannerPage(
                      key: const ValueKey('barcodeScanner'),
                      barcodeApiService: _barcodeApiService,
                      ttsService: _ttsService,
                   );
               } else if (feature.id == objectDetectionFeature.id) {
                  return ObjectDetectionPage(detectionResult: _lastObjectResult);
               } else if (feature.id == hazardDetectionFeature.id) {
                  return HazardDetectionPage(
                      detectionResult: _currentDisplayedHazardName,
                      isHazardAlert: _isHazardAlertActive
                  );
               } else if (feature.id == sceneDetectionFeature.id) {
                  return SceneDetectionPage(detectionResult: _lastSceneTextResult);
               } else if (feature.id == textDetectionFeature.id) {
                  return TextDetectionPage(detectionResult: _lastSceneTextResult);
               }
               else {
                  return Center(child: Text('Unknown Page: ${feature.id}', style: const TextStyle(color: Colors.white)));
               }
            },
          );
  }

  Widget _buildSettingsButton() {
     return Align(
           alignment: Alignment.topRight,
           child: SafeArea(
             child: Padding(
               padding: const EdgeInsets.only(top: 10.0, right: 15.0),
               child: IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white, size: 32.0, shadows: [Shadow(blurRadius: 6.0, color: Colors.black54, offset: Offset(1.0, 1.0))]),
                  onPressed: _navigateToSettingsPage,
                  tooltip: 'Settings',
                ),
             ),
           ),
         );
  }

  Widget _buildMainActionButton(FeatureConfig currentFeature) {
     final bool isRealtimePage = currentFeature.id == objectDetectionFeature.id || currentFeature.id == hazardDetectionFeature.id;
     final bool isBarcodePage = currentFeature.id == barcodeScannerFeature.id;

     return ActionButton(
            onTap: (isRealtimePage || isBarcodePage) ? null : () => _performManualDetection(currentFeature.id),
            onLongPress: () {
               if (!_speechEnabled) { _showStatusMessage('Speech not available', isError: true); _initSpeech(); return; }
               if (_speechToText.isNotListening) _startListening(); else _stopListening();
            },
            isListening: _isListening,
            color: currentFeature.color,
          );
  }

} // End of _HomeScreenState