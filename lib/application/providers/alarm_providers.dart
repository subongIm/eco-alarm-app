import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/repositories/alarm_repository.dart';
import '../../domain/entities/alarm.dart';
import '../../infrastructure/repositories/alarm_repository_impl.dart';
import '../../infrastructure/services/alarm_scheduler.dart';

// 리포지토리 Provider
final alarmRepositoryProvider = Provider<AlarmRepository>((ref) {
  return AlarmRepositoryImpl();
});

// 알람 상태 관리 StateNotifier
class AlarmNotifier extends StateNotifier<AsyncValue<List<Alarm>>> {
  final AlarmRepository _repository;

  AlarmNotifier(this._repository) : super(const AsyncValue.loading()) {
    _loadAlarms();
  }

  // 알람 리스트 로드
  Future<void> _loadAlarms() async {
    try {
      state = const AsyncValue.loading();
      final all = await _repository.getAllAlarms();
      // 스누즈 알람은 라벨 접두사 '__SNOOZE__'로 식별하여 목록에서 숨김
      final filtered = all.where((a) => !(a.label.startsWith('__SNOOZE__'))).toList();
      state = AsyncValue.data(filtered);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  // 알람 생성 (스케줄러 자동 등록)
  Future<void> createAlarm(Alarm alarm) async {
    try {
      // 1. 데이터베이스에 저장
      await _repository.saveAlarm(alarm);
      
      // 2. 스케줄러에 등록 (enabled인 경우만)
      if (alarm.enabled) {
        await AlarmScheduler.scheduleAlarm(alarm);
      }
      
      // 3. 리스트 새로고침
      await _loadAlarms();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  // 알람 수정 (스케줄러 자동 재등록)
  Future<void> updateAlarm(Alarm alarm) async {
    try {
      // 1. 기존 알람 취소
      await AlarmScheduler.cancelAlarm(alarm.id);
      
      // 2. 데이터베이스에 저장
      await _repository.saveAlarm(alarm);
      
      // 3. 스케줄러에 재등록 (enabled인 경우만)
      if (alarm.enabled) {
        await AlarmScheduler.scheduleAlarm(alarm);
      }
      
      // 4. 리스트 새로고침
      await _loadAlarms();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  // 알람 삭제 (스케줄러 자동 취소)
  Future<void> deleteAlarm(String alarmId) async {
    try {
      // 1. 스케줄러에서 취소
      await AlarmScheduler.cancelAlarm(alarmId);
      
      // 2. 데이터베이스에서 삭제
      await _repository.deleteAlarm(alarmId);
      
      // 3. 리스트 새로고침
      await _loadAlarms();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  // 알람 활성/비활성 토글 (스케줄러 자동 업데이트)
  Future<void> toggleAlarm(String alarmId, bool enabled) async {
    try {
      // 1. 알람 정보 가져오기
      final alarm = await _repository.getAlarmById(alarmId);
      if (alarm == null) return;

      // 2. 상태 업데이트
      final updatedAlarm = alarm.copyWith(enabled: enabled);
      
      // 3. 데이터베이스에 저장
      await _repository.saveAlarm(updatedAlarm);
      
      // 4. 스케줄러 업데이트
      if (enabled) {
        // 활성화: 스케줄러에 등록
        await AlarmScheduler.scheduleAlarm(updatedAlarm);
      } else {
        // 비활성화: 스케줄러에서 취소
        await AlarmScheduler.cancelAlarm(alarmId);
      }
      
      // 5. 리스트 새로고침
      await _loadAlarms();
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  // 리스트 새로고침
  Future<void> refresh() async {
    await _loadAlarms();
  }
}

// 알람 상태 관리 Provider
final alarmNotifierProvider =
    StateNotifierProvider<AlarmNotifier, AsyncValue<List<Alarm>>>((ref) {
  final repository = ref.watch(alarmRepositoryProvider);
  return AlarmNotifier(repository);
});

// 알람 리스트 Provider (기존 호환성을 위해 유지)
final alarmListProvider = Provider<AsyncValue<List<Alarm>>>((ref) {
  return ref.watch(alarmNotifierProvider);
});

// 유스케이스 Providers (기존 호환성을 위해 유지하되, 내부적으로는 Provider 사용)
final scheduleAlarmUseCaseProvider = Provider<ScheduleAlarmUseCase>((ref) {
  return ScheduleAlarmUseCase(ref.watch(alarmRepositoryProvider));
});

final cancelAlarmUseCaseProvider = Provider<CancelAlarmUseCase>((ref) {
  return CancelAlarmUseCase(ref.watch(alarmRepositoryProvider));
});

// UseCase 클래스들 (내부적으로는 Provider를 사용하도록 변경)
class ScheduleAlarmUseCase {
  final AlarmRepository repository;

  ScheduleAlarmUseCase(this.repository);

  Future<void> execute(Alarm alarm) async {
    await repository.saveAlarm(alarm);
    await AlarmScheduler.scheduleAlarm(alarm);
  }
}

class CancelAlarmUseCase {
  final AlarmRepository repository;

  CancelAlarmUseCase(this.repository);

  Future<void> execute(String alarmId) async {
    await repository.deleteAlarm(alarmId);
    await AlarmScheduler.cancelAlarm(alarmId);
  }
}
