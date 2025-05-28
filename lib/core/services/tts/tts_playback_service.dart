import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../cache/unified_cache_service.dart';

/// TTS 상태
enum TtsState { playing, stopped, paused }

/// TTS 재생 서비스
/// 오디오 파일 재생과 캐싱만 담당 (세그먼트 관리는 TTSService에서 처리)
class TtsPlaybackService {
  // 싱글톤 패턴
  static final TtsPlaybackService _instance = TtsPlaybackService._internal();
  factory TtsPlaybackService() => _instance;
  TtsPlaybackService._internal();

  // 오디오 재생 관련
  late AudioPlayer _audioPlayer = AudioPlayer();
  TtsState _ttsState = TtsState.stopped;
  bool _isSpeaking = false;

  // 캐시 서비스
  final UnifiedCacheService _cacheService = UnifiedCacheService();

  // 초기화 상태
  bool _isInitialized = false;

  // 스트림 구독 관리
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playbackEventSubscription;

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _cacheService.initialize();
      await _setupEventHandlers();
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('TTS 재생 서비스 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTS 재생 서비스 초기화 실패: $e');
      }
      rethrow;
    }
  }

  /// 현재 상태
  TtsState get state => _ttsState;

  /// 현재 재생 중 여부
  bool get isSpeaking => _isSpeaking;

  /// 캐시에서 파일 경로 가져오기
  Future<String?> getCachedFilePath(String text) async {
    return await _cacheService.getTtsPath(text);
  }

  /// 오디오 데이터를 캐시에 저장
  Future<String?> cacheAudioData(String text, Uint8List audioData) async {
    return await _cacheService.cacheTts(text, audioData);
  }

  /// 오디오 파일 재생
  Future<void> playAudioFile(String filePath) async {
    try {
      // 파일이 존재하는지 확인
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ 오디오 파일이 존재하지 않음: $filePath');
        _isSpeaking = false;
        return;
      }

      // 먼저 이전 재생 중지 및 리소스 해제
      await _audioPlayer.stop();
      
      // 파일 경로 설정
      await _audioPlayer.setFilePath(filePath);
      
      // 실제 재생 시작
      await _audioPlayer.play();
      _isSpeaking = true;
      _ttsState = TtsState.playing;
      debugPrint('▶️ 오디오 재생 시작: $filePath');
      
      // 안전장치: 10초 후 강제 종료 (무한 재생 방지)
      Future.delayed(const Duration(seconds: 10), () {
        if (_isSpeaking) {
          debugPrint('⚠️ 오디오 재생 타임아웃으로 강제 종료');
          _isSpeaking = false;
          _ttsState = TtsState.stopped;
        }
      });
    } catch (e) {
      debugPrint('❌ 오디오 파일 재생 중 오류: $e');
      _isSpeaking = false;
      _ttsState = TtsState.stopped;
    }
  }

  /// 재생 중지
  Future<void> stop() async {
    try {
      debugPrint('⏹️ TTS 재생 중지 요청');
      if (_audioPlayer != null) {
        await _audioPlayer.stop();
        _ttsState = TtsState.stopped;
      }
      _isSpeaking = false;
      debugPrint('✅ TTS 재생 중지 완료');
    } catch (e) {
      debugPrint('❌ TTS 중지 중 오류: $e');
      // 오류가 발생해도 상태는 초기화
      _ttsState = TtsState.stopped;
      _isSpeaking = false;
    }
  }

  /// 재생 일시정지
  Future<void> pause() async {
    await _audioPlayer.pause();
    _ttsState = TtsState.paused;
  }

  /// 리소스 해제
  Future<void> dispose() async {
    _isSpeaking = false;
    
    // 스트림 구독 취소
    await _playerStateSubscription?.cancel();
    await _playbackEventSubscription?.cancel();
    _playerStateSubscription = null;
    _playbackEventSubscription = null;
    
    await _audioPlayer.dispose();
    await _cacheService.clear();
    _isInitialized = false;
    if (kDebugMode) {
      debugPrint('TTS 재생 서비스 리소스 해제 완료');
    }
  }

  /// 캐시 비우기
  void clearCache() {
    _cacheService.clear();
    debugPrint('TTS 캐시 비움');
  }

  /// 이벤트 핸들러 초기화
  Future<void> _setupEventHandlers() async {
    // 기존 구독이 있으면 취소
    await _playerStateSubscription?.cancel();
    await _playbackEventSubscription?.cancel();
    
    // 재생 상태 변경 이벤트
    _playbackEventSubscription = _audioPlayer.playbackEventStream.listen((event) {
      if (event.processingState == ProcessingState.ready && _ttsState != TtsState.playing) {
        debugPrint("🎵 TtsPlaybackService: 오디오 준비 완료");
        _ttsState = TtsState.playing;
      }
    });

    // 재생 완료 이벤트
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        debugPrint("🎵 TtsPlaybackService: 재생 완료");
        _ttsState = TtsState.stopped;
        _isSpeaking = false;
      }
    });
  }
}
