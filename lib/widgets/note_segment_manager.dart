import 'package:flutter/material.dart';
import '../models/page.dart' as page_model;
import '../models/text_segment.dart';
import '../models/processed_text.dart';
import '../services/page_service.dart';
import '../services/page_content_service.dart';
import '../services/unified_cache_service.dart';

/// 노트 세그먼트 관리 클래스
/// 페이지 내 세그먼트 처리 관련 기능 제공
class NoteSegmentManager {
  final PageService _pageService = PageService();
  final PageContentService _pageContentService = PageContentService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  
  // 세그먼트 삭제 처리
  Future<page_model.Page?> deleteSegment({
    required String noteId,
    required page_model.Page page,
    required int segmentIndex,
  }) async {
    if (page.id == null) return null;
    
    // 현재 페이지의 processedText 객체 가져오기
    if (!_pageContentService.hasProcessedText(page.id!)) return null;
    
    final processedText = _pageContentService.getProcessedText(page.id!);
    if (processedText == null || 
        processedText.segments == null || 
        segmentIndex >= processedText.segments!.length) {
      return null;
    }
    
    // 세그먼트 목록에서 해당 인덱스의 세그먼트 제거
    final updatedSegments = List<TextSegment>.from(processedText.segments!);
    final removedSegment = updatedSegments.removeAt(segmentIndex);
    
    // 전체 원문에서도 해당 세그먼트 문장 제거
    String updatedFullOriginalText = processedText.fullOriginalText;
    String updatedFullTranslatedText = processedText.fullTranslatedText ?? '';
    
    // 원문에서 해당 세그먼트 문장 제거
    if (removedSegment.originalText.isNotEmpty) {
      updatedFullOriginalText = updatedFullOriginalText.replaceAll(removedSegment.originalText, '');
      // 연속된 공백 제거
      updatedFullOriginalText = updatedFullOriginalText.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    
    // 번역본에서 해당 세그먼트 문장 제거
    if (removedSegment.translatedText != null && removedSegment.translatedText!.isNotEmpty) {
      updatedFullTranslatedText = updatedFullTranslatedText.replaceAll(
          removedSegment.translatedText!, '');
      // 연속된 공백 제거
      updatedFullTranslatedText = updatedFullTranslatedText.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    
    // 업데이트된 세그먼트 목록으로 새 ProcessedText 생성
    final updatedProcessedText = processedText.copyWith(
      segments: updatedSegments,
      fullOriginalText: updatedFullOriginalText,
      fullTranslatedText: updatedFullTranslatedText,
    );
    
    // 업데이트된 ProcessedText 저장
    _pageContentService.setProcessedText(page.id!, updatedProcessedText);
    
    // Firestore 업데이트
    try {
      // 페이지 내용 업데이트
      await _pageService.updatePageContent(
        page.id!,
        updatedFullOriginalText,
        updatedFullTranslatedText,
      );
      
      // 업데이트된 페이지 객체 생성
      final updatedPage = page.copyWith(
        originalText: updatedFullOriginalText,
        translatedText: updatedFullTranslatedText,
        updatedAt: DateTime.now(),
      );
      
      // 캐시 업데이트
      await _cacheService.cachePage(noteId, updatedPage);
      
      debugPrint('세그먼트 삭제 후 Firestore 및 캐시 업데이트 완료');
      return updatedPage;
    } catch (e) {
      debugPrint('세그먼트 삭제 후 페이지 업데이트 중 오류 발생: $e');
      return null;
    }
  }
  
  // 텍스트 표시 모드 업데이트
  void updateTextDisplayMode({
    required String pageId,
    required bool showFullText,
    required bool showPinyin,
    required bool showTranslation,
  }) {
    if (!_pageContentService.hasProcessedText(pageId)) return;
    
    final processedText = _pageContentService.getProcessedText(pageId);
    if (processedText == null) return;
    
    final updatedProcessedText = processedText.copyWith(
      showFullText: showFullText,
    );
    
    _pageContentService.setProcessedText(pageId, updatedProcessedText);
  }
} 