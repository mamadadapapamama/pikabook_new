import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processed_text.dart';
import '../../../core/services/content/page_service.dart';
import '../../../core/services/media/image_service.dart';
import '../../../core/services/text_processing/llm_text_processing.dart';
import '../../../core/services/text_processing/enhanced_ocr_service.dart';
import '../../../core/services/storage/unified_cache_service.dart';
import '../../../core/services/authentication/user_preferences_service.dart';

/// 페이지 관리자: 페이지 상태 관리와 UI 관련 로직을 담당합니다.
class PageManager {
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final UnifiedTextProcessingService _textProcessingService = UnifiedTextProcessingService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();

  // 페이지 상태 관리
  final ValueNotifier<List<page_model.Page>> pages = ValueNotifier<List<page_model.Page>>([]);
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  // 현재 노트 ID
  String? _currentNoteId;

  /// 노트 ID 설정 및 페이지 로드
  Future<void> setNoteId(String noteId) async {
    _currentNoteId = noteId;
    await loadPages();
  }

  /// 페이지 로드
  Future<void> loadPages({bool forceReload = false}) async {
    if (_currentNoteId == null) return;

    try {
      isLoading.value = true;
      error.value = null;

      final loadedPages = await _pageService.getPagesForNote(_currentNoteId!, forceReload: forceReload);
      pages.value = loadedPages;
    } catch (e) {
      error.value = '페이지를 로드하는 중 오류가 발생했습니다: $e';
      debugPrint('페이지 로드 중 오류: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// 새 페이지 추가
  Future<void> addPage({
    required String originalText,
    required String translatedText,
    required int pageNumber,
    File? imageFile,
  }) async {
    if (_currentNoteId == null) return;

    try {
      isLoading.value = true;
      error.value = null;

      final newPage = await _pageService.createPage(
        noteId: _currentNoteId!,
        originalText: originalText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageFile: imageFile,
      );

      pages.value = [...pages.value, newPage];
    } catch (e) {
      error.value = '페이지를 추가하는 중 오류가 발생했습니다: $e';
      debugPrint('페이지 추가 중 오류: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// 페이지 업데이트
  Future<void> updatePage({
    required String pageId,
    String? originalText,
    String? translatedText,
    int? pageNumber,
    File? imageFile,
  }) async {
    try {
      isLoading.value = true;
      error.value = null;

      final updatedPage = await _pageService.updatePage(
        pageId,
        originalText: originalText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageFile: imageFile,
      );

      if (updatedPage != null) {
        final index = pages.value.indexWhere((p) => p.id == pageId);
        if (index != -1) {
          final updatedPages = List<page_model.Page>.from(pages.value);
          updatedPages[index] = updatedPage;
          pages.value = updatedPages;
        }
      }
    } catch (e) {
      error.value = '페이지를 업데이트하는 중 오류가 발생했습니다: $e';
      debugPrint('페이지 업데이트 중 오류: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// 페이지 삭제
  Future<void> deletePage(String pageId) async {
    try {
      isLoading.value = true;
      error.value = null;

      await _pageService.deletePage(pageId);
      pages.value = pages.value.where((p) => p.id != pageId).toList();
    } catch (e) {
      error.value = '페이지를 삭제하는 중 오류가 발생했습니다: $e';
      debugPrint('페이지 삭제 중 오류: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// 이미지에서 텍스트 추출 및 처리
  Future<ProcessedText?> processImage(File imageFile) async {
    try {
      isLoading.value = true;
      error.value = null;

      // OCR로 텍스트 추출
      final extractedText = await _ocrService.extractTextFromImage(imageFile);
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

  /// 리소스 정리
  void dispose() {
    pages.dispose();
    isLoading.dispose();
    error.dispose();
  }
}
