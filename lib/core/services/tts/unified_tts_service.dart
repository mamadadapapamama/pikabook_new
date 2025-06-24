import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../utils/language_constants.dart';
import 'dart:async';
import '../../../core/models/text_unit.dart';
import 'tts_api_service.dart';
import 'tts_cache_service.dart';

/// TTS 모드 (일반 vs 느린)
enum TtsMode { normal, slow }

/// TTS 상태
enum TtsState { playing, stopped, paused }

/// 통합 TTS 서비스
/// 일반 TTS와 느린 TTS를 하나의 서비스로 통합 관리
class UnifiedTtsService {
  static final UnifiedTtsService _instance = UnifiedTtsService._internal();
  factory UnifiedTtsService() => _instance;
  
  // 서비스 인스턴스
  final TtsApiService _apiService = TtsApiService();
  final TTSCacheService _cacheService = TTSCacheService();
  
  // 오디오 재생 관련
  final AudioPlayer _audioPlayer = AudioPlayer();
  TtsState _ttsState = TtsState.stopped;
  bool _isSpeaking = false;
  TtsMode _currentMode = TtsMode.normal;
  
  // 스트림 구독 관리
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playbackEventSubscription;
  
  // 세그먼트 관리
  int? _currentSegmentIndex;
  List<TextUnit> _currentSegments = [];
  bool _isPlayingAll = false;

  // 콜백 (여러 리스너 지원) - 모드별로 분리
  final Map<TtsMode, List<Function(int?)>> _onPlayingStateChangedCallbacks = {
    TtsMode.normal: [],
    TtsMode.slow: [],
  };
  final Map<TtsMode, List<Function()>> _onPlayingCompletedCallbacks = {
    TtsMode.normal: [],
    TtsMode.slow: [],
  };
  
  // 초기화 여부
  bool _isInitialized = false;
  
  // 타임아웃 관리
  Timer? _timeoutTimer;
  static const Duration _playbackTimeout = Duration(seconds: 30); // 15초 → 30초로 증가
  
  UnifiedTtsService._internal();

  /// 초기화
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await _apiService.initialize();
      await _cacheService.initialize();
      await _setupEventHandlers();
      await setLanguage(SourceLanguage.DEFAULT);
      
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('✅ 통합 TTS 서비스 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 통합 TTS 서비스 초기화 실패: $e');
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

  /// 현재 상태 확인
  TtsState get state => _ttsState;

  /// 현재 재생 중 여부
  bool get isSpeaking => _isSpeaking;

  /// 현재 재생 중인 세그먼트 인덱스
  int? get currentSegmentIndex => _currentSegmentIndex;

  /// 현재 모드
  TtsMode get currentMode => _currentMode;

  /// 텍스트 읽기 (모드 지정 가능)
  Future<void> speak(String text, {TtsMode mode = TtsMode.normal}) async {
    try {
      if (!_isInitialized) await init();
      
      // 이미 재생 중이면 중지
      if (_isSpeaking) {
        await stop();
        await Future.delayed(const Duration(milliseconds: 50));
      }

      if (text.isEmpty) return;

      _currentMode = mode;
      
      // 모드별 캐시 확인
      final textHash = text.hashCode.toString();
      final cachePrefix = mode == TtsMode.slow ? 'slow_' : '';
      final voiceId = mode == TtsMode.slow ? 'slow_voice' : 'default';
      
      final cachedPath = await _cacheService.getTTSPath(
        noteId: 'temp',
        pageId: 'temp',
        segmentId: '$cachePrefix$textHash',
        voiceId: voiceId,
      );
      
      if (cachedPath != null) {
        await _playAudioFile(cachedPath, mode);
        debugPrint('💾 캐시된 ${mode == TtsMode.slow ? '느린' : '일반'} TTS 재생');
        return;
      }

      // 새로운 TTS 요청 처리
      await _processNewTtsRequest(text, textHash, mode);
      
    } catch (e) {
      debugPrint('❌ TTS speak() 오류: $e');
      await _handleTtsError('TTS 오류: $e');
    }
  }

  /// 세그먼트 읽기
  Future<void> speakSegment(String text, int segmentIndex, {TtsMode mode = TtsMode.normal}) async {
    if (!_isInitialized) await init();
    
    // 이미 같은 세그먼트가 재생 중이면 중지
    if (_isSpeaking && _currentSegmentIndex == segmentIndex && _currentMode == mode) {
      await stop();
      return;
    }
    
    _currentSegmentIndex = segmentIndex;
    _updateCurrentSegment(segmentIndex, mode);
    
    await speak(text, mode: mode);
  }

