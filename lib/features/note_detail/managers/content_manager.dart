import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  // 필요한 서비스만 남김
  late final PageService _pageService = PageService();
  late final TtsService _ttsService = TtsService();
  late final DictionaryService _dictionaryService = DictionaryService();
  late final UnifiedCacheService _cacheService = UnifiedCacheService();

  SegmentManager._internal();

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
  // TTS 관련 메서드
  Future<void> speakText(String text) async {
    if (text.isEmpty) return;
    try {
      await _ttsService.setLanguage('zh-CN');
      await _ttsService.speak(text);
    } catch (e) {
      if (kDebugMode) debugPrint('TTS 실행 중 오류 발생: $e');
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
      if (kDebugMode) debugPrint('단어 검색 중 오류 발생: $e');
      return null;
    }
  }
  // 세그먼트 삭제 처리
  Future<page_model.Page?> deleteSegment({
    required String noteId,
    required page_model.Page page,
    required int segmentIndex,
  }) async {
    if (page.id == null) return null;
    debugPrint('세그먼트 삭제 시작: 페이지 ${page.id}의 세그먼트 $segmentIndex');
    if (!(await hasProcessedText(page.id!))) {
      debugPrint('ProcessedText가 없어 세그먼트를 삭제할 수 없습니다');
      return null;
    }
    final processedText = await getProcessedText(page.id!);
    if (processedText == null || processedText.segments == null || segmentIndex >= processedText.segments!.length) {
      debugPrint('유효하지 않은 ProcessedText 또는 세그먼트 인덱스');
      return null;
    }
    if (processedText.showFullText) {
      debugPrint('전체 텍스트 모드에서는 세그먼트 삭제가 불가능합니다');
      return null;
    }
    final updatedSegments = List<TextSegment>.from(processedText.segments!);
    updatedSegments.removeAt(segmentIndex);
    String updatedFullOriginalText = '';
    String updatedFullTranslatedText = '';
    for (final segment in updatedSegments) {
      updatedFullOriginalText += segment.originalText;
      if (segment.translatedText != null) {
        updatedFullTranslatedText += segment.translatedText!;
      }
    }
    final updatedProcessedText = processedText.copyWith(
      segments: updatedSegments,
      fullOriginalText: updatedFullOriginalText,
      fullTranslatedText: updatedFullTranslatedText,
      showFullText: processedText.showFullText,
      showPinyin: processedText.showPinyin,
      showTranslation: processedText.showTranslation,
    );
    await setProcessedText(page.id!, updatedProcessedText);
    await updatePageCache(page.id!, updatedProcessedText, "languageLearning");
    try {
      final updatedPageResult = await _pageService.updatePageContent(
        page.id!,
        updatedFullOriginalText,
        updatedFullTranslatedText,
      );
      if (updatedPageResult == null) {
        debugPrint('Firestore 페이지 업데이트 실패');
        return null;
      }
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
      await setProcessedText(pageId, processedText);
      await _pageService.cacheProcessedText(
        pageId,
        processedText,
        textProcessingMode,
      );
    } catch (e) {
      debugPrint('페이지 캐시 업데이트 중 오류 발생: $e');
    }
  }
}
