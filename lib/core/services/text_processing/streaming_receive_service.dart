import 'dart:async';
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
      // 다중 페이지: 간단한 분배 (텍스트 비교 없이)
      // TODO: 다중 페이지 처리 로직 개선 필요
      // 현재는 첫 번째 페이지에 모든 결과 누적
      final primaryPageId = pages.first.pageId;
      pageResults.putIfAbsent(primaryPageId, () => []);
      pageResults[primaryPageId]!.addAll(chunkUnits);
      
      if (kDebugMode) {
        debugPrint('⚠️ 다중 페이지 임시 처리: ${primaryPageId}에 ${chunkUnits.length}개 유닛 추가');
        debugPrint('   TODO: 다중 페이지 순차 분배 로직 구현 필요');
      }
    }
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