import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_segment.dart';
import '../../../core/models/dictionary.dart';
import '../../../core/services/content/page_service.dart';
import '../../../core/services/text_processing/text_reader_service.dart';
import '../../../core/services/dictionary/backup_dictionary_service.dart';
import '../../../core/services/storage/unified_cache_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/services/text_processing/llm_text_processing.dart';
import '../../../core/services/media/image_service.dart';
import '../../../core/services/text_processing/enhanced_ocr_service.dart';
import '../../../core/services/authentication/user_preferences_service.dart';
import 'dart:async';

/// - 페이지 캐시(processed text, LLM 처리 결과를 저장 조회 삭제)
/// - 사전 검색 (내부/외부 API 통합)
/// - 세그먼트 삭제/수정/처리
/// - 텍스트 읽기를 위한 TextReaderService 연동

class SegmentManager {
  static final SegmentManager _instance = () {
    if (kDebugMode) debugPrint('🏭 SegmentManager: 싱글톤 인스턴스 생성 시작');
    final instance = SegmentManager._internal();
    if (kDebugMode) debugPrint('🏭 SegmentManager: 싱글톤 인스턴스 생성 완료');
    return instance;
  }();
  
  factory SegmentManager() {
    if (kDebugMode) debugPrint('🏭 SegmentManager: 팩토리 생성자 호출됨 (싱글톤 반환)');
    return _instance;
  }
  
  // 필요한 서비스들
  late final PageService _pageService = PageService();
  late final TextReaderService _textReaderService = TextReaderService();
  late final BackupDictionaryService _dictionaryService = BackupDictionaryService();
  late final UnifiedCacheService _cacheService = UnifiedCacheService();
  late final UsageLimitService _usageLimitService = UsageLimitService();
  final UnifiedTextProcessingService _textProcessingService = UnifiedTextProcessingService();
  final ImageService _imageService = ImageService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  
  // getter
  TextReaderService get textReaderService => _textReaderService;
  int? get currentPlayingSegmentIndex => _textReaderService.currentSegmentIndex;
  bool get isPlaying => _textReaderService.isPlaying;

  SegmentManager._internal() {
    _initReader();
  }
  
  // TextReaderService 초기화
  Future<void> _initReader() async {
    try {
      await _textReaderService.init();
      await _textProcessingService.ensureInitialized();
      debugPrint('✅ TextReaderService 초기화 완료');
    } catch (e) {
      debugPrint('❌ TextReaderService 초기화 오류: $e');
    }
  }
  
  // TTS 상태 변경 콜백 설정
  void setOnTtsStateChanged(Function(int?) callback) {
    _textReaderService.setOnPlayingStateChanged(callback);
  }
  
  // TTS 재생 완료 콜백 설정
  void setOnTtsCompleted(Function() callback) {
    _textReaderService.setOnPlayingCompleted(callback);
  }
  
  // TTS 제한 확인
  Future<Map<String, dynamic>> checkTtsLimit() async {
    final remainingCount = await _textReaderService.ttsService.getRemainingTtsCount();
    final usagePercentages = await _usageLimitService.getUsagePercentages();
    
    return {
      'ttsLimitReached': remainingCount <= 0,
      'remainingCount': remainingCount,
      'usagePercentages': usagePercentages,
    };
  }

  // 노트/페이지 변경 시 TTS 플레이어 초기화
  Future<void> resetTtsForNewContext() async {
    try {
      // TTS 플레이어 완전 재설정 (캐시 상태 초기화, 오디오 플레이어 재생성)
      await _textReaderService.ttsService.resetPlayer();
      
      // 캐시 정리 (오래된 파일 삭제)
      _textReaderService.ttsService.cleanupCache();
      
      debugPrint('✅ 페이지/노트 변경으로 TTS 플레이어 재설정 완료');
    } catch (e) {
      debugPrint('❌ TTS 플레이어 재설정 중 오류: $e');
    }
  }

