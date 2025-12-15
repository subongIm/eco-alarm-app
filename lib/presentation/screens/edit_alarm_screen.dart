import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'dart:io' show Platform;
import 'package:audioplayers/audioplayers.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/entities/weekday.dart';
import '../../application/providers/alarm_providers.dart';
import '../../infrastructure/services/ringtone_service.dart';

class EditAlarmScreen extends ConsumerStatefulWidget {
  final Alarm? existingAlarm;

  const EditAlarmScreen({super.key, this.existingAlarm});

  @override
  ConsumerState<EditAlarmScreen> createState() => _EditAlarmScreenState();
}

class _EditAlarmScreenState extends ConsumerState<EditAlarmScreen> {
  TimeOfDay? _selectedTime;
  late Set<Weekday> _selectedWeekdays;
  late TextEditingController _labelController;
  late bool _vibrate;
  late int _snoozeMinutes;
  late String _selectedSound;
  // 주중/주말 그룹 선택 상태
  bool _isWeekdaysSelected = false;
  bool _isWeekendsSelected = false;

  // Android용 AudioPlayer (iOS는 RingtoneService 사용)
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 모든 assets 사운드 파일 목록
  // 출처: Mixkit (https://mixkit.co/) - 무료 사운드 효과
  // 라이선스: https://mixkit.co/license/ (무료 사용, 상업적 사용 가능, 출처 표기 불필요)
  static const List<Map<String, String>> _allSoundOptions = [
    {
      'path': 'assets/sounds/mixkit-driving-ambition-32.mp3',
      'title': 'Driving Ambition',
    },
    {
      'path': 'assets/sounds/mixkit-gimme-that-groove-872.mp3',
      'title': 'Gimme That Groove',
    },
    {'path': 'assets/sounds/mixkit-hey-billy-803.mp3', 'title': 'Hey Billy'},
    {
      'path': 'assets/sounds/mixkit-classic-alarm-995.wav',
      'title': 'Classic Alarm',
    },
    {
      'path': 'assets/sounds/mixkit-morning-clock-alarm-1003.wav',
      'title': 'Morning Clock Alarm',
    },
    {
      'path': 'assets/sounds/mixkit-short-rooster-crowing-2470.wav',
      'title': 'Rooster Crowing',
    },
    {
      'path': 'assets/sounds/mixkit-horde-of-barking-dogs-60.wav',
      'title': 'Barking Dogs',
    },
    {
      'path': 'assets/sounds/mixkit-magic-festive-melody-2986.wav',
      'title': 'Magic Festive Melody',
    },
    {
      'path': 'assets/sounds/mixkit-wrong-long-buzzer-954.wav',
      'title': 'Wrong Long Buzzer',
    },
  ];

