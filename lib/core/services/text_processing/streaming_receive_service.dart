import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../models/text_unit.dart';
import '../../../features/note/pre_llm_workflow.dart';
import 'api_service.dart';

/// **스트리밍 수신 & 분배 서비스**
/// 서버 HTTP 스트리밍을 받아서 페이지별로 분배하는 역할
/// - 네트워크 통신 (서버 ↔ 클라이언트)
/// - 청크 데이터 파싱 및 TextUnit 변환
/// - 다중 페이지 텍스트 유사도 분배
/// - 스트리밍 결과 조율

class StreamingReceiveService {
  final ApiService _apiService = ApiService();

  /// 스트리밍 번역 실행 및 결과 분배
  Stream<StreamingReceiveResult> processStreamingTranslation({
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
                  yield StreamingReceiveResult.error(
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
        yield StreamingReceiveResult.success(
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

  /// LLM 결과를 페이지별로 순차적으로 분배
  /// 
  /// **새로운 로직:**
  /// - 텍스트 유사도 비교 제거
  /// - 순서대로 페이지별 누적
  /// - LLM이 재배치/병합한 결과를 그대로 반영
  Future<void> _distributeUnitsToPages(
    List<TextUnit> chunkUnits,
    List<PageProcessingData> pages,
    Map<String, List<TextUnit>> pageResults, {
    bool isFirstChunk = false,
  }) async {
    if (chunkUnits.isEmpty || pages.isEmpty) return;
    
    if (pages.length == 1) {
      // 단일 페이지: LLM 결과를 순차적으로 누적
      final pageId = pages.first.pageId;
      pageResults.putIfAbsent(pageId, () => []);
      pageResults[pageId]!.addAll(chunkUnits);
      
      if (kDebugMode) {
        debugPrint('✅ 단일 페이지 순차 누적: ${pageId} (+${chunkUnits.length}개, 총 ${pageResults[pageId]!.length}개)');
      }
    } else {
      // 다중 페이지: OCR 세그먼트 순서 기반 순차 분배
      await _distributeUnitsToMultiplePages(chunkUnits, pages, pageResults);
    }
  }

  /// 다중 페이지에 유닛 분배 (기준점 비교 방식)
  Future<void> _distributeUnitsToMultiplePages(
    List<TextUnit> chunkUnits,
    List<PageProcessingData> pages,
    Map<String, List<TextUnit>> pageResults,
  ) async {
    // 각 페이지의 기준점 생성 (첫 번째 + 마지막 세그먼트)
    final pageMarkers = <String, PageMarker>{};
    
    for (final page in pages) {
      if (page.textSegments.isNotEmpty) {
        pageMarkers[page.pageId] = PageMarker(
          pageId: page.pageId,
          firstSegment: page.textSegments.first,
          lastSegment: page.textSegments.last,
          totalSegments: page.textSegments.length,
        );
      }
    }
    
    if (kDebugMode) {
      debugPrint('📄 다중 페이지 분배 (기준점 방식): ${chunkUnits.length}개 LLM 유닛');
      for (final marker in pageMarkers.values) {
        debugPrint('   📄 ${marker.pageId}: "${marker.firstSegment}" ... "${marker.lastSegment}" (${marker.totalSegments}개)');
      }
    }
    
    // LLM 유닛을 기준점 비교로 페이지별 분배
    for (final unit in chunkUnits) {
      final assignedPageId = _findMatchingPage(unit, pageMarkers.values.toList());
      
      if (assignedPageId != null) {
        pageResults.putIfAbsent(assignedPageId, () => []);
        pageResults[assignedPageId]!.add(unit);
      } else {
        // 매칭되지 않는 경우 첫 번째 페이지에 할당 (폴백)
        final fallbackPageId = pages.first.pageId;
        pageResults.putIfAbsent(fallbackPageId, () => []);
        pageResults[fallbackPageId]!.add(unit);
        
        if (kDebugMode) {
          debugPrint('⚠️ 매칭 실패, 폴백 할당: "${unit.originalText}" → ${fallbackPageId}');
        }
      }
    }
    
    if (kDebugMode) {
      debugPrint('✅ 다중 페이지 분배 완료:');
      for (final entry in pageResults.entries) {
        debugPrint('   📄 ${entry.key}: ${entry.value.length}개 유닛');
      }
    }
  }
  
  /// LLM 유닛이 어느 페이지에 속하는지 찾기
  String? _findMatchingPage(TextUnit unit, List<PageMarker> pageMarkers) {
    final unitText = unit.originalText.trim();
    
    // 1. 정확한 포함 관계 확인 (첫 번째 또는 마지막 세그먼트와 일치)
    for (final marker in pageMarkers) {
      if (unitText.contains(marker.firstSegment.trim()) || 
          unitText.contains(marker.lastSegment.trim()) ||
          marker.firstSegment.trim().contains(unitText) ||
          marker.lastSegment.trim().contains(unitText)) {
        return marker.pageId;
      }
    }
    
    // 2. 부분 문자열 유사도 확인 (70% 이상 일치)
    double maxSimilarity = 0.0;
    String? bestMatchPageId;
    
    for (final marker in pageMarkers) {
      final firstSimilarity = _calculateSimilarity(unitText, marker.firstSegment.trim());
      final lastSimilarity = _calculateSimilarity(unitText, marker.lastSegment.trim());
      final maxPageSimilarity = math.max(firstSimilarity, lastSimilarity);
      
      if (maxPageSimilarity > maxSimilarity && maxPageSimilarity >= 0.7) {
        maxSimilarity = maxPageSimilarity;
        bestMatchPageId = marker.pageId;
      }
    }
    
    return bestMatchPageId;
  }
  
  /// 간단한 문자열 유사도 계산 (공통 문자 비율)
  double _calculateSimilarity(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return 0.0;
    
    final shorter = text1.length <= text2.length ? text1 : text2;
    final longer = text1.length > text2.length ? text1 : text2;
    
    int matchCount = 0;
    for (int i = 0; i < shorter.length; i++) {
      if (longer.contains(shorter[i])) {
        matchCount++;
      }
    }
    
    return matchCount / shorter.length;
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
  Stream<StreamingReceiveResult> _createFallbackResults(
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
    
    yield StreamingReceiveResult.success(
      chunkIndex: 0,
      chunkUnits: pageResults.values.expand((units) => units).toList(),
      pageResults: pageResults,
      isComplete: true,
      processedChunks: 1,
    );
  }
}

/// 페이지 기준점 (첫 번째/마지막 세그먼트)
class PageMarker {
  final String pageId;
  final String firstSegment;
  final String lastSegment;
  final int totalSegments;

  PageMarker({
    required this.pageId,
    required this.firstSegment,
    required this.lastSegment,
    required this.totalSegments,
  });
}

/// 스트리밍 수신 결과
class StreamingReceiveResult {
  final bool isSuccess;
  final int chunkIndex;
  final List<TextUnit> chunkUnits;
  final Map<String, List<TextUnit>> pageResults;
  final bool isComplete;
  final int processedChunks;
  final String? error;

  StreamingReceiveResult._({
    required this.isSuccess,
    required this.chunkIndex,
    required this.chunkUnits,
    required this.pageResults,
    required this.isComplete,
    required this.processedChunks,
    this.error,
  });

  factory StreamingReceiveResult.success({
    required int chunkIndex,
    required List<TextUnit> chunkUnits,
    required Map<String, List<TextUnit>> pageResults,
    required bool isComplete,
    required int processedChunks,
  }) {
    return StreamingReceiveResult._(
      isSuccess: true,
      chunkIndex: chunkIndex,
      chunkUnits: chunkUnits,
      pageResults: pageResults,
      isComplete: isComplete,
      processedChunks: processedChunks,
    );
  }

  factory StreamingReceiveResult.error({
    required int chunkIndex,
    required String error,
  }) {
    return StreamingReceiveResult._(
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