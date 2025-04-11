import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/services/barcode_api_service.dart';
import '../../../../core/services/tts_service.dart';

class BarcodeScannerPage extends StatefulWidget {
  final BarcodeApiService barcodeApiService;
  final TtsService ttsService;

  const BarcodeScannerPage({
    super.key,
    required this.barcodeApiService,
    required this.ttsService,
  });

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> with WidgetsBindingObserver {
  MobileScannerController? controller;
  StreamSubscription<Object?>? _subscription;

  String? _lastProcessedBarcode;
  String _scanResult = "Point camera at a barcode";
  bool _isProcessing = false;
  bool _scannerStarted = false;
  bool _isPageActive = true;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScanner();
    debugPrint("[BarcodeScannerPage] initState completed.");
  }

  Future<void> _initializeScanner() async {
     debugPrint("[BarcodeScannerPage] Initializing Scanner...");
     controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        detectionTimeoutMs: 1500,

      );

      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted && _isPageActive) {
          _startListening();
      } else {
          debugPrint("[BarcodeScannerPage] Scanner init delayed, but page became inactive or unmounted.");
          controller?.dispose();
          controller = null;
      }
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
     super.didChangeAppLifecycleState(state);
     if (!mounted) return;
     debugPrint("[BarcodeScannerPage] AppLifecycleState: $state");
     if (state == AppLifecycleState.resumed) {
        _isPageActive = true;
        if (controller == null) {
           _initializeScanner();
        } else if (!_scannerStarted) {
          _startListening();
        }
     } else {
         _isPageActive = false;
         _stopListening();
     }
  }

  void _startListening() async {
    if (!mounted || controller == null || _scannerStarted || !_isPageActive) {
        debugPrint("[BarcodeScannerPage] Skipping startListening: mounted=$mounted, controllerNull=${controller==null}, started=$_scannerStarted, active=$_isPageActive");
        return;
    }
    debugPrint("[BarcodeScannerPage] Attempting to start scanner listening...");
    try {
      await controller!.start();
      if (!mounted || !_isPageActive) {
         debugPrint("[BarcodeScannerPage] Page became inactive or unmounted during controller start. Stopping.");
         await controller!.stop();
         return;
      }

      _subscription = controller!.barcodes.listen(_handleBarcode);
      setState(() { _scannerStarted = true; });
      debugPrint("[BarcodeScannerPage] Scanner listening started successfully.");

    } catch (e,s) {
        debugPrint("[BarcodeScannerPage] Error starting scanner controller or listener: $e \n$s");
        if (mounted) {
            setState(() { _scanResult = "Error starting scanner"; });
        }
        controller = null;
        _scannerStarted = false;
    }
  }

  Future<void> _stopListening() async {
    if (controller == null || !_scannerStarted) {
         debugPrint("[BarcodeScannerPage] Skipping stopListening: controllerNull=${controller==null}, notStarted=${!_scannerStarted}");
        return;
    }
    debugPrint("[BarcodeScannerPage] Attempting to stop scanner listening...");
    try {
       await _subscription?.cancel();
       _subscription = null;


       await controller!.stop();
       debugPrint("[BarcodeScannerPage] Scanner listening stopped successfully.");
       if(mounted) setState(() { _scannerStarted = false; });
    } catch(e,s) {
         debugPrint("[BarcodeScannerPage] Error stopping barcode listener/controller: $e \n$s");

         if (mounted) setState(() { _scannerStarted = false; });
    }
  }

  void _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing || !mounted || !_scannerStarted || !_isPageActive) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? scannedValue = barcodes.first.rawValue;

      if (scannedValue != null && scannedValue.isNotEmpty && scannedValue != _lastProcessedBarcode) {

        setState(() {
          _isProcessing = true;
          _scanResult = "Processing: $scannedValue";
          _lastProcessedBarcode = scannedValue;
        });
        widget.ttsService.stop();
        debugPrint("[BarcodeScannerPage] Detected barcode: $scannedValue");


        try {
          final productInfo = await widget.barcodeApiService.getProductInfo(scannedValue);
          if (mounted) {
            setState(() {
              _scanResult = productInfo;
            });
            widget.ttsService.speak(productInfo);
          }
        } catch (e) {
           debugPrint("[BarcodeScannerPage] Error fetching barcode info: $e");
           if (mounted) {
             setState(() {
                _scanResult = "Error fetching info";
             });
             widget.ttsService.speak("Error fetching info");
           }
        } finally {
           if (mounted) {
              await Future.delayed(const Duration(milliseconds: 500));
              if (mounted) setState(() { _isProcessing = false; });



              await Future.delayed(const Duration(seconds: 3));
              if (mounted && _lastProcessedBarcode == scannedValue && !_isProcessing) {
                   setState(() {
                       _lastProcessedBarcode = null;
                       _scanResult = "Point camera at a barcode";
                    });
                    debugPrint("[BarcodeScannerPage] Resetting last processed barcode.");
              }
           }
        }
      }
    }
  }




  @override
  void dispose() {
    debugPrint("[BarcodeScannerPage] Disposing.");
    WidgetsBinding.instance.removeObserver(this);
    _isPageActive = false;
    _stopListening();
    controller?.dispose();
    controller = null;
    widget.ttsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanWindow = Rect.fromCenter(
      center: MediaQuery.of(context).size.center(Offset.zero),
      width: 250,
      height: 250,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && _scannerStarted)
             MobileScanner(
                key: const ValueKey("MobileScannerWidget"),
                controller: controller!,
                scanWindow: scanWindow,
                errorBuilder: (context, error, child) {
                  String message = error.errorDetails?.message ?? 'Unknown scanner error';
                  debugPrint("[BarcodeScannerPage] MobileScanner Error: $message");
                  return Center(child: Text('Scanner Error: $message', style: const TextStyle(color: Colors.red)));
                },
             )
          else
            const Center(child: CircularProgressIndicator()),

          CustomPaint(
            painter: ScannerOverlayPainter(scanWindow),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              alignment: Alignment.center,
              height: 100,
              color: Colors.black.withOpacity(0.6),
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                _scanResult,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;

  ScannerOverlayPainter(this.scanWindow);

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final cutOutPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRect(scanWindow),
    );

    canvas.drawPath(cutOutPath, backgroundPaint);
    canvas.drawRect(scanWindow, borderPaint);


    final cornerPaint = Paint()
      ..color = Colors.tealAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    const cornerLength = 20.0;


    canvas.drawPath(
      Path()
        ..moveTo(scanWindow.left, scanWindow.top + cornerLength)
        ..lineTo(scanWindow.left, scanWindow.top)
        ..lineTo(scanWindow.left + cornerLength, scanWindow.top),
      cornerPaint,
    );
     canvas.drawPath(
      Path()
        ..moveTo(scanWindow.right - cornerLength, scanWindow.top)
        ..lineTo(scanWindow.right, scanWindow.top)
        ..lineTo(scanWindow.right, scanWindow.top + cornerLength),
      cornerPaint,
    );
      canvas.drawPath(
      Path()
        ..moveTo(scanWindow.right, scanWindow.bottom - cornerLength)
        ..lineTo(scanWindow.right, scanWindow.bottom)
        ..lineTo(scanWindow.right - cornerLength, scanWindow.bottom),
      cornerPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(scanWindow.left + cornerLength, scanWindow.bottom)
        ..lineTo(scanWindow.left, scanWindow.bottom)
        ..lineTo(scanWindow.left, scanWindow.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}