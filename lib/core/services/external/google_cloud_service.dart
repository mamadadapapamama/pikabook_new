import 'dart:io';
import 'package:flutter/foundation.dart';
import '../text_processing/enhanced_ocr_service.dart';
import '../../../LLM test/llm_text_processing.dart';
import '../../utils/language_constants.dart';
import '../../models/chinese_text.dart';

/// Google Cloud 서비스를 통합적으로 관리하는 클래스
/// OCR 및 번역 기능을 제공합니다.
/// MARK: 다국어 지원을 위한 확장 포인트

class GoogleCloudService {
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UnifiedTextProcessingService _textProcessingService = UnifiedTextProcessingService();

  // 싱글톤 패턴 구현
  static final GoogleCloudService _instance = GoogleCloudService._internal();
  factory GoogleCloudService() => _instance;
  GoogleCloudService._internal();

  /// 이미지에서 텍스트 추출 (OCR)
  /// 언어별 텍스트를 추출합니다.
  Future<String> extractText(File imageFile, {String? sourceLanguage}) async {
    try {
      debugPrint('GoogleCloudService: 이미지에서 텍스트 추출 시작');
      // 기본 언어는 중국어 (MVP)
      final source = sourceLanguage ?? SourceLanguage.DEFAULT;
      
      // TODO: 향후 확장 - 언어별 추출 방식 다르게 처리
      final result = await _ocrService.extractText(imageFile);
      
      debugPrint('GoogleCloudService: 텍스트 추출 완료 (${result.length} 자)');
      return result;
    } catch (e) {
      debugPrint('GoogleCloudService: 텍스트 추출 중 오류 발생: $e');
      throw Exception('텍스트를 추출할 수 없습니다: $e');
    }
  }

  /// 텍스트 번역
  /// 다양한 언어 지원 가능
  Future<String> translateText(String text, {
    String? sourceLanguage,
    String? targetLanguage,
    bool countCharacters = true,
  }) async {
    try {
      if (text.isEmpty) {
        debugPrint('GoogleCloudService: 번역할 텍스트가 비어 있습니다.');
        return '';
      }

      // 소스 언어가 지정되지 않은 경우 자동 감지
      final source = sourceLanguage ?? 'zh';
      
      // 타겟 언어는 기본값 설정
      final target = targetLanguage ?? TargetLanguage.DEFAULT;

      debugPrint(
          'GoogleCloudService: 텍스트 번역 시작 (${text.length} 자, 소스 언어: $source, 대상 언어: $target)');

      // 텍스트가 너무 길면 분할하여 번역
      if (text.length > 5000) {
        debugPrint('GoogleCloudService: 텍스트가 너무 길어 분할하여 번역합니다.');
        return await _translateLongText(text, sourceLanguage: source, targetLanguage: target, countCharacters: countCharacters);
      }

      // LLM 처리 서비스 사용
      final chineseText = await _textProcessingService.processWithLLM(text, sourceLanguage: source);
      final result = chineseText.sentences.map((s) => s.translation).join('\n');

      debugPrint('GoogleCloudService: 텍스트 번역 완료 (${result.length} 자)');
      return result;
    } catch (e) {
      debugPrint('GoogleCloudService: 텍스트 번역 중 오류 발생: $e');
      throw Exception('텍스트를 번역할 수 없습니다: $e');
    }
  }

  /// 긴 텍스트를 분할하여 번역
  Future<String> _translateLongText(String text,
      {String? sourceLanguage, String? targetLanguage, bool countCharacters = true}) async {
    try {
      // 소스 언어가 지정되지 않은 경우 자동 감지
      final source = sourceLanguage ?? 'zh';
      
      // 타겟 언어는 기본값 설정
      final target = targetLanguage ?? TargetLanguage.DEFAULT;

      // 텍스트를 문단 단위로 분할
      final paragraphs = text.split('\n\n');
      final translatedParagraphs = <String>[];

      // 각 문단을 번역
      for (int i = 0; i < paragraphs.length; i++) {
        final paragraph = paragraphs[i].trim();
        if (paragraph.isEmpty) {
          translatedParagraphs.add('');
          continue;
        }

        debugPrint(
            'GoogleCloudService: 문단 ${i + 1}/${paragraphs.length} 번역 중 (${paragraph.length} 자)');

        // 문단이 너무 길면 더 작은 단위로 분할
        if (paragraph.length > 5000) {
          // 언어에 맞는 문장 분리 규칙 적용
          final sentencePattern = SentenceSplitRules.getPatternForLanguage(sourceLanguage ?? SourceLanguage.DEFAULT);
          
          final sentences = paragraph.split(sentencePattern);
          final translatedSentences = <String>[];

          // 문장 단위로 번역
          for (final sentence in sentences) {
            if (sentence.isEmpty) continue;

            // LLM 서비스로 번역
            final chineseText = await _textProcessingService.processWithLLM(
              sentence,
              sourceLanguage: source
            );
            final translatedSentence = chineseText.sentences.map((s) => s.translation).join('\n');

            translatedSentences.add(translatedSentence);
          }

          translatedParagraphs.add(translatedSentences.join(' '));
        } else {
          // 문단 단위로 번역
          final chineseText = await _textProcessingService.processWithLLM(
            paragraph, 
            sourceLanguage: source
          );
          final translatedParagraph = chineseText.sentences.map((s) => s.translation).join('\n');

          translatedParagraphs.add(translatedParagraph);
        }
      }

      // 번역된 문단을 합쳐서 반환
      return translatedParagraphs.join('\n\n');
    } catch (e) {
      debugPrint('GoogleCloudService: 긴 텍스트 번역 중 오류 발생: $e');
      throw Exception('긴 텍스트를 번역할 수 없습니다: $e');
    }
  }

  /// 지원되는 언어 목록 가져오기
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    try {
      debugPrint('GoogleCloudService: 지원 언어 목록 조회 시작');
      // 현재는 중국어->한국어만 지원
      final languages = [
        {'code': 'zh', 'name': '중국어'},
        {'code': 'ko', 'name': '한국어'},
      ];
      
      debugPrint('GoogleCloudService: 지원 언어 목록 조회 완료 (${languages.length}개 언어)');
      return languages;
    } catch (e) {
      debugPrint('GoogleCloudService: 지원 언어 목록 조회 중 오류 발생: $e');
      // MVP에서는 한국어와 영어만 지원
      return [
        {'code': 'ko', 'name': '한국어'},
        {'code': 'zh', 'name': '중국어'},
      ];
    }
  }
  
  /// 텍스트를 문장으로 분리
  List<String> splitTextIntoSentences(String text, {String? languageCode}) {
    if (text.isEmpty) return [];
    
    final language = languageCode ?? SourceLanguage.DEFAULT;
    final pattern = SentenceSplitRules.getPatternForLanguage(language);
    
    // 빈 문장 제거 및 공백 처리
    return text
        .split(pattern)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  
  /// 언어 감지
  Future<String> detectLanguage(String text) async {
    // 현재는 기본 언어만 지원
    return SourceLanguage.DEFAULT;
  }
}
