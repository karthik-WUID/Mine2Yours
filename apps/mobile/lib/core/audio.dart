import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';

import 'languages.dart';
import 'api.dart';

class AudioService {
  AudioRecorder? _recorder;
  AudioRecorder get recorder => _recorder ??= AudioRecorder();
  final SpeechToText recognizer;
  final webTts = FlutterTts();
  static const channel = MethodChannel('com.mine2yourlingo/audio');
  StreamSubscription<Uint8List>? _subscription;
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  DateTime? _started;
  Timer? _limit;
  bool recording = false;
  bool dictating = false;
  String _recognized = '';
  String? _playing;
  String? _playingRequestId;
  int _playbackGeneration = 0;
  Completer<void>? _dictationDone;
  VoidCallback? _onDictationDone;
  void Function(String)? _onDictationText;
  String? _dictationError;
  String _dictationLanguage = 'en';
  final inputLevel = ValueNotifier<double>(0);
  bool _continuousDictation = false;
  String _dictationPrefix = '', _dictationSegment = '', _dictationLocale = '';
  Timer? _dictationRestart;
  int _dictationTicket = 0;
  int _captureGeneration = 0;

  void _setInputLevel(double value) {
    if (!_disposed) inputLevel.value = value.clamp(0.0, 1.0);
  }

  void _segmentEnded() {
    if (!dictating || _dictationDone == null) return;
    if (!_continuousDictation) {
      _completeDictation();
      return;
    }
    // Wait for final words before restarting a service-limited utterance.
    if (_dictationRestart != null) return;
    final ticket = _dictationTicket;
    _dictationRestart = Timer(const Duration(milliseconds: 450), () async {
      _dictationRestart = null;
      if (!dictating || !_continuousDictation || ticket != _dictationTicket) {
        return;
      }
      _dictationPrefix = [
        _dictationPrefix,
        _dictationSegment,
      ].where((part) => part.trim().isNotEmpty).join(' ').trim();
      _dictationSegment = '';
      _recognized = _dictationPrefix;
      try {
        await _listenSegment();
      } catch (e) {
        if (ticket + 1 == _dictationTicket && dictating) {
          _dictationError = describeError(e);
          _completeDictation();
        }
      }
    });
  }

  Future<void> _listenSegment() async {
    final ticket = ++_dictationTicket;
    await recognizer.listen(
      onResult: (result) {
        if (!dictating || ticket != _dictationTicket) return;
        _dictationSegment = result.recognizedWords;
        _recognized = [
          _dictationPrefix,
          _dictationSegment,
        ].where((part) => part.trim().isNotEmpty).join(' ').trim();
        _onDictationText?.call(_recognized);
      },
      onSoundLevelChange: (level) {
        if (dictating && ticket == _dictationTicket) {
          _setInputLevel((level + 2) / 14);
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: _dictationLocale,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 7),
        cancelOnError: true,
        partialResults: true,
      ),
    );
  }

