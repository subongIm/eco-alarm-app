import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'dart:io' show Platform;
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/entities/alarm_log.dart';
import '../../infrastructure/services/alarm_scheduler.dart';
import '../../infrastructure/services/ringtone_service.dart';
import '../../infrastructure/datasources/local_db.dart';
import '../../application/providers/ringing_providers.dart';
import '../../application/providers/alarm_providers.dart';
import 'package:uuid/uuid.dart';

class RingingScreen extends ConsumerStatefulWidget {
  final Alarm alarm;

  const RingingScreen({super.key, required this.alarm});

  @override
  ConsumerState<RingingScreen> createState() => _RingingScreenState();
}

class _RingingScreenState extends ConsumerState<RingingScreen> {
  // 사운드 재생을 위한 AudioPlayer (Android용)
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 진동 타이머 (반복 진동용)
  Timer? _vibrationTimer;

  // iOS 사운드 루프 타이머
  Timer? _iosSoundTimer;

  @override
  void initState() {
    super.initState();
    // Provider 업데이트와 사운드/진동 시작을 모두 postFrameCallback으로 처리
    // 위젯 트리 빌드 중에는 Provider를 수정할 수 없으므로
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Provider에 알람 울림 상태 업데이트
      final ringingNotifier = ref.read(ringingProvider.notifier);
      ringingNotifier.startRinging(widget.alarm);

      // 알람 소리 반복 재생 시작
      _startAlarmSound();
      // 진동 시작 (설정된 경우)
      if (widget.alarm.vibrate) {
        _startVibration();
      }
    });
  }

  // 진동 시작 (반복)
  Future<void> _startVibration() async {
    try {
      // 진동 권한 확인
      if (Platform.isAndroid) {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == null || !hasVibrator) {
          developer.log('⚠️ 진동 기능을 사용할 수 없습니다');
          return;
        }
      }

      // Provider에 진동 상태 업데이트 (안전하게 처리)
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(ringingProvider.notifier).setVibrating(true);
          }
        });
      }

      // 즉시 진동 시작
      if (Platform.isAndroid) {
        // Android: 패턴 진동 (0.5초 진동, 0.5초 대기 반복)
        await Vibration.vibrate(
          pattern: [0, 500, 500, 500],
          repeat: 0, // 무한 반복
        );
        developer.log('📳 [Android] 진동 시작 (패턴 반복)');
      } else {
        // iOS: 주기적으로 진동 (1초마다)
        _vibrateIOS();
        developer.log('📳 [iOS] 진동 시작 (주기적 반복)');
      }
    } catch (e) {
      developer.log('❌ 진동 시작 실패: $e');
      if (mounted) {
        ref.read(ringingProvider.notifier).setVibrating(false);
      }
    }
  }

  // iOS 진동 반복
  void _vibrateIOS() {
    HapticFeedback.vibrate();
    // 1초마다 반복
    _vibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        HapticFeedback.vibrate();
      } else {
        timer.cancel();
      }
    });
  }

  // 진동 중지
  Future<void> _stopVibration() async {
    try {
      // Provider에 진동 상태 업데이트 (mounted 체크)
      if (mounted) {
        ref.read(ringingProvider.notifier).setVibrating(false);
      }

      if (Platform.isAndroid) {
        await Vibration.cancel();
        developer.log('📳 [Android] 진동 중지');
      } else {
        _vibrationTimer?.cancel();
        _vibrationTimer = null;
        developer.log('📳 [iOS] 진동 중지');
      }
    } catch (e) {
      developer.log('❌ 진동 중지 실패: $e');
    }
  }

  // 알람 소리 반복 재생 시작
  Future<void> _startAlarmSound() async {
    try {
      final soundPath = widget.alarm.sound;
      if (soundPath.isEmpty || soundPath == 'default') {
        developer.log('🔇 알람 소리가 설정되지 않았습니다. 기본 소리 사용');
        return;
      }

      // Provider에 사운드 재생 상태 업데이트 (안전하게 처리)
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(ringingProvider.notifier).setSoundPlaying(true);
          }
        });
      }

      if (Platform.isIOS) {
        // iOS: 번들에 포함된 파일 사용 (RingtoneService 사용)
        // 번들 파일 이름만 추출 (확장자 포함)
        final fileName = soundPath.split('/').last;
        // RingtoneService를 통해 번들 파일 재생
        // iOS에서는 반복 재생을 위해 별도 처리 필요
        await RingtoneService.playRingtone(fileName);
        // iOS는 RingtoneService가 반복 재생을 지원하지 않으므로
        // 주기적으로 재생하도록 타이머 사용
        _startIOSSoundLoop(fileName);
      } else {
        // Android: assets 파일 사용 (audioplayers 사용)
        // 반복 재생 설정
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.play(
          AssetSource(soundPath.replaceFirst('assets/', '')),
        );
        developer.log('🔊 [Android] 알람 소리 반복 재생 시작: $soundPath');
      }
    } catch (e) {
      developer.log('❌ 알람 소리 재생 실패: $e');
      if (mounted) {
        ref.read(ringingProvider.notifier).setSoundPlaying(false);
      }
    }
  }

  // iOS 사운드 반복 재생 (타이머 사용)
  void _startIOSSoundLoop(String fileName) {
    // 3초마다 재생 (사운드 길이에 따라 조정 가능)
    _iosSoundTimer?.cancel();
    _iosSoundTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        if (ref.read(ringingProvider).isSoundPlaying) {
          RingtoneService.playRingtone(fileName);
        } else {
          timer.cancel();
        }
      } catch (e) {
        // ref 사용 불가 시 타이머 취소
        timer.cancel();
      }
    });
  }

  // 알람 소리 중지
  Future<void> _stopAlarmSound() async {
    try {
      // Provider에 사운드 재생 상태 업데이트 (안전하게 처리)
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(ringingProvider.notifier).setSoundPlaying(false);
          }
        });
      }

      if (Platform.isAndroid) {
        await _audioPlayer.stop();
        developer.log('🔇 [Android] 알람 소리 중지');
      } else {
        await RingtoneService.stopRingtone();
        _iosSoundTimer?.cancel();
        _iosSoundTimer = null;
        developer.log('🔇 [iOS] 알람 소리 중지');
      }
    } catch (e) {
      developer.log('❌ 알람 소리 중지 실패: $e');
    }
  }

  @override
  void dispose() {
    // 진동 중지
    _stopVibration();
    // 알람 소리 중지
    _stopAlarmSound();
    // 타이머 정리
    _vibrationTimer?.cancel();
    _iosSoundTimer?.cancel();
    // Android용 AudioPlayer 정리
    if (Platform.isAndroid) {
      _audioPlayer.dispose();
    }
    // Provider에 알람 울림 상태 초기화는 하지 않음
    // dispose에서는 이미 위젯이 dispose되기 시작했으므로,
    // _dismiss()나 _dismissAll()에서 이미 상태를 업데이트했을 가능성이 높음
    // dispose 중에는 Provider를 수정하지 않음 (위젯 트리 빌드 중일 수 있음)
    super.dispose();
  }

  // 알람 종료 후 스누즈 시간 후 다시 알람 예약
  Future<void> _dismiss() async {
    // 진동 중지
    await _stopVibration();
    // 알람 소리 중지
    await _stopAlarmSound();
    developer.log('🔔 [알람 종료] 스누즈 알람 예약 시작');
    developer.log('   📋 원본 알람 ID: ${widget.alarm.id}');
    developer.log('   ⏰ 스누즈 시간: ${widget.alarm.snoozeMinutes}분');

    // 현재 알람 해제
    await AlarmScheduler.cancelAlarm(widget.alarm.id);
    developer.log('   ✅ 현재 알람 취소 완료');

    // 기존 스누즈 알람 취소 (중복 방지)
    final allAlarms = LocalDatabase.getAllAlarms();
    final snoozePrefix = '__SNOOZE__:${widget.alarm.id}';
    for (var alarm in allAlarms) {
      if (alarm.label == snoozePrefix) {
        await AlarmScheduler.cancelAlarm(alarm.id);
        await LocalDatabase.deleteAlarm(alarm.id);
        developer.log('   🗑️ 기존 스누즈 알람 삭제: ${alarm.id}');
      }
    }

    // 스누즈 시간 후 재예약
    // 디바이스 현재 시간을 기준으로 정확히 스누즈 시간(분) 후로 계산
    final now = DateTime.now();
    final snoozeTime = now.add(Duration(minutes: widget.alarm.snoozeMinutes));

    developer.log('   📅 [디바이스 현재 시간] $now');
    developer.log(
      '   ⏰ [스누즈 시간 계산] 현재 시간 + ${widget.alarm.snoozeMinutes}분 = $snoozeTime',
    );
    developer.log(
      '   🕐 [스누즈 알람 설정 시간] ${snoozeTime.hour.toString().padLeft(2, '0')}:${snoozeTime.minute.toString().padLeft(2, '0')}',
    );

    final snoozeAlarm = widget.alarm.copyWith(
      id: const Uuid().v4(), // 새로운 알람 ID 생성
      time:
          '${snoozeTime.hour.toString().padLeft(2, '0')}:${snoozeTime.minute.toString().padLeft(2, '0')}',
      repeat: [], // 스누즈 알람은 반복 없음
      enabled: true, // 스누즈 알람 활성화
      // 목록에서 숨기기 위한 내부 식별 라벨 부여 (원본 알람 ID 포함)
      label: '__SNOOZE__:${widget.alarm.id}',
      // 원본 알람의 index 저장 (원본 알람 삭제 시 스누즈 알람도 함께 삭제하기 위해)
      originalAlarmIndex: widget.alarm.id,
    );
    developer.log('   🆔 [스누즈 알람 ID] ${snoozeAlarm.id}');
    developer.log('   ⏰ [스누즈 알람 최종 시간] ${snoozeAlarm.time}');

    // 스누즈 알람을 데이터베이스에 저장
    await LocalDatabase.saveAlarm(snoozeAlarm);
    developer.log('   💾 스누즈 알람 데이터베이스 저장 완료');

    // 스누즈 알람 예약
    await AlarmScheduler.scheduleAlarm(snoozeAlarm);
    developer.log('   ✅ 스누즈 알람 예약 완료');

    // Provider에 스누즈 상태 업데이트
    ref.read(ringingProvider.notifier).setSnoozeScheduled(snoozeAlarm.id);

    // 알람 리스트 새로고침 (스누즈 알람 추가됨)
    ref.read(alarmNotifierProvider.notifier).refresh();

    // 로그 저장
    final log = AlarmLog(
      id: const Uuid().v4(),
      alarmId: widget.alarm.id,
      firedAt: DateTime.now(),
      action: 'dismiss',
    );
    await LocalDatabase.saveAlarmLog(log);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // 현재 알람 + 스누즈 모두 종료
  Future<void> _dismissAll() async {
    // 진동 중지
    await _stopVibration();
    // 알람 소리 중지
    await _stopAlarmSound();
    developer.log('🔔 [알람 완전 종료] 현재 알람과 스누즈 알람 모두 종료');
    developer.log('   📋 원본 알람 ID: ${widget.alarm.id}');

    // 현재 알람 해제
    await AlarmScheduler.cancelAlarm(widget.alarm.id);
    developer.log('   ✅ 현재 알람 취소 완료');

    // 등록된 모든 스누즈 알람 찾아서 취소 및 삭제
    // originalAlarmIndex로 원본 알람과 연결된 모든 스누즈 알람 찾기
    final allAlarms = LocalDatabase.getAllAlarms();
    final originalAlarmIndex = widget.alarm.id;
    int deletedCount = 0;

    for (var alarm in allAlarms) {
      // originalAlarmIndex 또는 label로 원본 알람과 연결된 스누즈 알람 찾기
      if (alarm.originalAlarmIndex == originalAlarmIndex ||
          alarm.label == '__SNOOZE__:$originalAlarmIndex') {
        await AlarmScheduler.cancelAlarm(alarm.id);
        await LocalDatabase.deleteAlarm(alarm.id);
        deletedCount++;
        developer.log('   🗑️ 스누즈 알람 삭제: ${alarm.id} (시간: ${alarm.time})');
      }
    }

    if (deletedCount > 0) {
      developer.log('   ✅ 총 $deletedCount개의 스누즈 알람 삭제 완료');
    } else {
      developer.log('   ℹ️ 삭제할 스누즈 알람이 없습니다.');
    }

    // Provider에 스누즈 상태 초기화
    ref.read(ringingProvider.notifier).cancelSnooze();

    // 알람 리스트 새로고침
    ref.read(alarmNotifierProvider.notifier).refresh();

    // 로그 저장
    final log = AlarmLog(
      id: const Uuid().v4(),
      alarmId: widget.alarm.id,
      firedAt: DateTime.now(),
      action: 'dismiss_all',
    );
    await LocalDatabase.saveAlarmLog(log);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '알람이 울리고 있습니다',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                widget.alarm.time,
                style: const TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              if (widget.alarm.label.isNotEmpty &&
                  !widget.alarm.label.startsWith('__SNOOZE__'))
                Text(
                  widget.alarm.label,
                  style: const TextStyle(fontSize: 24, color: Colors.white70),
                ),
              const SizedBox(height: 64),
              // 버튼 배치
              Column(
                children: [
                  // 알람 종료 버튼 (큰 버튼)
                  ElevatedButton(
                    onPressed: _dismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      '알람 종료',
                      style: TextStyle(
                        fontSize: 18,
                        color: Color.fromARGB(255, 255, 255, 255),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 다시 울림 종료 버튼 (작은 버튼)
                  ElevatedButton(
                    onPressed: _dismissAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '다시 울림 종료',
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