  // TTS 텍스트 재생 (세그먼트 인덱스 포함) - TextReaderService 직접 활용
  Future<bool> playTts(String text, {int? segmentIndex}) async {
    if (text.isEmpty) {
      debugPrint('⚠️ TTS: 재생할 텍스트가 비어있습니다');
      return false;
    }
    
    try {
      // 현재 재생 중인 세그먼트를 다시 클릭한 경우 중지
      if (_textReaderService.currentSegmentIndex == segmentIndex) {
        await stopSpeaking();
        return true;
      }
      
      // 세그먼트 인덱스에 따라 처리
      if (segmentIndex != null) {
        await _textReaderService.readSegment(text, segmentIndex);
      } else {
        await _textReaderService.readText(text);
      }
      
      debugPrint('✅ TTS 재생 시작: ${text.length > 20 ? text.substring(0, 20) + '...' : text}');
      return true;
    } catch (e) {
      debugPrint('❌ TTS 재생 중 오류: $e');
      return false;
    }
  }
  
  // TTS 중지
  Future<void> stopSpeaking() async {
    await _textReaderService.stop();
    debugPrint('🛑 TTS 중지됨');
  }
  
  // ProcessedText의 모든 세그먼트 읽기
  Future<void> readAllSegments(ProcessedText processedText) async {
    await _textReaderService.readAllSegments(processedText);
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
      if (kDebugMode) debugPrint('처리된 텍스트 조회 중 오류: $e');
      return null;
    }
  }
  
  Future<void> setProcessedText(String pageId, ProcessedText processedText) async {
    try {
      await _cacheService.setProcessedText(pageId, processedText);
    } catch (e) {
      if (kDebugMode) debugPrint('ProcessedText 캐싱 중 오류: $e');
    }
  }
  
  Future<void> removeProcessedText(String pageId) async {
    try {
      await _cacheService.removeProcessedText(pageId);
    } catch (e) {
      if (kDebugMode) debugPrint('ProcessedText 캐시 제거 중 오류: $e');
    }
  }
  
  Future<void> clearProcessedTextCache() async {
    try {
      _cacheService.clearCache();
    } catch (e) {
      if (kDebugMode) debugPrint('전체 캐시 초기화 중 오류: $e');
    }
  }
  
  // 사전 검색 (내부 + 외부 API 통합)
  Future<DictionaryEntry?> lookupWord(String word) async {
    if (word.isEmpty) {
      debugPrint('⚠️ 사전: 검색할 단어가 비어있습니다');
      return null;
    }
    
    debugPrint('🔍 사전 검색 시작: "$word"');
    
    try {
      // 1. 먼저 내부 사전에서 검색
      final result = await _dictionaryService.lookupWord(word);
      
      if (result['success'] == true && result['entry'] != null) {
        debugPrint('✅ 내부 사전에서 단어 찾음: $word');
        return result['entry'] as DictionaryEntry;
      }
      
      // 2. 내부 사전에서 찾지 못한 경우, 외부 API로 검색
      debugPrint('⚠️ 내부 사전에서 단어를 찾지 못해 외부 API 사용을 시도합니다');
      final externalResult = await _dictionaryService.lookupWord(word);
      
      if (externalResult['success'] == true && externalResult['entry'] != null) {
        debugPrint('✅ 외부 API에서 단어 찾음: $word');
        return externalResult['entry'] as DictionaryEntry;
      }
      
      // 3. 모든 검색에서 실패한 경우
      debugPrint('❌ 모든 사전에서 단어를 찾지 못했습니다: $word');
      return null;
    } catch (e) {
      debugPrint('❌ 사전 검색 중 오류 발생: $e');
      return null;
    }
  }
  
  // 세그먼트 삭제 처리 (기존 메서드 확장)
  Future<page_model.Page?> deleteSegment({
    required String noteId,
    required page_model.Page page,
    required int segmentIndex,
  }) async {
    if (page.id == null) return null;
    
    debugPrint('🗑️ 세그먼트 삭제 시작: 페이지 ${page.id}의 세그먼트 $segmentIndex');
    
    try {
      // 1. ProcessedText 캐시에서 가져오기
      if (!(await hasProcessedText(page.id!))) {
        debugPrint('⚠️ ProcessedText가 없어 세그먼트를 삭제할 수 없습니다');
        return null;
      }
      
      final processedText = await getProcessedText(page.id!);
      if (processedText == null || 
          processedText.segments == null || 
          segmentIndex >= processedText.segments!.length) {
        debugPrint('⚠️ 유효하지 않은 ProcessedText 또는 세그먼트 인덱스');
        return null;
      }
      
      // 2. 전체 텍스트 모드에서는 세그먼트 삭제 불가
      if (processedText.showFullText) {
        debugPrint('⚠️ 전체 텍스트 모드에서는 세그먼트 삭제가 불가능합니다');
        return null;
      }
      
      // 3. 세그먼트 삭제 및 전체 텍스트 업데이트
      final updatedSegments = List<TextSegment>.from(processedText.segments!);
      updatedSegments.removeAt(segmentIndex);
      
      // 4. 전체 텍스트 다시 조합
      String updatedFullOriginalText = '';
      String updatedFullTranslatedText = '';
      
      for (final segment in updatedSegments) {
        updatedFullOriginalText += segment.originalText;
        if (segment.translatedText != null) {
          updatedFullTranslatedText += segment.translatedText!;
        }
      }
      
      // 5. 업데이트된 ProcessedText 생성
      final updatedProcessedText = processedText.copyWith(
        segments: updatedSegments,
        fullOriginalText: updatedFullOriginalText,
        fullTranslatedText: updatedFullTranslatedText,
        showFullText: processedText.showFullText,
        showPinyin: processedText.showPinyin,
        showTranslation: processedText.showTranslation,
      );
      
      // 6. 캐시 업데이트
      await setProcessedText(page.id!, updatedProcessedText);
      await updatePageCache(page.id!, updatedProcessedText, "languageLearning");
      
      // 7. Firestore DB 업데이트
      try {
        final updatedPageResult = await _pageService.updatePageContent(
          page.id!,
          updatedFullOriginalText,
          updatedFullTranslatedText,
        );
        
        if (updatedPageResult == null) {
          debugPrint('⚠️ Firestore 페이지 업데이트 실패');
          return null;
        }
        
        // 8. 페이지 캐시 업데이트
        await _cacheService.cachePage(noteId, updatedPageResult);
        
        debugPrint('✅ 세그먼트 삭제 후 업데이트 완료');
        return updatedPageResult;
      } catch (e) {
        debugPrint('❌ 세그먼트 삭제 후 페이지 업데이트 중 오류 발생: $e');
        return null;
      }
    } catch (e) {
      debugPrint('❌ 세그먼트 삭제 중 예외 발생: $e');
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
      await setProcessedText(pageId, processedText);
      await _pageService.cacheProcessedText(
        pageId,
        processedText,
        textProcessingMode,
      );
    } catch (e) {
      debugPrint('❌ 페이지 캐시 업데이트 중 오류 발생: $e');
    }
  }
  
  // LLM 기반 세그먼트 처리용 processPageText 메서드
  Future<ProcessedText?> processPageText({
    required page_model.Page page,
    File? imageFile,
  }) async {
    debugPrint('🔄 페이지 텍스트 처리 시작: ${page.id}');
    
    // 페이지 ID가 없는 경우 처리 불가
    if (page.id == null) {
      debugPrint('⚠️ 페이지 ID가 null이어서 처리할 수 없습니다');
      return null;
    }
    
    try {
      // 이미 처리된 텍스트가 있는지 확인 (캐시)
      final cachedText = await getProcessedText(page.id!);
      if (cachedText != null) {
        debugPrint('✅ 캐시에서 이미 처리된 텍스트를 찾았습니다');
        return cachedText;
      }
      
      // 원본 텍스트가 없는 경우 처리 불가
      if (page.originalText.isEmpty) {
        debugPrint('⚠️ 원본 텍스트가 비어있어 처리할 수 없습니다');
        return null;
      }
      
      // LLM 처리
      debugPrint('🔄 LLM 텍스트 처리 시작: ${page.originalText.length}자');
      final llmService = UnifiedTextProcessingService();
      final chineseText = await llmService.processWithLLM(page.originalText);
      
      if (chineseText == null || chineseText.sentences.isEmpty) {
        debugPrint('⚠️ LLM 처리 결과가 비어있습니다');
        return null;
      }
      
      // ProcessedText 생성
      final processedText = ProcessedText(
        fullOriginalText: chineseText.originalText,
        fullTranslatedText: chineseText.sentences.map((s) => s.translation).join('\n'),
        segments: chineseText.sentences.map((s) => TextSegment(
          originalText: s.original,
          translatedText: s.translation,
          pinyin: s.pinyin,
          sourceLanguage: 'zh-CN',
          targetLanguage: 'ko',
        )).toList(),
        showFullText: false,
        showPinyin: true,
        showTranslation: true,
      );
      
      // 캐시에 저장
      await setProcessedText(page.id!, processedText);
      debugPrint('✅ LLM 텍스트 처리 완료 및 캐시 저장');
      
      return processedText;
    } catch (e) {
      debugPrint('❌ 페이지 텍스트 처리 중 오류 발생: $e');
      return null;
    }
  }
  
  // 자원 정리
  void dispose() {
    _textReaderService.dispose();
  }
}

