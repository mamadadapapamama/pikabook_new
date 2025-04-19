import 'package:flutter/material.dart';

import '../../../../models/page.dart' as page_model;
import '../../../../models/processed_text.dart';
import '../../../../services/note/page_content_service.dart';
import '../../../../services/language/enhanced_ocr_service.dart';
import '../../../../services/language/tts_service.dart';
import '../../../../services/language/text_reader_service.dart';

/// 텍스트 처리 로직을 담당하는 클래스
/// 
/// 이 클래스는 OCR, 텍스트 처리, TTS 등의 로직을 처리합니다.

class TextProcessingManager {
  final Function(bool) onProcessingStateChanged;
  
  // 서비스 인스턴스
  final PageContentService _pageContentService = PageContentService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final TtsService _ttsService = TtsService();
  final TextReaderService _textReaderService = TextReaderService();
  
  // 상태 변수
  bool _isProcessing = false;
  
  TextProcessingManager({
    required this.onProcessingStateChanged,
  });
  
  // 텍스트 처리 상태 가져오기
  bool get isProcessing => _isProcessing;
  
  // 페이지 텍스트 처리
  Future<void> processTextForPage(page_model.Page? page) async {
    if (page == null || page.id == null) {
      return;
    }
    
    _setProcessing(true);
    
    try {
      debugPrint('페이지 텍스트 처리 시작: ${page.id}');
      
      // 페이지 콘텐츠 서비스를 통해 텍스트 처리
      final processedText = await _pageContentService.processPageText(
        page: page,
      );
      
      if (processedText != null && page.id != null) {
        // 기본 표시 설정 적용
        final updatedProcessedText = processedText.copyWith(
          showFullText: false, // 기본값: 세그먼트 모드
          showPinyin: true,
          showTranslation: true,
        );
        
        // 처리된 텍스트 캐싱
        _pageContentService.setProcessedText(page.id!, updatedProcessedText);
        
        debugPrint('텍스트 처리 완료: ${page.id}');
      } else {
        debugPrint('텍스트 처리 결과가 null이거나 페이지 ID가 null입니다');
      }
    } catch (e) {
      debugPrint('페이지 텍스트 처리 중 오류 발생: $e');
    } finally {
      _setProcessing(false);
    }
  }
  
  // 텍스트 모드 전환 (전체 텍스트 또는 세그먼트 모드)
  void toggleTextMode(String pageId, {required bool useSegmentMode}) {
    final processedText = _pageContentService.getProcessedText(pageId);
    
    if (processedText != null) {
      final updatedProcessedText = processedText.copyWith(
        showFullText: !useSegmentMode,
      );
      
      _pageContentService.updateProcessedText(pageId, updatedProcessedText);
    }
  }
  
  // 병음 표시 토글
  void togglePinyin(String pageId) {
    final processedText = _pageContentService.getProcessedText(pageId);
    
    if (processedText != null) {
      final updatedProcessedText = processedText.copyWith(
        showPinyin: !processedText.showPinyin,
      );
      
      _pageContentService.updateProcessedText(pageId, updatedProcessedText);
    }
  }
  
  // 번역 표시 토글
  void toggleTranslation(String pageId) {
    final processedText = _pageContentService.getProcessedText(pageId);
    
    if (processedText != null) {
      final updatedProcessedText = processedText.copyWith(
        showTranslation: !processedText.showTranslation,
      );
      
      _pageContentService.updateProcessedText(pageId, updatedProcessedText);
    }
  }
  
  // TTS 재생
  void playTts(String text) {
    if (text.isNotEmpty && text != '___PROCESSING___') {
      _ttsService.speak(text);
    }
  }
  
  // TTS 중지
  void stopTts() {
    _ttsService.stop();
  }
  
  // 텍스트 리더 재생
  void startTextReader(ProcessedText processedText) {
    _textReaderService.readProcessedText(processedText);
  }
  
  // 텍스트 리더 중지
  void stopTextReader() {
    _textReaderService.stop();
  }
  
  // 처리 상태 설정
  void _setProcessing(bool value) {
    if (_isProcessing != value) {
      _isProcessing = value;
      onProcessingStateChanged(value);
    }
  }
  
  // 리소스 정리
  Future<void> dispose() async {
    stopTts();
    stopTextReader();
  }
} 