import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/processed_text.dart';
import '../../models/page.dart' as page_model;
import '../text_processing/translation_service.dart';
import '../storage/unified_cache_service.dart';
import '../authentication/user_preferences_service.dart';

/// 텍스트 처리를 위한 최적화된 워크플로우
class OptimizedTextProcessingWorkflow {
  // 싱글톤 패턴
  static final OptimizedTextProcessingWorkflow _instance = OptimizedTextProcessingWorkflow._internal();
  factory OptimizedTextProcessingWorkflow() => _instance;
  
  OptimizedTextProcessingWorkflow._internal() {
    if (kDebugMode) {
      debugPrint('✨ OptimizedTextProcessingWorkflow: 생성자 호출됨');
    }
  }
  
  // 서비스 인스턴스
  final TranslationService _translationService = TranslationService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  
  /// 페이지 텍스트 처리 메인 메서드
  Future<ProcessedText?> processPageText({
    required page_model.Page? page,
    required File? imageFile,
  }) async {
    // 구현 없이 기본 빈 인터페이스만 제공
    return ProcessedText(
      fullOriginalText: page?.originalText ?? '',
      fullTranslatedText: page?.translatedText ?? '',
      segments: [],
      showFullText: true,
      showPinyin: true,
      showTranslation: true,
    );
  }
  
  /// 캐시 관련 메서드들
  Future<ProcessedText?> getProcessedText(String? pageId) async {
    if (pageId == null) return null;
    return await _cacheService.getProcessedText(pageId);
  }
} 