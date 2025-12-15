import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'dart:io' show Platform, File;
import 'dart:math' show Random;
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:path_provider/path_provider.dart';
import '../../infrastructure/services/ringtone_service.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/entities/alarm_log.dart';
import '../../infrastructure/services/alarm_scheduler.dart';
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

  // 현재 시간 업데이트 타이머
  Timer? _currentTimeTimer;

  // 현재 시간 상태
  DateTime _currentTime = DateTime.now();

  // 다이얼로그 라디오 버튼 선택 값
  int? _selectedRadioValue;

  // USD 환율 상태
  String? _usdRate;
  double? _usdRateValue; // 환율 숫자 값 (랜덤 값 생성용)

  // 한국 기준금리 상태
  String? _baseRate;

  // 환율 기반 랜덤 값 3개
  List<String> _randomRates = [];

  // 실제 환율 값 표시용
  String? _actualRateText;

  @override
  void initState() {
    super.initState();
    // 현재 시간 업데이트 시작 (1초마다)
    _currentTime = DateTime.now();
    _currentTimeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      } else {
        timer.cancel();
      }
    });

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

    // USD 환율 데이터 가져오기
    _fetchUsdRate();
    // 한국 기준금리 데이터 가져오기
    _fetchBaseRate();
  }

  // Supabase에서 USD 환율 가져오기
  Future<void> _fetchUsdRate() async {
    try {
      final supabase = Supabase.instance.client;

      // fx_rates 테이블에서 currency_code가 'USD'인 최신 데이터 가져오기
      final response = await supabase
          .from('fx_rates')
          .select()
          .eq('currency_code', 'USD')
          .order('base_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null && response['deal_bas_r'] != null) {
        final rate = response['deal_bas_r'] as num;
        if (mounted) {
          setState(() {
            _usdRate = '[미국 환율 USD] : ${rate.toStringAsFixed(2)}원';
            _usdRateValue = rate.toDouble();
            // 환율 기반 랜덤 값 4개 생성
            _generateRandomRates();
          });
        }
        developer.log('USD 환율 가져오기 성공: $_usdRate');
      } else {
        if (mounted) {
          setState(() {
            _usdRate = 'USD 환율 정보 없음';
          });
        }
        developer.log('USD 환율 데이터를 찾을 수 없습니다.');
      }
    } catch (e) {
      developer.log('USD 환율 가져오기 실패: $e');
      if (mounted) {
        setState(() {
          _usdRate = '환율 로딩 실패';
        });
      }
    }
  }

  // Supabase에서 한국 기준금리 가져오기
  Future<void> _fetchBaseRate() async {
    try {
      final supabase = Supabase.instance.client;

      // ecos_base_rate 테이블에서 stat_code가 '722Y001'인 최신 데이터 가져오기
      final response = await supabase
          .from('ecos_base_rate')
          .select('time_period, data_value')
          .eq('stat_code', '722Y001')
          .order('time_period', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null &&
          response['data_value'] != null &&
          response['time_period'] != null) {
        final dataValue = response['data_value'] as num;
        final timePeriod = response['time_period'] as String;

        // time_period를 날짜 형식으로 변환 (YYYYMMDD -> YYYY-MM-DD)
        String formattedDate = timePeriod;
        if (timePeriod.length == 8) {
          formattedDate =
              '${timePeriod.substring(0, 4)}-${timePeriod.substring(4, 6)}-${timePeriod.substring(6, 8)}';
        }

        if (mounted) {
          setState(() {
            _baseRate =
                '[한국 기준 금리] : ${dataValue.toStringAsFixed(2)}% ($formattedDate 기준)';
          });
        }
        developer.log('한국 기준금리 가져오기 성공: $_baseRate');
      } else {
        if (mounted) {
          setState(() {
            _baseRate = '한국 기준 금리 정보 없음';
          });
        }
        developer.log('한국 기준금리 데이터를 찾을 수 없습니다.');
      }
    } catch (e) {
      developer.log('한국 기준금리 가져오기 실패: $e');
      if (mounted) {
        setState(() {
          _baseRate = '금리 로딩 실패';
        });
      }
    }
  }

  // 진동 시작 (반복)
  Future<void> _startVibration() async {
    try {
      // 진동 권한 확인
      if (Platform.isAndroid) {
        final hasVibrator = await Vibration.hasVibrator();
        if (!hasVibrator) {
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
        // iOS: Runner 번들에 포함된 wav 등을 파일명으로 재생
        final fileName = soundPath.split('/').last;
        await RingtoneService.playRingtone(fileName);
        _startIOSSoundLoop(fileName);
        developer.log('🔊 [iOS] 번들 사운드 재생 시작: $fileName');
      } else {
        // Android: assets 파일 사용 (audioplayers 사용)
        // AssetSource는 'assets/' 접두사 없이 경로를 받아야 함
        // 예: 'assets/sounds/file.mp3' -> 'sounds/file.mp3'
        String assetPath = soundPath;
        if (assetPath.startsWith('assets/')) {
          assetPath = assetPath.substring(7); // 'assets/'.length = 7
        }
        developer.log('🔊 [Android] 원본 경로: $soundPath');
        developer.log('🔊 [Android] 변환된 경로: $assetPath');

        try {
          // 반복 재생 설정
          await _audioPlayer.setReleaseMode(ReleaseMode.loop);
          await _audioPlayer.play(AssetSource(assetPath));
          developer.log('🔊 [Android] 반복 재생 시작 성공: $assetPath');
        } catch (e) {
          developer.log('❌ [Android] AssetSource 재생 실패: $e');
          developer.log('   시도한 경로: $assetPath');
          // 대안: rootBundle을 사용하여 직접 로드
          try {
            final byteData = await rootBundle.load(soundPath);
            final tempDir = await getTemporaryDirectory();
            final tempFile = File(
              '${tempDir.path}/${soundPath.split('/').last}',
            );
            await tempFile.writeAsBytes(byteData.buffer.asUint8List());
            await _audioPlayer.setReleaseMode(ReleaseMode.loop);
            await _audioPlayer.play(DeviceFileSource(tempFile.path));
            developer.log('🔊 [Android] 임시 파일로 재생 성공: ${tempFile.path}');
          } catch (e2) {
            developer.log('❌ [Android] 임시 파일 재생도 실패: $e2');
            rethrow;
          }
        }
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

      if (Platform.isIOS) {
        await RingtoneService.stopRingtone();
        _iosSoundTimer?.cancel();
        _iosSoundTimer = null;
        developer.log('🔇 [iOS] 알람 소리 중지');
      } else {
        await _audioPlayer.stop();
        developer.log('🔇 [Android] 알람 소리 중지');
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
    _currentTimeTimer?.cancel();
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

  // 환율 기반 랜덤 값 4개 생성 (3개 랜덤 + 1개 실제 값, 랜덤 인덱스 배치)
  void _generateRandomRates() {
    if (_usdRateValue == null) {
      _randomRates = ['로딩 중...', '로딩 중...', '로딩 중...', '로딩 중...'];
      _actualRateText = '로딩 중...';
      return;
    }

    final baseRate = _usdRateValue!;
    final random = Random(DateTime.now().millisecondsSinceEpoch);

    // 실제 환율 값 텍스트 생성
    _actualRateText = '${baseRate.toStringAsFixed(2)}원';

    // 환율의 ±5% 범위 내에서 랜덤 값 3개 생성 (각각 다른 값 보장)
    final Set<String> uniqueRates = {};
    final List<String> randomValues = [];

    while (randomValues.length < 3) {
      // -5% ~ +5% 범위 내에서 랜덤 변동 생성
      final variation =
          (random.nextDouble() - 0.5) * 0.1; // -0.05 ~ 0.05 (5% 변동)
      final randomRate = baseRate * (1 + variation);
      final rateText = '${randomRate.toStringAsFixed(2)}원';

      // 중복 체크: 같은 값이 없고 실제 값과도 다를 때만 추가
      if (!uniqueRates.contains(rateText) && rateText != _actualRateText) {
        uniqueRates.add(rateText);
        randomValues.add(rateText);
      }
    }

    // 4개 배열 초기화 (빈 문자열로 채움)
    _randomRates = List<String>.filled(4, '');

    // 실제 환율 값이 들어갈 랜덤 인덱스 선택 (0~3)
    final actualRateIndex = random.nextInt(4);
    _randomRates[actualRateIndex] = _actualRateText!;

    // 나머지 3개 인덱스에 랜덤 값 배치
    int randomValueIndex = 0;
    for (int i = 0; i < 4; i++) {
      if (_randomRates[i].isEmpty) {
        _randomRates[i] = randomValues[randomValueIndex];
        randomValueIndex++;
      }
    }
  }

  // 종료 다이얼로그 표시
  Future<void> _showDismissDialog() async {
    _selectedRadioValue = null; // 다이얼로그 열 때 초기화

    // 환율 기반 랜덤 값이 없거나 로딩 중이면 생성
    if (_randomRates.isEmpty || _usdRateValue == null) {
      if (_usdRateValue != null) {
        _generateRandomRates();
      } else {
        // 환율이 아직 로딩 중이면 기본값 설정
        _randomRates = ['로딩 중...', '로딩 중...', '로딩 중...', '로딩 중...'];
        _actualRateText = '로딩 중...';
      }
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false, // 다이얼로그 외부 터치로 닫기 방지
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              //             title: const Text('알람 종료', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 텍스트
                  const Text(
                    '최근 환율 값은 어떤 것일 까요?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 라디오 버튼 4개 (수직 배치)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 라디오 버튼 1 (랜덤 값)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<int>(
                            value: 1,
                            groupValue: _selectedRadioValue,
                            onChanged: (int? value) {
                              setDialogState(() {
                                _selectedRadioValue = value;
                              });
                            },
                            fillColor: WidgetStateProperty.all(Colors.orange),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _randomRates.isNotEmpty &&
                                    _randomRates[0].isNotEmpty
                                ? _randomRates[0]
                                : '로딩 중...',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 라디오 버튼 2 (랜덤 값)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<int>(
                            value: 2,
                            groupValue: _selectedRadioValue,
                            onChanged: (int? value) {
                              setDialogState(() {
                                _selectedRadioValue = value;
                              });
                            },
                            fillColor: WidgetStateProperty.all(Colors.orange),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _randomRates.length > 1 &&
                                    _randomRates[1].isNotEmpty
                                ? _randomRates[1]
                                : '로딩 중...',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 라디오 버튼 3 (랜덤 값)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<int>(
                            value: 3,
                            groupValue: _selectedRadioValue,
                            onChanged: (int? value) {
                              setDialogState(() {
                                _selectedRadioValue = value;
                              });
                            },
                            fillColor: WidgetStateProperty.all(Colors.orange),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _randomRates.length > 2 &&
                                    _randomRates[2].isNotEmpty
                                ? _randomRates[2]
                                : '로딩 중...',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 라디오 버튼 4
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<int>(
                            value: 4,
                            groupValue: _selectedRadioValue,
                            onChanged: (int? value) {
                              setDialogState(() {
                                _selectedRadioValue = value;
                              });
                            },
                            fillColor: WidgetStateProperty.all(Colors.orange),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _randomRates.length > 3 &&
                                    _randomRates[3].isNotEmpty
                                ? _randomRates[3]
                                : '로딩 중...',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                // 취소 버튼
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // 다이얼로그만 닫기
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                  child: const Text(
                    '취소',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                // 완전종료 버튼
                ElevatedButton(
                  onPressed: () {
                    // 라디오 버튼이 선택되었는지 확인
                    if (_selectedRadioValue == null) {
                      // 선택되지 않았으면 경고 메시지 표시
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('환율 값을 선택해주세요.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      return;
                    }

                    // 선택된 라디오 버튼의 인덱스 (라디오는 1,2,3,4이므로 배열 인덱스는 0,1,2,3)
                    final selectedIndex = _selectedRadioValue! - 1;

                    // 선택된 값과 실제 환율 값 비교
                    if (selectedIndex >= 0 &&
                        selectedIndex < _randomRates.length &&
                        _actualRateText != null &&
                        _randomRates[selectedIndex] == _actualRateText) {
                      // 일치하면 알람 종료 및 스누즈 알람 제거
                      Navigator.of(context).pop(); // 다이얼로그 닫기
                      _dismissAll(); // 스누즈 알람 종료 및 알람 종료
                    } else {
                      // 일치하지 않으면 알람만 종료 (스누즈 알람은 유지)
                      Navigator.of(context).pop(); // 다이얼로그 닫기

                      // 경고 메시지 표시
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('값이 일치하지 않습니다.'),
                          duration: Duration(seconds: 2),
                          backgroundColor: Colors.orange,
                        ),
                      );

                      _dismissCurrentOnly(); // 알람만 종료 (스누즈는 유지)
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text(
                    '종료',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 현재 알람만 종료 (스누즈 알람은 유지 또는 새로 생성)
  Future<void> _dismissCurrentOnly() async {
    // 진동 중지
    await _stopVibration();
    // 알람 소리 중지
    await _stopAlarmSound();
    developer.log('🔔 [알람 종료] 현재 알람만 종료 (스누즈 알람은 유지)');
    developer.log('   📋 원본 알람 ID: ${widget.alarm.id}');
    developer.log('   ⏰ 스누즈 시간: ${widget.alarm.snoozeMinutes}분');

    // 현재 알람 해제
    await AlarmScheduler.cancelAlarm(widget.alarm.id);
    developer.log('   ✅ 현재 알람 취소 완료');

    // 스누즈 알람 확인
    final allAlarms = LocalDatabase.getAllAlarms();
    final originalAlarmIndex = widget.alarm.id;
    final snoozePrefix = '__SNOOZE__:$originalAlarmIndex';
    List<Alarm> existingSnoozeAlarms = [];

    for (var alarm in allAlarms) {
      // originalAlarmIndex 또는 label로 원본 알람과 연결된 스누즈 알람 찾기
      if (alarm.originalAlarmIndex == originalAlarmIndex ||
          alarm.label == snoozePrefix) {
        existingSnoozeAlarms.add(alarm);
        developer.log('   ⏰ 기존 스누즈 알람 발견: ${alarm.id} (시간: ${alarm.time})');
      }
    }

    if (existingSnoozeAlarms.isNotEmpty) {
      // 기존 스누즈 알람이 있으면 유지
      developer.log('   ✅ 총 ${existingSnoozeAlarms.length}개의 스누즈 알람이 유지됩니다.');
      for (var snoozeAlarm in existingSnoozeAlarms) {
        // 스누즈 알람이 활성화되어 있고 예약되어 있는지 확인
        if (snoozeAlarm.enabled) {
          developer.log('   ✅ 스누즈 알람 활성화됨: ${snoozeAlarm.id}');
          // Provider에 스누즈 상태 업데이트
          ref.read(ringingProvider.notifier).setSnoozeScheduled(snoozeAlarm.id);
        }
      }
    } else {
      // 기존 스누즈 알람이 없으면 새로 생성
      developer.log('   ℹ️ 기존 스누즈 알람이 없습니다. 새로 생성합니다.');

      // 스누즈 시간 후 재예약
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
        label: snoozePrefix,
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
    }

    // Provider 상태 업데이트
    if (mounted) {
      final ringingNotifier = ref.read(ringingProvider.notifier);
      ringingNotifier.stopRinging();
    }

    // 알람 리스트 새로고침
    ref.read(alarmNotifierProvider.notifier).refresh();

    // 로그 저장
    final log = AlarmLog(
      id: const Uuid().v4(),
      alarmId: widget.alarm.id,
      firedAt: DateTime.now(),
      action: 'dismiss_current_only',
    );
    await LocalDatabase.saveAlarmLog(log);

    // 화면 닫기
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
    // 현재 시간 포맷팅
    final currentTimeString =
        '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 컨텐츠
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 현재 시간
                    Text(
                      currentTimeString,
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 48),
                    // Text 위젯 4개
                    Text(
                      _usdRate ?? '로딩 중...',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.yellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _baseRate ?? '로딩 중...',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.yellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    /*
                    const SizedBox(height: 16),
                    const Text(
                      '텍스트 3',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.yellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '텍스트 4',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.yellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),*/
                  ],
                ),
              ),
            ),
            // 하단 종료 버튼
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: ElevatedButton(
                onPressed: _showDismissDialog,
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
            ),
          ],
        ),
      ),
    );
  }
}
