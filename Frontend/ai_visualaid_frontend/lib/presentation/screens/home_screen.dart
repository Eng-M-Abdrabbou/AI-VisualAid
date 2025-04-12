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
import '../../core/services/settings_service.dart'; // Import settings service
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

class HomeScreen extends StatefulWidget {
  final CameraDescription? camera;

  const HomeScreen({Key? key, required this.camera}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
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
  String _selectedObjectCategory = defaultObjectCategory; // New state variable

  String _lastObjectResult = ""; // This will now hold the FILTERED result
  String _lastSceneTextResult = "";


  String _lastHazardRawResult = "";
  String _currentDisplayedHazardName = "";
  bool _isHazardAlertActive = false;
  Timer? _hazardAlertClearTimer;

  Timer? _detectionTimer;
  final Duration _detectionInterval = const Duration(seconds: 1);

  final Duration _hazardAlertPersistence = const Duration(seconds: 4);
  bool _isProcessingImage = false;
  String? _lastRequestedFeatureId;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _hasVibrator = false;
  static const String _alertSoundPath = "audio/alert.mp3";

  static const Set<String> _hazardObjectNames = {
    "car", "bicycle", "motorcycle", "bus", "train", "truck", "boat",
    "traffic light", "stop sign",
    "knife", "scissors", "fork",
    "oven", "toaster", "microwave",
    "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe"
  };


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFeatures();
    _initializeServices(); // Calls _loadAndInitializeSettings
    _checkVibrator();
    debugPrint("[HomeScreen] initState Completed");
  }