  /// 새로운 TTS 요청 처리
  Future<void> _processNewTtsRequest(String text, String textHash, TtsMode mode) async {
    try {
      debugPrint('🔊 ${mode == TtsMode.slow ? '느린' : '일반'} TTS 새 요청');
      
      // 모드별 파라미터 설정
      final String? voiceId;
      final double speed;
      final String cachePrefix;
      final String cacheVoiceId;
      
      if (mode == TtsMode.slow) {
        voiceId = 'hkfHEbBvdQFNX4uWHqRF'; // 느린 TTS용 voice 모델
        speed = 0.7; // 70% 속도
        cachePrefix = 'slow_';
        cacheVoiceId = 'slow_voice';
      } else {
        voiceId = null; // 기본 voice 사용
        speed = 0.9; // 90% 속도
        cachePrefix = '';
        cacheVoiceId = 'default';
      }
      
      // 음성 합성
      final audioData = await _apiService.synthesizeSpeech(
        text,
        voiceId: voiceId,
        speed: speed,
      );
      
      if (audioData != null && audioData.isNotEmpty) {
        final audioPath = await _cacheService.cacheTTSAudio(
          noteId: 'temp',
          pageId: 'temp',
          segmentId: '$cachePrefix$textHash',
          voiceId: cacheVoiceId,
          audioData: audioData,
        );
        
        if (audioPath != null) {
          await _playAudioFile(audioPath, mode);
          await _apiService.incrementTtsUsageAfterPlayback();
        } else {
          throw Exception('캐시 저장 실패');
        }
      } else {
        throw Exception('API 응답 없음');
      }
    } catch (e) {
      debugPrint('❌ TTS 처리 중 오류: $e');
      await _handleTtsError('TTS 처리 오류: $e');
    }
  }

