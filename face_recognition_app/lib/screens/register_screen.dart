import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import '../services/face_detector_service.dart';
import '../services/face_embedder_service.dart';
import '../services/face_storage_service.dart';
import '../models/registered_face.dart';
import '../painters/face_mesh_painter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  final FaceDetectorService _detectorService = FaceDetectorService();
  final FaceEmbedderService _embedderService = FaceEmbedderService();
  final FaceStorageService _storageService = FaceStorageService();

  List<Face> _faces = [];
  bool _isProcessing = false;
  bool _cameraReady = false;
  String _statusText = 'Position your face in the frame';

  late AnimationController _scanAnimController;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _init();
  }

  Future<void> _init() async {
    _detectorService.init();
    await _embedderService.init();
    await _storageService.init();
    await _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    setState(() => _cameraReady = true);

    _cameraController!.startImageStream(_onFrame);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final camera = _cameraController!.description;
      final inputImage = _detectorService.inputImageFromCameraImage(
        image,
        camera,
        camera.sensorOrientation,
      );
      if (inputImage == null) return;

      final faces = await _detectorService.detectFacesWithContours(inputImage);

      if (mounted) {
        setState(() {
          _faces = faces;
          _statusText = faces.isEmpty
              ? 'Position your face in the frame'
              : faces.length == 1
                  ? 'Face detected — tap capture'
                  : 'Multiple faces — use only one';
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _captureAndRegister() async {
    if (_faces.isEmpty || _faces.length > 1) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    await _cameraController!.stopImageStream();

    final name = await _showNameDialog();
    if (name == null || name.trim().isEmpty) {
      _cameraController!.startImageStream(_onFrame);
      return;
    }

    setState(() => _statusText = 'Processing...');

    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();
      final fullImage = img.decodeImage(bytes);

      if (fullImage == null) {
        _showError('Failed to decode image');
        return;
      }

      final face = _faces.first;
      final box = face.boundingBox;

      final faceImg = img.copyCrop(
        fullImage,
        x: box.left.toInt().clamp(0, fullImage.width - 1),
        y: box.top.toInt().clamp(0, fullImage.height - 1),
        width: box.width.toInt().clamp(1, fullImage.width),
        height: box.height.toInt().clamp(1, fullImage.height),
      );

      final embedding = _embedderService.getEmbedding(faceImg);
      if (embedding == null) {
        _showError('Could not generate face embedding');
        return;
      }

      await _storageService.saveFace(
        RegisteredFace(
          name: name.trim(),
          embedding: embedding,
          registeredAt: DateTime.now(),
        ),
      );

      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${name.trim()} registered successfully'),
            backgroundColor: Colors.cyanAccent.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _showError('Registration failed: $e');
      _cameraController?.startImageStream(_onFrame);
    }
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.3)),
        ),
        title: const Text(
          'Enter Name',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Full name',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.4)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.cyanAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _detectorService.dispose();
    _embedderService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Register Face',
          style: TextStyle(fontSize: 16, letterSpacing: 1),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: _cameraReady && _cameraController != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_cameraController!),
                      AnimatedBuilder(
                        animation: _scanAnimController,
                        builder: (context, child) => CustomPaint(
                          painter: FaceMeshPainter(
                            faces: _faces,
                            imageSize: Size(
                              _cameraController!.value.previewSize!.width,
                              _cameraController!.value.previewSize!.height,
                            ),
                            isFrontCamera: _cameraController!
                                    .description.lensDirection ==
                                CameraLensDirection.front,
                            animationValue: _scanAnimController.value,
                          ),
                          child: _faces.isEmpty
                              ? CustomPaint(
                                  painter: _FaceGuidePainter(
                                    animValue: _scanAnimController.value,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              children: [
                Text(
                  _statusText,
                  style: TextStyle(
                    color: _faces.length == 1 ? Colors.cyanAccent : Colors.white54,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _faces.length == 1 ? _captureAndRegister : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      disabledBackgroundColor: Colors.white12,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Capture & Register',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
          ), // SafeArea
        ],
      ),
    );
  }
}

// Guide oval + scan line shown when no face is detected yet
class _FaceGuidePainter extends CustomPainter {
  final double animValue;
  const _FaceGuidePainter({required this.animValue});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.45;
    final rx = size.width * 0.32;
    final ry = size.height * 0.28;

    final ovalRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rx * 2,
      height: ry * 2,
    );

    // Dashed oval guide
    final borderPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.55)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawOval(ovalRect, borderPaint);

    // Corner accent marks on oval (top/bottom/left/right)
    const markLen = 18.0;
    final markPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Top
    canvas.drawLine(Offset(cx - markLen, cy - ry), Offset(cx + markLen, cy - ry), markPaint);
    // Bottom
    canvas.drawLine(Offset(cx - markLen, cy + ry), Offset(cx + markLen, cy + ry), markPaint);
    // Left
    canvas.drawLine(Offset(cx - rx, cy - markLen), Offset(cx - rx, cy + markLen), markPaint);
    // Right
    canvas.drawLine(Offset(cx + rx, cy - markLen), Offset(cx + rx, cy + markLen), markPaint);

    // Animated scan line inside oval
    final scanY = (cy - ry) + (ry * 2) * animValue;
    final halfWidth = rx * (1 - ((scanY - cy).abs() / ry).clamp(0.0, 1.0) * 0.6);
    final scanPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.5 + 0.4 * (1 - animValue))
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx - halfWidth, scanY),
      Offset(cx + halfWidth, scanY),
      scanPaint,
    );

    // Instruction text
    final tp = TextPainter(
      text: const TextSpan(
        text: 'ALIGN FACE HERE',
        style: TextStyle(
          color: Colors.white38,
          fontSize: 11,
          letterSpacing: 2,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy + ry + 14));
  }

  @override
  bool shouldRepaint(_FaceGuidePainter old) => old.animValue != animValue;
}
