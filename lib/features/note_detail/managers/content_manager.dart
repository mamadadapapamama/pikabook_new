import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_segment.dart';
import '../../../core/models/flash_card.dart';
import '../../../core/models/dictionary.dart';
import '../../../core/services/content/page_service.dart';
import '../../../core/services/text_processing/enhanced_ocr_service.dart';
import '../../../core/services/media/tts_service.dart';
import '../../../core/services/text_processing/translation_service.dart';
import '../../../core/services/dictionary/dictionary_service.dart';
import '../../../core/services/dictionary/external_cn_dictionary_service.dart';
import '../../../core/services/text_processing/pinyin_creation_service.dart';
import '../../../core/services/storage/unified_cache_service.dart';
import '../../../core/services/workflow/text_processing_workflow.dart';
import '../../../core/models/note.dart';

/// 콘텐츠 관리자 클래스
/// 페이지 텍스트 및 세그먼트 처리와 관련된 모든 로직을 중앙화합니다.
/// PageContentService와 NoteSegmentManager의 기능을 통합합니다.
/// 

class ContentManager {
  // 싱글톤 패턴 구현
  static final ContentManager _instance = () {
    debugPrint('🏭 ContentManager: 싱글톤 인스턴스 생성 시작');
    final instance = ContentManager._internal();
    debugPrint('🏭 ContentManager: 싱글톤 인스턴스 생성 완료');
    return instance;
  }();
  
  factory ContentManager() {
    debugPrint('🏭 ContentManager: 팩토리 생성자 호출됨 (싱글톤 반환)');
    return _instance;
  }

  // 사용할 서비스들 (late final로 변경)
  late final PageService _pageService = PageService();
  late final EnhancedOcrService _ocrService = EnhancedOcrService();
  late final TtsService _ttsService = TtsService();
  late final DictionaryService _dictionaryService = DictionaryService();
  late final UnifiedCacheService _cacheService = UnifiedCacheService();
  late final TranslationService _translationService = TranslationService();
  late final TextProcessingWorkflow _textProcessingWorkflow = TextProcessingWorkflow();
  late final PinyinCreationService _pinyinService = PinyinCreationService();

  ContentManager._internal() {
    debugPrint('🤫 ContentManager: 내부 생성자(_internal) 호출됨 - 서비스 초기화 지연됨');
    // _initTts(); // TTS 초기화는 필요 시 별도 호출 또는 _ttsService 접근 시 자동 초기화
  }

  // TTS 초기화 (필요 시 외부에서 호출하거나, _ttsService 첫 접근 시 자동 초기화되도록 함)
  // Future<void> initServices() async {
  //   await _ttsService.init(); 
  // }

  // TTS 초기화 - TtsService 접근 시 자동으로 초기화되도록 getter 사용 가능성
  TtsService get ttsService {
    // _ttsService.init(); // 필요하다면 여기서 init 호출
    return _ttsService;
  }

  //
  // ===== PageContentService 기능 =====
  //

  /// 페이지 텍스트 처리 - TextProcessingWorkflow에 위임
  /// 리팩토링: processPageContent 메서드로 중복 로직 통합
  @Deprecated('Use processPageContent instead')
  Future<ProcessedText?> processPageText({
    required page_model.Page page,
    required File? imageFile,
    int recursionDepth = 0, // 재귀 호출 깊이 추적을 위한 매개변수 추가
  }) async {
    // 재귀 호출 깊이 제한 (스택 오버플로우 방지)
    print("ContentManager.processPageText 시작: pageId=${page.id}, recursionDepth=$recursionDepth");
    
    if (recursionDepth > 2) {
      debugPrint('❌ 무한 루프 방지: 최대 재귀 깊이(2) 초과');
      return null;
    }
    
    if (page.originalText.isEmpty && imageFile == null) return null;

    try {
      // TextProcessingWorkflow에 위임
      return await _textProcessingWorkflow.processPageText(
        page: page,
        imageFile: imageFile,
      );
    } catch (e, stack) {
      debugPrint('페이지 텍스트 처리 중 오류 발생: $e');
      debugPrint('스택 트레이스: $stack');
      // 오류 발생 시 기본 텍스트 반환
      return ProcessedText(
        fullOriginalText: page.originalText,
        fullTranslatedText: page.translatedText,
        segments: [],
        showFullText: true,
      );
    }
  }
  
  // ProcessedText 캐시 메서드들
  Future<bool> hasProcessedText(String pageId) async {
    final processedText = await _cacheService.getProcessedText(pageId);
    return processedText != null;
  }

  Future<ProcessedText?> getProcessedText(String pageId) async {
    try {
      return await _cacheService.getProcessedText(pageId);
    } catch (e) {
      debugPrint('처리된 텍스트 조회 중 오류: $e');
      return null;
    }
  }

  Future<void> setProcessedText(String pageId, ProcessedText processedText) async {
    try {
      await _cacheService.setProcessedText(pageId, processedText);
    } catch (e) {
      debugPrint('ProcessedText 캐싱 중 오류: $e');
    }
  }

