// lib/core/services/websocket_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class WebSocketService {
  // Ensure this URL points to your backend server IP/domain and port
  final String _serverUrl = 'http://192.168.70.126:5000'; // <<<--- IMPORTANT: Use your actual backend IP/hostname
  // Example: final String _serverUrl = 'http://your-backend-domain.com';

  io.Socket? _socket;
  final StreamController<Map<String, dynamic>> _responseController =
      StreamController<Map<String, dynamic>>.broadcast();
  Timer? _connectionRetryTimer;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _retrySeconds = 5; // Initial retry delay

  Stream<Map<String, dynamic>> get responseStream => _responseController.stream;
  bool get isConnected => _isConnected;

  void connect() {
    if (_isConnecting || _isConnected) {
      debugPrint('[WebSocketService] Connect called but already connecting/connected.');
      return;
    }

    _isConnecting = true;
    _closeExistingSocket(); // Ensure any old socket is closed first
    _cancelRetryTimer();
    debugPrint('[WebSocketService] Attempting Socket.IO connection to: $_serverUrl');

    try {
      _socket = io.io(_serverUrl, io.OptionBuilder()
          .setTransports(['websocket']) // Use only WebSockets
          .disableAutoConnect()        // We connect manually
          .enableReconnection()        // Allow library to handle basic reconnections
          .setTimeout(10000)           // Connection timeout (milliseconds)
          .setReconnectionDelay(2000)  // Initial delay before trying to reconnect
          .setReconnectionDelayMax(10000)// Max delay between reconnection attempts
          .setRandomizationFactor(0.5) // Randomize reconnection delay
          .build());

      // --- Connection Event Handlers ---
      _socket!.onConnect((_) {
        debugPrint('[WebSocketService] Socket.IO connected: ID ${_socket?.id}');
        _isConnected = true;
        _isConnecting = false;
        _retrySeconds = 5; // Reset retry delay on successful connect
        _cancelRetryTimer(); // Stop any pending manual reconnect timers
        // Emit structured connection event
        _responseController.add({'event': 'connect', 'result': {'status': 'connected', 'id': _socket?.id}});
      });

      _socket!.onConnectError((data) {
        debugPrint('[WebSocketService] Socket.IO Connection Error: $data');
        _isConnected = false;
        _isConnecting = false;
        _responseController.addError({'status': 'error', 'message': 'Connection Error: ${data ?? "Unknown"}'});
        _scheduleReconnect(isInitialFailure: true); // Start manual retry logic
      });

      _socket!.on('connect_timeout', (data) {
         debugPrint('[WebSocketService] Socket.IO Connection Timeout: $data');
         _isConnected = false;
         _isConnecting = false;
         _responseController.addError({'status': 'error', 'message': 'Connection Timeout'});
         _scheduleReconnect(isInitialFailure: true);
      });

      _socket!.onError((data) {
        debugPrint('[WebSocketService] Socket.IO Error: $data');
        // Send structured error if possible
        _responseController.addError({'status': 'error', 'message': 'Socket Error: ${data ?? "Unknown"}'});
        // Schedule reconnect if disconnected and not already trying
         if (!_isConnected && !_isConnecting && _connectionRetryTimer == null) {
            debugPrint('[WebSocketService] Scheduling reconnect due to onError while disconnected.');
            _scheduleReconnect();
         }
      });

      _socket!.onDisconnect((reason) {
        debugPrint('[WebSocketService] Socket.IO disconnected: $reason');
         final wasConnected = _isConnected; // Check if we *were* connected before this event
         _isConnected = false;
         _isConnecting = false;
         // Only add error if disconnect wasn't manual and we were previously connected
         if (reason != 'io client disconnect' && wasConnected) {
           _responseController.addError({'status': 'error', 'message': 'Disconnected: ${reason ?? "Unknown reason"}'});
         }

         // Schedule reconnect unless it was a manual disconnect
         if (reason != 'io client disconnect') {
           _scheduleReconnect();
         } else {
             debugPrint('[WebSocketService] Manual disconnect requested, not scheduling reconnect.');
         }
      });
      // --- --- --- --- --- --- --- ---

      // --- Main Response Handler ---
      _socket!.on('response', (data) {
        // Assuming backend now consistently sends structured JSON data in 'result'
        // debugPrint('[WebSocketService] Received "response" event data: $data');
        try {
          if (data is Map<String, dynamic> && data.containsKey('result')) {
              // Check if the result itself is the structured data we expect
              if (data['result'] is Map<String, dynamic>) {
                _responseController.add(data); // Pass the whole {result: {...}} structure
              } else {
                 // Handle cases where 'result' might be a simple string (legacy or error?)
                 debugPrint('[WebSocketService] Received "response" with non-map result: ${data['result']}');
                 _responseController.add({'result': {'status': 'raw', 'data': data['result']}}); // Wrap it
              }
          } else if (data != null) {
              // Handle unexpected data format - wrap it
              debugPrint('[WebSocketService] Received unexpected data format on "response": $data');
              _responseController.add({'result': {'status': 'unknown_format', 'data': data.toString()}});
          } else {
              debugPrint('[WebSocketService] Received null data on "response" event.');
              _responseController.add({'result': {'status': 'null_data'}});
          }
        } catch (e, stackTrace) {
          debugPrint('[WebSocketService] Error processing "response" event data: $e');
          debugPrintStack(stackTrace: stackTrace);
          // Send structured error
          _responseController.addError({'status': 'error', 'message': 'Data Processing Error: $e'});
        }
      });
      // --- --- --- --- --- --- --- ---

      // --- Reconnection Event Handlers (for logging/debugging) ---
      _socket!.on('reconnecting', (attempt) => debugPrint('[WebSocketService] Reconnecting attempt $attempt...'));
      _socket!.on('reconnect', (attempt) {
          debugPrint('[WebSocketService] Reconnected on attempt $attempt');
          // Note: onConnect handler should manage state and emit event
      });
      _socket!.on('reconnect_attempt', (attempt) { debugPrint('[WebSocketService] Reconnect attempt $attempt'); });
      _socket!.on('reconnect_error', (data) => debugPrint('[WebSocketService] Reconnect error: $data'));
      _socket!.on('reconnect_failed', (data) {
         debugPrint('[WebSocketService] Reconnect failed permanently (after max attempts): $data');
          _responseController.addError({'status': 'error', 'message': 'Reconnect Failed Permanently'});
      });
      // --- --- --- --- --- --- --- ---

      // Initiate the connection
      _socket!.connect();

    } catch (e, stackTrace) {
      debugPrint('[WebSocketService] Error initializing Socket.IO client: $e');
      debugPrintStack(stackTrace: stackTrace);
      _isConnecting = false;
      _isConnected = false;
      _responseController.addError({'status': 'error', 'message': 'Initialization Error: ${e.toString()}'});
      _scheduleReconnect(isInitialFailure: true); // Schedule retry even on init error
    }
  }

  /// Sends an image to the backend for processing.
  ///
  /// [imageFile]: The image captured by the camera.
  /// [processingType]: The type of processing requested ('object_detection', 'scene_detection', 'text_detection', 'focus_detection').
  /// [languageCode]: Optional language code for 'text_detection'.
  /// [focusObject]: Optional object name for 'focus_detection'.
  void sendImageForProcessing({
    required XFile imageFile,
    required String processingType,
    String? languageCode,
    String? focusObject, // New optional parameter for focus mode
  }) async {
    if (!isConnected || _socket == null) {
      debugPrint('[WebSocketService] Cannot send image for $processingType: Not connected.');
      // Send structured error
      _responseController.addError({'status': 'error', 'message': 'Cannot send: Not connected'});
      return;
    }

    String logDetails = languageCode != null ? "(Lang: $languageCode)" : "";
    if (processingType == 'focus_detection' && focusObject != null) {
      logDetails += " (Focus: $focusObject)";
    }
    debugPrint('[WebSocketService] Preparing image for $processingType $logDetails...');

    try {
      final bytes = await imageFile.readAsBytes();
      // It's generally recommended NOT to include the data URI prefix when sending via WebSockets unless the server specifically expects it.
      // Send only the base64 encoded string. The backend seems to handle both cases, but leaner is better.
      final base64Image = base64Encode(bytes);
      // final base64ImageWithPrefix = 'data:image/jpeg;base64,$base64Image'; // Keep commented unless needed

      final payload = <String, dynamic>{
        'type': processingType,
        'image': base64Image, // Send raw base64
        // Conditionally add language
        if (processingType == 'text_detection' && languageCode != null)
          'language': languageCode,
        // Conditionally add focus object
        if (processingType == 'focus_detection' && focusObject != null)
          'focus_object': focusObject,
      };

      final payloadSizeKB = (json.encode(payload).length / 1024).toStringAsFixed(1);
      debugPrint('[WebSocketService] Sending "message" event ($payloadSizeKB kB) with payload keys: ${payload.keys}');

      // Send the message and optionally handle acknowledgment from the server
      _socket!.emitWithAck('message', payload, ack: (ackData) {
         // This callback executes when the server acknowledges receipt
         debugPrint('[WebSocketService] Server acknowledged "message" event. Ack data: $ackData');
         // You could use ackData for flow control or confirmation if needed
      });

    } catch (e, stackTrace) {
      debugPrint('[WebSocketService] Error preparing/sending image for $processingType: $e');
      debugPrintStack(stackTrace: stackTrace, label: '[WebSocketService] Send Image Error StackTrace');
      // Send structured error
      _responseController.addError({'status': 'error', 'message': 'Image send failed: ${e.toString()}'});
    }
  }

  void _scheduleReconnect({bool isInitialFailure = false}) {
    if (_connectionRetryTimer?.isActive ?? false) {
      // debugPrint('[WebSocketService] Reconnect already scheduled.');
      return; // Don't schedule multiple timers
    }
    // Close socket before attempting reconnect to ensure clean state
    _closeExistingSocket();

    // Use initial delay for first failure, exponential backoff otherwise
    final currentDelay = isInitialFailure ? 3 : _retrySeconds;
    debugPrint('[WebSocketService] Scheduling Socket.IO reconnect attempt in $currentDelay seconds...');

    _connectionRetryTimer = Timer(Duration(seconds: currentDelay), () {
      // Increase retry delay for next time, capped at a maximum (e.g., 60 seconds)
      if (!isInitialFailure) {
        _retrySeconds = (_retrySeconds * 1.5).clamp(5, 60).toInt();
        debugPrint('[WebSocketService] Next retry delay set to $_retrySeconds seconds.');
      }
      debugPrint('[WebSocketService] Attempting Socket.IO reconnection...');
      connect(); // Attempt connection again
    });
  }

  void _cancelRetryTimer() {
    _connectionRetryTimer?.cancel();
    _connectionRetryTimer = null;
  }

  void _closeExistingSocket() {
    if (_socket != null) {
      debugPrint('[WebSocketService] Disposing existing Socket.IO socket (ID: ${_socket?.id})...');
      try {
        // Important: Use dispose() for client-side cleanup, not disconnect() which implies intent to the server.
        _socket!.dispose();
      } catch (e) {
         debugPrint('[WebSocketService] Exception disposing socket: $e');
      } finally {
         _socket = null; // Ensure reference is cleared
      }
    }
    // Reset connection state flags when explicitly closing
    _isConnected = false;
    _isConnecting = false;
  }

  /// Closes the WebSocket connection and releases resources.
  void close() {
    debugPrint('[WebSocketService] Closing service requested...');
    _cancelRetryTimer(); // Stop any pending reconnect attempts

    // If the socket exists and is connected, explicitly tell the server we are disconnecting.
    if (_socket?.connected ?? false) {
      debugPrint('[WebSocketService] Manually disconnecting socket...');
       // Using disconnect() sends a signal to the server.
      _socket!.disconnect();
    }

    // Dispose of the client-side socket object resources regardless of connection state.
    _closeExistingSocket();

    // Close the stream controller to signal no more events will be emitted.
    _responseController.close();
    debugPrint('[WebSocketService] Service closed.');
  }
}