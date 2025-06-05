import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../models/text_unit.dart';
import '../../../features/note/pre_llm_workflow.dart';
import 'api_service.dart';

/// 스트리밍 번역 전담 서비스
/// HTTP 스트리밍, 텍스트 분배, 청크 처리를 담당
class StreamingTranslationService {
  final ApiService _apiService = ApiService();

  /// 스트리밍 번역 실행 및 결과 분배
  Stream<StreamingTranslationResult> processStreamingTranslation({
    required List<String> textSegments,
    required List<PageProcessingData> pages,
    required String sourceLanguage,
    required String targetLanguage,
    required String noteId,
    required bool needPinyin,
  }) async* {
    if (kDebugMode) {
      debugPrint('🌊 [스트리밍] 번역 시작: ${textSegments.length}개 세그먼트');
    }

    final Map<String, List<TextUnit>> pageResults = {};
    final Set<String> completedPages = {};
    int processedChunks = 0;

    try {
      // HTTP 스트리밍 시작
      await for (final chunkData in _apiService.translateSegmentsStream(
        textSegments: textSegments,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        needPinyin: needPinyin,
        noteId: noteId,
      )) {
        if (kDebugMode) {
          debugPrint('📦 [스트리밍] 청크 수신: ${chunkData['chunkIndex'] + 1}/${chunkData['totalChunks']}');
        }

        // 오류 청크 처리
        if (chunkData['isError'] == true) {
          yield StreamingTranslationResult.error(
            chunkIndex: chunkData['chunkIndex'] as int,
            error: chunkData['error']?.toString() ?? '알 수 없는 오류',
          );
          continue;
        }

        // 정상 청크 처리
        final chunkUnits = _extractUnitsFromChunkData(chunkData);
        final chunkIndex = chunkData['chunkIndex'] as int;
        
        if (kDebugMode) {
          debugPrint('📦 청크 ${chunkIndex} 처리: ${chunkUnits.length}개 유닛');
        }
        
        // LLM 결과를 페이지별로 분배
        await _distributeUnitsToPages(
          chunkUnits, 
          pages, 
          pageResults,
          isFirstChunk: chunkIndex == 0,
        );
        
        processedChunks++;
        
        // 스트리밍 결과 반환
        yield StreamingTranslationResult.success(
          chunkIndex: chunkIndex,
          chunkUnits: chunkUnits,
          pageResults: Map.from(pageResults),
          isComplete: chunkData['isComplete'] == true,
          processedChunks: processedChunks,
        );
        
        // 완료 확인
        if (chunkData['isComplete'] == true) {
          if (kDebugMode) {
            debugPrint('✅ [스트리밍] 완료: ${processedChunks}개 청크');
          }
          break;
        }
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [스트리밍] 실패: $e');
      }
      
      // 폴백 처리
      yield* _createFallbackResults(textSegments, pages, sourceLanguage, targetLanguage);
    }
  }

  /// LLM 결과를 페이지별로 분배 (OCR 세그먼트와 독립적)
  Future<void> _distributeUnitsToPages(
    List<TextUnit> chunkUnits,
    List<PageProcessingData> pages,
    Map<String, List<TextUnit>> pageResults, {
    bool isFirstChunk = false,
  }) async {
    if (chunkUnits.isEmpty || pages.isEmpty) return;
    
    if (pages.length == 1) {
      // 단일 페이지: LLM 결과를 점진적으로 추가
      final pageId = pages.first.pageId;
      pageResults.putIfAbsent(pageId, () => []);
      pageResults[pageId]!.addAll(chunkUnits);
      
      if (kDebugMode) {
        debugPrint('✅ LLM 청크 누적: ${pageId} (+${chunkUnits.length}개, 총 ${pageResults[pageId]!.length}개)');
      }
    } else {
      // 다중 페이지: 텍스트 유사도 기반 최적 매칭
      for (final unit in chunkUnits) {
        final bestPageId = _findBestMatchingPage(unit, pages);
        pageResults.putIfAbsent(bestPageId, () => []);
        pageResults[bestPageId]!.add(unit);
        
        if (kDebugMode) {
          debugPrint('🎯 유닛 매칭: "${unit.originalText.substring(0, math.min(30, unit.originalText.length))}..." → ${bestPageId}');
        }
      }
      
      if (kDebugMode) {
        debugPrint('🔀 다중 페이지 분배 완료: ${chunkUnits.length}개 유닛을 ${pages.length}개 페이지에 분배');
      }
    }
  }