  Future<void> removeProcessedText(String pageId) async {
    try {
      await _cacheService.removeProcessedText(pageId);
    } catch (e) {
      debugPrint('ProcessedText 캐시 제거 중 오류: $e');
    }
  }

  Future<void> clearProcessedTextCache() async {
    try {
      _cacheService.clearCache();
    } catch (e) {
      debugPrint('전체 캐시 초기화 중 오류: $e');
    }
  }

  // TTS 관련 메서드
  Future<void> speakText(String text) async {
    if (text.isEmpty) return;

    try {
      await _ttsService.setLanguage('zh-CN');
      await _ttsService.speak(text);
    } catch (e) {
      debugPrint('TTS 실행 중 오류 발생: $e');
    }
  }

  Future<void> stopSpeaking() async {
    await _ttsService.stop();
  }

  // 사전 검색
  Future<DictionaryEntry?> lookupWord(String word) async {
    try {
      final result = await _dictionaryService.lookupWord(word);

      if (result['success'] == true && result['entry'] != null) {
        return result['entry'] as DictionaryEntry;
      }
      return null;
    } catch (e) {
      debugPrint('단어 검색 중 오류 발생: $e');
      return null;
    }
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

  // 텍스트 처리
  Future<ProcessedText> processText(String originalText, String translatedText,
      String textProcessingMode) async {
    try {
      // 특수 처리 중 문자열인 경우 OCR 처리 없이 기본 객체 반환
      if (originalText == '___PROCESSING___') {
        return ProcessedText(
          fullOriginalText: originalText,
          fullTranslatedText: '',
          segments: [],
          showFullText: false,
          showPinyin: true,
          showTranslation: true,
        );
      }
      
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
      debugPrint('텍스트 처리 중 오류: $e');
      // 오류 발생 시 기본 ProcessedText 객체 반환
      return ProcessedText(
        fullOriginalText: originalText,
        fullTranslatedText: translatedText,
      );
    }
  }
  
  //
  // ===== NoteSegmentManager 기능 =====
  //

  /// 세그먼트 삭제 처리
  Future<page_model.Page?> deleteSegment({
    required String noteId,
    required page_model.Page page,
    required int segmentIndex,
  }) async {
    if (page.id == null) return null;
    
    debugPrint('세그먼트 삭제 시작: 페이지 ${page.id}의 세그먼트 $segmentIndex');
    
    // 현재 페이지의 processedText 객체 가져오기
    if (!(await hasProcessedText(page.id!))) {
      debugPrint('ProcessedText가 없어 세그먼트를 삭제할 수 없습니다');
      return null;
    }
    
    final processedText = await getProcessedText(page.id!);
    if (processedText == null || 
        processedText.segments == null || 
        segmentIndex >= processedText.segments!.length) {
      debugPrint('유효하지 않은 ProcessedText 또는 세그먼트 인덱스');
      return null;
    }
    
    // 전체 텍스트 모드에서는 세그먼트 삭제가 의미가 없음
    if (processedText.showFullText) {
      debugPrint('전체 텍스트 모드에서는 세그먼트 삭제가 불가능합니다');
      return null;
    }
    
    // 세그먼트 목록에서 해당 인덱스의 세그먼트 제거
    final updatedSegments = List<TextSegment>.from(processedText.segments!);
    final removedSegment = updatedSegments.removeAt(segmentIndex);
    
    // 전체 원문과 번역문 재구성
    String updatedFullOriginalText = '';
    String updatedFullTranslatedText = '';
    
    // 남은 세그먼트들을 결합하여 새로운 전체 텍스트 생성
    for (final segment in updatedSegments) {
      updatedFullOriginalText += segment.originalText;
      if (segment.translatedText != null) {
        updatedFullTranslatedText += segment.translatedText!;
      }
    }
    
    debugPrint('재구성된 전체 텍스트 - 원본 길이: ${updatedFullOriginalText.length}, 번역 길이: ${updatedFullTranslatedText.length}');
    
    // 업데이트된 세그먼트 목록으로 새 ProcessedText 생성
    final updatedProcessedText = processedText.copyWith(
      segments: updatedSegments,
      fullOriginalText: updatedFullOriginalText,
      fullTranslatedText: updatedFullTranslatedText,
      // 현재 표시 모드 유지
      showFullText: processedText.showFullText,
      showPinyin: processedText.showPinyin,
      showTranslation: processedText.showTranslation,
    );
    
    // 메모리 캐시에 ProcessedText 업데이트
    await setProcessedText(page.id!, updatedProcessedText);
    
    // ProcessedText 캐시 업데이트
    await updatePageCache(
      page.id!,
      updatedProcessedText,
      "languageLearning",
    );
    
    // Firestore 업데이트
    try {
      // 페이지 내용 업데이트
      final updatedPageResult = await _pageService.updatePageContent(
        page.id!,
        updatedFullOriginalText,
        updatedFullTranslatedText,
      );
      
      if (updatedPageResult == null) {
        debugPrint('Firestore 페이지 업데이트 실패');
        return null;
      }
      
      // 업데이트된 페이지 객체 캐싱
      await _cacheService.cachePage(noteId, updatedPageResult);
      
      debugPrint('세그먼트 삭제 후 업데이트 완료');
      return updatedPageResult;
    } catch (e) {
      debugPrint('세그먼트 삭제 후 페이지 업데이트 중 오류 발생: $e');
      return null;
    }
  }

  // 텍스트 표시 모드 업데이트
  Future<void> updateTextDisplayMode({
    required String pageId,
    required bool showFullText,
    required bool showPinyin,
    required bool showTranslation,
  }) async {
    if (!(await hasProcessedText(pageId))) return;
    
    final processedText = await getProcessedText(pageId);
    if (processedText == null) return;
    
    final updatedProcessedText = processedText.copyWith(
      showFullText: showFullText,
      showPinyin: showPinyin,
      showTranslation: showTranslation,
    );
    
    await setProcessedText(pageId, updatedProcessedText);
  }

  // 페이지 캐시 업데이트
  Future<void> updatePageCache(
    String pageId,
    ProcessedText processedText,
    String textProcessingMode,
  ) async {
    try {
      // 메모리 캐시 업데이트
      await setProcessedText(pageId, processedText);
      
      // 영구 캐싱
      await _pageService.cacheProcessedText(
        pageId,
        processedText,
        textProcessingMode,
      );
    } catch (e) {
      debugPrint('페이지 캐시 업데이트 중 오류 발생: $e');
    }
  }

  // TextProcessingWorkflow 기능 위임
  Future<ProcessedText?> toggleDisplayModeForPage(String? pageId) async {
    return await _textProcessingWorkflow.toggleDisplayModeForPage(pageId);
  }

  // 병음 토글
  Future<ProcessedText?> togglePinyinForPage(String? pageId) async {
    if (pageId == null) return null;
    
    final processedText = await getProcessedText(pageId);
    if (processedText == null) return null;
    
    // 병음 표시 상태 전환
    final updatedText = processedText.copyWith(
      showPinyin: !processedText.showPinyin,
    );
    
    // 업데이트된 상태 저장
    await setProcessedText(pageId, updatedText);
    
    return updatedText;
  }

  // 번역 토글 
  Future<ProcessedText?> toggleTranslationForPage(String? pageId) async {
    if (pageId == null) return null;
    
    final processedText = await getProcessedText(pageId);
    if (processedText == null) return null;
    
    // 번역 표시 상태 전환
    final updatedText = processedText.copyWith(
      showTranslation: !processedText.showTranslation,
    );
    
    // 업데이트된 상태 저장
    await setProcessedText(pageId, updatedText);
    
    return updatedText;
  }

  // ProcessedText 직접 업데이트 메서드 (page_content_service.dart에서 이전)
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

  // 백그라운드에서 텍스트 캐싱 (UI 차단 방지)
  void _cacheInBackground(String pageId, ProcessedText processedText) {
    Future.microtask(() async {
      try {
        await _pageService.cacheProcessedText(
          pageId,
          processedText,
          "languageLearning",
        );
        debugPrint('✅ 텍스트 처리 결과 백그라운드에서 영구 캐시에 저장 완료: $pageId');
      } catch (e) {
        debugPrint('⚠️ 백그라운드 캐싱 중 오류 (무시됨): $e');
      }
    });
  }

  // ===== 리팩토링: PageManager와 중복 로직 통합 =====
  
  /// 페이지 콘텐츠를 처리하는 통합 메서드
  /// PageManager.loadPageContent와 중복 로직을 이 메서드로 통합
  Future<Map<String, dynamic>> processPageContent({
    required page_model.Page page,
    required File? imageFile,
    required dynamic note,
  }) async {
    // 결과를 담을 맵
    final Map<String, dynamic> result = {
      'imageFile': null,
      'processedText': null,
      'isSuccess': false,
    };
    
    try {
      // 1. 이미지 정보 설정
      if (imageFile != null) {
        result['imageFile'] = imageFile;
      }
      
      // 2. 텍스트 처리
      if (page.id != null) {
        // 캐시에서 ProcessedText 확인
        ProcessedText? processedText;
        
        try {
          processedText = await getProcessedText(page.id!);
          
          // 캐시에 없으면 새로 처리
          if (processedText == null) {
            processedText = await _textProcessingWorkflow.processPageText(
              page: page,
              imageFile: imageFile,
            );
            
            // 처리 결과 캐싱
            if (processedText != null) {
              setProcessedText(page.id!, processedText);
              _cacheInBackground(page.id!, processedText);
            }
          }
        } catch (e) {
          debugPrint('ProcessedText 처리 중 오류: $e');
          // 오류 시 기본 객체 생성
          processedText = ProcessedText(
            fullOriginalText: page.originalText,
            fullTranslatedText: page.translatedText,
            segments: [],
            showFullText: true,
          );
        }
        
        result['processedText'] = processedText;
        result['isSuccess'] = processedText != null;
      }
      
      return result;
    } catch (e) {
      debugPrint('페이지 내용 처리 중 오류: $e');
      result['error'] = e.toString();
      return result;
    }
  }
}
