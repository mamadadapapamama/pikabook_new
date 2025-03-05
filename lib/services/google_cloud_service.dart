import 'dart:io';
import 'package:flutter/foundation.dart';
import 'ocr_service.dart';
import 'translation_service.dart';

/// Google Cloud 서비스를 통합적으로 관리하는 클래스
/// OCR 및 번역 기능을 제공합니다.
class GoogleCloudService {
  final OcrService _ocrService = OcrService();
  final TranslationService _translationService = TranslationService();

  // 싱글톤 패턴 구현
  static final GoogleCloudService _instance = GoogleCloudService._internal();
  factory GoogleCloudService() => _instance;
  GoogleCloudService._internal();

  /// 이미지에서 텍스트 추출 (OCR)
  /// 중국어 텍스트를 추출합니다.
  Future<String> extractTextFromImage(File imageFile) async {
    try {
      debugPrint('GoogleCloudService: 이미지에서 중국어 텍스트 추출 시작');
      final result = await _ocrService.extractText(imageFile);
      debugPrint('GoogleCloudService: 텍스트 추출 완료 (${result.length} 자)');
      return result;
    } catch (e) {
      debugPrint('GoogleCloudService: 텍스트 추출 중 오류 발생: $e');
      throw Exception('텍스트를 추출할 수 없습니다: $e');
    }
  }

  /// 텍스트 번역
  /// 중국어 텍스트를 한국어 또는 영어로 번역합니다.
  Future<String> translateText(String text, {String? targetLanguage}) async {
    try {
      if (text.isEmpty) {
        debugPrint('GoogleCloudService: 번역할 텍스트가 비어 있습니다.');
        return '';
      }

      // MVP에서는 타겟 언어를 한국어 또는 영어로만 제한
      final target = (targetLanguage == 'ko' || targetLanguage == 'en')
          ? targetLanguage!
          : 'ko'; // 기본값: 한국어

      debugPrint(
          'GoogleCloudService: 중국어 텍스트 번역 시작 (${text.length} 자, 대상 언어: $target)');

      // 텍스트가 너무 길면 분할하여 번역
      if (text.length > 5000) {
        debugPrint('GoogleCloudService: 텍스트가 너무 길어 분할하여 번역합니다.');
        return await _translateLongText(text, targetLanguage: target);
      }

      final result = await _translationService.translateText(
        text,
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
      {String? targetLanguage}) async {
    try {
      // MVP에서는 타겟 언어를 한국어 또는 영어로만 제한
      final target = (targetLanguage == 'ko' || targetLanguage == 'en')
          ? targetLanguage!
          : 'ko'; // 기본값: 한국어

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
          final sentences = paragraph.split(RegExp(r'(?<=[.!?])\s+'));
          final translatedSentences = <String>[];

          // 문장 단위로 번역
          for (final sentence in sentences) {
            if (sentence.isEmpty) continue;

            final translatedSentence = await _translationService.translateText(
              sentence,
              targetLanguage: target,
            );

            translatedSentences.add(translatedSentence);
          }

          translatedParagraphs.add(translatedSentences.join(' '));
        } else {
          // 문단 단위로 번역
          final translatedParagraph = await _translationService.translateText(
            paragraph,
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
  /// MVP에서는 한국어와 영어만 지원합니다.
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
}
