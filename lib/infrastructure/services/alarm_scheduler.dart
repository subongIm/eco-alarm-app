import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:io' show Platform, File, Directory;
import 'dart:developer' as developer;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/entities/weekday.dart';
import '../datasources/local_db.dart';

class AlarmScheduler {
  static const String _alarmChannelId = 'alarm_channel';
  static const String _alarmChannelName = '알람';
  static const String _alarmChannelDescription = '알람 알림 채널';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Navigator key 저장 (알람 화면으로 이동하기 위해)
  static GlobalKey<NavigatorState>? _navigatorKey;

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  // iOS 사운드 이름 반환
  // assets 사운드 파일 경로에서 파일 이름만 추출 (확장자 포함)
  // flutter_local_notifications는 iOS에서 확장자를 포함한 파일 이름을 사용합니다
  static String? _getIOSSound(String sound) {
    if (sound == 'default' || sound.isEmpty || !sound.startsWith('assets/')) {
      return 'default';
    }
    // assets/sounds/filename.wav -> filename.wav (확장자 포함)
    final fileName = sound.split('/').last;
    // iOS에서는 확장자를 포함한 파일 이름을 사용해야 합니다
    // 번들에 포함된 파일: mixkit-wrong-long-buzzer-954.wav
    // 전달할 이름: mixkit-wrong-long-buzzer-954.wav
    developer.log('🎵 [iOS 사운드 파일명] $fileName');
    return fileName;
  }

  // Android 사운드 설정
  // assets 사운드 파일을 내부 저장소에 복사한 후 URI로 사용
  static Future<AndroidNotificationSound?> _getAndroidSound(
    String sound,
  ) async {
    if (sound == 'default' || sound.isEmpty || !sound.startsWith('assets/')) {
      return null; // null이면 시스템 기본 알람 소리 사용
    }

    try {
      // assets 파일을 내부 저장소에 복사
      final appDir = await getApplicationDocumentsDirectory();
      final soundDir = Directory('${appDir.path}/sounds');
      if (!await soundDir.exists()) {
        await soundDir.create(recursive: true);
      }

      final fileName = sound.split('/').last;
      final soundFile = File('${soundDir.path}/$fileName');

      // 파일이 이미 복사되어 있지 않으면 복사
      if (!await soundFile.exists()) {
        final byteData = await rootBundle.load(sound);
        await soundFile.writeAsBytes(byteData.buffer.asUint8List());
        developer.log('📁 [Android 사운드 복사] $sound -> ${soundFile.path}');
      }

      // 파일 URI를 사용하여 알림 사운드 설정
      final fileUri = Uri.file(soundFile.path);
      return UriAndroidNotificationSound(fileUri.toString());
    } catch (e) {
      developer.log('❌ [Android 사운드 로드 실패] $sound: $e');
      return null; // 실패 시 시스템 기본 소리 사용
    }
  }

  static Future<void> initialize() async {
    // timezone 초기화 (tz.local 사용 전 필수)
    // 시스템 기본 로케이션 설정 - 한국 시간대 사용
    // tz.local이 초기화되지 않으면 LateInitializationError 발생
    try {
      // 시스템 기본 타임존 설정 (한국: Asia/Seoul)
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (e) {
      // 타임존 이름을 찾을 수 없으면 UTC 사용
      tz.setLocalLocation(tz.UTC);
    }

    final androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    // iOS 알림 설정 개선 (sound, badge 등)
    // onDidReceiveLocalNotification은 iOS 9 이하에서만 작동합니다.
    // iOS 10 이상에서는 onDidReceiveNotificationResponse를 사용해야 합니다.
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      onDidReceiveLocalNotification:
          (int id, String? title, String? body, String? payload) async {
            // iOS 9 이하에서만 호출됨
            developer.log('🔔 [iOS 알림 수신 - iOS 9 이하] 알림이 발송되었습니다!');
            developer.log(
              '   📋 ID: $id, 제목: $title, 본문: $body, Payload: $payload',
            );
            developer.log('   ⏰ 수신 시간: ${DateTime.now()}');
            developer.log('   ✅ 알람이 실제로 울렸습니다!');
          },
    );
    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    final initialized = await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      // iOS 10 이상에서 포그라운드 알림도 표시
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
    );

    developer.log('알림 초기화 완료: $initialized');

