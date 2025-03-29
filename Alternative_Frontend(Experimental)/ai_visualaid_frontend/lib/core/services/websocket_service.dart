// lib/core/services/websocket_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart'; // For XFile
import 'package:socket_io_client/socket_io_client.dart' as io;

class WebSocketService {
  // *** MAKE SURE THIS IP IS STILL CORRECT ***
  final String _serverUrl = 'http://xyz:5000'; // Replace xyz with your actual backend IP

  io.Socket? _socket;
  final StreamController<Map<String, dynamic>> _responseController =
      StreamController<Map<String, dynamic>>.broadcast();
  Timer? _connectionRetryTimer;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _retrySeconds = 5;

  Stream<Map<String, dynamic>> get responseStream => _responseController.stream;
  bool get isConnected => _isConnected;

  void connect() {
    if (_isConnecting || _isConnected) {
      debugPrint('[WebSocketService] Connect called but already connecting/connected.');
      return;
    }

    _isConnecting = true;
    _closeExistingSocket();
    _cancelRetryTimer();
    debugPrint('[WebSocketService] Attempting Socket.IO connection to: $_serverUrl');

    try {
      _socket = io.io(_serverUrl, io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setTimeout(10000) // Connection timeout
          .setReconnectionDelay(1000) // Initial reconnect delay
          .setReconnectionDelayMax(5000) // Max reconnect delay
          .setRandomizationFactor(0.5) // Randomize reconnect delay
          .build());

      // --- Event Handlers ---
      _socket!.onConnect((_) {
        debugPrint('[WebSocketService] Socket.IO connected: ID ${_socket?.id}');
        _isConnected = true;
        _isConnecting = false;
        _retrySeconds = 5;
        _responseController.add({'event': 'connect', 'result': 'Connected', 'id': _socket?.id});
      });

      _socket!.onConnectError((data) {
        debugPrint('[WebSocketService] Socket.IO Connection Error: $data');
        _isConnected = false;
        _isConnecting = false;
        _responseController.addError('Connection Error: ${data ?? "Unknown"}');
        _scheduleReconnect(isInitialFailure: true);
      });

      _socket!.on('connect_timeout', (data) {
         debugPrint('[WebSocketService] Socket.IO Connection Timeout: $data');
         _isConnected = false;
         _isConnecting = false;
         _responseController.addError('Connection Timeout');
         _scheduleReconnect(isInitialFailure: true);
      });

      _socket!.onError((data) {
        debugPrint('[WebSocketService] Socket.IO Error: $data');
        _responseController.addError('Socket Error: ${data ?? "Unknown"}');
         if (!_isConnected && !_isConnecting && _connectionRetryTimer == null) {
            debugPrint('[WebSocketService] Scheduling reconnect due to onError while disconnected.');
            _scheduleReconnect();
         }
      });

      _socket!.onDisconnect((reason) {
        debugPrint('[WebSocketService] Socket.IO disconnected: $reason');
         final wasConnected = _isConnected;
         _isConnected = false;
         _isConnecting = false;
         if (reason != 'io client disconnect' && wasConnected) {
           _responseController.addError('Disconnected: ${reason ?? "Unknown reason"}');
         }
         // Only schedule reconnect if it wasn't a manual client disconnect
         if (reason != 'io client disconnect') {
           _scheduleReconnect();
         } else {
             debugPrint('[WebSocketService] Manual disconnect requested, not scheduling reconnect.');
         }
      });

      _socket!.on('response', (data) {
        debugPrint('[WebSocketService] Received "response" event: $data');
        try {
          if (data is Map<String, dynamic>) {
            _responseController.add(data);
          } else if (data != null) {
             if (data is String) {
                _responseController.add({'result': data});
             } else {
                _responseController.add({'result': data.toString()});
                debugPrint('[WebSocketService] Received non-map data on "response", converting to string: $data');
             }
          } else {
              debugPrint('[WebSocketService] Received null data on "response" event.');
              _responseController.add({'result': null}); // Send null result forward
          }
        } catch (e, stackTrace) {
          debugPrint('[WebSocketService] Error processing "response" event data: $e');
          debugPrintStack(stackTrace: stackTrace);
          _responseController.addError(FormatException('Data Processing Error: $e'), stackTrace);
        }
      });

      // Other standard handlers...
      _socket!.on('reconnecting', (attempt) => debugPrint('[WebSocketService] Reconnecting attempt $attempt...'));
      _socket!.on('reconnect', (attempt) => debugPrint('[WebSocketService] Reconnected on attempt $attempt'));
      _socket!.on('reconnect_attempt', (attempt) {
          debugPrint('[WebSocketService] Reconnect attempt $attempt');
          // Optionally notify UI about reconnect attempts
          // _responseController.add({'event': 'reconnecting', 'attempt': attempt});
      });
      _socket!.on('reconnect_error', (data) => debugPrint('[WebSocketService] Reconnect error: $data'));
      _socket!.on('reconnect_failed', (data) {
         debugPrint('[WebSocketService] Reconnect failed: $data');
          _responseController.addError('Reconnect Failed');
          // Maybe stop trying after failed reconnects or notify user differently
      });
      // _socket!.on('ping', (_) => debugPrint('[WebSocketService] Ping')); // Can be verbose
      // _socket!.on('pong', (_) => debugPrint('[WebSocketService] Pong')); // Can be verbose

      // Manually initiate the connection
      _socket!.connect();
      // No need to set _isConnecting = true here, it's set at the start

    } catch (e, stackTrace) {
      debugPrint('[WebSocketService] Error initializing Socket.IO client: $e');
      debugPrintStack(stackTrace: stackTrace);
      _isConnecting = false;
      _isConnected = false;
      _responseController.addError('Initialization Error: ${e.toString()}', stackTrace);
      _scheduleReconnect(isInitialFailure: true);
    }
  }

