import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'dart:io' show Platform;
import 'dart:developer' as developer;
import 'infrastructure/datasources/local_db.dart';
import 'infrastructure/services/alarm_scheduler.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/edit_alarm_screen.dart';
import 'presentation/screens/ringing_screen.dart';
import 'presentation/screens/permission_screen.dart';
import 'domain/entities/alarm.dart';

/*
Flutter 바인딩 보장 → 안드로이드 알람 매니저(안드로이드일 때만) 
→ Hive DB(Hive 어댑터 등록 및 박스 오픈) → 로컬 알림 플러그인 초기화 순서로 실행됩니다.
초기화 로그가 여기서 출력됩니다.
*/
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Android 전용: 알람 매니저 초기화
    if (Platform.isAndroid) {
      await AndroidAlarmManager.initialize();
      developer.log('AndroidAlarmManager 초기화 완료');
    }
  } catch (e) {
    developer.log('AndroidAlarmManager 초기화 실패: $e');
  }

  try {
    // 로컬 DB 초기화
    await LocalDatabase.init();
    developer.log('LocalDatabase 초기화 완료');
  } catch (e) {
    developer.log('LocalDatabase 초기화 실패: $e');
  }

  try {
    // 알람 스케줄러 초기화
    await AlarmScheduler.initialize();
    developer.log('AlarmScheduler 초기화 완료');
  } catch (e) {
    developer.log('AlarmScheduler 초기화 실패: $e');
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Navigator key를 AlarmScheduler에 등록
    AlarmScheduler.setNavigatorKey(navigatorKey);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '알람',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // initialRoute 제거, '/' 라우트 항목 제거
      routes: {
        '/edit': (context) {
          final alarm = ModalRoute.of(context)?.settings.arguments as Alarm?;
          return EditAlarmScreen(existingAlarm: alarm);
        },
        '/ringing': (context) {
          final alarm = ModalRoute.of(context)?.settings.arguments as Alarm;
          return RingingScreen(alarm: alarm);
        },
        '/permission': (context) => const PermissionScreen(),
      },
      home: const HomeScreen(),
    );
  }
}
