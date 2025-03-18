import 'dart:io';
import 'package:flutter/material.dart';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import '../models/text_processing_mode.dart';
import '../models/flash_card.dart';
import '../models/dictionary_entry.dart';
import '../services/dictionary_service.dart';
import '../services/tts_service.dart';
import '../services/enhanced_ocr_service.dart';
import '../services/page_service.dart';

/// PageContentService는 페이지 콘텐츠 처리와 관련된 비즈니스 로직을 담당합니다.
/// PageContentWidget에서 분리된 로직을 포함합니다.
///
///
class PageContentService {
  // 싱글톤 패턴 구현
  static final PageContentService _instance = PageContentService._internal();
  factory PageContentService() => _instance;

  // 서비스 인스턴스
  final DictionaryService _dictionaryService = DictionaryService();
  final TtsService _ttsService = TtsService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final PageService _pageService = PageService();
  
  // 페이지 ID를 키로 사용하여 ProcessedText 객체 캐싱
  final Map<String, ProcessedText> _processedTextCache = {};

  PageContentService._internal() {
    _initTts();
  }

  // ProcessedText 캐시 메서드들
  bool hasProcessedText(String pageId) {
    return _processedTextCache.containsKey(pageId);
  }

  ProcessedText? getProcessedText(String pageId) {
    return _processedTextCache[pageId];
  }

  void setProcessedText(String pageId, ProcessedText processedText) {
    _processedTextCache[pageId] = processedText;
  }

  void removeProcessedText(String pageId) {
    _processedTextCache.remove(pageId);
  }

  void clearProcessedTextCache() {
    _processedTextCache.clear();
  }

  // TTS 초기화
  Future<void> _initTts() async {
    await _ttsService.init();
  }

  // 페이지 텍스트 처리
  Future<ProcessedText?> processPageText({
    required page_model.Page page,
    required File? imageFile,
    required TextProcessingMode textProcessingMode,
  }) async {
    if (page.originalText.isEmpty && imageFile == null) return null;

    try {
      final pageId = page.id;
      if (pageId == null) {
        debugPrint('페이지 ID가 없어 캐시를 확인할 수 없습니다.');
      } else {
        // 캐시된 ProcessedText 확인
        final cachedProcessedText = await _pageService.getCachedProcessedText(
          pageId,
          textProcessingMode.toString().split('.').last, // enum 값을 문자열로 변환
        );

        if (cachedProcessedText != null) {
          debugPrint(
              '캐시된 처리 텍스트 사용: 페이지 ID=$pageId, 모드=${textProcessingMode.toString().split('.').last}');
          return cachedProcessedText;
        }

        debugPrint(
            '캐시된 처리 텍스트 없음: 페이지 ID=$pageId, 모드=${textProcessingMode.toString().split('.').last}');
      }

      // 캐시된 텍스트 확인
      final originalText = page.originalText;
      final translatedText = page.translatedText;

      debugPrint(
          '페이지 텍스트 처리 시작: 페이지 ID=$pageId, 원본 텍스트 ${originalText.length}자, 번역 텍스트 ${translatedText.length}자');

      // 이미지 파일이 있고 텍스트가 없는 경우 OCR 처리
      if (imageFile != null &&
          (originalText.isEmpty || translatedText.isEmpty)) {
        debugPrint('캐시된 텍스트가 없어 OCR 처리 시작');
        final processedText = await _ocrService.processImage(
          imageFile,
          textProcessingMode,
        );

        // 처리된 텍스트를 페이지에 캐싱
        if (processedText.fullOriginalText.isNotEmpty && pageId != null) {
          await updatePageCache(pageId, processedText, textProcessingMode);
        }

        return processedText;
      } else {
        // 기존 텍스트 처리
        debugPrint('기존 텍스트 처리 시작');
        final processedText = await _ocrService.processText(
          originalText,
          textProcessingMode,
        );

        // 번역 텍스트가 변경된 경우에만 페이지 캐시 업데이트
        if (translatedText != processedText.fullTranslatedText &&
            pageId != null) {
          debugPrint('번역 텍스트가 변경되어 페이지 캐시 업데이트');
          await updatePageCache(pageId, processedText, textProcessingMode);
        } else if (pageId != null) {
          debugPrint('번역 텍스트가 동일하여 페이지 내용 업데이트 건너뜀, ProcessedText만 캐싱');
          await _pageService.cacheProcessedText(
            pageId,
            textProcessingMode.toString().split('.').last,
            processedText,
          );
        }

        return processedText;
      }
    } catch (e) {
      debugPrint('텍스트 처리 중 오류 발생: $e');
      return null;
    }
  }

