import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum TtsState { playing, stopped, paused, continued }

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  FlutterTts? _flutterTts;
  TtsState _ttsState = TtsState.stopped;
  String _currentLanguage = 'zh-CN'; // 기본 언어: 중국어

  // 초기화
  Future<void> init() async {
    _flutterTts = FlutterTts();

    // 이벤트 리스너 설정
    _flutterTts?.setStartHandler(() {
      debugPrint("TTS 재생 시작");
      _ttsState = TtsState.playing;
    });

    _flutterTts?.setCompletionHandler(() {
      debugPrint("TTS 재생 완료");
      _ttsState = TtsState.stopped;
    });

    _flutterTts?.setCancelHandler(() {
      debugPrint("TTS 재생 취소");
      _ttsState = TtsState.stopped;
    });

    _flutterTts?.setPauseHandler(() {
      debugPrint("TTS 재생 일시정지");
      _ttsState = TtsState.paused;
    });

    _flutterTts?.setContinueHandler(() {
      debugPrint("TTS 재생 계속");
      _ttsState = TtsState.continued;
    });

    _flutterTts?.setErrorHandler((msg) {
      debugPrint("TTS 오류: $msg");
      _ttsState = TtsState.stopped;
    });

    // 언어 설정
    await setLanguage(_currentLanguage);
  }

  // 언어 설정
  Future<void> setLanguage(String language) async {
    if (_flutterTts == null) await init();

    _currentLanguage = language;
    await _flutterTts?.setLanguage(language);

    // 언어에 따른 음성 설정
    if (language == 'zh-CN') {
      // 중국어 음성 설정
      await _flutterTts
          ?.setVoice({"name": "zh-CN-Standard-A", "locale": "zh-CN"});
      await _flutterTts?.setSpeechRate(0.5); // 중국어는 조금 느리게
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);
    } else if (language == 'ko-KR') {
      // 한국어 음성 설정
      await _flutterTts
          ?.setVoice({"name": "ko-KR-Standard-A", "locale": "ko-KR"});
      await _flutterTts?.setSpeechRate(0.5);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);
    }
  }

  // 텍스트 읽기
  Future<void> speak(String text) async {
    if (_flutterTts == null) await init();

    if (text.isNotEmpty) {
      await _flutterTts?.speak(text);
    }
  }

  // 재생 중지
  Future<void> stop() async {
    if (_flutterTts == null) return;

    await _flutterTts?.stop();
    _ttsState = TtsState.stopped;
  }

  // 재생 일시정지
  Future<void> pause() async {
    if (_flutterTts == null) return;

    await _flutterTts?.pause();
    _ttsState = TtsState.paused;
  }

  // 현재 상태 확인
  TtsState get state => _ttsState;

  // 리소스 해제
  Future<void> dispose() async {
    if (_flutterTts == null) return;

    await _flutterTts?.stop();
    _flutterTts = null;
  }

  // 사용 가능한 언어 목록 가져오기
  Future<List<String>> getAvailableLanguages() async {
    if (_flutterTts == null) await init();

    try {
      final languages = await _flutterTts?.getLanguages;
      return languages?.cast<String>() ?? [];
    } catch (e) {
      debugPrint('언어 목록을 가져오는 중 오류 발생: $e');
      return [];
    }
  }

  // 사용 가능한 음성 목록 가져오기
  Future<List<dynamic>> getAvailableVoices() async {
    if (_flutterTts == null) await init();

    try {
      final voices = await _flutterTts?.getVoices;
      return voices ?? [];
    } catch (e) {
      debugPrint('음성 목록을 가져오는 중 오류 발생: $e');
      return [];
    }
  }
}
