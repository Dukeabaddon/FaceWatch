import 'dart:async';
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
      imageFormatGroup: ImageFormatGroup.bgra8888,
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

      if (faces.isEmpty) {
        if (mounted) setState(() { _faces = []; _labels = []; });
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
            final faceImg = img.copyCrop(
              fullImg,
              x: box.left.toInt().clamp(0, fullImg.width - 1),
              y: box.top.toInt().clamp(0, fullImg.height - 1),
              width: box.width.toInt().clamp(1, fullImg.width),
              height: box.height.toInt().clamp(1, fullImg.height),
            );

            final embedding = _embedderService.getEmbedding(faceImg);
            if (embedding != null) {
              final match = FaceEmbedderService.findBestMatch(
                embedding,
                knownFaces,
              );
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

  img.Image? _cameraImageToRgbImage(CameraImage image) {
    try {
      final plane = image.planes[0];
      final bytes = plane.bytes;
      final width = image.width;
      final height = image.height;

      final rgbImage = img.Image(width: width, height: height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixelIndex = y * plane.bytesPerRow + x * 4;
          if (pixelIndex + 3 >= bytes.length) continue;
          final b = bytes[pixelIndex];
          final g = bytes[pixelIndex + 1];
          final r = bytes[pixelIndex + 2];
          final a = bytes[pixelIndex + 3];
          rgbImage.setPixel(x, y, img.ColorRgba8(r, g, b, a));
        }
      }
      return rgbImage;
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
                  imageSize: Size(
                    _cameraController!.value.previewSize!.height,
                    _cameraController!.value.previewSize!.width,
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
