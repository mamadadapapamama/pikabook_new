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
  
  // 페이지 ID를 키로 사용하여 ProcessedText 객체 캐싱 (메모리 캐시)
  final Map<String, ProcessedText> _processedTextCache = {};
  // 캐시 타임스탬프 관리
  final Map<String, DateTime> _cacheTimestamps = {};
  // 캐시 크기 제한
  static const int _maxCacheSize = 50;
  // 캐시 유효 기간
  static const Duration _cacheValidity = Duration(minutes: 30);

  PageContentService._internal() {
    _initTts();
  }

  // ProcessedText 캐시 메서드들 (메모리 캐시만 관리)
  bool hasProcessedText(String pageId) {
    return _processedTextCache.containsKey(pageId);
  }

  ProcessedText? getProcessedText(String pageId) {
    if (_processedTextCache.containsKey(pageId)) {
      // 캐시 타임스탬프 업데이트
      _cacheTimestamps[pageId] = DateTime.now();
      return _processedTextCache[pageId];
    }
    return null;
  }

  void setProcessedText(String pageId, ProcessedText processedText) {
    debugPrint('페이지 ID $pageId의 ProcessedText 메모리 캐시 업데이트: '
        'showFullText=${processedText.showFullText}, '
        'showPinyin=${processedText.showPinyin}, '
        'showTranslation=${processedText.showTranslation}');
    
    _processedTextCache[pageId] = processedText;
    _cacheTimestamps[pageId] = DateTime.now();
    
    // 캐시 크기 확인 및 정리
    _cleanupCacheIfNeeded();
  }
  
  // 캐시 크기가 제한을 초과하면 오래된 항목 제거
  void _cleanupCacheIfNeeded() {
    if (_processedTextCache.length > _maxCacheSize) {
      // 캐시 정리 로그
      debugPrint('ProcessedText 캐시 정리 시작: ${_processedTextCache.length}개 > $_maxCacheSize개');
      
      // 타임스탬프 기준으로 정렬된 키 목록 가져오기
      final sortedKeys = _cacheTimestamps.keys.toList()
        ..sort((a, b) {
          final timeA = _cacheTimestamps[a] ?? DateTime.now();
          final timeB = _cacheTimestamps[b] ?? DateTime.now();
          return timeA.compareTo(timeB);
        });
      
      // 제거할 항목 수 계산
      final itemsToRemove = _processedTextCache.length - _maxCacheSize;
      
      // 가장 오래된 항목부터 제거
      for (int i = 0; i < itemsToRemove && i < sortedKeys.length; i++) {
        final key = sortedKeys[i];
        _processedTextCache.remove(key);
        _cacheTimestamps.remove(key);
      }
      
      debugPrint('ProcessedText 캐시 정리 완료: $itemsToRemove개 항목 제거됨');
    }
  }
  
  // 오래된 캐시 항목 정리 (주기적으로 호출)
  void cleanupExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    // 만료된 캐시 항목 찾기
    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheValidity) {
        expiredKeys.add(entry.key);
      }
    }
    
    // 만료된 항목 제거
    if (expiredKeys.isNotEmpty) {
      debugPrint('만료된 ProcessedText 캐시 정리: ${expiredKeys.length}개 항목');
      
      for (final key in expiredKeys) {
        _processedTextCache.remove(key);
        _cacheTimestamps.remove(key);
      }
    }
  }

  // 특정 페이지의 캐시 제거
  void removeProcessedText(String pageId) {
    _processedTextCache.remove(pageId);
    _cacheTimestamps.remove(pageId);
  }

  // 모든 캐시 초기화
  void clearProcessedTextCache() {
    _processedTextCache.clear();
    _cacheTimestamps.clear();
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
        if (_processedTextCache.containsKey(pageId)) {
          debugPrint('메모리 캐시에서 처리된 텍스트 로드: 페이지 ID=$pageId');
          return _processedTextCache[pageId];
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
              _processedTextCache[pageId] = cachedProcessedText;
              debugPrint('캐시에서 처리된 텍스트 로드 성공: 페이지 ID=$pageId');
              return cachedProcessedText;
            } else if (cachedProcessedText is Map<String, dynamic>) {
              // Map 형태로 저장된 경우 변환 시도
              try {
                final convertedText = ProcessedText.fromJson(cachedProcessedText);
                _processedTextCache[pageId] = convertedText;
                debugPrint('캐시에서 Map으로 로드된 텍스트를 ProcessedText로 변환 성공: 페이지 ID=$pageId');
                return convertedText;
              } catch (e) {
                debugPrint('캐시된 Map 데이터를 ProcessedText로 변환 중 오류: $e');
                removeProcessedText(pageId); // 오류 발생 시 잘못된 캐시 제거
              }
            }
          }
        } catch (e) {
          debugPrint('캐시된 처리 텍스트 로드 중 오류: $e');
          removeProcessedText(pageId); // 오류 발생 시 캐시 제거
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
          _processedTextCache[pageId] = processedText;
          
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
          _processedTextCache[pageId] = processedText;
          
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
      setProcessedText(pageId, processedText);
      
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
      final fallbackResult = await _dictionaryService.lookupWordWithFallback(word);
      
      // 결과에서 entry 추출하여 반환
      if (fallbackResult['success'] == true && fallbackResult['entry'] != null) {
        return fallbackResult['entry'];
      }
      return null;
    }

    return entry;
  }

  Future<ProcessedText> processText(String originalText, String translatedText,
      String textProcessingMode) async {
    
      // 입력값 로깅
      debugPrint('PageContentService.processText 호출:');
      debugPrint(' - 원본 텍스트: ${originalText.length}자');
      debugPrint(' - 번역 텍스트: ${translatedText.length}자');
      debugPrint(' - 모드: $textProcessingMode');
      
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
}
