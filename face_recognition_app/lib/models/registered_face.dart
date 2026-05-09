import 'package:hive/hive.dart';

part 'registered_face.g.dart';

@HiveType(typeId: 0)
class RegisteredFace extends HiveObject {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final List<double> embedding;

  @HiveField(2)
  final DateTime registeredAt;

  RegisteredFace({
    required this.name,
    required this.embedding,
    required this.registeredAt,
  });
}
