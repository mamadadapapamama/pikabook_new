import 'package:flutter/foundation.dart';
import '../../models/processed_text.dart';
import '../media/tts_service.dart';
import '../../../LLM test/llm_text_processing.dart';
import '../../models/chinese_text.dart';

/// 텍스트 읽기 서비스
class TextReaderService {
  static final TextReaderService _instance = TextReaderService._internal();
  factory TextReaderService() => _instance;
  TextReaderService._internal();

  final TtsService _ttsService = TtsService();
  final UnifiedTextProcessingService _textProcessingService = UnifiedTextProcessingService();
  
  // TtsService getter 추가
  TtsService get ttsService => _ttsService;
  
  // 마지막으로 처리한 텍스트를 캐싱하여 불필요한 LLM 호출 방지
  String? _lastProcessedText;
  ChineseText? _lastProcessedResult;

  // 현재 재생 중인 세그먼트 인덱스
  int? get currentSegmentIndex => _ttsService.currentSegmentIndex;
  
  // 현재 재생 중인지 여부
  bool get isPlaying => currentSegmentIndex != null;

  // 재생 상태 변경 콜백
  void setOnPlayingStateChanged(Function(int?) callback) {
    _ttsService.setOnPlayingStateChanged(callback);
  }

  // 재생 완료 콜백
  void setOnPlayingCompleted(Function callback) {
    _ttsService.setOnPlayingCompleted(callback);
  }

  /// 서비스 초기화
  Future<void> init() async {
    await _ttsService.init();
    await _textProcessingService.ensureInitialized();
    
    // TTS 상태 변경 리스너 등록
    _ttsService.setOnPlayingStateChanged((segmentIndex) {
      // 별도의 로직 추가 가능
      debugPrint('TextReaderService: TTS 상태 변경 - segmentIndex=$segmentIndex');
    });
    
    // TTS 재생 완료 리스너 등록
    _ttsService.setOnPlayingCompleted(() {
      debugPrint('TextReaderService: TTS 재생 완료 이벤트 수신');
    });
  }

  /// 리소스 해제
  void dispose() {
    _ttsService.dispose();
    _lastProcessedText = null;
    _lastProcessedResult = null;
  }

  /// 언어 설정
  Future<void> setLanguage(String language) async {
    await _ttsService.setLanguage(language);
  }

  /// 텍스트 읽기 중지
  Future<void> stop() async {
    await _ttsService.stop();
    debugPrint('TextReaderService: TTS 중지됨');
  }

  /// 단일 세그먼트 읽기
  Future<void> readSegment(String text, int segmentIndex) async {
    debugPrint('TextReaderService: 세그먼트 읽기 시작 - segmentIndex=$segmentIndex, text="${text.substring(0, text.length > 20 ? 20 : text.length)}..."');
    await _ttsService.speakSegment(text, segmentIndex);
  }

  /// ProcessedText의 모든 세그먼트 읽기
  Future<void> readAllSegments(ProcessedText processedText) async {
    // 이미 재생 중이면 중지
    if (isPlaying) {
      await stop();
      return;
    }

    // 전체 텍스트 읽기
    await _ttsService.speakAllSegments(processedText);
  }

  /// 전체 텍스트 읽기
  Future<void> readText(String text) async {
    // 이미 재생 중이면 중지
    if (isPlaying) {
      await stop();
      return;
    }

    // 빈 텍스트는 무시
    if (text.isEmpty) return;

    // 전체 텍스트 읽기
    debugPrint('TextReaderService: 전체 텍스트 읽기 - text="${text.substring(0, text.length > 20 ? 20 : text.length)}..."');
    await _ttsService.speak(text);
  }

  /// 텍스트를 문장 단위로 분리하여 읽기
  Future<void> readTextBySentences(String text) async {
    // 이미 재생 중인 경우 중지
    if (currentSegmentIndex != null) {
      await stop();
      return;
    }
    
    if (text.isEmpty) return;

    // 텍스트를 LLM을 사용하여 처리하고 문장 가져오기
    final ChineseText chineseText = await _processWithLLM(text);
    final List<String> sentences = chineseText.sentences.map((s) => s.original).toList();

    // 문장이 없으면 전체 텍스트 읽기
    if (sentences.isEmpty) {
      await readText(text);
      return;
    }

    // 각 문장을 순차적으로 읽기
    for (int i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      if (sentence.isEmpty) continue;

      // 현재 문장 재생
      await _ttsService.speakSegment(sentence, i);

      // 재생 완료 대기 (대략적인 시간 계산)
      await Future.delayed(
          Duration(milliseconds: sentence.length * 100 + 1000));

      // 재생이 중단되었는지 확인
      if (currentSegmentIndex == null) break;
    }
  }

  /// 텍스트를 문장 단위로 분리 - LLM 처리 결과 재사용
  Future<List<String>> splitIntoSentences(String text) async {
    if (text.isEmpty) return [];
    
    try {
      // LLM을 통해 처리된 ChineseText에서 문장만 추출
      final ChineseText chineseText = await _processWithLLM(text);
      return chineseText.sentences.map((sentence) => sentence.original).toList();
    } catch (e) {
      debugPrint('TextReaderService: 문장 분리 중 오류 발생 - $e');
      
      // 오류 발생 시 간단한 구분자로 분리 (백업 방식)
      return text.split(RegExp(r'[.!?。！？\n]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
  }

  /// ProcessedText에서 세그먼트 텍스트 추출
  List<String> extractSegmentTexts(ProcessedText processedText) {
    if (processedText.segments == null || processedText.segments!.isEmpty) {
      return [processedText.fullOriginalText];
    }

    return processedText.segments!
        .map((segment) => segment.originalText)
        .where((text) => text.isNotEmpty)
        .toList();
  }
  
  /// LLM 텍스트 처리 - 중복 호출 방지를 위한 캐싱 추가
  Future<ChineseText> _processWithLLM(String text) async {
    // 이미 처리된 텍스트인 경우 캐시된 결과 반환
    if (_lastProcessedText == text && _lastProcessedResult != null) {
      debugPrint('TextReaderService: 캐시된 LLM 처리 결과 사용');
      return _lastProcessedResult!;
    }
    
    // 새로운 텍스트 처리
    final result = await _textProcessingService.processWithLLM(text);
    
    // 결과 캐싱
    _lastProcessedText = text;
    _lastProcessedResult = result;
    
    return result;
  }
}
