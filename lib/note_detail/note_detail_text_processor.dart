import 'dart:io';
import '../models/page.dart' as page_model;
import '../services/page_content_service.dart';
import '../models/processed_text.dart';
import '../services/translation_service.dart';
import '../services/enhanced_ocr_service.dart';
import 'package:flutter/material.dart';
import '../models/note.dart';

/// 노트 세부 화면에서 텍스트 처리와 관련된 기능을 관리하는 클래스입니다.
class NoteDetailTextProcessor {
  final PageContentService _pageContentService = PageContentService();
  final TranslationService _translationService = TranslationService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  
  /// 현재 페이지의 텍스트를 처리합니다.
  Future<ProcessedText?> processPageText({
    required page_model.Page? page,
    required File? imageFile,
  }) async {
    if (page == null) return null;
    
    debugPrint('NoteDetailTextProcessor: 페이지 텍스트 처리 시작 - 페이지 ID: ${page.id}');
    return await _pageContentService.processPageText(
      page: page,
      imageFile: imageFile,
    );
  }
  
  /// 번역 데이터가 있는지 확인하고 필요한 경우 로드합니다.
  Future<ProcessedText?> checkAndLoadTranslationData({
    required Note note,
    required page_model.Page? page,
    required File? imageFile,
    required ProcessedText? currentProcessedText,
  }) async {
    if (page == null || (currentProcessedText == null && imageFile == null)) {
      debugPrint('NoteDetailTextProcessor: 번역 데이터 로드 실패 - 페이지 또는 처리된 텍스트/이미지 없음');
      return null;
    }

    try {
      // 이미 처리된 텍스트가 있는지 확인
      if (currentProcessedText != null) {
        // 전체 번역이 누락된 경우
        if (currentProcessedText.fullTranslatedText == null || 
            currentProcessedText.fullTranslatedText!.isEmpty) {
          debugPrint('NoteDetailTextProcessor: 전체 번역 텍스트 누락됨, 번역 시도');
          
          // 1. 원본 텍스트로 번역 시도
          final String fullText = currentProcessedText.fullOriginalText;
          final translationResult = await _translationService.translateText(
            fullText,
            sourceLanguage: note.sourceLanguage,
            targetLanguage: note.targetLanguage,
          );
          
          if (translationResult.isNotEmpty) {
            // 번역된 결과로 ProcessedText 업데이트
            final updatedProcessedText = currentProcessedText.copyWith(
              fullTranslatedText: translationResult,
            );
            
            // 캐시에 저장
            if (page.id != null) {
              await _pageContentService.updatePageCache(
                page.id!,
                updatedProcessedText,
                "languageLearning",
              );
            }
            
            debugPrint('NoteDetailTextProcessor: 전체 번역 업데이트 완료');
            return updatedProcessedText;
          }
        }
        
        // 세그먼트가 누락된 경우
        if (currentProcessedText.segments == null || 
            currentProcessedText.segments!.isEmpty) {
          debugPrint('NoteDetailTextProcessor: 세그먼트 누락됨, 재처리 시도');
          
          // 원본 텍스트와 번역 텍스트로 다시 처리
          final fullOriginalText = currentProcessedText.fullOriginalText;
          final fullTranslatedText = currentProcessedText.fullTranslatedText;
          
          // OCR 서비스를 통해 텍스트 재처리
          final reprocessedText = await _ocrService.processText(
            fullOriginalText,
            "languageLearning",
          );
          
          // 번역 텍스트 설정
          final updatedProcessedText = reprocessedText.copyWith(
            fullTranslatedText: fullTranslatedText,
            showFullText: currentProcessedText.showFullText,
            showPinyin: currentProcessedText.showPinyin,
            showTranslation: currentProcessedText.showTranslation,
          );
          
          // 캐시에 저장
          if (page.id != null) {
            await _pageContentService.updatePageCache(
              page.id!,
              updatedProcessedText,
              "languageLearning",
            );
          }
          
          debugPrint('NoteDetailTextProcessor: 세그먼트 재처리 완료');
          return updatedProcessedText;
        }
        
        // 이미 모든 데이터가 있는 경우 현재 값 반환
        return currentProcessedText;
      } else {
        // 현재 처리된 텍스트가 없는 경우 새로 처리
        debugPrint('NoteDetailTextProcessor: 처리된 텍스트 없음, 새로 처리 시작');
        return await processPageText(
          page: page,
          imageFile: imageFile,
        );
      }
    } catch (e) {
      debugPrint('NoteDetailTextProcessor: 번역 데이터 로드 중 오류 발생 - $e');
      return currentProcessedText;
    }
  }
  
