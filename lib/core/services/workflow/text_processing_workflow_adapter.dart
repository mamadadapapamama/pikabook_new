import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../models/processed_text.dart';
import '../../models/page.dart' as page_model;
import '../../models/text_segment.dart';
import '../../../LLM test/llm_text_processing.dart';

/// 텍스트 처리 워크플로우 어댑터
/// 기존 레거시 워크플로우를 제거하고 LLM 기반 워크플로우만 사용하도록 수정됨
class TextProcessingWorkflowAdapter {
  final UnifiedTextProcessingService llmWorkflow;

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
      final chineseText = await llmWorkflow.processWithLLM(
        page.originalText,
        sourceLanguage: llmSourceLanguage ?? 'zh',
      );
      
      // LLM 결과를 ProcessedText로 변환
      return ProcessedText(
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
        showFullText: false,
        showPinyin: true,
        showTranslation: true,
      );
    } catch (e) {
      debugPrint('텍스트 처리 중 오류: $e');
      return null;
    }
  }
}
