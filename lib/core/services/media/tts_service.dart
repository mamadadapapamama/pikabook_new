import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import '../../models/processed_text.dart';
import '../../utils/language_constants.dart';
import '../common/usage_limit_service.dart';
import '../common/plan_service.dart';
import 'dart:async';
import 'package:path/path.dart' as path;
import '../cache/unified_cache_service.dart';
import '../../models/text_segment.dart';

// 텍스트 음성 변환 서비스를 제공합니다

enum TtsState { playing, stopped, paused, continued }

class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  final UnifiedCacheService _cacheService = UnifiedCacheService();
  late AudioPlayer _audioPlayer = AudioPlayer();
  TtsState _ttsState = TtsState.stopped;
  String _currentLanguage = SourceLanguage.DEFAULT; // 기본 언어: 중국어
  String? _apiKey;

  // 현재 재생 중인 세그먼트 인덱스
  int? _currentSegmentIndex;

  // 재생 상태 변경 콜백
  Function(int?)? _onPlayingStateChanged;

  // 재생 완료 콜백
  Function? _onPlayingCompleted;

  // 사용량 제한 서비스
  final UsageLimitService _usageLimitService = UsageLimitService();

  bool _isSpeaking = false;
  bool _isInitialized = false;
  List<TextSegment> _currentSegments = [];
  StreamController<int>? _segmentStreamController;
  Stream<int>? _segmentStream;

  // 초기화
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await _cacheService.initialize();
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

    // 이벤트 리스너 설정
    await _setupEventHandlers();

    // 언어 설정
    await setLanguage(_currentLanguage);
  }

  // API 키 로드
  Future<void> _loadApiKey() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/credentials/api_keys.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      _apiKey = jsonData['elevenlabs_key'] as String?;
      debugPrint('ElevenLabs API 키 로드 성공');
    } catch (e) {
      debugPrint('API 키 로드 중 오류: $e');
      rethrow;
    }
  }

  // 언어 설정
  Future<void> setLanguage(String language) async {
    _currentLanguage = language;
    debugPrint('TTS 언어 설정: $_currentLanguage');
  }

  /// 텍스트 읽기
  Future<void> speak(String text) async {
    // 이미 재생 중이면 중지하고 상태 초기화
    if (_isSpeaking) {
      debugPrint('⏹️ 이미 재생 중이므로 중지 후 새로 시작');
      await stop();
      // 상태 초기화가 확실히 반영되도록 잠시 대기
      await Future.delayed(Duration(milliseconds: 300));
    }
    
    _isSpeaking = true;
    if (text.isEmpty) {
      _isSpeaking = false;
      return;
    }

    // 캐시된 TTS 확인
    final cachedPath = await _cacheService.getTtsPath(text);
    if (cachedPath != null) {
      // 캐시된 오디오 파일 재생
      await _playAudioFile(cachedPath);
      debugPrint('💾 캐시된 TTS 재생: $text');
      return;
    }

    // 사용량 제한 확인
    try {
      debugPrint('🔊 TTS 새 요청');
      final canUseTts = await _usageLimitService.incrementTtsCharCount(1); // API 호출 1회로 카운트
      if (!canUseTts) {
        _isSpeaking = false;
        debugPrint('⚠️ TTS 사용량 제한 초과로 재생 불가');
        return;
      }
      
      // ElevenLabs API 호출
      final audioData = await _synthesizeSpeech(text);
      if (audioData != null) {
        // 오디오 데이터를 캐시에 저장
        final audioPath = await _cacheService.cacheTts(text, audioData);
        if (audioPath != null) {
          // 오디오 파일 재생
          await _playAudioFile(audioPath);
          debugPrint('🔊 TTS 재생 중: $text');
        } else {
          _isSpeaking = false;
          debugPrint('❌ TTS 캐시 저장 실패: $text');
        }
      } else {
        _isSpeaking = false;
        debugPrint('❌ TTS API 응답 없음: $text');
      }
    } catch (e) {
      _isSpeaking = false;
      debugPrint('❌ TTS 처리 중 오류: $e');
    }
  }

  // 재생 중지
  Future<void> stop() async {
    try {
      debugPrint('⏹️ TTS 재생 중지 요청');
      if (_audioPlayer != null) {
        await _audioPlayer.stop();
        _ttsState = TtsState.stopped;
        _updateCurrentSegment(null);
      }
      _isSpeaking = false;
      debugPrint('✅ TTS 재생 중지 완료');
    } catch (e) {
      debugPrint('❌ TTS 중지 중 오류: $e');
      // 오류가 발생해도 상태는 초기화
      _ttsState = TtsState.stopped;
      _updateCurrentSegment(null);
      _isSpeaking = false;
    }
  }

  // 재생 일시정지
  Future<void> pause() async {
    await _audioPlayer.pause();
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
    _isSpeaking = false;
    _currentSegmentIndex = null;
    _currentSegments = [];
    await _segmentStreamController?.close();
    _segmentStreamController = null;
    _segmentStream = null;
    await _audioPlayer.dispose();
    await _cacheService.clear();
    _isInitialized = false;
    if (kDebugMode) {
      debugPrint('TTS 서비스 리소스 해제 완료');
    }
  }

  // 현재 재생 중인 세그먼트 업데이트
  void _updateCurrentSegment(int? segmentIndex) {
    _currentSegmentIndex = segmentIndex;
    if (_onPlayingStateChanged != null) {
      _onPlayingStateChanged!(_currentSegmentIndex);
    }
  }

  /// **ProcessedText의 모든 세그먼트/문단 순차적으로 읽기**
  Future<void> speakAllSegments(ProcessedText processedText) async {
    // 이미 재생 중이면 중지
    if (_ttsState == TtsState.playing) {
      await stop();
      return;
    }

    // 사용 가능 여부 확인
    final contentList = processedText.contentList ?? [];
    if (contentList.isEmpty) {
      debugPrint('읽을 내용이 없습니다');
      return;
    }
    
    try {
      // 남은 사용량 확인
      final remainingCount = await getRemainingTtsCount();
      
      // 남은 사용량이 부족한 경우
      if (remainingCount < contentList.length) {
        debugPrint('TTS 사용량 부족: 필요=${contentList.length}, 남음=$remainingCount');
        return;
      }
    } catch (e) {
      debugPrint('TTS 사용량 확인 중 오류: $e');
    }

    // 모든 내용 순차 재생
    debugPrint("${contentList.length}개 항목 순차 재생 시작");
    _ttsState = TtsState.playing;
    
    for (var i = 0; i < contentList.length; i++) {
      if (_ttsState != TtsState.playing) break;
      
      final segment = contentList[i];
      _updateCurrentSegment(i);
      
      try {
        await speak(segment.originalText);
      } catch (e) {
        debugPrint('세그먼트 재생 중 오류: $e');
        continue;
      }
    }
    
    _ttsState = TtsState.stopped;
    _updateCurrentSegment(null);
    if (_onPlayingCompleted != null) {
      _onPlayingCompleted!();
    }
  }

  /// **단일 세그먼트/문단 읽기**
  Future<void> speakSegment(String text, int segmentIndex) async {
    if (text.isEmpty) return;
    
    // 현재 재생 중인 세그먼트 설정
    _updateCurrentSegment(segmentIndex);
    
    // 캐시된 TTS 확인
    final cachedPath = await _cacheService.getTtsPath(text);
    if (cachedPath != null) {
      await _playAudioFile(cachedPath);
      debugPrint('캐시된 TTS 재생 (사용량 변화 없음): $text (index: $segmentIndex)');
      return;
    }
    
    // 사용량 제한 확인
    try {
      debugPrint('TTS 요청: $text (index: $segmentIndex)');
      final canUseTts = await _usageLimitService.incrementTtsCharCount(1);
      if (!canUseTts) {
        debugPrint('TTS 사용량 제한 초과로 재생 불가: $text');
        _updateCurrentSegment(null);
        return;
      }
      
      // ElevenLabs TTS API 호출
      final audioData = await _synthesizeSpeech(text);
      if (audioData != null) {
        // 오디오 데이터를 캐시에 저장
        final audioPath = await _cacheService.cacheTts(text, audioData);
        if (audioPath != null) {
          // 오디오 파일 재생
          await _playAudioFile(audioPath);
          debugPrint('TTS 재생 시작 (사용량 증가): $text (index: $segmentIndex)');
        } else {
          debugPrint('TTS 캐시 저장 실패: $text');
          _updateCurrentSegment(null);
        }
      }
    } catch (e) {
      debugPrint('TTS 처리 중 오류: $e');
      _updateCurrentSegment(null);
    }
  }

  // TTS 사용 가능 여부 확인
  Future<bool> isTtsAvailable() async {
    try {
      final remainingCount = await getRemainingTtsCount();
      return remainingCount > 0;
    } catch (e) {
      debugPrint('TTS 사용 가능 여부 확인 중 오류: $e');
      return false;
    }
  }

  /// TTS 제한 안내 메시지 가져오기
  String getTtsLimitMessage() {
    return '무료 사용량을 모두 사용했습니다. 추가 사용을 원하시면 관리자에게 문의주세요.';
  }
  
  /// 세그먼트 기반 읽기
  Future<void> speakSegments(ProcessedText text) async {
    if (!_isSpeaking) await speakAllSegments(text);
  }

  /// 다음 세그먼트 읽기
  Future<void> _speakNextSegment() async {
    if (!_isSpeaking || _currentSegmentIndex! >= _currentSegments.length - 1) {
      _isSpeaking = false;
      _currentSegmentIndex = -1;
      _currentSegments = [];
      _segmentStreamController?.close();
      _segmentStreamController = null;
      _segmentStream = null;
      return;
    }

    _currentSegmentIndex = _currentSegmentIndex! + 1;
    final segment = _currentSegments[_currentSegmentIndex!];
    final textToSpeak = segment.originalText;

    await speak(textToSpeak);
    _segmentStreamController?.add(_currentSegmentIndex!);

    if (kDebugMode) {
      debugPrint('세그먼트 읽기: ${_currentSegmentIndex! + 1}/${_currentSegments.length}');
    }
  }

  /// 현재 세그먼트 다시 읽기
  Future<void> repeatCurrentSegment() async {
    if (!_isSpeaking || _currentSegmentIndex! < 0 || _currentSegmentIndex! >= _currentSegments.length) {
      return;
    }

    final segment = _currentSegments[_currentSegmentIndex!];
    final textToSpeak = segment.originalText;

    await speak(textToSpeak);
    if (kDebugMode) {
      debugPrint('현재 세그먼트 다시 읽기: ${_currentSegmentIndex! + 1}/${_currentSegments.length}');
    }
  }

  /// 다음 세그먼트로 이동
  Future<void> nextSegment() async {
    if (!_isSpeaking) return;
    await _speakNextSegment();
  }

  /// 이전 세그먼트로 이동
  Future<void> previousSegment() async {
    if (!_isSpeaking || _currentSegmentIndex! <= 0) return;

    _currentSegmentIndex = _currentSegmentIndex! - 2;
    await _speakNextSegment();
  }

  /// 세그먼트 스트림 가져오기
  Stream<int>? get segmentStream => _segmentStream;

  /// 캐시 비우기
  void clearCache() {
    _cacheService.clear();
    debugPrint('TTS 캐시 비움');
  }

  // 발화 완료 대기
  Future<void> _waitForSpeechCompletion() async {
    // 최대 10초 대기 (안전장치)
    final maxWait = 10;
    int waitCount = 0;
    
    while (_ttsState == TtsState.playing && waitCount < maxWait) {
      await Future.delayed(const Duration(seconds: 1));
      waitCount++;
    }
  }

  /// 현재 TTS 사용 횟수 가져오기
  Future<int> getCurrentTtsUsageCount() async {
    try {
      // 항상 최신 데이터 가져오기
      _usageLimitService.invalidateCache();
      final usage = await _usageLimitService.getUserUsage(forceRefresh: true);
      final int currentUsage = usage['ttsRequests'] is int 
          ? usage['ttsRequests'] as int 
          : 0;
      return currentUsage;
    } catch (e) {
      debugPrint('TTS 현재 사용량 확인 중 오류: $e');
      return 0;
    }
  }

  /// 남은 TTS 사용량 확인
  Future<int> getRemainingTtsCount() async {
    try {
      final plan = await PlanService().getCurrentPlan();
      final usage = await _usageLimitService.getTtsUsage();
      return (plan['maxTtsCount'] as int) - usage;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTS 사용량 확인 중 오류: $e');
      }
      rethrow;
    }
  }

  /// 전체 TTS 사용 한도 가져오기
  Future<int> getTtsUsageLimit() async {
    final limits = await _usageLimitService.getUserLimits();
    return limits['ttsRequests'] ?? 0;
  }

  /// TTS 사용량 안내 메시지 가져오기 (현재 사용량 포함)
  Future<String> getTtsUsageMessage() async {
    final currentCount = await getCurrentTtsUsageCount();
    final limit = await getTtsUsageLimit();
    return '현재 TTS 사용량: $currentCount/$limit회';
  }

  // 재생 상태 변경 콜백 설정
  void setOnPlayingStateChanged(Function(int?) callback) {
    _onPlayingStateChanged = callback;
  }

  // 재생 완료 콜백 설정
  void setOnPlayingCompleted(Function callback) {
    _onPlayingCompleted = callback;
  }

  /// 이벤트 핸들러 초기화
  Future<void> _setupEventHandlers() async {
    // 재생 시작 이벤트
    _audioPlayer.playbackEventStream.listen((event) {
      if (event.processingState == ProcessingState.ready) {
        debugPrint("TTS 재생 시작");
        _ttsState = TtsState.playing;
      }
    });

    // 재생 완료 이벤트
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        debugPrint("TTS 재생 완료");
        _ttsState = TtsState.stopped;
        _updateCurrentSegment(null);

        if (_onPlayingCompleted != null) {
          _onPlayingCompleted!();
        }
      }
    });
  }

  /// ElevenLabs TTS API를 사용하여 음성 합성
  Future<Uint8List?> _synthesizeSpeech(String text) async {
    try {
      if (_apiKey == null) {
        await _loadApiKey();
      }

      final response = await http.post(
        Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM'),
        headers: {
          'Accept': 'audio/mpeg',
          'Content-Type': 'application/json',
          'xi-api-key': _apiKey!,
        },
        body: json.encode({
          'text': text,
          'model_id': 'eleven_monolingual_v1',
          'voice_settings': {
            'stability': 0.5,
            'similarity_boost': 0.5,
          },
        }),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('음성 합성 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('음성 합성 중 오류: $e');
      }
      rethrow;
    }
  }

  /// 오디오 파일 재생
  Future<void> _playAudioFile(String filePath) async {
    try {
      // 파일이 존재하는지 확인
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ 오디오 파일이 존재하지 않음: $filePath');
        _updateCurrentSegment(null);
        _isSpeaking = false;
        return;
      }

      // 먼저 이전 재생 중지 및 리소스 해제
      await _audioPlayer.stop();
      
      // 파일 경로 설정
      await _audioPlayer.setFilePath(filePath);
      
      // 재생 완료 이벤트 추가 리스너
      final completer = Completer<void>();
      
      // 일회성 이벤트 리스너
      void onComplete() {
        if (!completer.isCompleted) {
          completer.complete();
          debugPrint('🎵 오디오 재생 완료됨');
          _isSpeaking = false;
          _updateCurrentSegment(null);
        }
      }
      
      // 재생 완료 시 호출될 콜백 등록
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          onComplete();
        }
      });
      
      // 오류 발생 시 호출될 콜백 등록
      _audioPlayer.playbackEventStream.listen(
        (_) {},  // 정상 이벤트는 무시
        onError: (Object e, StackTrace stackTrace) {
          debugPrint('❌ 오디오 재생 중 오류: $e');
          onComplete();  // 오류 발생 시에도 완료 처리
        },
      );
      
      // 실제 재생 시작
      await _audioPlayer.play();
      debugPrint('▶️ 오디오 재생 시작: $filePath');
      
      // 안전장치: 10초 후 강제 종료 (무한 재생 방지)
      Future.delayed(const Duration(seconds: 10), () {
        if (_isSpeaking) {
          debugPrint('⚠️ 오디오 재생 타임아웃으로 강제 종료');
          onComplete();
        }
      });
    } catch (e) {
      debugPrint('❌ 오디오 파일 재생 중 오류: $e');
      _isSpeaking = false;
      _updateCurrentSegment(null);
    }
  }

  /// 전체 텍스트 읽기
  Future<void> speakFullText(ProcessedText text) async {
    if (!_isSpeaking) await speakAllSegments(text);
  }
}
