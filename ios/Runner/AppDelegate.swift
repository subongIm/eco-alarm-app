import Flutter
import UIKit
import AVFoundation
import MediaPlayer
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var audioPlayer: AVAudioPlayer?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Method channel 설정
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    let channel = FlutterMethodChannel(
      name: "com.eco_alarm/ringtone",
      binaryMessenger: controller.binaryMessenger
    )
    
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "getRingtones":
        self?.getRingtones(result: result)
      case "playRingtone":
        if let args = call.arguments as? [String: Any],
           let uri = args["uri"] as? String {
          self?.playRingtone(uri: uri, result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "URI가 제공되지 않았습니다", details: nil))
        }
      case "stopRingtone":
        self?.stopRingtone(result: result)
      case "getDefaultRingtoneUri":
        self?.getDefaultRingtoneUri(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func getRingtones(result: @escaping FlutterResult) {
    var ringtones: [[String: String]] = []
    
    // 기본 벨소리 추가
    ringtones.append(["uri": "default", "title": "시스템 기본 벨소리"])
    
    // iOS에서는 시스템 벨소리를 직접 가져올 수 없으므로
    // 일반적인 벨소리 이름들을 제공합니다
    // 실제로는 사용자가 선택한 벨소리 파일을 사용해야 합니다
    let systemSounds = [
      "note": "노트",
      "alarm": "알람",
      "bell": "벨",
      "chime": "차임",
      "ding": "딩",
      "ring": "링",
    ]
    
    for (key, title) in systemSounds {
      ringtones.append(["uri": key, "title": title])
    }
    
    result(ringtones)
  }
  
  private func playRingtone(uri: String, result: @escaping FlutterResult) {
    stopRingtone(result: nil)
    
    do {
      if uri == "default" {
        // 시스템 기본 벨소리 재생
        // iOS에서는 알림 소리를 직접 재생할 수 없으므로
        // 시스템 사운드 ID를 사용합니다
        AudioServicesPlaySystemSound(1005) // 기본 알림 소리
        result(true)
        return
      }
      
      // 번들에서 사운드 파일 찾기
      // 확장자를 포함한 파일 이름인 경우와 확장자 없이 파일 이름만 있는 경우 모두 처리
      var soundPath: String?
      
      // 확장자가 포함된 경우 (예: mixkit-wrong-long-buzzer-954.wav)
      if uri.contains(".") {
        let components = uri.components(separatedBy: ".")
        if components.count >= 2 {
          let name = components.dropLast().joined(separator: ".")
          let ext = components.last
          soundPath = Bundle.main.path(forResource: name, ofType: ext)
        }
      }
      
      // 확장자 없이 파일 이름만 있는 경우
      if soundPath == nil {
        // .wav, .caf, .m4r 순서로 시도
        soundPath = Bundle.main.path(forResource: uri, ofType: "wav")
        if soundPath == nil {
          soundPath = Bundle.main.path(forResource: uri, ofType: "caf")
        }
        if soundPath == nil {
          soundPath = Bundle.main.path(forResource: uri, ofType: "m4r")
        }
      }
      
      if let soundPath = soundPath {
        let soundURL = URL(fileURLWithPath: soundPath)
        audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
        result(true)
      } else {
        // 시스템 사운드 ID 사용
        let systemSoundId: SystemSoundID
        switch uri {
        case "note":
          systemSoundId = 1054
        case "alarm":
          systemSoundId = 1005
        case "bell":
          systemSoundId = 1000
        case "chime":
          systemSoundId = 1001
        case "ding":
          systemSoundId = 1002
        case "ring":
          systemSoundId = 1003
        default:
          systemSoundId = 1005 // 기본 알림 소리
        }
        AudioServicesPlaySystemSound(systemSoundId)
        result(true)
      }
    } catch {
      result(FlutterError(code: "PLAY_ERROR", message: "벨소리 재생 실패: \(error.localizedDescription)", details: nil))
    }
  }
  
  private func stopRingtone(result: FlutterResult?) {
    audioPlayer?.stop()
    audioPlayer = nil
    result?(true)
  }
  
  private func getDefaultRingtoneUri(result: @escaping FlutterResult) {
    // iOS에서는 기본 벨소리 URI를 직접 가져올 수 없으므로
    // "default"를 반환합니다
    result("default")
  }
}