    // iOS 알림 권한 요청 및 포그라운드 알림 설정
    if (Platform.isIOS) {
      final iosImplementation = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (iosImplementation != null) {
        // 먼저 현재 권한 상태 확인
        final currentPermission = await iosImplementation.checkPermissions();
        developer.log(
          '📱 [iOS 알림 권한 확인] 현재 상태: ${currentPermission?.isEnabled ?? false}',
        );

        // 권한이 없으면 요청
        if (currentPermission?.isEnabled != true) {
          developer.log('📱 [iOS 알림 권한 요청] 권한을 요청합니다...');
          final requested = await iosImplementation.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
          developer.log('📱 [iOS 알림 권한 요청 결과] 권한 허용: ${requested ?? false}');
          if (requested != true) {
            developer.log('⚠️ [iOS 알림 권한] 권한이 거부되었습니다. 설정에서 알림 권한을 허용해주세요.');
          }
        } else {
          developer.log('✅ [iOS 알림 권한] 권한이 이미 허용되어 있습니다.');
        }
        developer.log(
          '💡 iOS에서 포그라운드 알림은 DarwinNotificationDetails에서 이미 설정되었습니다.',
        );
      }
    }

    // Android에서만 알림 채널 생성
    if (Platform.isAndroid) {
      final androidChannel = AndroidNotificationChannel(
        _alarmChannelId,
        _alarmChannelName,
        description: _alarmChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(androidChannel);
    }

    // 앱 시작 시 데이터베이스에서 모든 활성화된 알람을 불러와서 재스케줄링
    await _rescheduleAllAlarms();
  }

  // 데이터베이스에서 모든 알람을 불러와서 재스케줄링
  static Future<void> _rescheduleAllAlarms() async {
    developer.log('🔄 [알람 복원 시작] 데이터베이스에서 알람을 불러와 재스케줄링합니다.');
    try {
      final alarms = LocalDatabase.getAllAlarms();
      developer.log('   📋 데이터베이스에서 ${alarms.length}개의 알람을 찾았습니다.');

      // 원본 알람이 없는 스누즈 알람 정리
      _cleanupOrphanedSnoozeAlarms(alarms);

      int rescheduledCount = 0;
      for (var alarm in alarms) {
        // 스누즈 알람은 재스케줄링하지 않음 (원본 알람이 없으면 이미 삭제됨)
        if (alarm.label.startsWith('__SNOOZE__:')) {
          continue;
        }

        if (alarm.enabled) {
          developer.log(
            '   🔔 알람 재스케줄링: ${alarm.label.isEmpty ? "알람" : alarm.label} (${alarm.time})',
          );
          await scheduleAlarm(alarm);
          rescheduledCount++;
        } else {
          developer.log(
            '   ⏸️ 알람 건너뛰기 (비활성화): ${alarm.label.isEmpty ? "알람" : alarm.label}',
          );
        }
      }

      developer.log('✅ [알람 복원 완료] $rescheduledCount개의 알람을 재스케줄링했습니다.');
    } catch (e) {
      developer.log('❌ [알람 복원 실패] 오류: $e');
    }
  }

