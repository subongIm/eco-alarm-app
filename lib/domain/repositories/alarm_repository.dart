import '../entities/alarm.dart';
import '../entities/alarm_log.dart';

abstract class AlarmRepository {
  Future<List<Alarm>> getAllAlarms();
  Future<Alarm?> getAlarmById(String id);
  Future<void> saveAlarm(Alarm alarm);
  Future<void> deleteAlarm(String id);
  Future<void> toggleAlarm(String id, bool enabled);
  
  Future<List<AlarmLog>> getAlarmLogs(String alarmId);
  Future<void> saveAlarmLog(AlarmLog log);
}

