import 'dart:io';
import '../models/page.dart' as page_model;
import '../services/page_content_service.dart';
import '../models/processed_text.dart';
import '../services/translation_service.dart';
import '../services/enhanced_ocr_service.dart';
import '../services/unified_cache_service.dart';
import 'package:flutter/material.dart';

class NoteDetailTextProcessor {
  final PageContentService _pageContentService = PageContentService();
  final TranslationService _translationService = TranslationService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  
  // 페이지 텍스트 가져오기
  Future<ProcessedText?> getProcessedText(String pageId) async {
    return await _cacheService.getProcessedText(pageId);
  }
  
  // 페이지 텍스트 설정하기
  Future<void> setProcessedText(String pageId, ProcessedText processedText) async {
    await _cacheService.setProcessedText(pageId, processedText);
  }
  
  // 페이지 텍스트 삭제하기
  Future<void> removeProcessedText(String pageId) async {
    await _cacheService.removeProcessedText(pageId);
  }
  
  // 페이지 캐시 업데이트
  Future<void> updatePageCache(String pageId, ProcessedText processedText, String mode) async {
    await _cacheService.cacheProcessedText(pageId, mode, processedText);
  }
  
  // 페이지 텍스트 처리
  Future<ProcessedText?> processPageText({
    required page_model.Page page,
    required File? imageFile
  }) async {
    if (page.id == null) return null;
    
    // 이미 캐싱된 텍스트가 있는지 확인
    ProcessedText? processedText = await getProcessedText(page.id!);
    
    if (processedText != null) {
      return processedText;
    }
    
    // 캐싱된 데이터가 없으면 새로 처리
    processedText = await _pageContentService.processPageText(
      page: page,
      imageFile: imageFile,
    );
    
    if (processedText != null) {
      // 기본 표시 설정 지정
      final updatedProcessedText = processedText.copyWith(
        showFullText: false, // 기본값: 세그먼트 모드
        showPinyin: true, // 병음 표시는 기본적으로 활성화
        showTranslation: true, // 번역은 항상 표시
      );
      
      // 처리된 텍스트 캐싱
      await setProcessedText(page.id!, updatedProcessedText);
      return updatedProcessedText;
    }
    
    return null;
  }
  
  // 번역 데이터 확인 및 로드
  Future<ProcessedText?> checkAndLoadTranslationData(
      ProcessedText processedText, String pageId) async {
    // 현재 전체 텍스트 모드
    final bool isCurrentlyFullMode = processedText.showFullText;
    // 모드 전환 후 (toggleDisplayMode 후)
    final bool willBeFullMode = !isCurrentlyFullMode;
    
    debugPrint('checkAndLoadTranslationData: 현재 모드: ${isCurrentlyFullMode ? "전체" : "세그먼트"}, 전환 모드: ${willBeFullMode ? "전체" : "세그먼트"}');
    
    try {
      // 1. 전체 모드로 전환하는데 전체 번역이 없는 경우
      if (willBeFullMode && 
          (processedText.fullTranslatedText == null || processedText.fullTranslatedText!.isEmpty)) {
        
        debugPrint('전체 번역 모드로 전환하여 번역 시작');
        
        // 전체 번역 수행 (다이얼로그 표시 부분 제거)
        final fullTranslatedText = await _translationService.translateText(
          processedText.fullOriginalText,
          sourceLanguage: 'zh-CN',
          targetLanguage: 'ko'
        );
        
        // 번역 결과 업데이트
        final updatedText = processedText.copyWith(
          fullTranslatedText: fullTranslatedText,
          showFullText: true,
          showFullTextModified: true
        );
        
        // 캐시 및 UI 업데이트
        await setProcessedText(pageId, updatedText);
        
        // 캐시 업데이트
        await updatePageCache(
          pageId,
          updatedText,
          "languageLearning"
        );
        
        debugPrint('전체 번역 완료 및 캐시 업데이트 완료');
        return updatedText;
      } 
      // 2. 세그먼트 모드로 전환하는데 세그먼트가 없는 경우
      else if (!willBeFullMode && 
               (processedText.segments == null || processedText.segments!.isEmpty)) {
        
        debugPrint('세그먼트 모드로 전환하여 세그먼트 처리 시작');
        
        // 세그먼트 처리 (문장 분리 및 번역)
        final processedResult = await _ocrService.processText(
          processedText.fullOriginalText, 
          "languageLearning"
        );
        
        // 세그먼트 결과 업데이트
        if (processedResult.segments != null && processedResult.segments!.isNotEmpty) {
          final updatedText = processedText.copyWith(
            segments: processedResult.segments,
            showFullText: false,
            showFullTextModified: true
          );
          
          // 캐시 및 UI 업데이트
          await setProcessedText(pageId, updatedText);
          
          // 캐시 업데이트
          await updatePageCache(
            pageId,
            updatedText,
            "languageLearning"
          );
          
          debugPrint('세그먼트 처리 완료 및 캐시 업데이트 완료');
          return updatedText;
        }
        
        debugPrint('세그먼트 처리 결과 없음');
        return processedText;
      }
    } catch (e) {
      debugPrint('번역 데이터 확인 및 로드 중 오류: $e');
    }
    
    return processedText;
  }
  
  // 전체 텍스트/세그먼트 모드 전환
  Future<ProcessedText> toggleDisplayMode(String pageId, ProcessedText processedText) async {
    final updatedText = processedText.toggleDisplayMode();
    await setProcessedText(pageId, updatedText);
    return updatedText;
  }
  
  // 병음 표시 전환
  Future<ProcessedText> togglePinyin(String pageId, ProcessedText processedText) async {
    final updatedText = processedText.copyWith(showPinyin: !processedText.showPinyin);
    await setProcessedText(pageId, updatedText);
    return updatedText;
  }
  
  // 번역 표시 전환
  Future<ProcessedText> toggleTranslation(String pageId, ProcessedText processedText) async {
    final updatedText = processedText.copyWith(showTranslation: !processedText.showTranslation);
    await setProcessedText(pageId, updatedText);
    return updatedText;
  }
}
