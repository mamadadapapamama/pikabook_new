import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/models/processed_text.dart';
import '../../utils/language_constants.dart';
import '../../../core/services/common/usage_limit_service.dart';
import 'dart:async';
import '../../../core/models/text_unit.dart';
import 'tts_api_service.dart';
import 'tts_cache_service.dart';

/// 느린 TTS 상태
enum SlowTtsState { playing, stopped, paused }

/// 느린 텍스트 음성 변환 서비스
/// 새로운 voice 모델(hkfHEbBvdQFNX4uWHqRF)을 사용
/// API에서 70% 속도로 생성 + 플레이어에서 90% 속도 재생 = 전체 63% 속도
class SlowTtsService {
  static final SlowTtsService _instance = SlowTtsService._internal();
  factory SlowTtsService() => _instance;
  
  // 서비스 인스턴스
  final TtsApiService _apiService = TtsApiService();
  final TTSCacheService _cacheService = TTSCacheService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // 오디오 재생 관련
  final AudioPlayer _audioPlayer = AudioPlayer();
  SlowTtsState _ttsState = SlowTtsState.stopped;
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
  
  SlowTtsService._internal();

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
        debugPrint('🐢 느린 TTS 서비스 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 느린 TTS 서비스 초기화 실패: $e');
      }
      rethrow;
    }
  }

  /// 이벤트 핸들러 설정
  Future<void> _setupEventHandlers() async {
    // 재생 완료 이벤트 처리
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handlePlaybackCompleted();
      }
    });

    // 재생 이벤트 처리
    _playbackEventSubscription = _audioPlayer.playbackEventStream.listen((event) {
      // 재생 이벤트 로깅 (필요시)
    });
  }

  /// 재생 완료 처리
  void _handlePlaybackCompleted() {
    _isSpeaking = false;
    _ttsState = SlowTtsState.stopped;
    _currentSegmentIndex = null;
    
    if (kDebugMode) {
      debugPrint('🐢 느린 TTS 재생 완료');
    }
    
    // 콜백 호출
    _onPlayingCompleted?.call();
    _onPlayingStateChanged?.call(null);
  }

  /// 언어 설정
  Future<void> setLanguage(String language) async {
    await _apiService.setLanguage(language);
  }

  /// 현재 설정된 언어
  String get currentLanguage => _apiService.currentLanguage;

  /// 현재 상태 확인
  SlowTtsState get state => _ttsState;

  /// 현재 재생 중 여부
  bool get isSpeaking => _isSpeaking;

  /// 현재 재생 중인 세그먼트 인덱스
  int? get currentSegmentIndex => _currentSegmentIndex;

  /// 텍스트 읽기 (느린 속도)
  Future<void> speak(String text) async {
    if (!_isInitialized) await init();
    
    // 이미 재생 중이면 중지하고 상태 초기화
    if (_isSpeaking) {
      debugPrint('⏹️ 느린 TTS 이미 재생 중이므로 중지 후 새로 시작');
      await stop();
      await Future.delayed(Duration(milliseconds: 300));
    }

    if (text.isEmpty) return;

    // 느린 TTS용 캐시 확인 (slow_ 접두사 사용)
    final textHash = text.hashCode.toString();
    final cachedPath = await _cacheService.getTTSPath(
      noteId: 'temp',
      pageId: 'temp',
      segmentId: 'slow_$textHash',
      voiceId: 'slow_voice',
    );
    
    if (cachedPath != null) {
      // 캐시된 오디오 파일을 느린 속도로 재생
      await _playAudioFileSlowly(cachedPath);
      debugPrint('🐢 💾 캐시된 느린 TTS 재생: $text');
      return;
    }

    // 새로운 느린 TTS 요청 처리
    try {
      debugPrint('🐢 🔊 느린 TTS 새 요청');
      
      // 음성 합성 (새로운 voice 모델과 70% 속도 사용)
      final audioData = await _apiService.synthesizeSpeech(
        text,
        voiceId: 'hkfHEbBvdQFNX4uWHqRF', // 느린 TTS용 새로운 voice 모델
        speed: 0.7, // 70% 속도
      );
      
      if (audioData != null) {
        // 오디오 데이터를 캐시에 저장
        final audioPath = await _cacheService.cacheTTSAudio(
          noteId: 'temp',
          pageId: 'temp',
          segmentId: 'slow_$textHash',
          voiceId: 'slow_voice',
          audioData: audioData,
        );
        
        if (audioPath != null) {
          // 오디오 파일을 느린 속도로 재생
          await _playAudioFileSlowly(audioPath);
          debugPrint('🐢 🔊 느린 TTS 재생 중: $text');
          
          // 재생 완료 후 사용량 증가
          await _apiService.incrementTtsUsageAfterPlayback();
        } else {
          debugPrint('❌ 느린 TTS 캐시 저장 실패: $text');
        }
      } else {
        debugPrint('❌ 느린 TTS API 응답 없음: $text');
      }
    } catch (e) {
      debugPrint('❌ 느린 TTS 처리 중 오류: $e');
    }
  }

  /// 세그먼트 읽기 (느린 속도)
  Future<void> speakSegment(String text, int segmentIndex) async {
    if (!_isInitialized) await init();
    
    // 이미 같은 세그먼트가 재생 중이면 중지
    if (_isSpeaking && _currentSegmentIndex == segmentIndex) {
      await stop();
      return;
    }
    
    // 다른 세그먼트가 재생 중이면 중지하고 새로 시작
    if (_isSpeaking) {
      await stop();
      await Future.delayed(Duration(milliseconds: 300));
    }

    _currentSegmentIndex = segmentIndex;
    
    // 콜백 호출
    _onPlayingStateChanged?.call(segmentIndex);
    
    await speak(text);
  }

  /// 오디오 파일을 느린 속도로 재생
  Future<void> _playAudioFileSlowly(String filePath) async {
    try {
      // 파일이 존재하는지 확인
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ 느린 TTS 오디오 파일이 존재하지 않음: $filePath');
        _isSpeaking = false;
        return;
      }

      // 파일 크기 확인
      final fileSize = await file.length();
      debugPrint('🐢 🎵 느린 TTS 오디오 파일 정보: ${filePath.split('/').last} (${fileSize} bytes)');

      // 먼저 이전 재생 중지 및 리소스 해제
      await _audioPlayer.stop();
      
      // 볼륨 설정 (최대 볼륨)
      await _audioPlayer.setVolume(1.0);
      
      // 파일 경로 설정
      await _audioPlayer.setFilePath(filePath);
      
      // API에서 70% 속도로 생성된 오디오를 플레이어에서 90% 속도로 재생
      // 전체 속도: 0.7 * 0.9 = 0.63 (약 63% 속도)
      await _audioPlayer.setSpeed(0.95);
      debugPrint('🐢 API 70% + 플레이어 90% = 전체 63% 속도로 재생');
      
      // 실제 재생 시작
      await _audioPlayer.play();
      _isSpeaking = true;
      _ttsState = SlowTtsState.playing;
      debugPrint('🐢 ▶️ 느린 TTS 재생 시작: ${filePath.split('/').last}');
      
      // 안전장치: 20초 후 강제 종료 (느린 재생이므로 시간 연장)
      Future.delayed(const Duration(seconds: 20), () {
        if (_isSpeaking) {
          debugPrint('⚠️ 느린 TTS 재생 타임아웃으로 강제 종료');
          _isSpeaking = false;
          _ttsState = SlowTtsState.stopped;
          _currentSegmentIndex = null;
        }
      });
      
    } catch (e) {
      debugPrint('❌ 느린 TTS 오디오 재생 실패: $e');
      _isSpeaking = false;
      _ttsState = SlowTtsState.stopped;
      _currentSegmentIndex = null;
    }
  }

  /// 재생 중지
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _isSpeaking = false;
      _ttsState = SlowTtsState.stopped;
      _currentSegmentIndex = null;
      
      if (kDebugMode) {
        debugPrint('🐢 ⏹️ 느린 TTS 재생 중지');
      }
      
      // 콜백 호출
      _onPlayingCompleted?.call();
      _onPlayingStateChanged?.call(null);
    } catch (e) {
      debugPrint('❌ 느린 TTS 중지 실패: $e');
    }
  }

  /// 일시정지
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      _ttsState = SlowTtsState.paused;
      
      if (kDebugMode) {
        debugPrint('🐢 ⏸️ 느린 TTS 일시정지');
      }
    } catch (e) {
      debugPrint('❌ 느린 TTS 일시정지 실패: $e');
    }
  }

  /// 재개
  Future<void> resume() async {
    try {
      await _audioPlayer.play();
      _ttsState = SlowTtsState.playing;
      
      if (kDebugMode) {
        debugPrint('🐢 ▶️ 느린 TTS 재개');
      }
    } catch (e) {
      debugPrint('❌ 느린 TTS 재개 실패: $e');
    }
  }

  /// 재생 상태 변경 콜백 설정
  void setOnPlayingStateChanged(Function(int?) callback) {
    _onPlayingStateChanged = callback;
  }

  /// 재생 완료 콜백 설정
  void setOnPlayingCompleted(Function callback) {
    _onPlayingCompleted = callback;
  }

  /// 리소스 정리
  void dispose() {
    _playerStateSubscription?.cancel();
    _playbackEventSubscription?.cancel();
    _audioPlayer.dispose();
    
    if (kDebugMode) {
      debugPrint('🐢 느린 TTS 서비스 리소스 정리');
    }
  }
} 