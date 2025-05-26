import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import '../../../core/models/processed_text.dart';
import '../../utils/language_constants.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../common/plan_service.dart';
import 'dart:async';
import 'package:path/path.dart' as path;
import '../cache/unified_cache_service.dart';
import '../../../core/models/text_unit.dart';
import 'tts_api_service.dart';
import 'tts_playback_service.dart';

// TtsPlaybackService에서 TtsState 열거형 export
export 'tts_playback_service.dart' show TtsState;

// 텍스트 음성 변환 서비스를 제공합니다

/// 텍스트 음성 변환 서비스
/// TtsApiService와 TtsPlaybackService를 조율하여 TTS 기능을 제공합니다.
class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  
  // 서비스 인스턴스
  final TtsApiService _apiService = TtsApiService();
  final TtsPlaybackService _playbackService = TtsPlaybackService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // 초기화 여부
  bool _isInitialized = false;
  
  TTSService._internal();

  /// 초기화
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 하위 서비스 초기화
      await _apiService.initialize();
      await _playbackService.initialize();
      
      // 언어 설정
      await setLanguage(SourceLanguage.DEFAULT);
      
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('TTS 서비스 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTS 서비스 초기화 실패: $e');
      }
      rethrow;
    }
  }

  /// 언어 설정
  Future<void> setLanguage(String language) async {
    await _apiService.setLanguage(language);
  }

  /// 현재 설정된 언어
  String get currentLanguage => _apiService.currentLanguage;

  /// 텍스트 읽기
  Future<void> speak(String text) async {
    if (!_isInitialized) await init();
    
    // 이미 재생 중이면 중지하고 상태 초기화
    if (_playbackService.isSpeaking) {
      debugPrint('⏹️ 이미 재생 중이므로 중지 후 새로 시작');
      await stop();
      // 상태 초기화가 확실히 반영되도록 잠시 대기
      await Future.delayed(Duration(milliseconds: 300));
    }

    if (text.isEmpty) return;

    // 캐시된 TTS 확인
    final cachedPath = await _playbackService.getCachedFilePath(text);
    if (cachedPath != null) {
      // 캐시된 오디오 파일 재생
      await _playbackService.playAudioFile(cachedPath);
      debugPrint('💾 캐시된 TTS 재생: $text');
      return;
    }

    // 새로운 TTS 요청 처리
    try {
      debugPrint('🔊 TTS 새 요청');
      
      // 음성 합성
      final audioData = await _apiService.synthesizeSpeech(text);
      if (audioData != null) {
        // 오디오 데이터를 캐시에 저장
        final audioPath = await _playbackService.cacheAudioData(text, audioData);
        if (audioPath != null) {
          // 오디오 파일 재생
          await _playbackService.playAudioFile(audioPath);
          debugPrint('🔊 TTS 재생 중: $text');
          
          // 재생 완료 후 사용량 증가
          await _apiService.incrementTtsUsageAfterPlayback();
        } else {
          debugPrint('❌ TTS 캐시 저장 실패: $text');
        }
      } else {
        debugPrint('❌ TTS API 응답 없음: $text');
      }
    } catch (e) {
      debugPrint('❌ TTS 처리 중 오류: $e');
    }
  }

  /// 재생 중지
  Future<void> stop() async {
    await _playbackService.stop();
  }

  /// 재생 일시정지
  Future<void> pause() async {
    await _playbackService.pause();
  }

  /// 현재 상태 확인
  TtsState get state => _playbackService.state;

  /// 현재 재생 중인 세그먼트 인덱스
  int? get currentSegmentIndex => _playbackService.currentSegmentIndex;

  /// 리소스 해제
  Future<void> dispose() async {
    await _playbackService.dispose();
    _isInitialized = false;
  }

  /// **ProcessedText의 모든 세그먼트/문단 순차적으로 읽기**
  Future<void> speakAllSegments(ProcessedText processedText) async {
    if (!_isInitialized) await init();
    
    // 이미 재생 중이면 중지
    if (_playbackService.state == TtsState.playing) {
      await stop();
      return;
    }

    // 사용 가능 여부 확인
    final units = processedText.units;
    if (units.isEmpty) {
      debugPrint('읽을 내용이 없습니다');
      return;
    }

    // 모든 내용 순차 재생
    debugPrint("${units.length}개 항목 순차 재생 시작");
    _playbackService.setSegments(units);
    
    for (var i = 0; i < units.length; i++) {
      if (_playbackService.state != TtsState.playing) break;
      
      _playbackService.setCurrentSegmentIndex(i);
      
      try {
        await speak(units[i].originalText);
      } catch (e) {
        debugPrint('세그먼트 재생 중 오류: $e');
        continue;
      }
    }
  }

  /// **단일 세그먼트/문단 읽기**
  Future<void> speakSegment(String text, int segmentIndex) async {
    if (!_isInitialized) await init();
    if (text.isEmpty) return;
    
    // 현재 재생 중인 세그먼트 설정
    _playbackService.setCurrentSegmentIndex(segmentIndex);
    
    // 텍스트 읽기
    await speak(text);
  }
  
  /// 세그먼트 기반 읽기
  Future<void> speakSegments(ProcessedText text) async {
    if (!_playbackService.isSpeaking) await speakAllSegments(text);
  }

  /// 다음 세그먼트로 이동
  Future<void> nextSegment() async {
    await _playbackService.nextSegment(speak);
  }

  /// 이전 세그먼트로 이동
  Future<void> previousSegment() async {
    await _playbackService.previousSegment(speak);
  }

  /// 현재 세그먼트 다시 읽기
  Future<void> repeatCurrentSegment() async {
    await _playbackService.repeatCurrentSegment(speak);
  }

  /// 세그먼트 스트림 가져오기
  Stream<int>? get segmentStream => _playbackService.segmentStream;

  /// 캐시 비우기
  void clearCache() {
    _playbackService.clearCache();
  }

  /// 재생 상태 변경 콜백 설정
  void setOnPlayingStateChanged(Function(int?) callback) {
    _playbackService.setOnPlayingStateChanged(callback);
  }

  /// 재생 완료 콜백 설정
  void setOnPlayingCompleted(Function callback) {
    _playbackService.setOnPlayingCompleted(callback);
  }

  /// 전체 텍스트 읽기
  Future<void> speakFullText(ProcessedText text) async {
    if (!_playbackService.isSpeaking) await speakAllSegments(text);
  }
}
