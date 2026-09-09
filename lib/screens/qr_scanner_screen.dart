import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> with SingleTickerProviderStateMixin {
  late MobileScannerController _controller;
  late AnimationController _laserController;
  bool _isScanned = false;
  bool _hasPermission = false;
  bool _checkingPermission = true;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _checkCameraPermission();
  }

  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _hasPermission = status.isGranted;
        _checkingPermission = false;
      });
    }
  }

  @override
  void dispose() {
    _laserController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        _isScanned = true;
        Navigator.pop(context, rawValue.trim());
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan P2P QR Code', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: state.torchState == TorchState.on ? const Color(0xFF10B981) : Colors.white,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
            tooltip: 'Toggle Flashlight',
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
            onPressed: () => _controller.switchCamera(),
            tooltip: 'Switch Camera',
          ),
        ],
      ),
      body: _checkingPermission
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : !_hasPermission
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'Camera Permission Required',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please grant camera permission to scan QR codes for P2P pairing.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _checkCameraPermission,
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                          icon: const Icon(Icons.security_rounded),
                          label: const Text('Grant Camera Permission'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                    ),

                    // Scanner Viewfinder Overlay with Animated Laser Beam
                    Center(
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF10B981), width: 2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: AnimatedBuilder(
                          animation: _laserController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: _ScanLaserPainter(progress: _laserController.value),
                            );
                          },
                        ),
                      ),
                    ),

                    // Instruction Banner
                    Positioned(
                      bottom: 40,
                      left: 20,
                      right: 20,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'Point camera at target device QR code to pair',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.keyboard_outlined, color: Colors.white70, size: 18),
                            label: const Text('Enter IP Manually', style: TextStyle(color: Colors.white70)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    ),
    );
  }
}

class _ScanLaserPainter extends CustomPainter {
  _ScanLaserPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final linePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 3.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), linePaint);
  }

  @override
  bool shouldRepaint(covariant _ScanLaserPainter oldDelegate) => oldDelegate.progress != progress;
}
