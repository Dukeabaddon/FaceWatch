import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceEmbedderService {
  static const int _inputSize = 112;
  static const int _embeddingSize = 192;
  static const String _modelPath = 'assets/models/mobilefacenet.tflite';

  Interpreter? _interpreter;

  Future<void> init() async {
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  /// Converts raw CameraImage to an UPRIGHT RGB image matching ML Kit display coords.
  /// Pipeline: YUV420 (Android) or BGRA (iOS) → RGB → rotate by rotDeg → upright.
  /// After this, ML Kit display bbox maps 1:1 to the returned image (no coord transform).
  static img.Image? cameraImageToUprightRgb(CameraImage image, int rotDeg) {
    img.Image? raw;
    try {
      if (Platform.isAndroid) {
        final y = image.planes[0];
        final u = image.planes[1];
        final v = image.planes[2];
        final w = image.width;
        final h = image.height;
        raw = img.Image(width: w, height: h);
        final uvPx = u.bytesPerPixel ?? 1;
        for (int j = 0; j < h; j++) {
          for (int i = 0; i < w; i++) {
            final yVal = y.bytes[j * y.bytesPerRow + i] & 0xFF;
            final uIdx = (j ~/ 2) * u.bytesPerRow + (i ~/ 2) * uvPx;
            final vIdx = (j ~/ 2) * v.bytesPerRow + (i ~/ 2) * (v.bytesPerPixel ?? 1);
            final uV = (u.bytes[uIdx] & 0xFF) - 128;
            final vV = (v.bytes[vIdx] & 0xFF) - 128;
            final r = (yVal + 1.370705 * vV).clamp(0, 255).toInt();
            final g = (yVal - 0.337633 * uV - 0.698001 * vV).clamp(0, 255).toInt();
            final b = (yVal + 1.732446 * uV).clamp(0, 255).toInt();
            raw.setPixel(i, j, img.ColorRgb8(r, g, b));
          }
        }
      } else {
        final p = image.planes[0];
        final bytes = p.bytes;
        final w = image.width;
        final h = image.height;
        raw = img.Image(width: w, height: h);
        for (int j = 0; j < h; j++) {
          for (int i = 0; i < w; i++) {
            final k = j * p.bytesPerRow + i * 4;
            if (k + 3 >= bytes.length) continue;
            raw.setPixel(i, j, img.ColorRgb8(bytes[k + 2], bytes[k + 1], bytes[k]));
          }
        }
      }
    } catch (_) {
      return null;
    }
    if (rotDeg == 0) return raw;
    // img.copyRotate angle is clockwise positive in image package 4.x
    return img.copyRotate(raw, angle: rotDeg);
  }

  /// Crops the face from an upright RGB image using display-space bbox.
  /// Returns null if crop would be too small.
  static img.Image? cropFaceFromUpright(img.Image upright, Rect displayBbox) {
    final x = displayBbox.left.toInt().clamp(0, upright.width - 1);
    final y = displayBbox.top.toInt().clamp(0, upright.height - 1);
    final w = displayBbox.width.toInt().clamp(1, upright.width - x);
    final h = displayBbox.height.toInt().clamp(1, upright.height - y);
    if (w < 20 || h < 20) return null; // reject tiny crops
    return img.copyCrop(upright, x: x, y: y, width: w, height: h);
  }

  /// Extract a 192-d embedding from a cropped face image (img.Image).
  List<double>? getEmbedding(img.Image faceImage) {
    if (_interpreter == null) return null;

    final resized = img.copyResize(
      faceImage,
      width: _inputSize,
      height: _inputSize,
    );

    final input = _imageToInputTensor(resized);
    final output = List.filled(_embeddingSize, 0.0).reshape([1, _embeddingSize]);

    _interpreter!.run(input, output);

    final embedding = List<double>.from(output[0] as List);
    final normalized = _normalize(embedding);
    // Diagnostic: log first 4 values + L2 norm check. Healthy embedding should
    // have varied non-zero values. All-zero or constant = input corruption.
    final sumAbs = normalized.fold<double>(0, (s, e) => s + e.abs());
    // ignore: avoid_print
    print('[Embed] crop=${faceImage.width}x${faceImage.height} L1=${sumAbs.toStringAsFixed(2)} sample=${normalized.take(4).map((e) => e.toStringAsFixed(3)).toList()}');
    return normalized;
  }

  List<List<List<List<double>>>> _imageToInputTensor(img.Image image) {
    return List.generate(1, (_) {
      return List.generate(_inputSize, (y) {
        return List.generate(_inputSize, (x) {
          final pixel = image.getPixel(x, y);
          return [
            (pixel.r / 127.5) - 1.0,
            (pixel.g / 127.5) - 1.0,
            (pixel.b / 127.5) - 1.0,
          ];
        });
      });
    });
  }

  List<double> _normalize(List<double> v) {
    double norm = sqrt(v.fold(0.0, (sum, e) => sum + e * e));
    if (norm == 0) return v;
    return v.map((e) => e / norm).toList();
  }

  /// Cosine similarity between two embeddings (higher = more similar).
  static double cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  /// Returns name + similarity if match above threshold, else null.
  static ({String name, double similarity})? findBestMatch(
    List<double> queryEmbedding,
    List<({String name, List<double> embedding})> known, {
    double threshold = 0.75,
  }) {
    if (known.isEmpty) return null;

    double bestSim = -1;
    String bestName = '';

    for (final face in known) {
      final sim = cosineSimilarity(queryEmbedding, face.embedding);
      if (sim > bestSim) {
        bestSim = sim;
        bestName = face.name;
      }
    }

    // ignore: avoid_print
    print('[Embed] bestSim=$bestSim name=$bestName threshold=$threshold');
    if (bestSim >= threshold) {
      return (name: bestName, similarity: bestSim);
    }
    return null;
  }
}