  /// 유닛과 가장 유사한 페이지 찾기 (텍스트 매칭 기반)
  String _findBestMatchingPage(TextUnit unit, List<PageProcessingData> pages) {
    if (pages.length == 1) return pages.first.pageId;
    
    String bestPageId = pages.first.pageId;
    double highestSimilarity = 0.0;
    
    for (final page in pages) {
      final pageText = page.textSegments.join(' ');
      final similarity = _calculateTextSimilarity(unit.originalText, pageText);
      
      if (similarity > highestSimilarity) {
        highestSimilarity = similarity;
        bestPageId = page.pageId;
      }
    }
    
    return bestPageId;
  }

  /// 간단한 텍스트 유사도 계산 (공통 문자 비율)
  double _calculateTextSimilarity(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return 0.0;
    
    int commonChars = 0;
    final chars1 = text1.split('');
    final chars2 = text2.split('');
    
    for (final char in chars1) {
      if (chars2.contains(char)) {
        commonChars++;
      }
    }
    
    return commonChars / math.max(text1.length, text2.length);
  }

  /// 스트리밍 청크 데이터에서 TextUnit 리스트 추출
  List<TextUnit> _extractUnitsFromChunkData(Map<String, dynamic> chunkData) {
    try {
      if (chunkData['units'] == null) return [];

      final units = chunkData['units'] as List;
      return units.map((unitData) {
        final unit = Map<String, dynamic>.from(unitData);
        return TextUnit(
          originalText: unit['originalText'] ?? '',
          translatedText: unit['translatedText'] ?? '',
          pinyin: unit['pinyin'] ?? '',
          sourceLanguage: unit['sourceLanguage'] ?? 'zh-CN',
          targetLanguage: unit['targetLanguage'] ?? 'ko',
        );
      }).toList();
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 청크 데이터 파싱 실패: $e');
      }
      return [];
    }
  }

  /// 스트리밍 실패 시 폴백 결과 생성
  Stream<StreamingTranslationResult> _createFallbackResults(
    List<String> textSegments,
    List<PageProcessingData> pages,
    String sourceLanguage,
    String targetLanguage,
  ) async* {
    final Map<String, List<TextUnit>> pageResults = {};
    
    // 폴백 텍스트 유닛 생성
    for (int i = 0; i < textSegments.length; i++) {
      final pageId = pages.isNotEmpty ? pages.first.pageId : 'unknown';
      pageResults.putIfAbsent(pageId, () => []);
      
      pageResults[pageId]!.add(TextUnit(
        originalText: textSegments[i],
        translatedText: '[스트리밍 실패]',
        pinyin: '',
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      ));
    }
    
    yield StreamingTranslationResult.success(
      chunkIndex: 0,
      chunkUnits: pageResults.values.expand((units) => units).toList(),
      pageResults: pageResults,
      isComplete: true,
      processedChunks: 1,
    );
  }
}

/// 스트리밍 번역 결과
class StreamingTranslationResult {
  final bool isSuccess;
  final int chunkIndex;
  final List<TextUnit> chunkUnits;
  final Map<String, List<TextUnit>> pageResults;
  final bool isComplete;
  final int processedChunks;
  final String? error;

  StreamingTranslationResult._({
    required this.isSuccess,
    required this.chunkIndex,
    required this.chunkUnits,
    required this.pageResults,
    required this.isComplete,
    required this.processedChunks,
    this.error,
  });

  factory StreamingTranslationResult.success({
    required int chunkIndex,
    required List<TextUnit> chunkUnits,
    required Map<String, List<TextUnit>> pageResults,
    required bool isComplete,
    required int processedChunks,
  }) {
    return StreamingTranslationResult._(
      isSuccess: true,
      chunkIndex: chunkIndex,
      chunkUnits: chunkUnits,
      pageResults: pageResults,
      isComplete: isComplete,
      processedChunks: processedChunks,
    );
  }

  factory StreamingTranslationResult.error({
    required int chunkIndex,
    required String error,
  }) {
    return StreamingTranslationResult._(
      isSuccess: false,
      chunkIndex: chunkIndex,
      chunkUnits: [],
      pageResults: {},
      isComplete: false,
      processedChunks: 0,
      error: error,
    );
  }
} 