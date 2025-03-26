import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/processed_text.dart';
import '../utils/language_constants.dart';

// 텍스트 음성 변환 서비스를 제공합니다

enum TtsState { playing, stopped, paused, continued }

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  FlutterTts? _flutterTts;
  TtsState _ttsState = TtsState.stopped;
  String _currentLanguage = SourceLanguage.DEFAULT; // 기본 언어: 중국어

  // 현재 재생 중인 세그먼트 인덱스
  int? _currentSegmentIndex;

  // 재생 상태 변경 콜백
  Function(int?)? _onPlayingStateChanged;

  // 재생 완료 콜백
  Function? _onPlayingCompleted;

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

      // 재생 완료 콜백 호출
      if (_onPlayingCompleted != null) {
        _onPlayingCompleted!();
      }
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
    
    // TTS에 맞는 언어 코드로 변환
    final ttsLanguageCode = TtsLanguage.getTtsLanguageCode(language);
    await _flutterTts?.setLanguage(ttsLanguageCode);

    // 언어에 따른 음성 설정
    final voiceName = TtsLanguage.getVoiceName(ttsLanguageCode);
    await _flutterTts?.setVoice({"name": voiceName, "locale": ttsLanguageCode});
    
    // 언어별 발화 속도 조정
    double speechRate = 0.5;  // 기본값
    
    // MARK: 다국어 지원을 위한 확장 포인트
    // 언어별로 다른 발화 속도 설정
    switch (language) {
      case SourceLanguage.CHINESE:
      case SourceLanguage.CHINESE_TRADITIONAL:
        speechRate = 0.5;  // 중국어는 조금 느리게
        break;
      case SourceLanguage.KOREAN:
        speechRate = 0.5;  // 한국어
        break;
      case SourceLanguage.ENGLISH:
        speechRate = 0.6;  // 영어는 조금 빠르게
        break;
      case SourceLanguage.JAPANESE:
        speechRate = 0.5;  // 일본어
        break;
      default:
        speechRate = 0.5;  // 기본값
    }
    
    await _flutterTts?.setSpeechRate(speechRate);
    await _flutterTts?.setVolume(1.0);
    await _flutterTts?.setPitch(1.0);
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

    // 현재 재생 중인 세그먼트 초기화
    _updateCurrentSegment(null);
  }

  // 재생 일시정지
  Future<void> pause() async {
    if (_flutterTts == null) return;

    await _flutterTts?.pause();
    _ttsState = TtsState.paused;
  }

  // 현재 상태 확인
  TtsState get state => _ttsState;

  // 현재 재생 중인 세그먼트 인덱스
  int? get currentSegmentIndex => _currentSegmentIndex;

  // 현재 설정된 언어
  String get currentLanguage => _currentLanguage;

  // 리소스 해제
  Future<void> dispose() async {
    if (_flutterTts == null) return;

    await _flutterTts?.stop();
    _flutterTts = null;
    _onPlayingStateChanged = null;
    _onPlayingCompleted = null;
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

  // 재생 상태 변경 콜백 설정
  void setOnPlayingStateChanged(Function(int?) callback) {
    _onPlayingStateChanged = callback;
  }

  // 재생 완료 콜백 설정
  void setOnPlayingCompleted(Function callback) {
    _onPlayingCompleted = callback;
  }

  // 현재 재생 중인 세그먼트 업데이트
  void _updateCurrentSegment(int? segmentIndex) {
    _currentSegmentIndex = segmentIndex;
    if (_onPlayingStateChanged != null) {
      _onPlayingStateChanged!(_currentSegmentIndex);
    }
  }

  /// **세그먼트 단위로 텍스트 읽기**
  /// - segmentIndex: 재생할 세그먼트 인덱스
  /// - text: 재생할 텍스트
  Future<void> speakSegment(String text, int segmentIndex) async {
    if (_flutterTts == null) await init();

    // 이미 재생 중인 경우 중지
    if (_currentSegmentIndex != null) {
      await stop();
    }

    // 현재 재생 중인 세그먼트 업데이트
    _updateCurrentSegment(segmentIndex);

    // 텍스트 재생
    if (text.isNotEmpty) {
      await _flutterTts?.speak(text);
    }
  }

  /// **ProcessedText의 모든 세그먼트 순차적으로 읽기**
  Future<void> speakAllSegments(ProcessedText processedText) async {
    if (_flutterTts == null) await init();

    // 이미 재생 중이면 중지
    if (_ttsState == TtsState.playing) {
      await stop();
      return;
    }

    // 전체 원문 텍스트 읽기
    if (processedText.fullOriginalText.isNotEmpty) {
      _ttsState = TtsState.playing;
      await speak(processedText.fullOriginalText);
      return;
    }

    // 세그먼트가 있는 경우 각 세그먼트 순차 재생
    if (processedText.segments != null && processedText.segments!.isNotEmpty) {
      _ttsState = TtsState.playing;
      for (var segment in processedText.segments!) {
        if (_ttsState != TtsState.playing) break;
        await speak(segment.originalText);
        // 세그먼트 간 짧은 간격 추가
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }
}
