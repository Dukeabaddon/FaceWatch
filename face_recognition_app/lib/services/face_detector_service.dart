import 'dart:ui' show Size;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';

class FaceDetectorService {
  late final FaceDetector _faceDetector;
  late final FaceDetector _contourDetector;

  void init() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: false,
        enableLandmarks: false,
        enableContours: false,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    _contourDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: false,
        enableLandmarks: true,
        enableContours: true,
        enableTracking: false,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
  }

  void dispose() {
    _faceDetector.close();
    _contourDetector.close();
  }

  Future<List<Face>> detectFaces(InputImage inputImage) async {
    return await _faceDetector.processImage(inputImage);
  }

  Future<List<Face>> detectFacesWithContours(InputImage inputImage) async {
    return await _contourDetector.processImage(inputImage);
  }

  InputImage? inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera,
    int sensorOrientation,
  ) {
    final rotation = _getRotation(camera.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _getRotation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return null;
    }
  }
}
