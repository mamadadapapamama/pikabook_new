import 'package:flutter/material.dart';
import 'dart:io';
import '../models/flash_card.dart';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import '../services/flashcard_service.dart' hide debugPrint;
import '../services/page_content_service.dart';
import '../services/tts_service.dart';
import '../services/unified_cache_service.dart';
import 'note_detail_image_handler.dart';
import 'note_detail_page_manager.dart';
import 'note_detail_text_processor.dart';
import '../widgets/note_detail/note_detail_state.dart';

class NoteContentManager {
  final NoteDetailPageManager _pageManager;
  final NoteDetailTextProcessor _textProcessor;
  final NoteDetailImageHandler _imageHandler;
  final TtsService _ttsService = TtsService();
  final FlashCardService _flashCardService = FlashCardService();
  final PageContentService _pageContentService = PageContentService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final NoteDetailState _state;
  
  NoteContentManager(this._pageManager, this._textProcessor, this._imageHandler, this._state);
  
  // 현재 페이지 텍스트 처리
  Future<void> processCurrentPageText() async {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null) return;
    
    _state.setProcessingText(true);
    
    try {
      debugPrint('페이지 텍스트 처리 시작: ${currentPage.id}');
      
      // 이미지 로드가 필요한 경우 로드
      if (currentPage.imageUrl != null && currentPage.imageUrl!.isNotEmpty) {
        await _imageHandler.loadPageImage(currentPage);
      }
      
      // 텍스트 처리
      final processedText = await _textProcessor.processPageText(
        page: currentPage,
        imageFile: _imageHandler.getCurrentImageFile(),
      );
      
      if (processedText != null && currentPage.id != null) {
        try {
          // 기본 표시 설정 지정
          final updatedProcessedText = processedText.copyWith(
            showFullText: false, // 기본값: 세그먼트 모드
            showPinyin: true, // 병음 표시는 기본적으로 활성화
            showTranslation: true, // 번역은 항상 표시
          );
          
          // 업데이트된 텍스트 캐싱
          await _pageContentService.setProcessedText(currentPage.id!, updatedProcessedText);
          
          debugPrint('텍스트 처리 완료: ${currentPage.id}');
          
          // 페이지가 처음 방문된 것으로 표시
          _state.markPageVisited(_pageManager.currentPageIndex);
        } catch (e) {
          debugPrint('페이지 텍스트 처리 중 오류 발생: ProcessedText 객체 변환 실패: $e');
          // 캐시 삭제 및 다시 로드 시도
          await _pageContentService.removeProcessedText(currentPage.id!);
        }
      }
    } catch (e) {
      debugPrint('페이지 텍스트 처리 중 오류 발생: $e');
    } finally {
      _state.setProcessingText(false);
    }
  }
  
  // 전체 텍스트/세그먼트 모드 전환
  Future<void> toggleFullTextMode(bool useSegmentMode) async {
    final currentPage = _pageManager.currentPage;
    if (currentPage?.id == null) return;
    
    final pageId = currentPage!.id!;
    final processedText = await _pageContentService.getProcessedText(pageId);
    
    if (processedText != null) {
      // 현재 표시 모드와 요청된 모드가 다른 경우에만 전환
      final bool currentIsFullMode = processedText.showFullText;
      final bool requestingFullMode = !useSegmentMode;
      
      // 같은 모드로 전환하려는 경우 무시
      if (currentIsFullMode == requestingFullMode) return;
      
      // 1. 모드 전환 전에 번역 데이터 확인 및 필요시 로드
      if (_state.note != null) {
        final updatedText = await _textProcessor.checkAndLoadTranslationData(
          note: _state.note!,
          page: currentPage,
          imageFile: _imageHandler.getCurrentImageFile(),
          currentProcessedText: processedText
        );
        
        // 2. 모드 전환
        if (updatedText != null) {
          await _textProcessor.toggleDisplayMode(
            pageId: pageId,
            processedText: updatedText
          );
        }
      }
    }
  }
  
  // 플래시카드 생성
  Future<bool> createFlashCard(String front, String back, {String? pinyin}) async {
    try {
      if (_state.note?.id == null) return false;
      
      // 이미 있는 플래시카드인지 확인
      bool exists = false;
      if (_state.note?.flashCards != null) {
        for (var card in _state.note!.flashCards) {
          if (card.front == front) {
            exists = true;
            break;
          }
        }
      }
      
      if (exists) {
        debugPrint('이미 존재하는 플래시카드입니다: $front');
        return false;
      }
      
      // 새 플래시카드 생성
      await _flashCardService.createFlashCard(
        front: front,
        back: back,
        pinyin: pinyin,
        noteId: _state.note!.id!,
      );
      
      return true;
    } catch (e) {
      debugPrint('플래시카드 생성 중 오류 발생: $e');
      return false;
    }
  }
  
  // 세그먼트 삭제
  Future<void> handleDeleteSegment(int segmentIndex) async {
    try {
      final currentPage = _pageManager.currentPage;
      if (currentPage?.id == null) return;
      
      final pageId = currentPage!.id!;
      final processedText = await _pageContentService.getProcessedText(pageId);
      
      if (processedText == null || 
          processedText.segments == null || 
          segmentIndex >= processedText.segments!.length) {
        return;
      }
      
      // 세그먼트 목록에서 해당 세그먼트 제거
      final segments = List<TextSegment>.from(processedText.segments!);
      segments.removeAt(segmentIndex);
      
      // 업데이트된 ProcessedText 생성
      final updatedText = processedText.copyWith(
        segments: segments,
      );
      
      // 변경사항 저장
      await _pageContentService.setProcessedText(pageId, updatedText);
      
      debugPrint('세그먼트 삭제됨: 페이지 $pageId, 인덱스 $segmentIndex');
    } catch (e) {
      debugPrint('세그먼트 삭제 중 오류 발생: $e');
    }
  }
  
  // 리소스 정리
  void dispose() {
    _ttsService.stop();
  }
}
