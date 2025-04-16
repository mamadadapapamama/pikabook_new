import 'package:flutter/foundation.dart';
import '../models/processed_text.dart';
import 'tts_service.dart';
import 'internal_cn_segmenter_service.dart';

/// 텍스트 읽기 서비스
/// TTS 기능과 문장 분할 기능을 통합하여 제공합니다.
class TextReaderService {
  static final TextReaderService _instance = TextReaderService._internal();
  factory TextReaderService() => _instance;
  TextReaderService._internal();

  final TtsService _ttsService = TtsService();
  final InternalCnSegmenterService _segmenterService = InternalCnSegmenterService();

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
    await _segmenterService.initialize();
    
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

    // 텍스트를 문장 단위로 분리
    final sentences = _segmenterService.splitIntoSentences(text);

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

  /// 텍스트를 문장 단위로 분리
  List<String> splitIntoSentences(String text) {
    return _segmenterService.splitIntoSentences(text);
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
}
