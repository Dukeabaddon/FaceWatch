import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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

  // Snapshot-based identification state
  Timer? _identifyTimer;
  bool _isIdentifying = false;
  String _statusLabel = 'Scanning...';
  String? _lastDebugCropPath;

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
    // Start the periodic identification loop
    _identifyTimer?.cancel();
    _identifyTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _identifyTick(),
    );
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

      if (faces.isEmpty) {
        if (mounted) setState(() { _faces = []; _labels = []; _imageSize = sensorSize; });
        return;
      }

      // Stream pipeline is ONLY responsible for the mesh overlay + face count.
      // Identification happens in _identifyTick (snapshot-based) every 1.5s.
      // The _labels list is kept in sync with _faces so the painter can show
      // the last identified label beside each detected face.
      final labels = List<String?>.filled(faces.length, _statusLabel);
      if (mounted) {
        setState(() {
          _faces = faces;
          _labels = labels;
          _imageSize = sensorSize;
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Snapshot-based identification: pause stream, take a JPEG, run full
  /// ML-Kit-on-file + MobileFaceNet pipeline, show result, resume stream.
  Future<void> _identifyTick() async {
    if (!mounted) return;
    if (_isIdentifying) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_faces.isEmpty) return; // only identify when a face is visible

    _isIdentifying = true;
    try {
      // Pause stream briefly
      try { await _cameraController!.stopImageStream(); } catch (_) {}

      final xFile = await _cameraController!.takePicture();
      debugPrint('[Identify] jpeg: ${xFile.path}');

      final result = await _embedderService.embedFromJpegFile(
        xFile.path,
        _detectorService,
        tag: 'recognize',
      );

      String label;
      if (result.faceCount == 0) {
        label = 'No face';
      } else if (result.embedding == null) {
        label = 'Error';
      } else {
        final known = _storageService.getAllFaces().map((f) => (
          name: f.name,
          embedding: f.embedding,
        )).toList();
        if (known.isEmpty) {
          label = 'No registered faces';
        } else {
          final match = FaceEmbedderService.findBestMatch(
            result.embedding!,
            known,
          );
          if (match != null) {
            label = '${match.name} ${(match.similarity * 100).toStringAsFixed(0)}%';
            debugPrint('[Identify] MATCH: ${match.name} sim=${match.similarity.toStringAsFixed(3)}');
          } else {
            label = 'Unknown';
            debugPrint('[Identify] NO MATCH');
          }
        }
      }

      if (mounted) {
        setState(() {
          _statusLabel = label;
          _lastDebugCropPath = result.debugPath;
          // update label overlay for the single face we care about
          _labels = List<String?>.filled(_faces.length, label);
        });
        _triggerFeedback([label]);
      }
    } catch (e) {
      debugPrint('[Identify] error: $e');
    } finally {
      // Resume stream
      try {
        if (mounted && _cameraController != null && _cameraController!.value.isInitialized) {
          await _cameraController!.startImageStream(_onFrame);
        }
      } catch (_) {}
      _isIdentifying = false;
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


  @override
  void dispose() {
    _identifyTimer?.cancel();
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
          // Debug: status bar + last face crop thumbnail
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  if (_lastDebugCropPath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(_lastDebugCropPath!),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (ctx, err, st) => Container(
                          width: 64,
                          height: 64,
                          color: Colors.white10,
                          child: const Icon(Icons.image_not_supported,
                              color: Colors.white24, size: 20),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.hourglass_empty,
                          color: Colors.white24, size: 20),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _statusLabel,
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isIdentifying
                              ? 'Capturing...'
                              : (_faces.isEmpty
                                  ? 'Point at a face'
                                  : 'Next ID in ~1.5s'),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
