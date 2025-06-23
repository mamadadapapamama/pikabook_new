import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/models/processed_text.dart';
import '../../utils/language_constants.dart';
import 'dart:async';
import '../../../core/models/text_unit.dart';
import 'tts_api_service.dart';
import 'tts_cache_service.dart';

/// TTS 상태
enum TtsState { playing, stopped, paused }

/// 텍스트 음성 변환 서비스 (통합)
/// TTS API 호출, 오디오 재생, 세그먼트 관리를 통합 관리
class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  
  // 서비스 인스턴스
  final TtsApiService _apiService = TtsApiService();
  final TTSCacheService _cacheService = TTSCacheService();
  
  // 오디오 재생 관련
  final AudioPlayer _audioPlayer = AudioPlayer();
  TtsState _ttsState = TtsState.stopped;
  bool _isSpeaking = false;
  
  // 스트림 구독 관리
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playbackEventSubscription;
  
  // 세그먼트 관리
  int? _currentSegmentIndex;
  List<TextUnit> _currentSegments = [];
  bool _isPlayingAll = false; // 전체 재생 모드 플래그

  // 콜백 (여러 리스너 지원)
  final List<Function(int?)> _onPlayingStateChangedCallbacks = [];
  final List<Function()> _onPlayingCompletedCallbacks = [];
  
  // 초기화 여부
  bool _isInitialized = false;
  
  // 타임아웃 관리
  Timer? _timeoutTimer;
  static const Duration _playbackTimeout = Duration(seconds: 15); // 설정 가능한 타임아웃
  
  TTSService._internal();

  /// 초기화
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 하위 서비스 초기화
      await _apiService.initialize();
      await _cacheService.initialize();
      await _setupEventHandlers();
      
      // 언어 설정
      await setLanguage(SourceLanguage.DEFAULT);
      
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('✅ TTS 서비스 초기화 완료 (재생 기능 통합)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TTS 서비스 초기화 실패: $e');
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

  /// 텍스트 읽기
  Future<void> speak(String text) async {
    try {
      if (!_isInitialized) await init();
      
      // 이미 재생 중이면 중지하고 상태 초기화
      if (_isSpeaking) {
        debugPrint('⏹️ 이미 재생 중이므로 중지 후 새로 시작');
        await stop();
        // 🚀 최적화: 지연 시간 단축 (150ms → 50ms)
        await Future.delayed(const Duration(milliseconds: 50));
      }

      if (text.isEmpty) {
        debugPrint('⚠️ 빈 텍스트 - 재생 중지');
        return;
      }

      // 캐시된 TTS 확인
      final textHash = text.hashCode.toString();
      final cachedPath = await _cacheService.getTTSPath(
        noteId: 'temp',
        pageId: 'temp',
        segmentId: textHash,
        voiceId: 'default',
      );
      
      if (cachedPath != null) {
        // 캐시된 오디오 파일 재생
        await _playAudioFile(cachedPath);
        debugPrint('💾 캐시된 TTS 재생: ${text.length > 20 ? text.substring(0, 20) + '...' : text}');
        return;
      }

      // 새로운 TTS 요청 처리
      await _processNewTtsRequest(text, textHash);
      
    } catch (e) {
      debugPrint('❌ TTS speak() 전체 오류: $e');
      await _handleTtsError('전체 TTS 오류: $e');
    }
  }

  /// 🚀 최적화: 새로운 TTS 요청 처리 로직 분리
  Future<void> _processNewTtsRequest(String text, String textHash) async {
    try {
      debugPrint('🔊 TTS 새 요청: ${text.length > 20 ? text.substring(0, 20) + '...' : text}');
      
      // 음성 합성
      final audioData = await _apiService.synthesizeSpeech(text);
      if (audioData != null && audioData.isNotEmpty) {
        // 오디오 데이터를 캐시에 저장
        final audioPath = await _cacheService.cacheTTSAudio(
          noteId: 'temp',
          pageId: 'temp',
          segmentId: textHash,
          voiceId: 'default',
          audioData: audioData,
        );
        
        if (audioPath != null) {
          // 오디오 파일 재생
          await _playAudioFile(audioPath);
          debugPrint('🔊 TTS 재생 중: ${text.length > 20 ? text.substring(0, 20) + '...' : text}');
          
          // 새로운 TTS 요청 시에만 사용량 증가
          await _apiService.incrementTtsUsageAfterPlayback();
        } else {
          throw Exception('캐시 저장 실패');
        }
      } else {
        throw Exception('API 응답 없음 또는 빈 데이터');
      }
    } catch (e) {
      debugPrint('❌ TTS 처리 중 오류: $e');
      await _handleTtsError('TTS 처리 오류: $e');
    }
  }

  /// 오디오 파일 재생
  Future<void> _playAudioFile(String filePath) async {
    try {
      // 파일 존재 및 크기 확인
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('오디오 파일이 존재하지 않음: $filePath');
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('오디오 파일이 비어있음: $filePath');
      }

      debugPrint('🎵 오디오 파일 정보: ${filePath.split('/').last} (${fileSize} bytes)');

      // 🚀 최적화: 재생 준비 최적화
      await _prepareAudioPlayback(filePath);
      
      // 상태 업데이트
      _isSpeaking = true;
      _ttsState = TtsState.playing;
      
      // 실제 재생 시작
      await _audioPlayer.play();
      debugPrint('▶️ 오디오 재생 시작: ${filePath.split('/').last}');
      
      // 🚀 최적화: 타임아웃 관리 개선
      _startTimeoutTimer();
      
    } catch (e) {
      debugPrint('❌ 오디오 파일 재생 중 오류: $e');
      await _handleTtsError('오디오 파일 재생 오류: $e');
    }
  }

  /// 🚀 최적화: 오디오 재생 준비 로직 분리
  Future<void> _prepareAudioPlayback(String filePath) async {
    // 재생 중지 및 상태 초기화
    await _audioPlayer.stop();
    
    // 볼륨 설정 (최대 볼륨)
    await _audioPlayer.setVolume(1.0);
    
    // 오디오 소스 설정
    await _audioPlayer.setAudioSource(AudioSource.uri(Uri.file(filePath)));
    
    debugPrint('🎧 오디오 재생 준비 완료');
  }

  /// 🚀 최적화: 타임아웃 타이머 관리
  void _startTimeoutTimer() {
    _cancelTimeoutTimer();
    _timeoutTimer = Timer(_playbackTimeout, () {
      if (_isSpeaking) {
        debugPrint('⚠️ 오디오 재생 타임아웃으로 강제 종료 (${_playbackTimeout.inSeconds}초)');
        _resetState();
      }
    });
  }

  void _cancelTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  /// 🚀 최적화: 상태 초기화 로직 통합 및 개선
  void _resetState({bool callCompletedCallback = true}) {
    _isSpeaking = false;
    _ttsState = TtsState.stopped;
    
    // 타임아웃 타이머 정리
    _cancelTimeoutTimer();
    
    // 현재 세그먼트 업데이트 (상태 변경 콜백 호출)
    _updateCurrentSegment(null);
    
    // 재생 완료 콜백 호출 (옵션)
    if (callCompletedCallback) {
      // 전체 재생 모드일 때만 전체 재생 완료 콜백 호출
      if (_isPlayingAll) {
        debugPrint('🎵 전체 재생 완료 콜백 호출');
      }
      
      for (final callback in _onPlayingCompletedCallbacks) {
        callback();
      }
    }
    
    _currentSegmentIndex = null;
    _isPlayingAll = false; // 전체 재생 모드 해제
  }

  /// TTS 에러 처리 및 완전 초기화
  Future<void> _handleTtsError(String errorMessage) async {
    debugPrint('🔄 TTS 에러 처리: $errorMessage');
    
    try {
      // 1. 재생 중지
      await _audioPlayer.stop();
      
      // 2. 상태 초기화
      _resetState();
      
      // 🚀 최적화: 에러 복구 시간 단축
      await Future.delayed(const Duration(milliseconds: 50));
      
      debugPrint('✅ TTS 에러 처리 완료');
    } catch (e) {
      debugPrint('❌ TTS 에러 처리 중 추가 오류: $e');
      // 최후의 수단: 상태만 초기화
      _resetState();
    }
  }

  /// 🚀 최적화: 재생 중지 로직 간소화
  Future<void> stop() async {
    try {
      debugPrint('⏹️ TTS 재생 중지 요청');
      
      // 오디오 플레이어 중지
      await _audioPlayer.stop();
      
      // 상태 초기화 (통합된 메서드 사용)
      _resetState();
      
      debugPrint('✅ TTS 재생 중지 완료');
    } catch (e) {
      debugPrint('❌ TTS 중지 중 오류: $e');
      // 오류가 발생해도 상태는 초기화
      _resetState();
    }
  }

  /// 재생 일시정지
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      _ttsState = TtsState.paused;
      _cancelTimeoutTimer(); // 일시정지 시 타임아웃 해제
      debugPrint('⏸️ TTS 일시정지');
    } catch (e) {
      debugPrint('❌ TTS 일시정지 실패: $e');
    }
  }

  /// 재생 재개
  Future<void> resume() async {
    try {
      await _audioPlayer.play();
      _ttsState = TtsState.playing;
      _startTimeoutTimer(); // 재개 시 타임아웃 재시작
      debugPrint('▶️ TTS 재개');
    } catch (e) {
      debugPrint('❌ TTS 재개 실패: $e');
    }
  }

  /// 단일 세그먼트 읽기
  Future<void> speakSegment(String text, int segmentIndex) async {
    if (!_isInitialized) await init();
    if (text.isEmpty) return;
    
    // 현재 재생 중인 세그먼트 설정
    _currentSegmentIndex = segmentIndex;
    _updateCurrentSegment(segmentIndex);
    
    // 텍스트 읽기
    await speak(text);
  }

  /// 현재 재생 중인 세그먼트 인덱스
  int? get currentSegmentIndex => _currentSegmentIndex;

  /// ProcessedText의 모든 세그먼트 순차적으로 읽기
  Future<void> speakAllSegments(ProcessedText processedText) async {
    if (!_isInitialized) await init();
    
    // 이미 재생 중이면 중지
    if (_ttsState == TtsState.playing) {
      await stop();
      return;
    }

    // 사용 가능 여부 확인
    final units = processedText.units;
    if (units.isEmpty) {
      debugPrint('⚠️ 읽을 내용이 없습니다');
      return;
    }

    // 전체 재생 모드 설정
    _isPlayingAll = true;
    _currentSegments = units;
    
    // 모든 내용 순차 재생
    debugPrint("🎵 ${units.length}개 항목 순차 재생 시작 (전체 재생 모드)");
    
    for (var i = 0; i < units.length; i++) {
      if (_ttsState != TtsState.playing && !_isPlayingAll) break;
      
      _currentSegmentIndex = i;
      _updateCurrentSegment(i);
      
      try {
        await speak(units[i].originalText);
      } catch (e) {
        debugPrint('❌ 세그먼트 재생 중 오류: $e');
        continue;
      }
    }
    
    // 전체 재생 완료
    _isPlayingAll = false;
    debugPrint("🎵 전체 재생 완료");
  }

  /// 현재 재생 중인 세그먼트 업데이트
  void _updateCurrentSegment(int? segmentIndex) {
    _currentSegmentIndex = segmentIndex;
    for (final callback in _onPlayingStateChangedCallbacks) {
      callback(_currentSegmentIndex);
    }
  }

  /// 이벤트 핸들러 초기화
  Future<void> _setupEventHandlers() async {
    // 기존 구독이 있으면 취소
    await _playerStateSubscription?.cancel();
    await _playbackEventSubscription?.cancel();
    
    // 재생 상태 변경 이벤트
    _playbackEventSubscription = _audioPlayer.playbackEventStream.listen((event) {
      if (event.processingState == ProcessingState.ready && _ttsState != TtsState.playing) {
        debugPrint("🎵 TTSService: 오디오 준비 완료");
        _ttsState = TtsState.playing;
      }
    });

    // 재생 완료 이벤트
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        debugPrint("🎵 TTSService: 재생 완료");
        _resetState(); // 통합된 상태 초기화 사용
      }
    });
  }

  /// 캐시 비우기
  void clearCache() {
    _cacheService.clearAllTTSCache();
    debugPrint('🗑️ TTS 캐시 정리 완료');
  }

  /// 재생 상태 변경 콜백 설정 (여러 리스너 지원)
  void setOnPlayingStateChanged(Function(int?) callback) {
    _onPlayingStateChangedCallbacks.add(callback);
  }

  /// 재생 완료 콜백 설정 (여러 리스너 지원)
  void setOnPlayingCompleted(Function() callback) {
    _onPlayingCompletedCallbacks.add(callback);
  }

  /// 콜백 제거
  void removeOnPlayingStateChanged(Function(int?) callback) {
    _onPlayingStateChangedCallbacks.remove(callback);
  }

  void removeOnPlayingCompleted(Function() callback) {
    _onPlayingCompletedCallbacks.remove(callback);
  }

  /// 🚀 최적화: 리소스 해제 강화
  Future<void> dispose() async {
    debugPrint('🧹 TTS 서비스 리소스 해제 시작');
    
    // 재생 중지
    _resetState(callCompletedCallback: false);
    
    // 오디오 플레이어 정리
    try {
      await _audioPlayer.stop();
      await _audioPlayer.dispose();
    } catch (e) {
      debugPrint('⚠️ 오디오 플레이어 해제 중 오류: $e');
    }
    
    // 스트림 구독 취소
    await _playerStateSubscription?.cancel();
    await _playbackEventSubscription?.cancel();
    _playerStateSubscription = null;
    _playbackEventSubscription = null;
    
    // 캐시 서비스 정리
    await _cacheService.dispose();
    
    // 상태 초기화
    _currentSegments.clear();
    _onPlayingStateChangedCallbacks.clear();
    _onPlayingCompletedCallbacks.clear();
    _isInitialized = false;
    
    debugPrint('✅ TTS 서비스 리소스 해제 완료');
  }
}
