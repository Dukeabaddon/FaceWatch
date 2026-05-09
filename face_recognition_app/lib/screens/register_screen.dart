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

enum _FaceState { none, tooFar, tooClose, offCenter, lowLight, good }

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

  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  List<Face> _faces = [];
  CameraImage? _lastCameraImage;
  int _lastRotDeg = 0;
  Size _imageSize = Size.zero;
  bool _isProcessing = false;
  bool _cameraReady = false;
  bool _isSwitchingCamera = false;
  _FaceState _faceState = _FaceState.none;
  // ignore: prefer_final_fields
  DeviceOrientation _deviceOrientation = DeviceOrientation.portraitUp;

  late AnimationController _scanAnimController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    _detectorService.init();
    await _embedderService.init();
    await _storageService.init();
    await _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;

    // Default to front camera
    _cameraIndex = _cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    if (_cameraIndex < 0) _cameraIndex = 0;

    await _startCamera(_cameraIndex);
  }

  Future<void> _startCamera(int index) async {
    setState(() { _cameraReady = false; _faces = []; _faceState = _FaceState.none; });

    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();

    _cameraController = CameraController(
      _cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    // Track device orientation changes
    _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);

    setState(() { _cameraReady = true; _isSwitchingCamera = false; });
    _cameraController!.startImageStream(_onFrame);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isSwitchingCamera) return;
    setState(() => _isSwitchingCamera = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera(_cameraIndex);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final camera = _cameraController!.description;
      final inputImage = _detectorService.inputImageFromCameraImage(
        image, camera, _deviceOrientation,
      );
      if (inputImage == null) return;

      final faces = await _detectorService.detectFacesWithContours(inputImage);
      if (!mounted) return;

      debugPrint('[FaceDetect] faces=${faces.length} img=${image.width}x${image.height}');

      // Sensor is landscape (e.g. 720x480). Display rotates 90deg → portrait.
      // Painter scaleX = screenW/imageW, scaleY = screenH/imageH.
      // After rotation: sensor W maps to screen H, sensor H maps to screen W.
      // So pass swapped: Size(image.height, image.width).
      final sensorSize = Size(image.height.toDouble(), image.width.toDouble());
      final state = _evaluateFaceState(faces, image);

      final rotDeg = _detectorService.getRotationDegrees(camera, _deviceOrientation);
      setState(() {
        _faces = faces;
        _faceState = state;
        _imageSize = sensorSize;
        if (faces.isNotEmpty) {
          _lastCameraImage = image;
          _lastRotDeg = rotDeg;
        }
      });
    } finally {
      _isProcessing = false;
    }
  }

  _FaceState _evaluateFaceState(List<Face> faces, CameraImage image) {
    if (faces.isEmpty) return _FaceState.none;
    if (faces.length > 1) return _FaceState.none;

    final face = faces.first;
    final frameW = image.width.toDouble();
    final frameH = image.height.toDouble();
    final box = face.boundingBox;

    // Too far: face bounding box < 15% of frame area
    final faceArea = box.width * box.height;
    final frameArea = frameW * frameH;
    if (faceArea / frameArea < 0.10) return _FaceState.tooFar;

    // Too close: face > 80% of frame
    if (faceArea / frameArea > 0.80) return _FaceState.tooClose;

    // Off center: face center deviates > 35% from frame center
    final faceCx = box.center.dx / frameW;
    final faceCy = box.center.dy / frameH;
    if ((faceCx - 0.5).abs() > 0.35 || (faceCy - 0.5).abs() > 0.35) {
      return _FaceState.offCenter;
    }

    // Low light: sample Y-plane average brightness < 40
    if (Platform.isAndroid && image.planes.isNotEmpty) {
      final yPlane = image.planes[0].bytes;
      final step = yPlane.length ~/ 200;
      if (step > 0) {
        int sum = 0;
        for (int i = 0; i < yPlane.length; i += step) {
          sum += yPlane[i];
        }
        final avg = sum / (yPlane.length / step);
        if (avg < 40) return _FaceState.lowLight;
      }
    }

    return _FaceState.good;
  }


  String get _statusText {
    switch (_faceState) {
      case _FaceState.none:
        return 'Position your face in the oval';
      case _FaceState.tooFar:
        return 'Move closer';
      case _FaceState.tooClose:
        return 'Move further away';
      case _FaceState.offCenter:
        return 'Center your face';
      case _FaceState.lowLight:
        return 'Too dark — find better lighting';
      case _FaceState.good:
        return 'Face locked — tap to capture';
    }
  }

  Color get _stateColor {
    switch (_faceState) {
      case _FaceState.none:
        return Colors.white38;
      case _FaceState.tooFar:
      case _FaceState.tooClose:
      case _FaceState.offCenter:
        return Colors.orangeAccent;
      case _FaceState.lowLight:
        return Colors.yellowAccent;
      case _FaceState.good:
        return Colors.greenAccent;
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

    // Duplicate check
    if (_storageService.nameExists(name.trim())) {
      if (mounted) {
        final overwrite = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0F1A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.5)),
            ),
            title: const Text('Name Already Exists',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 15)),
            content: Text(
              '"${name.trim()}" is already registered.\nOverwrite with new face data?',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Overwrite', style: TextStyle(color: Colors.orangeAccent)),
              ),
            ],
          ),
        );
        if (overwrite != true) {
          _cameraController!.startImageStream(_onFrame);
          return;
        }
        // Delete old entry before saving new one
        final all = _storageService.getAllFaces();
        for (int i = 0; i < all.length; i++) {
          if (all[i].name.toLowerCase().trim() == name.toLowerCase().trim()) {
            await _storageService.deleteFace(i);
            break;
          }
        }
      }
    }

    setState(() => _faceState = _FaceState.none);

    try {
      // Crop from the live CameraImage frame — same coordinate space as ML Kit bounding box.
      // Do NOT use takePicture() JPEG: it is full-res (e.g. 3264x2448) while ML Kit
      // returns coords in stream space (720x480) → wrong crop → garbage embedding.
      final rawFrame = _lastCameraImage;
      if (rawFrame == null) {
        _showError('No camera frame available');
        _cameraController!.startImageStream(_onFrame);
        return;
      }

      final fullImage = _cameraImageToRgbImage(rawFrame);
      if (fullImage == null) {
        _showError('Failed to decode camera frame');
        _cameraController!.startImageStream(_onFrame);
        return;
      }

      final face = _faces.first;
      final box = face.boundingBox;
      // Convert ML Kit display-space bbox → raw sensor space, then rotate crop upright
      final rawBox = _displayBoxToSensorBox(box, fullImage.width, fullImage.height, _lastRotDeg);
      final cx = rawBox.left.toInt().clamp(0, fullImage.width - 1);
      final cy = rawBox.top.toInt().clamp(0, fullImage.height - 1);
      final cw = rawBox.width.toInt().clamp(1, fullImage.width - cx);
      final ch = rawBox.height.toInt().clamp(1, fullImage.height - cy);
      var faceImg = img.copyCrop(fullImage, x: cx, y: cy, width: cw, height: ch);
      if (_lastRotDeg != 0) {
        faceImg = img.copyRotate(faceImg, angle: _lastRotDeg.toDouble());
      }

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

  Rect _displayBoxToSensorBox(Rect displayBox, int rawW, int rawH, int rotDeg) {
    final double l = displayBox.left;
    final double t = displayBox.top;
    final double r = displayBox.right;
    final double b = displayBox.bottom;
    switch (rotDeg) {
      case 90:
        return Rect.fromLTRB(rawW - b, l, rawW - t, r);
      case 180:
        return Rect.fromLTRB(rawW - r, rawH - b, rawW - l, rawH - t);
      case 270:
        return Rect.fromLTRB(t, rawH - r, b, rawH - l);
      default:
        return displayBox;
    }
  }

  img.Image? _cameraImageToRgbImage(CameraImage image) {
    try {
      if (Platform.isAndroid) {
        final yPlane = image.planes[0];
        final uPlane = image.planes[1];
        final vPlane = image.planes[2];
        final width = image.width;
        final height = image.height;
        final rgbImage = img.Image(width: width, height: height);
        final uvPixelStride = uPlane.bytesPerPixel ?? 1;
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final yVal = yPlane.bytes[y * yPlane.bytesPerRow + x] & 0xFF;
            final uvRow = (y ~/ 2) * uPlane.bytesPerRow;
            final uvCol = (x ~/ 2) * uvPixelStride;
            final uVal = (uPlane.bytes[uvRow + uvCol] & 0xFF) - 128;
            final vVal = (vPlane.bytes[(y ~/ 2) * vPlane.bytesPerRow + (x ~/ 2) * (vPlane.bytesPerPixel ?? 1)] & 0xFF) - 128;
            final r = (yVal + 1.370705 * vVal).clamp(0, 255).toInt();
            final g = (yVal - 0.337633 * uVal - 0.698001 * vVal).clamp(0, 255).toInt();
            final b = (yVal + 1.732446 * uVal).clamp(0, 255).toInt();
            rgbImage.setPixel(x, y, img.ColorRgb8(r, g, b));
          }
        }
        return rgbImage;
      } else {
        final plane = image.planes[0];
        final bytes = plane.bytes;
        final width = image.width;
        final height = image.height;
        final rgbImage = img.Image(width: width, height: height);
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final i = y * plane.bytesPerRow + x * 4;
            if (i + 3 >= bytes.length) continue;
            rgbImage.setPixel(x, y, img.ColorRgb8(bytes[i + 2], bytes[i + 1], bytes[i]));
          }
        }
        return rgbImage;
      }
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    _pulseController.dispose();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _detectorService.dispose();
    _embedderService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGood = _faceState == _FaceState.good;

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
        actions: [
          if (_cameras.length > 1)
            IconButton(
              icon: _isSwitchingCamera
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.flip_camera_android_outlined),
              tooltip: 'Switch camera',
              onPressed: _isSwitchingCamera ? null : _switchCamera,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _cameraReady && _cameraController != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_cameraController!),
                      // Mesh overlay + guide oval
                      AnimatedBuilder(
                        animation: Listenable.merge(
                            [_scanAnimController, _pulseController]),
                        builder: (context, child) => CustomPaint(
                          painter: FaceMeshPainter(
                            faces: _faces,
                            imageSize: _imageSize != Size.zero
                                ? _imageSize
                                : Size(
                                    _cameraController!.value.previewSize!.width,
                                    _cameraController!.value.previewSize!.height,
                                  ),
                            isFrontCamera: _cameraController!
                                    .description.lensDirection ==
                                CameraLensDirection.front,
                            animationValue: _scanAnimController.value,
                          ),
                          child: CustomPaint(
                            painter: _FaceGuidePainter(
                              animValue: _scanAnimController.value,
                              pulseValue: _pulseController.value,
                              faceState: _faceState,
                              stateColor: _stateColor,
                              showOval: _faces.isEmpty,
                            ),
                          ),
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
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                children: [
                  // State icon + message row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _stateIcon,
                        color: _stateColor,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusText,
                        style: TextStyle(
                          color: _stateColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Capture button — active only when face is good
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isGood ? _captureAndRegister : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _stateColor,
                        disabledBackgroundColor: Colors.white12,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        isGood ? 'Capture & Register' : 'Align face to enable',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData get _stateIcon {
    switch (_faceState) {
      case _FaceState.none:
        return Icons.face_outlined;
      case _FaceState.tooFar:
        return Icons.zoom_in;
      case _FaceState.tooClose:
        return Icons.zoom_out;
      case _FaceState.offCenter:
        return Icons.center_focus_strong_outlined;
      case _FaceState.lowLight:
        return Icons.wb_sunny_outlined;
      case _FaceState.good:
        return Icons.check_circle_outline;
    }
  }
}

// Guide oval — always visible, color reflects face state
class _FaceGuidePainter extends CustomPainter {
  final double animValue;
  final double pulseValue;
  final _FaceState faceState;
  final Color stateColor;
  final bool showOval;

  const _FaceGuidePainter({
    required this.animValue,
    required this.pulseValue,
    required this.faceState,
    required this.stateColor,
    required this.showOval,
  });

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

    final isGood = faceState == _FaceState.good;
    final ovalAlpha = isGood ? (0.6 + 0.4 * pulseValue) : 0.55;

    // Oval border — color changes with state
    final borderPaint = Paint()
      ..color = stateColor.withValues(alpha: ovalAlpha)
      ..strokeWidth = isGood ? 3.0 : 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawOval(ovalRect, borderPaint);

    // Accent marks
    final markLen = isGood ? 22.0 : 18.0;
    final markPaint = Paint()
      ..color = stateColor
      ..strokeWidth = isGood ? 3.5 : 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - markLen, cy - ry), Offset(cx + markLen, cy - ry), markPaint);
    canvas.drawLine(Offset(cx - markLen, cy + ry), Offset(cx + markLen, cy + ry), markPaint);
    canvas.drawLine(Offset(cx - rx, cy - markLen), Offset(cx - rx, cy + markLen), markPaint);
    canvas.drawLine(Offset(cx + rx, cy - markLen), Offset(cx + rx, cy + markLen), markPaint);

    // Scan line — only when no face yet
    if (showOval) {
      final scanY = (cy - ry) + (ry * 2) * animValue;
      final halfWidth = rx * (1 - ((scanY - cy).abs() / ry).clamp(0.0, 1.0) * 0.6);
      final scanPaint = Paint()
        ..color = stateColor.withValues(alpha: 0.4 + 0.4 * (1 - animValue))
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(cx - halfWidth, scanY), Offset(cx + halfWidth, scanY), scanPaint);

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
  }

  @override
  bool shouldRepaint(_FaceGuidePainter old) =>
      old.animValue != animValue ||
      old.pulseValue != pulseValue ||
      old.faceState != faceState ||
      old.showOval != showOval;
}