  // 원본 알람이 없는 스누즈 알람 정리
  static void _cleanupOrphanedSnoozeAlarms(List<Alarm> allAlarms) {
    final originalAlarmIds = allAlarms
        .where((a) => !a.label.startsWith('__SNOOZE__:'))
        .map((a) => a.id)
        .toSet();

    int cleanedCount = 0;
    for (var alarm in allAlarms) {
      if (alarm.label.startsWith('__SNOOZE__:') ||
          alarm.originalAlarmIndex != null) {
        // 스누즈 알람의 원본 알람 ID 추출 (label 또는 originalAlarmIndex에서)
        final originalAlarmId =
            alarm.originalAlarmIndex ??
            alarm.label.substring('__SNOOZE__:'.length);
        if (!originalAlarmIds.contains(originalAlarmId)) {
          // 원본 알람이 없으면 스누즈 알람 삭제
          LocalDatabase.deleteAlarm(alarm.id);
          AlarmScheduler.cancelAlarm(alarm.id);
          cleanedCount++;
          developer.log(
            '   🗑️ 고아 스누즈 알람 삭제: ${alarm.id} (원본 알람 없음: $originalAlarmId)',
          );
        }
      }
    }
    if (cleanedCount > 0) {
      developer.log('   ✅ 고아 스누즈 알람 $cleanedCount개 정리 완료');
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    // iOS 10 이상에서는 알림이 발송되었을 때도 호출됩니다.
    developer.log('🔔 [알림 응답 수신] 알림이 발송되었거나 사용자가 탭했습니다!');
    developer.log(
      '   📋 알림 ID: ${response.id}, Payload: ${response.payload}, Action ID: ${response.actionId}',
    );
    developer.log('   ⏰ 수신 시간: ${DateTime.now()}');
    developer.log(
      '   📱 응답 타입: ${response.actionId == null ? "알림 표시됨 (사용자 탭 또는 자동 발송)" : "사용자 액션"}',
    );

    if (response.payload != null && response.payload!.isNotEmpty) {
      final alarmId = response.payload!;
      developer.log('   🆔 알람 ID (Payload): $alarmId');
      developer.log('   ✅ 알람이 실제로 울렸습니다!');

      // 알람 화면으로 이동
      _navigateToRingingScreen(alarmId);
    } else {
      developer.log('   ⚠️ Payload가 없습니다. 알람 ID를 확인할 수 없습니다.');
    }

    developer.log('📱 [알림 처리] 알람 화면으로 이동 처리 완료');
  }

  // 알람 화면으로 이동
  static void _navigateToRingingScreen(String alarmId) {
    if (_navigatorKey?.currentContext == null) {
      developer.log('   ⚠️ Navigator key가 설정되지 않았습니다. 알람 화면으로 이동할 수 없습니다.');
      return;
    }

    try {
      // 알람 정보 가져오기
      final alarms = LocalDatabase.getAllAlarms();
      final alarm = alarms.firstWhere(
        (a) => a.id == alarmId,
        orElse: () => throw Exception('알람을 찾을 수 없습니다: $alarmId'),
      );

      developer.log(
        '   📱 알람 화면으로 이동 시도: ${alarm.label.isEmpty ? "알람" : alarm.label}',
      );

      _navigatorKey!.currentState?.pushNamed('/ringing', arguments: alarm);

      developer.log('   ✅ 알람 화면으로 이동 완료');
    } catch (e) {
      developer.log('   ❌ 알람 화면으로 이동 실패: $e');
    }
  }

  // iOS 알림 권한 상태 확인
  static Future<bool> checkIOSNotificationPermission() async {
    if (!Platform.isIOS) {
      return true;
    }
    final iosImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosImplementation != null) {
      final permissionStatus = await iosImplementation.checkPermissions();
      developer.log('iOS 알림 권한 상태: $permissionStatus');
      // NotificationsEnabledOptions는 isEnabled 속성을 가짐
      return permissionStatus?.isEnabled ?? false;
    }
    return false;
  }

