import '../../domain/repositories/alarm_repository.dart';
import '../../infrastructure/services/alarm_scheduler.dart';

class CancelAlarmUseCase {
  final AlarmRepository repository;

  CancelAlarmUseCase(this.repository);

  Future<void> execute(String alarmId) async {
    await repository.deleteAlarm(alarmId);
    await AlarmScheduler.cancelAlarm(alarmId);
  }
}

