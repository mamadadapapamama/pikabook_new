import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/text_unit.dart';
import '../../models/processed_text.dart';
import '../../../features/note/pre_llm_workflow.dart';
import '../../../features/note/services/page_service.dart';

/// **스트리밍 데이터 혼합 & UI 업데이트 서비스**  
/// LLM 스트리밍 결과와 OCR 원본을 혼합하여 UI 업데이트하는 역할
/// - OCR 세그먼트 보존 (번역 전 상태 유지)
/// - LLM 결과와 OCR 데이터 혼합
/// - 진행률 계산 및 스트리밍 상태 관리
/// - Firestore 페이지 실시간 업데이트
class StreamingPageUpdateService {
  final PageService _pageService = PageService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 스트리밍 단위로 페이지 업데이트 (OCR 결과 보존)
  Future<void> updatePageWithStreamingResult({
    required PageProcessingData pageData,
    required List<TextUnit> llmResults,
    required int totalExpectedUnits,
  }) async {
    try {
      // OCR 원본 세그먼트 가져오기
      final ocrSegments = pageData.textSegments;
      
      // 진행률 계산 (LLM 처리된 세그먼트 비율)
      final progress = _calculateProgress(llmResults.length, totalExpectedUnits);
      final isCompleted = llmResults.length >= totalExpectedUnits;
      
      // LLM 결과와 OCR 결과를 혼합한 최종 유닛 생성 (완료 상태 전달)
      final mixedUnits = _createMixedUnits(
        llmResults, 
        ocrSegments, 
        pageData,
        isStreamingComplete: isCompleted,
      );
      
      // 스트리밍 상태 결정
      final streamingStatus = isCompleted ? StreamingStatus.completed : StreamingStatus.streaming;

      // ProcessedText 생성 (OCR + LLM 혼합)
      final processedText = _createProcessedText(
        mixedUnits: mixedUnits,
        pageData: pageData,
        llmResultsCount: llmResults.length,
        progress: progress,
        streamingStatus: streamingStatus,
      );

      // 페이지 업데이트 데이터 준비
      final updateData = _prepareUpdateData(
        processedText: processedText,
        mixedUnits: mixedUnits,
        isCompleted: isCompleted,
        progress: progress,
      );

      // 페이지 실시간 업데이트
      await _pageService.updatePage(pageData.pageId, updateData);

      // 진행률 알림
      await _notifyPageProgress(pageData.pageId, progress);

      if (kDebugMode && llmResults.length % 3 == 0) { // 3개마다 로그
        debugPrint('🔄 스트리밍 업데이트 (OCR 보존): ${pageData.pageId}');
        debugPrint('   LLM 처리: ${llmResults.length}개');
        debugPrint('   OCR 원본: ${ocrSegments.length}개');
        debugPrint('   혼합 유닛: ${mixedUnits.length}개');
        debugPrint('   진행률: ${(progress * 100).toInt()}%');
        debugPrint('   상태: ${streamingStatus.name}');
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 스트리밍 업데이트 실패: ${pageData.pageId}, 오류: $e');
      }
      rethrow;
    }
  }

  /// LLM 결과로 OCR 세그먼트를 순차적으로 overwrite
  /// 
  /// **새로운 로직:**
  /// 1. OCR 세그먼트를 순서대로 보여줌
  /// 2. LLM 결과가 들어오면 순차적으로 overwrite (3개씩)
  /// 3. 스트리밍 완료 시: 미번역 OCR 세그먼트 제거
  /// 4. 스트리밍 진행 중: 남은 OCR 세그먼트는 [병음 필요, 번역 필요] 상태로 유지
  List<TextUnit> _createMixedUnits(
    List<TextUnit> llmResults,
    List<String> ocrSegments,
    PageProcessingData pageData, {
    bool isStreamingComplete = false,
  }) {
    final mixedUnits = <TextUnit>[];
    
    // 1. LLM 결과를 순서대로 추가 (순차적 overwrite)
    mixedUnits.addAll(llmResults);
    
    // 2. 스트리밍 완료 여부에 따른 처리
    if (isStreamingComplete) {
      // ✅ 스트리밍 완료: 미번역 OCR 세그먼트 제거
      if (kDebugMode) {
        final removedCount = ocrSegments.length - llmResults.length;
        if (removedCount > 0) {
          debugPrint('🗑️ 스트리밍 완료: 미번역 OCR 세그먼트 ${removedCount}개 제거');
        }
      }
      // LLM 결과만 유지, 남은 OCR 세그먼트는 추가하지 않음
    } else {
      // 🔄 스트리밍 진행 중: 남은 OCR 세그먼트 추가 (로딩 상태)
      final remainingOcrCount = ocrSegments.length - llmResults.length;
      
      if (remainingOcrCount > 0) {
        // LLM이 처리하지 않은 나머지 OCR 세그먼트들
        final remainingOcrSegments = ocrSegments.skip(llmResults.length).take(remainingOcrCount);
        
        for (final ocrSegment in remainingOcrSegments) {
          mixedUnits.add(TextUnit(
            originalText: ocrSegment,
            translatedText: null, // 아직 번역되지 않음
            pinyin: null, // 아직 병음 없음
            sourceLanguage: pageData.sourceLanguage,
            targetLanguage: pageData.targetLanguage,
          ));
        }
      }
    }
    
    if (kDebugMode) {
      debugPrint('🔄 순차적 overwrite (완료: $isStreamingComplete):');
      debugPrint('   LLM 처리됨: ${llmResults.length}개');
      debugPrint('   OCR 원본: ${ocrSegments.length}개');
      if (!isStreamingComplete) {
        final remainingOcrCount = ocrSegments.length - llmResults.length;
        debugPrint('   남은 OCR: ${remainingOcrCount > 0 ? remainingOcrCount : 0}개');
      }
      debugPrint('   최종 유닛: ${mixedUnits.length}개');
    }
    
    return mixedUnits;
  }

