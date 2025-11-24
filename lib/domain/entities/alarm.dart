import 'package:hive/hive.dart';
import 'weekday.dart';

part 'alarm.g.dart';

@HiveType(typeId: 0)
class Alarm extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String time; // "07:30"

  @HiveField(2)
  List<int> repeat; // Weekday values

  @HiveField(3)
  String label;

  @HiveField(4)
  String sound; // uri or asset path

  @HiveField(5)
  bool vibrate;

  @HiveField(6)
  int snoozeMinutes;

  @HiveField(7)
  bool enabled;

  @HiveField(8)
  String? originalAlarmIndex; // 원본 알람의 index (스누즈 알람인 경우)

  Alarm({
    required this.id,
    required this.time,
    required this.repeat,
    this.label = '',
    this.sound = 'default',
    this.vibrate = true,
    this.snoozeMinutes = 5,
    this.enabled = true,
    this.originalAlarmIndex,
  });

  Set<Weekday> get repeatWeekdays {
    return repeat
        .map((v) => Weekday.values.firstWhere((w) => w.value == v))
        .toSet();
  }

  set repeatWeekdays(Set<Weekday> weekdays) {
    repeat = weekdays.map((w) => w.value).toList();
  }

  Alarm copyWith({
    String? id,
    String? time,
    List<int>? repeat,
    String? label,
    String? sound,
    bool? vibrate,
    int? snoozeMinutes,
    bool? enabled,
    String? originalAlarmIndex,
  }) {
    return Alarm(
      id: id ?? this.id,
      time: time ?? this.time,
      repeat: repeat ?? this.repeat,
      label: label ?? this.label,
      sound: sound ?? this.sound,
      vibrate: vibrate ?? this.vibrate,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      enabled: enabled ?? this.enabled,
      originalAlarmIndex: originalAlarmIndex ?? this.originalAlarmIndex,
    );
  }
}
