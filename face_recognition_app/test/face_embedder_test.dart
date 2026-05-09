import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:face_recognition_app/services/face_embedder_service.dart';

void main() {
  group('FaceEmbedderService - cosineSimilarity', () {
    test('identical vectors return 1.0', () {
      final v = [1.0, 0.0, 0.0];
      expect(FaceEmbedderService.cosineSimilarity(v, v), closeTo(1.0, 1e-6));
    });

    test('orthogonal vectors return 0.0', () {
      final a = [1.0, 0.0];
      final b = [0.0, 1.0];
      expect(FaceEmbedderService.cosineSimilarity(a, b), closeTo(0.0, 1e-6));
    });

    test('opposite vectors return -1.0', () {
      final a = [1.0, 0.0];
      final b = [-1.0, 0.0];
      expect(FaceEmbedderService.cosineSimilarity(a, b), closeTo(-1.0, 1e-6));
    });
  });

  group('FaceEmbedderService - findBestMatch', () {
    test('returns null when known list empty', () {
      final q = [1.0, 0.0, 0.0];
      final result = FaceEmbedderService.findBestMatch(q, []);
      expect(result, isNull);
    });

    test('matches identical embedding above threshold', () {
      final emb = [1.0, 0.0, 0.0];
      final known = [(name: 'Alice', embedding: emb)];
      final result = FaceEmbedderService.findBestMatch(emb, known);
      expect(result, isNotNull);
      expect(result!.name, 'Alice');
      expect(result.similarity, closeTo(1.0, 1e-6));
    });

    test('returns null for unrelated embedding below threshold', () {
      final q = [1.0, 0.0, 0.0];
      final known = [(name: 'Bob', embedding: [0.0, 1.0, 0.0])];
      final result = FaceEmbedderService.findBestMatch(q, known,
          threshold: 0.65);
      expect(result, isNull);
    });

    test('picks best match among multiple known faces', () {
      final alice = [1.0, 0.0, 0.0];
      final bob = [0.0, 1.0, 0.0];
      final query = [0.98, 0.1, 0.0];

      final mag = sqrt(query.fold(0.0, (s, e) => s + e * e));
      final normQuery = query.map((e) => e / mag).toList();

      final known = [
        (name: 'Alice', embedding: alice),
        (name: 'Bob', embedding: bob),
      ];
      final result = FaceEmbedderService.findBestMatch(normQuery, known,
          threshold: 0.5);
      expect(result, isNotNull);
      expect(result!.name, 'Alice');
    });
  });
}
