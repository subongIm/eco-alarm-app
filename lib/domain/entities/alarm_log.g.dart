// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alarm_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AlarmLogAdapter extends TypeAdapter<AlarmLog> {
  @override
  final int typeId = 1;

  @override
  AlarmLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AlarmLog(
      id: fields[0] as String,
      alarmId: fields[1] as String,
      firedAt: fields[2] as DateTime,
      action: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, AlarmLog obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.alarmId)
      ..writeByte(2)
      ..write(obj.firedAt)
      ..writeByte(3)
      ..write(obj.action);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlarmLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
