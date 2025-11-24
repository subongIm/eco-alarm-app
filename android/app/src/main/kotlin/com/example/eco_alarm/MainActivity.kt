package com.example.eco_alarm

import android.content.Context
import android.media.RingtoneManager
import android.media.AudioManager
import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.eco_alarm/ringtone"
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRingtones" -> {
                    try {
                        val ringtones = getRingtones()
                        result.success(ringtones)
                    } catch (e: Exception) {
                        result.error("ERROR", "벨소리 목록을 가져올 수 없습니다: ${e.message}", null)
                    }
                }
                "playRingtone" -> {
                    try {
                        val uri = call.argument<String>("uri")
                        if (uri != null) {
                            playRingtone(uri)
                            result.success(true)
                        } else {
                            result.error("ERROR", "URI가 제공되지 않았습니다", null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", "벨소리 재생 실패: ${e.message}", null)
                    }
                }
                "stopRingtone" -> {
                    try {
                        stopRingtone()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "벨소리 중지 실패: ${e.message}", null)
                    }
                }
                "getDefaultRingtoneUri" -> {
                    try {
                        val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                        result.success(defaultUri?.toString())
                    } catch (e: Exception) {
                        result.error("ERROR", "기본 벨소리 URI를 가져올 수 없습니다: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getRingtones(): List<Map<String, String>> {
        val ringtones = mutableListOf<Map<String, String>>()
        
        // 기본 벨소리 추가 (항상 첫 번째로)
        ringtones.add(mapOf("uri" to "default", "title" to "시스템 기본 벨소리"))
        
        try {
            val manager = RingtoneManager(this)
            
            // 벨소리 목록 가져오기 (알람 소리가 아닌 벨소리 사용)
            manager.setType(RingtoneManager.TYPE_RINGTONE)
            val cursor = manager.cursor
            
            while (cursor.moveToNext()) {
                val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                val id = cursor.getInt(RingtoneManager.ID_COLUMN_INDEX)
                val uriString = cursor.getString(RingtoneManager.URI_COLUMN_INDEX)
                val uri = android.net.Uri.parse("$uriString/$id")
                ringtones.add(mapOf("uri" to uri.toString(), "title" to title))
            }
            
            cursor.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return ringtones
    }

    private fun playRingtone(uri: String) {
        stopRingtone() // 기존 재생 중지
        
        try {
            mediaPlayer = MediaPlayer()
            if (uri == "default") {
                // 기본 벨소리 재생 (알람 소리가 아닌 벨소리 사용)
                val defaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                mediaPlayer?.setDataSource(this, defaultUri)
            } else {
                // 지정된 URI 재생
                val ringtoneUri = android.net.Uri.parse(uri)
                mediaPlayer?.setDataSource(this, ringtoneUri)
            }
            mediaPlayer?.setAudioStreamType(AudioManager.STREAM_ALARM)
            mediaPlayer?.prepare()
            mediaPlayer?.start()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopRingtone() {
        mediaPlayer?.release()
        mediaPlayer = null
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRingtone()
    }
}