  // 페이지 캐시 업데이트
  Future<void> updatePageCache(
    String pageId,
    ProcessedText processedText,
    TextProcessingMode textProcessingMode,
  ) async {
    try {
      if (pageId.isEmpty) {
        debugPrint('페이지 ID가 없어 캐시 업데이트를 건너뜁니다.');
        return;
      }

      // 페이지 업데이트
      await _pageService.updatePageContent(
        pageId,
        processedText.fullOriginalText,
        processedText.fullTranslatedText ?? '',
      );

      // ProcessedText 객체 캐싱
      await _pageService.cacheProcessedText(
        pageId,
        textProcessingMode.toString().split('.').last,
        processedText,
      );

      debugPrint('페이지 캐시 업데이트 완료: $pageId');
    } catch (e) {
      debugPrint('페이지 캐시 업데이트 중 오류 발생: $e');
    }
  }

  // TTS로 텍스트 읽기
  Future<void> speakText(String text) async {
    if (text.isEmpty) return;

    try {
      // 중국어로 언어 설정
      await _ttsService.setLanguage('zh-CN');
      // 텍스트 읽기
      await _ttsService.speak(text);
    } catch (e) {
      debugPrint('TTS 실행 중 오류 발생: $e');
    }
  }

  // TTS 중지
  Future<void> stopSpeaking() async {
    await _ttsService.stop();
  }

  // 플래시카드 단어 목록 추출
  Set<String> extractFlashcardWords(List<FlashCard>? flashCards) {
    final Set<String> flashcardWords = {};
    if (flashCards != null && flashCards.isNotEmpty) {
      for (final card in flashCards) {
        flashcardWords.add(card.front);
      }
    }
    return flashcardWords;
  }

  // 사전 검색
  Future<DictionaryEntry?> lookupWord(String word) async {
    // 사전 서비스에서 단어 검색
    final entry = _dictionaryService.lookupWord(word);

    if (entry == null) {
      // 사전에 없는 단어일 경우 Papago API로 검색 시도
      debugPrint('사전에 없는 단어, Papago API로 검색 시도: $word');
      return await _dictionaryService.lookupWordWithFallback(word);
    }

    return entry;
  }

  /// 문자열을 TextProcessingMode로 변환
  TextProcessingMode _getTextProcessingMode(String mode) {
    return mode == 'professionalReading'
        ? TextProcessingMode.professionalReading
        : TextProcessingMode.languageLearning;
  }

  Future<ProcessedText> processText(String originalText, String translatedText,
      TextProcessingMode textProcessingMode) async {
    try {
      // 텍스트 처리
      ProcessedText processedText =
          await _ocrService.processText(originalText, textProcessingMode);

      // 번역 텍스트가 있는 경우 설정
      if (translatedText.isNotEmpty &&
          processedText.fullTranslatedText == null) {
        processedText =
            processedText.copyWith(fullTranslatedText: translatedText);
      }

      return processedText;
    } catch (e) {
      debugPrint('Error processing text: $e');
      // 오류 발생 시 기본 ProcessedText 객체 반환
      return ProcessedText(
        fullOriginalText: originalText,
        fullTranslatedText: translatedText,
      );
    }
  }
}
