import 'dart:io';
import 'dart:typed_data';
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

    // On Android, camera stream is NV21; on iOS it's BGRA8888
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

  InputImage _buildNv21InputImage(CameraImage image, InputImageRotation rotation) {
    // Concatenate YUV planes into NV21 byte array
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final int ySize = yPlane.bytes.length;
    final int uvSize = uPlane.bytes.length + vPlane.bytes.length;
    final nv21 = List<int>.filled(ySize + uvSize, 0);

    // Copy Y plane
    nv21.setRange(0, ySize, yPlane.bytes);

    // Interleave V and U (NV21 = Y + VU interleaved)
    int offset = ySize;
    for (int i = 0; i < vPlane.bytes.length; i++) {
      nv21[offset++] = vPlane.bytes[i];
      if (i < uPlane.bytes.length) nv21[offset++] = uPlane.bytes[i];
    }

    return InputImage.fromBytes(
      bytes: Uint8List.fromList(nv21),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: yPlane.bytesPerRow,
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
