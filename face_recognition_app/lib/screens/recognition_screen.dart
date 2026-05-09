import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:vibration/vibration.dart';
import '../services/face_detector_service.dart';
import '../services/face_embedder_service.dart';
import '../services/face_storage_service.dart';
import '../painters/face_mesh_painter.dart';

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  final FaceDetectorService _detectorService = FaceDetectorService();
  final FaceEmbedderService _embedderService = FaceEmbedderService();
  final FaceStorageService _storageService = FaceStorageService();

  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isSwitchingCamera = false;
  // ignore: prefer_final_fields
  DeviceOrientation _deviceOrientation = DeviceOrientation.portraitUp;

  Size _imageSize = Size.zero;
  List<Face> _faces = [];
  List<String?> _labels = [];
  bool _isProcessing = false;
  bool _cameraReady = false;
  int _registeredCount = 0;
  String? _lastFeedbackLabel;
  DateTime _lastFeedbackTime = DateTime.fromMillisecondsSinceEpoch(0);

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
    setState(() => _registeredCount = _storageService.count);
    await _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    _cameraIndex = _cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    if (_cameraIndex < 0) _cameraIndex = 0;
    await _startCamera(_cameraIndex);
  }

  Future<void> _startCamera(int index) async {
    setState(() { _cameraReady = false; _faces = []; _labels = []; });
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
        image,
        camera,
        _deviceOrientation,
      );
      if (inputImage == null) return;

      final faces = await _detectorService.detectFacesWithContours(inputImage);
      // Swap W/H: sensor landscape 720x480, but display is portrait after 90deg rotation
      final sensorSize = Size(image.height.toDouble(), image.width.toDouble());
      // Degrees to rotate raw sensor crop → upright face for MobileFaceNet
      final rotDeg = _detectorService.getRotationDegrees(camera, _deviceOrientation);

      if (faces.isEmpty) {
        if (mounted) setState(() { _faces = []; _labels = []; _imageSize = sensorSize; });
        return;
      }

      final knownFaces = _storageService.getAllFaces().map((f) => (
        name: f.name,
        embedding: f.embedding,
      )).toList();

      final labels = <String?>[];

      if (knownFaces.isNotEmpty) {
        final fullImg = _cameraImageToRgbImage(image);
        if (fullImg != null) {
          for (final face in faces) {
            final box = face.boundingBox;
            // ML Kit bbox is in DISPLAY (rotated) space.
            // _cameraImageToRgbImage gives RAW sensor landscape image.
            // Must convert bbox from display space → raw sensor space before crop.
            final rawBox = _displayBoxToSensorBox(box, fullImg.width, fullImg.height, rotDeg);
            final x = rawBox.left.toInt().clamp(0, fullImg.width - 1);
            final y = rawBox.top.toInt().clamp(0, fullImg.height - 1);
            final w = rawBox.width.toInt().clamp(1, fullImg.width - x);
            final h = rawBox.height.toInt().clamp(1, fullImg.height - y);
            var faceImg = img.copyCrop(fullImg, x: x, y: y, width: w, height: h);
            // Rotate crop upright so MobileFaceNet receives a frontal face
            if (rotDeg != 0) {
              faceImg = img.copyRotate(faceImg, angle: rotDeg.toDouble());
            }

            final embedding = _embedderService.getEmbedding(faceImg);
            if (embedding != null) {
              final match = FaceEmbedderService.findBestMatch(
                embedding,
                knownFaces,
              );
              if (match != null) {
                debugPrint('[Recognize] MATCH: ${match.name} sim=${match.similarity.toStringAsFixed(3)}');
              } else {
                debugPrint('[Recognize] NO MATCH (best below threshold)');
              }
              labels.add(match != null
                  ? '${match.name} ${(match.similarity * 100).toStringAsFixed(0)}%'
                  : 'Unknown');
            } else {
              labels.add(null);
            }
          }
        }
      } else {
        for (int i = 0; i < faces.length; i++) {
          labels.add(null);
        }
      }

      if (mounted) {
        setState(() {
          _faces = faces;
          _labels = labels;
          _imageSize = sensorSize;
        });
        _triggerFeedback(labels);
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _triggerFeedback(List<String?> labels) async {
    if (labels.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastFeedbackTime).inMilliseconds < 2000) return;

    final topLabel = labels.first;
    if (topLabel == null || topLabel == _lastFeedbackLabel) return;

    _lastFeedbackLabel = topLabel;
    _lastFeedbackTime = now;

    final isMatch = topLabel != 'Unknown';
    final vibratorResult = await Vibration.hasVibrator();
    final hasVibrator = vibratorResult == true;

    if (isMatch) {
      HapticFeedback.mediumImpact();
      if (hasVibrator) {
        Vibration.vibrate(pattern: [0, 80, 60, 80]);
      }
    } else {
      HapticFeedback.lightImpact();
      if (hasVibrator) {
        Vibration.vibrate(duration: 200);
      }
    }
  }

  /// Convert bbox from ML Kit display/rotated space back to raw sensor space.
  /// rawW/rawH are the sensor image dimensions (e.g. 720x480).
  /// rotDeg is the clockwise rotation applied by ML Kit (e.g. 270).
  Rect _displayBoxToSensorBox(Rect displayBox, int rawW, int rawH, int rotDeg) {
    // ML Kit applies rotation so the display coords are in portrait space.
    // We need to reverse that to get raw landscape sensor coords.
    final double l = displayBox.left;
    final double t = displayBox.top;
    final double r = displayBox.right;
    final double b = displayBox.bottom;
    switch (rotDeg) {
      case 90:
        // display(x,y) = sensor(y, rawW-x) → reverse: sensor_x=rawW-displayY, sensor_y=displayX
        return Rect.fromLTRB(rawW - b, l, rawW - t, r);
      case 180:
        return Rect.fromLTRB(rawW - r, rawH - b, rawW - l, rawH - t);
      case 270:
        // display(x,y) = sensor(rawH-y, x) → reverse: sensor_x=displayY, sensor_y=rawH-displayX
        return Rect.fromLTRB(t, rawH - r, b, rawH - l);
      default: // 0
        return displayBox;
    }
  }

  img.Image? _cameraImageToRgbImage(CameraImage image) {
    try {
      if (Platform.isAndroid) {
        // YUV420: plane[0]=Y, plane[1]=U, plane[2]=V
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
        // iOS BGRA8888: plane[0] has full interleaved BGRA
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
          'Recognize',
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
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '$_registeredCount registered',
                style: TextStyle(
                  color: Colors.cyanAccent.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraReady && _cameraController != null)
            CameraPreview(_cameraController!)
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            ),
          if (_cameraReady && _cameraController != null)
            AnimatedBuilder(
              animation: _scanAnimController,
              builder: (context, child) => CustomPaint(
                painter: FaceMeshPainter(
                  faces: _faces,
                  imageSize: _imageSize != Size.zero
                      ? _imageSize
                      : Size(
                          _cameraController!.value.previewSize!.width,
                          _cameraController!.value.previewSize!.height,
                        ),
                  isFrontCamera: _cameraController!.description.lensDirection ==
                      CameraLensDirection.front,
                  animationValue: _scanAnimController.value,
                  labels: _labels,
                ),
              ),
            ),
          if (_registeredCount == 0)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'No faces registered yet.\nGo to Register Face first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
