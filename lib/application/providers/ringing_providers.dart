import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/alarm.dart';
import 'dart:developer' as developer;

// 알람 울림 상태 모델
class RingingState {
  final Alarm? currentAlarm; // 현재 울리고 있는 알람
  final bool isSoundPlaying; // 사운드 재생 중인지
  final bool isVibrating; // 진동 중인지
  final bool hasSnoozeScheduled; // 스누즈 예약되었는지
  final String? snoozeAlarmId; // 스누즈 알람 ID

  const RingingState({
    this.currentAlarm,
    this.isSoundPlaying = false,
    this.isVibrating = false,
    this.hasSnoozeScheduled = false,
    this.snoozeAlarmId,
  });

  bool get isRinging => currentAlarm != null;

  RingingState copyWith({
    Alarm? currentAlarm,
    bool? isSoundPlaying,
    bool? isVibrating,
    bool? hasSnoozeScheduled,
    String? snoozeAlarmId,
    bool clearCurrentAlarm = false,
    bool clearSnooze = false,
  }) {
    return RingingState(
      currentAlarm: clearCurrentAlarm
          ? null
          : (currentAlarm ?? this.currentAlarm),
      isSoundPlaying: isSoundPlaying ?? this.isSoundPlaying,
      isVibrating: isVibrating ?? this.isVibrating,
      hasSnoozeScheduled: clearSnooze
          ? false
          : (hasSnoozeScheduled ?? this.hasSnoozeScheduled),
      snoozeAlarmId: clearSnooze ? null : (snoozeAlarmId ?? this.snoozeAlarmId),
    );
  }
}

// 알람 울림 상태 관리 StateNotifier
class RingingNotifier extends StateNotifier<RingingState> {
  RingingNotifier() : super(const RingingState());

  // 알람 울림 시작
  void startRinging(Alarm alarm) {
    developer.log('🔔 [RingingProvider] 알람 울림 시작: ${alarm.id}');
    state = RingingState(
      currentAlarm: alarm,
      isSoundPlaying: true,
      isVibrating: alarm.vibrate,
      hasSnoozeScheduled: false,
      snoozeAlarmId: null,
    );
  }

  // 사운드 재생 상태 업데이트
  void setSoundPlaying(bool playing) {
    if (state.currentAlarm != null) {
      state = state.copyWith(isSoundPlaying: playing);
      developer.log('🔊 [RingingProvider] 사운드 재생 상태: $playing');
    }
  }

  // 진동 상태 업데이트
  void setVibrating(bool vibrating) {
    if (state.currentAlarm != null) {
      state = state.copyWith(isVibrating: vibrating);
      developer.log('📳 [RingingProvider] 진동 상태: $vibrating');
    }
  }

  // 스누즈 예약
  void setSnoozeScheduled(String snoozeAlarmId) {
    state = state.copyWith(
      hasSnoozeScheduled: true,
      snoozeAlarmId: snoozeAlarmId,
    );
    developer.log('⏰ [RingingProvider] 스누즈 예약: $snoozeAlarmId');
  }

  // 알람 울림 중지
  void stopRinging() {
    developer.log('🔕 [RingingProvider] 알람 울림 중지');
    state = const RingingState();
  }

  // 스누즈만 취소 (알람은 계속 울림)
  void cancelSnooze() {
    state = state.copyWith(
      hasSnoozeScheduled: false,
      snoozeAlarmId: null,
      clearSnooze: true,
    );
    developer.log('❌ [RingingProvider] 스누즈 취소');
  }
}

// 알람 울림 상태 Provider
final ringingProvider = StateNotifierProvider<RingingNotifier, RingingState>((
  ref,
) {
  return RingingNotifier();
});