/// 페이지 콘텐츠 관리자: 텍스트 처리와 콘텐츠 관리를 담당합니다.
class PageContentManager {
  final ImageService _imageService = ImageService();
  final UnifiedTextProcessingService _textProcessingService = UnifiedTextProcessingService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();

  // 콘텐츠 상태 관리
  final ValueNotifier<ProcessedText?> processedText = ValueNotifier<ProcessedText?>(null);
  final ValueNotifier<File?> imageFile = ValueNotifier<File?>(null);
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  /// 페이지 콘텐츠 로드
  Future<void> loadPageContent(ProcessedText content) async {
    try {
      isLoading.value = true;
      error.value = null;
      processedText.value = content;
    } catch (e) {
      error.value = '콘텐츠를 로드하는 중 오류가 발생했습니다: $e';
      debugPrint('콘텐츠 로드 중 오류: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// 이미지에서 텍스트 추출 및 처리
  Future<ProcessedText?> processImage(File file) async {
    try {
      isLoading.value = true;
      error.value = null;

      // 이미지 파일 저장
      imageFile.value = file;

      // OCR로 텍스트 추출
      final extractedText = await _ocrService.extractTextFromImage(file);
      if (extractedText.isEmpty) {
        throw Exception('이미지에서 텍스트를 추출할 수 없습니다.');
      }

      // 사용자 설정 가져오기
      final preferences = await _userPreferencesService.getPreferences();
      
      // 텍스트 처리
      final processedText = await _textProcessingService.processWithLLM(
        extractedText,
        sourceLanguage: preferences.sourceLanguage,
        targetLanguage: preferences.targetLanguage,
      );

      return processedText;
    } catch (e) {
      error.value = '이미지 처리 중 오류가 발생했습니다: $e';
      debugPrint('이미지 처리 중 오류: $e');
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  /// 페이지 콘텐츠 업데이트
  Future<void> updatePageContent({
    String? originalText,
    String? translatedText,
    List<TextSegment>? segments,
    TextProcessingMode? mode,
    TextDisplayMode? displayMode,
  }) async {
    if (processedText.value == null) return;

    try {
      isLoading.value = true;
      error.value = null;

      final updatedContent = processedText.value!.copyWith(
        fullOriginalText: originalText,
        fullTranslatedText: translatedText,
        segments: segments,
        mode: mode,
        displayMode: displayMode,
      );

      processedText.value = updatedContent;
    } catch (e) {
      error.value = '콘텐츠를 업데이트하는 중 오류가 발생했습니다: $e';
      debugPrint('콘텐츠 업데이트 중 오류: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// 표시 모드 전환
  void toggleDisplayMode() {
    if (processedText.value == null) return;
    processedText.value = processedText.value!.toggleDisplayMode();
  }

  /// 리소스 정리
  void dispose() {
    processedText.dispose();
    imageFile.dispose();
    isLoading.dispose();
    error.dispose();
  }
}
