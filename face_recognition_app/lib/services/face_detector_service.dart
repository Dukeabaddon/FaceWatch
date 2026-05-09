import 'dart:io';
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart' show WriteBuffer;
import 'package:flutter/services.dart' show DeviceOrientation;
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
    DeviceOrientation deviceOrientation,
  ) {
    final rotation = _getImageRotation(camera, deviceOrientation);
    if (rotation == null) return null;

    if (Platform.isAndroid) {
      return _buildNv21InputImage(image, rotation);
    }

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

  InputImageRotation? _getImageRotation(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    // Map device orientation to degrees
    int deviceDeg;
    switch (deviceOrientation) {
      case DeviceOrientation.portraitUp:
        deviceDeg = 0;
        break;
      case DeviceOrientation.landscapeLeft:
        deviceDeg = 90;
        break;
      case DeviceOrientation.portraitDown:
        deviceDeg = 180;
        break;
      case DeviceOrientation.landscapeRight:
        deviceDeg = 270;
        break;
    }

    final sensorDeg = camera.sensorOrientation;
    int rotationDeg;

    if (camera.lensDirection == CameraLensDirection.front) {
      // Front camera: sensor is mirrored
      rotationDeg = (sensorDeg + deviceDeg) % 360;
    } else {
      // Back camera
      rotationDeg = (sensorDeg - deviceDeg + 360) % 360;
    }

    switch (rotationDeg) {
      case 0:   return InputImageRotation.rotation0deg;
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return null;
    }
  }

  InputImage _buildNv21InputImage(CameraImage image, InputImageRotation rotation) {
    // Concat all YUV planes — official google_mlkit pattern for Android yuv420.
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.yuv_420_888,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

}
