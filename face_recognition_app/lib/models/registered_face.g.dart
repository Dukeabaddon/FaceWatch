// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'registered_face.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RegisteredFaceAdapter extends TypeAdapter<RegisteredFace> {
  @override
  final int typeId = 0;

  @override
  RegisteredFace read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RegisteredFace(
      name: fields[0] as String,
      embedding: (fields[1] as List).cast<double>(),
      registeredAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, RegisteredFace obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.embedding)
      ..writeByte(2)
      ..write(obj.registeredAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisteredFaceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