  // 플랫폼별 사운드 옵션 가져오기
  // 현재는 Android/iOS 모두에서 .wav 파일만 노출되도록 통일
  List<Map<String, String>> get _soundOptions {
    return _allSoundOptions
        .where((sound) => sound['path']?.endsWith('.wav') ?? false)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.existingAlarm != null) {
      final alarm = widget.existingAlarm!;
      final timeParts = alarm.time.split(':');
      _selectedTime = TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      );
      _selectedWeekdays = alarm.repeatWeekdays;
      _labelController = TextEditingController(text: alarm.label);
      _vibrate = alarm.vibrate;
      _snoozeMinutes = alarm.snoozeMinutes;
      _selectedSound = alarm.sound;
    } else {
      _selectedTime = null; // 새 알람일 때는 시간 미선택
      _selectedWeekdays = {};
      _labelController = TextEditingController();
      _vibrate = true;
      _snoozeMinutes = 3;
      _selectedSound = 'default';
    }
    // 그룹 선택 상태 초기화
    _updateGroupSelectionState();
    // 기본값이 없으면 첫 번째 사운드 선택
    if (_selectedSound.isEmpty || _selectedSound == 'default') {
      _selectedSound = _soundOptions.isNotEmpty
          ? _soundOptions.first['path'] ?? 'default'
          : 'default';
    }
  }

  // 사운드 재생 함수
  Future<void> _playSound(String soundPath) async {
    try {
      if (Platform.isIOS) {
        // iOS: 번들에 포함된 파일 사용 (RingtoneService 사용)
        // 번들 파일 이름만 추출 (확장자 포함)
        final fileName = soundPath.split('/').last;
        // RingtoneService를 통해 번들 파일 재생
        await RingtoneService.playRingtone(fileName);
      } else {
        // Android: assets 파일 사용 (audioplayers 사용)
        // AssetSource는 'assets/' 접두사 없이 경로를 받아야 함
        // 예: 'assets/sounds/file.mp3' -> 'sounds/file.mp3'
        String assetPath = soundPath;
        if (assetPath.startsWith('assets/')) {
          assetPath = assetPath.substring(7); // 'assets/'.length = 7
        }
        // 이전 재생 중지
        await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource(assetPath));
      }
    } catch (e) {
      // 재생 실패 시 무시 (에러 로그만 출력)
      debugPrint('사운드 재생 실패: $e');
    }
  }

  // 그룹 선택 상태 업데이트 (주중/주말 버튼 표시 상태)
  void _updateGroupSelectionState() {
    _isWeekdaysSelected = _selectedWeekdays.containsAll({
      Weekday.monday,
      Weekday.tuesday,
      Weekday.wednesday,
      Weekday.thursday,
      Weekday.friday,
    });
    _isWeekendsSelected = _selectedWeekdays.containsAll({
      Weekday.saturday,
      Weekday.sunday,
    });
  }

  @override
  void dispose() {
    // Android용 AudioPlayer 정리
    if (Platform.isAndroid) {
      _audioPlayer.dispose();
    } else {
      // iOS에서는 재생 중지
      RingtoneService.stopRingtone();
    }
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _toggleWeekday(Weekday weekday) {
    setState(() {
      if (_selectedWeekdays.contains(weekday)) {
        _selectedWeekdays.remove(weekday);
      } else {
        _selectedWeekdays.add(weekday);
      }
      // 개별 토글 후 그룹 선택 상태 동기화
      _updateGroupSelectionState();
    });
  }

  // 주중 토글 (월~금 전체 선택/해제)
  void _toggleWeekdaysGroup() {
    setState(() {
      final weekdays = {
        Weekday.monday,
        Weekday.tuesday,
        Weekday.wednesday,
        Weekday.thursday,
        Weekday.friday,
      };
      final allSelected = _selectedWeekdays.containsAll(weekdays);
      if (allSelected || _isWeekdaysSelected) {
        _selectedWeekdays.removeAll(weekdays);
        _isWeekdaysSelected = false;
      } else {
        _selectedWeekdays.addAll(weekdays);
        _isWeekdaysSelected = true;
      }
      // 주말 그룹 상태도 함께 동기화
      _updateGroupSelectionState();
    });
  }

  // 주말 토글 (토~일 전체 선택/해제)
  void _toggleWeekendsGroup() {
    setState(() {
      final weekends = {Weekday.saturday, Weekday.sunday};
      final allSelected = _selectedWeekdays.containsAll(weekends);
      if (allSelected || _isWeekendsSelected) {
        _selectedWeekdays.removeAll(weekends);
        _isWeekendsSelected = false;
      } else {
        _selectedWeekdays.addAll(weekends);
        _isWeekendsSelected = true;
      }
      // 주중 그룹 상태도 함께 동기화
      _updateGroupSelectionState();
    });
  }

  Future<void> _saveAlarm() async {
    // 시간이 선택되지 않았으면 저장 불가
    if (_selectedTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('시간을 선택해주세요'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final timeString =
        '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';

    final alarm = Alarm(
      id: widget.existingAlarm?.id ?? const Uuid().v4(),
      time: timeString,
      repeat: _selectedWeekdays.map((w) => w.value).toList(),
      label: _labelController.text,
      sound: _selectedSound,
      vibrate: _vibrate,
      snoozeMinutes: _snoozeMinutes,
      enabled: widget.existingAlarm?.enabled ?? true,
    );

    // Provider를 통해 알람 저장 (스케줄러 자동 처리)
    final alarmNotifier = ref.read(alarmNotifierProvider.notifier);
    try {
      if (widget.existingAlarm == null) {
        // 새 알람 생성
        await alarmNotifier.createAlarm(alarm);
      } else {
        // 기존 알람 수정
        await alarmNotifier.updateAlarm(alarm);
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('알람 저장 실패: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingAlarm == null ? '알람 추가' : '알람 편집'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 시간 선택
          InkWell(
            onTap: _selectTime,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _selectedTime != null
                        ? _selectedTime!.format(context)
                        : 'Enter time',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: _selectedTime != null ? null : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 라벨
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: '알람 이름',
              hintText: '알람 이름을 입력하세요',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          // 반복 요일
          const Text(
            '반복',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          // 주중/주말 빠른 선택 버튼
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('주중'),
                selected: _isWeekdaysSelected,
                onSelected: (_) => _toggleWeekdaysGroup(),
              ),
              FilterChip(
                label: const Text('주말'),
                selected: _isWeekendsSelected,
                onSelected: (_) => _toggleWeekendsGroup(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 개별 요일 선택
          Wrap(
            spacing: 8,
            children: Weekday.values.map((weekday) {
              final isSelected = _selectedWeekdays.contains(weekday);
              return FilterChip(
                label: Text(weekday.label),
                selected: isSelected,
                onSelected: (_) => _toggleWeekday(weekday),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // 진동
          SwitchListTile(
            title: const Text('진동'),
            value: _vibrate,
            onChanged: (value) {
              setState(() {
                _vibrate = value;
              });
            },
          ),
          const SizedBox(height: 24),

          // 알람 소리
          const Text(
            '알람 소리',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._soundOptions.map((sound) {
            final soundPath = sound['path'] ?? '';
            return RadioListTile<String>(
              title: Text(sound['title'] ?? '알 수 없음'),
              value: soundPath,
              // ignore: deprecated_member_use
              groupValue: _selectedSound,
              // ignore: deprecated_member_use
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedSound = value;
                  });
                  // 사운드 선택 시 자동으로 재생
                  _playSound(value);
                }
              },
            );
          }),

          // 다시 알람
          const Text(
            '다시 알람',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 3, label: Text('3분')),
              ButtonSegment(value: 6, label: Text('6분')),
              ButtonSegment(value: 9, label: Text('9분')),
            ],
            selected: {_snoozeMinutes},
            onSelectionChanged: (Set<int> selected) {
              setState(() {
                _snoozeMinutes = selected.first;
              });
            },
          ),
          const SizedBox(height: 32),
          // 저장 버튼
          ElevatedButton(
            onPressed: _saveAlarm,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              '저장',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
