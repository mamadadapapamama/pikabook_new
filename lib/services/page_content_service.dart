import 'dart:io';
import 'package:flutter/material.dart';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import '../services/page_service.dart';
import '../services/enhanced_ocr_service.dart';
import '../services/tts_service.dart';
import '../services/dictionary_service.dart';
import '../models/dictionary_entry.dart';
import '../models/text_segment.dart';
import '../models/flash_card.dart';
import 'package:flutter/foundation.dart'; // kDebugMode 사용
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
    debugPrint('페이지 ID $pageId의 ProcessedText 캐시 업데이트: '
        'showFullText=${processedText.showFullText}, '
        'showPinyin=${processedText.showPinyin}, '
        'showTranslation=${processedText.showTranslation}');
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
          "languageLearning", // 항상 languageLearning 모드 사용
        );

        if (cachedProcessedText != null) {
          debugPrint(
              '캐시된 처리 텍스트 사용: 페이지 ID=$pageId, 모드=languageLearning');
          return cachedProcessedText;
        }

        debugPrint(
            '캐시된 처리 텍스트 없음: 페이지 ID=$pageId, 모드=languageLearning');
      }

      // 캐시된 텍스트 확인
      final originalText = page.originalText;
      final translatedText = page.translatedText;

      debugPrint(
          '페이지 텍스트 처리 시작: 페이지 ID=$pageId, 원본 텍스트 ${originalText.length}자, 번역 텍스트 ${translatedText.length}자');

      // 이미지 파일이 있고 텍스트가 없는 경우 OCR 처리
      if (imageFile != null &&
          (originalText.isEmpty || translatedText.isEmpty)) {
        debugPrint('이미지 OCR 처리 시작');
        final processedText = await _ocrService.processImage(
          imageFile,
          "languageLearning", // 항상 languageLearning 모드 사용
        );

        // 처리된 텍스트를 페이지에 캐싱
        if (processedText.fullOriginalText.isNotEmpty && pageId != null) {
          await updatePageCache(pageId, processedText, "languageLearning");
        }

        return processedText;
      }

      // 텍스트 처리
      if (originalText.isNotEmpty) {
        // 항상 languageLearning 모드 사용
        ProcessedText processedText =
            await _ocrService.processText(originalText, "languageLearning");

        // 번역 텍스트가 있는 경우 설정
        if (translatedText.isNotEmpty &&
            processedText.fullTranslatedText == null) {
          processedText =
              processedText.copyWith(fullTranslatedText: translatedText);
        }

        // 페이지 ID가 있는 경우 캐시에 저장
        if (pageId != null) {
          await updatePageCache(
            pageId,
            processedText,
            "languageLearning",
          );
        }

        // 처리된 텍스트 반환
        return processedText;
      }
    } catch (e) {
      debugPrint('페이지 텍스트 처리 중 오류 발생: $e');
    }

    // 오류 발생 시 null 반환
    return null;
  }

  /// 페이지 캐시 업데이트 (메모리 + 디스크)
  /// pageId: 페이지 ID
  /// processedText: 처리된 텍스트 객체
  /// mode: 처리 모드 (예: "languageLearning", "flashcard" 등)
  Future<void> updatePageCache(String pageId, ProcessedText processedText, String mode) async {
    try {
      // 메모리 캐시 업데이트
      setProcessedText(pageId, processedText);
      
      // 텍스트 처리 모드 로깅
      debugPrint('페이지 $pageId의 ProcessedText 캐시 업데이트 중 (모드: $mode)');
      
      // SharedPreferences에 보관할 정보 추출
      final Map<String, dynamic> cacheData = {
        'pageId': pageId,
        'mode': mode,
        'fullOriginalText': processedText.fullOriginalText,
        'fullTranslatedText': processedText.fullTranslatedText,
        'showFullText': processedText.showFullText,
        'showPinyin': processedText.showPinyin,
        'showTranslation': processedText.showTranslation,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      // 세그먼트 목록 포함 (null이 아닌 경우에만)
      if (processedText.segments != null && processedText.segments!.isNotEmpty) {
        cacheData['segmentsCount'] = processedText.segments!.length;
        cacheData['segments'] = processedText.segments!.map((segment) => segment.toJson()).toList();
      }
      
      // SharedPreferences에 사용자 정의 키로 저장
      final prefs = await SharedPreferences.getInstance();
      final key = 'processed_text_${pageId}_${mode}';
      
      // Map을 JSON 문자열로 변환하여 저장
      await prefs.setString(key, jsonEncode(cacheData));
      
      debugPrint('페이지 $pageId의 ProcessedText 캐시 업데이트 완료 (모드: $mode, 세그먼트: ${processedText.segments?.length ?? 0}개)');
    } catch (e) {
      debugPrint('페이지 $pageId의 ProcessedText 캐시 업데이트 중 오류 발생: $e');
    }
  }
  
  /// 페이지 캐시에서 ProcessedText 로드 (메모리 → 디스크 순)
  Future<ProcessedText?> loadProcessedText(String pageId, String mode) async {
    try {
      // 1. 메모리 캐시에서 먼저 확인
      debugPrint('메모리 캐시에서 처리된 텍스트 로드: 페이지 ID=$pageId, 모드=$mode');
      
      if (_processedTextCache.containsKey(pageId)) {
        debugPrint('캐시된 처리 텍스트 사용: 페이지 ID=$pageId, 모드=$mode');
        return _processedTextCache[pageId];
      }
      
      // 2. 메모리에 없으면 디스크(SharedPreferences)에서 로드
      final prefs = await SharedPreferences.getInstance();
      final key = 'processed_text_${pageId}_${mode}';
      
      final jsonStr = prefs.getString(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          // JSON 문자열을 Map으로 변환
          final cacheData = jsonDecode(jsonStr) as Map<String, dynamic>;
          
          // 세그먼트 목록 복원
          List<TextSegment>? segments;
          if (cacheData.containsKey('segments')) {
            segments = (cacheData['segments'] as List)
                .map((segmentJson) => TextSegment.fromJson(segmentJson))
                .toList();
          }
          
          // ProcessedText 객체 생성
          final processedText = ProcessedText(
            fullOriginalText: cacheData['fullOriginalText'] as String? ?? '',
            fullTranslatedText: cacheData['fullTranslatedText'] as String?,
            segments: segments,
            showFullText: cacheData['showFullText'] as bool? ?? false,
            showPinyin: cacheData['showPinyin'] as bool? ?? true,
            showTranslation: cacheData['showTranslation'] as bool? ?? true,
          );
          
          // 메모리 캐시에도 저장
          setProcessedText(pageId, processedText);
          
          debugPrint('디스크 캐시에서 처리된 텍스트 로드 성공: 페이지 ID=$pageId, 모드=$mode, 세그먼트=${segments?.length ?? 0}개');
          return processedText;
        } catch (e) {
          debugPrint('디스크 캐시 데이터 파싱 중 오류 발생: $e');
        }
      }
      
      // 캐시에 없는 경우
      debugPrint('캐시에 처리된 텍스트가 없음: 페이지 ID=$pageId, 모드=$mode');
      return null;
    } catch (e) {
      debugPrint('처리된 텍스트 로드 중 오류 발생: $e');
      return null;
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

  Future<ProcessedText> processText(String originalText, String translatedText,
      String textProcessingMode) async {
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
