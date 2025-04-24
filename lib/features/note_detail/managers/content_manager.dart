import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_segment.dart';
import '../../../core/models/flash_card.dart';
import '../../../core/models/dictionary.dart';
import '../../../core/models/note.dart';
import '../../../core/services/content/page_service.dart';
import '../../../core/services/content/note_service.dart';
import '../../../core/services/media/image_service.dart';
import '../../../core/services/text_processing/enhanced_ocr_service.dart';
import '../../../core/services/media/tts_service.dart';
import '../../../core/services/text_processing/translation_service.dart';
import '../../../core/services/dictionary/dictionary_service.dart';
import '../../../core/services/text_processing/pinyin_creation_service.dart';
import '../../../core/services/storage/unified_cache_service.dart';
import '../../../core/services/workflow/text_processing_workflow.dart';
import '../../../core/services/common/usage_limit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

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
  
  // 추가 서비스 (NoteService에서 이관된 기능을 위해 필요)
  late final NoteService _noteService = NoteService();
  late final ImageService _imageService = ImageService();
  late final UsageLimitService _usageLimitService = UsageLimitService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  ContentManager._internal() {
    debugPrint('🤫 ContentManager: 내부 생성자(_internal) 호출됨 - 서비스 초기화 지연됨');
    // _initTts(); // TTS 초기화는 필요 시 별도 호출 또는 _ttsService 접근 시 자동 초기화
  }

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
      
      // 임시 노트 객체 생성 (TextProcessingWorkflow 호출용)
      final note = createTempNote(originalText, translatedText);
      
      // TextProcessingWorkflow의 processText 메서드 호출 (수정됨)
      ProcessedText processedText = await _textProcessingWorkflow.processText(
        text: originalText,
        note: note,
        pageId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      );

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
  
  // 임시 노트 객체 생성 (processText에서 사용)
  Note createTempNote(String originalText, String translatedText) {
    return Note(
      id: null,
      userId: '',
      originalText: originalText,
      translatedText: translatedText,
      extractedText: originalText,
      sourceLanguage: 'zh-CN', // 기본값
      targetLanguage: 'ko',     // 기본값
    );
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

  // 텍스트 표시 모드 업데이트 - 통합 버전
  Future<ProcessedText?> updateTextDisplayMode({
    required String pageId,
    bool? showFullText,
    bool? showPinyin,
    bool? showTranslation,
  }) async {
    if (!(await hasProcessedText(pageId))) return null;
    
    final processedText = await getProcessedText(pageId);
    if (processedText == null) return null;
    
    // null이 아닌 값만 업데이트
    final updatedProcessedText = processedText.copyWith(
      showFullText: showFullText ?? processedText.showFullText,
      showPinyin: showPinyin ?? processedText.showPinyin,
      showTranslation: showTranslation ?? processedText.showTranslation,
      showFullTextModified: showFullText != null ? true : processedText.showFullTextModified,
    );
    
    // 업데이트된 텍스트 저장
    await setProcessedText(pageId, updatedProcessedText);
    
    // 영구 캐시에도 저장
    await updatePageCache(
      pageId,
      updatedProcessedText,
      "languageLearning",
    );
    
    return updatedProcessedText;
  }
  
  // 표시 모드 토글 (통합 메서드)
  Future<ProcessedText?> toggleDisplayMode(String pageId) async {
    if (!(await hasProcessedText(pageId))) return null;
    
    final processedText = await getProcessedText(pageId);
    if (processedText == null) return null;
    
    // 현재 모드
    final bool currentIsFullMode = processedText.showFullText;
    // 새 모드 (전환)
    final bool newIsFullMode = !currentIsFullMode;
    
    debugPrint('뷰 모드 전환: ${currentIsFullMode ? "전체" : "세그먼트"} -> ${newIsFullMode ? "전체" : "세그먼트"}');
    
    // 현재 ProcessedText 복제
    ProcessedText updatedText = processedText.toggleDisplayMode();
    
    // 필요한 경우 추가 처리 (전체 텍스트 번역 또는 세그먼트 생성)
    if (newIsFullMode && 
        (updatedText.fullTranslatedText == null || updatedText.fullTranslatedText!.isEmpty)) {
      // 전체 번역 수행
      try {
        final fullTranslatedText = await _translationService.translateText(
          updatedText.fullOriginalText,
          sourceLanguage: 'zh-CN',
          targetLanguage: 'ko'
        );
        // 번역 결과 업데이트
        updatedText = updatedText.copyWith(fullTranslatedText: fullTranslatedText);
      } catch (e) {
        debugPrint('전체 번역 중 오류 발생: $e');
      }
    } 
    else if (!newIsFullMode && 
             (updatedText.segments == null || updatedText.segments!.isEmpty)) {
      // 세그먼트 처리 시작
      try {
        final processedSegments = await _textProcessingWorkflow.processText(
          text: updatedText.fullOriginalText,
          note: Note(
            id: null,
            userId: '',
            originalText: updatedText.fullOriginalText,
            translatedText: updatedText.fullTranslatedText ?? '',
            sourceLanguage: 'zh-CN',
            targetLanguage: 'ko',
            extractedText: updatedText.fullOriginalText,
          ),
          pageId: pageId,
        );
        
        if (processedSegments.segments != null && 
            processedSegments.segments!.isNotEmpty) {
          updatedText = updatedText.copyWith(segments: processedSegments.segments);
        }
      } catch (e) {
        debugPrint('세그먼트 처리 중 오류 발생: $e');
      }
    }
    
    // 업데이트된 텍스트 저장
    await setProcessedText(pageId, updatedText);
    
    // 영구 캐시에도 저장
    await updatePageCache(
      pageId,
      updatedText,
      "languageLearning",
    );
    
    return updatedText;
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

  // ===== NoteService에서 이관된 오케스트레이션 기능 =====
  
  /// 여러 이미지로 노트 생성 (ImagePickerBottomSheet에서 사용)
  Future<Map<String, dynamic>> createNoteWithMultipleImages({
    required List<File> imageFiles,
    bool waitForFirstPageProcessing = false,
  }) async {
    try {
      if (imageFiles.isEmpty) {
        return {
          'success': false,
          'message': '이미지 파일이 없습니다',
        };
      }

      // 현재 사용자 확인
      final user = _auth.currentUser;
      if (user == null) {
        return {
          'success': false,
          'message': '로그인이 필요합니다',
        };
      }
      
      // 기본 노트 생성 (NoteService 사용)
      final noteTitle = await _generateSequentialNoteTitle();
      
      // 노트 객체 생성 (NoteService 사용)
      final note = await _noteService.createNote(noteTitle, null);
      final noteId = note.id!;
      
      // 백그라운드 처리 상태 설정
      await _setBackgroundProcessingState(noteId, true);
      
      // 노트 메타데이터 업데이트 (이미지 개수 등)
      await _firestore.collection('notes').doc(noteId).update({
        'imageCount': imageFiles.length,
        'isProcessingBackground': true,
      });
      
      // 첫 번째 이미지 즉시 처리
      if (imageFiles.isNotEmpty) {
        await _processImageAndCreatePage(
          noteId, 
          imageFiles[0],
          shouldProcess: waitForFirstPageProcessing,
        );
        
        // 나머지 이미지는 백그라운드에서 처리
        if (imageFiles.length > 1) {
          _processRemainingImagesInBackground(noteId, imageFiles.sublist(1));
        }
      }

      return {
        'success': true,
        'noteId': noteId,
        'imageCount': imageFiles.length,
      };
    } catch (e) {
      debugPrint('여러 이미지로 노트 생성 중 오류 발생: $e');
      return {
        'success': false,
        'message': '노트 생성 중 오류가 발생했습니다: $e',
      };
    }
  }
  
  /// 순차적인 노트 제목 생성 ('노트 1', '노트 2', ...)
  Future<String> _generateSequentialNoteTitle() async {
    try {
      // 현재 사용자의 노트 수 가져오기
      final user = _auth.currentUser;
      if (user == null) {
        return '노트 1'; // 기본값
      }
      
      // 사용자의 노트 수 확인
      final snapshot = await _firestore
          .collection('notes')
          .where('userId', isEqualTo: user.uid)
          .count()
          .get();
      
      final noteCount = snapshot.count ?? 0; // null 체크 추가
      
      // 다음 번호로 노트 제목 생성
      return '노트 ${noteCount + 1}';
    } catch (e) {
      debugPrint('순차적 노트 제목 생성 중 오류: $e');
      // 오류 발생 시 기본값 반환
      return '노트 1';
    }
  }
  
  /// 백그라운드 처리 상태 설정
  Future<void> _setBackgroundProcessingState(String noteId, bool isProcessing) async {
    try {
      // 1. SharedPreferences에 상태 저장 (로컬 UI 업데이트용)
      final prefs = await SharedPreferences.getInstance();
      final key = 'processing_note_$noteId';
      await prefs.setBool(key, isProcessing);

      // 2. Firestore 노트 문서에도 상태 저장 (영구적)
      await _firestore.collection('notes').doc(noteId).update({
        'isProcessingBackground': isProcessing,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('백그라운드 처리 상태 설정: $noteId, 처리 중: $isProcessing');
    } catch (e) {
      debugPrint('백그라운드 처리 상태 설정 중 오류 발생: $e');
    }
  }
  
  /// 나머지 이미지 백그라운드 처리
  Future<void> _processRemainingImagesInBackground(String noteId, List<File> imageFiles) async {
    try {
      // 각 이미지에 대해 순차적으로 페이지 생성
      for (int i = 0; i < imageFiles.length; i++) {
        final pageNumber = i + 2; // 첫 번째 이미지는 이미 처리됨
        
        await _processImageAndCreatePage(
          noteId, 
          imageFiles[i],
          pageNumber: pageNumber,
        );
        
        // 처리 진행 상황 업데이트
        await _updateProcessingProgress(noteId, pageNumber, imageFiles.length + 1);
      }
      
      // 모든 처리 완료 후 상태 업데이트
      await _completeProcessing(noteId);
    } catch (e) {
      debugPrint('이미지 백그라운드 처리 중 오류 발생: $e');
      // 오류가 발생해도 처리 완료 표시
      await _completeProcessing(noteId);
    }
  }
  
  /// 이미지 처리 및 페이지 생성
  Future<Map<String, dynamic>> _processImageAndCreatePage(
    String noteId, 
    File imageFile, 
    {int pageNumber = 1, String? pageId, String? targetLanguage, bool shouldProcess = true, bool skipOcrUsageCount = false}
  ) async {
    try {
      // 1. 이미지 업로드
      String imageUrl = '';
      try {
        imageUrl = await _imageService.uploadImage(imageFile);
        if (imageUrl.isEmpty) {
          debugPrint('이미지 업로드 결과가 비어있습니다 - 기본 경로 사용');
          imageUrl = 'images/fallback_image.jpg';
        }
      } catch (uploadError) {
        debugPrint('이미지 업로드 중 오류: $uploadError - 기본 경로 사용');
        imageUrl = 'images/fallback_image.jpg';
      }

      // 2. OCR 및 번역 처리
      String extractedText = '';
      String translatedText = '';
      
      if (shouldProcess) {
        // OCR로 텍스트 추출
        extractedText = await _ocrService.extractText(imageFile, skipUsageCount: skipOcrUsageCount);
        
        // 텍스트 번역
        if (extractedText.isNotEmpty) {
          translatedText = await _translationService.translateText(
            extractedText,
            targetLanguage: targetLanguage ?? 'ko',
          );
        }
      } else {
        // 처리하지 않는 경우 특수 마커 사용
        extractedText = '___PROCESSING___';
        translatedText = '';
      }

      // 3. 페이지 생성
      final page = await _pageService.createPage(
        noteId: noteId,
        originalText: extractedText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageFile: imageFile,
      );

      // 4. 첫 페이지인 경우 노트 썸네일 업데이트
      if (pageNumber == 1) {
        await _updateNoteFirstPageInfo(noteId, imageUrl, extractedText, translatedText);
      }

      // 5. 결과 반환
      return {
        'success': true,
        'imageUrl': imageUrl,
        'extractedText': extractedText,
        'translatedText': translatedText,
        'pageId': page.id,
      };
    } catch (e) {
      debugPrint('이미지 처리 및 페이지 생성 중 오류 발생: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  /// 처리 진행 상황 업데이트
  Future<void> _updateProcessingProgress(String noteId, int processedCount, int totalCount) async {
    try {
      // 로컬 상태 저장 (SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('updated_page_count_$noteId', processedCount);
      
      // Firestore 업데이트 (매 페이지마다 하면 비효율적이므로 50% 간격으로만 업데이트)
      if (processedCount == totalCount || processedCount % max(1, (totalCount ~/ 2)) == 0) {
        await _firestore.collection('notes').doc(noteId).update({
          'processedPageCount': processedCount,
          'totalPageCount': totalCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('처리 진행 상황 업데이트 중 오류: $e');
    }
  }
  
  /// 처리 완료 표시
  Future<void> _completeProcessing(String noteId) async {
    try {
      // 로컬 상태 업데이트
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('processing_note_$noteId');
      
      // Firestore 업데이트
      await _firestore.collection('notes').doc(noteId).update({
        'isProcessingBackground': false,
        'processingCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('노트 $noteId의 백그라운드 처리 완료');
    } catch (e) {
      debugPrint('처리 완료 표시 중 오류: $e');
    }
  }
  
  /// 첫 페이지 정보로 노트 업데이트
  Future<void> _updateNoteFirstPageInfo(String noteId, String imageUrl, String extractedText, String translatedText) async {
    try {
      final noteDoc = await _firestore.collection('notes').doc(noteId).get();
      if (!noteDoc.exists) return;
      
      // 필요한 필드만 선택적으로 업데이트
      final Map<String, dynamic> updateData = {
        'updatedAt': DateTime.now(),
      };
      
      if (extractedText != '___PROCESSING___') {
        updateData['extractedText'] = extractedText;
      }
      
      if (translatedText.isNotEmpty) {
        updateData['translatedText'] = translatedText;
      }
      
      // 이미지 URL 업데이트
      updateData['imageUrl'] = imageUrl;
      
      // Firestore 업데이트
      await _firestore.collection('notes').doc(noteId).update(updateData);
      await _cacheService.removeCachedNote(noteId); // 캐시 갱신을 위해 제거
    } catch (e) {
      debugPrint('노트 첫 페이지 정보 업데이트 중 오류: $e');
    }
  }
  
  /// 백그라운드 처리 상태 확인
  Future<bool> getBackgroundProcessingStatus(String noteId) async {
    try {
      // 1. 메모리 & 로컬 저장소 먼저 확인 (더 빠름)
      final prefs = await SharedPreferences.getInstance();
      final key = 'processing_note_$noteId';
      final localProcessing = prefs.getBool(key) ?? false;
      
      if (localProcessing) {
        return true;
      }
      
      // 2. Firestore에서 상태 확인
      final docSnapshot = await _firestore.collection('notes').doc(noteId).get();
      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>?;
        final isProcessing = data?['isProcessingBackground'] as bool? ?? false;
        final isCompleted = data?['processingCompleted'] as bool? ?? false;
        
        // 처리 중이면서 완료되지 않은 경우에만 true
        return isProcessing && !isCompleted;
      }
      
      return false;
    } catch (e) {
      debugPrint('백그라운드 처리 상태 확인 중 오류 발생: $e');
      return false;
    }
  }
}