  // iOS 알림 권한 재요청
  static Future<bool> requestIOSNotificationPermission() async {
    if (!Platform.isIOS) {
      return true;
    }
    final iosImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosImplementation != null) {
      final requested = await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      developer.log('iOS 알림 권한 재요청 결과: $requested');
      return requested ?? false;
    }
    return false;
  }

  static Future<bool> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) {
      return true;
    }
    if (await Permission.scheduleExactAlarm.isGranted) {
      return true;
    }
    return await Permission.scheduleExactAlarm.request().isGranted;
  }

  static Future<void> scheduleAlarm(Alarm alarm) async {
    developer.log(
      '🔔 [알람 스케줄 시작] 알람 ID: ${alarm.id}, 시간: ${alarm.time}, 라벨: ${alarm.label}',
    );

    // 기존 알람 취소 (중복 예약 방지)
    await cancelAlarm(alarm.id);

    if (!alarm.enabled) {
      developer.log('⚠️ [알람 스케줄 취소] 알람이 비활성화되어 있습니다. 알람 취소 처리');
      return;
    }

    final now = DateTime.now();
    final timeParts = alarm.time.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);

    developer.log(
      '📅 [시간 계산] 현재 시간: $now, 설정 시간: ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
    );

    if (alarm.repeat.isEmpty) {
      // 스누즈 알람인 경우: 정확한 시간으로 예약 (label이 __SNOOZE__:로 시작)
      if (alarm.label.startsWith('__SNOOZE__:')) {
        // 스누즈 알람은 이미 미래 시간으로 설정되어 있으므로, 그대로 사용
        var targetDate = DateTime(now.year, now.month, now.day, hour, minute);
        // 만약 시간이 지났다면 내일로 설정 (하지만 스누즈 알람은 미래 시간이어야 함)
        if (targetDate.isBefore(now)) {
          targetDate = targetDate.add(const Duration(days: 1));
          developer.log('⏰ [스누즈 알람] 오늘 시간이 지났으므로 내일로 설정: $targetDate');
        } else {
          developer.log('⏰ [스누즈 알람] 정확한 시간으로 설정: $targetDate');
        }
        await _scheduleSingleAlarm(alarm, targetDate);
      } else {
        // 일반 반복 없는 알람: 오늘 또는 내일
        var targetDate = DateTime(now.year, now.month, now.day, hour, minute);
        if (targetDate.isBefore(now)) {
          targetDate = targetDate.add(const Duration(days: 1));
          developer.log('⏰ [반복 없음] 오늘 시간이 지났으므로 내일로 설정: $targetDate');
        } else {
          developer.log('⏰ [반복 없음] 오늘 시간으로 설정: $targetDate');
        }
        await _scheduleSingleAlarm(alarm, targetDate);
      }
    } else {
      // 반복 알람: 다음 요일 계산
      final weekdays = alarm.repeatWeekdays;
      developer.log(
        '🔄 [반복 알람] 반복 요일: ${weekdays.map((w) => w.label).join(", ")}',
      );
      for (final weekday in weekdays) {
        final targetDate = _getNextWeekday(now, weekday, hour, minute);
        developer.log('📆 [반복 알람] ${weekday.label} 요일로 예약: $targetDate');
        await _scheduleSingleAlarm(alarm, targetDate);
      }
    }

    developer.log('✅ [알람 스케줄 완료] 알람 ID: ${alarm.id}');
  }

  static DateTime _getNextWeekday(
    DateTime now,
    Weekday weekday,
    int hour,
    int minute,
  ) {
    var targetDate = DateTime(now.year, now.month, now.day, hour, minute);
    final currentWeekday = now.weekday; // 1=Monday, 7=Sunday
    final targetWeekday = weekday.value; // 1=Monday, 7=Sunday

    int daysUntilTarget = (targetWeekday - currentWeekday) % 7;

    // 오늘이 목표 요일이고 시간이 아직 지나지 않았으면 오늘로 예약
    if (daysUntilTarget == 0) {
      if (targetDate.isBefore(now)) {
        // 시간이 지났으면 다음 주로 예약
        daysUntilTarget = 7;
      } else {
        // 시간이 아직 안 지났으면 오늘로 예약
        daysUntilTarget = 0;
      }
    } else if (daysUntilTarget < 0) {
      // 음수가 나오면 다음 주로 조정
      daysUntilTarget += 7;
    }

    developer.log(
      '   📅 [다음 요일 계산] 현재 요일: $currentWeekday, 목표 요일: $targetWeekday, 일수 차이: $daysUntilTarget일',
    );

    return targetDate.add(Duration(days: daysUntilTarget));
  }

  static Future<void> _scheduleSingleAlarm(
    Alarm alarm,
    DateTime targetDate,
  ) async {
    developer.log('🎯 [단일 알람 예약 시작] 알람 ID: ${alarm.id}, 예약 시간: $targetDate');

    // 알람 ID를 안전하게 정수로 변환 (음수 방지)
    final hash = alarm.id.hashCode.abs();
    final alarmId = hash % 1000000000; // 9자리 이하로 제한
    developer.log('🆔 [알람 ID 변환] 원본 ID: ${alarm.id}, 변환된 ID: $alarmId');

    if (Platform.isAndroid) {
      developer.log('🤖 [Android 알람 매니저] AndroidAlarmManager.oneShotAt 호출');
      await AndroidAlarmManager.oneShotAt(
        targetDate,
        alarmId,
        _callback,
        exact: true,
        wakeup: true,
        alarmClock: true,
        params: {
          'alarmId': alarm.id,
          'label': alarm.label,
          'sound': alarm.sound,
          'vibrate': alarm.vibrate,
        },
      );
      developer.log('✅ [Android 알람 매니저] 예약 완료');
    }

    // 로컬 알림도 예약 (백업용)
    developer.log('📱 [로컬 알림 예약] flutter_local_notifications로 예약 시작');
    await _scheduleNotification(alarm, targetDate);
    developer.log('✅ [단일 알람 예약 완료] 알람 ID: ${alarm.id}');
  }

  static Future<void> _scheduleNotification(
    Alarm alarm,
    DateTime targetDate,
  ) async {
    // Android: assets 사운드 파일 사용
    final androidSound = await _getAndroidSound(alarm.sound);
    final androidDetails = AndroidNotificationDetails(
      _alarmChannelId,
      _alarmChannelName,
      channelDescription: _alarmChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: androidSound, // null이면 시스템 기본 알람 소리 사용
      enableVibration: alarm.vibrate,
    );

    // iOS: assets 사운드 파일 사용
    final iosSound = _getIOSSound(alarm.sound);
    developer.log('🔊 [iOS 사운드 설정] 원본 경로: ${alarm.sound}, 변환된 이름: $iosSound');
    developer.log(
      '   📦 번들에 포함된 파일: mixkit-horde-of-barking-dogs-60.wav, mixkit-magic-festive-melody-2986.wav, mixkit-wrong-long-buzzer-954.wav',
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: iosSound, // assets 사운드 파일 이름 사용 (확장자 없이)
      interruptionLevel: InterruptionLevel.critical,
    );

    final notificationDetails = NotificationDetails(
      android: Platform.isAndroid ? androidDetails : null,
      iOS: Platform.isIOS ? iosDetails : null,
    );

    final scheduledDate = tz.TZDateTime(
      tz.local,
      targetDate.year,
      targetDate.month,
      targetDate.day,
      targetDate.hour,
      targetDate.minute,
    );

    // 현재 시간과 예약 시간 비교
    final now = DateTime.now();
    final timeDifference = scheduledDate.difference(now);
    developer.log(
      '알람 예약: id=${alarm.id}, time=${alarm.time}, scheduledDate=$scheduledDate, 현재시간=$now, 차이=${timeDifference.inSeconds}초',
    );

    try {
      // iOS에서 예약된 알림이 제대로 등록되었는지 확인
      final scheduledNotifications = await _notifications
          .pendingNotificationRequests();
      developer.log(
        '📊 [예약 전 상태] 현재 예약된 알림 개수: ${scheduledNotifications.length}',
      );

      developer.log('⏰ [zonedSchedule 호출] 알람 ID: ${alarm.id.hashCode}');
      developer.log('   제목: ${alarm.label.isEmpty ? '알람' : alarm.label}');
      developer.log(
        '   본문: ${alarm.time} | ${targetDate.toIso8601String().substring(0, 10)}',
      );
      developer.log('   예약 시간: $scheduledDate');
      developer.log('   타임존: ${tz.local.name}');

      // iOS에서 알림이 제대로 스케줄되도록 추가 설정
      await _notifications.zonedSchedule(
        alarm.id.hashCode,
        alarm.label.isEmpty ? '알람' : alarm.label,
        // 본문에 날짜를 함께 넣어 알람 체커가 정확한 날짜에만 반응하도록 한다
        '${alarm.time} | ${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}',
        scheduledDate,
        notificationDetails,
        androidScheduleMode: Platform.isAndroid
            ? AndroidScheduleMode.exactAllowWhileIdle
            : null,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: alarm.id, // 알람 ID를 payload로 전달
        matchDateTimeComponents: Platform.isIOS
            ? DateTimeComponents.dateAndTime
            : null, // iOS에서 정확한 날짜/시간 매칭
      );

      // 예약 후 다시 확인
      final afterScheduled = await _notifications.pendingNotificationRequests();
      developer.log('📊 [예약 후 상태] 예약된 알림 개수: ${afterScheduled.length}');
      if (afterScheduled.isNotEmpty) {
        developer.log('📋 [예약된 알림 목록]');
        for (var notification in afterScheduled) {
          developer.log(
            '   - ID: ${notification.id}, 제목: ${notification.title}, 본문: ${notification.body}',
          );
        }
      }

      developer.log(
        '✅ [로컬 알림 예약 성공] 알람 ID: ${alarm.id}, 예약 시간: $scheduledDate',
      );
      developer.log('   ⏳ 예약 시간까지 대기 중... (현재 시간: $now)');
    } catch (e, stackTrace) {
      developer.log('❌ [로컬 알림 예약 실패] 알람 ID: ${alarm.id}');
      developer.log('   오류: $e');
      developer.log('   스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  static Future<void> cancelAlarm(String alarmId) async {
    final id = alarmId.hashCode;
    if (Platform.isAndroid) {
      await AndroidAlarmManager.cancel(id);
    }
    await _notifications.cancel(id);

    // 해당 알람의 스누즈 알람도 찾아서 취소
    // 스누즈 알람의 label 형식: "__SNOOZE__:${원본알람ID}"
    final snoozePrefix = '__SNOOZE__:$alarmId';
    final allAlarms = LocalDatabase.getAllAlarms();
    for (var alarm in allAlarms) {
      if (alarm.label == snoozePrefix) {
        final snoozeId = alarm.id.hashCode;
        if (Platform.isAndroid) {
          await AndroidAlarmManager.cancel(snoozeId);
        }
        await _notifications.cancel(snoozeId);
        developer.log('   ✅ 스누즈 알람 취소 완료: ${alarm.id}');
      }
    }
  }

  static Future<void> cancelAllAlarms() async {
    // AndroidAlarmManager에는 cancelAll 메서드가 없으므로
    // 개별 알람 취소는 각 알람을 취소할 때 처리됩니다.
    await _notifications.cancelAll();
  }

  // 테스트용: 즉시 알림 발송 (시뮬레이터 테스트용)
  static Future<void> testNotification() async {
    developer.log('테스트 알림 발송 시작');
    final androidDetails = AndroidNotificationDetails(
      _alarmChannelId,
      _alarmChannelName,
      channelDescription: _alarmChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      interruptionLevel: InterruptionLevel.critical,
    );

    final notificationDetails = NotificationDetails(
      android: Platform.isAndroid ? androidDetails : null,
      iOS: Platform.isIOS ? iosDetails : null,
    );

    await _notifications.show(
      999999,
      '테스트 알람',
      '알림이 정상적으로 작동합니다!',
      notificationDetails,
    );
    developer.log('테스트 알림 발송 완료');
  }

  // 예약된 알림 목록 확인 (디버깅용)
  static Future<void> listScheduledNotifications() async {
    final pending = await _notifications.pendingNotificationRequests();
    developer.log('📋 [예약된 알림 확인] 총 개수: ${pending.length}');
    if (pending.isEmpty) {
      developer.log('   ⚠️ 예약된 알림이 없습니다. 모든 알림이 발송되었거나 예약되지 않았을 수 있습니다.');
    } else {
      for (var notification in pending) {
        developer.log(
          '   - ID: ${notification.id}, 제목: ${notification.title}, 본문: ${notification.body}',
        );
        // 날짜 정보가 있다면 출력
        if (notification.body != null && notification.body!.contains(':')) {
          developer.log('     시간 정보: ${notification.body}');
        }
      }
    }
  }

  // 예약된 알림이 발송되었는지 확인 (시뮬레이터 테스트용)
  static Future<void> checkScheduledAlarmStatus() async {
    final pending = await _notifications.pendingNotificationRequests();
    final now = DateTime.now();

    developer.log('🔍 [알람 상태 확인] 현재 시간: $now');
    developer.log('   예약된 알림 개수: ${pending.length}');

    if (pending.isEmpty) {
      developer.log('   ✅ 예약된 알림이 없습니다. 모든 알림이 발송되었거나 예약되지 않았습니다.');
      developer.log('   💡 알림이 발송되었다면 위에 "🔔 [알림 응답 수신]" 로그가 표시되어야 합니다.');
      developer.log('   ⚠️ iOS 시뮬레이터에서는 백그라운드 알림이 제대로 작동하지 않을 수 있습니다.');
    } else {
      developer.log('   ⏳ 아직 발송되지 않은 알림이 있습니다:');
      for (var notification in pending) {
        developer.log(
          '     - ID: ${notification.id}, 제목: ${notification.title}',
        );
      }
    }
  }

  // 주기적으로 알람 시간을 체크하여 알람이 울렸는지 확인 (포그라운드에서만 작동)
  static Timer? _alarmCheckTimer;
  // 최근에 울린 알람 추적 (중복 트리거 방지)
  static final Map<String, DateTime> _lastTriggeredAlarms = {};

  static void startAlarmChecker() {
    // 이미 실행 중이면 중지
    _alarmCheckTimer?.cancel();

    developer.log('🔄 [알람 체커 시작] 주기적으로 알람 시간을 체크합니다.');

    _alarmCheckTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      final pending = await _notifications.pendingNotificationRequests();
      final now = DateTime.now();

      developer.log('🔍 [알람 체커 실행] 현재 시간: $now, 예약된 알림 개수: ${pending.length}');

      // 모든 알람을 확인하여 요일과 시간이 일치하는지 체크
      final alarms = LocalDatabase.getAllAlarms();
      final currentHour = now.hour;
      final currentMinute = now.minute;
      final currentWeekday = now.weekday; // 1=Monday, 7=Sunday

      developer.log(
        '   📅 현재 요일: $currentWeekday, 현재 시간: ${currentHour.toString().padLeft(2, '0')}:${currentMinute.toString().padLeft(2, '0')}',
      );

      for (var alarm in alarms) {
        if (!alarm.enabled) continue;

        // 알람 시간 파싱
        final timeParts = alarm.time.split(':');
        if (timeParts.length != 2) continue;
        final alarmHour = int.tryParse(timeParts[0]);
        final alarmMinute = int.tryParse(timeParts[1]);
        if (alarmHour == null || alarmMinute == null) continue;

        // 시간 체크: 디바이스 현재 시간과 알람 설정 시간을 정확히 비교
        // 현재 시간(시:분)과 알람 시간(시:분)이 정확히 일치하는지 확인
        final isTimeMatch =
            currentHour == alarmHour && currentMinute == alarmMinute;

        developer.log(
          '   🔍 알람 체크: ${alarm.label.isEmpty ? "알람" : alarm.label}, 설정 시간: ${alarm.time}, 반복: ${alarm.repeatWeekdays.map((w) => w.label).join(", ")}',
        );
        developer.log(
          '      디바이스 현재 시간: ${currentHour.toString().padLeft(2, '0')}:${currentMinute.toString().padLeft(2, '0')}, 알람 설정 시간: ${alarm.time}, 일치: $isTimeMatch',
        );

        // 시간이 정확히 일치하지 않으면 건너뜀
        if (!isTimeMatch) {
          developer.log('      ⏳ 시간이 일치하지 않습니다. 건너뜁니다.');
          continue;
        }

        // 반복 알람인 경우 요일 체크
        if (alarm.repeat.isNotEmpty) {
          final repeatWeekdays = alarm.repeatWeekdays
              .map((w) => w.value)
              .toSet();
          if (!repeatWeekdays.contains(currentWeekday)) {
            developer.log(
              '      ⚠️ [요일 불일치] 현재 요일($currentWeekday)이 반복 요일($repeatWeekdays)에 포함되지 않습니다.',
            );
            continue;
          } else {
            developer.log(
              '      ✅ [요일 일치] 현재 요일($currentWeekday)이 반복 요일($repeatWeekdays)에 포함됩니다.',
            );
          }
        }

        // 중복 트리거 방지: 같은 알람이 같은 시간(시:분)에 이미 울렸는지 확인
        final lastTriggered = _lastTriggeredAlarms[alarm.id];
        if (lastTriggered != null) {
          final lastTriggeredHour = lastTriggered.hour;
          final lastTriggeredMinute = lastTriggered.minute;
          // 같은 시간(시:분)에 이미 울렸는지 확인
          if (lastTriggeredHour == currentHour &&
              lastTriggeredMinute == currentMinute) {
            final timeSinceLastTrigger = now
                .difference(lastTriggered)
                .inSeconds;
            developer.log(
              '   ⏭️ [중복 방지] 이 알람은 이미 ${currentHour.toString().padLeft(2, '0')}:${currentMinute.toString().padLeft(2, '0')}에 울렸습니다. ($timeSinceLastTrigger초 전)',
            );
            continue;
          }
        }

        // 알람 시간이 되었고 요일도 일치함
        developer.log('🔔 [알람 시간 도래 감지] 알람이 울려야 합니다!');
        developer.log(
          '   📋 알람 ID: ${alarm.id}, 제목: ${alarm.label.isEmpty ? "알람" : alarm.label}',
        );
        developer.log(
          '   ⏰ 알람 시간: ${alarm.time}, 현재 시간: ${currentHour.toString().padLeft(2, '0')}:${currentMinute.toString().padLeft(2, '0')}',
        );

        // 해당 알람의 예약된 알림 취소
        await _notifications.cancel(alarm.id.hashCode);

        // 알람 트리거 시간 기록
        _lastTriggeredAlarms[alarm.id] = now;

        // 스누즈 알람인 경우: 울린 후 삭제 (한 번만 울리도록)
        if (alarm.label.startsWith('__SNOOZE__:')) {
          developer.log('   🗑️ 스누즈 알람이므로 울린 후 삭제합니다.');
          // 알람 트리거
          await _triggerAlarmImmediately(alarm.id);
          // 스누즈 알람 삭제 (한 번만 울리도록)
          await LocalDatabase.deleteAlarm(alarm.id);
          await AlarmScheduler.cancelAlarm(alarm.id);
          developer.log('   ✅ 스누즈 알람 트리거 및 삭제 완료');
        } else {
          // 일반 알람: 트리거만 수행
          await _triggerAlarmImmediately(alarm.id);
          developer.log('   ✅ 알람 트리거 완료');
        }
      }
    });
  }

  static void stopAlarmChecker() {
    _alarmCheckTimer?.cancel();
    _alarmCheckTimer = null;
    developer.log('🛑 [알람 체커 중지]');
  }

  // 알람을 즉시 발송 (알람 시간이 되었을 때 호출)
  static Future<void> _triggerAlarmImmediately(String alarmId) async {
    developer.log('🚨 [알람 즉시 발송] 알람 ID: $alarmId');

    try {
      // 알람 정보 가져오기
      final alarms = LocalDatabase.getAllAlarms();
      final alarm = alarms.firstWhere(
        (a) => a.id == alarmId,
        orElse: () => throw Exception('알람을 찾을 수 없습니다: $alarmId'),
      );

      developer.log(
        '   📋 알람 정보: ${alarm.label.isEmpty ? "알람" : alarm.label}, 시간: ${alarm.time}',
      );

      // 알림 즉시 표시 (소리 포함) - assets 사운드 파일 사용
      final androidSound = await _getAndroidSound(alarm.sound);
      final androidDetails = AndroidNotificationDetails(
        _alarmChannelId,
        _alarmChannelName,
        channelDescription: _alarmChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: androidSound, // null이면 시스템 기본 알람 소리 사용
        enableVibration: alarm.vibrate,
        ongoing: true, // 알람이 울리는 동안 계속 표시
      );

      // iOS: assets 사운드 파일 사용
      final iosSound = _getIOSSound(alarm.sound);
      developer.log(
        '🔊 [iOS 사운드 설정 - 즉시 발송] 원본 경로: ${alarm.sound}, 변환된 이름: $iosSound',
      );
      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: iosSound, // assets 사운드 파일 이름 사용 (확장자 없이)
        interruptionLevel: InterruptionLevel.critical,
      );

      final notificationDetails = NotificationDetails(
        android: Platform.isAndroid ? androidDetails : null,
        iOS: Platform.isIOS ? iosDetails : null,
      );

      await _notifications.show(
        alarm.id.hashCode,
        alarm.label.isEmpty ? '알람' : alarm.label,
        '${alarm.time} 알람이 울렸습니다!',
        notificationDetails,
        payload: alarm.id, // 알람 ID를 payload로 전달하여 알람 화면으로 이동 가능하게
      );

      developer.log('   ✅ 알림 즉시 표시 완료 (소리 포함)');

      // 알람 화면으로 자동 이동
      developer.log('   📱 알람 화면으로 자동 이동 시작');
      _navigateToRingingScreen(alarmId);
    } catch (e) {
      developer.log('   ❌ 알람 즉시 발송 실패: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _callback(int id, Map<String, dynamic>? params) async {
    developer.log('🔔 [Android 알람 콜백] 알람이 발송되었습니다!');
    developer.log('   📋 콜백 ID: $id, Params: $params');
    developer.log('   ⏰ 발송 시간: ${DateTime.now()}');

    if (params != null) {
      final alarmId = (params['alarmId'] ?? 'unknown').toString();
      final label = params['label'] ?? '알람';
      developer.log('   🆔 알람 ID: $alarmId, 라벨: $label');
      developer.log('   ✅ 알람이 실제로 울렸습니다!');

      // 알람 울림 처리 - assets 사운드 파일 사용
      // 여기서는 로컬 알림만 표시하고, 실제 울림 화면은 별도로 처리
      final sound = params['sound']?.toString() ?? 'default';
      final androidSound = await _getAndroidSound(sound);
      final androidDetails = AndroidNotificationDetails(
        _alarmChannelId,
        _alarmChannelName,
        channelDescription: _alarmChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: androidSound, // null이면 시스템 기본 알람 소리 사용
        enableVibration: params['vibrate'] ?? true,
      );

      final notificationDetails = NotificationDetails(android: androidDetails);

      await _notifications.show(
        id,
        label,
        '$label 알람이 울렸습니다',
        notificationDetails,
        payload: alarmId,
      );
      developer.log('   📱 알림 표시 완료');

      // 알람 화면으로 자동 이동
      developer.log('   📱 알람 화면으로 자동 이동 시작');
      _navigateToRingingScreen(alarmId);
    } else {
      developer.log('   ⚠️ Params가 null입니다. 알람 정보를 가져올 수 없습니다.');
    }
  }
}