  final _playbackEvents = StreamController<Map<String, dynamic>>.broadcast();
  bool _disposed = false;
  final languageStatus = ValueNotifier<Map<String, Map<String, dynamic>>>({});
  void _languageEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    final language = event['language']?.toString();
    if (language == null) return;
    languageStatus.value = {
      ...languageStatus.value,
      language: {...?languageStatus.value[language], ...event},
    };
  }

  Future<void> prepareLanguage(String language, {bool retry = false}) async {
    await prepareTranslationLanguage(language);
    if (AppLanguage.defaults.contains(language)) return;
    final previous = languageStatus.value[language]?['phase'];
    if (!retry &&
        ['queued', 'checking', 'downloading', 'installed'].contains(previous)) {
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _languageEvent({
        'language': language,
        'phase': 'manual',
        'message': 'Install this language in your device speech service. This platform does not expose automatic speech-model downloads.',
      });
      return;
    }
    _languageEvent({'language': language, 'phase': 'queued'});
    try {
      final result = await channel.invokeMethod('prepareLanguage', {
        'language': language,
        'locale': AppLanguage.of(language).locale,
      });
      if (!retry && result is Map && result['phase'] != 'permission') {
        await _ensureReadingVoice(language);
      }
    } catch (e) {
      _languageEvent({
        'language': language,
        'phase': 'error',
        'message': describeError(e),
      });
    }
  }

  static bool quantitiesChanged(String source, String translated) {
    List<String> numbers(String text) {
      final normalized = text.replaceAllMapped(
        RegExp(r'[০-৯०-९௦-௯୦-୯౦-౯೦-೯൦-൯٠-٩]'),
        (match) {
          final point = match.group(0)!.runes.first;
          final base = [
            0x09e6,
            0x0966,
            0x0be6,
            0x0b66,
            0x0c66,
            0x0ce6,
            0x0d66,
            0x0660,
          ].firstWhere((base) => point >= base && point <= base + 9);
          return '${point - base}';
        },
      );
      return RegExp(r'[0-9]+(?:[.,][0-9]+)?')
          .allMatches(normalized)
          .map((match) => match.group(0)!)
          .toList()
        ..sort();
    }

    return !listEquals(numbers(source), numbers(translated));
  }

  Future<void> prepareTranslationLanguage(String language) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _disposed) {
      return;
    }
    if ([
      'downloading',
      'ready',
    ].contains(languageStatus.value[language]?['translationPhase'])) {
      return;
    }
    try {
      await channel.invokeMethod('prepareTranslation', {'language': language});
    } catch (e) {
      _languageEvent({
        'language': language,
        'translationPhase': 'error',
        'translationCode': e is PlatformException
            ? e.code
            : 'translation_initialization_failed',
        'translationMessage': describeError(e),
      });
    }
  }

  Future<String> translateOnDevice(
    String text,
    String source,
    String target,
  ) async {
    if (source == target) return text;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw Exception(
        'Free device translation is available in the Android app.',
      );
    }
    final value = await channel
        .invokeMethod<String>('translateOnDevice', {
          'text': text,
          'source': source,
          'target': target,
        })
        .timeout(const Duration(seconds: 95));
    if (value == null || value.trim().isEmpty) {
      throw Exception('No translation was produced.');
    }
    return value;
  }

  final _voiceInstallAttempts = <String>{};
  Future<void> _ensureReadingVoice(String language) async {
    if (_disposed || !_voiceInstallAttempts.add(language)) return;
    final caps = await capabilities();
    if (_disposed) return;
    final ready = (caps['voices'] as List? ?? []).any(
      (voice) =>
          voice['language']?.toString().replaceAll('_', '-').split('-').first ==
          language,
    );
    if (!ready) {
      _languageEvent({
        'language': language,
        'voiceMessage': 'Confirm the voice installer, then choose this language. Reading voice readiness is checked separately.',
      });
      try {
        await installVoiceData();
      } catch (e) {
        _languageEvent({
          'language': language,
          'voiceMessage': describeError(e),
        });
      }
    }
  }

  Future<void> installVoiceData() async {
    if (kIsWeb) {
      throw Exception('Install a voice in your computer’s speech settings.');
    }
    await channel.invokeMethod('installVoiceData');
  }

  Stream<Map<String, dynamic>> get playbackEvents => _playbackEvents.stream;
  void Function(String, String, String?, String?)? onPlayback;
  AudioService({SpeechToText? speechRecognizer})
    : recognizer = speechRecognizer ?? SpeechToText() {
    if (!kIsWeb) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'translationDownload' && call.arguments is Map) {
          _languageEvent(Map<String, dynamic>.from(call.arguments));
          return;
        }
        final args = Map<String, dynamic>.from(call.arguments as Map);
        if (call.method == 'languagePermissionGranted') {
          unawaited(_ensureReadingVoice(args['language'].toString()));
          return;
        }
        if (call.method == 'languageDownload') {
          _languageEvent(args);
          return;
        }
        _emitPlayback(
          args['messageId']?.toString() ?? '',
          call.method,
          args['reason']?.toString(),
          args['playbackRequestId'] as String?,
        );
      });
    } else {
      webTts.setStartHandler(() {
        if (_playing != null) {
          _emitPlayback(_playing!, 'playbackStarted', null, _playingRequestId);
        }
      });
      webTts.setCompletionHandler(() {
        if (_playing != null) {
          _emitPlayback(
            _playing!,
            'playbackCompleted',
            null,
            _playingRequestId,
          );
        }
        _playing = null;
        _playingRequestId = null;
      });
      webTts.setErrorHandler((error) {
        if (_playing != null) {
          _emitPlayback(
            _playing!,
            'playbackError',
            error.toString(),
            _playingRequestId,
          );
        }
        _playing = null;
        _playingRequestId = null;
      });
    }
  }

  void _emitPlayback(
    String messageId,
    String event,
    String? reason,
    String? playbackRequestId,
  ) {
    if (!_playbackEvents.isClosed) {
      _playbackEvents.add({
        'messageId': messageId,
        'event': event,
        'reason': reason,
        'playbackRequestId': playbackRequestId,
      });
    }
    onPlayback?.call(messageId, event, reason, playbackRequestId);
  }

  static String describeError(Object error) => error is PlatformException
      ? error.message ??
            'Voice is unavailable. Check your phone’s voice settings.'
      : ApiClient.describe(error);

  static String speechError(String code, String language) => switch (code) {
    'error_permission' =>
      'Allow microphone access in your phone’s app settings, then try again.',
    'error_language_not_supported' || 'error_language_unavailable' =>
      '${AppLanguage.of(language).name} is not available in this phone’s speech service. Install its speech language, choose another test language, or type instead.',
    'error_network' || 'error_network_timeout' || 'error_server' => 'Your phone’s speech service could not connect. Check internet access or use a downloaded speech language.',
    'error_busy' =>
      'The microphone is busy. Stop other voice apps and try again.',
    'error_no_match' || 'error_speech_timeout' => 'No words were detected. Tap the microphone and speak clearly, or type instead.',
    _ =>
      'Your phone could not recognize speech. Try again or type your message.',
  };

  static String recognitionLocale(String language, Iterable<String> reported) {
    final preferred = AppLanguage.of(language).locale;
    final locales = reported.toList();
    String normalized(String value) => value.replaceAll('_', '-').toLowerCase();
    for (final value in locales) {
      if (normalized(value) == normalized(preferred)) return value;
    }
    for (final value in locales) {
      if (normalized(value).split('-').first == language) return value;
    }
    // The plugin's list may omit languages supported by online recognition.
    // Ask the service for the requested language; never substitute another one.
    return preferred;
  }

  void _completeDictation() {
    final done = _dictationDone;
    if (done == null || done.isCompleted) return;
    _continuousDictation = false;
    _dictationRestart?.cancel();
    _dictationRestart = null;
    _limit?.cancel();
    dictating = false;
    _setInputLevel(0);
    done.complete();
    _onDictationDone?.call();
  }

  Future<void> startRecording(VoidCallback onLimit) async {
    final generation = ++_captureGeneration;
    if (!await recorder.hasPermission()) {
      throw Exception(
        'Microphone permission is needed to record. Enable it in device settings.',
      );
    }
    if (_disposed || generation != _captureGeneration) {
      throw Exception('Recording cancelled.');
    }
    _pcm.clear();
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    if (_disposed || generation != _captureGeneration) {
      await recorder.stop();
      throw Exception('Recording cancelled.');
    }
    _subscription = stream.listen((chunk) {
      _pcm.add(chunk);
      final data = ByteData.sublistView(chunk);
      double squares = 0;
      for (var i = 0; i + 1 < chunk.length; i += 2) {
        final sample = data.getInt16(i, Endian.little) / 32768;
        squares += sample * sample;
      }
      if (chunk.length >= 2) {
        _setInputLevel(math.sqrt(squares / (chunk.length ~/ 2)) * 5);
      }
    });
    recording = true;
    _started = DateTime.now();
    _limit = Timer(const Duration(seconds: 60), onLimit);
  }

  Future<Map<String, dynamic>> finishRecording() async {
    _limit?.cancel();
    await recorder.stop();
    await _subscription?.cancel();
    recording = false;
    _setInputLevel(0);
    final pcm = _pcm.takeBytes();
    final seconds = pcm.length / 32000;
    if (seconds < 0.3) {
      throw Exception('Recording was too short. Please try again.');
    }
    final header = ByteData(44);
    void word(int offset, String value) {
      for (int i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    word(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    word(8, 'WAVE');
    word(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, 32000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    word(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    return {
      'audioBase64': base64Encode(
        Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]),
      ),
      'mimeType': 'audio/wav',
      'durationSeconds': seconds,
      'idempotencyKey': const Uuid().v4(),
    };
  }

  Future<void> startDictation(
    String language,
    void Function(String) onText,
    VoidCallback onDone, {
    bool continuous = false,
  }) async {
    final generation = ++_captureGeneration;
    _dictationError = null;
    _dictationLanguage = language;
    if (!await recognizer.initialize(
      onError: (e) {
        if (_continuousDictation &&
            dictating &&
            ['error_no_match', 'error_speech_timeout'].contains(e.errorMsg)) {
          _segmentEnded();
          return;
        }
        _dictationError = speechError(e.errorMsg, _dictationLanguage);
        _completeDictation();
      },
      onStatus: (status) {
        // notListening precedes final words; finishing then lost transcripts.
        if (status == 'done') _segmentEnded();
      },
      options: [SpeechToText.androidNoBluetooth],
    )) {
      throw Exception(
        _dictationError ?? 'Speech input is not enabled on this phone. Allow microphone access and check voice input settings, or type instead.',
      );
    }
    final locales = await recognizer.locales();
    if (_disposed || generation != _captureGeneration) {
      throw Exception('Recording cancelled.');
    }
    _recognized = '';
    _dictationPrefix = '';
    _dictationSegment = '';
    _dictationLocale = recognitionLocale(
      language,
      locales.map((l) => l.localeId),
    );
    _started = DateTime.now();
    _dictationDone = Completer<void>();
    _onDictationDone = onDone;
    _onDictationText = onText;
    _continuousDictation = continuous;
    dictating = true;
    if (continuous) {
      _limit = Timer(const Duration(seconds: 60), _completeDictation);
    }
    try {
      await _listenSegment();
    } catch (_) {
      await cancel();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> finishDictation() async {
    _continuousDictation = false;
    _dictationRestart?.cancel();
    _dictationRestart = null;
    _limit?.cancel();
    await recognizer.stop();
    await _dictationDone?.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    dictating = false;
    _onDictationText = null;
    _onDictationDone = null;
    _dictationDone = null;
    _setInputLevel(0);
    if (_recognized.trim().isEmpty) {
      throw Exception(
        _dictationError ?? 'No words were detected. Please type or try again.',
      );
    }
    return {
      'text': _recognized,
      'durationSeconds':
          DateTime.now().difference(_started!).inMilliseconds / 1000,
      'idempotencyKey': const Uuid().v4(),
    };
  }

  Future<Map<String, dynamic>> capabilities() async {
    if (kIsWeb) {
      return {
        'platform': 'web',
        'automaticBackgroundPlayback': false,
        'foregroundPlayback': true,
      };
    }
    try {
      return Map<String, dynamic>.from(
        await channel.invokeMethod('getCapabilities'),
      );
    } on MissingPluginException {
      return {
        'platform': defaultTargetPlatform.name,
        'foregroundPlayback': false,
      };
    }
  }

  Future<void> receive(bool active) async {
    if (!kIsWeb) {
      await channel.invokeMethod(active ? 'startReceiving' : 'stopReceiving');
    }
  }

  Future<void> openVoiceSettings({bool speechInput = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw Exception(
        'Open your device settings and look for speech or text-to-speech languages.',
      );
    }
    await channel.invokeMethod(
      speechInput ? 'openSpeechSettings' : 'openVoiceSettings',
    );
  }

  Future<void> speak(
    String id,
    String text,
    String language, {
    bool headphonesOnly = false,
    int? stopAtEpochMillis,
    String? playbackRequestId,
  }) async {
    final generation = ++_playbackGeneration;
    void checkCurrent() {
      if (generation != _playbackGeneration ||
          (stopAtEpochMillis != null &&
              DateTime.now().millisecondsSinceEpoch >= stopAtEpochMillis)) {
        throw Exception('Playback was cancelled or quiet hours began.');
      }
    }

    checkCurrent();
    if (kIsWeb) {
      if (headphonesOnly) {
        throw Exception(
          'Headphone routing cannot be verified in this browser. Use the mobile app.',
        );
      }
      final available = await webTts.isLanguageAvailable(
        AppLanguage.of(language).locale,
      );
      checkCurrent();
      if (available != true) {
        throw Exception(
          'No ${AppLanguage.of(language).name} voice installed. The transcript remains available.',
        );
      }
      _playing = null;
      _playingRequestId = null;
      await webTts.stop();
      checkCurrent();
      await webTts.setLanguage(AppLanguage.of(language).locale);
      await webTts.setSpeechRate(0.45);
      checkCurrent();
      _playing = id;
      _playingRequestId = playbackRequestId;
      await webTts.speak(text);
    } else {
      await channel.invokeMethod('speak', {
        'messageId': id,
        'text': text,
        'language': AppLanguage.of(language).locale,
        'headphonesOnly': headphonesOnly,
        'stopAtEpochMillis': ?stopAtEpochMillis,
        'playbackRequestId': ?playbackRequestId,
      });
    }
  }

  Future<void> stopPlayback() async {
    final generation = ++_playbackGeneration;
    if (kIsWeb) {
      _playing = null;
      _playingRequestId = null;
      await webTts.stop();
      if (generation == _playbackGeneration) {
        _playing = null;
        _playingRequestId = null;
      }
    } else {
      await channel.invokeMethod('stopPlayback');
    }
  }

  Future<void> playRemote(
    String id,
    String url,
    Map<String, String> headers, {
    bool headphonesOnly = false,
    int? stopAtEpochMillis,
    String? playbackRequestId,
  }) async {
    if (kIsWeb) {
      throw Exception('Use the mobile app to play generated cloud audio.');
    }
    await channel.invokeMethod('playAudio', {
      'messageId': id,
      'url': url,
      'headers': headers,
      'headphonesOnly': headphonesOnly,
      'stopAtEpochMillis': ?stopAtEpochMillis,
      'playbackRequestId': ?playbackRequestId,
    });
  }

  Future<void> cancel() async {
    ++_captureGeneration;
    ++_dictationTicket;
    _continuousDictation = false;
    _dictationRestart?.cancel();
    _dictationRestart = null;
    _limit?.cancel();
    _setInputLevel(0);
    if (recording) {
      await recorder.stop();
      await _subscription?.cancel();
    }
    final wasDictating = dictating;
    _onDictationText = null;
    _onDictationDone = null;
    final done = _dictationDone;
    _dictationDone = null;
    if (done != null && !done.isCompleted) done.complete();
    if (wasDictating) await recognizer.cancel();
    recording = false;
    dictating = false;
    _pcm.clear();
  }

  Future<void> dispose() async {
    _disposed = true;
    await cancel();
    await _recorder?.dispose();
    await stopPlayback();
    await _playbackEvents.close();
    languageStatus.dispose();
    inputLevel.dispose();
  }
}
