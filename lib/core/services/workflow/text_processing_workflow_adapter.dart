import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../models/processed_text.dart';
import '../../models/page.dart' as page_model;
import '../../models/text_segment.dart';
import '../../../LLM test/llm_text_processing.dart';
import 'text_processing_workflow.dart';

/// 텍스트 처리 워크플로우 어댑터
/// useLLM 플래그에 따라 기존 워크플로우 또는 LLM 기반 워크플로우를 선택적으로 사용
class TextProcessingWorkflowAdapter {
  final OptimizedTextProcessingWorkflow legacyWorkflow;
  final UnifiedTextProcessingService llmWorkflow;

  TextProcessingWorkflowAdapter({
    OptimizedTextProcessingWorkflow? legacyWorkflow,
    UnifiedTextProcessingService? llmWorkflow,
  })  : legacyWorkflow = legacyWorkflow ?? OptimizedTextProcessingWorkflow(),
        llmWorkflow = llmWorkflow ?? UnifiedTextProcessingService();

  /// 페이지 텍스트 처리 (useLLM: true면 LLM, false면 기존 워크플로우)
  Future<ProcessedText?> processPageText({
    required page_model.Page? page,
    required bool useLLM,
    String? llmSourceLanguage,
  }) async {
    if (useLLM) {
      if (page == null) return null;
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
    } else {
      // 기존 워크플로우 사용
      return await legacyWorkflow.processPageText(page: page, imageFile: null);
    }
  }
}