  /// 진행률 계산
  double _calculateProgress(int completedCount, int totalCount) {
    if (totalCount <= 0) return 1.0;
    return (completedCount / totalCount).clamp(0.0, 1.0);
  }

  /// ProcessedText 생성
  ProcessedText _createProcessedText({
    required List<TextUnit> mixedUnits,
    required PageProcessingData pageData,
    required int llmResultsCount,
    required double progress,
    required StreamingStatus streamingStatus,
  }) {
    // 전체 텍스트 생성
    final originalText = mixedUnits.map((unit) => unit.originalText).join(' ');
    final translatedText = mixedUnits
        .map((unit) => unit.translatedText ?? '')
        .where((text) => text.isNotEmpty)
        .join(' ');

    return ProcessedText(
      mode: pageData.mode,
      displayMode: TextDisplayMode.full,
      fullOriginalText: originalText,
      fullTranslatedText: translatedText,
      units: mixedUnits,
      sourceLanguage: pageData.sourceLanguage,
      targetLanguage: pageData.targetLanguage,
      streamingStatus: streamingStatus,
      completedUnits: llmResultsCount,
      progress: progress,
    );
  }

  /// 페이지 업데이트 데이터 준비
  Map<String, dynamic> _prepareUpdateData({
    required ProcessedText processedText,
    required List<TextUnit> mixedUnits,
    required bool isCompleted,
    required double progress,
  }) {
    final translatedText = mixedUnits
        .map((unit) => unit.translatedText ?? '')
        .where((text) => text.isNotEmpty)
        .join(' ');
    
    final pinyinText = mixedUnits
        .map((unit) => unit.pinyin ?? '')
        .where((text) => text.isNotEmpty)
        .join(' ');

    final updateData = <String, dynamic>{
      'translatedText': translatedText,
      'pinyin': pinyinText,
      'processedText': {
        'units': mixedUnits.map((unit) => unit.toJson()).toList(),
        'mode': processedText.mode.toString(),
        'displayMode': processedText.displayMode.toString(),
        'fullOriginalText': processedText.fullOriginalText,
        'fullTranslatedText': processedText.fullTranslatedText,
        'sourceLanguage': processedText.sourceLanguage,
        'targetLanguage': processedText.targetLanguage,
        'streamingStatus': processedText.streamingStatus.index,
        'completedUnits': processedText.completedUnits,
        'progress': progress,
      },
    };

    // 완료된 경우에만 최종 상태 업데이트
    if (isCompleted) {
      updateData.addAll({
        'processedAt': FieldValue.serverTimestamp(),
        'status': 'completed',
      });
    } else {
      updateData['status'] = 'translating';
    }

    return updateData;
  }

  /// 페이지 진행 상황 알림
  Future<void> _notifyPageProgress(String pageId, double progress) async {
    try {
      await _firestore.collection('pages').doc(pageId).update({
        'processingProgress': progress,
        'progressUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 진행 상황 알림 실패: $pageId, 오류: $e');
      }
    }
  }

  /// 최종 완료된 페이지 업데이트 (기존 호환성)
  Future<void> updatePageWithFinalResults({
    required PageProcessingData pageData,
    required List<TextUnit> results,
  }) async {
    try {
      // 번역과 병음 텍스트 조합
      final translatedText = results.map((unit) => unit.translatedText ?? '').join(' ');
      final pinyinText = results.map((unit) => unit.pinyin ?? '').join(' ');
      final originalText = results.map((unit) => unit.originalText).join(' ');

      // 완료된 ProcessedText 생성
      final completeProcessedText = ProcessedText(
        mode: pageData.mode,
        displayMode: TextDisplayMode.full,
        fullOriginalText: originalText,
        fullTranslatedText: translatedText,
        units: results,
        sourceLanguage: pageData.sourceLanguage,
        targetLanguage: pageData.targetLanguage,
        streamingStatus: StreamingStatus.completed,
        completedUnits: results.length,
        progress: 1.0,
      );

      // 페이지 최종 업데이트
      await _pageService.updatePage(pageData.pageId, {
        'translatedText': translatedText,
        'pinyin': pinyinText,
        'processedAt': FieldValue.serverTimestamp(),
        'status': 'completed',
        'processedText': {
          'units': results.map((unit) => unit.toJson()).toList(),
          'mode': completeProcessedText.mode.toString(),
          'displayMode': completeProcessedText.displayMode.toString(),
          'fullOriginalText': completeProcessedText.fullOriginalText,
          'fullTranslatedText': completeProcessedText.fullTranslatedText,
          'sourceLanguage': completeProcessedText.sourceLanguage,
          'targetLanguage': completeProcessedText.targetLanguage,
          'streamingStatus': StreamingStatus.completed.index,
          'completedUnits': results.length,
          'progress': 1.0,
        },
      });

      if (kDebugMode) {
        debugPrint('✅ 최종 페이지 업데이트 완료: ${pageData.pageId}');
        debugPrint('   번역 완료: ${results.length}개 유닛');
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 최종 페이지 업데이트 실패: ${pageData.pageId}, 오류: $e');
      }
      rethrow;
    }
  }
} 