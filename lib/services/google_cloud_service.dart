import 'dart:io';
import 'package:flutter/foundation.dart';
import 'enhanced_ocr_service.dart';
import 'translation_service.dart';
import '.language_service_interface.dart';
import '../utils/language_constants.dart';

/// Google Cloud 서비스를 통합적으로 관리하는 클래스
/// OCR 및 번역 기능을 제공합니다.
/// MARK: 다국어 지원을 위한 확장 포인트

class GoogleCloudService implements LanguageServiceInterface, ChineseLanguageServiceInterface {
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final TranslationService _translationService = TranslationService();

  // 싱글톤 패턴 구현
  static final GoogleCloudService _instance = GoogleCloudService._internal();
  factory GoogleCloudService() => _instance;
  GoogleCloudService._internal();

  /// 이미지에서 텍스트 추출 (OCR)
  /// 언어별 텍스트를 추출합니다.
  @override
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
  @override
  Future<String> translateText(String text, {
    String? sourceLanguage,
    String? targetLanguage,
  }) async {
    try {
      if (text.isEmpty) {
        debugPrint('GoogleCloudService: 번역할 텍스트가 비어 있습니다.');
        return '';
      }

      // 소스 언어가 지정되지 않은 경우 자동 감지
      final source = sourceLanguage ?? 'auto';
      
      // 타겟 언어는 기본값 설정
      final target = targetLanguage ?? TargetLanguage.DEFAULT;

      debugPrint(
          'GoogleCloudService: 텍스트 번역 시작 (${text.length} 자, 소스 언어: $source, 대상 언어: $target)');

      // 텍스트가 너무 길면 분할하여 번역
      if (text.length > 5000) {
        debugPrint('GoogleCloudService: 텍스트가 너무 길어 분할하여 번역합니다.');
        return await _translateLongText(text, sourceLanguage: source, targetLanguage: target);
      }

      final result = await _translationService.translateText(
        text,
        sourceLanguage: source,
        targetLanguage: target,
      );

      debugPrint('GoogleCloudService: 텍스트 번역 완료 (${result.length} 자)');
      return result;
    } catch (e) {
      debugPrint('GoogleCloudService: 텍스트 번역 중 오류 발생: $e');
      throw Exception('텍스트를 번역할 수 없습니다: $e');
    }
  }

  /// 긴 텍스트를 분할하여 번역
  Future<String> _translateLongText(String text,
      {String? sourceLanguage, String? targetLanguage}) async {
    try {
      // 소스 언어가 지정되지 않은 경우 자동 감지
      final source = sourceLanguage ?? 'auto';
      
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

            final translatedSentence = await _translationService.translateText(
              sentence,
              sourceLanguage: source,
              targetLanguage: target,
            );

            translatedSentences.add(translatedSentence);
          }

          translatedParagraphs.add(translatedSentences.join(' '));
        } else {
          // 문단 단위로 번역
          final translatedParagraph = await _translationService.translateText(
            paragraph,
            sourceLanguage: source,
            targetLanguage: target,
          );

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
  @override
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    try {
      debugPrint('GoogleCloudService: 지원 언어 목록 조회 시작');
      final languages = await _translationService.getSupportedLanguages();
      debugPrint(
          'GoogleCloudService: 지원 언어 목록 조회 완료 (${languages.length}개 언어)');
      return languages;
    } catch (e) {
      debugPrint('GoogleCloudService: 지원 언어 목록 조회 중 오류 발생: $e');
      // MVP에서는 한국어와 영어만 지원
      return [
        {'code': 'ko', 'name': '한국어'},
        {'code': 'en', 'name': 'English'},
      ];
    }
  }
  
  /// 텍스트를 문장으로 분리
  @override
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
  
  /// 발음 생성 (중국어의 경우 핀인)
  @override
  Future<String> generatePronunciation(String text, {String? languageCode}) async {
    // 언어별 발음 생성 처리 (MVP에서는 중국어 핀인만 구현)
    final language = languageCode ?? SourceLanguage.DEFAULT;
    final processor = getLanguageProcessor(language);
    
    if (processor == LanguageProcessor.chinese) {
      return await generatePinyin(text);
    }
    
    // 다른 언어는 미구현
    return '';
  }
  
  /// 중국어 핀인 생성 (ChineseLanguageServiceInterface 구현)
  @override
  Future<String> generatePinyin(String text) async {
    // TODO: 실제 구현체 호출
    // 현재는 가상 구현
    try {
      return ''; // 실제로는 PinyinCreationService 호출해야 함
    } catch (e) {
      debugPrint('핀인 생성 중 오류 발생: $e');
      return '';
    }
  }
  
  /// 중국어 텍스트 분절 (ChineseLanguageServiceInterface 구현)
  @override
  Future<List<String>> segmentChineseText(String text) async {
    // TODO: 실제 구현체 호출
    // 현재는 가상 구현
    try {
      return [text]; // 실제로는 ChineseSegmenterService 호출해야 함
    } catch (e) {
      debugPrint('중국어 분절 중 오류 발생: $e');
      return [text];
    }
  }
  
  /// 중국어 단어 사전 검색 (ChineseLanguageServiceInterface 구현)
  @override
  Future<Map<String, dynamic>?> lookupChineseWord(String word) async {
    // TODO: 실제 구현체 호출
    // 현재는 가상 구현
    try {
      return null; // 실제로는 DictionaryService 호출해야 함
    } catch (e) {
      debugPrint('중국어 단어 검색 중 오류 발생: $e');
      return null;
    }
  }
  
  /// 언어 감지
  @override
  Future<String> detectLanguage(String text) async {
    // TODO: 실제 언어 감지 API 호출
    // MVP에서는 중국어로 가정
    return SourceLanguage.DEFAULT;
  }
  
  /// 언어 프로세서 타입 가져오기
  @override
  LanguageProcessor getLanguageProcessor(String languageCode) {
    return getProcessorForLanguage(languageCode);
  }
}
