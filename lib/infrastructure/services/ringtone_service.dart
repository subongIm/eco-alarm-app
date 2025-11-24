import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'dart:developer' as developer;

class RingtoneService {
  static const MethodChannel _channel = MethodChannel('com.eco_alarm/ringtone');

  /// 시스템 벨소리 목록 가져오기
  /// Android: RingtoneManager를 통해 벨소리 목록 반환
  /// iOS: 시스템 벨소리 목록 반환
  static Future<List<Map<String, String>>> getSystemRingtones() async {
    try {
      if (Platform.isAndroid) {
        final List<dynamic> result = await _channel.invokeMethod('getRingtones');
        return result
            .map((item) => {
                  'uri': item['uri'] as String,
                  'title': item['title'] as String,
                })
            .toList();
      } else if (Platform.isIOS) {
        // iOS에서도 벨소리 목록 가져오기
        final List<dynamic> result = await _channel.invokeMethod('getRingtones');
        return result
            .map((item) => {
                  'uri': item['uri'] as String,
                  'title': item['title'] as String,
                })
            .toList();
      }
    } catch (e) {
      developer.log('벨소리 목록 가져오기 실패: $e');
    }
    // 기본값 반환
    return [
      {'uri': 'default', 'title': '시스템 기본 벨소리'}
    ];
  }

  /// 벨소리 미리듣기 (Android 및 iOS 지원)
  static Future<void> playRingtone(String uri) async {
    try {
      await _channel.invokeMethod('playRingtone', {'uri': uri});
    } catch (e) {
      developer.log('벨소리 재생 실패: $e');
    }
  }

  /// 벨소리 재생 중지 (Android 및 iOS 지원)
  static Future<void> stopRingtone() async {
    try {
      await _channel.invokeMethod('stopRingtone');
    } catch (e) {
      developer.log('벨소리 중지 실패: $e');
    }
  }

  /// 기본 벨소리 URI 가져오기 (Android 및 iOS 지원)
  /// 'default'일 때 사용할 기본 벨소리 URI를 반환
  static Future<String?> getDefaultRingtoneUri() async {
    try {
      final String? uri = await _channel.invokeMethod('getDefaultRingtoneUri');
      return uri;
    } catch (e) {
      developer.log('기본 벨소리 URI 가져오기 실패: $e');
    }
    return null;
  }
}

