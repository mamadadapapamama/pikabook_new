import 'package:flutter/foundation.dart';
import '../../models/processed_text.dart';
import '../media/tts_service.dart';
import 'internal_cn_segmenter_service.dart';

/// 이 클래스는 더 이상 사용되지 않습니다.
/// 
/// ## 대체 방법:
/// 모든 TTS 관련 기능은 TtsService로 통합되었습니다.
/// 
/// ```dart
/// // 대신 TtsService를 사용하세요:
/// final ttsService = TtsService();
/// await ttsService.init();
/// await ttsService.speak("안녕하세요");
/// await ttsService.speakSegment("你好", 0);
/// await ttsService.readTextBySentences("긴 문장...");
/// ```
@Deprecated("TtsService로 통합되었습니다. TtsService를 직접 사용하세요.")
class TextReaderService {
  static final TextReaderService _instance = TextReaderService._internal();
  factory TextReaderService() => _instance;
  TextReaderService._internal();

  final TtsService _ttsService = TtsService();

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
  }

  /// 단일 세그먼트 읽기
  Future<void> readSegment(String text, int segmentIndex) async {
    await _ttsService.speakSegment(text, segmentIndex);
  }

  /// ProcessedText의 모든 세그먼트 읽기
  Future<void> readAllSegments(ProcessedText processedText) async {
    await _ttsService.speakAllSegments(processedText);
  }

  /// 전체 텍스트 읽기
  Future<void> readText(String text) async {
    await _ttsService.speak(text);
  }

  /// 텍스트를 문장 단위로 분리하여 읽기
  Future<void> readTextBySentences(String text) async {
    await _ttsService.readTextBySentences(text);
  }

  /// 텍스트를 문장 단위로 분리
  List<String> splitIntoSentences(String text) {
    return _ttsService.splitIntoSentences(text);
  }

  /// ProcessedText에서 세그먼트 텍스트 추출
  List<String> extractSegmentTexts(ProcessedText processedText) {
    return _ttsService.extractSegmentTexts(processedText);
  }
}
