import 'dart:math';
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
    return _normalize(embedding);
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
