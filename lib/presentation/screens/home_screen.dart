import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import '../../application/providers/alarm_providers.dart';
import '../../infrastructure/services/alarm_scheduler.dart';
import '../widgets/alarm_card.dart';
import 'dart:developer' as developer;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool? _hasNotificationPermission;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    // 알람 체커 시작 (포그라운드에서 알람 시간을 주기적으로 체크)
    AlarmScheduler.startAlarmChecker();
  }

  @override
  void dispose() {
    // 알람 체커 중지
    AlarmScheduler.stopAlarmChecker();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    if (Platform.isIOS) {
      final hasPermission =
          await AlarmScheduler.checkIOSNotificationPermission();
      setState(() {
        _hasNotificationPermission = hasPermission;
      });
    } else {
      setState(() {
        _hasNotificationPermission = true;
      });
    }
  }

  Future<void> _requestPermission() async {
    if (Platform.isIOS) {
      final granted = await AlarmScheduler.requestIOSNotificationPermission();
      setState(() {
        _hasNotificationPermission = granted;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              granted ? '알림 권한이 허용되었습니다' : '알림 권한이 거부되었습니다. 설정에서 권한을 허용해주세요.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    developer.log('HomeScreen build 시작');
    final alarmListAsync = ref.watch(alarmNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('알람'),
        elevation: 0,
        actions: [
          /* aileen - debug alarm
          // 테스트 알림 버튼 (디버그용 - 항상 표시)
          IconButton(
            icon: const Icon(Icons.notification_important),
            color: Colors.blue,
            onPressed: () async {
              final navigator = Navigator.of(context);
              await AlarmScheduler.testNotification();
              if (!mounted) return;
              ScaffoldMessenger.of(navigator.context).showSnackBar(
                const SnackBar(
                  content: Text('테스트 알림을 발송했습니다. 알림이 표시되는지 확인하세요.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            tooltip: '테스트 알림',
          ),
          */
          // iOS 알림 권한 상태 표시 및 요청 버튼
          if (Platform.isIOS && _hasNotificationPermission == false)
            IconButton(
              icon: const Icon(Icons.notifications_off, color: Colors.red),
              onPressed: _requestPermission,
              tooltip: '알림 권한 요청',
            ),
        ],
      ),
      body: Column(
        children: [
          // iOS 알림 권한 안내 배너
          if (Platform.isIOS && _hasNotificationPermission == false)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: const Text(
                      '알림 권한이 필요합니다. 알람이 작동하려면 권한을 허용해주세요.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  TextButton(
                    onPressed: _requestPermission,
                    child: const Text('권한 허용'),
                  ),
                ],
              ),
            ),
          // 알람 목록
          Expanded(
            child: alarmListAsync.when(
              data: (alarms) {
                developer.log('알람 목록 로드 완료: ${alarms.length}개');
                if (alarms.isEmpty) {
                  return const Center(
                    child: Text(
                      '알람이 없습니다\n+ 버튼을 눌러 알람을 추가하세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    // Provider를 통해 리스트 새로고침
                    final alarmNotifier = ref.read(
                      alarmNotifierProvider.notifier,
                    );
                    await alarmNotifier.refresh();
                    // 간단한 대기 추가로 RefreshIndicator 완료 애니메이션 보장
                    await Future<void>.delayed(
                      const Duration(milliseconds: 150),
                    );
                  },
                  child: ListView.builder(
                    itemCount: alarms.length,
                    itemBuilder: (context, index) {
                      final alarm = alarms[index];
                      return AlarmCard(alarm: alarm);
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) {
                developer.log('알람 목록 로드 오류: $error');
                return Center(child: Text('오류: $error'));
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/edit');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
