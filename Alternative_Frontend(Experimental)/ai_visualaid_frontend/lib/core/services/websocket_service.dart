import 'dart:async';
import 'dart:convert';
// import 'dart:io'; // REMOVED - Unused import

import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:web_socket_channel/web_socket_channel.dart'; // Provides WebSocketChannelException
import 'package:camera/camera.dart'; // For XFile
// Import status codes with a lowercase prefix
import 'package:web_socket_channel/status.dart' as websocket_status; // FIXED: Lowercase prefix
// REMOVED - Unnecessary and implementation import
// import 'package:web_socket_channel/src/exception.dart';

class WebSocketService {
  final String _baseUrl = 'ws://192.168.70.126:5000';

  WebSocketChannel? _channel;
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
    _closeExistingChannel();
    _cancelRetryTimer();

    Uri uriToConnect;
    try {
      uriToConnect = Uri.parse(_baseUrl);
      debugPrint('[WebSocketService] Attempting connection to: $uriToConnect');
      if (uriToConnect.port != 5000) {
        final errorMsg = 'Config Error: WebSocket port must be 5000, found ${uriToConnect.port}. Check _baseUrl.';
        debugPrint('[WebSocketService] $errorMsg');
        _responseController.addError(ArgumentError(errorMsg)); // No const here
        _isConnecting = false;
        return;
      }
    } catch (e) {
      final errorMsg = 'Config Error: Failed to parse WebSocket URL "$_baseUrl". Error: $e';
      debugPrint('[WebSocketService] $errorMsg');
      _responseController.addError(ArgumentError(errorMsg)); // No const here
      _isConnecting = false;
      return;
    }

