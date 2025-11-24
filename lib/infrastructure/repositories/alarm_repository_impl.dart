import '../../domain/entities/alarm.dart';
import '../../domain/entities/alarm_log.dart';
import '../../domain/repositories/alarm_repository.dart';
import '../datasources/local_db.dart';

class AlarmRepositoryImpl implements AlarmRepository {
  @override
  Future<List<Alarm>> getAllAlarms() async {
    final box = LocalDatabase.alarmBox;
    return box.values.toList();
  }

  @override
  Future<Alarm?> getAlarmById(String id) async {
    final box = LocalDatabase.alarmBox;
    return box.get(id);
  }

  @override
  Future<void> saveAlarm(Alarm alarm) async {
    final box = LocalDatabase.alarmBox;
    await box.put(alarm.id, alarm);
  }

  @override
  Future<void> deleteAlarm(String id) async {
    final box = LocalDatabase.alarmBox;
    await box.delete(id);
  }

  @override
  Future<void> toggleAlarm(String id, bool enabled) async {
    final alarm = await getAlarmById(id);
    if (alarm != null) {
      final updated = alarm.copyWith(enabled: enabled);
      await saveAlarm(updated);
    }
  }

  @override
  Future<List<AlarmLog>> getAlarmLogs(String alarmId) async {
    final box = LocalDatabase.logBox;
    return box.values.where((log) => log.alarmId == alarmId).toList();
  }

  @override
  Future<void> saveAlarmLog(AlarmLog log) async {
    final box = LocalDatabase.logBox;
    await box.put(log.id, log);
  }
}

