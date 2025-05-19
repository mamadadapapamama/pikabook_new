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

// 텍스트 음성 변환 서비스를 제공합니다

enum TtsState { playing, stopped, paused, continued }

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  TtsState _ttsState = TtsState.stopped;
  String _currentLanguage = SourceLanguage.DEFAULT; // 기본 언어: 중국어
  String? _apiKey;

  // 현재 재생 중인 세그먼트 인덱스
  int? _currentSegmentIndex;

  // 재생 상태 변경 콜백
  Function(int?)? _onPlayingStateChanged;

  // 재생 완료 콜백
  Function? _onPlayingCompleted;

  // 캐시된 음성 데이터 (텍스트 -> 파일 경로)
  final Map<String, String> _ttsCache = {};

  // 사용량 제한 서비스
  final UsageLimitService _usageLimitService = UsageLimitService();

  // 초기화
  Future<void> init() async {
    try {
      // API 키 로드
      await _loadApiKey();
      
      if (_apiKey == null || _apiKey!.isEmpty) {
        throw Exception('ElevenLabs API 키를 로드할 수 없습니다.');
      }

      // 오디오 플레이어 이벤트 리스너 설정
      _audioPlayer.playbackEventStream.listen(
        (event) {
          // 재생 상태 변경 처리
          debugPrint('TTS 재생 상태 변경: ${event.processingState}');
        },
        onError: (Object e, StackTrace stackTrace) {
          debugPrint('오디오 플레이어 오류: $e');
        },
      );
      
      debugPrint('TTS 엔진 초기화 성공');
    } catch (e) {
      debugPrint('TTS 엔진 초기화 중 오류: $e');
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
    if (text.isEmpty) return;

    // 이미 캐시된 텍스트인지 확인
    if (_ttsCache.containsKey(text)) {
      final audioFile = _ttsCache[text];
      if (audioFile != null) {
        // 캐시된 오디오 파일 재생
        await _playAudioFile(audioFile);
        debugPrint('캐시된 TTS 재생 (사용량 변화 없음): $text');
      } else {
        debugPrint('TTS 사용량 제한으로 재생 불가: $text');
      }
      return;
    }

    // 사용량 제한 확인
    try {
      debugPrint('TTS 요청: ${text.length} 글자');
      final canUseTts = await _usageLimitService.incrementTtsCharCount(text.length);
      if (!canUseTts) {
        _ttsCache[text] = ''; // 사용 불가로 캐싱
        debugPrint('TTS 사용량 제한 초과로 재생 불가: $text');
        return;
      }
      
      // Google Cloud TTS API 호출
      final audioData = await _synthesizeSpeech(text);
      if (audioData != null) {
        // 오디오 데이터를 파일로 저장
        final audioFile = await _saveAudioToFile(audioData, text);
        _ttsCache[text] = audioFile; // 파일 경로 캐싱
        
        // 오디오 파일 재생
        await _playAudioFile(audioFile);
        debugPrint('TTS 재생 시작 (사용량 증가): $text');
      }
    } catch (e) {
      debugPrint('TTS 처리 중 오류: $e');
    }
  }

  // 재생 중지
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _ttsState = TtsState.stopped;
      _updateCurrentSegment(null);
      debugPrint('TtsService: stop() 완료');
    } catch (e) {
      debugPrint('TtsService: stop() 중 오류 발생: $e');
      _ttsState = TtsState.stopped;
      _updateCurrentSegment(null);
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
    await _audioPlayer.dispose();
    _onPlayingStateChanged = null;
    _onPlayingCompleted = null;
  }

  // 현재 재생 중인 세그먼트 업데이트
  void _updateCurrentSegment(int? segmentIndex) {
    _currentSegmentIndex = segmentIndex;
    if (_onPlayingStateChanged != null) {
      _onPlayingStateChanged!(_currentSegmentIndex);
    }
  }

  /// **세그먼트 단위로 텍스트 읽기**
  Future<void> speakSegment(String text, int segmentIndex) async {
    if (text.isEmpty) return;
    
    // 현재 재생 중인 세그먼트 설정
    _updateCurrentSegment(segmentIndex);
    
    // 이미 캐시된 텍스트인지 확인
    if (_ttsCache.containsKey(text)) {
      final audioFile = _ttsCache[text];
      if (audioFile != null && audioFile.isNotEmpty) {
        await _playAudioFile(audioFile);
        debugPrint('캐시된 세그먼트 TTS 재생 (사용량 변화 없음): $text (segmentIndex: $segmentIndex)');
      } else {
        debugPrint('TTS 사용량 제한으로 세그먼트 재생 불가: $text');
        _updateCurrentSegment(null);
      }
      return;
    }
    
    // 사용량 제한 확인
    try {
      debugPrint('TTS 세그먼트 요청: ${text.length} 글자 (segmentIndex: $segmentIndex)');
      final canUseTts = await _usageLimitService.incrementTtsCharCount(text.length);
      if (!canUseTts) {
        _ttsCache[text] = ''; // 사용 불가로 캐싱
        debugPrint('TTS 사용량 제한 초과로 세그먼트 재생 불가: $text');
        _updateCurrentSegment(null);
        return;
      }
      
      // Google Cloud TTS API 호출
      final audioData = await _synthesizeSpeech(text);
      if (audioData != null) {
        // 오디오 데이터를 파일로 저장
        final audioFile = await _saveAudioToFile(audioData, text);
        _ttsCache[text] = audioFile; // 파일 경로 캐싱
        
        // 오디오 파일 재생
        await _playAudioFile(audioFile);
        debugPrint('세그먼트 TTS 재생 시작 (사용량 증가): $text (segmentIndex: $segmentIndex)');
      }
    } catch (e) {
      debugPrint('TTS 세그먼트 처리 중 오류: $e');
      _updateCurrentSegment(null);
    }
  }

  /// **ProcessedText의 모든 세그먼트 순차적으로 읽기**
  Future<void> speakAllSegments(ProcessedText processedText) async {
    // 이미 재생 중이면 중지
    if (_ttsState == TtsState.playing) {
      await stop();
      return;
    }

    // 사용 가능 여부 확인 (세그먼트 개수만큼 사용량 필요)
    final segmentCount = processedText.segments?.length ?? 1;
    
    try {
      // 남은 사용량 확인
      final remainingCount = await getRemainingTtsCount();
      
      // 남은 사용량이 부족한 경우
      if (remainingCount < segmentCount) {
        debugPrint('TTS 사용량 부족: 필요=$segmentCount, 남음=$remainingCount');
        return;
      }
    } catch (e) {
      debugPrint('TTS 사용량 확인 중 오류: $e');
    }

    // 세그먼트가 없거나 비어있는 경우 전체 원문 텍스트 읽기
    if (processedText.segments == null || processedText.segments!.isEmpty) {
      debugPrint("세그먼트가 없어 전체 원문 텍스트 읽기: ${processedText.fullOriginalText.length}자");
      _ttsState = TtsState.playing;
      await speak(processedText.fullOriginalText);
      return;
    }

    // 세그먼트가 있는 경우 각 세그먼트 순차 재생
    debugPrint("세그먼트 ${processedText.segments!.length}개 순차 재생 시작");
    _ttsState = TtsState.playing;
    
    for (int i = 0; i < processedText.segments!.length; i++) {
      if (_ttsState != TtsState.playing) {
        debugPrint("재생 중단됨: _ttsState=$_ttsState");
        break;
      }

      final segment = processedText.segments![i];
      final text = segment.originalText;
      
      // 각 세그먼트 발화
      _updateCurrentSegment(i);
      await speakSegment(text, i);

      // 발화 완료 대기
      await _waitForSpeechCompletion();
    }

    // 재생 완료 후 처리
    _updateCurrentSegment(null);
    _ttsState = TtsState.stopped;
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
  
  // 캐시 비우기
  void clearCache() {
    _ttsCache.clear();
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
      final usage = await _usageLimitService.getUserUsage();
      final limits = await _usageLimitService.getUserLimits();
      final int currentUsage = usage['ttsRequests'] is int 
          ? usage['ttsRequests'] as int 
          : 0;
      return limits['ttsRequests']! - currentUsage;
    } catch (e) {
      debugPrint('TTS 남은 사용량 확인 중 오류: $e');
      return 0;
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
        throw Exception('API 키가 설정되지 않았습니다.');
      }

      // API 엔드포인트
      const url = 'https://api.elevenlabs.io/v1/text-to-speech/4VZIsMPtgggwNg7OXbPY';

      // 요청 헤더
      final headers = {
        'Accept': 'audio/mpeg',
        'Content-Type': 'application/json',
        'xi-api-key': _apiKey!,
      };

      // 요청 본문
      final body = {
        'text': text,
        'model_id': 'eleven_flash_v2_5',
        'voice_settings': {
          'stability': 0.5,
          'similarity_boost': 0.75,
          'style': 0.0,
          'use_speaker_boost': true
        }
      };

      // API 호출
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode(body),
      );

      // 응답 처리
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        debugPrint('ElevenLabs API 오류: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('TTS API 호출 중 오류: $e');
      return null;
    }
  }

  /// 오디오 데이터를 파일로 저장
  Future<String> _saveAudioToFile(Uint8List audioData, String text) async {
    try {
      // 캐시 디렉토리 가져오기
      final cacheDir = await getTemporaryDirectory();
      final fileName = 'tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final file = File('${cacheDir.path}/$fileName');
      
      // 파일 저장
      await file.writeAsBytes(audioData);
      return file.path;
    } catch (e) {
      debugPrint('오디오 파일 저장 중 오류: $e');
      return '';
    }
  }

  /// 오디오 파일 재생
  Future<void> _playAudioFile(String filePath) async {
    try {
      await _audioPlayer.setFilePath(filePath);
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('오디오 파일 재생 중 오류: $e');
    }
  }
}