  void _initializeFeatures() {
     _features = availableFeatures;
     debugPrint("[HomeScreen] Features Initialized: ${_features.map((f) => f.id).toList()}");
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

  Future<void> _initializeServices() async {
    await _loadAndInitializeSettings(); // Load all settings including category
    final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
    if (currentFeatureId != barcodeScannerFeature.id) {
      await _initializeMainCameraController();
    } else {
      debugPrint("[HomeScreen] Initializing on barcode page, skipping main camera init.");
    }
    _initSpeech();
    _initializeWebSocket();
    debugPrint("[HomeScreen] Services Initialized");
  }

  Future<void> _loadAndInitializeSettings() async {
    // Load all settings together
    final results = await Future.wait([
      _settingsService.getOcrLanguage(),
      _settingsService.getTtsVolume(),
      _settingsService.getTtsPitch(),
      _settingsService.getTtsRate(),
      _settingsService.getObjectDetectionCategory(), // Load category
    ]);

    _selectedOcrLanguage = results[0] as String;
    final ttsVolume = results[1] as double;
    final ttsPitch = results[2] as double;
    final ttsRate = results[3] as double;
    _selectedObjectCategory = results[4] as String; // Store category

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

    if (mounted) setState(() {}); // Update UI after loading all settings
  }

  void _initSpeech() async {
     try {
       _speechEnabled = await _speechToText.initialize(
           onStatus: _handleSpeechStatus, onError: _handleSpeechError, debugLogging: kDebugMode);
       debugPrint('Speech recognition initialized: $_speechEnabled');
       if (!_speechEnabled && mounted) _showStatusMessage('Speech unavailable', durationSeconds: 3);
     } catch (e) {
        debugPrint('Error initializing speech: $e');
        if (mounted) _showStatusMessage('Speech init failed', durationSeconds: 3);
     }
    if (mounted) setState(() {});
  }


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
        // if(mounted) setState((){});

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
          //  _isMainCameraInitializing = false;
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


  void _initializeWebSocket() {
     debugPrint("[HomeScreen] Initializing WebSocket listener...");
     _webSocketService.responseStream.listen(
      (data) {
        if (!mounted) return;

        if (data.containsKey('event') && data['event'] == 'connect') {
             _showStatusMessage("Connected", durationSeconds: 2);
             _startDetectionTimerIfNeeded();
             return;
        }


        if (data.containsKey('result')) {
           final resultTextRaw = data['result'] as String? ?? "No result";
           // Hazard detection needs the raw (potentially unfiltered) list
           final String rawDetectionsForHazards = resultTextRaw;

           final String? receivedForFeatureId = _lastRequestedFeatureId;


           if (receivedForFeatureId == null) {
               debugPrint('[HomeScreen] Received result, but _lastRequestedFeatureId is null. Ignoring.');
               return;
           }

           debugPrint('[HomeScreen] Received result for "$receivedForFeatureId": "$resultTextRaw"');


           setState(() {
               _lastRequestedFeatureId = null;

               bool speakResult = false;
               String textToSpeak = "";
               String displayResult = ""; // For non-realtime or filtered OD

               // --- Hazard Detection Logic (Uses RAW results) ---
               // This logic needs to run regardless of the *current* page
               // if the request was for object detection.
               if (receivedForFeatureId == objectDetectionFeature.id || receivedForFeatureId == hazardDetectionFeature.id) {
                   _lastHazardRawResult = rawDetectionsForHazards; // Store raw
                   String specificHazardFound = "";
                   bool hazardFoundInFrame = false;

                   if (rawDetectionsForHazards.isNotEmpty && rawDetectionsForHazards != "No objects detected" && !rawDetectionsForHazards.startsWith("Error")) {
                       // Use lowercased raw results for hazard check
                       List<String> detectedObjects = rawDetectionsForHazards.toLowerCase().split(',').map((e) => e.trim()).toList();
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
                   // NO else needed here, alert clears automatically by timer
               }
               // --- End Hazard Detection Logic ---


               // --- Feature-Specific Display/TTS Logic ---
               if (receivedForFeatureId == objectDetectionFeature.id) {
                  // Filter based on settings
                   if (rawDetectionsForHazards.isNotEmpty && rawDetectionsForHazards != "No objects detected" && !rawDetectionsForHazards.startsWith("Error")) {
                       List<String> allDetected = rawDetectionsForHazards.split(',').map((e) => e.trim()).toList();
                       List<String> filteredObjects = [];

                       if (_selectedObjectCategory == 'all') {
                           filteredObjects = allDetected;
                       } else {
                           for (String obj in allDetected) {
                               String lowerObj = obj.toLowerCase();
                               if (cocoObjectToCategoryMap[lowerObj] == _selectedObjectCategory) {
                                   filteredObjects.add(obj); // Add original casing
                               }
                           }
                       }

                       if (filteredObjects.isNotEmpty) {
                            displayResult = filteredObjects.join(', ');
                            speakResult = true;
                            textToSpeak = displayResult;
                       } else {
                            displayResult = "No objects found in category: ${objectDetectionCategories[_selectedObjectCategory] ?? _selectedObjectCategory}";
                            speakResult = false; // Don't speak "nothing found" message
                       }

                   } else {
                       // Handle "No objects detected" or "Error" from backend
                       displayResult = rawDetectionsForHazards; // Show the original message
                       speakResult = false; // Don't speak error or "no objects"
                   }
                   _lastObjectResult = displayResult; // Update state with filtered result


               } else if (receivedForFeatureId == hazardDetectionFeature.id) {
                  // Hazard display is handled by _triggerHazardAlert and _clearHazardAlert
                  // No direct update to _lastObjectResult needed here
                  // We already processed hazards above using raw results
                   ; // No action needed for display state here

               } else if (receivedForFeatureId == sceneDetectionFeature.id) {
                    displayResult = resultTextRaw.replaceAll('_', ' '); // Use formatted for display/speech
                    _lastSceneTextResult = displayResult;
                     if (displayResult.isNotEmpty && !displayResult.startsWith("Error")) {
                        speakResult = true;
                        textToSpeak = "Scene: $displayResult";
                     }
               } else if (receivedForFeatureId == textDetectionFeature.id) {
                   displayResult = resultTextRaw; // Keep raw text for display/speech
                   _lastSceneTextResult = displayResult;
                    if (displayResult.isNotEmpty && displayResult != "No text detected" && !displayResult.startsWith("Error")) {
                        speakResult = true;
                        textToSpeak = "Text detected: $displayResult";
                     }
               } else {
                   debugPrint("[HomeScreen] Received result for UNKNOWN feature ID: $receivedForFeatureId.");
               }

               // Speak result only if applicable and not for hazards (hazards speak separately)
               if (speakResult && _ttsInitialized && receivedForFeatureId != hazardDetectionFeature.id) {
                   _ttsService.speak(textToSpeak);
               }
           });
        } else {
            debugPrint('[HomeScreen] Received non-result/event data: $data');
        }
      },
      onError: (error) {
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
      },
      onDone: () {
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
      },
      cancelOnError: false
    );
    _webSocketService.connect();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final currentFeatureId = _features.isNotEmpty ? _features[_currentPage.clamp(0, _features.length - 1)].id : null;
    debugPrint("[Lifecycle] State changed to: $state, Current Page: $currentFeatureId");

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      debugPrint("[Lifecycle] App inactive/paused - Cleaning up...");
      _stopDetectionTimer();
      if(_ttsInitialized) _ttsService.stop();
      _audioPlayer.pause();
      _hazardAlertClearTimer?.cancel();


      if (currentFeatureId != barcodeScannerFeature.id) {

        _disposeMainCameraController();
      } else {
          debugPrint("[Lifecycle] App paused/inactive on barcode page, main camera should be disposed.");

      }

    } else if (state == AppLifecycleState.resumed) {
      debugPrint("[Lifecycle] App resumed");


      if (currentFeatureId != barcodeScannerFeature.id) {
         debugPrint("[Lifecycle] Resumed on non-barcode page. Ensuring main camera is initialized.");

         _initializeMainCameraController();
      } else {
          debugPrint("[Lifecycle] App resumed on barcode page, main camera should remain off.");

      }


       if (!_webSocketService.isConnected) {
           debugPrint("[Lifecycle] Attempting WebSocket reconnect on resume...");
           _webSocketService.connect();
       }


    }
  }


  @override
  void dispose() {
    debugPrint("[HomeScreen] Disposing...");
    WidgetsBinding.instance.removeObserver(this);
    _stopDetectionTimer();

    _hazardAlertClearTimer?.cancel();
    _pageController.dispose();
    _disposeMainCameraController();
    if (_speechToText.isListening) { _speechToText.stop(); }
    _speechToText.cancel();
    if (_ttsInitialized) _ttsService.dispose();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    _webSocketService.close();
    debugPrint("[HomeScreen] Dispose complete.");
    super.dispose();
  }


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
       _lastRequestedFeatureId = currentFeatureId; // Use the actual page ID here

       final XFile imageFile = await _cameraController!.takePicture();


       _webSocketService.sendImageForProcessing(imageFile, objectDetectionFeature.id); // Always send as object_detection type

     } catch (e, stackTrace) {
       _handleCaptureError(e, stackTrace, currentFeatureId);
       _lastRequestedFeatureId = null;

     } finally {

        await Future.delayed(const Duration(milliseconds: 50));
        if(mounted) {

           _isProcessingImage = false;

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
       _lastRequestedFeatureId = null;
     } finally { if (mounted) setState(() => _isProcessingImage = false); }
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
            _initializeMainCameraController();
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

         if (featureId == objectDetectionFeature.id) {
             _lastObjectResult = "Error";

         } else if (featureId == hazardDetectionFeature.id) {
             _lastHazardRawResult = ""; _clearHazardAlert();
             _hazardAlertClearTimer?.cancel();
         } else if (featureId != null && featureId != barcodeScannerFeature.id) {
             _lastSceneTextResult = "Error";
         }
       });
       _showStatusMessage(errorMsg, isError: true, durationSeconds: 4);
     }
   }

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
         if (mounted) setState(() {});
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
         if (command == 'settings' || command == 'setting') { _navigateToSettingsPage(); return; }
         int targetPageIndex = -1;
         for (int i = 0; i < _features.length; i++) {
           for (String keyword in _features[i].voiceCommandKeywords) {
             if (command.contains(keyword)) { targetPageIndex = i; debugPrint('Matched "$command" to "${_features[i].title}" ($i)'); break; } }
           if (targetPageIndex != -1) break;
         }
         if (targetPageIndex != -1) _navigateToPage(targetPageIndex);
         else _showStatusMessage('Command "$command" not recognized.', durationSeconds: 3);
     }
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
     await _loadAndInitializeSettings();


      if (isMainCameraPage) {
         debugPrint("Attempting to reinitialize main camera after settings.");
         await _initializeMainCameraController();

      }


     _startDetectionTimerIfNeeded();
   }

   void _showPermissionInstructions() {
    if (!mounted) return;
     showDialog( context: context, builder: (BuildContext dialogContext) => AlertDialog(
           title: const Text('Microphone Permission'),
           content: const Text( 'Voice control requires microphone access.\n\nPlease enable the Microphone permission for this app in Settings.', ),
           actions: <Widget>[ TextButton( child: const Text('OK'), onPressed: () => Navigator.of(dialogContext).pop(), ), ],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)), ), );
   }


  @override
  Widget build(BuildContext context) {
     if (_features.isEmpty) return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text("No features configured.", style: TextStyle(color: Colors.white))));
     final validPageIndex = _currentPage.clamp(0, _features.length - 1);
     final currentFeature = _features[validPageIndex];
     final bool isRealtimePage = currentFeature.id == objectDetectionFeature.id || currentFeature.id == hazardDetectionFeature.id;
     final bool isBarcodePage = currentFeature.id == barcodeScannerFeature.id;


     Widget cameraDisplayWidget;
     if (isBarcodePage) {
       cameraDisplayWidget = Container(color: Colors.black); // Barcode page handles its own camera
    } else if (_isMainCameraInitializing) {
       cameraDisplayWidget = Container( // Show loading indicator while initializing
           key: const ValueKey('placeholder_initializing'),
           color: Colors.black,
           child: const Center(child: CircularProgressIndicator(color: Colors.white,)));
    } else if (_cameraController != null && _initializeControllerFuture != null) {
       cameraDisplayWidget = CameraViewWidget( // Show camera view if ready
                     key: _cameraViewKey, // Use key to force rebuild
             cameraController: _cameraController,
             initializeControllerFuture: _initializeControllerFuture,
           );
     } else {
              cameraDisplayWidget = Container( // Fallback / Error state
                     key: const ValueKey('placeholder_error'),
                     color: Colors.black,
                     child: const Center(child: Text("Camera unavailable", style: TextStyle(color: Colors.red)))
                     );
     }


     return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [

          cameraDisplayWidget, // Use the determined widget

          // Use AnimatedSwitcher for smoother visual transition
          // AnimatedSwitcher(
          //    duration: const Duration(milliseconds: 300),
          //    child: cameraDisplayWidget,
          // ),


          PageView.builder(
            controller: _pageController,
            itemCount: _features.length,
            physics: const ClampingScrollPhysics(),

            onPageChanged: (index) async {
              if (!mounted) return;
              final newPageIndex = index.clamp(0, _features.length - 1);
              if (newPageIndex >= _features.length) return;
              final previousPageIndex = _currentPage.clamp(0, _features.length - 1);
              if (previousPageIndex >= _features.length || previousPageIndex == newPageIndex) return;

              final previousFeature = _features[previousPageIndex];
              final newFeature = _features[newPageIndex];
              debugPrint("Page changed from ${previousFeature.title} to ${newFeature.title}");


              if(_ttsInitialized) _ttsService.stop();


              _stopDetectionTimer(); // ALWAYS stop timer first

              bool isSwitchingFromBarcode = previousFeature.id == barcodeScannerFeature.id;
              bool isSwitchingToBarcode = newFeature.id == barcodeScannerFeature.id;

              // Update page index state FIRST
              if(mounted) {
                // setState(() { _currentPage = newPageIndex; });

                                setState(() {
                  _currentPage = newPageIndex;
                  _isProcessingImage = false; _lastRequestedFeatureId = null;
                  // Clear previous page results
                  if (previousFeature.id == objectDetectionFeature.id) { _lastObjectResult = ""; }
                  else if (previousFeature.id == hazardDetectionFeature.id) { _hazardAlertClearTimer?.cancel(); _clearHazardAlert(); _lastHazardRawResult = ""; }
                  else if (previousFeature.id != barcodeScannerFeature.id) { _lastSceneTextResult = ""; }
                });

              } else { return; }


               // Handle Camera Transitions
               if (isSwitchingToBarcode) {
                   debugPrint("Switching TO barcode page - disposing main camera...");
                   await _disposeMainCameraController(); // Calls setState internally
                   debugPrint("Main camera disposed (awaited).");

               } else if (isSwitchingFromBarcode) {
                   debugPrint("Switching FROM barcode page - initializing main camera...");
                   await _initializeMainCameraController(); // Calls setState internally in finally block
                   debugPrint("Main camera initialization attempt completed.");
                   // NO extra setState or postFrameCallback needed here, init function handles it

                   
                   // Schedule final check/update/timer start for next frame
                   WidgetsBinding.instance.addPostFrameCallback((_) {
                       if(mounted){
                           bool isCamReadyNow = _cameraControllerCheck(showError: false);
                           setState((){}); // Force final UI update
                           debugPrint("Post-init callback: Camera ready=$isCamReadyNow. Forcing UI Update.");
                           if (isCamReadyNow) _startDetectionTimerIfNeeded();
                       }
                   });
               }

               // Start timer if switching between non-barcode realtime pages

              //  }


              // if(mounted) {
              //   // Clear previous page results AFTER camera ops complete
              //   setState(() {
              //     _isProcessingImage = false; _lastRequestedFeatureId = null;
              //     if (previousFeature.id == objectDetectionFeature.id) { _lastObjectResult = ""; }
              //     else if (previousFeature.id == hazardDetectionFeature.id) { _hazardAlertClearTimer?.cancel(); _clearHazardAlert(); _lastHazardRawResult = ""; }
              //     else if (previousFeature.id != barcodeScannerFeature.id) { _lastSceneTextResult = ""; }
              //   });

              // } else {
              //    return;
              // }



              final bool isNowRealtime = newFeature.id == objectDetectionFeature.id || newFeature.id == hazardDetectionFeature.id;

              if (isNowRealtime && !isSwitchingFromBarcode) {

              // if (isNowRealtime) {
                
                   // Try starting timer AFTER the page transition logic
                   _startDetectionTimerIfNeeded();
               }

            },

            itemBuilder: (context, index) {
               if (index >= _features.length) return const Center(child: Text("Error: Invalid page index", style: TextStyle(color: Colors.red)));
               final feature = _features[index];


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
          ),


          FeatureTitleBanner( title: currentFeature.title, backgroundColor: currentFeature.color, ),


          Align( alignment: Alignment.topRight, child: SafeArea( child: Padding(
                padding: const EdgeInsets.only(top: 10.0, right: 15.0),
                child: IconButton( icon: const Icon(Icons.settings, color: Colors.white, size: 32.0, shadows: [Shadow(blurRadius: 6.0, color: Colors.black54, offset: Offset(1.0, 1.0))]),
                  onPressed: _navigateToSettingsPage, tooltip: 'Settings', ), ), ), ),


          ActionButton(
            onTap: (isRealtimePage || isBarcodePage) ? null : () => _performManualDetection(currentFeature.id),
            onLongPress: () { if (!_speechEnabled) { _showStatusMessage('Speech not available', isError: true); _initSpeech(); return; }
               if (_speechToText.isNotListening) _startListening(); else _stopListening(); },
            isListening: _isListening, color: currentFeature.color,
          ),
        ],
      ),
    );
  }
}