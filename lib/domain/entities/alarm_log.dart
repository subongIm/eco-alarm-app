import 'package:hive/hive.dart';

part 'alarm_log.g.dart';

@HiveType(typeId: 1)
class AlarmLog extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String alarmId;

  @HiveField(2)
  final DateTime firedAt;

  @HiveField(3)
  final String action; // "dismiss" | "snooze"

  AlarmLog({
    required this.id,
    required this.alarmId,
    required this.firedAt,
    required this.action,
  });
}