  /// 표시 모드를 전환합니다 (전체 텍스트 <-> 세그먼트).
  Future<ProcessedText?> toggleDisplayMode({
    required String? pageId,
    required ProcessedText processedText,
  }) async {
    if (pageId == null) {
      debugPrint('NoteDetailTextProcessor: 페이지 ID가 없어 표시 모드를 전환할 수 없습니다.');
      // 페이지 ID가 없어도 UI 변경을 위해 객체는 업데이트
      return processedText.toggleDisplayMode();
    }

    try {
      // 표시 모드 토글 적용
      final updatedProcessedText = processedText.toggleDisplayMode();
      
      // PageContentService를 통해 캐시 업데이트
      await _pageContentService.setProcessedText(pageId, updatedProcessedText);
      await _pageContentService.updatePageCache(
        pageId,
        updatedProcessedText,
        "languageLearning",
      );
      
      debugPrint('NoteDetailTextProcessor: 표시 모드 전환됨 - showFullText: ${updatedProcessedText.showFullText}');
      return updatedProcessedText;
    } catch (e) {
      debugPrint('NoteDetailTextProcessor: 표시 모드 전환 중 오류 발생 - $e');
      return processedText;
    }
  }
  
  /// 병음 표시 여부를 전환합니다.
  Future<ProcessedText?> togglePinyin({
    required String? pageId,
    required ProcessedText processedText,
  }) async {
    if (pageId == null) {
      debugPrint('NoteDetailTextProcessor: 페이지 ID가 없어 병음 표시를 전환할 수 없습니다.');
      // 페이지 ID가 없어도 UI 변경을 위해 객체는 업데이트
      return processedText.copyWith(showPinyin: !processedText.showPinyin);
    }

    try {
      // 병음 표시 토글 적용
      final updatedProcessedText = processedText.copyWith(
        showPinyin: !processedText.showPinyin
      );
      
      // PageContentService를 통해 캐시 업데이트
      await _pageContentService.setProcessedText(pageId, updatedProcessedText);
      await _pageContentService.updatePageCache(
        pageId,
        updatedProcessedText,
        "languageLearning",
      );
      
      debugPrint('NoteDetailTextProcessor: 병음 표시 전환됨 - showPinyin: ${updatedProcessedText.showPinyin}');
      return updatedProcessedText;
    } catch (e) {
      debugPrint('NoteDetailTextProcessor: 병음 표시 전환 중 오류 발생 - $e');
      return processedText;
    }
  }
  
  /// 번역 표시 여부를 전환합니다.
  Future<ProcessedText?> toggleTranslation({
    required String? pageId,
    required ProcessedText processedText,
  }) async {
    if (pageId == null) {
      debugPrint('NoteDetailTextProcessor: 페이지 ID가 없어 번역 표시를 전환할 수 없습니다.');
      // 페이지 ID가 없어도 UI 변경을 위해 객체는 업데이트
      return processedText.copyWith(showTranslation: !processedText.showTranslation);
    }

    try {
      // 번역 표시 토글 적용
      final updatedProcessedText = processedText.copyWith(
        showTranslation: !processedText.showTranslation
      );
      
      // PageContentService를 통해 캐시 업데이트
      await _pageContentService.setProcessedText(pageId, updatedProcessedText);
      await _pageContentService.updatePageCache(
        pageId,
        updatedProcessedText,
        "languageLearning",
      );
      
      debugPrint('NoteDetailTextProcessor: 번역 표시 전환됨 - showTranslation: ${updatedProcessedText.showTranslation}');
      return updatedProcessedText;
    } catch (e) {
      debugPrint('NoteDetailTextProcessor: 번역 표시 전환 중 오류 발생 - $e');
      return processedText;
    }
  }
  
  /// 처리된 텍스트를 가져옵니다.
  Future<ProcessedText?> getProcessedText(String pageId) async {
    return await _pageContentService.getProcessedText(pageId);
  }
  
  /// 처리된 텍스트를 설정합니다.
  Future<void> setProcessedText(String pageId, ProcessedText processedText) async {
    await _pageContentService.setProcessedText(pageId, processedText);
  }
  
  /// 처리된 텍스트를 제거합니다.
  Future<void> removeProcessedText(String pageId) async {
    await _pageContentService.removeProcessedText(pageId);
  }
}
