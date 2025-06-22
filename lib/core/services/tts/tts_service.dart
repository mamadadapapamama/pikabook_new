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
  
  // 오디오 재생 관련 (TtsPlaybackService에서 이동)
  final AudioPlayer _audioPlayer = AudioPlayer();
  TtsState _ttsState = TtsState.stopped;
  bool _isSpeaking = false;
  
  // 스트림 구독 관리
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playbackEventSubscription;
  
  // 세그먼트 관리
  int? _currentSegmentIndex;
  List<TextUnit> _currentSegments = [];

  // 콜백
  Function(int?)? _onPlayingStateChanged;
  Function? _onPlayingCompleted;
  
  // 초기화 여부
  bool _isInitialized = false;
  
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
        debugPrint('TTS 서비스 초기화 완료 (재생 기능 통합)');
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
        // 상태 초기화가 확실히 반영되도록 잠시 대기
        await Future.delayed(Duration(milliseconds: 150));
      }

      if (text.isEmpty) return;

      // 캐시된 TTS 확인 (TTSCacheService 사용)
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
        debugPrint('💾 캐시된 TTS 재생: $text');
        return;
      }

      // 새로운 TTS 요청 처리
      try {
        debugPrint('🔊 TTS 새 요청');
        
        // 음성 합성
        final audioData = await _apiService.synthesizeSpeech(text);
        if (audioData != null) {
          // 오디오 데이터를 캐시에 저장 (TTSCacheService 사용)
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
            debugPrint('🔊 TTS 재생 중: $text');
            
            // 새로운 TTS 요청 시에만 사용량 증가
            await _apiService.incrementTtsUsageAfterPlayback();
          } else {
            debugPrint('❌ TTS 캐시 저장 실패: $text');
            await _handleTtsError('캐시 저장 실패');
          }
        } else {
          debugPrint('❌ TTS API 응답 없음: $text');
          await _handleTtsError('API 응답 없음');
        }
      } catch (e) {
        debugPrint('❌ TTS 처리 중 오류: $e');
        await _handleTtsError('TTS 처리 오류: $e');
      }
    } catch (e) {
      debugPrint('❌ TTS speak() 전체 오류: $e');
      await _handleTtsError('전체 TTS 오류: $e');
    }
  }

  /// 오디오 파일 재생 (TtsPlaybackService에서 이동)
  Future<void> _playAudioFile(String filePath) async {
    try {
      // 파일이 존재하는지 확인
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ 오디오 파일이 존재하지 않음: $filePath');
        _resetState();
        return;
      }

      // 파일 크기 확인
      final fileSize = await file.length();
      debugPrint('🎵 오디오 파일 정보: ${filePath.split('/').last} (${fileSize} bytes)');

      // 재생 중지 및 상태 초기화
      await _audioPlayer.stop();
      
      // 볼륨 설정 (최대 볼륨)
      await _audioPlayer.setVolume(1.0);
      debugPrint('🔊 볼륨 설정: 1.0 (최대)');
      
      // 오디오 소스 설정
      await _audioPlayer.setAudioSource(
        AudioSource.uri(Uri.file(filePath)),
      );
      debugPrint('🎧 오디오 소스 설정 완료');
      
      // 상태 업데이트
      _isSpeaking = true;
      _ttsState = TtsState.playing;
      
      // 실제 재생 시작
      await _audioPlayer.play();
      debugPrint('▶️ 오디오 재생 시작: ${filePath.split('/').last}');
      
      // 안전장치: 10초 후 강제 종료 (무한 재생 방지)
      Future.delayed(const Duration(seconds: 10), () {
        if (_isSpeaking) {
          debugPrint('⚠️ 오디오 재생 타임아웃으로 강제 종료');
          _resetState();
        }
      });
    } catch (e) {
      debugPrint('❌ 오디오 파일 재생 중 오류: $e');
      await _handleTtsError('오디오 파일 재생 오류: $e');
    }
  }

  /// 상태 초기화
  void _resetState() {
    _isSpeaking = false;
    _ttsState = TtsState.stopped;
    _updateCurrentSegment(null);
  }

  /// TTS 에러 처리 및 완전 초기화
  Future<void> _handleTtsError(String errorMessage) async {
    debugPrint('🔄 TTS 에러 처리: $errorMessage');
    
    try {
      // 1. 재생 중지
      await _audioPlayer.stop();
      
      // 2. 상태 초기화
      _resetState();
      
      // 3. 잠시 대기하여 상태 안정화
      await Future.delayed(Duration(milliseconds: 100));
      
      debugPrint('✅ TTS 에러 처리 완료');
    } catch (e) {
      debugPrint('❌ TTS 에러 처리 중 추가 오류: $e');
      // 최후의 수단: 상태만 초기화
      _resetState();
    }
  }

  /// 재생 중지
  Future<void> stop() async {
    try {
      debugPrint('⏹️ TTS 재생 중지 요청');
      await _audioPlayer.stop();
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
    await _audioPlayer.pause();
    _ttsState = TtsState.paused;
  }

  /// **단일 세그먼트 읽기**
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

  /// **ProcessedText의 모든 세그먼트 순차적으로 읽기**
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
      debugPrint('읽을 내용이 없습니다');
      return;
    }

    // 세그먼트 설정
    _currentSegments = units;
    
    // 모든 내용 순차 재생
    debugPrint("${units.length}개 항목 순차 재생 시작");
    
    for (var i = 0; i < units.length; i++) {
      if (_ttsState != TtsState.playing) break;
      
      _currentSegmentIndex = i;
      _updateCurrentSegment(i);
      
      try {
        await speak(units[i].originalText);
      } catch (e) {
        debugPrint('세그먼트 재생 중 오류: $e');
        continue;
      }
    }
  }

  /// 현재 재생 중인 세그먼트 업데이트
  void _updateCurrentSegment(int? segmentIndex) {
    _currentSegmentIndex = segmentIndex;
    if (_onPlayingStateChanged != null) {
      _onPlayingStateChanged!(_currentSegmentIndex);
    }
  }

  /// 이벤트 핸들러 초기화 (TtsPlaybackService에서 이동)
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
        _ttsState = TtsState.stopped;
        _isSpeaking = false;
        
        // 재생 완료 콜백 호출
        if (_onPlayingCompleted != null) {
          _onPlayingCompleted!();
        }
        
        // 현재 세그먼트 초기화
        _updateCurrentSegment(null);
      }
    });
  }

  /// 캐시 비우기
  void clearCache() {
    _cacheService.clearAllTTSCache();
  }

  /// 재생 상태 변경 콜백 설정
  void setOnPlayingStateChanged(Function(int?) callback) {
    _onPlayingStateChanged = callback;
  }

  /// 재생 완료 콜백 설정
  void setOnPlayingCompleted(Function callback) {
    _onPlayingCompleted = callback;
  }

  /// 리소스 해제
  Future<void> dispose() async {
    _isSpeaking = false;
    _currentSegmentIndex = null;
    _currentSegments = [];
    
    // 스트림 구독 취소
    await _playerStateSubscription?.cancel();
    await _playbackEventSubscription?.cancel();
    _playerStateSubscription = null;
    _playbackEventSubscription = null;
    
    await _audioPlayer.dispose();
    await _cacheService.dispose();
    _isInitialized = false;
    
    if (kDebugMode) {
      debugPrint('TTS 서비스 리소스 해제 완료');
    }
  }
}
