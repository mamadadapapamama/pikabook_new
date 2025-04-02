import 'package:flutter/material.dart';
import '../models/page.dart' as page_model;
import '../models/text_segment.dart';
import '../services/page_service.dart';
import '../services/page_content_service.dart';
import '../services/unified_cache_service.dart';

/// 노트 세그먼트 관리 클래스 입니다
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
    
    debugPrint('세그먼트 매니저: 페이지 ${page.id}의 세그먼트 $segmentIndex 삭제 시작');
    
    // 현재 페이지의 processedText 객체 가져오기
    if (!_pageContentService.hasProcessedText(page.id!)) {
      debugPrint('세그먼트 매니저: ProcessedText가 없어 세그먼트를 삭제할 수 없습니다');
      return null;
    }
    
    final processedText = _pageContentService.getProcessedText(page.id!);
    if (processedText == null || 
        processedText.segments == null || 
        segmentIndex >= processedText.segments!.length) {
      debugPrint('세그먼트 매니저: 유효하지 않은 ProcessedText 또는 세그먼트 인덱스');
      return null;
    }
    
    // 전체 텍스트 모드에서는 세그먼트 삭제가 의미가 없음
    if (processedText.showFullText) {
      debugPrint('세그먼트 매니저: 전체 텍스트 모드에서는 세그먼트 삭제가 불가능합니다');
      return null;
    }
    
    // 세그먼트 목록에서 해당 인덱스의 세그먼트 제거
    final updatedSegments = List<TextSegment>.from(processedText.segments!);
    final removedSegment = updatedSegments.removeAt(segmentIndex);
    
    debugPrint('세그먼트 매니저: 세그먼트 삭제됨 - 원본: "${removedSegment.originalText}", 번역: "${removedSegment.translatedText}"');
    
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
    
    debugPrint('세그먼트 매니저: 재구성된 전체 텍스트 - 원본 길이: ${updatedFullOriginalText.length}, 번역 길이: ${updatedFullTranslatedText.length}');
    
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
    _pageContentService.setProcessedText(page.id!, updatedProcessedText);
    
    // ProcessedText 캐시 업데이트
    await _pageContentService.updatePageCache(
      page.id!,
      updatedProcessedText,
      "languageLearning", // 언어 학습 모드로 고정
    );
    
    // Firestore 업데이트
    try {
      debugPrint('세그먼트 매니저: Firestore 페이지 내용 업데이트 중...');
      
      // 페이지 내용 업데이트
      final updatedPageResult = await _pageService.updatePageContent(
        page.id!,
        updatedFullOriginalText,
        updatedFullTranslatedText,
      );
      
      if (updatedPageResult == null) {
        debugPrint('세그먼트 매니저: Firestore 페이지 업데이트 실패');
        return null;
      }
      
      // 업데이트된 페이지 객체 캐싱
      await _cacheService.cachePage(noteId, updatedPageResult);
      
      debugPrint('세그먼트 매니저: 세그먼트 삭제 후 Firestore 및 캐시 업데이트 완료');
      return updatedPageResult;
    } catch (e) {
      debugPrint('세그먼트 매니저: 세그먼트 삭제 후 페이지 업데이트 중 오류 발생: $e');
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