    try {
      _channel = WebSocketChannel.connect(uriToConnect);
      _isConnecting = false;

      debugPrint('[WebSocketService] Channel established. Listening...');

      _channel!.stream.listen(
        (message) {
          if (!_isConnected) {
            debugPrint('[WebSocketService] Connection confirmed (first message received).');
            _isConnected = true;
            _retrySeconds = 5;
          }

          try {
            if (message is String && message.isNotEmpty) {
              final decodedMessage = json.decode(message);
              if (decodedMessage is Map<String, dynamic>) {
                _responseController.add(decodedMessage);
              } else {
                debugPrint('[WebSocketService] Received non-map JSON: $decodedMessage');
                _responseController.addError(
                  // FIXED: Added const where applicable
                  const FormatException("Received non-map JSON data")
                );
              }
            } else if (message != null) {
              debugPrint('[WebSocketService] Received unexpected message type: ${message.runtimeType}');
               _responseController.addError(
                 // FIXED: Added const where applicable
                 const FormatException("Received unexpected data type")
               );
            } else {
              debugPrint('[WebSocketService] Received null message.');
            }
          } catch (e, stackTrace) {
            debugPrint('[WebSocketService] Error decoding message: $e');
            debugPrint('[WebSocketService] Raw message: $message');
            _responseController.addError(FormatException('JSON Decode Error: $e'), stackTrace); // No const
          }
        },
        onError: (error, stackTrace) {
          debugPrint('[WebSocketService] Stream Error: $error');
          debugPrintStack(stackTrace: stackTrace, label: '[WebSocketService] Stream Error StackTrace');
          // Pass the original error object
          _responseController.addError(error, stackTrace); // No const

          _isConnected = false;
          _isConnecting = false;
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[WebSocketService] Stream closed (connection done). Was connected: $_isConnected');
          if (_isConnected) {
            _responseController.addError(
              // FIXED: Added const where applicable
               WebSocketChannelException('WebSocket disconnected unexpectedly')
            );
          }
          _isConnected = false;
          _isConnecting = false;
          _scheduleReconnect();
        },
        cancelOnError: false,
      );

      Future.delayed(const Duration(seconds: 1), () {
        if (_channel != null && !_isConnected) {
          debugPrint('[WebSocketService] Sending initial ping check...');
          _sendJson({'type': 'ping'});
        }
      });

    } catch (e, stackTrace) {
      debugPrint('[WebSocketService] Connection failed immediately: $e');
      debugPrintStack(stackTrace: stackTrace, label: '[WebSocketService] Connection StackTrace');
      // Pass the original error object
      _responseController.addError(e, stackTrace); // No const

      _isConnecting = false;
      _isConnected = false;
      _scheduleReconnect(isInitialFailure: true);
    }
  }

  void _sendJson(Map<String, dynamic> data) {
    if (_channel == null) {
      debugPrint('[WebSocketService] Cannot send: Channel is null.');
      _responseController.addError(
        // FIXED: Removed const
        WebSocketChannelException('Cannot send: Not connected')
      );
      return;
    }

    try {
      final message = json.encode(data);
      _channel!.sink.add(message);
      debugPrint('[WebSocketService] Sent: ${data['type'] ?? 'message'}');
    } catch (e, stackTrace) {
      debugPrint('[WebSocketService] Error sending message: $e');
      debugPrintStack(stackTrace: stackTrace, label: '[WebSocketService] Send Error StackTrace');
      _responseController.addError(e, stackTrace); // No const

      if (_isConnected || _isConnecting) {
        _isConnected = false;
        _isConnecting = false;
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect({bool isInitialFailure = false}) {
    if (_connectionRetryTimer?.isActive ?? false) {
      debugPrint('[WebSocketService] Reconnect already scheduled.');
      return;
    }
    _closeExistingChannel();

    final currentDelay = isInitialFailure ? 3 : _retrySeconds;

    debugPrint('[WebSocketService] Scheduling WebSocket reconnect in $currentDelay seconds...');
    _connectionRetryTimer = Timer(Duration(seconds: currentDelay), () {
      if (!isInitialFailure) {
        _retrySeconds = (_retrySeconds * 1.5).clamp(5, 60).toInt();
        debugPrint('[WebSocketService] Next retry delay set to $_retrySeconds seconds.');
      }
      debugPrint('[WebSocketService] Attempting WebSocket reconnection...');
      connect();
    });
  }

  void _cancelRetryTimer() {
    _connectionRetryTimer?.cancel();
    _connectionRetryTimer = null;
    _retrySeconds = 5;
  }

  void _closeExistingChannel() {
    if (_channel != null) {
      debugPrint('[WebSocketService] Closing existing WebSocket channel...');
      try {
        // FIXED: Use lowercase prefix
        _channel!.sink.close(websocket_status.goingAway).catchError((error) {
          debugPrint('[WebSocketService] Error closing WebSocket sink: $error');
        });
      } catch (e) {
        debugPrint('[WebSocketService] Exception closing WebSocket sink: $e');
      } finally {
        _channel = null;
      }
    }
  }

  void sendImageForProcessing(XFile imageFile, String pageType) async {
    if (!isConnected) {
      debugPrint('[WebSocketService] Cannot send image for $pageType: Not connected.');
      _responseController.addError(
        // FIXED: Removed const
         WebSocketChannelException('Cannot send: Not connected')
      );
      return;
    }

    debugPrint('[WebSocketService] Preparing image for $pageType...');
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final payload = {
        'type': pageType,
        'image': base64Image,
      };

      debugPrint('[WebSocketService] Sending $pageType image (${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} kB)...');
      _sendJson(payload);

    } catch (e, stackTrace) {
      debugPrint('[WebSocketService] Error preparing/sending image for $pageType: $e');
      debugPrintStack(stackTrace: stackTrace, label: '[WebSocketService] Send Image Error StackTrace');
      _responseController.addError('Image send failed: $e', stackTrace); // No const
    }
  }

  void close() {
    debugPrint('[WebSocketService] Closing service...');
    _cancelRetryTimer();
    _closeExistingChannel();
    _responseController.close();
    _isConnected = false;
    _isConnecting = false;
    debugPrint('[WebSocketService] Service closed.');
  }
}