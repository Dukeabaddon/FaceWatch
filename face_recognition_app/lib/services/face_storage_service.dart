import 'package:hive_flutter/hive_flutter.dart';
import '../models/registered_face.dart';

class FaceStorageService {
  static const String _boxName = 'registered_faces';
  late Box<RegisteredFace> _box;

  Future<void> init() async {
    _box = await Hive.openBox<RegisteredFace>(_boxName);
  }

  List<RegisteredFace> getAllFaces() {
    return _box.values.toList();
  }

  Future<void> saveFace(RegisteredFace face) async {
    await _box.add(face);
  }

  Future<void> deleteFace(int index) async {
    await _box.deleteAt(index);
  }

  Future<void> clearAll() async {
    await _box.clear();
  }

  int get count => _box.length;
}