  // --- Sending Data ---
  // *** MODIFIED: Added optional languageCode parameter ***
  void sendImageForProcessing(
      XFile imageFile,
      String pageType,
      {String? languageCode} // Optional language code
      ) async {
    if (!isConnected || _socket == null) {
      debugPrint('[WebSocketService] Cannot send image for $pageType: Not connected.');
      _responseController.addError('Cannot send: Not connected');
      return;
    }

    debugPrint('[WebSocketService] Preparing image for $pageType ${languageCode != null ? "(Lang: $languageCode)" : ""}...');
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // *** MODIFIED: Add language to payload if provided and type is text_detection ***
      final payload = {
        'type': pageType,
        'image': base64Image,
        if (pageType == 'text_detection' && languageCode != null)
          'language': languageCode, // Include language code conditionally
      };

      final payloadSizeKB = (json.encode(payload).length / 1024).toStringAsFixed(1);
      debugPrint('[WebSocketService] Sending "message" event ($payloadSizeKB kB) with payload keys: ${payload.keys}');

      _socket!.emitWithAck('message', payload, ack: (ackData) {
         debugPrint('[WebSocketService] Server acknowledged "message" event. Ack data: $ackData');
      });

    } catch (e, stackTrace) {
      debugPrint('[WebSocketService] Error preparing/sending image for $pageType: $e');
      debugPrintStack(stackTrace: stackTrace, label: '[WebSocketService] Send Image Error StackTrace');
      _responseController.addError('Image send failed: ${e.toString()}', stackTrace);
    }
  }

  // --- Connection Management ---
  void _scheduleReconnect({bool isInitialFailure = false}) {
    if (_connectionRetryTimer?.isActive ?? false) {
      debugPrint('[WebSocketService] Reconnect already scheduled.');
      return;
    }
    _closeExistingSocket(); // Ensure previous socket is closed before scheduling
    final currentDelay = isInitialFailure ? 3 : _retrySeconds;
    debugPrint('[WebSocketService] Scheduling Socket.IO reconnect in $currentDelay seconds...');
    _connectionRetryTimer = Timer(Duration(seconds: currentDelay), () {
      // Exponential backoff for subsequent retries
      if (!isInitialFailure) {
         // Increase delay, clamped between 5 and 60 seconds
        _retrySeconds = (_retrySeconds * 1.5).clamp(5, 60).toInt();
        debugPrint('[WebSocketService] Next retry delay set to $_retrySeconds seconds.');
      }
      debugPrint('[WebSocketService] Attempting Socket.IO reconnection...');
      connect(); // Try connecting again
    });
  }

  void _cancelRetryTimer() {
    _connectionRetryTimer?.cancel();
    _connectionRetryTimer = null;
     // Reset retry seconds when manually cancelled or successfully connected
     // (reset on connect is handled in onConnect)
     // If cancelled due to manual close, reset doesn't matter much.
     // If cancelled due to other reasons (e.g., manual connect attempt), resetting might be desired.
     // Let's reset it here for simplicity.
     // _retrySeconds = 5; // Optional: Reset backoff on any cancellation
  }

  void _closeExistingSocket() {
    if (_socket != null) {
      debugPrint('[WebSocketService] Disposing existing Socket.IO socket (ID: ${_socket?.id})...');
      try {
        // Important: use dispose() for socket_io_client
        _socket!.dispose();
      } catch (e) {
         debugPrint('[WebSocketService] Exception disposing socket: $e');
      } finally {
         _socket = null;
      }
    }
     // Reset connection state flags whenever closing
     _isConnected = false;
     _isConnecting = false;
  }

  void close() {
    debugPrint('[WebSocketService] Closing service requested...');
    _cancelRetryTimer(); // Stop any scheduled reconnects
     if (_socket?.connected ?? false) {
        debugPrint('[WebSocketService] Manually disconnecting socket...');
        // Use disconnect() for a clean client-side disconnect signal
        _socket!.disconnect();
     }
    _closeExistingSocket(); // Dispose the socket resources
    _responseController.close(); // Close the stream controller
    debugPrint('[WebSocketService] Service closed.');
  }
}