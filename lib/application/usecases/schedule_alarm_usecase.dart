import '../../domain/entities/alarm.dart';
import '../../domain/repositories/alarm_repository.dart';
import '../../infrastructure/services/alarm_scheduler.dart';

class ScheduleAlarmUseCase {
  final AlarmRepository repository;

  ScheduleAlarmUseCase(this.repository);

  Future<void> execute(Alarm alarm) async {
    await repository.saveAlarm(alarm);
    await AlarmScheduler.scheduleAlarm(alarm);
  }
}

