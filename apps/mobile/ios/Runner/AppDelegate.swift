import Flutter
import UIKit
import AVFAudio
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Mine2YourLingoAudio") {
      Mine2YourLingoAudio.register(with: registrar)
    }
  }
}

/// Foreground speech and ordinary notifications; no VoIP or background audio entitlement.
final class Mine2YourLingoAudio: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate, URLSessionDataDelegate {
  private let channel: FlutterMethodChannel
  private let synthesizer = AVSpeechSynthesizer()
  private var receivingEnabled = false
  private var activeMessageId: String?
  private var activePlaybackRequestId: String?
  private var activeUtterance: AVSpeechUtterance?
  private var headphonesRequired = false
  private var startedOnHeadphones = false
  private var mediaPlayer: AVAudioPlayer?
  private var mediaSession: URLSession?
  private var mediaTask: URLSessionDataTask?
  private var mediaData = Data()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.mine2yourlingo/audio", binaryMessenger: registrar.messenger())
    let instance = Mine2YourLingoAudio(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    synthesizer.delegate = self
    synthesizer.usesApplicationAudioSession = true
    NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCapabilities":
      result([
        "platform": "ios", "onDeviceTts": true, "backgroundPlayback": false,
        "remoteAudioPlayback": true,
        "backgroundReceive": false, "receivingEnabled": receivingEnabled,
        "headphonesConnected": headphonesConnected,
        "headphonesOnlySupported": true,
        "voices": AVSpeechSynthesisVoice.speechVoices().map {
          ["identifier": $0.identifier, "language": $0.language, "offlineVerified": false] as [String: Any]
        },
        "note": "Automatic speech requires the foreground app. Background delivery requires configured APNs/FCM notifications and user interaction. Verify installed voices offline on each device."
      ] as [String: Any])
    case "startReceiving":
      guard UIApplication.shared.applicationState == .active else {
        result(FlutterError(code: "foreground_required", message: "Enable receiving while the app is visible.", details: nil)); return
      }
      receivingEnabled = true
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        DispatchQueue.main.async {
          result(["enabled": true, "backgroundReceive": false, "backgroundPlayback": false,
                  "notificationsAllowed": granted, "note": "Foreground playback only; notifications are the background fallback."] as [String: Any])
        }
      }
    case "stopReceiving":
      receivingEnabled = false
      stop(reason: "receiving_disabled")
      result(true)
    case "stopPlayback": stop(reason: "user_stopped"); result(true)
    case "playAudio": playAudio(call, result: result)
    case "speak":
      guard let args = call.arguments as? [String: Any], let text = args["text"] as? String,
            let language = args["language"] as? String, let id = args["messageId"] as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4000,
            !language.isEmpty, !id.isEmpty, id.count <= 200 else {
        result(FlutterError(code: "invalid_arguments", message: "Provide messageId, language and 1–4000 characters of text.", details: nil)); return
      }
      let request = playbackRequestId(args, result: result)
      guard request.valid else { return }
      guard UIApplication.shared.applicationState == .active else {
        if receivingEnabled { notify(messageId: id) }
        result(FlutterError(code: "foreground_required", message: "Open the app to play this message. Background automatic speech is unavailable on iOS.", details: nil)); return
      }
      let onlyHeadphones = args["headphonesOnly"] as? Bool ?? false
      guard !onlyHeadphones || headphonesConnected else {
        result(FlutterError(code: "headphones_required", message: "Connect headphones to play this private message.", details: nil)); return
      }
      let voices = AVSpeechSynthesisVoice.speechVoices()
      let languageBase = language.split(separator: "-").first?.lowercased()
      guard let voice = voices.first(where: { $0.language.lowercased() == language.lowercased() })
              ?? voices.first(where: { $0.language.split(separator: "-").first?.lowercased() == languageBase }) else {
        result(FlutterError(code: "voice_unavailable", message: "Install an available voice for \(language) in iOS speech settings.", details: nil)); return
      }
      stop(reason: "replaced_by_new_playback")
      do {
        // Ambient respects the silent switch. No background audio category or mode is enabled.
        try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {
        result(FlutterError(code: "audio_session_unavailable", message: "Audio is busy. Replay when the current call or audio session ends.", details: nil)); return
      }
      let utterance = AVSpeechUtterance(string: text)
      utterance.voice = voice
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate
      activeMessageId = id
      activePlaybackRequestId = request.id
      activeUtterance = utterance
      headphonesRequired = onlyHeadphones
      startedOnHeadphones = headphonesConnected
      synthesizer.speak(utterance)
      result(true)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private var headphonesConnected: Bool {
    AVAudioSession.sharedInstance().currentRoute.outputs.contains {
      // Generic Bluetooth/USB ports also describe speakers or car kits.
      $0.portType == .headphones
    }
  }

  private func notify(messageId: String) {
    let content = UNMutableNotificationContent()
    content.title = "Mine2YourLingo message"
    content.body = "Open the app to read or replay your translated message."
    content.userInfo = ["messageId": messageId]
    // Notification only; no transcript, custom audio, or attempt to wake a speech loop.
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "message-\(messageId)", content: content, trigger: nil))
  }

  private func playbackRequestId(_ args: [String: Any], result: FlutterResult) -> (valid: Bool, id: String?) {
    guard args.keys.contains("playbackRequestId") else { return (true, nil) }
    guard let id = args["playbackRequestId"] as? String, (1...128).contains(id.utf8.count),
          id.utf8.allSatisfy({ byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 95 || byte == 45
          }) else {
      result(FlutterError(code: "invalid_playback_request_id", message: "playbackRequestId must contain 1–128 ASCII letters, digits, underscores or hyphens.", details: nil))
      return (false, nil)
    }
    return (true, id)
  }

  private func emit(_ event: String, id: String, requestId: String?, reason: String? = nil) {
    var payload: [String: Any] = ["messageId": id]
    if let requestId = requestId { payload["playbackRequestId"] = requestId }
    if let reason = reason { payload["reason"] = reason }
    if Thread.isMainThread { channel.invokeMethod(event, arguments: payload) }
    else { DispatchQueue.main.async { [weak self] in self?.channel.invokeMethod(event, arguments: payload) } }
  }

  private func stop(reason: String) {
    let id = activeMessageId
    let requestId = activePlaybackRequestId
    activeMessageId = nil; activePlaybackRequestId = nil; activeUtterance = nil
    synthesizer.stopSpeaking(at: .immediate)
    mediaTask?.cancel(); mediaTask = nil
    mediaSession?.invalidateAndCancel(); mediaSession = nil
    mediaPlayer?.stop(); mediaPlayer = nil
    mediaData.removeAll(keepingCapacity: false)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    headphonesRequired = false; startedOnHeadphones = false
    if let id = id { emit("playbackError", id: id, requestId: requestId, reason: reason) }
  }

  private func playAudio(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let id = args["messageId"] as? String,
          let address = args["url"] as? String, !id.isEmpty, id.count <= 200, address.count <= 4096,
          let url = URL(string: address), let host = url.host?.lowercased(), url.user == nil, url.password == nil, url.fragment == nil else {
      result(FlutterError(code: "invalid_arguments", message: "Provide messageId and an authorized audio URL.", details: nil)); return
    }
    let playbackRequest = playbackRequestId(args, result: result)
    guard playbackRequest.valid else { return }
    #if DEBUG
    let debugLoopback = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    #else
    let debugLoopback = false
    #endif
    guard url.scheme == "https" || (debugLoopback && url.scheme == "http") else {
      result(FlutterError(code: "insecure_audio_url", message: "Use an authorized HTTPS audio URL; HTTP is permitted only for debug loopback development.", details: nil)); return
    }
    guard UIApplication.shared.applicationState == .active else {
      if receivingEnabled { notify(messageId: id) }
      result(FlutterError(code: "foreground_required", message: "Open the app to play this message. Background automatic audio is unavailable on iOS.", details: nil)); return
    }
    let onlyHeadphones = args["headphonesOnly"] as? Bool ?? false
    guard !onlyHeadphones || headphonesConnected else {
      result(FlutterError(code: "headphones_required", message: "An active route explicitly identified as headphones is required.", details: nil)); return
    }
    stop(reason: "replaced_by_new_playback")
    activeMessageId = id
    activePlaybackRequestId = playbackRequest.id
    headphonesRequired = onlyHeadphones
    startedOnHeadphones = headphonesConnected
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    request.setValue("audio/*", forHTTPHeaderField: "Accept")
    if let headers = args["headers"] as? [String: String] {
      for (key, value) in headers where ["authorization", "accept"].contains(key.lowercased()) {
        request.setValue(value, forHTTPHeaderField: key)
      }
    }
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.timeoutIntervalForRequest = 20
    config.timeoutIntervalForResource = 30
    let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    mediaSession = session
    let task = session.dataTask(with: request)
    mediaTask = task
    task.resume()
    result(true)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void) {
    // Never follow redirects with an authenticated private-audio request.
    completionHandler(nil)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                  completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard dataTask === mediaTask, let response = response as? HTTPURLResponse,
          response.statusCode == 200, response.expectedContentLength <= 4_000_000,
          response.mimeType?.lowercased().hasPrefix("audio/") == true else {
      completionHandler(.cancel)
      if dataTask === mediaTask { stop(reason: "audio_download_failed") }
      return
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard dataTask === mediaTask else { return }
    guard mediaData.count + data.count <= 4_000_000 else { stop(reason: "audio_size_limit"); return }
    mediaData.append(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard task === mediaTask, let id = activeMessageId else { return }
    guard error == nil, !mediaData.isEmpty else { stop(reason: "audio_download_failed"); return }
    guard UIApplication.shared.applicationState == .active else { stop(reason: "app_backgrounded"); return }
    guard !headphonesRequired || headphonesConnected else { stop(reason: "headphones_disconnected"); return }
    mediaTask = nil
    mediaSession?.finishTasksAndInvalidate(); mediaSession = nil
    do {
      try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
      try AVAudioSession.sharedInstance().setActive(true)
      let player = try AVAudioPlayer(data: mediaData)
      mediaData.removeAll(keepingCapacity: false)
      player.delegate = self
      mediaPlayer = player
      guard player.prepareToPlay(), player.play() else { stop(reason: "audio_start_failed"); return }
      emit("playbackStarted", id: id, requestId: activePlaybackRequestId)
    } catch { stop(reason: "audio_decode_failed") }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.audioPlayerDidFinishPlaying(player, successfully: flag) }; return
    }
    guard player === mediaPlayer, let id = activeMessageId else { return }
    if !flag { stop(reason: "audio_playback_failed"); return }
    let requestId = activePlaybackRequestId
    activeMessageId = nil; activePlaybackRequestId = nil; mediaPlayer = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    emit("playbackCompleted", id: id, requestId: requestId)
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.audioPlayerDecodeErrorDidOccur(player, error: error) }; return
    }
    if player === mediaPlayer { stop(reason: "audio_decode_failed") }
  }

  @objc private func routeChanged(_ notification: Notification) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.routeChanged(notification) }; return
    }
    guard activeMessageId != nil else { return }
    let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
    if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue ||
         ((headphonesRequired || startedOnHeadphones) && !headphonesConnected) {
      stop(reason: "headphones_disconnected")
    }
  }

  @objc private func interrupted(_ notification: Notification) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.interrupted(notification) }; return
    }
    if let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
       raw == AVAudioSession.InterruptionType.began.rawValue { stop(reason: "audio_interrupted") }
  }

  @objc private func backgrounded() { stop(reason: "app_backgrounded") }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.speechSynthesizer(synthesizer, didStart: utterance) }; return
    }
    if activeUtterance === utterance, let id = activeMessageId { emit("playbackStarted", id: id, requestId: activePlaybackRequestId) }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.speechSynthesizer(synthesizer, didFinish: utterance) }; return
    }
    guard activeUtterance === utterance, let id = activeMessageId else { return }
    let requestId = activePlaybackRequestId
    activeMessageId = nil; activePlaybackRequestId = nil; activeUtterance = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    emit("playbackCompleted", id: id, requestId: requestId)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.speechSynthesizer(synthesizer, didCancel: utterance) }; return
    }
    if activeUtterance === utterance { stop(reason: "speech_cancelled") }
  }
}
