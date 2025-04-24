import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../models/processed_text.dart';
import '../../utils/language_constants.dart';
import '../common/usage_limit_service.dart';
import '../text_processing/internal_cn_segmenter_service.dart';

/// TextToSpeech 서비스 (TTS)
/// 
/// 앱 전체의 TTS 기능을 관리하는 중앙 서비스입니다.
/// 
/// ## 주요 기능
/// - 다양한 언어(중국어, 한국어 등)의 텍스트 음성 변환
/// - 세그먼트 단위 텍스트 읽기
/// - ProcessedText 전체 읽기
/// - 문장 분할 및 순차적 읽기
/// - TTS 사용량 제한 관리
/// - 언어별 최적화된 음성 설정
///
/// ## 사용 예시
/// ```dart
/// final ttsService = TtsService();
/// await ttsService.init();
/// await ttsService.speak("안녕하세요");
/// 
/// // 세그먼트 읽기
/// await ttsService.speakSegment("你好", 0);
/// 
/// // 전체 ProcessedText 읽기
/// await ttsService.speakAllSegments(processedText);
/// ```
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

  // 캐시된 음성 데이터 (텍스트 -> 사용 가능 여부)
  final Map<String, bool> _ttsCache = {};

  // 사용량 제한 서비스
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // 문장 분할 서비스 (text_reader_service에서 이동)
  final InternalCnSegmenterService _segmenterService = InternalCnSegmenterService();

  // 초기화
  Future<void> init() async {
    _flutterTts = FlutterTts();
    
    // 문장 분할 서비스 초기화
    await _segmenterService.initialize();

    try {
      // 오디오 세션 설정 (iOS/macOS에서 중요)
      await _flutterTts?.setSharedInstance(true);
      await _flutterTts?.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker
        ],
        IosTextToSpeechAudioMode.defaultMode
      );
      
      // 오디오 포커스 설정 (Android용)
      await _flutterTts?.setQueueMode(1); // 1: QUEUE_ADD
      
      debugPrint('TTS 엔진 초기화 성공');
    } catch (e) {
      debugPrint('오디오 세션 설정 중 오류(무시 가능): $e');
    }
    
    // 이벤트 리스너 설정
    await _setupEventHandlers();

    // 언어 설정
    await setLanguage(_currentLanguage);
    
    // 가용성 확인
    try {
      bool isAvailable = await _flutterTts?.isLanguageAvailable(_currentLanguage) ?? false;
      debugPrint('TTS 언어 가용성: $_currentLanguage = $isAvailable');
      
      // 음성 목록 확인
      final voices = await _flutterTts?.getVoices;
      debugPrint('사용 가능한 음성 수: ${voices?.length ?? 0}');
      
      // 시스템 볼륨 확인 (iOS에서만 가능)
      final volume = await _flutterTts?.getMaxSpeechInputLength;
      debugPrint('현재 설정된 볼륨 정보: $volume');
    } catch (e) {
      debugPrint('TTS 가용성 확인 중 오류(무시 가능): $e');
    }
  }

  // 언어 설정
  Future<void> setLanguage(String language) async {
    if (_flutterTts == null) await init();

    _currentLanguage = language;
    
    // TTS에 맞는 언어 코드로 변환
    final ttsLanguageCode = TtsLanguage.getTtsLanguageCode(language);
    await _flutterTts?.setLanguage(ttsLanguageCode);
    debugPrint('TTS 언어 설정: $ttsLanguageCode');

    // 언어에 따른 음성 설정
    final voiceName = TtsLanguage.getVoiceName(ttsLanguageCode);
    await _flutterTts?.setVoice({"name": voiceName, "locale": ttsLanguageCode});
    debugPrint('TTS 음성 설정: $voiceName, 로케일: $ttsLanguageCode');
    
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
    debugPrint('TTS 설정 완료: 속도=$speechRate, 볼륨=1.0, 피치=1.0');
  }

  /// 텍스트 읽기
  Future<void> speak(String text) async {
    if (_flutterTts == null) await init();
    if (text.isEmpty) return;

    // 이미 캐시된 텍스트인지 확인 (같은 단어를 반복해서 API 호출하지 않도록)
    if (_ttsCache.containsKey(text)) {
      if (_ttsCache[text] == true) {
        // 동일 단어 반복 재생 시, 재생 상태 업데이트만 하고 사용량은 증가시키지 않음
        await _flutterTts?.speak(text);
        (kDebugMode) ? debugPrint('캐시된 TTS 재생 (사용량 변화 없음): $text') : debugPrint('캐시된 TTS 재생 (사용량 변화 없음): $text');
      } else {
        (kDebugMode) ? debugPrint('TTS 사용량 제한으로 재생 불가: $text') : debugPrint('TTS 사용량 제한으로 재생 불가: $text');
        // 여기서 알림을 표시하거나 다른 처리를 할 수 있음
      }
      return;
    }

    // 사용량 제한 확인
    try {
      debugPrint('TTS 요청: ${text.length} 글자');
      final canUseTts = await _usageLimitService.incrementTtsCharCount(text.length);
      if (!canUseTts) {
        _ttsCache[text] = false; // 사용 불가로 캐싱
        debugPrint('TTS 사용량 제한 초과로 재생 불가: $text');
        
        // 여기서 사용자에게 알림을 표시하거나 다른 처리를 할 수 있음
        return;
      }
      
      // 사용량 제한이 없으면 재생
      _ttsCache[text] = true; // 사용 가능으로 캐싱
      await _flutterTts?.speak(text);
      debugPrint('TTS 재생 시작 (사용량 증가): $text');
    } catch (e) {
      debugPrint('TTS 사용량 확인 중 오류: $e');
      // 오류 발생 시 캐싱하지 않음 (다음에 다시 시도)
    }
  }

  // 재생 중지
  Future<void> stop() async {
    if (_flutterTts == null) return;

    try {
      debugPrint('TtsService: stop() 호출됨');
      await _flutterTts?.stop();
      _ttsState = TtsState.stopped;

      // 현재 재생 중인 세그먼트 초기화
      _updateCurrentSegment(null);
      
      debugPrint('TtsService: stop() 완료');
    } catch (e) {
      debugPrint('TtsService: stop() 중 오류 발생: $e');
      // 오류 발생시에도 상태 초기화
      _ttsState = TtsState.stopped;
      _updateCurrentSegment(null);
    }
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
    if (text.isEmpty) return;
    
    // 현재 재생 중인 세그먼트 설정 (즉시 업데이트)
    _updateCurrentSegment(segmentIndex);
    
    // 이미 캐시된 텍스트인지 확인
    if (_ttsCache.containsKey(text)) {
      if (_ttsCache[text] == true) {
        await _flutterTts?.speak(text);
        debugPrint('캐시된 세그먼트 TTS 재생 (사용량 변화 없음): $text (segmentIndex: $segmentIndex)');
      } else {
        debugPrint('TTS 사용량 제한으로 세그먼트 재생 불가: $text');
        _updateCurrentSegment(null); // 재생 불가 시 세그먼트 인덱스 초기화
      }
      return;
    }
    
    // 사용량 제한 확인
    try {
      debugPrint('TTS 세그먼트 요청: ${text.length} 글자 (segmentIndex: $segmentIndex)');
      final canUseTts = await _usageLimitService.incrementTtsCharCount(text.length);
      if (!canUseTts) {
        _ttsCache[text] = false; // 사용 불가로 캐싱
        debugPrint('TTS 사용량 제한 초과로 세그먼트 재생 불가: $text');
        _updateCurrentSegment(null); // 재생 불가 시 세그먼트 인덱스 초기화
        return;
      }
      
      _ttsCache[text] = true; // 사용 가능으로 캐싱
      await _flutterTts?.speak(text);
      debugPrint('세그먼트 TTS 재생 시작 (사용량 증가): $text (segmentIndex: $segmentIndex)');
    } catch (e) {
      debugPrint('TTS 사용량 확인 중 오류: $e');
      _updateCurrentSegment(null); // 오류 발생 시 세그먼트 인덱스 초기화
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

    // 사용 가능 여부 확인 (세그먼트 개수만큼 사용량 필요)
    final segmentCount = processedText.segments?.length ?? 1;
    
    try {
      // 남은 사용량 확인
      final remainingCount = await getRemainingTtsCount();
      
      // 남은 사용량이 부족한 경우
      if (remainingCount < segmentCount) {
        debugPrint('TTS 사용량 부족: 필요=$segmentCount, 남음=$remainingCount');
        // 여기서 사용자에게 알림 표시
        return;
      }
    } catch (e) {
      debugPrint('TTS 사용량 확인 중 오류: $e');
      // 오류 발생 시 계속 진행
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

      // 이미 캐시된 텍스트인지 확인
      if (_ttsCache.containsKey(text)) {
        if (_ttsCache[text] == true) {
          await _flutterTts?.speak(text);
        } else {
          debugPrint('TTS 사용량 제한으로 세그먼트 재생 불가: $text');
          continue; // 다음 세그먼트로 진행
        }
      } else {
        // 사용량 제한 확인
        try {
          debugPrint('TTS 세그먼트 요청: ${text.length} 글자');
          final canUseTts = await _usageLimitService.incrementTtsCharCount(text.length);
          if (!canUseTts) {
            _ttsCache[text] = false; // 사용 불가로 캐싱
            debugPrint('TTS 사용량 제한 초과로 세그먼트 재생 불가: $text');
            continue; // 다음 세그먼트로 진행
          }
          
          _ttsCache[text] = true; // 사용 가능으로 캐싱
          await _flutterTts?.speak(text);
        } catch (e) {
          debugPrint('TTS 사용량 확인 중 오류: $e');
          continue; // 다음 세그먼트로 진행
        }
      }

      // 발화 완료 대기
      await _waitForSpeechCompletion();
    }

    // 재생 완료 후 처리
    _updateCurrentSegment(null);
    _ttsState = TtsState.stopped;
  }

  // TTS 사용 가능 여부 확인
  Future<bool> canUseTts() async {
    try {
      final limits = await _usageLimitService.checkFreeLimits();
      return !limits['ttsLimitReached']!;
    } catch (e) {
      debugPrint('TTS 사용량 제한 확인 중 오류: $e');
      return true; // 오류 시 기본적으로 사용 가능하도록
    }
  }

  // 남은 TTS 사용량 확인
  Future<int> getRemainingTtsCount() async {
    try {
      final usage = await _usageLimitService.getUserUsage();
      final int currentUsage = usage['ttsRequests'] is int 
          ? usage['ttsRequests'] as int 
          : 0;
      return UsageLimitService.MAX_FREE_TTS_REQUESTS - currentUsage;
    } catch (e) {
      debugPrint('TTS 남은 사용량 확인 중 오류: $e');
      return 0;
    }
  }

  /// TTS 사용 가능 여부 확인 (UI에서 버튼 상태 결정에 사용)
  Future<bool> isTtsAvailable() async {
    try {
      // 캐시 무효화하고 최신 데이터 가져오기
      _usageLimitService.invalidateCache();
      final usageData = await _usageLimitService.getUserUsage(forceRefresh: true);
      
      // 현재 사용량 직접 확인 (타입 안전성 고려)
      final int currentUsage = usageData['ttsRequests'] is int 
          ? usageData['ttsRequests'] as int 
          : 0;
      
      // 제한 도달 여부 직접 계산 
      final bool isLimitReached = currentUsage >= UsageLimitService.MAX_FREE_TTS_REQUESTS;
      
      debugPrint('TTS 사용 가능 여부 확인: 현재=${currentUsage}/${UsageLimitService.MAX_FREE_TTS_REQUESTS}, 제한 도달=${isLimitReached}');
      
      // 캐시 초기화 (이전 값 사용 방지)
      if (isLimitReached) {
        clearCache();
      }
      
      return !isLimitReached;
    } catch (e) {
      debugPrint('TTS 사용 가능 여부 확인 중 오류: $e');
      return false;  // 오류 시 안전하게 사용 불가로 처리
    }
  }

  /// TTS 제한 안내 메시지 가져오기
  String getTtsLimitMessage() {
    return '무료 사용량(${UsageLimitService.MAX_FREE_TTS_REQUESTS}회)을 모두 사용했습니다. 추가 사용을 원하시면 관리자에게 문의주세요.';
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

  /// 전체 TTS 사용 한도 가져오기
  int getTtsUsageLimit() {
    return UsageLimitService.MAX_FREE_TTS_REQUESTS;
  }

  /// TTS 사용량 안내 메시지 가져오기 (현재 사용량 포함)
  Future<String> getTtsUsageMessage() async {
    final currentCount = await getCurrentTtsUsageCount();
    final limit = getTtsUsageLimit();
    return '현재 TTS 사용량: $currentCount/$limit회';
  }

  /// 이벤트 핸들러 초기화 (TTS 이벤트 리스너 설정)
  Future<void> _setupEventHandlers() async {
    // 이벤트 리스너 설정
    _flutterTts?.setStartHandler(() {
      debugPrint("TTS 재생 시작");
      _ttsState = TtsState.playing;
    });

    _flutterTts?.setCompletionHandler(() {
      debugPrint("TTS 재생 완료");
      _ttsState = TtsState.stopped;
      
      // 재생 완료 시 현재 재생 중인 세그먼트 초기화
      _updateCurrentSegment(null);

      // 재생 완료 콜백 호출 - 항상 호출하도록 수정
      if (_onPlayingCompleted != null) {
        _onPlayingCompleted!();
      }
    });

    _flutterTts?.setCancelHandler(() {
      debugPrint("TTS 재생 취소");
      _ttsState = TtsState.stopped;
      
      // 재생 취소 시 현재 재생 중인 세그먼트 초기화
      _updateCurrentSegment(null);
      
      // 재생 취소 시에도 완료 콜백 호출 (추가)
      if (_onPlayingCompleted != null) {
        _onPlayingCompleted!();
      }
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
      
      // 오류 발생 시 현재 재생 중인 세그먼트 초기화
      _updateCurrentSegment(null);
      
      // 오류 발생 시에도 완료 콜백 호출 (추가)
      if (_onPlayingCompleted != null) {
        _onPlayingCompleted!();
      }
    });
  }
  
  /// TextReaderService에서 이동한 기능: 문장 단위로 분리하여 읽기
  Future<void> readTextBySentences(String text) async {
    // 이미 재생 중인 경우 중지
    if (currentSegmentIndex != null) {
      await stop();
      return;
    }

    // 텍스트를 문장 단위로 분리
    final sentences = _segmenterService.splitIntoSentences(text);

    // 문장이 없으면 전체 텍스트 읽기
    if (sentences.isEmpty) {
      await speak(text);
      return;
    }

    // 각 문장을 순차적으로 읽기
    for (int i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      if (sentence.isEmpty) continue;

      // 현재 문장 재생
      await speakSegment(sentence, i);

      // 재생 완료 대기 (대략적인 시간 계산)
      await Future.delayed(
          Duration(milliseconds: sentence.length * 100 + 1000));

      // 재생이 중단되었는지 확인
      if (currentSegmentIndex == null) break;
    }
  }

  /// TextReaderService에서 이동: 텍스트를 문장 단위로 분리
  List<String> splitIntoSentences(String text) {
    return _segmenterService.splitIntoSentences(text);
  }

  /// TextReaderService에서 이동: ProcessedText에서 세그먼트 텍스트 추출
  List<String> extractSegmentTexts(ProcessedText processedText) {
    if (processedText.segments == null || processedText.segments!.isEmpty) {
      return [processedText.fullOriginalText];
    }

    return processedText.segments!
        .map((segment) => segment.originalText)
        .where((text) => text.isNotEmpty)
        .toList();
  }
}
