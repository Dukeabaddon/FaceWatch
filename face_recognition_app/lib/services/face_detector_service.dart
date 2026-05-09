import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;
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
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
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

  /// Returns the clockwise degrees the sensor image must be rotated to appear upright.
  /// Use this to rotate a face crop before feeding to MobileFaceNet.
  int getRotationDegrees(CameraDescription camera, DeviceOrientation deviceOrientation) {
    int deviceDeg;
    switch (deviceOrientation) {
      case DeviceOrientation.portraitUp:    deviceDeg = 0;   break;
      case DeviceOrientation.landscapeLeft: deviceDeg = 90;  break;
      case DeviceOrientation.portraitDown:  deviceDeg = 180; break;
      case DeviceOrientation.landscapeRight:deviceDeg = 270; break;
    }
    if (Platform.isIOS) return 0;
    return (camera.sensorOrientation - deviceDeg + 360) % 360;
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

    if (Platform.isIOS) {
      // iOS: rotation is always 0 — AVFoundation handles orientation
      rotationDeg = 0;
    } else if (camera.lensDirection == CameraLensDirection.front) {
      // Android front camera: mirror compensation
      rotationDeg = (sensorDeg - deviceDeg + 360) % 360;
    } else {
      // Android back camera
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
    // Convert YUV420 planes to NV21 format (Y plane + interleaved VU)
    // NV21 = Y bytes followed by interleaved V,U bytes
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = width * height ~/ 2;
    final nv21 = List<int>.filled(ySize + uvSize, 0);

    // Copy Y plane row by row (handle stride)
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    int pos = 0;
    for (int row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      for (int col = 0; col < width; col++) {
        nv21[pos++] = yPlane.bytes[rowStart + col];
      }
    }

    // Interleave V and U for NV21 (V first, then U)
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    for (int row = 0; row < height ~/ 2; row++) {
      for (int col = 0; col < width ~/ 2; col++) {
        final vIdx = row * vPlane.bytesPerRow + col * (vPlane.bytesPerPixel ?? 1);
        final uIdx = row * uvRowStride + col * uvPixelStride;
        nv21[pos++] = vPlane.bytes[vIdx]; // V
        nv21[pos++] = uPlane.bytes[uIdx]; // U
      }
    }

    return InputImage.fromBytes(
      bytes: Uint8List.fromList(nv21),
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: width,
      ),
    );
  }

}