  /// 오디오 파일 재생
  Future<void> _playAudioFile(String filePath, TtsMode mode) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('오디오 파일이 존재하지 않음: $filePath');
      }
      
      // 파일 크기 검사
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('오디오 파일이 비어있음: $filePath');
      }
      
      if (kDebugMode) {
        debugPrint('🎵 오디오 파일 검증 완료: ${(fileSize / 1024).toStringAsFixed(1)} KB');
      }

      await _prepareAudioPlayback(filePath, mode);
      
      _isSpeaking = true;
      _ttsState = TtsState.playing;
      
      await _audioPlayer.play();
      debugPrint('▶️ ${mode == TtsMode.slow ? '느린' : '일반'} TTS 재생 시작');
      
      _startTimeoutTimer();
      
    } catch (e) {
      debugPrint('❌ 오디오 파일 재생 중 오류: $e');
      await _handleTtsError('오디오 파일 재생 오류: $e');
    }
  }

  /// 오디오 재생 준비
  Future<void> _prepareAudioPlayback(String filePath, TtsMode mode) async {
    await _audioPlayer.stop();
    await _audioPlayer.setVolume(1.0);
    await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(filePath)));
    
    // 모드별 재생 속도 설정
    if (mode == TtsMode.slow) {
      // API 70% + 플레이어 95% = 전체 66.5% 속도
      await _audioPlayer.setSpeed(0.95);
    } else {
      // 일반 속도
      await _audioPlayer.setSpeed(1.0);
    }
  }

  /// 재생 중지
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _resetState();
      debugPrint('⏹️ TTS 재생 중지');
    } catch (e) {
      debugPrint('❌ TTS 중지 중 오류: $e');
      _resetState();
    }
  }

  /// 상태 초기화
  void _resetState({bool callCompletedCallback = true}) {
    _isSpeaking = false;
    _ttsState = TtsState.stopped;
    _cancelTimeoutTimer();
    
    _updateCurrentSegment(null, _currentMode);
    
    if (callCompletedCallback) {
      final callbacks = _onPlayingCompletedCallbacks[_currentMode] ?? [];
      for (final callback in callbacks) {
        callback();
      }
    }
    
    _currentSegmentIndex = null;
    _isPlayingAll = false;
  }

  /// 현재 재생 중인 세그먼트 업데이트
  void _updateCurrentSegment(int? segmentIndex, TtsMode mode) {
    _currentSegmentIndex = segmentIndex;
    final callbacks = _onPlayingStateChangedCallbacks[mode] ?? [];
    for (final callback in callbacks) {
      callback(_currentSegmentIndex);
    }
  }

  /// 타임아웃 타이머 관리
  void _startTimeoutTimer() {
    _cancelTimeoutTimer();
    _timeoutTimer = Timer(_playbackTimeout, () {
      if (_isSpeaking) {
        debugPrint('⚠️ TTS 재생 타임아웃');
        _handleTimeout();
      }
    });
  }

  void _cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  /// 타임아웃 발생 시 처리 (오디오 플레이어 재초기화)
  Future<void> _handleTimeout() async {
    debugPrint('🔄 TTS 타임아웃으로 인한 재초기화 시작');
    
    try {
      // 1. 현재 재생 중지
      await _audioPlayer.stop();
      
      // 2. 상태 초기화
      _resetState(callCompletedCallback: true);
      
      // 3. 오디오 플레이어 완전 재초기화
      await _reinitializeAudioPlayer();
      
      debugPrint('✅ TTS 타임아웃 재초기화 완료');
      
    } catch (e) {
      debugPrint('❌ TTS 타임아웃 재초기화 중 오류: $e');
      // 재초기화 실패 시 강제로 상태만 리셋
      _resetState(callCompletedCallback: true);
    }
  }

  /// 오디오 플레이어 재초기화
  Future<void> _reinitializeAudioPlayer() async {
    try {
      // 1. 기존 구독 해제
      await _playerStateSubscription?.cancel();
      await _playbackEventSubscription?.cancel();
      _playerStateSubscription = null;
      _playbackEventSubscription = null;
      
      // 2. 오디오 플레이어 완전 정리
      await _audioPlayer.stop();
      await _audioPlayer.seek(Duration.zero);
      
      // 3. 이벤트 핸들러 재설정
      await _setupEventHandlers();
      
      if (kDebugMode) {
        debugPrint('🔄 오디오 플레이어 재초기화 완료');
      }
      
    } catch (e) {
      debugPrint('❌ 오디오 플레이어 재초기화 실패: $e');
      rethrow;
    }
  }

  /// TTS 에러 처리
  Future<void> _handleTtsError(String errorMessage) async {
    debugPrint('🔄 TTS 에러 처리: $errorMessage');
    
    try {
      await _audioPlayer.stop();
      _resetState();
      await Future.delayed(const Duration(milliseconds: 50));
    } catch (e) {
      debugPrint('❌ TTS 에러 처리 중 추가 오류: $e');
      _resetState();
    }
  }

  /// 이벤트 핸들러 설정
  Future<void> _setupEventHandlers() async {
    await _playerStateSubscription?.cancel();
    await _playbackEventSubscription?.cancel();
    
    _playbackEventSubscription = _audioPlayer.playbackEventStream.listen((event) {
      if (kDebugMode) {
        debugPrint('🎵 TTS 재생 이벤트: ${event.processingState}');
      }
      
      if (event.processingState == ProcessingState.ready && _ttsState != TtsState.playing) {
        _ttsState = TtsState.playing;
      }
    }, onError: (error) {
      if (kDebugMode) {
        debugPrint('❌ TTS 재생 이벤트 오류: $error');
      }
      _handleTtsError('재생 이벤트 오류: $error');
    });

    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (kDebugMode) {
        debugPrint('🎵 TTS 플레이어 상태: ${state.processingState}, 재생중: ${state.playing}');
      }
      
      if (state.processingState == ProcessingState.completed) {
        debugPrint('🎵 TTS 재생 완료');
        _resetState();
      } else if (state.processingState == ProcessingState.idle && _isSpeaking) {
        // 예상치 못한 idle 상태로 전환된 경우
        debugPrint('⚠️ TTS 예상치 못한 idle 상태');
        _resetState();
      }
    }, onError: (error) {
      if (kDebugMode) {
        debugPrint('❌ TTS 플레이어 상태 오류: $error');
      }
      _handleTtsError('플레이어 상태 오류: $error');
    });
  }

  /// 콜백 설정 (모드별)
  void setOnPlayingStateChanged(Function(int?) callback, {TtsMode mode = TtsMode.normal}) {
    _onPlayingStateChangedCallbacks[mode]?.add(callback);
  }

  void setOnPlayingCompleted(Function() callback, {TtsMode mode = TtsMode.normal}) {
    _onPlayingCompletedCallbacks[mode]?.add(callback);
  }

  /// 콜백 제거 (모드별)
  void removeOnPlayingStateChanged(Function(int?) callback, {TtsMode mode = TtsMode.normal}) {
    _onPlayingStateChangedCallbacks[mode]?.remove(callback);
  }

  void removeOnPlayingCompleted(Function() callback, {TtsMode mode = TtsMode.normal}) {
    _onPlayingCompletedCallbacks[mode]?.remove(callback);
  }

  /// 리소스 해제
  Future<void> dispose() async {
    debugPrint('🧹 통합 TTS 서비스 리소스 해제 시작');
    
    _resetState(callCompletedCallback: false);
    
    try {
      await _audioPlayer.stop();
      await _audioPlayer.dispose();
    } catch (e) {
      debugPrint('⚠️ 오디오 플레이어 해제 중 오류: $e');
    }
    
    await _playerStateSubscription?.cancel();
    await _playbackEventSubscription?.cancel();
    _playerStateSubscription = null;
    _playbackEventSubscription = null;
    
    await _cacheService.dispose();
    
    _currentSegments.clear();
    _onPlayingStateChangedCallbacks.clear();
    _onPlayingCompletedCallbacks.clear();
    _isInitialized = false;
    
    debugPrint('✅ 통합 TTS 서비스 리소스 해제 완료');
  }
} 