import 'dart:io';
import 'package:flutter/material.dart';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import '../services/page_service.dart';
import '../services/enhanced_ocr_service.dart';
import '../services/tts_service.dart';
import '../services/dictionary/dictionary_service.dart';
import '../models/dictionary_entry.dart';
import '../models/text_segment.dart';
import '../models/flash_card.dart';
import 'package:flutter/foundation.dart'; // kDebugMode 사용
import '../services/unified_cache_service.dart';

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
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  
  // 캐시 크기 제한
  static const int _maxCacheSize = 50;
  // 캐시 유효 기간
  static const Duration _cacheValidity = Duration(minutes: 30);

  PageContentService._internal() {
    _initTts();
  }

  // ProcessedText 캐시 메서드들 (UnifiedCacheService에 위임)
  Future<bool> hasProcessedText(String pageId) async {
    final processedText = await _cacheService.getProcessedText(pageId);
    return processedText != null;
  }

  Future<ProcessedText?> getProcessedText(String pageId) async {
    try {
      // 캐시 서비스에서 조회
      return await _cacheService.getProcessedText(pageId);
    } catch (e) {
      debugPrint('처리된 텍스트 조회 중 오류: $e');
      return null;
    }
  }

  Future<void> setProcessedText(String pageId, ProcessedText processedText) async {
    try {
      debugPrint('페이지 ID $pageId의 ProcessedText 캐시 업데이트: '
          'showFullText=${processedText.showFullText}, '
          'showPinyin=${processedText.showPinyin}, '
          'showTranslation=${processedText.showTranslation}');
      
      // 캐시 서비스에 저장
      await _cacheService.setProcessedText(pageId, processedText);
    } catch (e) {
      debugPrint('ProcessedText 캐싱 중 오류: $e');
    }
  }

  // 특정 페이지의 캐시 제거
  Future<void> removeProcessedText(String pageId) async {
    try {
      await _cacheService.removeProcessedText(pageId);
    } catch (e) {
      debugPrint('ProcessedText 캐시 제거 중 오류: $e');
    }
  }

  // 모든 캐시 초기화
  Future<void> clearProcessedTextCache() async {
    try {
      _cacheService.clearCache();
    } catch (e) {
      debugPrint('전체 캐시 초기화 중 오류: $e');
    }
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
        // 메모리 캐시 확인
        if (await hasProcessedText(pageId)) {
          debugPrint('메모리 캐시에서 처리된 텍스트 로드: 페이지 ID=$pageId');
          return await getProcessedText(pageId);
        }
        
        // UnifiedCacheService를 통한 캐시 확인
        try {
          final cachedProcessedText = await _pageService.getCachedProcessedText(
            pageId,
            "languageLearning", // 항상 languageLearning 모드 사용
          );

          if (cachedProcessedText != null) {
            debugPrint('캐시에서 로드된 처리 텍스트 타입: ${cachedProcessedText.runtimeType}');
            
            if (cachedProcessedText is ProcessedText) {
              // 이미 ProcessedText 객체인 경우
              await setProcessedText(pageId, cachedProcessedText);
              debugPrint('캐시에서 처리된 텍스트 로드 성공: 페이지 ID=$pageId');
              return cachedProcessedText; // 캐시된 텍스트가 있으므로 여기서 바로 반환
            } else if (cachedProcessedText is Map<String, dynamic>) {
              // Map 형태로 저장된 경우 변환 시도
              try {
                final convertedText = ProcessedText.fromJson(cachedProcessedText);
                await setProcessedText(pageId, convertedText);
                debugPrint('캐시에서 Map으로 로드된 텍스트를 ProcessedText로 변환 성공: 페이지 ID=$pageId');
                return convertedText; // 캐시된 텍스트가 있으므로 여기서 바로 반환
              } catch (e) {
                debugPrint('캐시된 Map 데이터를 ProcessedText로 변환 중 오류: $e');
                await removeProcessedText(pageId); // 오류 발생 시 잘못된 캐시 제거
              }
            }
          }
        } catch (e) {
          debugPrint('캐시된 처리 텍스트 로드 중 오류: $e');
          await removeProcessedText(pageId); // 오류 발생 시 캐시 제거
        }

        debugPrint('캐시된 처리 텍스트 없음 또는 오류 발생: 페이지 ID=$pageId');
      }

      // 캐시된 텍스트 확인
      final originalText = page.originalText;
      final translatedText = page.translatedText ?? ''; // null인 경우 빈 문자열로 처리

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
          // 메모리 캐시에 저장
          await setProcessedText(pageId, processedText);
          
          // UnifiedCacheService를 통한 영구 캐싱
          await _pageService.cacheProcessedText(
            pageId,
            processedText,
            "languageLearning",
          );
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
          // 메모리 캐시에 저장
          await setProcessedText(pageId, processedText);
          
          // UnifiedCacheService를 통한 영구 캐싱
          await _pageService.cacheProcessedText(
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

  // 페이지 캐시 업데이트 (메모리 + UnifiedCacheService)
  Future<void> updatePageCache(
    String pageId,
    ProcessedText processedText,
    String textProcessingMode,
  ) async {
    try {
      // 메모리 캐시 업데이트
      await setProcessedText(pageId, processedText);
      
      // UnifiedCacheService를 통한 영구 캐싱
      await _pageService.cacheProcessedText(
        pageId,
        processedText,
        textProcessingMode,
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

  // TTS 서비스 반환 메서드 추가
  TtsService getTtsService() {
    return _ttsService;
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
    try {
      // 사전 서비스에서 단어 검색
      final result = await _dictionaryService.lookupWord(word);

      // 결과에서 entry 추출하여 반환
      if (result['success'] == true && result['entry'] != null) {
        return result['entry'] as DictionaryEntry;
      }
      return null;
    } catch (e) {
      debugPrint('단어 검색 중 오류 발생: $e');
      return null;
    }
  }

  Future<ProcessedText> processText(String originalText, String translatedText,
      String textProcessingMode) async {
    
      // 입력값 로깅
      debugPrint('PageContentService.processText 호출:');
      debugPrint(' - 원본 텍스트: ${originalText.length}자');
      debugPrint(' - 번역 텍스트: ${translatedText.length}자');
      debugPrint(' - 모드: $textProcessingMode');
      
      // 특수 처리 중 문자열인 경우 OCR 처리 없이 기본 객체 반환
      if (originalText == '___PROCESSING___') {
        debugPrint('PageContentService: 특수 처리 중 문자열 감지, OCR 처리 생략');
        return ProcessedText(
          fullOriginalText: originalText,
          fullTranslatedText: '',
          segments: [], // 빈 세그먼트 목록 제공
          showFullText: false,
          showPinyin: true,
          showTranslation: true,
        );
      }
      
      try {
      // 텍스트 처리
      ProcessedText processedText =
          await _ocrService.processText(originalText, textProcessingMode);

      // 번역 텍스트가 있는 경우 설정
      if (translatedText.isNotEmpty &&
          processedText.fullTranslatedText == null) {
        debugPrint('PageContentService: 번역 텍스트 설정 (전달받은 값 사용)');
        processedText =
            processedText.copyWith(fullTranslatedText: translatedText);
      } else if (processedText.fullTranslatedText != null) {
        debugPrint('PageContentService: OCR 서비스에서 이미 번역 텍스트 제공됨 (${processedText.fullTranslatedText!.length}자)');
      } else {
        debugPrint('PageContentService: 번역 텍스트 없음 (null)');
      }

      // 메소드 종료 시 결과 요약
      final hasSegments = processedText.segments != null && processedText.segments!.isNotEmpty;
      debugPrint('PageContentService.processText 완료:');
      debugPrint(' - 원본 텍스트: ${processedText.fullOriginalText.length}자');
      debugPrint(' - 번역 텍스트: ${processedText.fullTranslatedText?.length ?? 0}자');
      debugPrint(' - 세그먼트: ${hasSegments ? processedText.segments!.length : 0}개');

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

  // 프로세스된 텍스트 업데이트
  void updateProcessedText(String pageId, ProcessedText processedText) {
    // 기존 setProcessedText 메서드를 사용하여 업데이트
    setProcessedText(pageId, processedText);
    
    // 영구 캐시에도 저장 (비동기로 처리)
    _pageService.cacheProcessedText(
      pageId,
      processedText,
      "languageLearning", // 항상 languageLearning 모드 사용
    ).catchError((error) {
      debugPrint('페이지 $pageId의 ProcessedText 영구 캐시 업데이트 중 오류: $error');
    });
  }
}
