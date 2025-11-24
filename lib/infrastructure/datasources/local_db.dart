import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/entities/alarm_log.dart';

class LocalDatabase {
  static const String _alarmBoxName = 'alarms';
  static const String _logBoxName = 'alarm_logs';

  static Future<void> init() async {
    await Hive.initFlutter();

    // Hive 어댑터 등록
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(AlarmAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AlarmLogAdapter());
    }

    // 박스 열기
    await Hive.openBox<Alarm>(_alarmBoxName);
    await Hive.openBox<AlarmLog>(_logBoxName);
  }

  static Box<Alarm> get alarmBox => Hive.box<Alarm>(_alarmBoxName);
  static Box<AlarmLog> get logBox => Hive.box<AlarmLog>(_logBoxName);

  // 알람 저장
  static Future<void> saveAlarm(Alarm alarm) async {
    await alarmBox.put(alarm.id, alarm);
  }

  // 모든 알람 가져오기
  static List<Alarm> getAllAlarms() {
    return alarmBox.values.toList();
  }

  // 알람 삭제 (원본 알람 삭제 시 관련 스누즈 알람도 함께 삭제)
  static Future<void> deleteAlarm(String id) async {
    // 원본 알람 삭제
    await alarmBox.delete(id);
    
    // 해당 알람의 스누즈 알람도 찾아서 삭제
    // 방법 1: label 형식으로 찾기 (기존 방식)
    final snoozePrefix = '__SNOOZE__:$id';
    // 방법 2: originalAlarmIndex로 찾기 (새로운 방식)
    final allAlarms = alarmBox.values.toList();
    for (var alarm in allAlarms) {
      // label 또는 originalAlarmIndex로 원본 알람과 연결된 스누즈 알람 찾기
      if (alarm.label == snoozePrefix || alarm.originalAlarmIndex == id) {
        await alarmBox.delete(alarm.id);
      }
    }
  }

  // 알람 로그 저장
  static Future<void> saveAlarmLog(AlarmLog log) async {
    await logBox.put(log.id, log);
  }

  // 모든 알람 로그 가져오기
  static List<AlarmLog> getAllAlarmLogs() {
    return logBox.values.toList();
  }

  // 특정 알람의 로그 가져오기
  static List<AlarmLog> getAlarmLogs(String alarmId) {
    return logBox.values.where((log) => log.alarmId == alarmId).toList();
  }
}
