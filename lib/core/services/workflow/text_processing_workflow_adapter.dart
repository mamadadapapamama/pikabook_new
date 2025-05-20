import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../models/processed_text.dart';
import '../../models/page.dart' as page_model;
import '../../models/text_segment.dart';
import '../text_processing/llm_text_processing.dart';
import '../authentication/user_preferences_service.dart';

/// 텍스트 처리 워크플로우 어댑터
/// 기존 레거시 워크플로우를 제거하고 LLM 기반 워크플로우만 사용하도록 수정됨
class TextProcessingWorkflowAdapter {
  final UnifiedTextProcessingService llmWorkflow;
  final UserPreferencesService _preferencesService = UserPreferencesService();

  TextProcessingWorkflowAdapter({
    UnifiedTextProcessingService? llmWorkflow,
  }) : llmWorkflow = llmWorkflow ?? UnifiedTextProcessingService();

  /// 페이지 텍스트 처리 (항상 LLM 사용)
  Future<ProcessedText?> processPageText({
    required page_model.Page? page,
    bool useLLM = true, // 하위 호환성을 위해 유지하되 기본값은 true
    String? llmSourceLanguage,
  }) async {
    if (page == null) return null;
    
    try {
      // 사용자의 번역 모드 설정 확인
      final useSegmentMode = await _preferencesService.getUseSegmentMode();
      final translationMode = useSegmentMode ? 'segment' : 'full';
      debugPrint('TextProcessingWorkflowAdapter: 번역 모드 = $translationMode');
      
      final chineseText = await llmWorkflow.processWithLLM(
        page.originalText,
        sourceLanguage: llmSourceLanguage ?? 'zh',
      );
      
      // LLM 결과를 ProcessedText로 변환
      final processedText = ProcessedText(
        mode: useSegmentMode ? TextProcessingMode.segment : TextProcessingMode.full,
        fullOriginalText: chineseText.originalText,
        fullTranslatedText: chineseText.sentences.map((s) => s.translation).join('\n'),
        segments: chineseText.sentences.map((s) =>
          TextSegment(
            originalText: s.original,
            translatedText: s.translation,
            pinyin: s.pinyin,
            sourceLanguage: llmSourceLanguage ?? 'zh-CN',
            targetLanguage: 'ko',
          )
        ).toList(),
        showFullText: !useSegmentMode, // 번역 모드에 따라 초기 표시 설정
        showPinyin: useSegmentMode, // full 모드에서는 병음 표시하지 않음
        showTranslation: true,
      );
      
      debugPrint('TextProcessingWorkflowAdapter: 처리 완료 - ${chineseText.sentences.length}개 세그먼트, 전체 텍스트 모드: ${!useSegmentMode}');
      return processedText;
    } catch (e) {
      debugPrint('텍스트 처리 중 오류: $e');
      return null;
    }
  }
}
