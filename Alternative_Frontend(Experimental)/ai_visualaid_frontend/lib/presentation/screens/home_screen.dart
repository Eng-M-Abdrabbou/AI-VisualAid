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

// Core & Services
import '../../core/models/feature_config.dart';
import '../../core/services/websocket_service.dart';
import '../../core/services/settings_service.dart';

// Features
import '../../features/feature_registry.dart';
import '../../features/object_detection/presentation/pages/object_detection_page.dart';
import '../../features/hazard_detection/presentation/pages/hazard_detection_page.dart';
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

  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;


  final PageController _pageController = PageController();
  int _currentPage = 0;


  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;

  
  final WebSocketService _webSocketService = WebSocketService();
  late List<FeatureConfig> _features;
  final SettingsService _settingsService = SettingsService();
  String _selectedOcrLanguage = SettingsService.getValidatedDefaultLanguage();


  String _lastObjectResult = "";
  String _lastSceneTextResult = "";
  Timer? _objectResultClearTimer;
  String _lastHazardRawResult = ""; 
  String _currentDisplayedHazardName = "";
  bool _isHazardAlertActive = false; 
  Timer? _hazardAlertClearTimer; 


  Timer? _detectionTimer;
  final Duration _detectionInterval = const Duration(seconds: 1);
  final Duration _objectResultPersistence = const Duration(seconds: 2);
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
    _initializeServices();
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

    if (mounted) {
      setState(() {
        _isHazardAlertActive = true;
        _currentDisplayedHazardName = hazardName; 
      });
    }


    _playAlertSound();

    _triggerVibration();

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
    await _loadSettings();
    _initializeCameraController();
    _initSpeech();
    _initializeWebSocket();
    debugPrint("[HomeScreen] Services Initialized");
  }

  Future<void> _loadSettings() async {
    _selectedOcrLanguage = await _settingsService.getOcrLanguage();
    if (mounted) setState(() {});
     debugPrint("[HomeScreen] OCR language setting loaded: $_selectedOcrLanguage");
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

  void _initializeCameraController() {
     if (widget.camera == null) {
       debugPrint("No camera provided to HomeScreen");
       _showStatusMessage("No camera available", isError: true);
       return;
     }
     Future<void> disposeAndCreate() async {
         if (_cameraController != null) {
            debugPrint("Disposing previous camera controller...");
            await _cameraController!.dispose().catchError((e) { debugPrint("Error disposing previous camera: $e"); });
            _cameraController = null; _initializeControllerFuture = null;
            if (mounted) setState(() {});
            await Future.delayed(Duration(milliseconds: 100));
         }
         if (!mounted) return;
         debugPrint("Creating new CameraController...");
         _cameraController = CameraController(widget.camera!, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
         _initializeControllerFuture = _cameraController!.initialize().then((_) {
           if (!mounted) return;
           debugPrint("Camera initialized successfully.");
           setState(() {});
           _startDetectionTimerIfNeeded();
         }).catchError((error) {
           debugPrint("Camera initialization error: $error");
           if (mounted) {
              _showStatusMessage("Camera init failed: ${error is CameraException ? error.description : error}", isError: true);
              _cameraController = null; _initializeControllerFuture = null;
              setState(() {});
           }
         });
         if (mounted) setState(() {});
     }
     disposeAndCreate();
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
           final resultText = data['result'] as String? ?? "No result";
           final String? receivedForFeatureId = _lastRequestedFeatureId;

           if (receivedForFeatureId == null) {
               debugPrint('[HomeScreen] Received result, but _lastRequestedFeatureId is null. Ignoring.');
               return;
           }

           debugPrint('[HomeScreen] Received result for "$receivedForFeatureId": "$resultText"');

           setState(() {
               _lastRequestedFeatureId = null; 

               if (receivedForFeatureId == objectDetectionFeature.id) {
                   _lastObjectResult = resultText;
                   _objectResultClearTimer?.cancel();
                   _objectResultClearTimer = Timer(_objectResultPersistence, () {
                       if (mounted) setState(() => _lastObjectResult = "");
                   });

               } else if (receivedForFeatureId == hazardDetectionFeature.id) {
                   _lastHazardRawResult = resultText; 

                   String specificHazardFound = ""; 
                   bool hazardFoundInFrame = false;

                   if (resultText.isNotEmpty && resultText != "No objects detected" && !resultText.startsWith("Error")) {
                       List<String> detectedObjects = resultText.toLowerCase().split(',').map((e) => e.trim()).toList();
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
                   } else {
                   }

               } else if (receivedForFeatureId == sceneDetectionFeature.id || receivedForFeatureId == textDetectionFeature.id) {
                   _lastSceneTextResult = resultText;
               } else {
                   debugPrint("[HomeScreen] Received result for UNKNOWN feature ID: $receivedForFeatureId.");
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
        _objectResultClearTimer?.cancel();
        _hazardAlertClearTimer?.cancel(); 
        setState(() {
          _lastObjectResult = ""; _lastSceneTextResult = "Connection Error";
          _lastHazardRawResult = ""; _isHazardAlertActive = false; _currentDisplayedHazardName = ""; // Clear hazard state fully
        });
        _showStatusMessage("Connection Error: ${error.toString()}", isError: true);
      },
      onDone: () {
        if (!mounted) return;
        debugPrint('[HomeScreen] WebSocket connection closed.');
        _stopDetectionTimer();
        _objectResultClearTimer?.cancel();
        _hazardAlertClearTimer?.cancel(); 
        if (mounted) {
           setState(() {
             _lastObjectResult = ""; _lastSceneTextResult = "Disconnected";
             _lastHazardRawResult = ""; _isHazardAlertActive = false; _currentDisplayedHazardName = ""; // Clear hazard state fully
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
    final controller = _cameraController;
    debugPrint("[Lifecycle] State changed to: $state");

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      debugPrint("[Lifecycle] App inactive/paused - Cleaning up...");
      _stopDetectionTimer();
      _audioPlayer.pause(); 
      _hazardAlertClearTimer?.cancel(); 

      controller?.dispose().then((_) {
           debugPrint("[Lifecycle] Camera controller disposed.");
           if (mounted) setState(() { _cameraController = null; _initializeControllerFuture = null; });
      }).catchError((e) {
          debugPrint("[Lifecycle] Error disposing camera controller on pause: $e");
          if (mounted) setState(() { _cameraController = null; _initializeControllerFuture = null; });
      });
       
       if (mounted && _cameraController != null) {
           setState(() { _cameraController = null; _initializeControllerFuture = null; });
       }

    } else if (state == AppLifecycleState.resumed) {
      debugPrint("[Lifecycle] App resumed");
      
      if (_cameraController == null) {
        debugPrint("[Lifecycle] Re-initializing camera controller...");
        _initializeCameraController();
      }
       
       if (!_webSocketService.isConnected) {
           debugPrint("[Lifecycle] Attempting WebSocket reconnect on resume...");
           _webSocketService.connect();
       } else {
          _startDetectionTimerIfNeeded(); 
       }
  
    }
  }


  @override
  void dispose() {
    debugPrint("[HomeScreen] Disposing...");
    WidgetsBinding.instance.removeObserver(this);
    _stopDetectionTimer();
    _objectResultClearTimer?.cancel();
    _hazardAlertClearTimer?.cancel(); 
    _pageController.dispose();
    _cameraController?.dispose().catchError((e) { debugPrint("[Dispose] Error disposing camera: $e"); });
    _cameraController = null;
    if (_speechToText.isListening) { _speechToText.stop(); }
    _speechToText.cancel();
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

    if (isRealtimePage && _detectionTimer == null && (_cameraController?.value.isInitialized ?? false) && _webSocketService.isConnected) {
        debugPrint("[HomeScreen] Starting detection timer for page: $currentFeatureId");
        _detectionTimer = Timer.periodic(_detectionInterval, (_) { _performPeriodicDetection(); });
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
     if (!mounted || _features.isEmpty || _cameraController == null || !_cameraController!.value.isInitialized) return;
     final currentFeatureId = _features[_currentPage.clamp(0, _features.length - 1)].id;
     if (currentFeatureId != objectDetectionFeature.id && currentFeatureId != hazardDetectionFeature.id) {
         _stopDetectionTimer(); return;
     }
     if (!_cameraControllerCheck() || _isProcessingImage || !_webSocketService.isConnected) return;

     try {
       _isProcessingImage = true;
       _lastRequestedFeatureId = currentFeatureId; 

       final XFile imageFile = await _cameraController!.takePicture();

       _webSocketService.sendImageForProcessing(imageFile, objectDetectionFeature.id);

     } catch (e, stackTrace) {
       _handleCaptureError(e, stackTrace, currentFeatureId); 
       _lastRequestedFeatureId = null; 
       _isProcessingImage = false; 
     } finally {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) _isProcessingImage = false;
     }
   }

   void _performManualDetection(String featureId) async {
     if (featureId == objectDetectionFeature.id || featureId == hazardDetectionFeature.id) return; // Ignore for real-time
     debugPrint('Manual detection triggered for feature: $featureId');
     if (!_cameraControllerCheck() || _isProcessingImage || !_webSocketService.isConnected) return;

     try {
       _isProcessingImage = true; _lastRequestedFeatureId = featureId;
       _showStatusMessage("Capturing...", durationSeconds: 1);
       final XFile imageFile = await _cameraController!.takePicture();
       _showStatusMessage("Processing...", durationSeconds: 2);
       _webSocketService.sendImageForProcessing( imageFile, featureId,
           languageCode: (featureId == textDetectionFeature.id) ? _selectedOcrLanguage : null, );
     } catch (e, stackTrace) {
       _handleCaptureError(e, stackTrace, featureId); _lastRequestedFeatureId = null;
     } finally { if (mounted) _isProcessingImage = false; }
   }

   bool _cameraControllerCheck() {
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
       debugPrint('Camera not ready.'); _showStatusMessage("Camera not ready", isError: true);
       if (_cameraController == null && widget.camera != null) _initializeCameraController();
       return false;
     }
      if (_cameraController!.value.isTakingPicture) {
          debugPrint('Camera busy taking picture.'); return false;
      }
      return true;
   }

  void _handleCaptureError(Object e, StackTrace stackTrace, String featureId) {
     debugPrint('Capture/Send Error for $featureId: $e'); debugPrintStack(stackTrace: stackTrace);
     String errorMsg = e is CameraException ? "Capture Error: ${e.description ?? e.code}" : "Processing Error";
     if (mounted) {
       setState(() {
         if (featureId == objectDetectionFeature.id) {
             _lastObjectResult = "Error"; _objectResultClearTimer?.cancel();
         } else if (featureId == hazardDetectionFeature.id) {
             _lastHazardRawResult = ""; _clearHazardAlert(); 
             _hazardAlertClearTimer?.cancel();
         } else {
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
         debugPrint("Navigating to page index: $targetIndex (${_features[targetIndex].title})");
         _pageController.animateToPage( targetIndex, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut, );
      }
   }

   void _navigateToSettingsPage() async {
     if (mounted) {
       debugPrint("Navigating to Settings page...");
       if (_speechToText.isListening) await _stopListening();
       _stopDetectionTimer();
       await Navigator.push( context, MaterialPageRoute(builder: (context) => const SettingsScreen()), );
       if (!mounted) return; debugPrint("Returned from Settings page.");
       await _loadSettings();
       _startDetectionTimerIfNeeded();
     }
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

     return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera View
          CameraViewWidget( cameraController: _cameraController, initializeControllerFuture: _initializeControllerFuture, ),
          // 2. PageView
          PageView.builder(
            controller: _pageController,
            itemCount: _features.length,
            onPageChanged: (index) {
              if (!mounted) return;
              final newPageIndex = index.clamp(0, _features.length - 1);
              if (newPageIndex >= _features.length) return;
              final previousPageIndex = _currentPage.clamp(0, _features.length - 1);
              if (previousPageIndex >= _features.length || previousPageIndex == newPageIndex) return;

              final previousFeature = _features[previousPageIndex];
              final newFeature = _features[newPageIndex];
              debugPrint("Page changed from ${previousFeature.title} to ${newFeature.title}");

              setState(() {
                 _currentPage = newPageIndex;
                 _isProcessingImage = false; _lastRequestedFeatureId = null;


                 if (previousFeature.id == objectDetectionFeature.id) {
                     _objectResultClearTimer?.cancel(); _lastObjectResult = "";
                 } else if (previousFeature.id == hazardDetectionFeature.id) {
                     _hazardAlertClearTimer?.cancel();
                     _clearHazardAlert();
                     _lastHazardRawResult = "";
                 } else {

                 }
              });


              final bool wasRealtime = previousFeature.id == objectDetectionFeature.id || previousFeature.id == hazardDetectionFeature.id;
              final bool isNowRealtime = newFeature.id == objectDetectionFeature.id || newFeature.id == hazardDetectionFeature.id;
              if (wasRealtime && !isNowRealtime) _stopDetectionTimer();
              if (isNowRealtime) _startDetectionTimerIfNeeded();
            },

            itemBuilder: (context, index) {
               if (index >= _features.length) return const Center(child: Text("Error: Invalid page index", style: TextStyle(color: Colors.red)));
               final feature = _features[index];

               if (feature.id == objectDetectionFeature.id) {
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
               } else {
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
            onTap: isRealtimePage ? null : () => _performManualDetection(currentFeature.id),
            onLongPress: () { if (!_speechEnabled) { _showStatusMessage('Speech not available', isError: true); _initSpeech(); return; }
               if (_speechToText.isNotListening) _startListening(); else _stopListening(); },
            isListening: _isListening, color: currentFeature.color,
          ),
        ],
      ),
    );
  }
}